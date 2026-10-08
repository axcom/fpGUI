# fp_bridge 桥接 API 应用指导

> 适用版本：`OHOS_BRIDGE_VERSION = 13`
> 桥接头文件：`lib_fp_bridge/fp_bridge/src/main/cpp/fp_bridge.h`
> 实现文件：`fp_bridge.cpp`（桥核心）、`napi_init.cpp`（NAPI 表面/Pascal 加载器）、`arkts_invoke.cpp`（Pascal→ArkTS 反向调用）、`binder_bridge.cpp`（IPC Kit）
> Pascal 侧对接：`fpGUI-2.1.0/framework/src/main/pascal/corelib/ohos/fpg_ohos.pas` 及扩展单元 `fpg_ohos_dispatch/filepicker/filestream/invoke`

---

## 0. 阅读指南

- 本文档面向两类开发者：
  - **Pascal 侧开发者**：调用 `FpBridgeCppApi` 回调（第 4 章），向 ArkTS/C++ 请求窗口、剪贴板、拖拽、文件等系统能力。
  - **C++/桥维护者**：实现/维护 `FpBridgePascalApi` 注入链（第 5 章），以及 ArkTS 侧 v13 反向调用注册面（第 6 章）。
- 文中所有结构体、槽位顺序、参数类型必须与 `fp_bridge.h` 及 `fpg_ohos.pas` 中 `TOHOSExportTable/TOHOSBridgeCallbacks` **逐字段严格一致**，任意增删改都必须同步修改版本号。

---

## 1. 架构总览

### 1.1 三层结构与反向桥接

```
┌────────────────────────────────────────────────────────────────────┐
│ ArkTS (HAP/ETS)      Index.ets / FpgSurface.ets / TrayManager ...  │
│   import fpbridge from 'libfp_bridge.so'                           │
└──────────────┬─────────────────────────────────────────────────────┘
               │ NAPI（ArkTS → C++：onTouchEvent/onSurfaceReady/...）
               │ NAPI（C++ → ArkTS：setNativeCallback TSFN 命令通道）
┌──────────────▼─────────────────────────────────────────────────────┐
│ C++ libfp_bridge.so                                                 │
│   napi_init.cpp   NAPI 表面 + Pascal 加载器 + TSFN                  │
│   fp_bridge.cpp   桥核心：ohos_* 导出 + fp_bridge_init              │
│   arkts_invoke.cpp Pascal→ArkTS 方法注册表 + 调用入口               │
│   binder_bridge.cpp IPC Kit（子进程/ServiceExtension）              │
└──────────────┬─────────────────────────────────────────────────────┘
               │ 反向桥接（Pascal 主动连接）
               │ fp_bridge_init(version, pascalApi, cppApi)
               │   pascalApi：Pascal 实现的 30 个回调（C++ 缓存后调用）
               │   cppApi   ：C++ 实现的 30 个回调（Pascal 缓存后调用）
┌──────────────▼─────────────────────────────────────────────────────┐
│ Pascal libhelloworld.so (fpGUI + 应用)                              │
│   fpg_ohos.pas / fpg_ohos_dispatch.pas / fpg_ohos_filepicker.pas ...│
└────────────────────────────────────────────────────────────────────┘
```

**“反向桥接”含义**：传统桥由 C++ 在加载 Pascal 库后通过 dlsym 注入函数指针；本工程由 **Pascal 主动调用 C++ 导出的 `fp_bridge_init`**，一次调用同时完成：

1. Pascal 把自己实现的函数表（`FpBridgePascalApi`）交给 C++ 缓存；
2. C++ 把自身实现的函数表（`FpBridgeCppApi`）填回给 Pascal；
3. C++ 内部同步完成显示预初始化（屏幕尺寸、缩放、系统配置下发）。

### 1.2 握手与启动时序

```
ArkTS Index.aboutToAppear
  ├─ fpbridge.setSandboxPaths(...)      # 必须在 start 前
  ├─ fpbridge.start('helloworld', payload?, appArgs?)
  │     └─ 创建 8MB 栈 Pascal 线程 → 等待 g_etsReady
  ├─ fpbridge.setEtsReady()             # 放行 Pascal 线程
  └─ fpbridge.setNativeCallback(cb)     # 注册 C++→ArkTS 命令回调（TSFN）

C++ PascalThread（独立线程）
  ├─ dlopen libhelloworld.so → MainProc
  ├─ set_zoom_scale(g_zoomScale)
  ├─ set_screen_size(w, h, dpi, density)
  ├─ update_configuration(初始 KV)
  └─ MainProc() 阻塞运行

Pascal 主线程（fpgApplication.Initialize 完成后）
  └─ ohos_bridge_connect()              # fpg_ohos.pas 初始化节自动调用
        ├─ dlopen libfp_bridge.so
        ├─ 填充 pascalApi（30 槽）
        ├─ fp_bridge_init(13, @pascalApi, @cppApi)
        └─ 装载 cppApi 到 _ohos_* 全局函数指针
```

> 扩展单元（dispatch / filepicker / filestream / invoke）在各自 initialization 中向 `fpg_ohos.pascalApi` **补填槽位**，若桥已连接则再次调用 `ohos_bridge_connect` 重新下发。因此这些单元必须列在 `fpg_ohos` 之后（uses 顺序）才能生效。

### 1.3 线程模型

| 线程 | 说明 | 允许操作 |
|---|---|---|
| ArkTS JS 线程（主线程） | NAPI 接口、TSFN 回调目标 | 操作 ArkTS 对象、调用 NAPI |
| Pascal 主线程 | fpGUI 事件循环（UI 线程） | 操作 fpGUI 窗口/控件、创建 native window |
| C++ PascalThread | `start()` 创建的启动线程 | 调 Pascal 预初始化回调（在 Pascal 运行前） |
| 任意线程 | 应用异步任务 | 调桥导出函数（内部经 TSFN/队列封送） |

规则：
- `FpBridgePascalApi` 中的 `inject_*` 回调**多数在 JS 线程被 C++ 调用**，Pascal 实现必须只做“拷贝参数 + 加锁入队 + 唤醒主循环”，不得直接操作 UI 对象；Pascal 侧已统一封装为 `EnqueueXxxEvent`。
- 例外（同步语义、调用方阻塞等待）：
  - `can_close`：JS 线程 → 入队 → 主循环 `CloseQuery` → 事件唤醒，等待 ≤500ms，超时返回 1（可关）。
  - `drag_process_drop`：JS 线程 → 入队 → 主循环处理 → 等待 ≤2500ms，超时返回 0（拒绝）。
- `FpBridgeCppApi` 中的函数均可从 Pascal 任意线程调用（C++ 内部经 TSFN 投递到 JS 线程执行，`create_window` 为同步阻塞等待 surface）。

### 1.4 版本与兼容

- `fp_bridge.h` 的 `OHOS_BRIDGE_VERSION` 与 `fpg_ohos.pas` 的 `OHOS_BRIDGE_VERSION` 必须相等，当前为 **13**。
- `fp_bridge_init` 校验：入参 `version`、`pascal_api->version` 双重校验；任何布局/成员变更必须**两处同时 +1**，否则返回 `-1`。
- 槽位是**按位置**解析的裸指针数组，**禁止**在中间插入/删除字段；新增字段只能追加到记录尾部，并同步升版本。
- 记录全部使用指针/`int32`，C 侧 `#pragma pack` 无特殊要求；Pascal 侧 `TOHOSWindowOptions` 使用 `{$packrecords C}`（4 字节自然对齐）。

### 1.5 内存所有权约定

| 返回形式 | 产生方 | 释放方 |
|---|---|---|
| `char*`（`clipboard_get_text`、`get_user_dir`） | C++ `strdup`/`malloc` | Pascal 用 libc `free`（`cfree`）释放 |
| `char*`（`dispatch` 返回的 PChar） | Pascal 内存管理器 | 必须经 `dispatch_free` 释放 |
| `const char*` 入参 | 调用方栈/堆 | 被调方**不得**保存指针，需拷贝 |
| `file_io_result` 的 `data` | JS 线程 ArrayBuffer | 回调内立即拷贝，返回后失效 |
| `arkts_invoke_result` 的 `resultJson` | C++ `std::string` 临时串 | 回调内立即拷贝 |

---

## 2. 核心数据结构

### 2.1 FpBridgePascalApi（Pascal → C++）

C++ 在 `fp_bridge_init` 中按值拷贝缓存，后续由 `napi_init.cpp`/`fp_bridge.cpp` 直接调用。字段顺序（共 30 个函数指针，`version` 除外）：

| # | 字段 | Pascal 实现 | 功能 | C++ 调用方 |
|---|---|---|---|---|
| 0 | `version` | 常量 13 | 版本匹配 | — |
| 1 | `set_screen_size` | `ohos_set_screen_size` | 显示预初始化（w/h/dpi/density） | PascalThread |
| 2 | `set_zoom_scale` | `ohos_set_zoom_scale` | 用户缩放倍数 | PascalThread |
| 3 | `inject_touch_to_window` | `ohos_inject_touch_to_window` | 触摸注入（按窗口路由） | OnTouchEvent |
| 4 | `inject_key_event` | `ohos_inject_key_event` | 键盘注入 | OnKeyEvent |
| 5 | `inject_mouse_event` | `ohos_inject_mouse_event` | 鼠标注入 | OnMouseEvent |
| 6 | `inject_wheel_event` | `ohos_inject_wheel_event` | 滚轮注入 | OnWheelEvent |
| 7 | `inject_hover_event` | `ohos_inject_hover_event` | 悬停注入 | OnHoverEvent |
| 8 | `inject_text` | `ohos_inject_text` | IME 文本注入 | OnTextInput |
| 9 | `inject_delete_chars` | `ohos_inject_delete_chars` | IME 退格删除 | OnDeleteChars |
| 10 | `inject_delete_right_chars` | `ohos_inject_delete_right_chars` | IME 前向删除 | OnDeleteRightChars |
| 11 | `inject_move_cursor` | `ohos_inject_move_cursor` | IME 光标移动 | OnImeMoveCursor |
| 12 | `inject_window_resized` | `ohos_inject_window_resized` | 窗口尺寸变化反馈 | OnWindowResized |
| 13 | `inject_window_moved` | `ohos_inject_window_moved` | 窗口位置变化反馈 | OnWindowMoved |
| 14 | `inject_window_closed` | `ohos_inject_window_closed` | 标题栏关闭收尾 | OnWindowClosed |
| 15 | `can_close` | `ohos_can_close` | 关闭前 CanClose 查询 | napi QueryCanClose |
| 16 | `force_window_refresh` | `ohos_force_window_refresh` | 主动刷新窗口 | napi RefreshWindow |
| 17 | `inject_tray_event` | `ohos_inject_tray_event` | 托盘事件注入 | OnTrayEvent |
| 18 | `update_configuration` | `ohos_update_configuration` | 系统配置变更/首启下发 | PascalThread / OnNotifyConfiguration |
| 19 | `set_launch_params` | `ohos_set_launch_params` | 热启动载荷 JSON | OnSetLaunchParams |
| 20 | `inject_app_args` | `ohos_inject_app_args` | 启动载荷 + 命令行参数 | PascalThread（pro/run 前） |
| 21 | `timer_tick` | `ohos_timer_tick` | 定时器 tick 唤醒事件循环 | OnTimerTick |
| 22 | `timer_query` | `ohos_timer_query` | 是否有活动定时器 | OnTimerQuery |
| 23 | `inject_drag_event` | `ohos_inject_drag_event` | 拖拽 enter/move/leave | OnDragEvent |
| 24 | `drag_process_drop` | `ohos_drag_process_drop` | drop 同步应答 | OnDropEvent |
| 25 | `inject_drag_end` | `ohos_inject_drag_end` | 拖拽会话结束 | OnDragEnd |
| 26 | `dispatch` | `fpgui_dispatch_entry` | 动态分发入口（Pascal 处理） | NAPI Dispatch |
| 27 | `dispatch_free` | `fpgui_dispatch_free` | 释放 dispatch 返回串 | NAPI Dispatch |
| 28 | `file_picker_result` | 文件选择器回调 | 选择器结果回传 | OnNotifyFilePickerResult |
| 29 | `file_io_result` | 文件流回调 | 文件流结果回传 | OnNotifyFileIoResult |
| 30 | `arkts_invoke_result` | `InvokeResultCallback` | ArkTS 调用结果回传（v13） | ArkInvokeCallJS |

> 注：头文件注释中的“26 个函数”为历史遗留描述，实际当前为 **30 个**。`file_picker_result`/`file_io_result`/`arkts_invoke_result` 由扩展单元晚注册，C++ 每次使用前判空（`nil` 时记录日志并丢弃）。

### 2.2 FpBridgeCppApi（C++ → Pascal）

由 `fp_bridge_init` 填出，Pascal 装载到 `_ohos_*` 全局。字段顺序（共 30 个函数指针，`version` 除外）：

| # | 字段 | C++ 实现 | 功能 |
|---|---|---|---|
| 0 | `version` | 常量 13 | 版本匹配 |
| 1 | `create_window` | `ohos_create_window` | 创建系统窗口并同步取回 OHNativeWindow* |
| 2 | `destroy_window` | `ohos_destroy_window` | 销毁窗口 |
| 3 | `resize_window` | `ohos_resize_window` | 调整客户区尺寸 |
| 4 | `move_window` | `ohos_move_window` | 移动窗口 |
| 5 | `set_window_visible` | `ohos_set_window_visible` | 显示/隐藏 |
| 6 | `set_modal_window` | `ohos_set_modal_window` | 标记模态窗口 |
| 7 | `set_pointer_style` | `ohos_set_pointer_style` | 鼠标指针样式 |
| 8 | `shake_window` | `ohos_shake_window` | 窗口抖动（模态校验失败反馈） |
| 9 | `show_keyboard` | `ohos_bridge_show_keyboard` | 软键盘弹/收 |
| 10 | `clipboard_set_text` | `ohos_clipboard_set_text` | 写系统剪贴板 |
| 11 | `clipboard_get_text` | `ohos_clipboard_get_text` | 读系统剪贴板 |
| 12 | `get_user_dir` | `ohos_get_user_dir` | 获取沙箱目录 |
| 13 | `get_main_window_decoration` | `ohos_get_main_window_decoration` | 主窗装饰尺寸（vp） |
| 14 | `get_window_decoration` | `ohos_get_window_decoration` | 指定窗装饰尺寸（vp） |
| 15 | `drag_start` | `ohos_drag_start` | 发起系统拖拽 |
| 16 | `set_dnd_enabled` | `ohos_set_dnd_enabled` | 窗口拖入开关 |
| 17 | `set_window_state` | `ohos_set_window_state` | 窗口状态（normal/min/max） |
| 18 | `set_window_opacity` | `ohos_set_window_opacity` | 窗口透明度 |
| 19 | `set_window_title` | `ohos_set_window_title` | 运行时改标题 |
| 20 | `set_window_attributes` | `ohos_set_window_attributes` | 窗口属性位掩码 |
| 21 | `tray_add` | `ohos_tray_add` | 添加托盘图标 |
| 22 | `tray_set_menu` | `ohos_tray_set_menu` | 设置托盘菜单 |
| 23 | `tray_remove` | `ohos_tray_remove` | 移除托盘 |
| 24 | `dispatch_result` | `ohos_dispatch_result` | 动态分发结果回传（v6） |
| 25 | `get_window_state` | `ohos_get_window_state` | 查询缓存的窗口状态（v10） |
| 26 | `open_url` | `ohos_open_url` | 打开 URL/文档（v11） |
| 27 | `notify_first_frame` | `ohos_notify_first_frame` | 首帧上屏通知（v12） |
| 28 | `show_file_picker` | `ohos_show_file_picker` | 系统文件选择器 |
| 29 | `file_io` | `ohos_file_io` | 系统文件流（picker URI 随机读写） |
| 30 | `arkts_invoke` | `ohos_arkts_invoke` | Pascal→ArkTS 反向调用（v13） |

### 2.3 WindowOptions（`ohos_create_window` 入参）

```c
#pragma pack(push, 4)          // Pascal 侧 {$packrecords C}
struct WindowOptions {
    int32_t  windowType;       // TWindowType：0=wtChild 1=wtWindow 2=wtModalForm 3=wtPopup
    int32_t  windowAttributes; // TWindowAttributes 位掩码（见 4.3.8）
    int32_t  windowState;      // 初始窗口状态（0=normal 1=min 2=max）
    int32_t  isMainform;       // 1=主窗（强制 reqId=1）；0=子窗（reqId 自增）
    int32_t  mouseCursor;      // 初始光标样式
    float    opacity;          // 透明度 0..1
    int32_t  left, top;        // 窗口位置（vp/px，经 ETS 透传）
    int32_t  width, height;    // 客户区尺寸
    char     title[256];       // 窗口标题（NUL 结尾）
    uint64_t surfaceId;        // 保留（0；surface 由 ETS XComponent.onLoad 回传）
};
#pragma pack(pop)
```

### 2.4 命令通道（C++ → ArkTS，`NativeCommandData`）

`fp_bridge.cpp` 将 `ohos_*` 调用封送为命令对象，经 `g_tsfn` 投递到 JS 线程，由 ArkTS `setNativeCallback` 注册的回调消费（`Index.ets` `handleNativeCommand`）。命令类型：

| type | 名称 | 附带字段 | ArkTS 侧处理 |
|---|---|---|---|
| 0 | CREATE_WINDOW | reqId/xcId/x/y/width/height/windowAttributes/windowType/title | 建主窗或子窗 + XComponent |
| 1 | MOVE_WINDOW | reqId/x/y | `moveWindowTo` |
| 2 / 3 | SHOW / HIDE | reqId | `showWindow`/`hideWindow` |
| 4 | DESTROY | reqId | `destroyWindow` |
| 5 | SHAKE | reqId | 抖动动画 |
| 6 | SHOW_KEYBOARD | x=show | `showIme`/`hideIme` |
| 7 | RESIZE | reqId/width/height | 调整客户区 |
| 8 / 9 / 10 | TRAY_ADD / SET_MENU / REMOVE | title / payload | TrayManager |
| 11 | TIMER_STATE | x=active | 启停 `setInterval` |
| 12 | SET_POINTER_STYLE | reqId/x=style | `pointer.setPointerStyle` |
| 13 | DRAG_START | reqId=sessionId低31位/payload=dataJson/title=extraJson | `executeDrag` |
| 14 | SET_DND_ENABLED | reqId/x=enabled | AppStorage 记录 |
| 15 | SET_WINDOW_STATE | reqId/x=state | 最小化/最大化 |
| 16 | SET_WINDOW_OPACITY | x=opacity×1000 | 暂存（SDK 无接口） |
| 17 | SET_WINDOW_TITLE | title | 改标题 |
| 18 | SET_WINDOW_ATTRIBUTES | x=attrs | 全屏/无边框/置顶 |
| 19 | FIRST_FRAME | reqId | 打开 XComponent 显示门 |
| 20 | FILE_PICKER | reqId/x=类型/payload=optsJson | 拉起系统选择器 |
| 21 | FILE_IO | reqId/x=op/y=arg/offset/length/payload=URI/data=写数据 | `fs.*Sync` 操作 |

---

## 3. 连接入口

### 3.1 `fp_bridge_init`

```c
int fp_bridge_init(int32_t version,
                   const FpBridgePascalApi* pascal_api,
                   FpBridgeCppApi* cpp_api);
```

- **功能**：反向桥接唯一入口。校验版本与必需函数；缓存 Pascal 函数表并装载 `g_inject_*`；填出 C++ 函数表；置 `g_bridgeReady = true`。
- **目的/意义**：一次调用完成双向函数表交换，取代零散的 dlsym 注入；版本字段防止两侧 ABI 错配导致崩溃。
- **参数**：
  - `version`：Pascal 侧 `OHOS_BRIDGE_VERSION`（必须等于 C++ 常量，当前 13）。
  - `pascal_api`：Pascal 填充的导出函数表指针。⚠ FPC `cdecl` 下不能用 `const record`（会按值拷贝错位），必须显式指针。
  - `cpp_api`：输出参数，Pascal 提供栈/全局记录指针，函数内 `memset` 后填充。
- **返回码**：
  - `0` 成功；
  - `-1` 版本不匹配（`version` 或 `pascal_api->version` 与 C++ 不一致）；
  - `-2` 入参空指针或必需函数缺失（当前仅校验 `set_screen_size`，其余槽位缺失不阻断，但对应功能不可用）。
- **调用者/时机**：Pascal `ohos_bridge_connect`（`fpg_ohos.pas` 初始化节，`fpgApplication.Initialize` 之后、主循环之前）。扩展单元补槽后重连。必须在 Pascal 主线程调用；内部同步完成（无阻塞等待）。
- **注意事项**：
  - 幂等性由 Pascal 侧控制（当前实现重连会覆盖函数表，是扩展单元补槽的正式通道）。
  - 失败时 Pascal 侧 `gBridgeInitialized` 保持 False，后续可重试。

### 3.2 `fp_bridge_get_pascal_lib_handle`

```c
void* fp_bridge_get_pascal_lib_handle(void);
```

- **功能**：返回 C++ `PascalThread` `dlopen(lib<app>.so)` 得到的句柄（`g_pascalLibHandle`）。
- **目的/意义**：供 `binder_bridge.cpp` 在子进程启动回调中 `dlsym(handle, "ohos_binder_on_proxy")`，把 IPC proxy 句柄直接交给 Pascal；其他扩展亦可用它按需取 Pascal 导出符号。
- **返回**：库句柄；未加载/已 `dlclose` 时为 `nullptr`。
- **注意事项**：线程安全读取（指针在 Pascal 线程结束时清空）；**不要**自行 `dlclose`。

### 3.3 Pascal 侧 `ohos_bridge_connect`（对接说明）

- 位置：`fpg_ohos.pas`，声明 `procedure ohos_bridge_connect;`
- 行为：`dlopen(LIB_fpgBridge)` → `dlsym('fp_bridge_init')` → 填充 `pascalApi` → 调用 → 把 `cppApi` 各槽装入 `_ohos_*` 全局（如 `_ohos_create_window := cppApi.create_window`）。
- 扩展槽位补填：`fpg_ohos_dispatch.pas` 在 initialization 中写入 `pascalApi.dispatch/dispatch_free` 后调用 `ohos_bridge_connect`；`fpg_ohos_filepicker.pas`、`fpg_ohos_filestream.pas`、`fpg_ohos_invoke.pas` 同理补 `file_picker_result`/`file_io_result`/`arkts_invoke_result`。
- 调用顺序要求：`fpg_ohos` 必须在所有扩展单元之前初始化（uses 顺序），否则扩展单元的“补连”发生在首次连接之前，第二次连接时机不正确。

---

## 4. C++ → Pascal 回调 API（`FpBridgeCppApi`）

以下函数均由 Pascal 调用（经 `_ohos_*` 函数指针），C++ 实现。除特别说明外**可从任意线程调用**（内部经 TSFN 封送到 JS 线程）。

### 4.1 窗口生命周期

#### 4.1.1 `create_window`

```c
void* create_window(WindowOptions* opts);
```

- **功能**：请求 ArkTS 创建系统窗口及 XComponent，同步等待 `onSurfaceReady` 回传 surfaceId，转换为 `OHNativeWindow*` 返回。
- **目的/意义**：Pascal 侧窗口的“物理载体”由 ArkTS 窗口系统提供；本函数把两步异步（建窗 + surface 就绪）封装为一次同步调用，简化 Pascal 窗口分配逻辑（`DoAllocateWindowHandle`）。
- **参数**：`opts` 见 2.3。主窗体 `isMainform=1` → reqId 固定 1（主窗 XComponent `xc_fpg_1` 固定存在于 Index 页面）；其余窗口 reqId 从 2 递增，XComponent id 为 `xc_fpg_<reqId>`。
- **返回**：`OHNativeWindow*`；失败返回 `nullptr`（ETS 未就绪、超时 10s、surface 创建失败）。
- **注意事项**：
  - **阻塞调用**，最坏 10s；只能在非 UI 阻塞敏感路径使用（现有调用点在窗口 show 流程，可接受）。
  - 创建期 ETS 可能先报 `onWindowResized`，C++ 用 `g_pendingResize` 暂存并在句柄登记后**补送**一次 resize，保证 Pascal 按真实尺寸重建缓冲。
  - 缓冲几何以 ETS 上报的 surface 权威尺寸（`g_surfaceSize`）为准，防止系统强制最大化时被旧尺寸覆盖。

#### 4.1.2 `destroy_window`

```c
void destroy_window(void* handle);
```

- **功能**：销毁 `OHNativeWindow`，清理 reqId 映射/矩形/resize 缓存，并通知 ETS `destroyWindow`（主窗销毁会终止 Ability）。
- **参数**：`handle` 为 `create_window` 返回值；`nullptr` 安全返回。
- **注意事项**：Pascal `hide` 释放窗口时调用；销毁后句柄立即失效，不得复用。

#### 4.1.3 `resize_window`

```c
void resize_window(void* handle, int w, int h);
```

- **功能**：更新 native buffer 几何（`SET_BUFFER_GEOMETRY`）并通知 ETS 调整窗口客户区。
- **参数**：`w/h` 为客户区尺寸（与 surface 物理像素 1:1）。
- **注意事项**：若 C++ 已缓存权威 surface 尺寸（`g_surfaceSize`），buffer 几何会**忽略入参**使用权威值，仅窗口 resize 语义转发 ETS——避免被系统强制最大化场景下画面被放大。

#### 4.1.4 `move_window`

```c
void move_window(void* handle, int x, int y);
```

- **功能**：移动窗口到屏幕坐标 `(x, y)`。
- **注意事项**：用于标题栏拖动/最大化后位置同步（配合 `inject_window_moved` 反馈闭环）。

#### 4.1.5 `set_window_visible`

```c
void set_window_visible(void* handle, int visible);
```

- **功能**：`visible != 0` 显示，`0` 隐藏。对应 ETS `showWindow/hideWindow`。
- **注意事项**：主窗 show 前 XComponent 显示门依赖 `notify_first_frame`（见 4.8.3），避免黑屏闪现。

#### 4.1.6 `set_modal_window`

```c
void set_modal_window(void* handle);
```

- **功能**：记录当前模态窗口 reqId（`g_modalReqId`）；传 `nullptr` 清除。
- **目的/意义**：ArkTS 侧据此过滤非模态窗口事件、`getModalReqId` 判定事件路由；Pascal 侧 `gModalWinHandle` 同步。
- **注意事项**：仅跟踪“当前一个”模态窗口；多模态嵌套时以最后设置为准。

#### 4.1.7 `set_pointer_style`

```c
int set_pointer_style(void* handle, int style);
```

- **功能**：设置指定窗口鼠标指针样式；转发 ETS `pointer.setPointerStyle(windowId, style)`。
- **参数**：`style` 为 OHOS `PointerStyle` 枚举值；`handle` 为空时 reqId 解析为 -1（ETS 侧忽略）。
- **返回**：固定 `0`。
- **注意事项**：样式枚举由 ETS 统一解释，桥不做映射；`style=-1` 表示恢复默认。

#### 4.1.8 `shake_window`

```c
void shake_window(void* handle);
```

- **功能**：触发窗口抖动动画（模态/校验失败的用户反馈）。
- **注意事项**：ETS 侧无动画降级时仅记录日志，不影响主流程。

### 4.2 输入与键盘

#### 4.2.1 `show_keyboard`

```c
void show_keyboard(int show);
```

- **功能**：请求 ETS `showIme(show)`/`hideIme()`。
- **参数**：`show > 0` 弹出，`0` 收起。
- **注意事项**：避免回环——ETS 主动 `showKeyboard(show)` NAPI 只做状态日志，不再回传 Pascal（见 napi `ShowKeyboard`）。

### 4.3 剪贴板

#### 4.3.1 `clipboard_set_text`

```c
int clipboard_set_text(const char* text);
```

- **功能**：经 Pasteboard + UDMF 写系统剪贴板纯文本。
- **返回**：`0` 成功；`-1` 失败（空指针/创建对象失败）。
- **注意事项**：UTF-8 输入；内部创建/销毁全部 UDMF 对象，无泄漏责任转移。

#### 4.3.2 `clipboard_get_text`

```c
char* clipboard_get_text(void);
```

- **功能**：读系统剪贴板纯文本，失败内部重试 2 次（间隔 50ms，规避时序竞态）。
- **返回**：`strdup` 的 NUL 结尾字符串（**调用方必须释放**）；无内容返回 `nullptr`。
- **注意事项**：Pascal 侧用 `free/cfree` 释放，不可用 fpGUI 内存管理器。

### 4.4 路径与装饰

#### 4.4.1 `get_user_dir`

```c
char* get_user_dir(int dirType);
```

- **功能**：返回沙箱目录绝对路径。
- **参数**（⚠ ）：

| dirType | 含义 | 数据来源 |
|---|---|---|
| 0 | filesDir | `filesDir`（否则 HOME / 默认 el2 files） |
| 1 | cacheDir | `cacheDir` |
| 2 | tempDir | `tempDir` |
| 3 | resourceDir          | `resourceDir`                            |
| 4 | databaseDir          | `databaseDir`                            |
| 5 | preferencesDir       | `preferencesDir`                         |
| 6 | bundleCodeDir        | `bundleCodeDir`                          |
| 7 | distributedFilesDir  | `distributedFilesDir`                    |
| 8 | cloudFileDir         | `cloudFileDir`                           |
| 101 | `filesDir/Downloads` | 自动逐级 `mkdir(0755)` |
| 102 | `filesDir/Documents` | 自动逐级 `mkdir(0755)` |
| 其他 | 同 0（filesDir） | — |

- **返回**：`strdup` 字符串（**调用方释放**）。
- **注意事项**：
  - 必须在 `setSandboxPaths` 之后调用才能拿到真实沙箱路径；未设置时回退 `HOME`/固定默认值。
  - `dirType > 100` 的扩展目录会自动创建目录树，可写。
  - Pascal 侧有 `GetResfileDir`/`GetRawfileDir`/`EnsureRawfileDir` 等封装。

#### 4.4.2 `get_main_window_decoration`

```c
void get_main_window_decoration(int* decW, int* decH);
```

- **功能**：返回主窗总装饰尺寸（标题栏+边框，单位 vp；由 ETS `setMainWindowDec` 上报）。
- **目的/意义**：鼠标坐标补偿（ETS 报 displayX/Y 屏幕坐标，需减去装饰偏移）与弹窗定位。
- **注意事项**：纯内存读取，任意线程安全；未上报时为 0。

#### 4.4.3 `get_window_decoration`

```c
void get_window_decoration(void* handle, int* decW, int* decH);
```

- **功能**：返回指定窗口装饰尺寸（vp）；子窗无装饰或未上报时输出 0。
- **注意事项**：用于 per-window 弹窗定位补偿；`handle` 无效时安全输出 0。

### 4.5 窗口属性

#### 4.5.1 `set_window_state`

```c
void set_window_state(void* handle, int state);
```

- **功能**：`0=normal 1=minimized 2=maximized`，转发 ETS `applyWindowState`。
- **注意事项**：状态来源可经 `updateWindowState` NAPI 反馈缓存；查询用 `get_window_state`。

#### 4.5.2 `get_window_state`

```c
int32_t get_window_state(void* handle);
```

- **功能**：返回缓存的 OHOS `WindowStatusType`（0=UNDEFINED 1=FULL_SCREEN 2=MAXIMIZE 3=MINIMIZE 4=FLOATING 5=SPLIT_SCREEN）。
- **返回**：缓存值；句柄无效或无缓存返回 `4`（FLOATING）。
- **注意事项**：纯内存查询不阻塞；缓存由 ETS `updateWindowState` 事件维护。

#### 4.5.3 `set_window_opacity`

```c
void set_window_opacity(void* handle, float opacity);
```

- **功能**：设置窗口透明度 `0..1`，C++ 乘 1000 取整透传给 ETS。
- **注意事项**：当前 OpenHarmony SDK 无 `setWindowOpacity` 对应接口，ETS 侧只暂存/记录（预留）。

#### 4.5.4 `set_window_title`

```c
void set_window_title(void* handle, const char* title);
```

- **功能**：运行时修改窗口标题（ETS `applyWindowTitle`）。
- **注意事项**：`title` 最长 255 字节，超长截断；基因串须 NUL 结尾。

#### 4.5.5 `set_window_attributes`

```c
void set_window_attributes(void* handle, int attributes);
```

- **功能**：更新窗口属性位掩码。
- **参数**（fpGUI `TWindowAttribute` 集合位，按声明顺序）：

| 位 | 值 | 属性 | 含义 |
|---|---|---|---|
| 0 | 1 | `waSizeable` | 可调整大小 |
| 1 | 2 | `waAutoPos` | 自动定位 |
| 2 | 4 | `waStayOnTop` | 应用内置顶 |
| 3 | 8 | `waFullScreen` | 全屏 |
| 4 | 16 | `waBorderless` | 无边框 |
| 5 | 32 | `waUnblockableMessages` | 不可屏蔽消息 |
| 6 | 64 | `waX11SkipWMHints` | （X11 遗留，忽略） |
| 7 | 128 | `waSystemStayOnTop` | 系统级置顶 |

- **注意事项**：ETS 侧对 `waFullScreen`（`attrs & 8`）有特殊处理（跳过期望客户区显示门）；位定义与 `fpg_base.pas` 严格对应。

### 4.6 托盘（仅 2in1/PC）

#### 4.6.1 `tray_add`

```c
void tray_add(const char* title, int iconIndex);
```

- **功能**：添加系统托盘图标（title 为悬浮提示/标识，iconIndex 预留给内置图标）。
- **结果反馈**：ETS 完成后经 `onTrayEvent(3, "ok"/"fail")` 回传。

#### 4.6.2 `tray_set_menu`

```c
void tray_set_menu(const char* json);
```

- **功能**：设置托盘右键菜单，JSON 由 ETS `TrayManager.setMenu` 解析（菜单项 id/title 等）。
- **注意事项**：payload 缓冲上限 4096 字节。

#### 4.6.3 `tray_remove`

```c
void tray_remove(void);
```

- **功能**：移除托盘图标。Pascal `TfpgOhosSystemTrayIcon.Hide` 调用。

### 4.7 系统拖拽

#### 4.7.1 `drag_start`

```c
int64_t drag_start(const char* dataJson, const char* extraJson);
```

- **功能**：发起系统拖拽（ETS `executeDrag`）。
- **参数**：
  - `dataJson`：拖拽数据（UDMF 记录 JSON，ETS 侧解析，payload 上限 4096）；
  - `extraJson`：附加参数（title 缓冲，上限 255）。
- **返回**：同步返回会话 `sessionId`（从 1 递增）；ETS 未就绪返回 0。
- **注意事项**：`sessionId` 会话结束时经 `inject_drag_end` 回传，必须匹配；超时/取消路径也必须回调，否则 Pascal `Execute` 最长卡 60s。

#### 4.7.2 `set_dnd_enabled`

```c
void set_dnd_enabled(void* handle, int enabled);
```

- **功能**：开启/关闭指定窗口的系统拖入（DND）响应。
- **目的/意义**：ETS `onDrag`/`onDrop` 先查 `isDndEnabled(reqId)`，未开启则直接丢弃，节省无谓封送。
- **注意事项**：缓存于 C++ `g_dndEnabled`，同时通知 ETS 写 AppStorage。

### 4.8 系统集成

#### 4.8.1 `dispatch_result`

```c
void dispatch_result(const char* jobId, const char* resultJson, int failed);
```

- **功能**：Pascal 分发 Handler 完成时调用；C++ 经 TSFN 在 JS 线程 resolve 对应 Promise。
- **目的/意义**：动态分发（Registry-Dispatch）异步结果回传通道。
- **参数**：
  - `jobId`：`dispatch` 起步响应中的 `"jobId"`；
  - `resultJson`：处理结果 JSON 串（成功或错误信封均可）；
  - `failed`：0/1，仅作标记；**约定 Promise 一律 resolve**，调用方解析 `ok` 字段。
- **注意事项**：任意线程可调用；无 pending 命中（超时/取消）时安全丢弃；C++ 侧另有 35s 守护超时兜底。

#### 4.8.2 `open_url`

```c
void open_url(const char* url);
```

- **功能**：请求 ArkTS 打开 URL/文档（`openLink` 或 `startAbility(viewData)`）。
- **目的/意义**：OHOS 沙箱禁止直接起外部进程，必须经 ArkTS 系统能力打开。
- **注意事项**：
  - 空串/未注册回调时静默忽略；
  - 回调经专用 TSFN（`registerOpenUrl` 注册），非阻塞投递；
  - Pascal 侧符号为 `ohos_open_url`，`fpg_utils_impl.inc` 的 `fpgOpenURL` dlsym 调用。

#### 4.8.3 `notify_first_frame`

```c
void notify_first_frame(void* handle);
```

- **功能**：Pascal 第一次 `FlushBuffer` 成功后调用，通知 ETS 打开该窗口 XComponent 显示门（`contentReady`）。
- **目的/意义**：消除“窗口 show → 首帧 flush”之间 XComponent 黑屏闪现。
- **注意事项**：每窗口只需/只应调用一次首帧；重复调用无害但无意义；句柄无效时安全返回。

### 4.9 系统文件选择器与文件流

#### 4.9.1 `show_file_picker`

```c
void show_file_picker(int reqId, int pickerType, const char* optsJson);
```

- **功能**：拉起系统 FileManager/Gallery/Audio 选择器（免权限）。
- **参数**：
  - `reqId`：Pascal 生成的递增整数，ETS 完成后经 `notifyFilePickerResult` 原样回传；
  - `pickerType`：`0=文档打开`、`1=图片/视频`、`2=音频`、`3=文档另存为`（回传可写 URI）；
  - `optsJson`：紧凑 JSON，如 `{"suffix":[".txt",".pdf"],"max":5}`、`{"mime":"image","max":1}`；type=3 时 `{"name":"ESC.INF","suffix":[".inf"]}`。
- **结果**：`{"uris":["file://..."],"code":0}`，`code: 0=成功 -1=取消 -2=错误`。
- **注意事项**：结果通道固定走命令 20（tsfn），`file_picker_result` 槽位允许 Pascal 晚注册（nil 安全）。

#### 4.9.2 `file_io`

```c
void file_io(int reqId, int op, int arg, int64_t offset, int64_t length,
             const char* uri, const void* data, int dataLen);
```

- **功能**：对 picker 授权 URI（`file://docs/...`）做同步随机读写（pread/pwrite 语义），ETS 侧用 `fs.*Sync` 实现。
- **参数**：

| 字段 | 说明 |
|---|---|
| `reqId` | Pascal 生成，结果经 `notifyFileIoResult` 原样回传 |
| `op` | 0=open 1=read 2=write 3=truncate 4=fsync 5=close 6=stat 7=delete |
| `arg` | open=OpenMode 位掩码；read/write/truncate=文件句柄 id |
| `offset` | read/write 文件偏移（64 位，不移动共享句柄位置） |
| `length` | read 字节数 / truncate 新大小 |
| `uri` | open/stat/delete 目标 URI（其余可空） |
| `data/dataLen` | write 数据；C++ 复制后立即 `delete[]` **所有权不转移** |

- **结果**：`notifyFileIoResult(reqId, '{"code":0,"n":123,"size":456,"handle":1}', data?)`；`code=0` 成功，`handle` 为 open 结果。
- **注意事项**：`data` 可能较大（4096 payload 之外的二进制走 `bin` 字段，无此限制）；回调 data 指针仅本次有效。

### 4.10 调试辅助

#### 4.10.1 `getModalReqId`（NAPI 侧）

- ArkTS 调用，返回当前模态窗口 reqId（-1 无）。用于事件路由判断。

---

## 5. Pascal → C++ 回调 API（`FpBridgePascalApi`）

以下函数由 C++ 调用、Pascal 实现。Pascal 侧实现原则：**入队 + 唤醒**（UI 线程消费），不得在回调内直接操作 UI。返回 `0=成功 -1=失败`（多数槽位如此，个别为 `void`）。

### 5.1 显示初始化（启动期同步调用）

#### 5.1.1 `set_screen_size`

```c
void set_screen_size(int w, int h, int dpi, float density);
```

- **功能**：下发默认显示屏物理尺寸、DPI、密度（`VirtualPixelRatio`），Pascal 调 `ApplyScreenScaling` 计算 `gScaleFactor*`。
- **意义**：后续所有坐标/字体/画布缩放的基础；**唯一必需函数**，缺失则 `fp_bridge_init` 返回 -2。
- **参数**：`w/h` 物理像素；`dpi` 物理 DPI；`density` 密度倍数（1.0=160dpi 基准）。
- **调用时机**：C++ `PascalThread`，Pascal 应用 `MainProc` 运行前（同步）。
- **注意事项**：此时 `fpgApplication` 可能为 nil，Pascal 实现需容忍（当前直接写全局）。

#### 5.1.2 `set_zoom_scale`

```c
void set_zoom_scale(float scale);
```

- **功能**：设置用户缩放倍数（`gZoomScale`）。
- **调用时机**：启动期，与 `set_screen_size` 相邻。

### 5.2 输入注入

> 坐标统一为**物理像素**（ETS 报 vp，C++ 已乘 `g_density`）。触摸/鼠标/滚轮/悬停按窗口句柄路由。

#### 5.2.1 `inject_touch_to_window`

```c
int inject_touch_to_window(void* winHandle, float x, float y, int action);
```

- **参数**：`action`：`0=Down 1=Move 2=Up`（OH_TOUCH_*）。
- **调用方**：NAPI `onTouchEvent`（ETS 触摸含长按/右键模拟路径）。
- **注意事项**：Pascal 侧线程安全入队；窗口句柄为 `OHNativeWindow*`，Pascal 用 `FindWindowByHandle` 解析。

#### 5.2.2 `inject_key_event`

```c
int inject_key_event(int keyCode, int action, int modifiers, unsigned int unicodeChar);
```

- **参数**：
  - `keyCode`：OHOS KeyCode（如 2000='0'、2017-2042='A'-'Z'、2050=空格、2055=退格、2071=Delete 等）；
  - `action`：`0=Down 1=Up`；
  - `modifiers` 位：`1=CTRL 2=SHIFT 4=ALT 8=META`；
  - `unicodeChar`：可打印字符码点（无则 0；仅 DOWN + 无 CTRL/ALT/META 时才会生成 KEYCHAR 插入）。
- **调用方**：NAPI `onKeyEvent`（物理键盘/隐藏 TextInput/IME 转发）。
- **注意事项**：
  - 软键盘删除键双路径（IME delete + 物理键）已由 ETS 侧 250ms 去重，Pascal 不必重复处理；
  - 修饰键状态由 Pascal 自维护（`gShift/Ctrl/Alt`），ETS 传入的 modifiers 可能简化，最可靠的是键码追踪。

#### 5.2.3 `inject_mouse_event`

```c
int inject_mouse_event(void* winHandle, float x, float y, int action, int button);
```

- **参数**：`action`（ETS 已归一为 OH_TOUCH 语义）`0=Down 1=Move 2=Up`；`button` `1=左键 2=右键`。
- **调用方**：NAPI `onMouseEvent`（真机鼠标主通道）。
- **注意事项**：模拟器同时发 onTouch/onMouse 时 ETS 已抑制 onMouse；Pascal 另有 50ms MOUSEDOWN 去重。

#### 5.2.4 `inject_wheel_event`

```c
int inject_wheel_event(void* winHandle, float x, float y, int delta);
```

- **参数**：`delta` 单位“格”：向前滚 `-1`，向后 `+1`（ETS `axisVertical` 归一后 50ms 去抖）。
- **目的/意义**：鼠标滚轮在 XComponent 无原生滚动，必须注入 fpGUI（`FPGM_SCROLL`）。

#### 5.2.5 `inject_hover_event`

```c
int inject_hover_event(void* winHandle, float x, float y);
```

- **功能**：无按键悬停移动（菜单高亮、提示框跟踪）。
- **注意事项**：不得与 drag 混淆；Pascal 用 `gLastDownButton` 区分悬停/拖拽。

#### 5.2.6 `inject_text`

```c
void inject_text(const char* text, int length);
```

- **功能**：IME 提交的文本（UTF-8）注入焦点控件。
- **注意事项**：C++ 的 NAPI 缓冲上限 4096，`length` 可能被截断超出实际串长度；Pascal 侧用 `StrLen` 二次校正（已实现），保证不越界读取。

#### 5.2.7 `inject_delete_chars`

```c
int inject_delete_chars(int count);
```

- **功能**：IME deleteLeft（退格），删除光标前 `count` 个字符。
- **注意事项**：`count < 1` 直接返回 -1。

#### 5.2.8 `inject_delete_right_chars`

```c
int inject_delete_right_chars(int count);
```

- **功能**：IME deleteRight（前向删除）。
- **注意事项**：同 5.2.7。

#### 5.2.9 `inject_move_cursor`

```c
int inject_move_cursor(int direction);
```

- **参数**：`1=Up 2=Down 3=Left 4=Right`（`OHOS_CURSOR_*`）。
- **功能**：IME 光标方向键（软键盘上下左右）。

### 5.3 窗口事件

#### 5.3.1 `inject_window_resized`

```c
int inject_window_resized(void* winHandle, int w, int h);
```

- **功能**：ETS `onWindowResized` 反馈客户区新尺寸（物理 px）。
- **目的/意义**：驱动 Pascal 重建缓冲/重排布局；C++ 侧同时更新权威 surface 尺寸与 buffer 几何。
- **注意事项**：
  - 去重：C++ 对相同尺寸只送一次；
  - 创建握手期（句柄未登记）先暂存 `g_pendingResize`，登记后补送；
  - 被系统强制最大化时 surface 才是权威，客户端逻辑尺寸也随之更新。

#### 5.3.2 `inject_window_moved`

```c
int inject_window_moved(void* winHandle, int x, int y);
```

- **功能**：标题栏拖动/最大化后窗口屏幕位置（物理 px）同步。
- **目的/意义**：触摸坐标映射（屏幕坐标-窗口位置）与弹窗定位基准随之修正。
- **注意事项**：Pascal 经 win-cmd 队列串行化到 loop 线程执行 `SetScreenPosition`。

#### 5.3.3 `inject_window_closed`

```c
int inject_window_closed(void* winHandle);
```

- **功能**：系统标题栏 X 关闭后通知 Pascal 走标准关闭流程（`FPGM_CLOSE` → CloseQuery/OnClose/释放）。
- **注意事项**：native 句柄已由 C++ 在 `OnWindowClosed` 中销毁并移出 `g_winMap`；Pascal 只做逻辑收尾。

#### 5.3.4 `can_close`

```c
int can_close(void* winHandle);   // 1=可关 0=不可
```

- **功能**：标题栏 X 关闭前查询业务 `CloseQuery`。
- **调用方**：ETS `windowWillClose` → NAPI `queryCanClose`（**JS 线程同步调用**）。
- **注意事项**：
  - Pascal 实现为阻塞等待（≤500ms），超时默认返回 1（可关）；
  - 回调在 JS 线程执行，Pascal 侧用 `TEvent` 等待 loop 线程结果，勿在回调内做重活。

#### 5.3.5 `force_window_refresh`

```c
void force_window_refresh(void* winHandle);
```

- **功能**：主动刷新窗口：`Invalidate` 重绘 + `DoUpdateWindowPosition` 重发 move/resize。
- **调用方**：ETS `refreshWindow`（setupMainWindow 尺寸确认后）。
- **目的/意义**：校正首帧前的窗口位置/尺寸与重绘，消除空白/错位。

### 5.4 系统集成

#### 5.4.1 `inject_tray_event`

```c
int inject_tray_event(int eventType, const char* menuId);
```

- **参数**：`0=左键点击 1=右键点击 2=菜单项选中(menuId) 3=add结果("ok"/"fail")`。
- **注意事项**：`eventType=3 'ok'` 时 Pascal 置 `gTrayActive=True`，`'fail'` 复位。

#### 5.4.2 `update_configuration`

```c
void update_configuration(const char* config);
```

- **功能**：系统 Configuration 变更/首启初始化下发，紧凑 KV 串 `k=v;k2=v2;...`（值不含 `;`/`=`）。
- **键位**：

| 键 | 含义 | 取值 |
|---|---|---|
| `l` | 语言 | 如 `zh-Hans` |
| `c` | 色彩模式 | -1=NOT_SET 0=DARK 1=LIGHT |
| `d` | 屏幕方向 | -1=NOT_SET 0=竖 1=横 |
| `den` | 密度倍数 | 如 `3.0` |
| `denKonf` | 密度枚举 | 120/160/240/320/480/640 |
| `i` | 显示屏 id | 整数 |
| `p` | 是否有指针设备 | 0/1 |
| `f` | 字体 id | 字符串 |
| `fs` | 字体缩放 | 如 `1.0` |
| `fw` | 字重缩放 | 如 `1.0` |
| `mcc/mnc` | 运营商 | 字符串 |
| `lc` | locale | 字符串 |
| `tf` | 时间制式 | `12`/`24` |
| `df` | 日期格式 | `mm/dd/yyyy` 等 |

- **调用方**：PascalThread（首启 native 值）与 NAPI `notifyConfiguration`（ETS 事件）。
- **注意事项**：
  - 启动期（`fpgApplication=nil`）就地写全局；运行期 Pascal 投递 UI 队列，置 `gCfgChangedFlags` 并发送 `FPGM_OHOS_CONFIG_CHANGED`；
  - ETS 在桥连接前的推送由 C++ `g_pendingConfig` 暂存，连接时补发。

#### 5.4.3 `set_launch_params`

```c
void set_launch_params(const char* payload);
```

- **功能**：热启动（`onNewWant`）载荷 JSON 注入：`{"uri","action","entities","parameters"}`。
- **调用方**：NAPI `setLaunchParams`（ETS）；桥未连接时 C++ 暂存 `g_pendingLaunchParams`，连接时补发。
- **注意事项**：框架只存全局并回调 `OnOhosLaunchParams` 事件，JSON 解析由应用完成；连接前推送不丢失。

#### 5.4.4 `inject_app_args`

```c
void inject_app_args(const char* payload, const char* appArgs);
```

- **功能**：启动前注入：`payload` → `gLaunchParams`；`appArgs` → `OhosArgs`（已在 C++ 完成 `%xxx%` 占位符替换）。
- **调用方**：PascalThread，调用 `MainProc()`/`main()` **之前**（同步）。
- **注意事项**：冷启动的原始载荷也由此进入（`MainProc` 的 argv[1] 路径之外的第二通道）；命令行参数格式 `-b debug key=value`，由 `TfpgOhosCmdLineParams` 消费。

### 5.5 定时器

#### 5.5.1 `timer_tick`

```c
void timer_tick(void);
```

- **功能**：ETS `setInterval` tick → Pascal `WakeChannel.Signal` 唤醒事件循环 → `fpgCheckTimers`。
- **目的/意义**：取代 select 超时轮询（500ms cap），短定时器精度靠 `fpgClosestTimer` 双保险；无定时器时 ETS 停表零轮询（省电）。

#### 5.5.2 `timer_query`

```c
int timer_query(void);
```

- **功能**：返回 `1=有活动定时器 0=无`。
- **意义**：ETS 注册期补查，防“早期通知丢失”导致 setInterval 未启动。

### 5.6 系统拖拽（仅 DND 开启窗口收到事件）

#### 5.6.1 `inject_drag_event`

```c
int inject_drag_event(void* winHandle, int kind, float x, float y, const char* summaryJson);
```

- **参数**：`kind`：`0=enter 1=move 2=leave`；`x/y` 物理 px；`summaryJson` 拖拽摘要。
- **注意事项**：**不阻塞**（直接入队）；ETS 侧仅在 `isDndEnabled` 为真时投递。

#### 5.6.2 `drag_process_drop`

```c
int drag_process_drop(void* winHandle, float x, float y, const char* recordsJson);
```

- **功能**：drop 同步应答，返回 `(accept << 8) | action`。
- **参数**：`recordsJson` 为 UDMF 记录 JSON；`accept=1/0`；`action ∈ TfpgDropAction`（0=ignore..4=ask）。
- **调用方**：ETS `onDrop`（**阻塞等待 ≤2500ms**，超时按拒绝 0 处理）。
- **注意事项**：Pascal 通过 win-cmd 队列串行化到 loop 线程执行；单会话串行，参数经 `gDragSession` 暂存。

#### 5.6.3 `inject_drag_end`

```c
int inject_drag_end(int64_t sessionId, int result);
```

- **功能**：拖拽会话结束（ETS `executeDrag` 回调，成功/取消/失败均会回调）。
- **目的/意义**：置 `Result` + `EndEvent` + 唤醒事件循环，否则 Pascal `Execute` 最长卡 60s。
- **注意事项**：`sessionId` 必须与 `drag_start` 返回值一致才生效。

### 5.7 文件回传

#### 5.7.1 `file_picker_result`

```c
void file_picker_result(int reqId, const char* resultJson);
```

- **功能**：系统文件选择器结果回传：`{"uris":["file://..."],"code":0}`（0=成功 -1=取消 -2=错误）。
- **注意事项**：
  - 回调在 **JS 线程**执行；Pascal 实现只做“拷贝串 + SetEvent”；
  - 允许 `nil`（扩展单元未注册），C++ 判空丢弃并记日志；
  - `reqId` 与 `show_file_picker` 发起值一致。

#### 5.7.2 `file_io_result`

```c
void file_io_result(int reqId, const char* json,
                    const unsigned char* data, int dataLen);
```

- **功能**：文件流操作结果回传：`{"code":0,"n":123,"size":456,"handle":1}`；`data` 为读操作字节。
- **注意事项**：`data` 指针仅本次调用有效，Pascal **必须立即拷贝**；`code` 非 0 表示失败。

### 5.8 动态分发

#### 5.8.1 `dispatch`

```c
char* dispatch(const char* opType, const char* params);
```

- **功能**：ArkTS `dispatch(op, params)` 的 Pascal 入口。Pascal 查注册表：
  - 命中同步处理器 → 立即返回结果 JSON（无 `jobId`）；
  - 命中异步处理器 → 返回 `{"ok":true,"jobId":"job_N"}`，完成后经 `dispatch_result` 回传；
  - 未命中/错误 → 返回错误信封 `{"ok":false,"code":...}`；
  - `op="__cancel"`：取消异步作业 `{"jobId":"..."}`。
- **目的/意义**：ArkTS 与 Pascal 业务解耦的动态调用通道，无需每加一个接口改 ABI。
- **返回值**：Pascal 内存管理器分配的 `PChar`，C++ 用后经 `dispatch_free` 释放。
- **注意事项**：
  - 立即返回，**不得阻塞**；
  - 异步并发上限 `OHOS_DISPATCH_MAX_ASYNC=4`，作业超时 30s；
  - opType 大小写不敏感。

#### 5.8.2 `dispatch_free`

```c
void dispatch_free(char* p);
```

- **功能**：释放 `dispatch` 返回的字符串（v7 新增）。
- **注意事项**：C++ 仅在指针非空且槽位存在时调用；缺失会导致内存泄漏。

### 5.9 ArkTS 反向调用结果

#### 5.9.1 `arkts_invoke_result`

```c
void arkts_invoke_result(const char* callId, const char* resultJson, int32_t failed);
```

- **功能**：`ohos_arkts_invoke` 的结果回传（v13）。
- **调用时机**：C++ 在 **JS 线程**执行 ArkTS 方法后调用。
- **注意事项**：
  - Pascal 实现必须快速：拷贝 `callId`/`resultJson` → 锁内匹配 pending → `SetEvent`；
  - `resultJson` 生命周期仅本次调用，必须拷贝；
  - 未注册（nil）时 C++ 记录日志丢弃结果；
  - 详见第 6 章。

---

## 6. arkTS_Invoke：Pascal → ArkTS 反向调用（v13）

### 6.1 调用入口

```c
int32_t ohos_arkts_invoke(const char* callId, const char* method, const char* params);
```

- **功能**：Pascal 任意线程请求执行 ArkTS 已注册方法。
- **调用链**：`cppApi.arkts_invoke` 槽位（或 `LibBridgeSym('ohos_arkts_invoke')` dlsym 兜底）→
  - 调用方在 JS 线程（重入场景）→ **内联快路径**立即执行；
  - 其他线程 → TSFN 投递到 JS 线程执行。
- **参数**：
  - `callId`：调用方生成的唯一标识（Pascal `ArkTS_Invoke` 用 `p_N`，`ArkTS_InvokeAsync` 用 `n_N`）；结果按此回传；
  - `method`：方法名（点分路径，大小写不敏感，长度 ≤128）；
  - `params`：JSON 字符串；空串会被兜底为 `"{}"`。
- **返回码**：
  | 码 | 含义 |
  |---|---|
  | `0` | 已受理（结果异步经 `arkts_invoke_result` 回传；内联路径受理即已执行） |
  | `-1` | 入参错误（callId/method 空或 method 超长） |
  | `-2` | 未初始化（`ArkInvokeInit` 未执行；非 JS 线程投递还需 TSFN 可用） |
  | `-3` | 方法未注册且无 dispatcher |
  | `-4` | 队列满 / TSFN 已关闭 |
- **注意事项**：
  - 结果回传与注册表访问的线程铁律见 `arkts_invoke.cpp` 头注释；
  - 投递路径 FIFO 保序（`napi_tsfn_blocking`）。

### 6.2 ArkTS 注册面（NAPI 导出）

| NAPI | 签名 | 说明 |
|---|---|---|
| `registerInvokeMethod` | `(name: string, fn: (params: string) => string)` | 注册单个方法；需 `this` 的先 `.bind(obj)` |
| `registerInvokeNamespace` | `(prefix: string, obj: object\|Function)` | 推荐：递归注册对象/类实例的公有方法（原型链自有属性，深度 8，上限 512，跳过 `_` 前缀与 `constructor`，自动 bind）；传函数等价 `registerInvokeMethod` |
| `registerInvokeDispatcher` | `(fn: (method, params) => string)` | 统一分发兜底：未命中方法时调用 |
| `unregisterInvokeMethod` | `(name: string)` | 注销单个方法 |
| `clearInvokeMethods` | `()` | 清空方法表+分发器（Ability onDestroy/热重启） |
| `listInvokeMethods` | `() => string[]` | 已注册方法展示名（原始大小写） |
| `invokeLocal` | `(method, params) => string` | JS 线程直查注册表同步执行（relay 自测；永不抛异常，错误以信封返回） |

### 6.3 内置方法与结果信封

- 内置方法（无需注册）：`__ping` → `{"ok":true,"pong":true}`；`__list` → 已注册方法列表。
- 方法返回值转换：
  - `undefined/null` → `{"ok":true}`；
  - `string` → 原样返回；
  - 其他 → `JSON.stringify`，失败降级 `String(v)`。
- 错误信封（`failed=1`，`resultJson` 仍为 JSON 串）：
  - `NO_METHOD`、`JS_EXCEPTION`（含 message/stack）、`CALL_FAIL`、`NOT_CONNECTED`。
- Pascal 侧封装（`fpg_ohos_invoke.pas`）：
  - `ArkTS_Invoke(method, params, timeout=5000)`：同步等待结果，返回结果串或错误信封；
  - `ArkTS_InvokeAsync(method, params)`：即发即忘，返回受理码；
  - `ArkTS_InvokeReady`：调用入口是否可用。

---

## 7. 典型调用链示例

### 7.1 窗口创建（show）

```
Pascal TfpgOhosWindow.Show → DoAllocateWindowHandle
  → _ohos_create_window(@opts)                [同步阻塞 ≤10s]
      → TSFN 命令 0 → ETS createWindowFromNative
          → setupMainWindow / createSubWin + XComponent(xc_fpg_N)
          → XComponent.onLoad → NAPI onSurfaceReady(reqId, xcId, surfaceId, w, h)
              → CreateNativeWindowFromSurfaceId + SET_BUFFER_GEOMETRY
      ← C++ 返回 OHNativeWindow*
  → Pascal 首帧渲染 + FlushBuffer
  → _notify_first_frame(handle) → TSFN 命令 19 → ETS 打开显示门（防黑屏）
```

### 7.2 鼠标点击（真机）

```
ETS XComponent.onMouse → onMouseEvent(reqId, x, y, act, btn)  [vp/屏幕坐标]
  → C++ OnMouseEvent: px = vp × density → g_inject_mouse(win, px, py, act, btn)
      → Pascal EnqueueMouseEvent → UI 线程解析窗口/控件 → 分发 FPGM_MOUSEDOWN/UP
```

### 7.3 文件选择器 + 文件流

```
Pascal ShowFilePicker
  → _ohos_show_file_picker(reqId, 0, '{"suffix":[".txt"],"max":1}')
      → 命令 20 → ETS showFilePicker → 系统选择器
  ← ETS notifyFilePickerResult(reqId, '{"uris":["file://docs/..."],"code":0}')
      → pascalApi.file_picker_result → Pascal 拷贝+SetEvent
Pascal 打开选中 URI
  → _ohos_file_io(reqId, FILE_IO_OPEN, mode, 0, 0, uri, nil, 0)
      → 命令 21 → ETS FpgFileIo.fs.openSync
  ← notifyFileIoResult(reqId, '{"code":0,"handle":1,"size":123}') → Pascal
  → _ohos_file_io(reqId, FILE_IO_READ, handle, offset, len, nil, nil, 0)
  ← notifyFileIoResult(reqId, '{"code":0,"n":len}', ArrayBuffer) → Pascal 立即拷贝
```

### 7.4 ArkTS 反向调用

```
ArkTS 初始化：registerInvokeNamespace('ui', uiService)
Pascal 任意线程：
  ArkTS_Invoke('ui.showToast', '{"text":"hi"}')
    → pending['p_1'] 登记 → ohos_arkts_invoke('p_1','ui.showToast','{...}')
        → TSFN/inline → JS 线程执行 uiService.showToast(params)
        → DeliverResult → pascalApi.arkts_invoke_result('p_1', '{"ok":true}', 0)
    ← Pascal InvokeResultCallback：拷贝+锁定 pending+SetEvent → ArkTS_Invoke 返回
```

---

## 8. 开发注意事项汇总（Checklist）

**ABI / 版本**
- [ ] 结构体字段只能尾部追加；任何变更同步 `fp_bridge.h` 与 `fpg_ohos.pas` 的 `OHOS_BRIDGE_VERSION` 并 +1。
- [ ] FPC cdecl 传递记录指针必须显式指针（`POHOSExportTable`），不可用 `const record` 按值参数。
- [ ] `TOHOSWindowOptions` 必须保持 `{$packrecords C}` 4 字节对齐，字段顺序与 `WindowOptions` 完全一致。

**线程**
- [ ] `inject_*` 回调内只入队+唤醒，不直接操作 UI；同步语义回调（`can_close`、`drag_process_drop`）注意超时兜底值。
- [ ] 桥接导出函数可从任意线程调用，但 `create_window` 会阻塞（≤10s），避免在 UI 热点路径频繁调用。
- [ ] `arkts_invoke_result`/`file_picker_result`/`file_io_result` 在 JS 线程执行，实现必须快（拷贝+锁+SetEvent）。

**内存**
- [ ] `get_user_dir`/`clipboard_get_text` 返回 `strdup` 串，Pascal 必须 `free`；`dispatch` 返回串必须走 `dispatch_free`。
- [ ] `file_io_result.data`、`arkts_invoke_result.resultJson` 仅本次调用有效，必须立即拷贝。
- [ ] `file_io` 的写数据由 C++ 复制，调用方 buffer 可立即复用/释放。

**功能细节**
- [ ] `get_user_dir` 的 `dirType` ，扩展目录用 101/102。
- [ ] 坐标：ETS 报 vp，C++ 转物理 px 后注入 Pascal；resize/move 均为物理 px。
- [ ] 触摸 action `0/1/2`、按键 action `0/1`、修饰位 `1/2/4/8`、光标方向 `1..4`，不要混用。
- [ ] 拖拽 `inject_drag_end` 在成功/取消/失败路径都必须回调，否则卡 60s。
- [ ] 首帧通知 `notify_first_frame` 每窗口一次，配合 `set_window_visible` 防黑屏。
- [ ] `set_window_attributes` 位定义对齐 `fpg_base.pas`（waFullScreen=8、waBorderless=16、waSystemStayOnTop=128）。
- [ ] 托盘仅 2in1/PC 有效；`tray_add` 结果经 `inject_tray_event(3, 'ok'/'fail')` 异步反馈。
- [ ] `update_configuration` KV 值不得包含 `;`/`=`；启动期与运行期走不同路径（就地/队列）。
- [ ] 扩展单元（dispatch/filepicker/filestream/invoke）通过“补槽+重连”注册，需保证 uses 顺序在 `fpg_ohos` 之后。

**构建**
- [ ] 修改桥 ABI 或 fpg_ohos.pas 后，Pascal 侧使用工程 `build.bat -B` 全量重编（避免 PPU 级联触发 FPC 崩溃），并同步部署 `libhelloworld.so` 与 `libfp_bridge.so`。

---

## 9. 版本演进历史

| 版本 | 变更 |
|---|---|
| v5 | `TOHOSExportTable` 增 `set_launch_params`（启动载荷） |
| v6 | 增 `dispatch` 动态分发入口 + `dispatch_result` 回调 |
| v7 | 增 `dispatch_free` 释放入口返回的 PChar |
| v8 | `TOHOSBridgeCallbacks` 增 `tray_add/tray_set_menu/tray_remove` |
| v9 | 清理废弃字段（PascalApi 删 `inject_touch_event/show_keyboard/clipboard*`；CppApi 删 `get_actual_window_position`） |
| v10 | `TOHOSBridgeCallbacks` 增 `get_window_state`（查询缓存窗口状态） |
| v11 | `TOHOSBridgeCallbacks` 增 `open_url`（打开 URL/文档） |
| v12 | `TOHOSBridgeCallbacks` 增 `notify_first_frame`（首帧上屏通知，消除黑屏闪现） |
| **v13（当前）** | `TOHOSExportTable` 增 `arkts_invoke_result`；`TOHOSBridgeCallbacks` 增 `arkts_invoke`（Pascal → ArkTS 反向调用） |

---

*文档依据源码：`fp_bridge.h`（106 行）、`fp_bridge.cpp`（972 行）、`napi_init.cpp`（2003 行）、`arkts_invoke.cpp`（587 行）、`binder_bridge.cpp`（103 行）、`types/libfp_bridge/Index.d.ts`、`fpg_ohos.pas`、`fpg_ohos_dispatch.pas`、`fpg_ohos_invoke.pas`（OHOS_BRIDGE_VERSION 13）。*
