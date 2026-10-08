// fpGUI HarmonyOS 统一桥 — arkTS_Invoke（Pascal → ArkTS 反向调用）
// ================================================================
// 职责：
//   1. ArkTS 方法注册表（按名 / 命名空间递归 / 统一分发器）
//   2. 全局 TSFN（Init 创建一次，资源名 "arkTS_Invoke"）：任意线程投递 → JS 线程执行
//   3. C 导出 ohos_arkts_invoke：Pascal 经 v13 槽位调用（JS 线程重入时内联直执行）
//   4. 结果回传 g_pascal.arkts_invoke_result（JS 线程，快路径约定：拷贝+锁+SetEvent）
//
// 线程铁律：
//   - napi_env / napi_ref / napi_value 仅 JS 线程使用。
//     g_reg.methods 与 g_reg.dispatcher 只在 JS 线程读写 → 无锁。
//   - g_reg.names 受 g_reg.mtx 保护（注册在 JS 线程写、ohos_arkts_invoke 任意线程读）。
//   - 投递侧只 new InvokePayload，绝不在非 JS 线程触碰任何 NAPI 句柄。

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cctype>      // tolower（部分 NDK 工具链不保证经 <cstring> 间接可见）
#include <string>
#include <vector>      // 原型链收集
#include <map>
#include <set>
#include <mutex>
#include <atomic>
#include <pthread.h>

#include "hilog/log.h"
#include "napi/native_api.h"
#include "fp_bridge_internal.h"

// ── 全局状态（NAPI 侧拥有） ────────────────────────────────
napi_threadsafe_function g_invokeTsfn = nullptr;
static napi_env   g_jsEnv = nullptr;        // 仅 JS 线程解引用（内联快路径）
static pthread_t  g_jsThreadId{};
static std::atomic<bool> g_jsThreadKnown{false};   // store-release / load-acquire

static const int    INVOKE_MAX_DEPTH  = 8;
static const int    INVOKE_MAX_METHODS = 512;
static const size_t INVOKE_MAX_NAME   = 128;

struct InvokeMethod {
    std::string display;   // 原始大小写（listInvokeMethods 返回用）
    napi_ref    ref;       // 引用计数 1，防 GC
};

struct InvokeRegistry {
    std::map<std::string, InvokeMethod> methods;  // 仅 JS 线程
    napi_ref dispatcher = nullptr;                // 仅 JS 线程
    std::set<std::string> names;                  // 小写 key，锁保护
    std::mutex mtx;
    std::atomic<bool> hasDispatcher{false};       // 供任意线程读
};

static InvokeRegistry g_reg;

struct InvokePayload {
    std::string callId;
    std::string method;     // 已小写归一
    std::string display;    // 原始大小写（dispatcher 第 1 参）
    std::string params;     // 已保证非空（"{}" 兜底）
};

// ── 小工具 ─────────────────────────────────────────────────
static std::string NormalizeName(const char* s) {
    std::string r = s ? s : "";
    for (auto& c : r) c = (char)tolower((unsigned char)c);
    return r;
}

static std::string JsonEscape(const std::string& s) {
    std::string r;
    for (char c : s) {
        switch (c) {
            case '"':  r += "\\\""; break;
            case '\\': r += "\\\\"; break;
            case '\n': r += "\\n";  break;
            case '\r': r += "\\r";  break;
            case '\t': r += "\\t";  break;
            default:
                if ((unsigned char)c < 0x20) {
                    char buf[8];
                    snprintf(buf, sizeof(buf), "\\u%04x", (unsigned char)c);
                    r += buf;
                } else r += c;
        }
    }
    return r;
}

static std::string ErrorEnvelope(const char* code, const std::string& msg) {
    return std::string("{\"ok\":false,\"code\":\"") + code +
           "\",\"error\":\"" + JsonEscape(msg) + "\"}";
}

// ── JS 线程：执行一次调用（注册表查找 → 调用 → 结果转换） ──
static bool JsonStringify(napi_env env, napi_value v, std::string& out) {
    napi_value global, json, stringify, arg, res;
    if (napi_get_global(env, &global) != napi_ok) return false;
    if (napi_get_named_property(env, global, "JSON", &json) != napi_ok) return false;
    if (napi_get_named_property(env, json, "stringify", &stringify) != napi_ok) return false;
    arg = v;
    if (napi_call_function(env, json, stringify, 1, &arg, &res) != napi_ok) return false;
    napi_valuetype t;
    napi_typeof(env, res, &t);
    if (t != napi_string) return false;            // undefined = 循环引用
    size_t len = 0;
    napi_get_value_string_utf8(env, res, nullptr, 0, &len);
    out.resize(len);
    if (len) napi_get_value_string_utf8(env, res, &out[0], len + 1, &len);
    out.resize(len);
    return true;
}

static void CopyNapiString(napi_env env, napi_value v, std::string& out) {
    size_t len = 0;
    napi_get_value_string_utf8(env, v, nullptr, 0, &len);
    out.resize(len);
    if (len) napi_get_value_string_utf8(env, v, &out[0], len + 1, &len);
    out.resize(len);
}

static void DescribeException(napi_env env, napi_value exc, std::string& msg) {
    napi_valuetype t;
    napi_typeof(env, exc, &t);
    if (t == napi_string) { CopyNapiString(env, exc, msg); return; }
    if (t == napi_object) {
        napi_value prop;
        if (napi_get_named_property(env, exc, "message", &prop) == napi_ok) {
            napi_valuetype pt; napi_typeof(env, prop, &pt);
            if (pt == napi_string) { CopyNapiString(env, prop, msg); return; }
        }
        if (napi_get_named_property(env, exc, "stack", &prop) == napi_ok) {
            napi_valuetype pt; napi_typeof(env, prop, &pt);
            if (pt == napi_string) { CopyNapiString(env, prop, msg); return; }
        }
    }
    msg = "unknown JS exception";
}

// 内置元方法（Pascal 侧可直调，无需 ArkTS 注册）：__ping / __list
static bool ExecuteBuiltin(napi_env env, const InvokePayload& p, std::string& out) {
    if (p.method == "__ping") {
        out = "{\"ok\":true,\"pong\":true}";
        return true;
    }
    if (p.method == "__list") {
        std::string items;
        for (auto& kv : g_reg.methods) {           // JS 线程直接遍历，无需锁
            if (!items.empty()) items += ",";
            items += "\"" + JsonEscape(kv.second.display) + "\"";
        }
        out = "{\"ok\":true,\"methods\":[" + items + "]}";
        return true;
    }
    return false;
}

static void ExecuteInvoke(napi_env env, const InvokePayload& p,
                          std::string& out, bool& failed) {
    failed = false;
    if (env == nullptr) {                          // TSFN 关闭期兜底
        out = ErrorEnvelope("NOT_CONNECTED", "js env unavailable");
        failed = true;
        return;
    }
    if (ExecuteBuiltin(env, p, out)) return;

    napi_value fn = nullptr;
    bool isDispatcher = false;
    auto it = g_reg.methods.find(p.method);
    if (it != g_reg.methods.end()) {
        if (napi_get_reference_value(env, it->second.ref, &fn) != napi_ok) fn = nullptr;
    } else if (g_reg.hasDispatcher.load()) {
        if (g_reg.dispatcher != nullptr &&
            napi_get_reference_value(env, g_reg.dispatcher, &fn) == napi_ok)
            isDispatcher = true;
        else fn = nullptr;
    }
    if (fn == nullptr) {
        out = ErrorEnvelope("NO_METHOD", "no such method: " + p.display);
        failed = true;
        return;
    }

    // 组参：普通方法 1 参 (params)；dispatcher 2 参 (method, params)
    napi_value args[2];
    uint32_t argc = 1;
    if (isDispatcher) {
        napi_create_string_utf8(env, p.display.c_str(), NAPI_AUTO_LENGTH, &args[0]);
        napi_create_string_utf8(env, p.params.c_str(),  NAPI_AUTO_LENGTH, &args[1]);
        argc = 2;
    } else {
        napi_create_string_utf8(env, p.params.c_str(), NAPI_AUTO_LENGTH, &args[0]);
    }

    napi_value result = nullptr;
    napi_status st = napi_call_function(env, nullptr, fn, argc, args, &result);
    // 注：普通方法经 registerInvokeNamespace 注册时 this 已 bind，thisArg 传 nullptr 无害；
    //     registerInvokeMethod 要求调用方自行 bind（见 Index.d.ts 契约）。
    if (st == napi_pending_exception) {
        napi_value exc;
        napi_get_and_clear_last_exception(env, &exc);   // 必须清掉，否则污染后续 NAPI 调用
        std::string msg;
        DescribeException(env, exc, msg);
        out = ErrorEnvelope("JS_EXCEPTION", msg);
        failed = true;
        return;
    }
    if (st != napi_ok || result == nullptr) {
        out = ErrorEnvelope("CALL_FAIL",
            "napi_call_function status=" + std::to_string((int)st));
        failed = true;
        return;
    }

    napi_valuetype t;
    napi_typeof(env, result, &t);
    if (t == napi_undefined || t == napi_null) {
        out = "{\"ok\":true}";                      // 方法无返回值 → 默认成功信封
    } else if (t == napi_string) {
        CopyNapiString(env, result, out);
    } else if (!JsonStringify(env, result, out)) {
        napi_value s;
        if (napi_coerce_to_string(env, result, &s) == napi_ok)
            CopyNapiString(env, s, out);
        else
            out = "{\"ok\":true}";
    }
}

// ── 结果回传（JS 线程） ────────────────────────────────────
static void DeliverResult(const std::string& callId,
                          const std::string& out, bool failed) {
    auto fn = (ArkTsInvokeResultFn)g_pascal.arkts_invoke_result;
    if (fn == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
            "arkTS_Invoke: result dropped, pascal callback not registered, "
            "callId=%{public}s", callId.c_str());
        return;
    }
    fn(callId.c_str(), out.c_str(), failed ? 1 : 0);
}

// ── TSFN call_js_cb（JS 线程执行） ─────────────────────────
static void ArkInvokeCallJS(napi_env env, napi_value jsCb,
                            void* context, void* data) {
    auto* p = static_cast<InvokePayload*>(data);
    if (p == nullptr) return;
    std::string callId = p->callId;      // 先拷出，delete 后不可再取
    std::string out;
    bool failed = false;
    ExecuteInvoke(env, *p, out, failed);
    delete p;
    DeliverResult(callId, out, failed);
}

// ── NAPI：方法注册 ─────────────────────────────────────────
// 仅 JS 线程执行 → methods/dispatcher 无锁写入
static void StoreMethod(napi_env env, const std::string& display, napi_value fn) {
    std::string key = NormalizeName(display.c_str());
    if (key.empty() || key.size() > INVOKE_MAX_NAME) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
            "registerInvoke: bad name '%{public}s'", display.c_str());
        return;
    }
    napi_ref ref;
    if (napi_create_reference(env, fn, 1, &ref) != napi_ok) return;

    auto it = g_reg.methods.find(key);
    if (it != g_reg.methods.end()) {
        napi_delete_reference(env, it->second.ref);   // 覆盖旧注册
        it->second.ref = ref;
        it->second.display = display;
        return;
    }
    if ((int)g_reg.methods.size() >= INVOKE_MAX_METHODS) {
        napi_delete_reference(env, ref);
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
            "registerInvoke: method cap %d reached", INVOKE_MAX_METHODS);
        return;
    }
    g_reg.methods[key] = InvokeMethod{display, ref};
    std::lock_guard<std::mutex> lk(g_reg.mtx);
    g_reg.names.insert(key);
}

// 取 Object.prototype 作为原型链终止判据（拿不到则退化为跳数上限截断）
static bool GetObjectPrototype(napi_env env, napi_value& out) {
    napi_value global, ctor, proto;
    napi_valuetype t = napi_undefined;
    if (napi_get_global(env, &global) != napi_ok) return false;
    if (napi_get_named_property(env, global, "Object", &ctor) != napi_ok) return false;
    if (napi_get_named_property(env, ctor, "prototype", &proto) != napi_ok) return false;
    napi_typeof(env, proto, &t);
    if (t != napi_object) return false;
    out = proto;
    return true;
}

// 命名空间注册：沿原型链逐层取"自有属性"。
//   - 必须用 napi_get_all_property_names(own_only, all_properties)：
//     napi_get_property_names 只返回可枚举自有属性——class 方法挂在原型上且
//     非枚举，传 class 实例会得到空表（对象字面量才有可枚举自有属性）。
//   - 自顶向下注册（基类/原型先、实例自身后）→ 派生层天然覆盖基类层。
//   - Object.prototype 不入链（否则 constructor/toString 等被外露）。
//   - 深度 + 方法数上限终止（a.self = a 在深度 8 截断），不依赖指针去重。
static void RegisterFromObject(napi_env env, napi_value obj,
                               const std::string& prefix, int depth) {
    if (depth > INVOKE_MAX_DEPTH) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
            "registerInvokeNamespace: depth cap %d at '%{public}s'",
            INVOKE_MAX_DEPTH, prefix.c_str());
        return;
    }

    // ① 收集原型链 [自身, proto, proto², ...]（不含 Object.prototype）
    std::vector<napi_value> chain;
    napi_value objectProto = nullptr;
    const bool haveRoot = GetObjectPrototype(env, objectProto);
    napi_value cur = obj;
    for (int hop = 0; hop < INVOKE_MAX_DEPTH + 4 && cur != nullptr; hop++) {
        napi_valuetype ct = napi_undefined;
        napi_typeof(env, cur, &ct);
        if (ct != napi_object && ct != napi_function) break;
        if (haveRoot) {
            bool isRoot = false;
            if (napi_strict_equals(env, cur, objectProto, &isRoot) == napi_ok && isRoot)
                break;
        }
        chain.push_back(cur);
        napi_value proto = nullptr;
        if (napi_get_prototype(env, cur, &proto) != napi_ok) break;
        napi_valuetype pt = napi_undefined;
        if (proto != nullptr) napi_typeof(env, proto, &pt);
        if (pt != napi_object) break;              // null/原始原型到顶
        cur = proto;
    }

    // ② 自顶向下逐层注册
    for (int li = (int)chain.size() - 1; li >= 0; li--) {
        napi_value level = chain[(size_t)li];
        napi_value propNames;
        if (napi_get_all_property_names(env, level, napi_key_own_only,
                (napi_key_filter)(napi_key_all_properties | napi_key_skip_symbols),
                napi_key_keep_numbers, &propNames) != napi_ok) continue;
        uint32_t len = 0;
        napi_get_array_length(env, propNames, &len);
        for (uint32_t i = 0; i < len; i++) {
            if ((int)g_reg.methods.size() >= INVOKE_MAX_METHODS) return;
            napi_value key, val;
            if (napi_get_element(env, propNames, i, &key) != napi_ok) continue;
            std::string k;
            CopyNapiString(env, key, k);
            if (k.empty() || k[0] == '_') continue;       // 跳过 _ 前缀
            if (k == "constructor") continue;             // 类构造器不外露
            if (napi_get_property(env, level, key, &val) != napi_ok) {
                bool pending = false;   // getter 抛错等：清掉挂起异常，勿污染后续 NAPI 调用
                if (napi_is_exception_pending(env, &pending) == napi_ok && pending) {
                    napi_value dummy;
                    napi_get_and_clear_last_exception(env, &dummy);
                }
                continue;
            }
            napi_valuetype t;
            napi_typeof(env, val, &t);
            std::string full = prefix.empty() ? k : (prefix + "." + k);
            if (t == napi_function) {
                napi_value bindFn, bound;
                bool boundOk = false;
                if (napi_get_named_property(env, val, "bind", &bindFn) == napi_ok) {
                    napi_value thisArg = obj;   // bind 到注册时的根对象（实例），非原型
                    boundOk = (napi_call_function(env, val, bindFn, 1, &thisArg, &bound) == napi_ok);
                }
                StoreMethod(env, full, boundOk ? bound : val);  // 无 bind（Proxy 等）→ 存原函数
            } else if (t == napi_object) {
                RegisterFromObject(env, val, full, depth + 1);
            }
        }
    }
}

static napi_value ReturnUndefined(napi_env env) {
    napi_value u; napi_get_undefined(env, &u); return u;
}

napi_value ArkInvoke_RegisterMethod(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) return ReturnUndefined(env);
    napi_valuetype t0, t1;
    napi_typeof(env, args[0], &t0);
    napi_typeof(env, args[1], &t1);
    if (t0 != napi_string || t1 != napi_function) return ReturnUndefined(env);
    std::string name;
    CopyNapiString(env, args[0], name);
    StoreMethod(env, name, args[1]);
    return ReturnUndefined(env);
}

napi_value ArkInvoke_RegisterNamespace(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) return ReturnUndefined(env);
    napi_valuetype t0, t1;
    napi_typeof(env, args[0], &t0);
    napi_typeof(env, args[1], &t1);
    if (t0 != napi_string) return ReturnUndefined(env);
    std::string prefix;
    CopyNapiString(env, args[0], prefix);
    if (t1 == napi_function) {              // 便捷：传函数等价 registerInvokeMethod
        StoreMethod(env, prefix, args[1]);
    } else if (t1 == napi_object) {
        RegisterFromObject(env, args[1], prefix, 0);
    }
    return ReturnUndefined(env);
}

napi_value ArkInvoke_RegisterDispatcher(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) return ReturnUndefined(env);
    napi_valuetype t;
    napi_typeof(env, args[0], &t);
    if (t != napi_function) return ReturnUndefined(env);
    napi_ref ref;
    if (napi_create_reference(env, args[0], 1, &ref) != napi_ok) return ReturnUndefined(env);
    if (g_reg.dispatcher != nullptr) napi_delete_reference(env, g_reg.dispatcher);
    g_reg.dispatcher = ref;
    g_reg.hasDispatcher.store(true);
    return ReturnUndefined(env);
}

napi_value ArkInvoke_UnregisterMethod(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) return ReturnUndefined(env);
    std::string name;
    CopyNapiString(env, args[0], name);
    std::string key = NormalizeName(name.c_str());
    auto it = g_reg.methods.find(key);
    if (it != g_reg.methods.end()) {
        napi_delete_reference(env, it->second.ref);
        g_reg.methods.erase(it);
        std::lock_guard<std::mutex> lk(g_reg.mtx);
        g_reg.names.erase(key);
    }
    return ReturnUndefined(env);
}

napi_value ArkInvoke_ClearMethods(napi_env env, napi_callback_info info) {
    for (auto& kv : g_reg.methods) napi_delete_reference(env, kv.second.ref);
    g_reg.methods.clear();
    if (g_reg.dispatcher != nullptr) {
        napi_delete_reference(env, g_reg.dispatcher);
        g_reg.dispatcher = nullptr;
    }
    g_reg.hasDispatcher.store(false);
    std::lock_guard<std::mutex> lk(g_reg.mtx);
    g_reg.names.clear();
    return ReturnUndefined(env);
}

napi_value ArkInvoke_ListMethods(napi_env env, napi_callback_info info) {
    napi_value arr;
    napi_create_array_with_length(env, g_reg.methods.size(), &arr);
    uint32_t idx = 0;
    for (auto& kv : g_reg.methods) {
        napi_value s;
        napi_create_string_utf8(env, kv.second.display.c_str(), NAPI_AUTO_LENGTH, &s);
        napi_set_element(env, arr, idx++, s);
    }
    return arr;
}

// JS 线程直查注册表同步执行（跨进程 relay / 自测用；永不抛异常）
napi_value ArkInvoke_InvokeLocal(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    InvokePayload p;
    p.callId = "local";
    if (argc >= 1 && args[0] != nullptr) {
        std::string m; CopyNapiString(env, args[0], m);
        p.display = m;
        p.method  = NormalizeName(m.c_str());
    }
    p.params = "{}";
    if (argc >= 2 && args[1] != nullptr) {
        std::string s; CopyNapiString(env, args[1], s);
        if (!s.empty()) p.params = s;
    }
    if (p.method.empty()) {
        p.method = "__invalid__";
        p.display = "";
    }
    std::string out;
    bool failed = false;
    ExecuteInvoke(env, p, out, failed);
    napi_value v;
    napi_create_string_utf8(env, out.c_str(), NAPI_AUTO_LENGTH, &v);
    return v;
}

// ── 模块入口（napi_init.cpp 的 Init 调用；必须在 JS 线程） ──
void ArkInvokeInit(napi_env env) {
    g_jsEnv = env;
    g_jsThreadId = pthread_self();
    g_jsThreadKnown.store(true);              // release：id/env 写入先行可见

    napi_value resourceName;
    napi_create_string_utf8(env, "arkTS_Invoke", NAPI_AUTO_LENGTH, &resourceName);
    // 与 g_dispatchTsfn 同款：js_cb=nullptr，靠 call_js_cb + payload 路由
    napi_status st = napi_create_threadsafe_function(env, nullptr, nullptr, resourceName,
        0 /*无上限*/, 1, nullptr, nullptr, nullptr, ArkInvokeCallJS, &g_invokeTsfn);
    if (st != napi_ok) {
        g_invokeTsfn = nullptr;               // 创建失败：仅投递路径不可用，内联路径不受影响
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI",
            "arkTS_Invoke TSFN create failed st=%{public}d (inline path still usable)", (int)st);
        return;
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "arkTS_Invoke TSFN created: %p", (void*)g_invokeTsfn);
}

// ── C 导出：Pascal 调用入口（任意线程） ────────────────────
__attribute__((visibility("default")))
int32_t ohos_arkts_invoke(const char* callId, const char* method,
                          const char* params) {
    if (callId == nullptr || callId[0] == '\0' ||
        method == nullptr || method[0] == '\0')
        return -1;                                            // BAD_ARGS
    if (strlen(method) > INVOKE_MAX_NAME) return -1;

    // 就绪检查分两层：内联快路径只依赖 g_jsEnv，不依赖 TSFN；
    // 只有"投递路径"才要求 TSFN 可用，避免 TSFN 创建失败连带拒绝重入调用。
    if (!g_jsThreadKnown.load() || g_jsEnv == nullptr)        // acquire
        return -2;                                            // NOT_INITIALIZED：ArkInvokeInit 未执行
    const bool inlinePath = (pthread_equal(pthread_self(), g_jsThreadId) != 0);
    if (!inlinePath && g_invokeTsfn == nullptr)
        return -2;                                            // 非 JS 线程投递需要 TSFN

    std::string display(method);
    std::string key = NormalizeName(method);
    if (key != "__ping" && key != "__list") {                 // 内置方法免注册
        std::lock_guard<std::mutex> lk(g_reg.mtx);
        if (g_reg.names.find(key) == g_reg.names.end() &&
            !g_reg.hasDispatcher.load())
            return -3;                                        // NO_METHOD
    }

    auto* payload = new InvokePayload{callId, key, display,
                                      (params && params[0]) ? params : "{}"};

    // 内联快路径：调用方就在 JS 线程（can_close / drop / 结果回调等重入上下文）
    if (inlinePath) {
        napi_handle_scope scope = nullptr;
        napi_open_handle_scope(g_jsEnv, &scope);
        std::string out;
        bool failed = false;
        ExecuteInvoke(g_jsEnv, *payload, out, failed);
        if (scope != nullptr) napi_close_handle_scope(g_jsEnv, scope);
        std::string callIdCopy = payload->callId;
        delete payload;
        OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
            "arkTS_Invoke inline: method=%{public}s callId=%{public}s",
            display.c_str(), callIdCopy.c_str());
        DeliverResult(callIdCopy, out, failed);
        return 0;
    }

    napi_status st = napi_call_threadsafe_function(
        g_invokeTsfn, payload, napi_tsfn_blocking);            // FIFO 保序
    if (st != napi_ok) {
        delete payload;
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
            "arkTS_Invoke: tsfn post failed st=%{public}d", (int)st);
        return -4;                                             // QUEUE_FULL
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "arkTS_Invoke queued: method=%{public}s callId=%{public}s",
        display.c_str(), callId);
    return 0;
}
