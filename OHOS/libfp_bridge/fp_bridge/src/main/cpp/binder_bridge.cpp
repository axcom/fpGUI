// fpGUI HarmonyOS 桥 — Binder (IPC Kit) 桥接（独立文件，不侵入 napi_init.cpp）
// ======================================================
// 职责：
//   P1 原生子进程宿主：ohos_binder_spawn_server() 让桥把 libhelloworld.so
//     作为原生子进程拉起（子进程内 Pascal 导出 NativeChildProcess_OnConnect
//     提供 OHIPCRemoteStub），子进程启动回调里拿到 OHIPCRemoteProxy* 后
//     交给 Pascal（ohos_binder_on_proxy）。
//   P2 ServiceExtensionAbility 客户端：proxy 由 ETS 侧
//     connectServiceExtensionAbility 获取，经本文件 ohos_binder_set_proxy
//     交给 Pascal（NAPI 从 ETS 调用）。
// 需要链接：libipc_capi.so（OH_IPCRemoteProxy_*）、
//           libchild_process.so（OH_Ability_CreateNativeChildProcess）

#include <dlfcn.h>
#include <mutex>
#include "AbilityKit/native_child_process.h"
#include "IPCKit/ipc_cremote_object.h"
#include "hilog/log.h"
#include "fp_bridge.h"

static void* g_binderProxy = nullptr;
static std::mutex g_binderMutex;

// C++ → Pascal：把桥获得的 proxy 句柄交给 Pascal（ohos_binder_on_proxy）
static void CallPascalOnProxy(void* proxy) {
    void* handle = fp_bridge_get_pascal_lib_handle();
    if (!handle) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI",
            "binder: pascal lib not loaded yet");
        return;
    }
    typedef void (*OnProxyFn)(void*);
    OnProxyFn onProxy = (OnProxyFn)dlsym(handle, "ohos_binder_on_proxy");
    if (onProxy) {
        onProxy(proxy);
    } else {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "fpGUI",
            "binder: dlsym ohos_binder_on_proxy failed: %s", dlerror());
    }
}

// P1：原生子进程启动回调（在子进程创建后于主进程调用）
static void OnNativeChildProcessStarted(int errCode, OHIPCRemoteProxy* remoteProxy) {
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "binder: child process started, errCode=%d proxy=%p",
        errCode, (void*)remoteProxy);
    if (errCode != NCP_NO_ERROR || remoteProxy == nullptr) {
        {
            std::lock_guard<std::mutex> lock(g_binderMutex);
            g_binderProxy = nullptr;
        }
        return;
    }
    {
        std::lock_guard<std::mutex> lock(g_binderMutex);
        g_binderProxy = remoteProxy;
    }
    CallPascalOnProxy(remoteProxy);
}

extern "C" {

// P1：Pascal 调用 —— 拉起 libhelloworld.so 原生子进程（宿主 Binder 服务器）
// 返回：0=已发起（proxy 稍后经 ohos_binder_on_proxy 送达）；非 0=失败
int ohos_binder_spawn_server(void) {
    int32_t ret = (int32_t)OH_Ability_CreateNativeChildProcess(
        "libhelloworld.so", OnNativeChildProcessStarted);
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "fpGUI",
        "binder: ohos_binder_spawn_server ret=%d", (int)ret);
    return (int)ret;
}

// P2：ETS 侧拿到 proxy 后经 NAPI 调用本函数交给 Pascal
void ohos_binder_set_proxy(void* proxy) {
    {
        std::lock_guard<std::mutex> lock(g_binderMutex);
        g_binderProxy = proxy;
    }
    if (proxy) {
        CallPascalOnProxy(proxy);
    }
}

// 供查询：当前 proxy 句柄
void* ohos_binder_get_proxy(void) {
    std::lock_guard<std::mutex> lock(g_binderMutex);
    return g_binderProxy;
}

// 释放 proxy（断开/退出时）
void ohos_binder_proxy_destroy(void) {
    OHIPCRemoteProxy* proxy;
    {
        std::lock_guard<std::mutex> lock(g_binderMutex);
        proxy = (OHIPCRemoteProxy*)g_binderProxy;
        g_binderProxy = nullptr;
    }
    if (proxy) {
        OH_IPCRemoteProxy_Destroy(proxy);
    }
}

} // extern "C"
