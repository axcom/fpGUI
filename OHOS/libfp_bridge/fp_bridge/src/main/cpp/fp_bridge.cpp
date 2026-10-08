// fpGUI HarmonyOS 统一桥 libfp_bridge.so — 桥核心单元
// ======================================================
// 从原 napi_init.cpp 拆出的桥核心：Pascal → C++ 的全部 ohos_* 导出 +
// fp_bridge_init 反向桥接入口 + 桥辅助函数 + 桥拥有全局。
// 共享契约见 fp_bridge_internal.h；NAPI 表面（ArkTS → C++）在 napi_init.cpp。

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unistd.h>
#include <sys/stat.h>
#include <atomic>
#include <map>
#include <mutex>
#include <condition_variable>
#include <string>
#include <vector>

#include <native_window/external_window.h>
#include <database/pasteboard/oh_pasteboard.h>
#include <database/udmf/udmf.h>
#include <database/udmf/uds.h>
#include "hilog/log.h"
#include "napi/native_api.h"
#include "fp_bridge_internal.h"

// ── Touch/Mouse/Key injection (loaded from libhelloworld.so) ──
InjectTouchToWinFunc g_inject_touch_to_win = nullptr;
InjectMouseFunc g_inject_mouse = nullptr;
InjectWheelFunc g_inject_wheel = nullptr;
InjectHoverFunc g_inject_hover = nullptr;
InjectKeyFunc g_inject_key = nullptr;
InjectTextFunc g_inject_text = nullptr;
InjectDeleteFunc g_inject_delete = nullptr;
InjectDeleteFunc g_inject_delete_right = nullptr;
InjectMoveCursorFunc g_inject_move_cursor = nullptr;
InjectResizeFunc g_inject_resize = nullptr;
InjectWindowMovedFunc  g_inject_moved  = nullptr;
InjectWindowClosedFunc g_inject_closed = nullptr;
CanCloseFunc           g_can_close     = nullptr;
ForceWindowRefreshFunc g_force_refresh = nullptr;
InjectTrayEventFunc g_inject_tray = nullptr;
InjectDragEventFunc g_inject_drag = nullptr;
InjectDropFunc      g_inject_drop = nullptr;
InjectDragEndFunc   g_inject_drag_end = nullptr;

// ── 反向桥核心状态 ─────────────────────────────
// Pascal 经 fp_bridge_init 传入的函数表（按值拷贝缓存）与就绪标志
FpBridgePascalApi g_pascal;
std::atomic<bool> g_bridgeReady{false};

// ── 启动载荷 JSON（ArkTS → Pascal；热启动 onNewWant 通道）──
SetLaunchParamsFn g_set_launch_params = nullptr;
std::string g_pendingLaunchParams;
std::mutex g_launchMutex;

// ── 命令行参数注入（两个独立参数，不经 mergePayloadJson）──
InjectAppArgsFn g_inject_app_args = nullptr;

// ── 动态分发（Registry-Dispatch）：Pascal 注册表 + C++ Promise 桥 ──
// Pascal 经导出表提供 dispatch(op,params) → 立即返回 {"ok":true,"jobId":"job_N"}；
// 结果经 C++ ohos_dispatch_result(jobId,json,failed) → TSFN → Promise resolve/reject。
DispatchFn g_dispatch = nullptr;
DispatchFreeFn g_dispatch_free = nullptr;

// 拖入开关（reqId -> 是否允许拖入）
std::map<int, bool> g_dndEnabled;
std::mutex g_dndMutex;

// 拖拽会话 id（C++ 分配，ETS extraParams 透传回传）
int64_t g_nextSessionId = 1;

// ── XComponent 就绪请求 ─────────────────────────────────
std::map<int, XComponentRequest*> g_xcReqs;
std::mutex g_xcMutex;
std::condition_variable g_xcCV;

// ── 原生窗口映射表：reqId ↔ OHNativeWindow* ──────────────
std::map<int, OHNativeWindow*> g_winMap;
std::map<int, WinRect> g_winRects;
std::mutex g_winMutex;

// ── 窗口状态缓存（reqId → OHOS WindowStatusType）──────────────
// 由 ETS windowStatusChange 事件更新，Pascal GetWindowState 查询
std::map<int, int> g_winStateCache;

// per-window 上次反馈尺寸（OnWindowResized 去重）
std::map<int, SizeW> g_lastResize;
// 句柄尚未登记时暂存的 resize（ETS 在创建握手期上报，待 ohos_create_window 登记后补送）
std::map<int, SizeW> g_pendingResize;
// ETS 上报的渲染面(surface)权威尺寸：native buffer 几何一律以它为准，
// 防 Pascal 创建期用旧逻辑尺寸覆盖（被系统强制最大化场景会因此放大显示）
std::map<int, SizeW> g_surfaceSize;
std::mutex g_resizeMutex;

// ── 窗口属性暂存 ──────────────────────────────────────────
int g_nextReqId = 1;

// ── Modal 窗口跟踪 ─────────────────────────────────────────
int g_modalReqId = -1;

// ── 主窗口装饰尺寸 ──────────────────
int32_t g_mainDecW = 0;
int32_t g_mainDecH = 0;
std::map<int, std::pair<int32_t, int32_t>> g_winDec;
std::mutex g_decMutex;

// Keyboard callback stack
std::vector<napi_threadsafe_function> g_kbTsfnStack;
std::mutex g_kbMutex;

// ═══════════════════════════════════════════════════════════════
//  Helper 函数
// ═══════════════════════════════════════════════════════════════

OHNativeWindow* SurfaceIdToWindow(uint64_t sid, int w, int h) {
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "SurfaceIdToWindow: sid=%{public}lu w=%{public}d h=%{public}d", sid, w, h);
    OHNativeWindow* win = nullptr;
    int ret = OH_NativeWindow_CreateNativeWindowFromSurfaceId(sid, &win);
    if (ret != 0 || !win) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI",
            "CreateNativeWindowFromSurfaceId failed: ret=%d win=%p", ret, win);
        return nullptr;
    }
    if (w > 0 && h > 0) {
        OH_NativeWindow_NativeWindowHandleOpt(win, SET_BUFFER_GEOMETRY, w, h);
    }
    return win;
}

int FindReqIdByHandle(void* handle) {
    if (!handle) return -1;
    std::lock_guard<std::mutex> lock(g_winMutex);
    for (auto& kv : g_winMap) {
        if (kv.second == handle) return kv.first;
    }
    return -1;
}

void SendNativeCommand(NativeCommandData* data) {
    if (g_tsfn) {
        napi_call_threadsafe_function(g_tsfn, data, napi_tsfn_blocking);
    } else {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
            "SendNativeCommand: g_tsfn null, cmd type=%d dropped", data->type);
        delete data;
    }
}

napi_threadsafe_function GetKbTsfn() {
    std::lock_guard<std::mutex> lock(g_kbMutex);
    if (!g_kbTsfnStack.empty()) return g_kbTsfnStack.back();
    return g_tsfn;
}

// ═══════════════════════════════════════════════════════════════
//  C bridge 函数 — 由 Pascal 经 fp_bridge_init 装载（亦导出符号）
// ═══════════════════════════════════════════════════════════════
extern "C" {

// ── 创建窗口 ──────────────────────────────────────────────
__attribute__((visibility("default"))) void* ohos_create_window(WindowOptions* opts) {
    if (!opts) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI", "ohos_create_window: null opts");
        return nullptr;
    }
    if (!g_etsReady) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI", "ohos_create_window: ETS not ready");
        return nullptr;
    }

    //int reqId = g_nextReqId++;
    int reqId;
    if (opts->isMainform == 1) {
        reqId = 1;  // 主窗固定 reqId=1，不消耗计数器
    } else {
        reqId = ++g_nextReqId;  // 子窗从 2 递增
    }
    char xcId[64];
    snprintf(xcId, sizeof(xcId), "xc_fpg_%d", reqId);

    int vpW =  opts->width;
    int vpH =  opts->height;
    int vpX =  opts->left;
    int vpY =  opts->top;

    auto* req = new XComponentRequest();
    req->reqId      = reqId;
    req->nativeWin  = nullptr;
    req->widthPhys  = vpW;
    req->heightPhys = vpH;
    req->done       = false;
    req->failed     = false;
    strncpy(req->xcId, xcId, sizeof(req->xcId) - 1);
    req->xcId[sizeof(req->xcId) - 1] = '\0';

    {
        std::lock_guard<std::mutex> lock(g_xcMutex);
        g_xcReqs[reqId] = req;
    }

    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "ohos_create_window: req=%{public}d xcId=%{public}s w=%{public}d h=%{public}d pos=(%{public}d,%{public}d)",
        reqId, xcId, opts->width, opts->height, opts->left, opts->top);

    auto* cmd = new NativeCommandData();
    cmd->type   = NATIVE_CMD_CREATE_WINDOW;
    cmd->reqId  = reqId;
    cmd->x      = vpX;
    cmd->y      = vpY;
    cmd->width  = vpW;
    cmd->height = vpH;
    cmd->windowAttributes = opts->windowAttributes;
    cmd->windowType       = opts->windowType;
    cmd->surfaceId = opts->surfaceId;
    strncpy(cmd->xcId, xcId, sizeof(cmd->xcId) - 1);
    cmd->xcId[sizeof(cmd->xcId) - 1] = '\0';
    strncpy(cmd->title, opts->title, sizeof(cmd->title) - 1);
    cmd->title[sizeof(cmd->title) - 1] = '\0';

    SendNativeCommand(cmd);

    {
        std::unique_lock<std::mutex> lock(g_xcMutex);
        if (!g_xcCV.wait_for(lock, std::chrono::seconds(10),
            [req] { return req->done || req->failed; })) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI",
                "ohos_create_window TIMEOUT for req %{public}d", reqId);
            auto* cleanup = new NativeCommandData();
            cleanup->type = NATIVE_CMD_DESTROY_WINDOW;
            cleanup->reqId = reqId;
            SendNativeCommand(cleanup);
            g_xcReqs.erase(reqId);
            delete req;
            return nullptr;
        }
    }

    OHNativeWindow* win = req->nativeWin;
    g_xcReqs.erase(reqId);

    if (win) {
        {
            std::lock_guard<std::mutex> lock(g_winMutex);
            g_winMap[reqId] = win;
            g_winRects[reqId] = { vpX, vpY, vpW, vpH };
            OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
                "ohos_create_window SUCCESS: req=%{public}d win=%{public}p", reqId, win);
        }
        // 补送创建握手段被丢弃的 resize（ETS 上报时本句柄尚未登记）：
        // 登记句柄后立即注入一次，保证 Pascal 按真实尺寸重建缓冲（渲染/点击 1:1）
        SizeW pendingResize;
        bool hasPendingResize = false;
        {
            std::lock_guard<std::mutex> lk(g_resizeMutex);
            auto pit = g_pendingResize.find(reqId);
            if (pit != g_pendingResize.end()) {
                pendingResize = pit->second;
                hasPendingResize = true;
                g_pendingResize.erase(pit);
                g_lastResize[reqId] = pendingResize;
                g_surfaceSize[reqId] = pendingResize;   // 渲染面权威尺寸
            }
        }
        if (hasPendingResize && pendingResize.w > 0 && pendingResize.h > 0) {
            if (g_inject_resize)
                g_inject_resize(win, pendingResize.w, pendingResize.h);
            int rc = OH_NativeWindow_NativeWindowHandleOpt(
                win, SET_BUFFER_GEOMETRY, pendingResize.w, pendingResize.h);
            OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
                "replay pending resize req=%{public}d %{public}dx%{public}d (rc=%{public}d)",
                reqId, pendingResize.w, pendingResize.h, rc);
        }
    } else {
        auto* cleanup = new NativeCommandData();
        cleanup->type = NATIVE_CMD_DESTROY_WINDOW;
        cleanup->reqId = reqId;
        SendNativeCommand(cleanup);
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI",
            "ohos_create_window FAILED: no native window for req %{public}d", reqId);
    }

    delete req;
    return win;
}

// ── 销毁窗口 ──────────────────────────────────────────────
__attribute__((visibility("default"))) void ohos_destroy_window(void* handle) {
    if (!handle) return;
    int reqId = -1;
    OHNativeWindow* win = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_winMutex);
        for (auto it = g_winMap.begin(); it != g_winMap.end(); ++it) {
            if (it->second == handle) {
                reqId = it->first;
                win = it->second;
                g_winMap.erase(it);
                break;
            }
        }
    }
    if (win) {
        OH_NativeWindow_DestroyNativeWindow(win);
        OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
            "ohos_destroy_window: native window destroyed req=%{public}d", reqId);
    }
    {
        std::lock_guard<std::mutex> lock(g_winMutex);
        g_winRects.erase(reqId);
        g_xcReqs.erase(reqId);
    }
    {
        std::lock_guard<std::mutex> lk(g_resizeMutex);
        g_lastResize.erase(reqId);
    }
    if (reqId >= 0) {
        auto* cmd = new NativeCommandData();
        cmd->type  = NATIVE_CMD_DESTROY_WINDOW;
        cmd->reqId = reqId;
        SendNativeCommand(cmd);
    }
}

// ── 调整窗口大小 ──────────────────────────────────────────
__attribute__((visibility("default"))) void ohos_resize_window(void* handle, int w, int h) {
    int reqId = FindReqIdByHandle(handle);
    // 缓冲几何以 ETS 上报的 surface 尺寸为权威：被系统强制最大化时 Pascal 会用
    // 建窗前的旧逻辑尺寸（如 1344x831）覆盖几何 → buffer 池被钉死在旧尺寸 →
    // 合成器把画面放大。存在权威值时忽略传入值（窗口 resize 语义仍按下方命令
    // 转发给 ETS，不受影响）。
    int geomW = w;
    int geomH = h;
    if (reqId >= 0) {
        std::lock_guard<std::mutex> lk(g_resizeMutex);
        auto sit = g_surfaceSize.find(reqId);
        if (sit != g_surfaceSize.end() && sit->second.w > 0 && sit->second.h > 0) {
            geomW = sit->second.w;
            geomH = sit->second.h;
        }
    }
    if (handle && geomW > 0 && geomH > 0)
        OH_NativeWindow_NativeWindowHandleOpt((OHNativeWindow*)handle, SET_BUFFER_GEOMETRY, geomW, geomH);
    if (reqId >= 0) {
        auto* cmd = new NativeCommandData();
        cmd->type   = NATIVE_CMD_RESIZE_WINDOW;
        cmd->reqId  = reqId;
        cmd->width  = w;
        cmd->height = h;
        OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
            "ohos_resize_window: req=%{public}d client=%{public}dx%{public}d geom=%{public}dx%{public}d",
            reqId, w, h, geomW, geomH);
        SendNativeCommand(cmd);
    }
}

// ── 移动窗口 ──────────────────────────────────────────────
__attribute__((visibility("default"))) void ohos_move_window(void* handle, int x, int y) {
    int reqId = FindReqIdByHandle(handle);
    if (reqId < 0) return;
    auto* cmd = new NativeCommandData();
    cmd->type = NATIVE_CMD_MOVE_WINDOW;
    cmd->reqId = reqId;
    cmd->x = x;
    cmd->y = y;
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "ohos_move_window: handle=%{public}p x=%{public}d y=%{public}d", handle, x, y);
    SendNativeCommand(cmd);
}

// ── 设置窗口可见性 ────────────────────────────────────────
__attribute__((visibility("default"))) void ohos_set_window_visible(void* handle, int visible) {
    int reqId = FindReqIdByHandle(handle);
    if (reqId < 0) return;
    int cmdType = visible ? NATIVE_CMD_SHOW_WINDOW : NATIVE_CMD_HIDE_WINDOW;
    auto* cmd = new NativeCommandData();
    cmd->type = cmdType;
    cmd->reqId = reqId;
    SendNativeCommand(cmd);
}

// ── Modal 窗口跟踪 ────────────────────────────────────────
__attribute__((visibility("default"))) void ohos_set_modal_window(void* handle) {
    g_modalReqId = handle ? FindReqIdByHandle(handle) : -1;
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "ohos_set_modal_window: handle=%{public}p reqId=%{public}d", handle, g_modalReqId);
}

// ── 抖动窗口 (modal 反馈) ────────────────────────────────
__attribute__((visibility("default"))) void ohos_shake_window(void* handle) {
    int reqId = FindReqIdByHandle(handle);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "ohos_shake_window: handle=%p reqId=%d", handle, reqId);
    if (reqId < 0) return;
    auto* cmd = new NativeCommandData();
    cmd->type = NATIVE_CMD_SHAKE_WINDOW;
    cmd->reqId = reqId;
    SendNativeCommand(cmd);
}

// ── 指针样式（统一 ArkTS）─────────────────────────────────
__attribute__((visibility("default"))) int ohos_set_pointer_style(void* handle, int style) {
    auto* cmd = new NativeCommandData();
    memset(cmd, 0, sizeof(*cmd));
    cmd->type = NATIVE_CMD_SET_POINTER_STYLE;
    cmd->reqId = FindReqIdByHandle(handle);
    cmd->x = style;
    SendNativeCommand(cmd);
    return 0;
}

// ── 剪贴板 pasteboard + UDMF ──────────────────────────────────────────────
__attribute__((visibility("default"))) int ohos_clipboard_set_text(const char* text) {
    if (!text) return -1;
    OH_Pasteboard* pb = OH_Pasteboard_Create();
    if (!pb) return -1;
    OH_UdmfData* data = OH_UdmfData_Create();
    OH_UdmfRecord* rec = OH_UdmfRecord_Create();
    OH_UdsPlainText* pt = OH_UdsPlainText_Create();
    int rc = -1;
    if (data && rec && pt) {
        if (OH_UdsPlainText_SetContent(pt, text) == 0 &&
            OH_UdmfRecord_AddPlainText(rec, pt) == 0 &&
            OH_UdmfData_AddRecord(data, rec) == 0) {
            rc = OH_Pasteboard_SetData(pb, data);
        }
    }
    if (pt) OH_UdsPlainText_Destroy(pt);
    if (rec) OH_UdmfRecord_Destroy(rec);
    if (data) OH_UdmfData_Destroy(data);
    if (pb) OH_Pasteboard_Destroy(pb);
    return rc;
}

__attribute__((visibility("default"))) char* ohos_clipboard_get_text(void) {
    OH_Pasteboard* pb = OH_Pasteboard_Create();
    if (!pb) return nullptr;
    int status = 0;
    OH_UdmfData* data = nullptr;
    for (int attempt = 0; attempt < 2; ++attempt) {
        if (data) { OH_UdmfData_Destroy(data); data = nullptr; }
        data = OH_Pasteboard_GetData(pb, &status);
        if (data && status == 0) break;
        usleep(50 * 1000);
    }
    char* out = nullptr;
    if (data && status == 0) {
        OH_UdsPlainText* pt = OH_UdsPlainText_Create();
        if (pt) {
            if (OH_UdmfData_GetPrimaryPlainText(data, pt) == 0) {
                const char* c = OH_UdsPlainText_GetContent(pt);
                if (c) out = strdup(c);
            }
            OH_UdsPlainText_Destroy(pt);
        }
    }
    if (data) OH_UdmfData_Destroy(data);
    if (pb) OH_Pasteboard_Destroy(pb);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "clipboard_get: status=%{public}d len=%{public}d", status, out ? (int)strlen(out) : -1);
    return out;   // strdup — freed by Pascal via libc free (cfree)
}

// ──── 用户目录 ────
__attribute__((visibility("default"))) char* ohos_get_user_dir(int dirType) {
    char base[512];
    // 优先使用 ArkTS context.filesDir 传入的真实沙箱路径
    if (!g_sandboxFilesDir.empty()) {
        snprintf(base, sizeof(base), "%s", g_sandboxFilesDir.c_str());
    } else {
        const char* home = getenv("HOME");
        if (home && home[0] != '\0') {
            snprintf(base, sizeof(base), "%s", home);
        } else {
            snprintf(base, sizeof(base), "/data/storage/el2/base/haps/entry/files");
        }
    }    
    char out[640];
    switch (dirType) {
        case 0: snprintf(out, sizeof(out), "%s", base); break; //文件目录
        case 1: snprintf(out, sizeof(out), "%s", g_sandboxCacheDir.c_str()); break; //缓存目录
        case 2: snprintf(out, sizeof(out), "%s", g_sandboxTempDir.c_str()); break; //临时目录
        case 3: snprintf(out, sizeof(out), "%s", g_sandboxResourceDir.c_str()); break; //资源目录
        case 4: snprintf(out, sizeof(out), "%s", g_sandboxDatabaseDir.c_str()); break; //数据库目录
        case 5: snprintf(out, sizeof(out), "%s", g_sandboxPreferencesDir.c_str()); break; //偏好设置目录
        case 6: snprintf(out, sizeof(out), "%s", g_sandboxBundleCodeDir.c_str()); break; //安装包目录
        case 7: snprintf(out, sizeof(out), "%s", g_sandboxDistributedFilesDir.c_str()); break; //分布式文件目录
        case 8: snprintf(out, sizeof(out), "%s", g_sandboxCloudFileDir.c_str()); break; //云文件目录
        case 101: snprintf(out, sizeof(out), "%s/Downloads", base); break;
        case 102: snprintf(out, sizeof(out), "%s/Documents", base); break;
        default: snprintf(out, sizeof(out), "%s", base); break;
    }
    if (dirType>100) {
        char tmp[640];
        snprintf(tmp, sizeof(tmp), "%s", out);
        for (char* p = tmp + 1; *p; ++p) {
            if (*p == '/') {
                *p = '\0';
                mkdir(tmp, 0755);
                *p = '/';
            }
        }
        mkdir(tmp, 0755);
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "get_user_dir: type=%{public}d -> %{public}s", dirType, out);
    return strdup(out);
}

// ── 显示/隐藏软键盘 (Pascal → ETS) ─────────────────────────
__attribute__((visibility("default")))
void ohos_bridge_show_keyboard(int show) {
    napi_threadsafe_function kb = GetKbTsfn();
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "bridge_show_keyboard: show=%{public}d kb=%{public}p", show, (void*)kb);
    auto* cmd = new NativeCommandData();
    memset(cmd, 0, sizeof(NativeCommandData));
    cmd->type = NATIVE_CMD_SHOW_KEYBOARD;
    cmd->x = show;
    cmd->reqId = 0;
    if (kb) {
        napi_call_threadsafe_function(kb, cmd, napi_tsfn_blocking);
    } else {
        delete cmd;
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
            "bridge_show_keyboard: no kb callback, dropped");
    }
}

// ── 系统托盘命令 (Pascal → ETS，经 SendNativeCommand) ────────────
__attribute__((visibility("default")))
void ohos_tray_add(const char* title, int iconIndex) {
    auto* cmd = new NativeCommandData();
    memset(cmd, 0, sizeof(NativeCommandData));
    cmd->type = NATIVE_CMD_TRAY_ADD;
    cmd->x = iconIndex;
    if (title) strncpy(cmd->title, title, sizeof(cmd->title) - 1);
    SendNativeCommand(cmd);
}

__attribute__((visibility("default")))
void ohos_tray_set_menu(const char* json) {
    auto* cmd = new NativeCommandData();
    memset(cmd, 0, sizeof(NativeCommandData));
    cmd->type = NATIVE_CMD_TRAY_SET_MENU;
    if (json) strncpy(cmd->payload, json, sizeof(cmd->payload) - 1);
    SendNativeCommand(cmd);
}

__attribute__((visibility("default")))
void ohos_tray_remove(void) {
    auto* cmd = new NativeCommandData();
    memset(cmd, 0, sizeof(NativeCommandData));
    cmd->type = NATIVE_CMD_TRAY_REMOVE;
    SendNativeCommand(cmd);
}

// ── 打开 URL / 文档（Pascal → C++ → ArkTS）────────────────────────
// Pascal fpgOpenURL 经 dlsym 调用本函数（符号必须 default 可见）。
// OHOS 沙箱禁止直接起外部进程，实际打开必须经 ArkTS openLink /
// startAbility(viewData)，故经 TSFN 封送到 JS 线程交给注册的回调。
// Pascal-facing symbol：fpg_utils_impl.inc fpgOpenURL → ohos_open_url
__attribute__((visibility("default")))
void ohos_open_url(const char* url) {
    if (url == nullptr || url[0] == '\0') {
        return;
    }
    std::lock_guard<std::mutex> lk(g_open_url_mtx);
    if (g_open_url_tsfn == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
            "ohos_open_url: no ArkTS callback registered; ignoring '%{public}s'", url);
        return;
    }
    auto* call = new OpenUrlCall{ std::string(url) };
    napi_status st = napi_call_threadsafe_function(g_open_url_tsfn, call, napi_tsfn_nonblocking);
    if (st != napi_ok) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI",
            "ohos_open_url: tsfn call failed: %d", st);
        delete call;
    }
}

// ── 系统拖拽：起拖 ──
__attribute__((visibility("default")))
int64_t ohos_drag_start(const char* dataJson, const char* extraJson) {
    if (!g_etsReady) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI", "ohos_drag_start: ETS not ready");
        return 0;
    }
    int64_t sid = g_nextSessionId++;
    auto* cmd = new NativeCommandData();
    memset(cmd, 0, sizeof(NativeCommandData));
    cmd->type  = NATIVE_CMD_DRAG_START;
    cmd->reqId = (int)(sid & 0x7FFFFFFF);
    if (dataJson)
        strncpy(cmd->payload, dataJson, sizeof(cmd->payload) - 1);
    cmd->payload[sizeof(cmd->payload) - 1] = '\0';
    if (extraJson)
        strncpy(cmd->title, extraJson, sizeof(cmd->title) - 1);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "ohos_drag_start: session=%lld", (long long)sid);
    SendNativeCommand(cmd);
    return sid;
}

// ── 系统拖拽：窗口拖入开关 ──
__attribute__((visibility("default")))
void ohos_set_dnd_enabled(void* handle, int enabled) {
    int reqId = FindReqIdByHandle(handle);
    if (reqId < 0) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
            "ohos_set_dnd_enabled: no reqId for handle %p", handle);
        return;
    }
    {
        std::lock_guard<std::mutex> lk(g_dndMutex);
        g_dndEnabled[reqId] = (enabled != 0);
    }
    auto* cmd = new NativeCommandData();
    memset(cmd, 0, sizeof(NativeCommandData));
    cmd->type = NATIVE_CMD_SET_DND_ENABLED;
    cmd->reqId = reqId;
    cmd->x = enabled;
    SendNativeCommand(cmd);
}

// ── 窗口属性联动 ────────────────────
__attribute__((visibility("default")))
void ohos_set_window_state(void* handle, int state) {
    int reqId = FindReqIdByHandle(handle);
    if (reqId < 0) return;
    auto* cmd = new NativeCommandData();
    memset(cmd, 0, sizeof(NativeCommandData));
    cmd->type = NATIVE_CMD_SET_WINDOW_STATE;
    cmd->reqId = reqId;
    cmd->x = state;
    SendNativeCommand(cmd);
}

// ── 查询缓存的窗口状态（Pascal 调用）─────────────────────────
__attribute__((visibility("default")))
int32_t ohos_get_window_state(void* handle) {
    int reqId = FindReqIdByHandle(handle);
    if (reqId < 0) return 4;  // 默认 FLOATING=4
    std::lock_guard<std::mutex> lock(g_winMutex);
    auto it = g_winStateCache.find(reqId);
    return (it != g_winStateCache.end()) ? it->second : 4;  // 默认 FLOATING
}

__attribute__((visibility("default")))
void ohos_set_window_opacity(void* handle, float opacity) {
    int reqId = FindReqIdByHandle(handle);
    if (reqId < 0) return;
    auto* cmd = new NativeCommandData();
    memset(cmd, 0, sizeof(NativeCommandData));
    cmd->type = NATIVE_CMD_SET_WINDOW_OPACITY;
    cmd->reqId = reqId;
    cmd->x = (int)(opacity * 1000.0f + 0.5f);
    SendNativeCommand(cmd);
}

__attribute__((visibility("default")))
void ohos_set_window_title(void* handle, const char* title) {
    int reqId = FindReqIdByHandle(handle);
    if (reqId < 0) return;
    auto* cmd = new NativeCommandData();
    memset(cmd, 0, sizeof(NativeCommandData));
    cmd->type = NATIVE_CMD_SET_WINDOW_TITLE;
    cmd->reqId = reqId;
    if (title) strncpy(cmd->title, title, sizeof(cmd->title) - 1);
    cmd->title[sizeof(cmd->title) - 1] = '\0';
    SendNativeCommand(cmd);
}

__attribute__((visibility("default")))
void ohos_set_window_attributes(void* handle, int attributes) {
    int reqId = FindReqIdByHandle(handle);
    OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
        "ohos_set_window_attributes: handle=%p attrs=%d reqId=%{public}d", handle, attributes, reqId);
    if (reqId < 0) return;
    auto* cmd = new NativeCommandData();
    memset(cmd, 0, sizeof(NativeCommandData));
    cmd->type = NATIVE_CMD_SET_WINDOW_ATTRIBUTES;
    cmd->reqId = reqId;
    cmd->x = attributes;
    SendNativeCommand(cmd);
}

// ── 系统文件选择器（Pascal → C++ → ETS）────────────────────
// 拉起系统 FileManager/Gallery/Audio 选择器，无需申请权限。
//   pickerType: 0=文档(DocumentViewPicker) 1=图片/视频(PhotoViewPicker) 2=音频(AudioViewPicker) 3=文档另存为(DocumentViewPicker.save，回传可写 URI)
//   optsJson: 紧凑 JSON，如 {"suffix":[".txt",".pdf"],"max":5} / {"mime":"image","max":1}
//             type=3 时 {"name":"ESC.INF","suffix":[".inf"]}
//   reqId: Pascal 生成的递增整数，ETS 完成后经 notifyFilePickerResult 原样回传。
// 结果回传不经过 FpBridgeCppApi（不改共享结构体布局），由 NATIVE_CMD_FILE_PICKER
// 走既有 tsfn 通道；回传回调槽 file_picker_result 允许 Pascal 侧晚注册（见下方 setter）。
__attribute__((visibility("default")))
void ohos_show_file_picker(int reqId, int pickerType, const char* optsJson) {
    auto* cmd = new NativeCommandData();
    memset(cmd, 0, sizeof(NativeCommandData));
    cmd->type = NATIVE_CMD_FILE_PICKER;
    cmd->reqId = reqId;
    cmd->x = pickerType;
    if (optsJson) {
        strncpy(cmd->payload, optsJson, sizeof(cmd->payload) - 1);
        cmd->payload[sizeof(cmd->payload) - 1] = '\0';
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "ohos_show_file_picker: reqId=%{public}d type=%{public}d", reqId, pickerType);
    SendNativeCommand(cmd);
}

// ── 系统文件流（Pascal TOhosFileStream → C++ → ETS fs.*Sync）────────
// 对 file://docs/... 等 picker 授权 URI 的同步随机读写（pread/pwrite 语义）。
//   op:     FileIoOp（0=open 1=read 2=write 3=truncate 4=fsync 5=close 6=stat 7=delete）
//   arg:    open=OpenMode 位掩码；read/write/truncate=ETS 文件句柄 id
//   offset: read/write 文件偏移（pread/pwrite，不移动共享句柄位置）
//   length: read 字节数 / truncate 新大小
//   uri:    open/stat/delete 目标 URI（其余操作可空）
//   data:   write 数据；dataLen 字节（所有权转移：C++ 复制后 delete[]）
// 结果由 ETS 经 notifyFileIoResult 回传（json + 可选 ArrayBuffer）。
__attribute__((visibility("default")))
void ohos_file_io(int reqId, int op, int arg, int64_t offset, int64_t length,
                  const char* uri, const void* data, int dataLen) {
    auto* cmd = new NativeCommandData();
    cmd->type = NATIVE_CMD_FILE_IO;
    cmd->reqId = reqId;
    cmd->x = op;
    cmd->y = arg;
    cmd->ioff = offset;
    cmd->ilen = length;
    if (uri) {
        strncpy(cmd->payload, uri, sizeof(cmd->payload) - 1);
        cmd->payload[sizeof(cmd->payload) - 1] = '\0';
    }
    if (data != nullptr && dataLen > 0) {
        cmd->binLen = dataLen;
        cmd->bin = new uint8_t[dataLen];
        memcpy(cmd->bin, data, dataLen);
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "ohos_file_io: reqId=%{public}d op=%{public}d arg=%{public}d "
        "off=%{public}lld len=%{public}lld bin=%{public}d",
        reqId, op, arg, (long long)offset, (long long)length, dataLen);
    SendNativeCommand(cmd);
}

// ── 首帧上屏通知（Pascal 第一次 FlushBuffer 后调用）────────
// ETS 收到后打开 XComponent 显示门（contentReady），消除黑屏闪现。
// 由 fp_bridge_init 填出（v12，经桥接表 notify_first_frame 槽位）。
__attribute__((visibility("default")))
void ohos_notify_first_frame(void* handle) {
    int reqId = FindReqIdByHandle(handle);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "ohos_notify_first_frame: handle=%{public}p reqId=%{public}d", handle, reqId);
    if (reqId < 0) return;
    auto* cmd = new NativeCommandData();
    memset(cmd, 0, sizeof(NativeCommandData));
    cmd->type = NATIVE_CMD_FIRST_FRAME;
    cmd->reqId = reqId;
    SendNativeCommand(cmd);
}

// ── 主窗口装饰尺寸 ──────────────────
__attribute__((visibility("default"))) void ohos_get_main_window_decoration(int* decW, int* decH) {
    if (decW) *decW = g_mainDecW;
    if (decH) *decH = g_mainDecH;
}

__attribute__((visibility("default"))) void ohos_get_window_decoration(void* handle, int* decW, int* decH) {
    if (decW) *decW = 0;
    if (decH) *decH = 0;
    if (!handle) return;
    int reqId = FindReqIdByHandle(handle);
    if (reqId < 0) return;
    std::lock_guard<std::mutex> lock(g_decMutex);
    auto it = g_winDec.find(reqId);
    if (it != g_winDec.end()) {
        if (decW) *decW = it->second.first;
        if (decH) *decH = it->second.second;
    }
}

// ── 定时器活动态通知 (Pascal → ETS) ──
__attribute__((visibility("default"))) void ohos_send_timer_state(int active) {
    auto* cmd = new NativeCommandData();
    memset(cmd, 0, sizeof(*cmd));
    cmd->type = NATIVE_CMD_TIMER_STATE;
    cmd->x = active;
    SendNativeCommand(cmd);
}

// ── 反向桥接入口（Pascal 调用，Pascal 主线程）──────────────
// ① 校验版本（首参数 version，与 Pascal TFpBridgeInitFn 严格一致）与必需函数；
// ② 缓存 Pascal 函数表并按槽位装载 g_inject_*；
// ③ 填出 C++ 函数表。
// 返回：0=成功；-1=版本不匹配；-2=必需函数缺失
__attribute__((visibility("default")))
int fp_bridge_init(int32_t version,
                   const FpBridgePascalApi* pascal_api,
                   FpBridgeCppApi* cpp_api) {
    if (!pascal_api || !cpp_api) return -2;
    if (version != OHOS_BRIDGE_VERSION) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI",
            "fp_bridge_init: version mismatch pascal=%d expect=%d",
            version, OHOS_BRIDGE_VERSION);
        return -1;
    }
    if (pascal_api->version != OHOS_BRIDGE_VERSION) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI",
            "fp_bridge_init: pascalApi.version mismatch pascal=%d expect=%d",
            pascal_api->version, OHOS_BRIDGE_VERSION);
        return -1;
    }
    if (!pascal_api->set_screen_size) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI",
            "fp_bridge_init: set_screen_size missing");
        return -2;
    }

    // 缓存 Pascal 函数表（按值拷贝；Pascal 线程写入，ETS 事件到达前完成）
    g_pascal = *pascal_api;

    // 装载 g_inject_*（ETS 事件处理器使用）
    g_inject_touch_to_win = (InjectTouchToWinFunc)g_pascal.inject_touch_to_window;
    g_inject_mouse        = (InjectMouseFunc)g_pascal.inject_mouse_event;
    g_inject_wheel        = (InjectWheelFunc)g_pascal.inject_wheel_event;
    g_inject_hover        = (InjectHoverFunc)g_pascal.inject_hover_event;
    g_inject_key          = (InjectKeyFunc)g_pascal.inject_key_event;
    g_inject_resize       = (InjectResizeFunc)g_pascal.inject_window_resized;
    g_inject_moved        = (InjectWindowMovedFunc)g_pascal.inject_window_moved;
    g_inject_closed       = (InjectWindowClosedFunc)g_pascal.inject_window_closed;
    g_can_close           = (CanCloseFunc)g_pascal.can_close;
    g_force_refresh       = (ForceWindowRefreshFunc)g_pascal.force_window_refresh;
    g_inject_text         = (InjectTextFunc)g_pascal.inject_text;
    g_inject_delete       = (InjectDeleteFunc)g_pascal.inject_delete_chars;
    g_inject_delete_right = (InjectDeleteFunc)g_pascal.inject_delete_right_chars;
    g_inject_move_cursor  = (InjectMoveCursorFunc)g_pascal.inject_move_cursor;
    g_inject_tray         = (InjectTrayEventFunc)g_pascal.inject_tray_event;
    g_inject_drag         = (InjectDragEventFunc)g_pascal.inject_drag_event;
    g_inject_drop         = (InjectDropFunc)g_pascal.drag_process_drop;
    g_inject_drag_end     = (InjectDragEndFunc)g_pascal.inject_drag_end;
    g_dispatch            = (DispatchFn)g_pascal.dispatch;   // v6 动态分发入口
    g_dispatch_free       = (DispatchFreeFn)g_pascal.dispatch_free;   // v7 释放入口返回的 PChar
    g_set_launch_params   = (SetLaunchParamsFn)g_pascal.set_launch_params;
    g_inject_app_args     = (InjectAppArgsFn)g_pascal.inject_app_args;

    // 填出 C++ 函数表（命名回调）
    memset(cpp_api, 0, sizeof(*cpp_api));
    cpp_api->version                   = OHOS_BRIDGE_VERSION;
    cpp_api->create_window             = (void*)ohos_create_window;
    cpp_api->destroy_window            = (void*)ohos_destroy_window;
    cpp_api->resize_window             = (void*)ohos_resize_window;
    cpp_api->move_window               = (void*)ohos_move_window;
    cpp_api->set_window_visible        = (void*)ohos_set_window_visible;
    cpp_api->set_modal_window          = (void*)ohos_set_modal_window;
    cpp_api->set_pointer_style         = (void*)ohos_set_pointer_style;
    cpp_api->shake_window              = (void*)ohos_shake_window;
    cpp_api->show_keyboard             = (void*)ohos_bridge_show_keyboard;
    cpp_api->clipboard_set_text        = (void*)ohos_clipboard_set_text;
    cpp_api->clipboard_get_text        = (void*)ohos_clipboard_get_text;
    cpp_api->get_user_dir              = (void*)ohos_get_user_dir;
    cpp_api->get_main_window_decoration = (void*)ohos_get_main_window_decoration;
    cpp_api->get_window_decoration = (void*)ohos_get_window_decoration;
    cpp_api->drag_start          = (void*)ohos_drag_start;
    cpp_api->set_dnd_enabled     = (void*)ohos_set_dnd_enabled;
    cpp_api->set_window_state    = (void*)ohos_set_window_state;
    cpp_api->set_window_opacity  = (void*)ohos_set_window_opacity;
    cpp_api->set_window_title    = (void*)ohos_set_window_title;
    cpp_api->set_window_attributes = (void*)ohos_set_window_attributes;
    cpp_api->tray_add              = (void*)ohos_tray_add;
    cpp_api->tray_set_menu         = (void*)ohos_tray_set_menu;
    cpp_api->tray_remove           = (void*)ohos_tray_remove;
    cpp_api->dispatch_result   = (void*)ohos_dispatch_result;   // v6 分发结果回传
    cpp_api->get_window_state  = (void*)ohos_get_window_state;  // v10 查询缓存的窗口状态
    cpp_api->open_url          = (void*)ohos_open_url;          // v11 打开 URL/文档
    cpp_api->notify_first_frame = (void*)ohos_notify_first_frame;  // v12 首帧上屏通知
    cpp_api->show_file_picker = (void*)ohos_show_file_picker;
    cpp_api->arkts_invoke = (void*)ohos_arkts_invoke;  // v13：Pascal → ArkTS 反向调用

    g_bridgeReady = true;
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "fp_bridge_init OK (v%d), pascal=%p", OHOS_BRIDGE_VERSION, (void*)pascal_api);

    return 0;
}

} // extern "C"

// ═══════════════════════════════════════════════════════════════
//  线程安全函数回调 — 在 JS 线程上执行
// ═══════════════════════════════════════════════════════════════

void NativeCallbackCallJS(napi_env env, napi_value jsCb, void* context, void* data) {
    auto* cmd = (NativeCommandData*)data;

    napi_value arg;
    napi_create_object(env, &arg);

    napi_value typeVal, reqIdVal, xVal, yVal, wVal, hVal, attrVal, wtypeVal, xcIdVal;
    napi_create_int32(env, cmd->type, &typeVal);
    napi_set_named_property(env, arg, "type", typeVal);
    napi_create_int32(env, cmd->reqId, &reqIdVal);
    napi_set_named_property(env, arg, "reqId", reqIdVal);
    napi_create_int32(env, cmd->x, &xVal);
    napi_set_named_property(env, arg, "x", xVal);
    napi_create_int32(env, cmd->y, &yVal);
    napi_set_named_property(env, arg, "y", yVal);
    napi_create_int32(env, cmd->width, &wVal);
    napi_set_named_property(env, arg, "width", wVal);
    napi_create_int32(env, cmd->height, &hVal);
    napi_set_named_property(env, arg, "height", hVal);
    napi_create_int32(env, cmd->windowAttributes, &attrVal);
    napi_set_named_property(env, arg, "windowAttributes", attrVal);
    napi_create_int32(env, cmd->windowType, &wtypeVal);
    napi_set_named_property(env, arg, "windowType", wtypeVal);
    napi_value sidVal;
    char sidBuf[32];
    snprintf(sidBuf, sizeof(sidBuf), "%llu", (unsigned long long)cmd->surfaceId);
    napi_create_string_utf8(env, sidBuf, NAPI_AUTO_LENGTH, &sidVal);
    napi_set_named_property(env, arg, "surfaceId", sidVal);
    napi_create_string_utf8(env, cmd->xcId, NAPI_AUTO_LENGTH, &xcIdVal);
    napi_set_named_property(env, arg, "xcId", xcIdVal);
    napi_value titleVal;
    napi_create_string_utf8(env, cmd->title, NAPI_AUTO_LENGTH, &titleVal);
    napi_set_named_property(env, arg, "title", titleVal);
    napi_value payloadVal;
    napi_create_string_utf8(env, cmd->payload, NAPI_AUTO_LENGTH, &payloadVal);
    napi_set_named_property(env, arg, "payload", payloadVal);

    // 文件流命令：64 位偏移/长度 + 写数据 ArrayBuffer（仅 NATIVE_CMD_FILE_IO 使用）
    napi_value offVal, lenVal;
    napi_create_int64(env, cmd->ioff, &offVal);
    napi_set_named_property(env, arg, "offset", offVal);
    napi_create_int64(env, cmd->ilen, &lenVal);
    napi_set_named_property(env, arg, "length", lenVal);
    napi_value dataVal;
    void* dataPtr = nullptr;
    if (cmd->binLen > 0) {
        napi_create_arraybuffer(env, cmd->binLen, &dataPtr, &dataVal);
        if (dataPtr != nullptr && cmd->bin != nullptr)
            memcpy(dataPtr, cmd->bin, cmd->binLen);
    } else {
        napi_create_arraybuffer(env, 0, &dataPtr, &dataVal);
    }
    napi_set_named_property(env, arg, "data", dataVal);

    napi_call_function(env, nullptr, jsCb, 1, &arg, nullptr);
    delete[] static_cast<uint8_t*>(cmd->bin);
    delete cmd;
}

// ═══════════════════════════════════════════════════════════════
//  动态分发（Registry-Dispatch）— Pascal 完成回调桥（Pascal → JS）
// ═══════════════════════════════════════════════════════════════

// Pascal Handler 完成时调用（任意线程：UI 线程或异步 Worker）。
// DispatchResultCallJS（Promise resolve/reject）在 napi_init.cpp（NAPI 侧）。
extern "C" __attribute__((visibility("default")))
void ohos_dispatch_result(const char* jobId, const char* resultJson, int failed) {
    if (jobId == nullptr || g_dispatchTsfn == nullptr) return;
    auto* d = new DispatchResultData();
    d->jobId = jobId;
    d->result = (resultJson != nullptr) ? resultJson : "";
    d->failed = failed;
    napi_status st = napi_call_threadsafe_function(g_dispatchTsfn, d, napi_tsfn_blocking);
    if (st != napi_ok) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "fpGUI",
            "dispatch_result: tsfn call failed st=%d", (int)st);
        delete d;
    }
}