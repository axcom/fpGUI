// fpGUI HarmonyOS 统一桥 libfp_bridge.so — 反向桥接 ABI
// ======================================================
// 布局与 fpg_ohos.pas 的 TOHOSExportTable / TOHOSBridgeCallbacks 严格一致：
//   - 4 字节自然对齐（全 int32_t/指针字段）
//   - 版本字段防错配：OHOS_BRIDGE_VERSION 与 Pascal 侧同步，布局或成员变更时两处同时 +1
// 方向（反向桥接）：Pascal 主动调用 fp_bridge_init（本库导出），
//   传入 FpBridgePascalApi（Pascal 实现的 26 个函数），
//   取回 FpBridgeCppApi（C++ 实现的回调）。
// 调用时机：fpg_ohos.pas 的 ohos_bridge_connect（fpgApplication.Initialize 之前，
//   Pascal 主线程）。fp_bridge_init 内部同步完成初始化）。

#pragma once
#include <cstdint>

#define OHOS_BRIDGE_VERSION 13   // v13：新增 arkts_invoke_result（Pascal→ArkTS 结果回传）/ arkts_invoke（反向调用入口）

// Pascal → C++：Pascal 实现的导出函数表（Pascal 填充输入，C++ 缓存后直接调用）
typedef struct {
    int32_t version;
    void* set_screen_size;            // ohos_set_screen_size
    void* set_zoom_scale;             // ohos_set_zoom_scale
    void* inject_touch_to_window;     // ohos_inject_touch_to_window
    void* inject_key_event;           // ohos_inject_key_event
    void* inject_mouse_event;         // ohos_inject_mouse_event
    void* inject_wheel_event;         // ohos_inject_wheel_event
    void* inject_hover_event;         // ohos_inject_hover_event
    void* inject_text;                // ohos_inject_text
    void* inject_delete_chars;        // ohos_inject_delete_chars
    void* inject_delete_right_chars;  // ohos_inject_delete_right_chars
    void* inject_move_cursor;         // ohos_inject_move_cursor
    void* inject_window_resized;      // ohos_inject_window_resized
    void* inject_window_moved;        // ohos_inject_window_moved（标题栏拖动/最大化位置同步）
    void* inject_window_closed;       // ohos_inject_window_closed（标题栏 X 关闭后收尾）
    void* can_close;                  // ohos_can_close（关闭前 CanClose 查询：1=可关 0=不可）
    void* force_window_refresh;       // ohos_force_window_refresh（主动刷新）
    void* inject_tray_event;          // 托盘事件注入
    void* update_configuration;       // 系统 Configuration 变更（紧凑 KV）
    void* set_launch_params;          // 启动载荷 JSON（want.uri/action/entities/parameters 全量）
    void* inject_app_args;            // ohos_inject_app_args
    void* timer_tick;                 // 定时器 ArkUI tick 注入
    void* timer_query;                // 定时器活跃态查询
    void* inject_drag_event;          // 系统拖拽 enter/move/leave
    void* drag_process_drop;          // drop 同步应答 (accept<<8)|action
    void* inject_drag_end;            // 拖拽会话结束
    void* dispatch;                   // fpgui_dispatch_entry(op,params)（v6 动态分发入口，立即返回 jobId）
    void* dispatch_free;              // fpgui_dispatch_free(p)（v7 释放 dispatch 返回的 PChar）
    void* file_picker_result;         // ETS 文件选择器结果回传 (int reqId, const char* resultJson)
    void* file_io_result;             // 
    void* arkts_invoke_result;        // v13：void(const char* callId, const char* resultJson, int32_t failed)
} FpBridgePascalApi;

// C++ → Pascal：本库（libfp_bridge.so）实现的所有回调（Pascal 消费）
typedef struct {
    int32_t version;
    void* create_window;              // ohos_create_window
    void* destroy_window;             // ohos_destroy_window
    void* resize_window;              // ohos_resize_window
    void* move_window;                // ohos_move_window
    void* set_window_visible;         // ohos_set_window_visible
    void* set_modal_window;           // ohos_set_modal_window
    void* set_pointer_style;          // ohos_set_pointer_style
    void* shake_window;               // ohos_shake_window
    void* show_keyboard;              // ohos_bridge_show_keyboard
    void* clipboard_set_text;         // ohos_clipboard_set_text
    void* clipboard_get_text;         // ohos_clipboard_get_text
    void* get_user_dir;               // 沙箱用户目录
    void* get_main_window_decoration; // 主窗装饰偏移（vp）
    void* get_window_decoration;      // per-window dec（vp），弹窗定位补偿
    void* drag_start;                 // 系统拖拽：起拖，同步返回 sessionId
    void* set_dnd_enabled;            // 系统拖拽：窗口拖入开关
    void* set_window_state;           // 0=normal 1=minimized 2=maximized
    void* set_window_opacity;         // 窗口透明度（×1000 整数透传）
    void* set_window_title;           // 运行时改标题
    void* set_window_attributes;      // 窗口属性位掩码
    void* tray_add;                   // void(const char* title, int iconIndex)
    void* tray_set_menu;              // void(const char* json)
    void* tray_remove;                // void(void)
    void* dispatch_result;            // void(jobId,resultJson,failed)（v6 分发结果回传）
    void* get_window_state;           // int32_t(*)(void* handle)（v10 查询缓存的窗口状态）
    void* open_url;                   // void(const char* url)（v11 打开 URL/文档）
    void* notify_first_frame;         // void(void* handle)（v12 首帧上屏通知：FlushBuffer 成功后调用）
    void* show_file_picker;           // 文件选择器
    void* file_io;
    void* arkts_invoke;               // v13：int32_t(const char* callId, const char* method, const char* params)
} FpBridgeCppApi; // pascal 以后也可直接动态加载 而不必再维护本表

void* fp_bridge_get_pascal_lib_handle(void);

#ifdef __cplusplus
extern "C" {
#endif
// 反向桥接入口（Pascal 调用，Pascal 侧 TFpBridgeInitFn 声明严格一致）：
//   TFpBridgeInitFn = function(version: Integer; const pascalApi: TOHOSExportTable;
//     var cppApi: TOHOSBridgeCallbacks): Integer; cdecl;
// 返回：0=成功；-1=版本不匹配；-2=必需函数缺失
int fp_bridge_init(int32_t version,
                   const FpBridgePascalApi* pascal_api,
                   FpBridgeCppApi* cpp_api);

// v13：Pascal → ArkTS 反向调用入口（经 cppApi.arkts_invoke 槽位，或 LibBridgeSym dlsym 兜底）：
//   返回 0=已受理（结果经 pascalApi.arkts_invoke_result 回传）
//       -1=入参错误 -2=未初始化 -3=方法未注册(且无 dispatcher) -4=队列满/TSFN 关闭
int32_t ohos_arkts_invoke(const char* callId, const char* method, const char* params);
#ifdef __cplusplus
}
#endif