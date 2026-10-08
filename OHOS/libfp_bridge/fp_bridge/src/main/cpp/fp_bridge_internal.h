// fp_bridge 内部共享头（不对外，不入 fp_bridge.h ABI）
// ======================================================
// napi_init.cpp 与 fp_bridge.cpp 跨文件共享的结构/枚举/typedef/全局/辅助函数原型。
// 公共 ABI（fp_bridge.h）保持不变，Pascal 侧零改动。
#pragma once

#include <cstdint>
#include <atomic>
#include <map>
#include <mutex>
#include <condition_variable>
#include <string>
#include <vector>

#include <native_window/external_window.h>
#include "napi/native_api.h"
#include "fp_bridge.h"

// ── WindowOptions 结构体（必须精确匹配 fpg_ohos.pas 的 TOHOSWindowOptions）──
// Pascal 侧使用 {$packrecords C} (4 字节对齐)
#pragma pack(push, 4)
struct WindowOptions {
    int32_t windowType;
    int32_t windowAttributes;
    int32_t windowState;
    int32_t isMainform;
    int32_t mouseCursor;
    float   opacity;
    int32_t left;
    int32_t top;
    int32_t width;
    int32_t height;
    char    title[256];
    uint64_t surfaceId;
};
#pragma pack(pop)

// ── 原生命令类型 ────────────────────────────────────────────
enum NativeCmdType {
    NATIVE_CMD_CREATE_WINDOW  = 0,
    NATIVE_CMD_MOVE_WINDOW    = 1,
    NATIVE_CMD_SHOW_WINDOW    = 2,
    NATIVE_CMD_HIDE_WINDOW    = 3,
    NATIVE_CMD_DESTROY_WINDOW = 4,
    NATIVE_CMD_SHAKE_WINDOW   = 5,
    NATIVE_CMD_SHOW_KEYBOARD  = 6,
    NATIVE_CMD_RESIZE_WINDOW  = 7,
    NATIVE_CMD_TRAY_ADD       = 8,
    NATIVE_CMD_TRAY_SET_MENU  = 9,
    NATIVE_CMD_TRAY_REMOVE    = 10,
    NATIVE_CMD_TIMER_STATE    = 11,
    NATIVE_CMD_SET_POINTER_STYLE = 12,
    NATIVE_CMD_DRAG_START       = 13,
    NATIVE_CMD_SET_DND_ENABLED  = 14,
    NATIVE_CMD_SET_WINDOW_STATE = 15,
    NATIVE_CMD_SET_WINDOW_OPACITY = 16,
    NATIVE_CMD_SET_WINDOW_TITLE = 17,
    NATIVE_CMD_SET_WINDOW_ATTRIBUTES = 18,
    NATIVE_CMD_FIRST_FRAME      = 19,   // 首帧上屏通知（Pascal FlushBuffer 成功后）
    NATIVE_CMD_FILE_PICKER      = 20,   // Pascal 请求拉起系统文件选择器（x=picker 类型，payload=optsJson）
    NATIVE_CMD_FILE_IO          = 21,   // Pascal 文件流操作（x=子操作，y=open 模式，offset/length/bin=数据）
};

// 文件流子操作（与 ETS FpgFileIo.ets、Pascal fpg_ohos_filestream.pas 一致）
enum FileIoOp {
    FILE_IO_OPEN      = 0,   // 打开（payload=URI，y=OpenMode 位掩码）→ 回复 handle + size
    FILE_IO_READ      = 1,   // 读（x=handle，offset/length）→ 回复 n + data
    FILE_IO_WRITE     = 2,   // 写（x=handle，offset，bin=data）→ 回复 n + size
    FILE_IO_TRUNCATE  = 3,   // 截断（x=handle，length=新大小）→ 回复 size
    FILE_IO_FSYNC     = 4,   // 刷盘（x=handle）
    FILE_IO_CLOSE     = 5,   // 关闭（x=handle）
    FILE_IO_STAT      = 6,   // 不开句柄取大小（payload=URI）→ 回复 size；不存在/无权限 code 非 0
    FILE_IO_DELETE    = 7    // 删除（payload=URI）
};

// ── 线程安全函数传递的命令数据结构 ──────────────────────────
struct NativeCommandData {
    int type;
    int reqId;
    int x, y;
    int width, height;
    int windowAttributes;
    int windowType;
    uint64_t surfaceId;
    char xcId[64];
    char title[256];
    char payload[4096];
    // 文件流（NATIVE_CMD_FILE_IO）专用：64 位偏移/长度 + 可变长二进制载荷。
    // 仅 C++ 内部构造/消费（Pascal 不感知此结构体），故扩字段无 ABI 风险。
    int64_t ioff = 0;
    int64_t ilen = 0;
    void* bin = nullptr;     // Pascal→ETS 写数据；NativeCallbackCallJS 转 ArrayBuffer 后 delete[]
    int binLen = 0;
};

// ── XComponent 就绪请求 ─────────────────────────────────
struct XComponentRequest {
    int reqId;
    char xcId[64];
    OHNativeWindow* nativeWin;
    int widthPhys;
    int heightPhys;
    bool done;
    bool failed;
};

struct WinRect { int x, y, w, h; };
struct SizeW   { int32_t w = 0, h = 0; };

// ── 打开 URL / 文档（Pascal → C++ → ArkTS）封送载荷 ──
struct OpenUrlCall {
    std::string url;
};

// ── 动态分发结果封送载荷（DispatchResultCallJS 消费）──
struct DispatchResultData {
    std::string jobId;
    std::string result;
    int failed;
};

// ── inject / 桥函数指针 typedef（fp_bridge_init 装载，NAPI 侧消费）──
typedef int (*InjectTouchToWinFunc)(void* winHandle, float x, float y, int action);
typedef int (*InjectMouseFunc)(void* winHandle, float x, float y, int action, int button);
typedef int (*InjectWheelFunc)(void* winHandle, float x, float y, int delta);
typedef int (*InjectHoverFunc)(void* winHandle, float x, float y);
typedef int (*InjectKeyFunc)(int keyCode, int action, int modifiers, unsigned int unicodeChar);
typedef int (*InjectTextFunc)(const char* text, int length);
typedef int (*InjectDeleteFunc)(int count);
typedef int (*InjectMoveCursorFunc)(int direction);
typedef int (*InjectResizeFunc)(void* winHandle, int w, int h);
typedef int (*InjectWindowMovedFunc)(void* winHandle, int x, int y);
typedef int (*InjectWindowClosedFunc)(void* winHandle);
typedef int (*CanCloseFunc)(void* winHandle);   // 1=可关 0=不可
typedef void (*ForceWindowRefreshFunc)(void* winHandle);
typedef int (*InjectTrayEventFunc)(int eventType, const char* menuId);
typedef int (*InjectDragEventFunc)(void* winHandle, int kind, float x, float y, const char* summaryJson);
typedef int (*InjectDropFunc)(void* winHandle, float x, float y, const char* recordsJson);
typedef int (*InjectDragEndFunc)(int64_t sessionId, int result);

typedef void (*SetLaunchParamsFn)(const char* payload);
typedef void (*InjectAppArgsFn)(const char* payload, const char* appArgs);
typedef char* (*DispatchFn)(const char* opType, const char* params);
typedef void  (*DispatchFreeFn)(char* p);

// v13：arkTS_Invoke 结果回传（Pascal 实现，JS 线程调用；快路径约定：拷贝+锁+SetEvent）
typedef void (*ArkTsInvokeResultFn)(const char* callId, const char* resultJson, int32_t failed);

// ── 共享全局（extern 声明；定义归一方）────────────────────
// 桥核心拥有（fp_bridge.cpp 定义）
extern InjectTouchToWinFunc g_inject_touch_to_win;
extern InjectMouseFunc      g_inject_mouse;
extern InjectWheelFunc      g_inject_wheel;
extern InjectHoverFunc      g_inject_hover;
extern InjectKeyFunc        g_inject_key;
extern InjectTextFunc       g_inject_text;
extern InjectDeleteFunc     g_inject_delete;
extern InjectDeleteFunc     g_inject_delete_right;
extern InjectMoveCursorFunc g_inject_move_cursor;
extern InjectResizeFunc     g_inject_resize;
extern InjectWindowMovedFunc  g_inject_moved;
extern InjectWindowClosedFunc g_inject_closed;
extern CanCloseFunc            g_can_close;
extern ForceWindowRefreshFunc g_force_refresh;
extern InjectTrayEventFunc   g_inject_tray;
extern InjectDragEventFunc   g_inject_drag;
extern InjectDropFunc        g_inject_drop;
extern InjectDragEndFunc     g_inject_drag_end;

extern FpBridgePascalApi      g_pascal;
extern std::atomic<bool>      g_bridgeReady;
extern std::map<int, bool>    g_dndEnabled;
extern std::mutex             g_dndMutex;
extern int64_t                g_nextSessionId;
extern std::map<int, XComponentRequest*> g_xcReqs;
extern std::mutex             g_xcMutex;
extern std::condition_variable g_xcCV;
extern std::map<int, OHNativeWindow*> g_winMap;
extern std::map<int, WinRect> g_winRects;
extern std::mutex             g_winMutex;
extern std::map<int, int>     g_winStateCache;
extern std::map<int, SizeW>   g_lastResize;    
extern std::map<int, SizeW>   g_pendingResize; // 句柄未登记时暂存的 resize（创建握手期）
extern std::map<int, SizeW>   g_surfaceSize;   // ETS 上报的渲染面(surface)权威尺寸
extern std::mutex             g_resizeMutex;   
extern int                    g_nextReqId;
extern int                    g_modalReqId;
extern int32_t                g_mainDecW;
extern int32_t                g_mainDecH;
extern std::map<int, std::pair<int32_t,int32_t>> g_winDec;
extern std::mutex             g_decMutex;
extern std::vector<napi_threadsafe_function> g_kbTsfnStack;
extern std::mutex             g_kbMutex;
extern SetLaunchParamsFn      g_set_launch_params;
extern std::string            g_pendingLaunchParams;
extern std::mutex             g_launchMutex;
extern InjectAppArgsFn        g_inject_app_args;
extern DispatchFn             g_dispatch;
extern DispatchFreeFn         g_dispatch_free;

// NAPI 侧拥有（napi_init.cpp 定义；桥核心经 extern 消费）
extern std::atomic<bool>      g_started;
extern std::atomic<bool>      g_etsReady;
extern float                  g_density;
extern float                  g_zoomScale;
extern napi_threadsafe_function g_tsfn;
extern std::string            g_sandboxFilesDir;
extern std::string            g_sandboxCacheDir;
extern std::string            g_sandboxTempDir;
extern std::string            g_sandboxResourceDir;
extern std::string            g_sandboxDatabaseDir;
extern std::string            g_sandboxPreferencesDir;
extern std::string            g_sandboxBundleCodeDir;
extern std::string            g_sandboxDistributedFilesDir;
extern std::string            g_sandboxCloudFileDir;
extern napi_threadsafe_function g_dispatchTsfn;
extern napi_threadsafe_function g_open_url_tsfn;
extern std::mutex             g_open_url_mtx;
extern void*                  g_pascalLibHandle;

// arkts_invoke（Pascal → ArkTS）：arkts_invoke.cpp 拥有（Init 创建一次）
extern napi_threadsafe_function g_invokeTsfn;

// ── 共享辅助函数原型（定义归 fp_bridge.cpp；NAPI 侧跨文件引用）──
OHNativeWindow* SurfaceIdToWindow(uint64_t sid, int w, int h);
int  FindReqIdByHandle(void* handle);
void SendNativeCommand(NativeCommandData* data);
napi_threadsafe_function GetKbTsfn();
void NativeCallbackCallJS(napi_env env, napi_value jsCb, void* context, void* data);

#ifdef __cplusplus
extern "C" {
#endif
// Pascal Handler 完成时调用（任意线程）；napi_init.cpp 守护线程亦调用
void ohos_dispatch_result(const char* jobId, const char* resultJson, int failed);
#ifdef __cplusplus
}
#endif

// ── arkts_invoke（Pascal → ArkTS 反向调用，v13；实现归 arkts_invoke.cpp）──
// 模块入口（napi_init.cpp 的 Init 调用；必须在 JS 线程：建 TSFN + 缓存 env/JS 线程 id）
void ArkInvokeInit(napi_env env);

// NAPI 注册函数（实现于 arkts_invoke.cpp；napi_init.cpp desc 表登记）
napi_value ArkInvoke_RegisterMethod(napi_env env, napi_callback_info info);
napi_value ArkInvoke_RegisterNamespace(napi_env env, napi_callback_info info);
napi_value ArkInvoke_RegisterDispatcher(napi_env env, napi_callback_info info);
napi_value ArkInvoke_UnregisterMethod(napi_env env, napi_callback_info info);
napi_value ArkInvoke_ClearMethods(napi_env env, napi_callback_info info);
napi_value ArkInvoke_ListMethods(napi_env env, napi_callback_info info);
napi_value ArkInvoke_InvokeLocal(napi_env env, napi_callback_info info);