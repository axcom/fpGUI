// fpGUI HarmonyOS 统一桥 libfp_bridge.so — NAPI 表面 + Pascal 加载器
// ======================================================
// 从原 napi_init.cpp 拆出的 NAPI 侧：ArkTS → C++ 的全部 NAPI 函数 +
// Pascal .so 加载线程 + NAPI 模块注册。
// 桥核心（ohos_* 导出 + fp_bridge_init）在 fp_bridge.cpp；
// 共享契约见 fp_bridge_internal.h。

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <pthread.h>
#include <unistd.h>
#include <sys/stat.h>
#include <atomic>
#include <map>
#include <mutex>
#include <condition_variable>
#include <thread>
#include <chrono>
#include <string>
#include <algorithm>
#include <vector>
#include <iostream>

#include <native_window/external_window.h>
#include <window_manager/oh_display_manager.h>
#include "hilog/log.h"
#include "napi/native_api.h"
#include "fp_bridge_internal.h"

// ── NAPI 侧拥有的全局状态 ────────────────────────────────
std::atomic<bool> g_started{false};   // start() 单实例守卫
std::atomic<bool> g_etsReady{false};
float g_density = 1.0f;
float g_zoomScale = 1.0f;
napi_threadsafe_function g_tsfn = nullptr;

// ── 沙箱目录路径（ArkTS context 属性传入）──
std::string g_sandboxFilesDir;          // /data/storage/el2/base/files
std::string g_sandboxCacheDir;          // /data/storage/el2/base/cache
std::string g_sandboxTempDir;            // /data/storage/el2/base/temp
std::string g_sandboxResourceDir;        // /data/storage/el2/base/haps/entry/resources
std::string g_sandboxDatabaseDir;        // /data/storage/el2/database
std::string g_sandboxPreferencesDir;     // /data/storage/el2/base/preferences
std::string g_sandboxBundleCodeDir;      // /data/storage/el2/bundle
std::string g_sandboxDistributedFilesDir;// /data/storage/el2/distributedfiles
std::string g_sandboxCloudFileDir;       // /data/storage/el2/cloud

// ── Pascal 库句柄（供 binder_bridge.cpp 复用）──
void* g_pascalLibHandle = nullptr;

// ── 动态分发：Promise 结果 TSFN（Init 创建；桥 ohos_dispatch_result 消费）──
napi_threadsafe_function g_dispatchTsfn = nullptr;

// ── 打开 URL / 文档：ArkTS 回调 TSFN（RegisterOpenUrl 创建；桥 ohos_open_url 消费）──
napi_threadsafe_function g_open_url_tsfn = nullptr;
std::mutex g_open_url_mtx;

// ── 动态分发：pending 表 + 守护线程（NAPI 侧局部）──
struct PendingDispatch {
    napi_deferred deferred;
    int64_t createdMs;
    bool timedOut;
};
static std::map<std::string, PendingDispatch*> g_dispatchPending;
static std::mutex g_dispatchMutex;

// 分发 Promise 兜底超时（守护线程；Pascal 侧已有时超时，这里防桥/Pascal 异常）。
// 设为 0 表示禁用超时处理（守护线程仍运行但不做过期回收）。
static const int64_t DISPATCH_PENDING_TIMEOUT_MS = 35000;
static std::atomic<bool> g_dispatchJanitorStop{false};
static std::atomic<bool> g_dispatchJanitorStarted{false};
static std::thread g_dispatchJanitor;

// ── 系统 Configuration 暂存（连接前推送兜底）──
static std::string g_pendingConfig;
static std::mutex g_cfgMutex;

// ═══════════════════════════════════════════════════════════════
//  动态分发（Registry-Dispatch）— Pascal 处理、C++ Promise 桥
// ═══════════════════════════════════════════════════════════════

// 提取 JSON 中 "key":"value" 的 value（轻量；仅解析 Pascal 起步响应的 jobId）
static std::string JsonStringField(const std::string& s, const char* key) {
    std::string pat = std::string("\"") + key + "\":\"";
    size_t pos = s.find(pat);
    if (pos == std::string::npos) return "";
    pos += pat.size();
    size_t end = s.find('"', pos);
    if (end == std::string::npos) return "";
    return s.substr(pos, end - pos);
}

// 在 JS 线程执行：按 jobId 找回 Promise 并 resolve/reject
static void DispatchResultCallJS(napi_env env, napi_value jsCb, void* context, void* data) {
    auto* d = static_cast<DispatchResultData*>(data);
    if (d == nullptr) return;
    PendingDispatch* pending = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_dispatchMutex);
        auto it = g_dispatchPending.find(d->jobId);
        if (it != g_dispatchPending.end()) {
            pending = it->second;
            g_dispatchPending.erase(it);
        }
    }
    if (pending != nullptr) {
        napi_value v;
        napi_create_string_utf8(env, d->result.c_str(), NAPI_AUTO_LENGTH, &v);
        // 约定：dispatch 结果（含失败信封 {"ok":false,"code":...}）一律 resolve，
        // 调用方 JSON.parse 判断 ok；reject 仅用于入参/连接类错误。
        napi_resolve_deferred(env, pending->deferred, v);
        delete pending;
    }
    delete d;
}

// 守护：定期扫描 pending，超时经 TSFN 在 JS 线程 reject（防 Pascal/桥异常导致 Promise 永不 settle）
static void DispatchPendingJanitor() {
    while (!g_dispatchJanitorStop.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1000));
        int64_t now = (int64_t)std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now().time_since_epoch()).count();
        std::vector<std::string> expired;
        {
            std::lock_guard<std::mutex> lock(g_dispatchMutex);
            for (auto& kv : g_dispatchPending) {
                if (DISPATCH_PENDING_TIMEOUT_MS > 0 && !kv.second->timedOut &&
                    (now - kv.second->createdMs) > DISPATCH_PENDING_TIMEOUT_MS) {
                    kv.second->timedOut = true;
                    expired.push_back(kv.first);
                }
            }
        }
        for (auto& id : expired) {
            OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
                "dispatch pending timeout: job=%{public}s", id.c_str());
            ohos_dispatch_result(id.c_str(),
                "{\"ok\":false,\"code\":\"TIMEOUT\",\"error\":\"dispatch timeout\"}", 1);
        }
    }
}

// NAPI: dispatch(op, params) → Promise<string>
static napi_value Dispatch(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value promise;
    napi_deferred deferred;
    napi_create_promise(env, &deferred, &promise);

    auto rejectText = [&](const char* text) -> napi_value {
        napi_value v;
        napi_create_string_utf8(env, text, NAPI_AUTO_LENGTH, &v);
        napi_reject_deferred(env, deferred, v);
        return promise;
    };

    if (argc < 1 || args[0] == nullptr) {
        return rejectText("{\"ok\":false,\"code\":\"BAD_ARGS\",\"error\":\"op required\"}");
    }

    napi_valuetype t = napi_undefined;
    napi_typeof(env, args[0], &t);
    if (t != napi_string) {
        return rejectText("{\"ok\":false,\"code\":\"BAD_ARGS\",\"error\":\"op must be string\"}");
    }

    char op[256] = {0};
    size_t opLen = 0;
    napi_get_value_string_utf8(env, args[0], op, sizeof(op), &opLen);
    if (opLen >= sizeof(op) - 1) {
        return rejectText("{\"ok\":false,\"code\":\"BAD_ARGS\",\"error\":\"op too long\"}");
    }

    std::string params = "{}";
    if (argc > 1 && args[1] != nullptr) {
        napi_typeof(env, args[1], &t);
        if (t != napi_string) {
            return rejectText("{\"ok\":false,\"code\":\"BAD_ARGS\",\"error\":\"params must be string\"}");
        }
        size_t len = 0;
        napi_get_value_string_utf8(env, args[1], nullptr, 0, &len);
        params.resize(len + 1);
        if (len > 0) {
            napi_get_value_string_utf8(env, args[1], &params[0], len + 1, &len);
        }
        params.resize(len);
    }

    if (g_dispatch == nullptr) {
        return rejectText("{\"ok\":false,\"code\":\"NOT_CONNECTED\",\"error\":\"dispatch not connected\"}");
    }

    char* resp = g_dispatch(op, params.c_str());
    std::string s = (resp != nullptr) ? resp : "";
    if (resp != nullptr && g_dispatch_free != nullptr) {
        g_dispatch_free(resp);   // Pascal 侧释放（v7）
    }

    std::string jobId = JsonStringField(s, "jobId");
    if (jobId.empty()) {
        // 未受理（错误信封）：直接 resolve，调用方解析 ok:false
        napi_value v;
        napi_create_string_utf8(env, s.c_str(), NAPI_AUTO_LENGTH, &v);
        napi_resolve_deferred(env, deferred, v);
        return promise;
    }

    {
        auto* pd = new PendingDispatch{deferred,
            (int64_t)(std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now().time_since_epoch()).count()),
            false};
        std::lock_guard<std::mutex> lock(g_dispatchMutex);
        g_dispatchPending[jobId] = pd;
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "dispatch: op=%{public}s job=%{public}s", op, jobId.c_str());
    return promise;
}

// NAPI: dispatchCancel(jobId)
static napi_value DispatchCancel(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char jobId[128] = {0};
    if (argc > 0 && args[0] != nullptr) {
        size_t len = 0;
        napi_get_value_string_utf8(env, args[0], jobId, sizeof(jobId), &len);
    }

    if (g_dispatch != nullptr && jobId[0] != '\0') {
        char cparams[192];
        snprintf(cparams, sizeof(cparams), "{\"jobId\":\"%s\"}", jobId);
        char* r = g_dispatch("__cancel", cparams);
        if (r != nullptr && g_dispatch_free != nullptr) {
            g_dispatch_free(r);
        }
    }

    PendingDispatch* pending = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_dispatchMutex);
        auto it = g_dispatchPending.find(jobId);
        if (it != g_dispatchPending.end()) {
            pending = it->second;
            g_dispatchPending.erase(it);
        }
    }
    if (pending != nullptr) {
        napi_value v;
        napi_create_string_utf8(env,
            "{\"ok\":false,\"code\":\"CANCELLED\",\"error\":\"cancelled by user\"}",
            NAPI_AUTO_LENGTH, &v);
        napi_resolve_deferred(env, pending->deferred, v);
        delete pending;
    }

    napi_value u;
    napi_get_undefined(env, &u);
    return u;
}

// ═══════════════════════════════════════════════════════════════
//  NAPI 函数 — 由 ETS (ArkTS) 调用
// ═══════════════════════════════════════════════════════════════

static napi_value SetEtsReady(napi_env env, napi_callback_info info) {
    g_etsReady = true;
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI", "ETS ready signal received");
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

static napi_value SetNativeCallback(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string cbType = "window";
    if (argc > 1 && args[1] != nullptr) {
        char buf[32] = {0};
        size_t len = 0;
        if (napi_get_value_string_utf8(env, args[1], buf, sizeof(buf), &len) == napi_ok) {
            cbType = buf;
        }
    }

    napi_value resource_name;
    napi_create_string_utf8(env, "fpGUI_NativeCallback", NAPI_AUTO_LENGTH, &resource_name);

    napi_threadsafe_function tsfn = nullptr;
    napi_create_threadsafe_function(
        env, args[0], nullptr, resource_name,
        0,
        1,
        nullptr, nullptr,
        nullptr,
        NativeCallbackCallJS,
        &tsfn);

    if (cbType == "keyboard") {
        std::lock_guard<std::mutex> lock(g_kbMutex);
        g_kbTsfnStack.push_back(tsfn);
        OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
            "Keyboard callback registered, stack=%{public}d", (int)g_kbTsfnStack.size());
    } else {
        if (g_tsfn) {
            napi_release_threadsafe_function(g_tsfn, napi_tsfn_release);
            g_tsfn = nullptr;
        }
        g_tsfn = tsfn;
        OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
            "Window callback registered, g_tsfn=%p", g_tsfn);
    }

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

static napi_value ReleaseKeyboardCallback(napi_env env, napi_callback_info info) {
    std::lock_guard<std::mutex> lock(g_kbMutex);
    if (!g_kbTsfnStack.empty()) {
        napi_release_threadsafe_function(g_kbTsfnStack.back(), napi_tsfn_release);
        g_kbTsfnStack.pop_back();
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "Keyboard callback released, stack=%{public}d", (int)g_kbTsfnStack.size());
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── 沙箱路径设置 (ETS → C++) ──────────────────────────────────
// ArkTS onWindowStageCreate 中调用，传入 context 的全部目录属性
// 必须在 start() 前调用，使 ohos_get_user_dir 能返回真实沙箱路径
static napi_value SetSandboxPaths(napi_env env, napi_callback_info info) {
    size_t argc = 9;
    napi_value args[9] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    auto getString = [&](napi_value val, std::string& out) {
        if (val == nullptr) return;
        size_t len = 0;
        napi_get_value_string_utf8(env, val, nullptr, 0, &len);
        if (len > 0) {
            out.resize(len);
            napi_get_value_string_utf8(env, val, &out[0], len + 1, &len);
            out.resize(len);
        }
    };

    getString(args[0], g_sandboxFilesDir);
    getString(args[1], g_sandboxCacheDir);
    getString(args[2], g_sandboxTempDir);
    getString(args[3], g_sandboxResourceDir);
    getString(args[4], g_sandboxDatabaseDir);
    getString(args[5], g_sandboxPreferencesDir);
    getString(args[6], g_sandboxBundleCodeDir);
    getString(args[7], g_sandboxDistributedFilesDir);
    getString(args[8], g_sandboxCloudFileDir);

    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "setSandboxPaths: files=%{public}s cache=%{public}s temp=%{public}s "
        "resource=%{public}s database=%{public}s preferences=%{public}s "
        "bundleCode=%{public}s distributed=%{public}s cloud=%{public}s",
        g_sandboxFilesDir.c_str(), g_sandboxCacheDir.c_str(), g_sandboxTempDir.c_str(),
        g_sandboxResourceDir.c_str(), g_sandboxDatabaseDir.c_str(), g_sandboxPreferencesDir.c_str(),
        g_sandboxBundleCodeDir.c_str(), g_sandboxDistributedFilesDir.c_str(), g_sandboxCloudFileDir.c_str());

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── XComponent Surface 就绪回调 ──────────────────────────
static napi_value OnSurfaceReady(napi_env env, napi_callback_info info) {
    size_t argc = 5;
    napi_value args[5] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t reqId = 0;
    napi_get_value_int32(env, args[0], &reqId);

    char xcId[64] = {0};
    size_t xcLen = 0;
    napi_get_value_string_utf8(env, args[1], xcId, sizeof(xcId), &xcLen);

    char sid[128] = {0};
    if (argc >= 3) {
        size_t sidLen = 0;
        napi_get_value_string_utf8(env, args[2], nullptr, 0, &sidLen);
        if (sidLen > 0 && sidLen < sizeof(sid)) {
            napi_get_value_string_utf8(env, args[2], sid, sizeof(sid), &sidLen);
        }
    }

    int32_t surfW = 0, surfH = 0;
    if (argc >= 5 && args[3] != nullptr && args[4] != nullptr) {
        napi_get_value_int32(env, args[3], &surfW);
        napi_get_value_int32(env, args[4], &surfH);
    }

    // 句柄已创建后的重复上报（surface 尺寸刷新）：只更新权威尺寸，不重复建窗
    {
        std::lock_guard<std::mutex> lock(g_xcMutex);
        if (g_xcReqs.find(reqId) == g_xcReqs.end()) {
            if (surfW > 0 && surfH > 0) {
                std::lock_guard<std::mutex> lk(g_resizeMutex);
                g_surfaceSize[reqId] = { surfW, surfH };
            }
            napi_value result;
            napi_get_undefined(env, &result);
            return result;
        }
    }

    // 渲染面真实尺寸优先级：ETS onLoad 上报 > 创建期暂存的 resize 反馈 >
    // 建窗请求尺寸。被系统强制最大化时请求尺寸是旧值（如 1344x831），用它
    // SET_BUFFER_GEOMETRY 会把 native buffer 池钉死在旧尺寸 → 合成器把画面
    // 放大显示（且首帧后失配帧被丢弃，画面冻结）。
    int physW = 0, physH = 0;
    if (surfW > 0 && surfH > 0) {
        physW = surfW;
        physH = surfH;
    } else {
        std::lock_guard<std::mutex> lk(g_resizeMutex);
        auto pit = g_pendingResize.find(reqId);
        if (pit != g_pendingResize.end() && pit->second.w > 0 && pit->second.h > 0) {
            physW = pit->second.w;
            physH = pit->second.h;
        }
    }
    if (physW <= 0 || physH <= 0) {
        std::lock_guard<std::mutex> lock(g_xcMutex);
        auto it = g_xcReqs.find(reqId);
        if (it != g_xcReqs.end()) {
            physW = it->second->widthPhys;
            physH = it->second->heightPhys;
        }
    }
    if (physW > 0 && physH > 0) {
        std::lock_guard<std::mutex> lk(g_resizeMutex);
        g_surfaceSize[reqId] = { physW, physH };
    }

    OHNativeWindow* nativeWin = nullptr;
    if (sid[0] != '\0') {
        uint64_t surfaceId = std::strtoull(sid, nullptr, 10);
        nativeWin = SurfaceIdToWindow(surfaceId, physW, physH);
    }
    
    {
        std::lock_guard<std::mutex> lock(g_xcMutex);
        auto it = g_xcReqs.find(reqId);
        if (it != g_xcReqs.end()) {
            if (nativeWin) {
                OH_NativeWindow_NativeWindowHandleOpt(nativeWin,
                    SET_BUFFER_GEOMETRY, physW, physH);
                it->second->nativeWin = nativeWin;
                OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
                    "OnSurfaceReady SUCCESS: req=%d win=%p sid=%s", reqId, nativeWin, sid);
            } else {
                it->second->failed = true;
                OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI",
                    "OnSurfaceReady FAILED: no native window for req=%d sid=%s", reqId, sid);
            }
            it->second->done = true;
        }
    }
    g_xcCV.notify_all();

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── 主窗口装饰尺寸 ──────────────────
static napi_value SetMainWindowDec(napi_env env, napi_callback_info info) {    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t decW = 0, decH = 0;
    napi_get_value_int32(env, args[0], &decW);
    napi_get_value_int32(env, args[1], &decH);
    g_mainDecW = decW;
    g_mainDecH = decH;
    {
        std::lock_guard<std::mutex> lock(g_decMutex);
        g_winDec[1] = {decW, decH};
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "MainWindow dec set: decW=%{public}d decH=%{public}d (vp)", decW, decH);
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

static napi_value SetWindowDec(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t reqId = 0, decW = 0, decH = 0;
    napi_get_value_int32(env, args[0], &reqId);
    napi_get_value_int32(env, args[1], &decW);
    napi_get_value_int32(env, args[2], &decH);
    {
        std::lock_guard<std::mutex> lock(g_decMutex);
        g_winDec[reqId] = {decW, decH};
    }
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── 窗口大小变化事件 ─────────────────────────────────────
static napi_value OnWindowResized(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t reqId = 0, w = 0, h = 0;
    napi_get_value_int32(env, args[0], &reqId);
    napi_get_value_int32(env, args[1], &w);
    napi_get_value_int32(env, args[2], &h);

    int pxW = w;
    int pxH = h;

    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "OnWindowResized: req=%{public}d w=%{public}d h=%{public}d (ETS)", reqId, w, h);

    // 去重只针对"已送达"的尺寸；句柄尚未登记（创建握手期）时先暂存 pending，
    // 由 ohos_create_window 登记句柄后补送，避免创建期尺寸反馈永久丢失
    // （实测：ETS 上报早于 g_winMap[1] 登记 13ms，事件被丢后永不重发）。
    {
        std::lock_guard<std::mutex> lk(g_resizeMutex);
        auto lit = g_lastResize.find(reqId);
        if (lit != g_lastResize.end() && lit->second.w == pxW && lit->second.h == pxH) {
            OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
                "OnWindowResized: skip duplicate req=%{public}d %{public}dx%{public}d", reqId, pxW, pxH);
            napi_value result;
            napi_get_undefined(env, &result);
            return result;
        }
    }

    bool delivered = false;
    {
        std::lock_guard<std::mutex> lock(g_winMutex);
        auto it = g_winMap.find(reqId);
        if (it != g_winMap.end() && g_inject_resize) {
            delivered = true;
            g_inject_resize(it->second, pxW, pxH);
            if (pxW > 0 && pxH > 0) {
                int rc = OH_NativeWindow_NativeWindowHandleOpt(
                    it->second, SET_BUFFER_GEOMETRY, pxW, pxH);
                OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
                    "SetBufferGeometry(req=%{public}d): %{public}dx%{public}d rc=%{public}d", reqId, pxW, pxH, rc);
            }
        }
    }

    {
        std::lock_guard<std::mutex> lk(g_resizeMutex);
        if (delivered) {
            g_lastResize[reqId] = { pxW, pxH };
            if (pxW > 0 && pxH > 0)
                g_surfaceSize[reqId] = { pxW, pxH };   // 渲染面权威尺寸（几何统一依据）
        } else {
            g_pendingResize[reqId] = { pxW, pxH };
            OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
                "OnWindowResized: pending (handle not registered) req=%{public}d %{public}dx%{public}d",
                reqId, pxW, pxH);
        }
    }

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── 系统 Configuration 变更（ArkTS → Pascal）──────────────
static napi_value OnNotifyConfiguration(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string cfg;
    if (argc >= 1) {
        size_t len = 0;
        napi_get_value_string_utf8(env, args[0], nullptr, 0, &len);
        if (len > 0) {
            cfg.resize(len);
            napi_get_value_string_utf8(env, args[0], &cfg[0], len + 1, &len);
            cfg.resize(len);
        }
    }
    if (!cfg.empty()) {
        typedef void (*UpdateConfigFn)(const char*);
        UpdateConfigFn fn = nullptr;
        {
            std::lock_guard<std::mutex> lock(g_cfgMutex);
            fn = (UpdateConfigFn)g_pascal.update_configuration;
            if (!fn) g_pendingConfig = cfg;
        }
        if (fn) {
            fn(cfg.c_str());
        }
    }
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── 启动载荷 JSON 推送（ArkTS onNewWant → Pascal）──────────────
// payload 为 JSON 串：{"uri","action","entities","parameters"}
// Pascal 未连接（连接前推送）时暂存，fp_bridge_init 内兜底补发。
static napi_value OnSetLaunchParams(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string payload;
    if (argc >= 1) {
        size_t len = 0;
        napi_get_value_string_utf8(env, args[0], nullptr, 0, &len);
        if (len > 0) {
            payload.resize(len);
            napi_get_value_string_utf8(env, args[0], &payload[0], len + 1, &len);
            payload.resize(len);
        }
    }
    if (!payload.empty()) {
        SetLaunchParamsFn fn = nullptr;
        {
            std::lock_guard<std::mutex> lock(g_launchMutex);
            fn = g_set_launch_params;
            if (!fn) g_pendingLaunchParams = payload;
        }
        if (fn) {
            OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
                "LaunchParams push: %{public}s", payload.c_str());
            fn(payload.c_str());
        }
    }
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── 定时器 ArkUI 注入（ETS → Pascal）──────────────────────
static napi_value OnTimerTick(napi_env env, napi_callback_info info) {
    typedef void (*TimerTickFn)();
    TimerTickFn fn = (TimerTickFn)g_pascal.timer_tick;
    if (fn) fn();
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

static napi_value OnTimerQuery(napi_env env, napi_callback_info info) {
    typedef int (*TimerQueryFn)();
    TimerQueryFn fn = (TimerQueryFn)g_pascal.timer_query;
    int active = fn ? fn() : 0;
    napi_value result;
    napi_create_int32(env, active, &result);
    return result;
}

// ── 标题栏事件（ETS → Pascal）──────────────
static napi_value OnWindowMoved(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t reqId = 0, x = 0, y = 0;
    napi_get_value_int32(env, args[0], &reqId);
    napi_get_value_int32(env, args[1], &x);
    napi_get_value_int32(env, args[2], &y);
    {
        std::lock_guard<std::mutex> lock(g_winMutex);
        auto it = g_winMap.find(reqId);
        if (it != g_winMap.end() && g_inject_moved) {
            g_inject_moved(it->second, x, y);
            OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
                "WindowMoved: req=%{public}d (%{public}d,%{public}d)", reqId, x, y);
        }
    }
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

static napi_value OnWindowClosed(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t reqId = 0;
    napi_get_value_int32(env, args[0], &reqId);
    void* win = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_winMutex);
        auto it = g_winMap.find(reqId);
        if (it != g_winMap.end()) {
            win = it->second;
            if (g_inject_closed) g_inject_closed(win);
            g_winMap.erase(reqId);
            g_winRects.erase(reqId);
            g_modalReqId = -1;
            OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
                "WindowClosed: req=%d cleaned (win=%p)", reqId, win);
        }
    }
    if (win) OH_NativeWindow_DestroyNativeWindow((OHNativeWindow*)win);
    if (win) {
        auto* cmd = new NativeCommandData();
        memset(cmd, 0, sizeof(NativeCommandData));
        cmd->type = NATIVE_CMD_DESTROY_WINDOW;
        cmd->reqId = reqId;
        SendNativeCommand(cmd);
        OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
            "WindowClosed: queued destroyWindow cmd req=%d", reqId);
    }
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── ETS 调用：更新窗口状态缓存（windowStatusChange 事件）─────────
static napi_value UpdateWindowState(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        napi_value result;
        napi_get_undefined(env, &result);
        return result;
    }
    int32_t reqId = 0, state = 0;
    napi_get_value_int32(env, args[0], &reqId);
    napi_get_value_int32(env, args[1], &state);
    {
        std::lock_guard<std::mutex> lock(g_winMutex);
        g_winStateCache[reqId] = state;
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "UpdateWindowState: req=%{public}d state=%{public}d", reqId, state);
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

static napi_value QueryCanClose(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t reqId = 0;
    napi_get_value_int32(env, args[0], &reqId);
    int can = 1;
    {
        std::lock_guard<std::mutex> lock(g_winMutex);
        auto it = g_winMap.find(reqId);
        if (it != g_winMap.end() && g_can_close) {
            can = g_can_close(it->second);
        }
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "QueryCanClose: req=%d -> %d", reqId, can);
    napi_value result;
    napi_create_int32(env, can, &result);
    return result;
}

static napi_value RefreshWindow(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t reqId = 0;
    napi_get_value_int32(env, args[0], &reqId);
    void* win = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_winMutex);
        auto it = g_winMap.find(reqId);
        if (it != g_winMap.end()) win = it->second;
    }
    // Re-verify: window may have been closed between first lock release and here
    if (win) {
        std::lock_guard<std::mutex> lock(g_winMutex);
        if (g_winMap.find(reqId) == g_winMap.end()) {
            OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
                "RefreshWindow: DROP req=%{public}d (window closed during dispatch)", reqId);
            win = nullptr;
        }
    }
    if (win && g_force_refresh) {
        g_force_refresh(win);
        OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI", "RefreshWindow: req=%d", reqId);
    }
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── 触摸事件注入 ─────────────────────────────────────────
static napi_value OnTouchEvent(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &len);
    char reqIdStr[32] = {0};
    if (len > 0 && len < sizeof(reqIdStr)) {
        napi_get_value_string_utf8(env, args[0], reqIdStr, sizeof(reqIdStr), &len);
    }
    int reqId = std::atoi(reqIdStr);

    double x = 0, y = 0, action = 0;
    napi_get_value_double(env, args[1], &x);
    napi_get_value_double(env, args[2], &y);
    napi_get_value_double(env, args[3], &action);

    // Unified GLOBAL (screen) coordinate basis：ETS 报 displayX/displayY（vp）
    // fpGUI 坐标已是物理像素 → vp × density → px
    float px = (float)(x * g_density);
    float py = (float)(y * g_density);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "OnTouchEvent: req=%{public}d vp=(%{public}d,%{public}d) -> px=(%{public}f,%{public}f)",
        reqId, (int)x, (int)y, px, py);

    OHNativeWindow* targetWin = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_winMutex);
        auto it = g_winMap.find(reqId);
        if (it != g_winMap.end()) targetWin = it->second;
    }

    if (!targetWin) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
            "OnTouchEvent: DROP no live window for req=%{public}d", reqId);
        napi_value result;
        napi_get_undefined(env, &result);
        return result;
    }

    // Re-verify: window may have been closed between first lock release and here
    {
        std::lock_guard<std::mutex> lock(g_winMutex);
        if (g_winMap.find(reqId) == g_winMap.end()) {
            OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
                "OnTouchEvent: DROP req=%{public}d (window closed during dispatch)", reqId);
            napi_value result;
            napi_get_undefined(env, &result);
            return result;
        }
    }

    if (g_inject_touch_to_win) {
        g_inject_touch_to_win(targetWin, px, py, (int)action);
    }

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── 鼠标事件注入 ─────────────────────────────────────────
#define MOUSE_ACTION_PRESS        1
#define MOUSE_ACTION_RELEASE      2
#define MOUSE_ACTION_MOVE         3
#define MOUSE_ACTION_HOVER        4
#define MOUSE_ACTION_ENTER_WINDOW 5
#define MOUSE_ACTION_LEAVE_WINDOW 6
#define MOUSE_ACTION_CANCEL       13

static napi_value OnMouseEvent(napi_env env, napi_callback_info info) {
    size_t argc = 5;
    napi_value args[5] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &len);
    char reqIdStr[32] = {0};
    if (len > 0 && len < sizeof(reqIdStr)) {
        napi_get_value_string_utf8(env, args[0], reqIdStr, sizeof(reqIdStr), &len);
    }
    int reqId = std::atoi(reqIdStr);

    double x = 0, y = 0;
    int32_t action = 0, button = 0;
    napi_get_value_double(env, args[1], &x);
    napi_get_value_double(env, args[2], &y);
    napi_get_value_int32(env, args[3], &action);
    napi_get_value_int32(env, args[4], &button);

    float px = (float)(x * g_density);
    float py = (float)(y * g_density);

    OHNativeWindow* targetWin = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_winMutex);
        auto it = g_winMap.find(reqId);
        if (it != g_winMap.end())
            targetWin = it->second;
    }

    if (!targetWin) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
            "OnMouseEvent: DROP no live window for req=%{public}d", reqId);
        napi_value result;
        napi_get_undefined(env, &result);
        return result;
    }

    // Re-verify: window may have been closed between first lock release and here
    {
        std::lock_guard<std::mutex> lock(g_winMutex);
        if (g_winMap.find(reqId) == g_winMap.end()) {
            OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
                "OnMouseEvent: DROP req=%{public}d (window closed during dispatch)", reqId);
            napi_value result;
            napi_get_undefined(env, &result);
            return result;
        }
    }

    if (g_inject_mouse) {
        char mbuf[256];
        snprintf(mbuf, sizeof(mbuf),
            "MouseEvent: req=%d action=%d button=%d xy=(%.0f,%.0f)",
            reqId, action, button, px, py);
        OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI", "%{public}s", mbuf);
        g_inject_mouse(targetWin, px, py, action, button);
    }

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── 滚轮事件注入 ─────────────────────────────────────────
static napi_value OnWheelEvent(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &len);
    char reqIdStr[32] = {0};
    if (len > 0 && len < sizeof(reqIdStr)) {
        napi_get_value_string_utf8(env, args[0], reqIdStr, sizeof(reqIdStr), &len);
    }
    int reqId = std::atoi(reqIdStr);

    double x = 0, y = 0;
    int32_t delta = 0;
    napi_get_value_double(env, args[1], &x);
    napi_get_value_double(env, args[2], &y);
    napi_get_value_int32(env, args[3], &delta);

    float px = (float)(x * g_density);
    float py = (float)(y * g_density);

    OHNativeWindow* targetWin = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_winMutex);
        auto it = g_winMap.find(reqId);
        if (it != g_winMap.end())
            targetWin = it->second;
    }
    if (!targetWin) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
            "OnWheelEvent: DROP no live window for req=%{public}d", reqId);
        napi_value result;
        napi_get_undefined(env, &result);
        return result;
    }

    // Re-verify: window may have been closed between first lock release and here
    {
        std::lock_guard<std::mutex> lock(g_winMutex);
        if (g_winMap.find(reqId) == g_winMap.end()) {
            OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
                "OnWheelEvent: DROP req=%{public}d (window closed during dispatch)", reqId);
            napi_value result;
            napi_get_undefined(env, &result);
            return result;
        }
    }

    if (g_inject_wheel) {
        g_inject_wheel(targetWin, px, py, delta);
    }

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── 悬停事件注入 ─────────────────────────────────────────
static napi_value OnHoverEvent(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &len);
    char reqIdStr[32] = {0};
    if (len > 0 && len < sizeof(reqIdStr)) {
        napi_get_value_string_utf8(env, args[0], reqIdStr, sizeof(reqIdStr), &len);
    }
    int reqId = std::atoi(reqIdStr);

    double x = 0, y = 0;
    napi_get_value_double(env, args[1], &x);
    napi_get_value_double(env, args[2], &y);

    float px = (float)(x * g_density);
    float py = (float)(y * g_density);

    OHNativeWindow* targetWin = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_winMutex);
        auto it = g_winMap.find(reqId);
        if (it != g_winMap.end())
            targetWin = it->second;
    }
    if (!targetWin) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
            "OnHoverEvent: DROP no live window for req=%{public}d", reqId);
        napi_value result;
        napi_get_undefined(env, &result);
        return result;
    }

    // Re-verify: window may have been closed between first lock release and here
    {
        std::lock_guard<std::mutex> lock(g_winMutex);
        if (g_winMap.find(reqId) == g_winMap.end()) {
            OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
                "OnHoverEvent: DROP req=%{public}d (window closed during dispatch)", reqId);
            napi_value result;
            napi_get_undefined(env, &result);
            return result;
        }
    }

    if (g_inject_hover) {
        g_inject_hover(targetWin, px, py);
    }

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── 键盘事件注入 ─────────────────────────────────────────
static napi_value OnKeyEvent(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t keyCode = 0, action = 0, modifiers = 0, unicodeChar = 0;
    napi_get_value_int32(env, args[0], &keyCode);
    napi_get_value_int32(env, args[1], &action);
    napi_get_value_int32(env, args[2], &modifiers);
    napi_get_value_int32(env, args[3], &unicodeChar);

    if (g_inject_key) {
        g_inject_key(keyCode, action, modifiers, unicodeChar);
    }

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── IME 文本输入注入 ──────────────────────────────────────
static napi_value OnTextInput(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char buf[4096];
    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], buf, sizeof(buf), &len);

    if (g_inject_text && len > 0) {
        g_inject_text(buf, (int)len);
    }

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── IME deleteLeft 注入 ──────────────────────────────────
static napi_value OnDeleteChars(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t count = 0;
    napi_get_value_int32(env, args[0], &count);

    if (g_inject_delete) {
        g_inject_delete(count);
    }

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── IME deleteRight 注入 ─────────────────────────────────
static napi_value OnDeleteRightChars(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t count = 0;
    napi_get_value_int32(env, args[0], &count);

    if (g_inject_delete_right) {
        g_inject_delete_right(count);
    }

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── IME moveCursor 注入 ──────────────────────────────────
static napi_value OnImeMoveCursor(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t direction = 0;
    napi_get_value_int32(env, args[0], &direction);

    if (g_inject_move_cursor) {
        g_inject_move_cursor(direction);
    }

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── 获取 modal reqId ─────────────────────────────────────
static napi_value GetModalReqId(napi_env env, napi_callback_info info) {
    napi_value val;
    napi_create_int32(env, g_modalReqId, &val);
    return val;
}

// ── ETS 主动请求显示/隐藏软键盘（状态同步，仅日志）────────────
// 对齐旧 ohos_show_keyboard_from_ets 语义：ETS FpgSurface.showIme/hideIme
// 自行完成弹/收键盘，本函数只记录状态、不回调 Pascal
// （避免 showIme → showKeyboard → Pascal → bridge → case 6 → showIme 回环）。
static napi_value ShowKeyboard(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t show = 0;
    napi_get_value_int32(env, args[0], &show);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "ShowKeyboard (ETS state sync): show=%{public}d", show);
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── 系统托盘事件 (ETS → C++ → Pascal) ────────────────────
static napi_value OnTrayEvent(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t evType = 0;
    napi_get_value_int32(env, args[0], &evType);
    char menuId[128] = {0};
    if (argc > 1) {
        size_t len = 0;
        napi_get_value_string_utf8(env, args[1], nullptr, 0, &len);
        if (len > 0 && len < sizeof(menuId))
            napi_get_value_string_utf8(env, args[1], menuId, sizeof(menuId), &len);
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "OnTrayEvent: type=%{public}d menuId=%{public}s inject=%{public}p",
        evType, menuId, (void*)g_inject_tray);
    if (g_inject_tray)
        g_inject_tray((int)evType, menuId);
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── 打开 URL / 文档：ArkTS 侧回调注册（ETS → C++）────────
// Pascal fpgOpenURL → C++ ohos_open_url（fp_bridge.cpp）→ 本 TSFN → openUrl(url)
static void OpenUrlCallJS(napi_env env, napi_value jsCb, void* /*context*/, void* data) {
    auto* call = static_cast<OpenUrlCall*>(data);
    if (env == nullptr || call == nullptr) {
        delete call;
        return;
    }
    napi_value jsUrl;
    napi_create_string_utf8(env, call->url.c_str(), NAPI_AUTO_LENGTH, &jsUrl);
    napi_value result = nullptr;
    napi_status st = napi_call_function(env, nullptr, jsCb, 1, &jsUrl, &result);
    if (st != napi_ok) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI",
            "OpenUrlCallJS: napi_call_function failed: %d", st);
    }
    delete call;
}

// NAPI: ArkTS 启动时注册 openUrl(url) 回调（bindOpenUrlContext + registerOpenUrl）
static napi_value RegisterOpenUrl(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::lock_guard<std::mutex> lk(g_open_url_mtx);
    if (g_open_url_tsfn != nullptr) {
        napi_release_threadsafe_function(g_open_url_tsfn, napi_tsfn_release);
        g_open_url_tsfn = nullptr;
    }
    napi_value resourceName;
    napi_create_string_utf8(env, "fpGUI_OpenUrl", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_threadsafe_function(env, args[0], nullptr, resourceName,
        0, 1, nullptr, nullptr, nullptr, OpenUrlCallJS, &g_open_url_tsfn);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "RegisterOpenUrl: tsfn=%p", (void*)g_open_url_tsfn);
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── 系统文件选择器结果回传（ETS → C++ → Pascal）────────────
// ETS FpgFilePicker.showFilePicker 完成（选中/取消/出错）后调用：
//   notifyFilePickerResult(reqId, resultJson)
// resultJson: {"uris":["file://...", ...],"code":0}  code: 0=成功 -1=用户取消 -2=错误
// 回调在 JS 线程触发；Pascal 侧回调仅做"拷贝结果串 + SetEvent"，线程安全。
// 注意回调指针可能为 nil（扩展单元未注册），此时仅记录日志丢弃。
static napi_value OnNotifyFilePickerResult(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t reqId = 0;
    if (argc >= 1 && args[0] != nullptr)
        napi_get_value_int32(env, args[0], &reqId);

    std::string resultJson;
    if (argc >= 2 && args[1] != nullptr) {
        size_t len = 0;
        napi_status st = napi_get_value_string_utf8(env, args[1], nullptr, 0, &len);
        if (st == napi_ok && len > 0) {
            resultJson.resize(len);
            napi_get_value_string_utf8(env, args[1], &resultJson[0], len + 1, &len);
            resultJson.resize(len);
        }
    }

    typedef void (*FilePickerResultFn)(int reqId, const char* resultJson);
    auto fn = (FilePickerResultFn)g_pascal.file_picker_result;
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "OnNotifyFilePickerResult: reqId=%{public}d len=%{public}d fn=%{public}p",
        reqId, (int)resultJson.size(), (void*)fn);
    if (fn)
        fn((int)reqId, resultJson.c_str());

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}


// ── 系统文件流操作结果回传（ETS → C++ → Pascal）────────────
// ETS FpgFileIo 完成 fs.*Sync 后调用：
//   notifyFileIoResult(reqId, resultJson, data?)
// resultJson: {"code":0,"n":123,"size":456,"handle":1}
// data: 读操作返回的字节 ArrayBuffer（其余操作可省略/空）
// data 指针仅本次调用有效；Pascal 回调须立即拷贝。
static napi_value OnNotifyFileIoResult(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t reqId = 0;
    if (argc >= 1 && args[0] != nullptr)
        napi_get_value_int32(env, args[0], &reqId);

    std::string resultJson;
    if (argc >= 2 && args[1] != nullptr) {
        size_t len = 0;
        napi_status st = napi_get_value_string_utf8(env, args[1], nullptr, 0, &len);
        if (st == napi_ok && len > 0) {
            resultJson.resize(len);
            napi_get_value_string_utf8(env, args[1], &resultJson[0], len + 1, &len);
            resultJson.resize(len);
        }
    }

    void* binData = nullptr;
    size_t binLen = 0;
    if (argc >= 3 && args[2] != nullptr) {
        napi_valuetype vt;
        if (napi_typeof(env, args[2], &vt) == napi_ok && vt == napi_object) {
            bool isBuf = false;
            if (napi_is_arraybuffer(env, args[2], &isBuf) == napi_ok && isBuf)
                napi_get_arraybuffer_info(env, args[2], &binData, &binLen);
        }
    }

    typedef void (*FileIoResultFn)(int reqId, const char* json,
                                   const unsigned char* data, int dataLen);
    auto fn = (FileIoResultFn)g_pascal.file_io_result;
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "OnNotifyFileIoResult: reqId=%{public}d jsonLen=%{public}d "
        "binLen=%{public}zu fn=%{public}p",
        reqId, (int)resultJson.size(), binLen, (void*)fn);
    if (fn)
        fn((int)reqId, resultJson.c_str(),
           static_cast<const unsigned char*>(binData), (int)binLen);

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ═══════════════════════════════════════════════════════════════
//  系统拖拽 (ETS XComponent 拖拽事件 → C++ → Pascal)
// ═══════════════════════════════════════════════════════════════

static napi_value OnDragEvent(napi_env env, napi_callback_info info) {
    size_t argc = 5;
    napi_value args[5] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 5) { napi_value r; napi_get_undefined(env, &r); return r; }

    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &len);
    char reqIdStr[32] = {0};
    if (len > 0 && len < sizeof(reqIdStr))
        napi_get_value_string_utf8(env, args[0], reqIdStr, sizeof(reqIdStr), &len);
    int reqId = std::atoi(reqIdStr);

    int32_t kind = 0;
    napi_get_value_int32(env, args[1], &kind);
    double x = 0, y = 0;
    napi_get_value_double(env, args[2], &x);
    napi_get_value_double(env, args[3], &y);

    size_t slen = 0;
    napi_get_value_string_utf8(env, args[4], nullptr, 0, &slen);
    char summary[2048] = {0};
    if (slen > 0 && slen < sizeof(summary))
        napi_get_value_string_utf8(env, args[4], summary, sizeof(summary), &slen);

    {
        std::lock_guard<std::mutex> lk(g_dndMutex);
        auto it = g_dndEnabled.find(reqId);
        if (it == g_dndEnabled.end() || !it->second) {
            OH_LOG_Print(LOG_APP, LOG_DEBUG, 0xFF00, "fpGUI",
                "OnDragEvent: dnd disabled req=%{public}d kind=%{public}d", reqId, kind);
            napi_value r; napi_get_undefined(env, &r);
            return r;
        }
    }

    OHNativeWindow* targetWin = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_winMutex);
        auto it = g_winMap.find(reqId);
        if (it != g_winMap.end()) targetWin = it->second;
    }
    if (!targetWin) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
            "OnDragEvent: DROP no live window for req=%{public}d", reqId);
        napi_value result;
        napi_get_undefined(env, &result);
        return result;
    }

    // Re-verify: window may have been closed between first lock release and here
    {
        std::lock_guard<std::mutex> lock(g_winMutex);
        if (g_winMap.find(reqId) == g_winMap.end()) {
            OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
                "OnDragEvent: DROP req=%{public}d (window closed during dispatch)", reqId);
            napi_value result;
            napi_get_undefined(env, &result);
            return result;
        }
    }

    if (g_inject_drag) {
        float px = (float)(x * g_density);
        float py = (float)(y * g_density);
        if (kind != 1) {
            char dlog[512];
            snprintf(dlog, sizeof(dlog),
                "OnDragEvent: req=%d kind=%d vp=(%.0f,%.0f) summary=%s",
                reqId, kind, x, y, summary);
            OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI", "%{public}s", dlog);
        }
        g_inject_drag(targetWin, kind, px, py, summary);
    }
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ── onDrop：同步等待 Pascal 应答（≤5s），返回 (accept<<8)|action ──
static napi_value OnDropEvent(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t result = 0;

    if (argc >= 4) {
        size_t len = 0;
        napi_get_value_string_utf8(env, args[0], nullptr, 0, &len);
        char reqIdStr[32] = {0};
        if (len > 0 && len < sizeof(reqIdStr))
            napi_get_value_string_utf8(env, args[0], reqIdStr, sizeof(reqIdStr), &len);
        int reqId = std::atoi(reqIdStr);

        double x = 0, y = 0;
        napi_get_value_double(env, args[1], &x);
        napi_get_value_double(env, args[2], &y);

        size_t rlen = 0;
        napi_get_value_string_utf8(env, args[3], nullptr, 0, &rlen);
        char records[8192] = {0};
        if (rlen > 0 && rlen < sizeof(records))
            napi_get_value_string_utf8(env, args[3], records, sizeof(records), &rlen);

        OHNativeWindow* targetWin = nullptr;
        {
            std::lock_guard<std::mutex> lock(g_winMutex);
            auto it = g_winMap.find(reqId);
            if (it != g_winMap.end()) targetWin = it->second;
        }
        // Re-verify: window may have been closed between first lock release and here
        if (targetWin) {
            std::lock_guard<std::mutex> lock(g_winMutex);
            if (g_winMap.find(reqId) == g_winMap.end()) {
                OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
                    "OnDropEvent: DROP req=%{public}d (window closed during dispatch)", reqId);
                targetWin = nullptr;
            }
        }
        if (targetWin && g_inject_drop) {
            result = g_inject_drop(targetWin,
                (float)(x * g_density), (float)(y * g_density), records);
        }
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "OnDropEvent: result=%{public}d", result);
    napi_value v;
    napi_create_int32(env, result, &v);
    return v;
}

// ── executeDrag 回调结束 → Pascal 会话结束 ──
static napi_value OnDragEnd(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int64_t sessionId = 0;
    if (argc >= 1) napi_get_value_int64(env, args[0], &sessionId);
    int32_t result = 2;
    if (argc >= 2) napi_get_value_int32(env, args[1], &result);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "OnDragEnd: session=%lld result=%{public}d", (long long)sessionId, result);
    if (g_inject_drag_end) g_inject_drag_end(sessionId, result);
    napi_value r;
    napi_get_undefined(env, &r);
    return r;
}

// ── ETS 查询窗口是否启用拖入 ──
static napi_value IsDndEnabled(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t reqId = 0;
    if (argc >= 1) napi_get_value_int32(env, args[0], &reqId);
    bool enabled = false;
    {
        std::lock_guard<std::mutex> lk(g_dndMutex);
        auto it = g_dndEnabled.find(reqId);
        if (it != g_dndEnabled.end()) enabled = it->second;
    }
    napi_value v;
    napi_get_boolean(env, enabled, &v);
    return v;
}

// ── 启动 Pascal 应用（ArkTS 调用）────────────────────────
// 单实例守卫：加载 lib<appLibName>.so 并在独立线程启动 RunLazarus。
// 桥接（fp_bridge_init）由 Pascal 端 RunLazarus 内部完成，本函数不等待。
static void* PascalThread(void* arg);   // 定义见文件尾部

// 冷启动载荷：随线程参数传给 PascalThread（appLib 必填，launchPayload/appArgs 可空）
struct PascalStartArgs {
    char* appLib;
    char* launchPayload;
    char* appArgs;      // 命令行参数（空格分隔；可空）
};

static napi_value Start(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char appLib[128] = {0};
    if (argc >= 1) {
        size_t len = 0;
        napi_get_value_string_utf8(env, args[0], nullptr, 0, &len);
        if (len > 0 && len < sizeof(appLib)) {
            napi_get_value_string_utf8(env, args[0], appLib, sizeof(appLib), &len);
        }
    }
    if (appLib[0] == '\0') {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI", "Start: appLibName empty");
        napi_value r;
        napi_get_undefined(env, &r);
        return r;
    }
    if (g_started.exchange(true)) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
            "Start: already started (%s)", appLib);
        napi_value r;
        napi_get_undefined(env, &r);
        return r;
    }

    // 可选第二参数：启动载荷 JSON（want.uri/action/entities/parameters 全量）
    char* payload = nullptr;
    if (argc >= 2 && args[1] != nullptr) {
        size_t len = 0;
        napi_get_value_string_utf8(env, args[1], nullptr, 0, &len);
        if (len > 0) {
            payload = (char*)malloc(len + 1);
            if (payload) {
                napi_get_value_string_utf8(env, args[1], payload, len + 1, &len);
                payload[len] = '\0';
                OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
                    "Start: launchPayload=%{public}s", payload);
            }
        }
    }

    // 可选第三参数：命令行参数（空格分隔；-b debug / key=value）
    char* appArgs = nullptr;
    if (argc >= 3 && args[2] != nullptr) {
        size_t len = 0;
        napi_get_value_string_utf8(env, args[2], nullptr, 0, &len);
        if (len > 0) {
            appArgs = (char*)malloc(len + 1);
            if (appArgs) {
                napi_get_value_string_utf8(env, args[2], appArgs, len + 1, &len);
                appArgs[len] = '\0';
                OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
                    "Start: appArgs=%{public}s", appArgs);
            }
        }
    }

    PascalStartArgs* sa = new PascalStartArgs();
    sa->appLib = strdup(appLib);
    sa->launchPayload = payload;
    sa->appArgs = appArgs;
    pthread_t t;
    // 重要：Pascal 库（libhelloworld.so）的加载期单元初始化（FPC RTL + fpGUI
    // 全部单元 + -gl 行号信息）会深链递归，musl 默认线程栈仅 128KB，实测
    // 会在单元初始化收尾（LNFODWRF.INITIALIZEAFTERUNITS）时栈溢出
    // （SIGSEGV@stack_low-8）。显式分配 8MB，对齐正常 app 主线程。
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, 8 * 1024 * 1024);
    pthread_create(&t, &attr, PascalThread, sa);
    pthread_attr_destroy(&attr);
    pthread_detach(t);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "Start: Pascal app '%{public}s' launching", appLib);

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ═══════════════════════════════════════════════════════════════
//  NAPI 模块注册
// ═══════════════════════════════════════════════════════════════

EXTERN_C_START
// Binder (IPC Kit) bridge — implemented in binder_bridge.cpp
extern "C" int ohos_binder_spawn_server(void);
extern "C" void* ohos_binder_get_proxy(void);

static napi_value SpawnBinderServer(napi_env env, napi_callback_info info) {
    int ret = ohos_binder_spawn_server();
    napi_value v;
    napi_create_int32(env, ret, &v);
    return v;
}

static napi_value BinderProxyReady(napi_env env, napi_callback_info info) {
    bool ready = ohos_binder_get_proxy() != nullptr;
    napi_value v;
    napi_get_boolean(env, ready, &v);
    return v;
}

static napi_value Init(napi_env env, napi_value exports) {
    // 动态分发结果回传用的持久 TSFN（js_cb=nullptr，靠 call_js_cb + data.jobId 路由）
    {
        napi_value dispatchResName;
        napi_create_string_utf8(env, "fpGUI_Dispatch", NAPI_AUTO_LENGTH, &dispatchResName);
        napi_create_threadsafe_function(env, nullptr, nullptr, dispatchResName,
            0, 1, nullptr, nullptr, nullptr, DispatchResultCallJS, &g_dispatchTsfn);
        OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
            "dispatch TSFN created: %p", (void*)g_dispatchTsfn);
    }
    // arkTS_Invoke（Pascal → ArkTS）持久 TSFN（必须在 JS 线程创建，此处即 JS 线程）
    ArkInvokeInit(env);
    // 分发超时守护线程（单次启动）
    bool expected = false;
    if (g_dispatchJanitorStarted.compare_exchange_strong(expected, true)) {
        try {
            g_dispatchJanitor = std::thread(DispatchPendingJanitor);
            g_dispatchJanitor.detach();
        } catch (...) {
            OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
                "dispatch janitor start failed");
        }
    }

    napi_property_descriptor desc[] = {
        // ── 生命周期 ──
        { "start",               nullptr, Start,               nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setEtsReady",         nullptr, SetEtsReady,         nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setSandboxPaths",     nullptr, SetSandboxPaths,     nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setNativeCallback",   nullptr, SetNativeCallback,   nullptr, nullptr, nullptr, napi_default, nullptr },
        { "releaseKeyboardCallback", nullptr, ReleaseKeyboardCallback, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "registerOpenUrl",     nullptr, RegisterOpenUrl,     nullptr, nullptr, nullptr, napi_default, nullptr },

        // ── Binder (IPC Kit) ── 定义见 binder_bridge.cpp
        { "spawnBinderServer",   nullptr, SpawnBinderServer,   nullptr, nullptr, nullptr, napi_default, nullptr },
        { "binderProxyReady",    nullptr, BinderProxyReady,    nullptr, nullptr, nullptr, napi_default, nullptr },

        // ── Surface 就绪 ──
        { "onSurfaceReady",      nullptr, OnSurfaceReady,      nullptr, nullptr, nullptr, napi_default, nullptr },

        // ── 窗口属性 ──
        { "onWindowResized",     nullptr, OnWindowResized,     nullptr, nullptr, nullptr, napi_default, nullptr },
        { "onWindowMoved",       nullptr, OnWindowMoved,       nullptr, nullptr, nullptr, napi_default, nullptr },
        { "onWindowClosed",      nullptr, OnWindowClosed,      nullptr, nullptr, nullptr, napi_default, nullptr },
        { "queryCanClose",       nullptr, QueryCanClose,       nullptr, nullptr, nullptr, napi_default, nullptr },
        { "refreshWindow",       nullptr, RefreshWindow,       nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setMainWindowDec",    nullptr, SetMainWindowDec,    nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setWindowDec",        nullptr, SetWindowDec,        nullptr, nullptr, nullptr, napi_default, nullptr },

        // ── 事件注入 ──
        { "onTouchEvent",        nullptr, OnTouchEvent,        nullptr, nullptr, nullptr, napi_default, nullptr },
        { "onMouseEvent",        nullptr, OnMouseEvent,        nullptr, nullptr, nullptr, napi_default, nullptr },
        { "onWheelEvent",        nullptr, OnWheelEvent,        nullptr, nullptr, nullptr, napi_default, nullptr },
        { "onHoverEvent",        nullptr, OnHoverEvent,        nullptr, nullptr, nullptr, napi_default, nullptr },
        { "onKeyEvent",          nullptr, OnKeyEvent,          nullptr, nullptr, nullptr, napi_default, nullptr },
        { "onTextInput",         nullptr, OnTextInput,         nullptr, nullptr, nullptr, napi_default, nullptr },
        { "onDeleteChars",       nullptr, OnDeleteChars,       nullptr, nullptr, nullptr, napi_default, nullptr },
        { "onDeleteRightChars",  nullptr, OnDeleteRightChars,  nullptr, nullptr, nullptr, napi_default, nullptr },
        { "onImeMoveCursor",     nullptr, OnImeMoveCursor,     nullptr, nullptr, nullptr, napi_default, nullptr },
        { "showKeyboard",        nullptr, ShowKeyboard,        nullptr, nullptr, nullptr, napi_default, nullptr },

        // ── 辅助 ──
        { "getModalReqId",       nullptr, GetModalReqId,       nullptr, nullptr, nullptr, napi_default, nullptr },

        // ── 动态分发（Registry-Dispatch） ──
        { "dispatch",            nullptr, Dispatch,             nullptr, nullptr, nullptr, napi_default, nullptr },
        { "dispatchCancel",      nullptr, DispatchCancel,       nullptr, nullptr, nullptr, napi_default, nullptr },

        // ── 系统托盘 / 配置 / 定时器 ──
        { "onTrayEvent",         nullptr, OnTrayEvent,         nullptr, nullptr, nullptr, napi_default, nullptr },
        { "notifyConfiguration", nullptr, OnNotifyConfiguration, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setLaunchParams",     nullptr, OnSetLaunchParams,     nullptr, nullptr, nullptr, napi_default, nullptr },
        { "timerTick",           nullptr, OnTimerTick,         nullptr, nullptr, nullptr, napi_default, nullptr },
        { "timerQuery",          nullptr, OnTimerQuery,        nullptr, nullptr, nullptr, napi_default, nullptr },

        // ── 系统文件选择器（结果回传 ETS → Pascal）──
        { "notifyFilePickerResult", nullptr, OnNotifyFilePickerResult, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "notifyFileIoResult", nullptr, OnNotifyFileIoResult, nullptr, nullptr, nullptr, napi_default, nullptr },
        
        // ── 系统拖拽 ──
        { "onDragEvent",         nullptr, OnDragEvent,         nullptr, nullptr, nullptr, napi_default, nullptr },
        { "onDropEvent",         nullptr, OnDropEvent,         nullptr, nullptr, nullptr, napi_default, nullptr },
        { "onDragEnd",           nullptr, OnDragEnd,           nullptr, nullptr, nullptr, napi_default, nullptr },
        { "isDndEnabled",        nullptr, IsDndEnabled,        nullptr, nullptr, nullptr, napi_default, nullptr },

        // ── 窗口状态缓存（v10） ──
        { "updateWindowState",   nullptr, UpdateWindowState,   nullptr, nullptr, nullptr, napi_default, nullptr },

        // ── arkTS_Invoke：Pascal → ArkTS 方法注册（v13） ──
        { "registerInvokeMethod",   nullptr, ArkInvoke_RegisterMethod,   nullptr, nullptr, nullptr, napi_default, nullptr },
        { "registerInvokeNamespace",nullptr, ArkInvoke_RegisterNamespace,nullptr, nullptr, nullptr, napi_default, nullptr },
        { "registerInvokeDispatcher",nullptr, ArkInvoke_RegisterDispatcher, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "unregisterInvokeMethod", nullptr, ArkInvoke_UnregisterMethod, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "clearInvokeMethods",     nullptr, ArkInvoke_ClearMethods,     nullptr, nullptr, nullptr, napi_default, nullptr },
        { "listInvokeMethods",      nullptr, ArkInvoke_ListMethods,      nullptr, nullptr, nullptr, napi_default, nullptr },
        { "invokeLocal",            nullptr, ArkInvoke_InvokeLocal,      nullptr, nullptr, nullptr, napi_default, nullptr },
    };

    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);

    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "NAPI Init complete (libfp_bridge, reverse-bridge mode)");

    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "fp_bridge",
    .nm_priv = ((void*)0),
    .reserved = {0}
};

// 合并 appArgs 到 payload JSON（在最后一个 '}' 前插入 "appArgs":"..."）
// 从 JSON 中提取 "key":"value" 的 value（简单扫描）
// 返回新分配的字符串（调用方需 free），未找到返回 nullptr
static char* extractJsonField(const char* json, const char* key) {
    if (!json || !key) return nullptr;
    std::string search = std::string("\"") + key + "\":\"";
    const char* p = strstr(json, search.c_str());
    if (!p) return nullptr;
    p += search.size();
    const char* end = p;
    while (*end && *end != '"') {
        if (*end == '\\' && end[1]) end++;
        end++;
    }
    char* result = (char*)malloc(end - p + 1);
    if (result) {
        memcpy(result, p, end - p);
        result[end - p] = '\0';
    }
    return result;
}

// 替换 APP_ARGS 中的 %xxx% 占位符（从 payload JSON 取值）
// 返回新分配的字符串（调用方需 free）
static char* replacePlaceholders(const char* appArgs, const char* payload, const char* libname) {
    if (!appArgs || appArgs[0] == '\0') return nullptr;
    if (!payload || payload[0] == '\0') return strdup(appArgs);

    std::string result;
    result += libname;
    result += ' ';
    const char* p = appArgs;
    while (*p) {
        if (*p == '%') {
            const char* end = strchr(p + 1, '%');
            if (end) {
                std::string key(p + 1, end - p - 1);
                char* val = extractJsonField(payload, key.c_str());
                if (val) {
                    result += val;
                    free(val);
                    p = end + 1;
                    continue;
                }
            }
            result += *p;
            p++;
        } else {
            result += *p;
            p++;
        }
    }
    return strdup(result.c_str());
}

// ═══════════════════════════════════════════════════════════════
//  Pascal 启动线程
// ═══════════════════════════════════════════════════════════════

static void* PascalThread(void* arg) {
    char appLib[128] = {0};
    char* payload = nullptr;
    char appArgsBuf[4096] = {0};
    if (arg) {
        PascalStartArgs* sa = (PascalStartArgs*)arg;
        if (sa->appLib) {
            strncpy(appLib, sa->appLib, sizeof(appLib) - 1);
            free(sa->appLib);
        }
        payload = sa->launchPayload;   // 可空；Pascal 侧按 argc 判定
        if (sa->appArgs) {
            strncpy(appArgsBuf, sa->appArgs, sizeof(appArgsBuf) - 1);
            free(sa->appArgs);
        }
        delete sa;
    }
    if (appLib[0] == '\0') {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI", "PascalThread: no app name");
        free(payload);
        return nullptr;
    }

    // 等待 ETS 就绪
    for (int i = 0; i < 300 && !g_etsReady; i++) usleep(100000);
    if (!g_etsReady) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI", "Timeout waiting for ETS ready");
        free(payload);
        return nullptr;
    }

    char libName[160];
    snprintf(libName, sizeof(libName), "lib%s.so", appLib);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI", "Opening %s", libName);

    // 替换 APP_ARGS 中的 %xxx% 占位符（从 payload JSON 取值）
    char* resolvedArgs = nullptr;
    if (appArgsBuf[0] != '\0') {
        resolvedArgs = replacePlaceholders(appArgsBuf, payload, libName);
        OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
            "PascalThread: resolved appArgs=%{public}s", resolvedArgs ? resolvedArgs : "(null)");
    }

    void* h = dlopen(libName, RTLD_NOW);
    if (!h) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI",
            "dlopen %s failed: %s", libName, dlerror());
        free(payload);
        return nullptr;
    }
    g_pascalLibHandle = h;   // ← 保存句柄供 binder_bridge 复用

    // ④ 显示预初始化（set_screen_size/zoom/config）
    
    // ── 显示预初始化（同步，Pascal 线程内完成）──
    int32_t screenW = 1920, screenH = 1080, physicalDpi = 160;
    float densityPixels = 1.0f, xDpi = 0.0f, yDpi = 0.0f;
    OH_NativeDisplayManager_GetDefaultDisplayWidth(&screenW);
    OH_NativeDisplayManager_GetDefaultDisplayHeight(&screenH);
    OH_NativeDisplayManager_GetDefaultDisplayDensityDpi(&physicalDpi);
    OH_NativeDisplayManager_GetDefaultDisplayDensityXdpi(&xDpi);
    OH_NativeDisplayManager_GetDefaultDisplayDensityYdpi(&yDpi);
    // 浮点日志一律 snprintf 预格式化再 %{public}s 输出——绕开 libhilog 对
    // %{public}.2f 的 va_list 浮点读取路径（实测在此环境触发 fmt_fp SEGV）
    {
        char vabuf[256];
        snprintf(vabuf, sizeof(vabuf),
            "VisArea: device=%dx%d xDpi=%.2f yDpi=%.2f",
            screenW, screenH, xDpi, yDpi);
        OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI", "%{public}s", vabuf);
    }
    {
        float dp = 0.0f;
        if (OH_NativeDisplayManager_GetDefaultDisplayVirtualPixelRatio(&dp) == 0 && dp > 0)
            densityPixels = dp;
        g_density = densityPixels;
    }
    {
        char dspbuf[256];
        snprintf(dspbuf, sizeof(dspbuf),
            "Display: %dx%d dpi=%d density=%.2f",
            screenW, screenH, physicalDpi, densityPixels);
        OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI", "%{public}s", dspbuf);
    }

    typedef void (*SetZoomScaleFn)(float);
    SetZoomScaleFn setZoom = (SetZoomScaleFn)g_pascal.set_zoom_scale;
    if (setZoom) setZoom(g_zoomScale);
    typedef void (*SetScreenFunc)(int, int, int, float);
    SetScreenFunc setScr = (SetScreenFunc)g_pascal.set_screen_size;
    if (setScr) setScr(screenW, screenH, physicalDpi, densityPixels);

    // 系统 Configuration 首启下发（native 值；ArkTS 暂存由 notifyConfiguration 通道合并）
    typedef void (*UpdateConfigFn)(const char*);
    UpdateConfigFn cfgFn = (UpdateConfigFn)g_pascal.update_configuration;
    if (cfgFn) {
        std::string nativeCfg;
        char kbuf[96];
        snprintf(kbuf, sizeof(kbuf), "den=%.4f;", densityPixels);
        nativeCfg += kbuf;
        int denKonf = 0;
        if (physicalDpi >= 640) denKonf = 640;
        else if (physicalDpi >= 480) denKonf = 480;
        else if (physicalDpi >= 320) denKonf = 320;
        else if (physicalDpi >= 240) denKonf = 240;
        else if (physicalDpi >= 160) denKonf = 160;
        else if (physicalDpi >= 120) denKonf = 120;
        snprintf(kbuf, sizeof(kbuf), "denKonf=%d;", denKonf);
        nativeCfg += kbuf;
        NativeDisplayManager_Orientation ori = DISPLAY_MANAGER_UNKNOWN;
        if (OH_NativeDisplayManager_GetDefaultDisplayOrientation(&ori) == 0) {
            int dir = -1;
            if (ori == DISPLAY_MANAGER_PORTRAIT || ori == DISPLAY_MANAGER_PORTRAIT_INVERTED) dir = 0;
            else if (ori == DISPLAY_MANAGER_LANDSCAPE || ori == DISPLAY_MANAGER_LANDSCAPE_INVERTED) dir = 1;
            snprintf(kbuf, sizeof(kbuf), "d=%d;", dir);
            nativeCfg += kbuf;
        }
        uint64_t dispId = 0;
        if (OH_NativeDisplayManager_GetDefaultDisplayId(&dispId) == 0) {
            snprintf(kbuf, sizeof(kbuf), "i=%llu;", (unsigned long long)dispId);
            nativeCfg += kbuf;
        }
        float scaledDen = 0.0f;
        if (OH_NativeDisplayManager_GetDefaultDisplayScaledDensity(&scaledDen) == 0 &&
            scaledDen > 0 && densityPixels > 0) {
            snprintf(kbuf, sizeof(kbuf), "fs=%.4f;", scaledDen / densityPixels);
            nativeCfg += kbuf;
        }
        OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
            "Config init: %{public}s", nativeCfg.c_str());
        cfgFn(nativeCfg.c_str());
    }
    
    // 启动 Pascal 应用（fp_bridge_init 桥接由 Pascal 端 RunMainProc 内部完成）
    typedef void (*RunProc)();
    RunProc pro = (RunProc)dlsym(h, "MainProc");
    if (pro) {
        OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
            "Starting Pascal app (MainProc)");
        if (g_inject_app_args)
            g_inject_app_args(payload, resolvedArgs);
        pro();  // 阻塞：内部 fp_bridge_init + 事件循环
    } else {
        typedef int (*RunFunc)(int, char**);
        RunFunc run = (RunFunc)dlsym(h, "main");
        if (run) {
            OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
                "Starting Pascal app main(argc, argv)");
            if (g_inject_app_args)
                g_inject_app_args(payload, resolvedArgs);
            // 构建 argv：按空格分割 resolvedArgs
            const int MAXARGV = 64;
            char* argv[MAXARGV + 1];
            memset(argv, 0, sizeof(argv));
            int argc = 1;
            argv[0] = libName;//(char*)"helloworld";
            char* argsCopy = nullptr;
            if (resolvedArgs && resolvedArgs[0] != '\0') {
                argsCopy = strdup(resolvedArgs);
                char* token = strtok(argsCopy, " ");
                while (token && argc < MAXARGV) {
                    argv[argc++] = token;
                    token = strtok(nullptr, " ");
                }
            }
            OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
                "main: argc=%d", argc);
            run(argc, argv);
            free(argsCopy);
        } else {
            OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI",
                "dlsym RunMainProc FAILED: %s", dlerror());
        }
    }

    // 清理
    free(resolvedArgs);
    free(payload);
    {
        std::lock_guard<std::mutex> lock(g_winMutex);
        for (auto& kv : g_winMap)
            OH_NativeWindow_DestroyNativeWindow(kv.second);
        g_winMap.clear();
    }

    g_pascalLibHandle = nullptr;   // ← dlclose 前清空
    dlclose(h);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI", "Pascal thread exiting");
    return nullptr;
}

void* fp_bridge_get_pascal_lib_handle(void) {
    return g_pascalLibHandle;
}

// ═══════════════════════════════════════════════════════════════
//  启动入口 — 构造函数级别，so 加载时自动执行
// ═══════════════════════════════════════════════════════════════

extern "C" __attribute__((constructor)) void Bootstrap(void) {
    napi_module_register(&demoModule);
    // 自身置为 RTLD_GLOBAL：Pascal 经 dlsym(RTLD_DEFAULT) 也能找到桥接符号
    dlopen("libfp_bridge.so", RTLD_NOLOAD | RTLD_GLOBAL);
}