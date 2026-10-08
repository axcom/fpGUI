# fpGUI OHOS 系统托盘（System Tray）使用手册

> 适用版本：fpGUI OHOS 移植（fpg_ohos.pas / OHOS_BRIDGE_VERSION = 11）
> 适用平台：HarmonyOS 2in1 / PC 设备（状态栏托盘区）
> 关联文件：`framework/src/main/pascal/gui/fpg_trayicon.pas`、`framework/src/main/pascal/corelib/ohos/fpg_ohos.pas`、`entry/src/main/ets/common/TrayManager*.ets`、`entry/src/main/cpp/napi_init.cpp`

---

## 目录

1. [概述](#1-概述)
2. [能力矩阵与平台差异](#2-能力矩阵与平台差异)
3. [架构与原理](#3-架构与原理)
4. [Pascal API 参考](#4-pascal-api-参考)
5. [快速上手（最小示例）](#5-快速上手最小示例)
6. [完整示例：常驻托盘 + 关闭到托盘](#6-完整示例常驻托盘--关闭到托盘)
7. [关闭到托盘的四个陷阱（重要）](#7-关闭到托盘的四个陷阱重要)
8. [接入新工程清单](#8-接入新工程清单)
9. [常见问题 FAQ](#9-常见问题-faq)
10. [调试指南](#10-调试指南)
11. [限制与后续计划](#11-限制与后续计划)

---

## 1. 概述

fpGUI 的系统托盘在 HarmonyOS 上映射为**状态栏托盘区**（`@kit.DeskTopExtensionKit` 的 `statusBarManager`）。应用可以获得：

- **托盘图标**（黑白双态，随系统主题渲染）
- **右键菜单**（系统原生渲染的菜单分组，点击回传菜单项 id）
- **左键点击事件**（可绑定"恢复主窗口"等动作）
- **左键快捷操作面板**（`StatusBarViewExtensionAbility`，可自定义 ArkUI 面板）

Pascal 侧保持 fpGUI 跨平台 API 不变：应用只使用 `TfpgSystemTrayIcon`（widget 层），平台差异全部由 `TfpgOhosSystemTrayIcon`（handler 层）与 C++/ETS 桥承担。

### 一句话上手

```pascal
uses fpg_trayicon, fpg_menu;

FTrayMenu := TfpgPopupMenu.Create(Self);
FTrayMenu.AddMenuItem('显示主窗口', '', @TrayClick);
FTrayMenu.AddSeparator;
FTrayMenu.AddMenuItem('退出', '', @TrayExit);

FTray := TfpgSystemTrayIcon.Create(Self);
FTray.Hint := 'My App';                 { 托盘悬浮提示 / 面板标题 }
FTray.PopupMenu := FTrayMenu;           { 右键菜单（自动序列化） }
FTray.OnClick := @TrayClick;            { 左键点击 }
FTray.Show;                             { 上架托盘 }
```

---

## 2. 能力矩阵与平台差异

| 能力 | HarmonyOS（2in1/PC） | OpenHarmony | 说明 |
|---|---|---|---|
| 托盘图标 | ✅ 支持 | ❌ 不支持 | OH 无 `DeskTopExtensionKit`，`TrayManager.open.ets` 空实现 |
| 右键菜单 | ✅ 支持 | ❌ 不支持 | 菜单 JSON → `StatusBarGroupMenu` 分组 |
| 左键点击 | ✅ 支持 | ❌ 不支持 | `statusBarIconClick` 事件 |
| 快捷操作面板 | ✅ 支持 | ❌ 不支持 | 需注册 `statusBarView` 扩展 |
| `IsSystemTrayAvailable` | 运行时经 add 结果确认 | 恒 `False` | add 失败回传 `evType=3 'fail'` |
| 气泡通知 `ShowMessage` | ⚠️ 占位（未实现） | ❌ | `SupportsMessages=True`，但 handler 未覆写（TODO） |

**降级设计**：OpenHarmony 或托盘不可用时，`IsSystemTrayAvailable` 返回 `False`，应用应据此走普通关闭/退出逻辑（示例见第 6 节）。

---

## 3. 架构与原理

### 3.1 分层结构

```
┌────────────────────────────────────────────────────────────┐
│ 应用代码（Pascal）                                          │
│   TfpgSystemTrayIcon（跨平台 widget，fpg_trayicon.pas）      │
│     └─ FSysTrayHandler : TfpgSystemTrayHandler              │
├────────────────────────────────────────────────────────────┤
│ 平台 Handler（fpg_ohos.pas）                                │
│   TfpgOhosSystemTrayIcon                                    │
│     · Show      → SyncMenu + _ohos_tray_add    (CMD 8)      │
│     · Hide      → _ohos_tray_remove            (CMD 10)     │
│     · SyncMenu  → _ohos_tray_set_menu          (CMD 9)      │
│     · HandleTrayEvent ← 事件回放（OnOhosTray 全局回调）      │
├────────────────────────────────────────────────────────────┤
│ C++ 桥（libentry.so / libfp_bridge.so）                      │
│   正向：ohos_tray_add / ohos_tray_set_menu / ohos_tray_remove│
│         → SendNativeCommand(NativeCommandData)               │
│         → napi_threadsafe_function（任意线程安全投递）        │
│   反向：NAPI onTrayEvent(evType, menuId)                     │
│         → g_inject_tray = ohos_inject_tray_event             │
├────────────────────────────────────────────────────────────┤
│ ETS（ArkTS，TrayManager.ets）                                │
│   正向：Index.ets handleNativeCommand case 8/9/10            │
│         → TrayManager.add / setMenu / remove                 │
│         → statusBarManager.addToStatusBar /                  │
│           updateStatusBarMenu / removeFromStatusBar          │
│   反向：statusBarManager.on('rightMenuClick' /               │
│           'statusBarIconClick')                              │
│         → testNapi.onTrayEvent(...)                          │
└────────────────────────────────────────────────────────────┘
```

### 3.2 线程模型（关键）

托盘事件**绝不**在 NAPI/ETS 线程直接回调进 fpGUI（fpGUI 非线程安全）。全链路为：

```
ETS 事件
  → C++ OnTrayEvent
  → Pascal ohos_inject_tray_event()            [任意线程]
  → EnqueueTrayEvent()：New + FTrayQueueLock 保护入队
  → WakeChannel.Signal 唤醒 select
  → fpGUI loop 线程 DoWaitWindowMessage()
  → ProcessQueuedTrayEvents()：锁内取事件、锁外派发
  → OnOhosTray(evType, menuId)                 [loop 线程]
  → TfpgOhosSystemTrayIcon.HandleTrayEvent
```

- 队列：`FTrayEventQueue: TList`（`PfpgOhosTrayEvent`）
- 锁：`FTrayQueueLock: TCriticalSection`（NAPI 注入 vs loop 消费，同 EventQueue/ResizeQueue 模式）
- 消费点：`TfpgOhosApplication.DoWaitWindowMessage` 内 `ProcessQueuedTrayEvents`（fpg_ohos.pas，约 6615 / 6670 行）

### 3.3 命令协议（Pascal → ETS）

C++ 的 `NativeCmdType` 定义：

| CMD | 名称 | 载荷字段 | 说明 |
|---|---|---|---|
| 8 | `NATIVE_CMD_TRAY_ADD` | `title`（悬浮提示/面板标题）、`x`（图标索引） | 创建托盘图标 |
| 9 | `NATIVE_CMD_TRAY_SET_MENU` | `payload`（菜单 JSON，≤4096 字节） | 更新右键菜单 |
| 10 | `NATIVE_CMD_TRAY_REMOVE` | — | 移除托盘图标 |

> 命令经 `SendNativeCommand` → `napi_call_threadsafe_function(..., napi_tsfn_blocking)` 投递到 ETS UI 线程；`Index.ets` 的 `handleNativeCommand` 分发。

### 3.4 事件回传协议（ETS → Pascal）

`evType` 定义（`TfpgOhosTrayEvent.EventType`）：

| evType | 含义 | MenuId 内容 | Pascal 行为 |
|---|---|---|---|
| 0 | 左键点击图标 | `''` | 触发 `TfpgSystemTrayIcon.OnClick` |
| 1 | 右键点击图标 | `''` | 仅记录日志（菜单由系统渲染） |
| 2 | 右键菜单项选中 | `'m0'..'mN'` | 按 id 反查 `FMenuIndex` → 触发 `TfpgMenuItem.OnClick` |
| 3 | add 结果回传 | `'ok'` / `'fail'` | 更新 `gTrayActive` / `FActive` |

ETS 侧事件源：

- `statusBarManager.on('statusBarIconClick')` → 仅 `iconClickType === 'leftClick'` 时发 `evType=0`
- `statusBarManager.on('rightMenuClick')` → `eventData.data.menuCode` → `evType=2`

### 3.5 菜单序列化与 id 映射

`TfpgOhosSystemTrayIcon.SyncMenu` 把 `TfpgSystemTrayIcon.PopupMenu` 的组件序列化为扁平 JSON：

```json
[
  {"id":"m0","label":"显示主窗口"},
  {"id":"sep1","type":"sep"},
  {"id":"m1","label":"退出"}
]
```

序列化规则：

1. 遍历 `PopupMenu.ComponentCount`，仅处理 `Visible=True` 的 `TfpgMenuItem`
2. `Separator` 或 `Header` → `{"id":"sepN","type":"sep"}`（**不占用 `m` 序号**）
3. 普通项 → `{"id":"mK","label":"转义后文本"}`，`K` 从 0 递增；同时 `FMenuIndex.Add(item)`，**下标 K 与菜单项一一对应**
4. `label` 经 `OhosTrayEscapeJson` 转义（`"` `\` `\n` `\r` `\t`）
5. 菜单项选中回调：ETS 回传 `menuCode`（即 `'mK'`）→ Pascal 按 `'m'+IntToStr(i)` 反查 `FMenuIndex[i]` → `item.OnClick(item)`

ETS 侧 `buildGroups` 把扁平数组映射为系统分组结构：

- `type === 'sep'` → 结束当前分组，`sep` 之后的项进入新分组（系统以分组间分隔线呈现）
- 普通项生成 `StatusBarMenuItem`，**必须带 `menuAction`**（否则错误码 `1010720001`）：
  ```ts
  menuAction: {
    abilityName: 'Fp_bridgeAbility',   // 必须是当前模块的 Ability 名
    moduleName: 'fp_bridge',           // 必须是当前模块名
    notifyOnly: true                   // 不拉起 Ability，仅回传 rightMenuClick
  }
  ```

---

## 4. Pascal API 参考

### 4.1 `TfpgSystemTrayIcon`（应用唯一需要使用的类）

定义于 `framework/src/main/pascal/gui/fpg_trayicon.pas`，继承 `TfpgWidget`。

**published 属性**

| 属性 | 类型 | 说明 |
|---|---|---|
| `Hint` | `TfpgString` | 托盘图标悬浮提示；同时作为 `ohos_tray_add(title)` 的标题（缺省 `'fpGUI'`） |
| `ImageName` | `TfpgString` | widget 自绘图标名（`fpgImages` 资源名；OHOS 托盘图标由系统 rawfile 提供，此项仅影响自绘） |
| `PopupMenu` | `TfpgPopupMenu` | 右键菜单；`Show` 时自动序列化上送 |
| `OnClick` | `TNotifyEvent` | 左键点击托盘图标（参数为 widget 自身） |
| `OnMessageClicked` | `TNotifyEvent` | 气泡消息点击（预留） |
| `ShowHint` | `Boolean` | widget 悬浮提示开关 |
| `BackgroundColor` / `OnPaint` | — | widget 自绘相关 |

**方法**

| 方法 | 说明 |
|---|---|
| `Show` | 上架托盘：`SyncMenu` → `ohos_tray_add(Hint, 0)`；内部 `FActive` 乐观置真，`evType=3 'fail'` 时复位。**已激活时直接返回（幂等）**——运行期修改菜单后重复 `Show` 不会重发菜单，需 `Hide` 后再 `Show` 或后续 `RefreshMenu` API |
| `Hide` | 下架托盘：`ohos_tray_remove()`（CMD 10） |
| `IsSystemTrayAvailable: Boolean` | 当前托盘是否可用（= 最近一次 add 结果） |
| `SupportsMessages: Boolean` | OHOS 恒 `True`（通知实现未完成，见限制） |
| `ShowMessage(ATitle, AMessage, AMessageIcon, TimeoutHint=10000)` | 委托 handler（OHOS 当前为空操作） |

### 4.2 `TfpgOhosSystemTrayIcon`（平台 handler，一般无需直接使用）

定义于 `fpg_ohos.pas`，继承 `TfpgSystemTrayHandlerBase`。

- `FActive: Boolean` —— add 成功标志（`Show` 乐观置真，`evType=3` 修正）
- `FMenuIndex: TList` —— 菜单项反查表（`'mK'` ↔ `TfpgMenuItem`）
- `SyncMenu` —— 序列化菜单并调用 `_ohos_tray_set_menu`
- `HandleTrayEvent(evType, MenuId)` —— 事件分发（0→OnClick，2→菜单项 OnClick，3→FActive）

> 回调注册：构造时 `OnOhosTray := @HandleTrayEvent`（**全局单回调**，多实例时后注册者生效——应用应保持单托盘实例）。

### 4.3 相关全局

| 全局 | 位置 | 说明 |
|---|---|---|
| `gTrayActive: Boolean` | fpg_ohos.pas | add 结果（`'ok'`=True）；供降级判断 |
| `OnOhosTray` | fpg_ohos.pas | 托盘事件全局回调（由 handler 注册） |
| `_ohos_tray_add / _ohos_tray_set_menu / _ohos_tray_remove` | fpg_ohos.pas | C++ 桥函数指针（未装载则托盘 API 静默失败） |

---

## 5. 快速上手（最小示例）

```pascal
unit myform;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  fpg_base, fpg_main, fpg_form, fpg_menu, fpg_trayicon;

type
  TMainForm = class(TfpgForm)
  private
    FTray: TfpgSystemTrayIcon;
    FTrayMenu: TfpgPopupMenu;
    procedure TrayShowMain(Sender: TObject);
    procedure TrayQuit(Sender: TObject);
  public
    procedure AfterCreate; override;
  end;

implementation

procedure TMainForm.TrayShowMain(Sender: TObject);
begin
  { 恢复主窗口：句柄有效 → 仅恢复显示；句柄失效 → Show 重建 }
  if Window.HasHandle then
    Window.SetWindowVisible(True)
  else
    Show;
  BringToFront;
end;

procedure TMainForm.TrayQuit(Sender: TObject);
begin
  FTray.Hide;          { 先移除托盘图标 }
  Close;
end;

procedure TMainForm.AfterCreate;
begin
  inherited AfterCreate;
  Width := 600;
  Height := 400;
  WindowTitle := 'Tray Demo';

  FTrayMenu := TfpgPopupMenu.Create(Self);
  FTrayMenu.AddMenuItem('显示主窗口', '', @TrayShowMain);
  FTrayMenu.AddSeparator;
  FTrayMenu.AddMenuItem('退出', '', @TrayQuit);

  FTray := TfpgSystemTrayIcon.Create(Self);
  FTray.Hint := 'Tray Demo';           { 悬浮提示 }
  FTray.PopupMenu := FTrayMenu;        { 右键菜单 }
  FTray.OnClick := @TrayShowMain;      { 左键恢复主窗 }
  FTray.Show;                          { 上架（OpenHarmony 上会失败并降级） }
end;

end.
```

---

## 6. 完整示例：常驻托盘 + 关闭到托盘

以下模式来自 `test/helloworld/helloworld.lpr`（真机验证）。

```pascal
type
  TMainForm = class(TfpgForm)
  private
    FTray: TfpgSystemTrayIcon;
    FTrayMenu: TfpgPopupMenu;
    FTrayHideTimer: TfpgTimer;
    FForceExit: Boolean;
    procedure FormCloseQuery(Sender: TObject; var CanClose: boolean);
    procedure DoTrayHide(Sender: TObject);      { 延迟隐藏（主线程执行） }
    procedure TrayClick(Sender: TObject);        { 左键：恢复 }
    procedure TrayExit(Sender: TObject);         { 菜单"退出" }
  public
    procedure AfterCreate; override;
  end;

procedure TMainForm.AfterCreate;
begin
  inherited AfterCreate;
  { ... 窗口初始化 ... }
  OnCloseQuery := @FormCloseQuery;

  FTrayMenu := TfpgPopupMenu.Create(Self);
  FTrayMenu.AddMenuItem('显示主窗口', '', @TrayClick);
  FTrayMenu.AddSeparator;
  FTrayMenu.AddMenuItem('退出', '', @TrayExit);

  FTray := TfpgSystemTrayIcon.Create(Self);
  FTray.Hint := 'fpGUI Demo';
  FTray.PopupMenu := FTrayMenu;
  FTray.OnClick := @TrayClick;
  FTray.Show;
end;

{ 关闭到托盘：拦截标题栏 X。
  关键：windowWillClose → queryCanClose 查询链在 ETS JS 线程执行，
  此处【严禁直接 Hide/SetWindowVisible】——会经 napi_tsfn_blocking
  投递回被阻塞的 JS 线程 → 死锁（窗口既不关也不隐藏）。
  正确做法：CanClose := False，用 100ms 定时器延迟到 Pascal 主线程执行。 }
procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: boolean);
begin
  if FTray.IsSystemTrayAvailable and (not FForceExit) then
  begin
    CanClose := False;
    if FTrayHideTimer = nil then
    begin
      FTrayHideTimer := TfpgTimer.Create(100);
      FTrayHideTimer.OnTimer := @DoTrayHide;
      FTrayHideTimer.Enabled := True;
    end;
  end;
end;

procedure TMainForm.DoTrayHide(Sender: TObject);
begin
  if FTrayHideTimer <> nil then
  begin
    FTrayHideTimer.Enabled := False;
    FTrayHideTimer.Free;
    FTrayHideTimer := nil;
  end;
  { 严禁用 Hide：Hide → FWindow.Free → ohos_destroy_window(主窗)
    → ETS destroyWindow(1) → terminateAbility → 程序退出。
    用 SetWindowVisible(False) 仅隐藏（minimize），不销毁不重建。 }
  if Window.HasHandle then
    Window.SetWindowVisible(False)
  else
    Hide;
end;

procedure TMainForm.TrayClick(Sender: TObject);
begin
  { 恢复：句柄有效（最小化/隐藏后）→ SetWindowVisible(True)；
    句柄失效 → Show（重建）。注意 fpGUI 的 Show 在句柄有效时会
    无条件新建窗口对象（泄漏旧对象），必须先判 HasHandle。 }
  if Window.HasHandle then
    Window.SetWindowVisible(True)
  else
    Show;
  BringToFront;
end;

procedure TMainForm.TrayExit(Sender: TObject);
begin
  FTray.Hide;              { 移除托盘图标（CMD 10） }
  FForceExit := True;      { 绕过关闭到托盘，真正退出 }
  Close;
end;
```

---

## 7. 关闭到托盘的几个陷阱（重要）

### 陷阱 1：在 `FormCloseQuery` 中直接隐藏 → JS 线程死锁

- 链路：ETS `windowWillClose` 回调（JS 线程）→ `queryCanClose` → C++ `napi_tsfn_blocking` 等待 → Pascal `FormCloseQuery`
- 若此处调用 `Hide`/`SetWindowVisible`，会反向经 `napi_tsfn_blocking` 投递回**正在被阻塞的 JS 线程** → 死锁（窗口不关也不隐藏）
- **正确**：`CanClose := False` + 延迟 `TfpgTimer`（主线程）执行隐藏

### 陷阱 2：用 `Hide` 隐藏 → 应用被系统退出

- `Hide` → `HandleHide` → `FWindow.Free` → `ohos_destroy_window(主窗)` → ETS `destroyWindow` → `terminateAbility` → **进程退出**
- **正确**：`Window.SetWindowVisible(False)`（最小化语义，不销毁句柄），恢复用 `SetWindowVisible(True)`

### 陷阱 3：恢复时无条件 `Show` → 窗口对象泄漏/双窗

- fpGUI 的 `Show` 会**无条件重建 `FWindow`**（fpg_widget.pas）
- 句柄仍有效时调用会新建窗口对象（旧对象泄漏，甚至出现"两个主窗"）
- **正确**：`if Window.HasHandle then SetWindowVisible(True) else Show;`

### 陷阱 4：退出路径未区分（系统"退出" vs 应用"退出到托盘"）

- 系统托盘"退出"与 Dock 关闭无法在 `onPrepareToTerminate` 中区分（系统强制项，无配置 API）
- 本移植**不实现** `onPrepareToTerminate`，让系统退出放行
- 应用自定义"退出"菜单项：先 `FTray.Hide`，再置 `FForceExit := True`，最后 `Close`

### 陷阱 5：缺少托盘图标资源（导致 TrayManager.add() 失败 → 托盘被判定不可用）

- 完整链路：Pascal TfpgSystemTrayIcon.Show → C++ CMD8 → Index.ets: case 8 → TrayManager.add(title)
- TrayManager.ets（ harmony 实现）在 loadIcon() 里从 rawfile 读图标
- this.ctx.resourceManager.getRawFileContentSync('white.png'/'black.png')

---

## 8. 接入新工程清单

### 8.1 C++ 桥（`napi_init.cpp` / `fp_bridge.h`）

1. **命令号**：`NATIVE_CMD_TRAY_ADD=8`、`NATIVE_CMD_TRAY_SET_MENU=9`、`NATIVE_CMD_TRAY_REMOVE=10`
2. **正向函数**（Pascal 经桥指针调用）：
   ```cpp
   void ohos_tray_add(const char* title, int iconIndex);   // → CMD 8
   void ohos_tray_set_menu(const char* json);              // → CMD 9（payload 缓冲 4096 字节）
   void ohos_tray_remove(void);                            // → CMD 10
   // 全部经 SendNativeCommand → napi_call_threadsafe_function 投递 ETS
   ```
3. **导出到 Pascal**：桥回调结构中填入（二选一，取决于工程所用桥）：
   - 统一桥 `ohos_bridge_init`：`OhosBridgeCallbacks.tray_add / tray_set_menu / tray_remove`（v8+）
   - 旧桥 `fp_bridge_init`：`cpp_api->tray_add / tray_set_menu / tray_remove`
4. **反向注入**：NAPI 导出 `onTrayEvent(evType: number, menuId: string)`：
   ```cpp
   static napi_value OnTrayEvent(napi_env env, napi_callback_info info) {
       // 取 evType(int32) 与 menuId(utf8, <128B)
       if (g_inject_tray) g_inject_tray((int)evType, menuId);
       // g_inject_tray = Pascal 导出表 reserved[0]（ohos_inject_tray_event）
   }
   ```
5. **导出表挂接**：`g_inject_tray = (InjectTrayEventFunc)exps.reserved[0];`

### 8.2 ETS 侧

1. **TrayManager 双 SDK 变体 + 构建期选择**
   - `common/TrayManager.harmony.ets`（完整实现）
   - `common/TrayManager.open.ets`（空实现，add 立即回传 `'fail'` 降级）
   - `tools/prebuild.ps1`：读取 `build-profile.json5` 的 `runtimeOS`，复制对应变体为 `TrayManager.ets`（切换 SDK 后**必须**先跑一次）
2. **Index.ets**：`TrayManager.getInstance().init(getContext(this))`；`handleNativeCommand` 增加 `case 8/9/10`
3. **QuickOperation 面板**（可选）：
   - `MyStatusBarViewAbility.ets`（`StatusBarViewExtensionAbility`，`windowStage.loadContent('pages/StatusBarView')`）
   - `pages/StatusBarView.ets`（面板 UI）
   - `module.json5` → `extensionAbilities` 注册：
     ```json5
     {
       "name": "MyStatusBarViewAbility",
       "srcEntry": "./ets/fp_bridgeability/MyStatusBarViewAbility.ets",
       "type": "statusBarView",
       "exported": false
     }
     ```
   - `QuickOperation` 的 `abilityName` / `moduleName` **必须是当前模块的 Ability 名与模块名**（写错 → 面板只显示标题白卡片）
4. **图标资源**：`resources/rawfile/white.png`、`black.png`（TrayManager 会强制缩放到 24vp——**规避 `addToStatusBar` 的 1010710001 PixelMap 尺寸超限**）
5. **import 适配**：`testNapi from 'libentry.so'` 或 `fpbridge from 'libfp_bridge.so'`（与工程所用桥一致）

### 8.3 Pascal 侧

1. `uses` 添加 `fpg_trayicon`、`fpg_menu`
2. 创建 `TfpgPopupMenu`（先）→ `TfpgSystemTrayIcon`（后），设置 `Hint` / `PopupMenu` / `OnClick`
3. 调用 `FTray.Show`
4. 关闭到托盘逻辑（见第 6 节）
5. 运行期判断 `IsSystemTrayAvailable` 实现降级

### 8.4 设备要求

- **HarmonyOS 2in1 / PC**（状态栏托盘区存在）
- 手机/平板形态无状态栏托盘 → `addToStatusBar` 失败 → 自动降级（`IsSystemTrayAvailable=False`）

---

## 9. 常见问题 FAQ

**Q1：`FTray.Show` 后 `IsSystemTrayAvailable` 立刻为 True，但系统上没有图标？**
`Show` 采用**乐观置真**（add 结果异步回传）。真实结果在 `evType=3` 到达时修正：`'ok'` 保持，`'fail'` 复位为 `False`。若需精确判断，可在 `Show` 后延时（如 300ms 定时器）再查询，或监听应用层自行维护的状态。

**Q2：菜单不显示/丢失？**
两条常见路径：
- 顺序问题：`Show` 内部**先** `SyncMenu`（CMD 9）**后** `add`（CMD 8）——ETS 侧 `TrayManager` 用 `pendingMenu` 缓存先到的菜单，add 成功回调后自动补发（`updateStatusBarMenu` 在图标未 add 时调用会失败且被吞——这是历史根因，已被缓存机制修复）
- 菜单为空：`PopupMenu` 未创建、所有项 `Visible=False`、或 `_ohos_tray_set_menu` 未装载（C++ 未实现/桥版本不匹配）

**Q3：add 失败，错误码 `1010710001`？**
`addToStatusBar` 的 PixelMap 尺寸超限。TrayManager 已将图标强制缩放到 24vp；若自定义 TrayManager，请保留该缩放。

**Q4：右键菜单项点击后系统报 `1010720001`？**
菜单项缺少 `menuAction`。普通项必须带 `menuAction`（`notifyOnly: true`），详见 3.5 节。

**Q5：菜单项点击无反应？**
按链路排查：
1. ETS `rightMenuClick` 是否触发（hilog 关键字 `rightMenuClick data=`）
2. `menuCode` 是否为 `'m0'..'mN'` 格式（Pascal 按该格式反查）
3. `FMenuIndex` 与序列化顺序是否一致（`SyncMenu` 每次调用会重建，菜单变更后需重新 `SyncMenu`——当前仅 `Show` 时调用一次；运行期动态改菜单需自行触发）
4. `item.OnClick` 是否赋值

**Q6：左键点击无反应？**
`statusBarIconClick` 事件的 `iconClickType` 需为 `'leftClick'`；面板（QuickOperation）弹出与事件并行，若"打开主界面"由面板按钮承担，须在面板 `StatusBarView.ets` 中 `startAbility` 拉起主 Ability。

**Q7：OpenHarmony 设备上表现？**
`TrayManager.open.ets` 全部空实现，`add` 立即回传 `'fail'` → `gTrayActive=False` → `IsSystemTrayAvailable=False`。应用据此走普通退出逻辑；`Show`/`Hide`/`SyncMenu` 均安全空转。

**Q8：切换 runtimeOS 后托盘失效？**
切换 `build-profile.json5` 的 `runtimeOS` 后必须重跑 `tools/prebuild.ps1` 重新选择 `TrayManager.ets` 变体，否则静态 import 会因 SDK 缺失而编译失败（open）或托盘不可用（harmony）。

**Q9：托盘图标点击"退出"后应用未退出？**
检查"退出"菜单项处理是否设置了绕过关闭到托盘的标志（如 `FForceExit := True`）再 `Close`，否则 `FormCloseQuery` 会再次拦截并隐藏。

---

## 10. 调试指南

**hilog 关键路径（由内到外）**

| 关键字 | 来源 | 含义 |
|---|---|---|
| `Tray Show: title=` | Pascal handler | `Show` 发出 add 请求 |
| `Tray SyncMenu: [...]` | Pascal handler | 菜单 JSON 序列化结果 |
| `TrayEvent: type=N menu=... cb=` | Pascal loop | 事件出队（type=0/1/2/3） |
| `Tray add result: ok/fail` | Pascal handler | add 结果 |
| `OnTrayEvent: type=... menuId=... inject=` | C++ | NAPI → Pascal 注入点（`inject` 为空指针则为桥未接好） |
| `addToStatusBar OK` / `failed: ...` | ETS | 系统 API 结果与错误码 |
| `rightMenuClick data=` | ETS | 菜单项点击原始数据 |
| `Tray menu updated:` | ETS | `updateStatusBarMenu` 成功 |
| `Tray setMenu deferred (not ready)` | ETS | 菜单先于 add 到达，已缓存（正常） |

**排查清单（托盘不出现）**

1. 设备是否为 HarmonyOS 2in1/PC
2. `build-profile.json5` 的 `runtimeOS` 是否为 `HarmonyOS`，且已跑 `prebuild.ps1`
3. `module.json5` 是否注册 `statusBarView` 扩展（仅影响快捷面板）
4. hilog 看 `addToStatusBar failed:` 错误码
5. C++ 桥是否实现 `ohos_tray_*` 并填入回调表（`_ohos_tray_add` 为空时 `Show` 直接返回）
6. rawfile 图标是否存在（`white.png` / `black.png`）

**排查清单（事件不回调）**

1. C++ `OnTrayEvent` 是否收到（hilog）
2. `exps.reserved[0]` / `g_pascal.inject_tray_event` 是否非空（日志 `inject=0x...`）
3. Pascal 队列是否消费（`TrayEvent:` 日志；无则检查 `WakeChannel` 唤醒 / loop 是否运行）
4. `OnOhosTray` 是否已注册（handler 构造后自动注册；`cb=True`）

---

## 11. 限制与后续计划

| 项 | 现状 | 计划 |
|---|---|---|
| 气泡通知 `ShowMessage` | `SupportsMessages=True` 但 handler 未覆写（空操作） | 接入 HarmonyOS 通知体系（`@kit.NotificationKit`） |
| 子菜单 | JSON 协议预留（`SubMenu` 未序列化） | SDK 支持后扩展 JSON 格式 |
| 勾选态 `Checked` | 未序列化 | 同上 |
| 运行期菜单变更 | 仅 `Show` 时 `SyncMenu` 一次 | 增加 `RefreshMenu` 级 API（或菜单项变更钩子） |
| `rightClick`（evType=1） | 仅记录日志（菜单由系统渲染，无需应用处理） | 保持 |
| 多托盘实例 | 全局单回调（后注册者生效） | 应用应保持单实例；框架侧可加多实例分发 |
| 图标选择 | `ohos_tray_add(title, 0)`（索引保留） | 支持自定义图标资源名 |

---

## 附录 A：相关源码位置速查

| 文件 | 内容 |
|---|---|
| `framework/src/main/pascal/gui/fpg_trayicon.pas` | `TfpgSystemTrayIcon`（跨平台 widget API） |
| `framework/src/main/pascal/corelib/fpg_base.pas` | `TfpgSystemTrayHandlerBase`（抽象基类） |
| `framework/src/main/pascal/corelib/ohos/fpg_interface.pas` | `TfpgSystemTrayHandler = TfpgOhosSystemTrayIcon` 别名 |
| `framework/src/main/pascal/corelib/ohos/fpg_ohos.pas` | `TfpgOhosSystemTrayIcon`、`TfpgOhosTrayEvent`、`EnqueueTrayEvent`、`ProcessQueuedTrayEvents`、`ohos_inject_tray_event`、`SyncMenu`/`HandleTrayEvent` 实现 |
| `test/helloworld/helloworld.lpr` | 完整托盘示例（关闭到托盘 + 恢复 + 退出） |
| `docs/xml/gui/examples/fpg_trayicon_usage.pas` | 官方最小用法片段 |
| `<app>/entry/src/main/cpp/napi_init.cpp` | CMD 8/9/10、`ohos_tray_*`、`OnTrayEvent` |
| `<app>/entry/src/main/ets/common/TrayManager.harmony.ets` | HarmonyOS 完整实现（statusBarManager） |
| `<app>/entry/src/main/ets/common/TrayManager.open.ets` | OpenHarmony 降级实现 |
| `<app>/tools/prebuild.ps1` | runtimeOS → TrayManager 变体选择 |
| `<app>/entry/src/main/ets/pages/Index.ets` | `handleNativeCommand` case 8/9/10 |
| `<app>/entry/src/main/ets/entryability/MyStatusBarViewAbility.ets` | 快捷操作面板扩展 |
| `<app>/entry/src/main/ets/pages/StatusBarView.ets` | 面板 UI |
| `<app>/entry/src/main/module.json5` | `statusBarView` 扩展注册 |
| `<app>/entry/src/main/resources/rawfile/{white,black}.png` | 托盘图标 |

## 附录 B：与 C++/ETS 的接口契约（Bridge v10）

```text
Pascal → C++（回调表字段）
  tray_add        : void(const char* title, int iconIndex)
  tray_set_menu   : void(const char* json)
  tray_remove     : void(void)

C++ → Pascal（导出表 reserved）
  reserved[0] = ohos_inject_tray_event : int(int eventType, const char* menuId)
                 eventType: 0=click 1=rightClick 2=menuItem 3=addResult('ok'/'fail')

ETS 命令（NativeCommandData.type）
  8=TRAY_ADD(title) 9=TRAY_SET_MENU(payload=JSON) 10=TRAY_REMOVE
```

> 注意：`TOHOSBridgeCallbacks` 与 `OhosBridgeCallbacks` 布局必须严格一致（4 字节对齐、版本号同步 +1）。修改任一字段时两侧同步更新。
