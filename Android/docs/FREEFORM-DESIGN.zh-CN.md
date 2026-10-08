# fpGUI Android Freeform 多窗口设计（v2）

> 状态：**已实现并在 LDPlayer9 实机验收通过**（见 §7 验收记录；实现计划 `FREEFORM-PLAN.zh-CN.md`）。
> 前置文档：`DESIGN.zh-CN.md`（v1 后端/子窗口设计）、`FRAMEWORK-CHANGES.zh-CN.md`（框架修改记录）。

## 0. 背景与目标

- **现状（v1）**：次级窗口为应用内浮动窗口（Java `PopupWindow` + 普通 `View`），
  受限于同一 Activity，窗口不能移出应用、无法真正并存多窗口。
- **目标（v2）**：**所有 fpGUI 窗口（主窗口 + 全部次级窗口，含多级子菜单）均为
  系统级 Freeform 窗口**（独立 OS 窗口，可拖动、缩放、并存）。
- **已确认决策**：
  - **A1**：菜单打开时点击其他窗口 → **关闭整条菜单链且点击穿透**到目标窗口（桌面风格）。
  - **B2**：Freeform 窗口被用户拖动/缩放 → **位置+尺寸都同步**回 fpGUI 窗口。
  - **C**：**主窗口也 Freeform 化**（启动即为可拖动/缩放的 Freeform 窗口）。

### 0.1 可行性实测结论（LDPlayer9 / Android 9 / SDK 28，已探针验证）

| 项目 | 结论 |
|---|---|
| ROM Freeform 支持 | `android.software.freeform_window_management` 存在；`enable_freeform_support=1`、`force_resizable_activities=1`（adb 已设置） |
| 普通应用请求 Freeform | **可行**：反射调用隐藏 API `ActivityOptions.setLaunchWindowingMode(5)` 成功，`startActivity` 无 SecurityException（Android 9 不强制 `MANAGE_ACTIVITY_TASKS`） |
| 多实例 Activity | `FLAG_ACTIVITY_NEW_TASK\|FLAG_ACTIVITY_MULTIPLE_TASK` → 独立 `mode=freeform` 栈（实测 Stack #27） |
| 初始位置/尺寸 | `ActivityOptions.setLaunchBounds(Rect)`（公开 API）生效，实测 `mBounds=Rect(400,225-1200,675)` |
| 关闭按钮/标题栏 | 系统自动提供（freeform 窗口装饰） |

> `MANAGE_ACTIVITY_TASKS` 为 `signature|privileged` 权限，普通安装不会授予；已在 Manifest
> 声明（文档/priv-app 测试路径用）。Android 10+ 若平台拒绝显式 Freeform 请求，见 §5 回退。

## 1. 架构总览

```
┌──────────────────────────── 同一进程 ────────────────────────────┐
│  Pascal 应用（单实例、单消息循环、全局窗口表）                     │
│    TfpgAndroidWindow(main, subId=0)  TfpgAndroidWindow(subId=N)…  │
│         │  subId 路由（创建/呈现/事件/销毁，复用 v1 机制）          │
│  ───────┼─────────────────────────────────────────────────────   │
│  Java 桥接（fpg_android_bridge）  id→(activity,view) 全局引用表    │
│  ───────┼─────────────────────────────────────────────────────   │
│  FpActivity#0 (main)   FpActivity#1   FpActivity#2  …             │
│   SurfaceView          WindowView      WindowView                 │
│   Java Canvas          Java Canvas     Java Canvas                │
└──────────────────────────────────────────────────────────────────┘
```

- **每个 fpGUI 窗口 = 一个 `FpActivity` 实例**（同进程，共享 Pascal 循环）。
- **主窗口** = 首个实例（windowId=0）；**次级窗口**（对话框/菜单/子菜单/下拉）= 附加实例。
- **呈现**：次级窗口用**普通 `View`（`FpWindowView`）+ Java Canvas 位图呈现**，
  不使用 SurfaceView——规避 LDPlayer"销毁 SurfaceView → 宿主 GL 重连 → present 崩溃"的已知问题
  （v1 已踩坑，见 `DESIGN.zh-CN.md` §11.6）。主窗口沿用现有 `FpSurfaceView`（其 surface 生命周期内不销毁）。
- **事件/模态/菜单链**：沿用 v1 的 subId 路由与 `TopModalForm` 模态逻辑，新增：
  菜单穿透关闭（A1）、窗口 bounds 同步（B2）、按窗口 id 的 IME/按键路由。

## 2. 组件与接口

### 2.1 Java 侧

#### FpActivity（多实例化）
- Intent extras：`windowId`（int，0=主窗口，>0=次级窗口）、`relaunched`（主窗口 freeform 重启标记）。
- **主窗口 Freeform 化（C）**：
  - 从 Launcher 启动的实例（无 `windowId` extra）且设备支持 Freeform 时：
    以 `NEW_TASK|MULTIPLE_TASK` + Freeform 请求 + 初始 bounds（工作区全尺寸）**重启自身**
    （extra `relaunched=1`），随后 `finish()` 旧实例。存在约一帧的全屏闪屏，可接受。
  - `relaunched=1` 实例：按 `windowId=0` 主窗口初始化（现有 SurfaceView + nativeInit 流程），
    跳过 Insets padding（`isInMultiWindowMode()` 为真时不加系统栏 padding）。
  - **重复 Launcher 启动**：应用已在运行时（静态标志 `sAppStarted`，首个实例初始化成功后置位）
    再次从 Launcher 启动 → 新实例**立即 `finish()`**，避免产生孤儿主窗口。
  - Freeform 不可用时：保持现状全屏启动。
- **次级窗口实例**（`windowId>0`）：
  - `setContentView(new FpWindowView(...))`（普通 View，无 SurfaceView）。
  - **不调用** `nativeInit/nativeSurfaceChanged`（Pascal 应用已由主实例启动）。
  - 触摸/悬停/滚轮 → `nativeWindowTouch(id, action, x, y, button)` 等（新增 natives，见 2.2）。
  - IME 文本/按键/删除 → `nativeWindowText/Key/Delete(id, ...)`。
  - 关闭（系统 X / 返回键）→ `onDestroy` → `nativeWindowClosed(id)`。
  - 尺寸变化（缩放）→ `onConfigurationChanged`/`onSizeChanged` → `nativeWindowBoundsChanged(id, x, y, w, h)`。
  - 位置变化（拖动）→ UI 线程 250ms 轮询 `getLocationOnScreen`（freeform 拖动无系统回调），
    变化（>2px 阈值）时上报 `nativeWindowBoundsChanged`。
  - 焦点变化 → `onWindowFocusChanged` → `nativeWindowFocused(id)`（IME/键盘目标）。
- **创建次级窗口**：`createSubWindow(id, x, y, w, h, flags)`：
  - 首选 Freeform：`ActivityOptions`（反射 `setLaunchWindowingMode(5)` + `setLaunchBounds(x,y,x+w,y+h)`）
    + `NEW_TASK|MULTIPLE_TASK` → `startActivity`。
  - **失败回退**（异常/设备不支持）：创建 v1 `FpSubWindow`（PopupWindow+View），对 Pascal 透明。
  - 窗口实例注册表 `SparseArray<FpActivity>`（弱引用）供 move/finish/present 路由。
- **销毁**：`destroySubWindow(id)` → 对应实例 `finish()`（已在结束时 no-op 安全）。
- **呈现**：`presentSubFrame(id, buffer, w, h)` → 按 id 路由到实例的 `FpWindowView`（bitmap+invalidate）。

#### 新增 `FpWindowView`（普通 View）
- 职责：绘制收到的位图帧（`onDraw` + 锁防撕裂）、采集触摸/悬停/滚轮/IME 事件并带上 `windowId`
  调用对应 natives、`onSizeChanged` 上报尺寸、`setKeyboardVisible`（该实例的 IME）。
- 复用 v1 `FpSubWindow.FrameView` 的实现（抽取共享）。

#### 其他
- `FpSubWindow.java`：保留为回退路径（不再用于 Freeform 设备）。
- `ProbeActivity.java`：**实现时删除**（含 Manifest 条目与 build.bat 编译项）。

### 2.2 桥接层（`fpg_android_bridge.pas`）

- **id → (activity, view) 全局引用表**：`TAndroidWindowRef = record Id; Activity, View: jobject; end;`
  新实例创建时（`createSubWindow` 的 Java 侧回调 `nativeWindowAttached(id, activity, view)`）
  `NewGlobalRef` 登记；`nativeWindowClosed` 时删除引用。主窗口沿用现有单引用（id=0）。
- **新增 natives**（注册在 `FpWindowView` 类）：
  - `nativeWindowAttached(int id, Activity activity, View view)`
  - `nativeWindowTouch(int id, int action, float x, float y, int button)`
  - `nativeWindowHover(int id, float x, float y)`
  - `nativeWindowWheel(int id, int delta)`
  - `nativeWindowText(int id, String text)`
  - `nativeWindowKey(int id, int keyCode, boolean down, int metaState, int unicode)`
  - `nativeWindowDelete(int id, int before, int after)`
  - `nativeWindowBack(int id)` → boolean
  - `nativeWindowBoundsChanged(int id, int x, int y, int w, int h)`
  - `nativeWindowClosed(int id)`
  - `nativeWindowFocused(int id)`
- **IME**：`AndroidShowKeyboardProc` 扩展为按窗口：`SetKeyboardVisible(windowId, visible, kbType)`
  → 查表取 view → `view.setKeyboardVisible(...)`（`FpWindowView` 与 `FpSurfaceView` 均提供该方法）。
- **创建/销毁/移动/显隐**：现有 4 个 proc 保留签名；`CreateSubWindowViaJava` 内部改为
  Freeform 优先（含 bounds 参数已有 x/y/w/h）；`MoveSubWindowViaJava` 对 Freeform 窗口为
  **尽力而为**（仅记录；系统不允许程序化移动 Activity 窗口，见 §4）。
- **能力探测**：`nativeInit` 增加 `supportsFreeform` 参数（Java `PackageManager.hasSystemFeature`
  查询），Pascal 保存 `gSupportsFreeform` 供日志/诊断。

### 2.3 Pascal 侧（`fpg_android.pas` 等）

- **事件队列**：新增事件种类（bounds changed / closed / focused），复用现有队列与 WakeChannel。
- **bounds 同步（B2）**：
  - `nativeWindowBoundsChanged(id,x,y,w,h)` → 循环线程：`w := FindWindowBySubId(id)`；
    `w.FSyncingFromJava := True`（新增标志）下更新 `FPosition`/`FSize`（÷density 转逻辑），
    并向窗口主控件投递 `FPGM_RESIZE`（触发布局/重绘）；窗口画布缓冲按新尺寸重分配。
  - `FSyncingFromJava=True` 时 `DoMoveWindow/DoUpdateWindowPosition/DoSetWindowVisible`
    **跳过**调用 Java（防回环）。
  - 主窗口：尺寸仍由 surface 回调提供（现有路径）；位置同步跳过（主窗口无父级定位意义）。
- **关闭（X/返回）**：
  - `nativeWindowClosed(id)` → 按窗口类型分派：菜单/弹窗（`wtPopup`）→ `TfpgPopupWindow.Close`；
    窗体/对话框（`wtWindow/wtDialog/wtModalForm`）→ `TfpgBaseForm.Close`（走 OnClose/CloseQuery）；
    关闭过程触发 `HandleHide` → 现有 `AndroidDestroySubWindowProc` → Java `finish()`（重复 finish 安全）。
- **菜单穿透关闭（A1）**：
  - `ProcessQueuedEvents` 派发前：若目标窗口不是弹窗（`wnd.WindowType <> wtPopup`）且存在打开的
    弹窗链 → 先 `ClosePopups`（fpg_popupwindow.pas），**然后照常派发本次触摸**（穿透）。
  - 键事件同理：非弹窗窗口获得按键前关闭弹窗链。
- **键/IME 路由**：
  - 键事件队列条目增加 `WindowId`；`ProcessQueuedKeyEvents` 优先路由到该 id 对应窗口
    （回退顺序保持：TopModalForm → 事件来源窗口 → gFocusedWinHandle → 主窗口）。
  - `UpdateKeyboardVisibility` 使用**焦点窗口**的 id 调用 IME 钩子；焦点更新来自
    `nativeWindowFocused` 与触摸 DOWN。
- **主窗口 Freeform（C）**：Pascal 侧无额外改动（尺寸/位置由 surface/bounds 回调驱动）；
  `isInMultiWindowMode` 时的 Insets 处理在 Java 侧完成。

### 2.4 Manifest / 构建

- Manifest（已改，保留）：`resizeableActivity="true"`（application+activity）、
  `launchMode="standard"`、`MANAGE_ACTIVITY_TASKS` 声明。**不用**
  `documentLaunchMode="always"`：它使每次 launcher 启动都新建任务（文档任务），
  后台会残留多个活动/任务且点图标回不到原实例；主窗口保持单任务复用，点图标
  恢复原实例。次级 Freeform 窗口的多任务由启动意图的显式
  `FLAG_ACTIVITY_NEW_TASK|FLAG_ACTIVITY_MULTIPLE_TASK` 保证，不依赖该属性。
- `build.bat`：`-dUseCThreads`（已加，修复 Runtime error 232）；ProbeActivity 编译项**实现时移除**。

## 3. 关键数据流

**创建（Pascal→Java）**：`AllocateWindowHandle`（次级）→ `AndroidCreateSubWindowProc(id,x,y,w,h)`
→ 桥接 → Java `createSubWindow` →（Freeform）`startActivity`（freeform+bounds）
→ 新实例 `onCreate` → `nativeWindowAttached(id, activity, view)` → Pascal 登记引用。

**呈现**：Pascal 画布 `PutBufferToScreen`（子窗口分支）→ `PresentSubWindowSurface`
→ `AndroidPresentSubFrameProc(id, buffer, w, h)` → 桥接 `presentSubFrame`
→ Java 实例 `FpWindowView` 位图 + invalidate。

**触摸**：`FpWindowView.onTouchEvent` → `nativeWindowTouch(id,…)` → Pascal 事件队列
→（A1：必要时先关弹窗链）→ subId 路由 → fpGUI 控件。

**拖动/缩放（B2）**：Java（轮询/onSizeChanged）→ `nativeWindowBoundsChanged(id,…)`
→ Pascal 更新窗口几何（带 syncing 标志）→ fpGUI 布局/重绘。

**关闭**：系统 X → `onDestroy` → `nativeWindowClosed(id)` → Pascal `Close`
→ `HandleHide` → `AndroidDestroySubWindowProc(id)` → Java `finish()`（安全重入）。

## 4. 边界与已知限制

- **程序化移动**：Android 不提供移动已打开 Activity 窗口的公开 API；Freeform 窗口的
  初始位置必须通过 `setLaunchBounds` 在**启动时**给定。fpGUI 的 `ShowAt` 在创建窗口前已确定
  Left/Top ✓（菜单/子菜单/对话框定位均满足）。运行中 fpGUI 若移动窗口（罕见），Freeform 下
  仅更新内部状态、不下发 Java（记录日志）。
- **子菜单定位**：依赖父菜单窗口位置；B2 位置同步保证用户拖动父菜单后子菜单仍定位正确。
- **回退**：设备无 Freeform 特性 / 请求被拒（Android 10+ 权限强制时）→ 该窗口回退 v1
  PopupWindow 路径（逐窗口判定，Pascal 无感）。回退路径的次级窗口不可聚焦，其 IME 输入
  仍经主窗口（v1 既有机制：主视图 IME → `nativeText` → 按模态/焦点路由），功能可用。
- **系统回收**：附加 Activity 被系统销毁 → `nativeWindowClosed` → Pascal 关闭对应窗口（与用户点 X 一致）。
- **主窗口启动闪屏**：Launcher 实例→Freeform 重启约一帧（可接受；后续可改独立透明 LauncherActivity 优化）。

## 5. 测试与验收

**环境**：LDPlayer9（Android 9，freeform 已启用）。release 构建（x86_64）。

| # | 用例 | 通过标准 |
|---|---|---|
| 1 | 主窗口 Freeform 启动 | 独立 freeform 窗口（带标题栏），可拖动/缩放，无闪退 |
| 2 | 同时打开 2+ 对话框 | 各自独立窗口并存、各自渲染/交互 |
| 3 | 菜单 + 多级子菜单 | 每级独立窗口；子菜单定位在父菜单项旁；拖动父菜单后打开子菜单定位正确 |
| 4 | A1 穿透关闭 | 菜单开着时点击主窗口控件：菜单链关闭且该次点击生效 |
| 5 | B2 同步 | 拖动/缩放 Freeform 窗口 → fpGUI 窗口内容随新尺寸重排、位置更新（子菜单定位验证） |
| 6 | 模态阻塞 | 模态对话框打开时点击主窗口无响应（Pascal 模态逻辑） |
| 7 | IME | 对话框内编辑框获得焦点 → 键盘弹出并输入到该窗口；主窗口编辑框互不串扰 |
| 8 | 关闭 | 系统 X / 返回键 → 对应 fpGUI 窗口关闭；菜单项执行 → 整链关闭 |
| 9 | 回退 | 关闭 `enable_freeform_support` 后重装运行 → 次级窗口回退 PopupWindow，功能正常 |
| 10 | 回归 | 主窗口渲染/中文/定时器/右键菜单/字符映射表/退格/光标闪烁（v1 清单） |

## 6. 明确不做（v2 范围外）

- Android 10+ 平台拒绝显式 Freeform 时的系统级绕过（依赖设备多窗口能力/回退路径）。
- 跨显示器迁移、画中画、系统级窗口动画定制。
- 附加窗口独立进程。

## 7. 实施与验收记录（2026-10-01，LDPlayer9 / Android 9）

### 7.1 验收结果

| # | 用例 | 结果 | 证据 |
|---|---|---|---|
| 1 | 主窗口 Freeform 启动 | ✅ | `Stack #34 mode=freeform`；系统标题栏（最小化/关闭）；`freeform window management available` |
| 2 | 多对话框并存 | ✅ | 2 个独立 freeform 窗口（Dialog A/B）各自渲染 |
| 3 | 菜单 + 多级子菜单 | ✅ | 每级独立 freeform 窗口；子菜单在父菜单右侧；**拖动父菜单后子菜单跟随新位置**（B2 位置同步实证：menu pos Δ=(210,84) 逻辑 → 子菜单 pos 同步 Δ 相同） |
| 4 | A1 穿透关闭 | ✅ | 菜单链打开时点击主窗口按钮：链关闭且按钮响应（新窗口 id 递增证明事件穿透） |
| 5 | B2 拖动同步 | ✅ | 拖动 → `nativeWindowBoundsChanged` → Pascal `ApplyWindowBounds`；无崩溃 |
| 6 | B2 缩放同步 | ⚠️ 未能实测 | LDPlayer freeform 装饰无角缩放（拖动角被当作移动）；代码路径与位置同步相同（`onSizeChanged`→同一事件） |
| 7 | 模态阻塞 | ✅ | 模态文件对话框打开时，点击主窗口 MenuTest 无响应（无新窗口创建）；文件对话框内组合框下拉亦为独立 freeform 窗口 |
| 8 | IME 按窗口 | ✅ | 对话框内编辑框聚焦 → `KBD: type 1 focus=TfpgEdit win=1`；主窗口 `win=0`（`adb input text` 不携带 unicode 字符为 Android 工具链已知限制，非回归） |
| 9 | 系统 X / 返回关闭 | ✅ | 对话框 X → 对应 fpGUI 窗口关闭 |
| 10 | 回退路径 | ✅ | 强制 `supportsFreeform=false` 构建：PopupWindow 弹窗正常渲染（含菜单/对话框） |
| 11 | v1 回归 | ✅ | 主窗口渲染/中文/编辑框/按钮/目录树正常 |

### 7.2 实施中发现并修复的问题

1. **首帧丢失（两条路径共有）**：Pascal 首次绘制可能早于 Java 窗口创建完成，
   `presentSubFrame` 找不到目标被丢弃 → 窗口空白。修复：新增
   `AndroidEnqueueWindowRepaint(id)`（事件 Kind=6）——Freeform 在
   `nativeWindowAttached`、回退在 `nativeSubWindowAttached`（View.onAttachedToWindow）
   时通知 Pascal 重绘窗口。
2. **子窗口坐标未叠加主窗口屏幕偏移**：fpGUI 窗口坐标以主窗口内容原点为基准；
   `createSubWindow` 现在叠加 `view.getLocationOnScreen()` 再 `setLaunchBounds`。
3. **菜单 z 序（已知限制）**：同一批 `startActivity` 创建的多个窗口，后创建的
   菜单可能位于对话框之下（LDPlayer 的 freeform 堆叠行为）；单独打开菜单（实际
   使用场景）正常置顶。规避：菜单由点击触发（获得焦点）时天然置顶。
4. **Freeform 最小窗口尺寸**：该 ROM 对 freeform 窗口有约 220dp×220dp 下限，
   小菜单窗口内容外有背景留白（外观问题，功能不受影响）。
5. **窗口装饰高度估算**：`setLaunchBounds` 为含装饰的窗口边界，按 `DECOR_DP=48`
   估算补偿；B2 首次 bounds 回调后内容尺寸自动校正。
6. **弹窗位置偏移（2026-10-01 修复，根因 1）**：平台 freeform task 有最小尺寸
   （AOSP `default_minimal_size_resizable_task` = 220dp）。请求的浮窗小于该尺寸时，
   WindowManager 会把内容窗口在 task 内**居中**，弹窗整体偏移
   `((minW-w)/2, (minH-h)/2)`（LDPlayer 240dpi 实测 184×72 菜单偏移 +2,+43px），
   且 task 二次回绕后窗口再次偏移。修复：`finishBorderlessWindow` 设置
   `lp.gravity = Gravity.TOP | Gravity.LEFT`，窗口钉在 task 左上角，内容与
   `setLaunchBounds` 位置完全一致（实测菜单 frame 精确等于 主窗内容原点 + 逻辑坐标×density）。
7. **弹窗/子菜单位置随距离增大（2026-10-01 修复，根因 2）**：B2 bounds 回调上报的是
   **绝对屏幕坐标**并直接写入 `FPosition`，而 `createSubWindow` 又按“主窗口内容原点
   相对坐标”叠加 `view.getLocationOnScreen()` → 每次 bounds 同步后 FPosition 变成绝对
   坐标，之后创建的窗口（子菜单/多级菜单/重开菜单）重复叠加主窗口原点，偏差随主窗口
   离 (0,0) 的距离与菜单层级累积。修复：`FpWindowView.reportBounds` 上报相对
   `FpActivity.getMainViewLocation()`（主窗口内容原点）的坐标，FPosition 全程保持
   虚拟屏幕坐标；实测父菜单 (200,260) → 子菜单 (318,283)，无累积偏移。
8. **弹窗入场闪跳（2026-10-01 修复，根因 3）**：freeform task 创建时的入场定位
   （含根因 1 的居中调整）在屏幕上可见，表现为弹窗从 (0,0) 闪跳几次。修复：
   borderless 次级窗口创建时 `lp.alpha = 0`，`FpWindowView.presentFrame` 首帧到达后
   调 `FpActivity.revealWindow()` 置 alpha=1（另有 800ms 兜底，避免永不显示）；
   入场过程不可见，弹窗直接出现在最终位置。

### 7.3 关键接口（实现后）

- 事件 Kind 扩展：0 触摸 / 1 滚轮 / 2 悬停 / 3 bounds / 4 closed / 5 focused / 6 repaint。
- 键事件 `TfpgAndroidKeyEvent.WindowId`；桥接 `id→(activity,view)` 全局引用表；
  `AndroidWinViewMethod`（FpWindowView 类方法缓存，jmethodID 类绑定）。
- 防回环：`TfpgAndroidWindow.FSyncingFromJava` 守卫 `DoMoveWindow/DoUpdateWindowPosition/DoSetWindowVisible`。

## 8. 模态强阻塞 / 菜单悬停切换 / 主窗强制最大化（v3，2026-10-01）

> 背景：v2 落地后实机暴露三个交互缺口：
> (a) ShowModal 期间其它窗口的事件虽被 Pascal 丢弃，但窗口仍可被点击激活、
> 系统标题栏按钮仍可用；
> (b) 主菜单打开后鼠标移到菜单栏其它顶级项不能切换（点击也只关不切）；
> (c) 主窗被系统强制最大化时窗体不随窗口尺寸调整。
>
> `TfpgAndroidWindow.DoAllocateWindowHandle` **第 796 行**：
>
> ```pascal
> FIsMain := (Owner = fpgApplication.MainForm) or (fpgApplication.MainForm = nil);  改为：
> FIsMain := False; --> 即可不让主窗口最大化。

### 8.1 模态强阻塞

**根因**：模态拦截只在 Pascal 事件层（`ProcessQueuedEvents` 丢弃非模态窗口事件），
OS 层窗口仍可获焦/上浮，系统装饰（标题栏关闭/最小化）完全不受应用事件层控制。

**设计**：
- Pascal 后端主循环每轮比对 `fpgApplication.TopModalForm.Window` 的 subId，变化时经
  钩子 `AndroidSetModalWindowProc(id)` 通知 Java（id=0 = 无模态）。
- Java `FpActivity.setModalWindow(id)`：
  - 激活：对所有**非模态**窗口（主窗 + 次级窗）`addFlags(FLAG_NOT_TOUCHABLE)`
    —— 窗口内容与系统标题栏按钮全部失效；再 `ActivityManager.moveTaskToFront(模态 task)`
    把模态带到最前。
  - 关闭：`clearFlags(FLAG_NOT_TOUCHABLE)` 恢复全部窗口。
  - 模态期间新建窗口：`dismissOnOutside=false`（非 wtPopup）的同样加锁；wtPopup
    （模态自己的下拉框）豁免，保持可用。
- Pascal 侧现有事件丢弃保留为双保险（跨 ROM 兜底）。

### 8.2 菜单悬停/点击切换（装饰带事件转发）

**根因**：freeform 浮窗的可触摸区域比内容 frame 大约 45px（系统装饰带；`dumpsys input`
实测 frame=[3,134][329,378] / touchableRegion=[0,89][374,423]，与 `surfaceInsets`
无关，置 0 无效）。菜单弹窗该装饰带正好盖住菜单栏 → 菜单栏收不到 hover/点击：
悬停不切换、点击只触发弹窗自身的 `ClosePopups`。

**设计**：弹窗 `FpWindowView` 收到的事件若局部坐标在自身内容矩形之外，即判定为落在
装饰带内，换算为「主窗内容原点为基准的物理坐标」（`popupScreen + event - mainViewScreen`）
后转发到主窗 native 入口：
- hover → `nativeHover(vx,vy)`；
- touch DOWN → `nativeTouch(...)` 并记录该指针序列，其 MOVE/UP 继续转发（保持拖拽语义）。

转发事件在 Pascal 侧走正常队列：`HitTestWindow` 重新命中真实目标（菜单栏/父菜单/
主窗），因此悬停即切换（`TfpgMenuBar.HandleMouseMove`）、点击其它顶级菜单走 A1
（关整条链 + 穿透打开新菜单）。无需修改 Pascal。

### 8.3 主窗强制最大化适配

**根因**：主窗启动 bounds 在屏幕高度上再加 72px 装饰估算（1600×972 > 900），系统
"最大化"以 task 原始 bounds 为上限 → 窗口比屏幕高 72px，内容下沿被裁；且窗体内
控件（未加锚点）不随尺寸变化。

**设计**：
- 主窗启动/重开 bounds 不再叠加装饰估算：请求 1600×900，最大化即工作区，不超屏。
- 主 Activity 增加窗口客户区尺寸监听（root 视图 `addOnLayoutChangeListener`）：
  窗口 bounds 变化而 `surfaceChanged` 未回调时也上报 `nativeSurfaceChanged`
  （Pascal 按物理尺寸去重，不会重复处理）。
- 测试程序 `helloworld.lpr` 的 Quit/WindowTest/MenuTest 按钮加
  `Anchors := [anRight, anBottom]`，窗口尺寸变化后随右下角移动。

### 8.4 实现记录与实测补充（2026-10-01 实施）

1. **模态强阻塞**：`FpActivity.setModalWindow(int)` + 主循环 `SyncModalState`
   （fpg_android.pas）比对 `TopModalForm` 的 subId 变化后通知 Java；非模态窗口
   `FLAG_NOT_TOUCHABLE`（系统标题栏按钮一并失效）+ `moveTaskToFront(模态 task)`；
   `REORDER_TASKS` 权限已加入 Manifest；模态期间新建的 wtPopup 豁免。
2. **菜单点击切换（A1 穿透）根因再定位**：freeform 弹窗 frame 上方约 45px 的装饰带
   是**系统窗口拖动区**——其中的触摸/点击不投递给应用（实测拖动该带会移动弹窗），
   因此"点击其它顶级菜单"永远被吞。修复：wtPopup 弹窗**顶部加 48dp 透明 padding**
   （窗口上移、位图下移绘制，`POPUP_PAD_DP`），拖动带整体移到菜单栏上方；padding
   内的事件由 `FpWindowView` 转发到主窗 native 入口，Pascal 重命中后走 A1 关闭链 +
   穿透点击 → 点击其它主菜单直接切换子菜单。
3. **悬停切换根因**：Android 的 `ACTION_HOVER_MOVE` 走 `onHoverEvent` 而非
   `onGenericMotionEvent`——原实现是死代码，菜单栏从未收到悬停。修复：
   `FpSurfaceView/FpWindowView` 实现 `onHoverEvent`；弹窗 padding/装饰带内的悬停同样
   转发主窗 → `TfpgMenuBar.HandleMouseMove` 切换。
4. **鼠标点击去重**：一次鼠标点击产生 ACTION_DOWN + ACTION_BUTTON_PRESS（松开时
   ACTION_BUTTON_RELEASE + ACTION_UP）两个 DOWN/UP 对，且 ACTION_DOWN 的
   buttonState 可能不带按键位（右键被当成左键，输入框右键菜单不弹出）。修复：
   按钮一律取 `ACTION_BUTTON_PRESS/RELEASE` 的 actionButton，丢弃重复的
   ACTION_DOWN/UP（FpSurfaceView/FpWindowView/FpSubWindow 三处一致）。
5. **弹窗首帧空白**：`presentFrame` 可能在 View attach/布局前到达（view=0x0），
   postInvalidate 丢失 → 弹窗空白。修复：`onAttachedToWindow/onSizeChanged` 时若已有
   位图则重绘。
6. **弹窗不做尺寸反向同步**：`ApplyWindowBounds` 对 `wtPopup` 只同步 FPosition，
   忽略 FSize（弹窗尺寸由内容决定，反向同步会因 padding/最小 task 引入留白）。
7. **主窗强制最大化**：主窗启动 bounds 不再加装饰（1600×900）；主 Activity 增加
   `watchMainViewSize`（布局变化 → `nativeSurfaceChanged` 兜底）；测试程序按钮
   `Anchors := [anRight, anBottom]` 验证右下跟随。

### 8.5 接口与验证

- 新增 Pascal→Java：`FpActivity.setModalWindow(int id)`；
  `FpSurfaceView.nativeTouch/nativeHover` 改为包内可见，供弹窗转发调用。
- 验证（LDPlayer9，注入真实鼠标事件）：
  - 模态（ShowMessage）：点主窗菜单栏/控件无反应，系统标题栏按钮无效，模态保持最前；
  - 菜单：File 打开后悬停 Insert/Extra 直接切换；点击其它顶级项关链并直接打开新菜单；
  - 尺寸：`am task resize` / 系统最大化后窗体随窗口重排，右下锚定按钮跟随。

## 9. v4：主窗全屏 + wtPopup 应用内浮动窗口（2026-10-02）

> 背景：v2/v3 的 freeform 全窗口模型在实机上体验差——主窗带系统标题栏/最大化
> 异常/超屏，弹窗受 freeform 拖动带、最小 task、入场动画影响。按需求调整：
> **主窗改普通全屏 Activity；wtPopup（菜单/下拉）改应用内浮动窗口；对话框/窗体保持
> freeform 系统窗口**。

### 9.1 架构

- **主窗（windowId=0）**：普通全屏 Activity，无 freeform task、无系统标题栏、无启动
  重启/重挂载（v3 的 `requestMainBorderless`/reattach 路径删除，Pascal 主窗分支不再
  调用 `AndroidMainBorderlessProc`）。内容区 = 屏幕减系统栏（insets padding）。
- **尺寸反向通知（要求项）**：主窗尺寸由 `surfaceChanged` 与
  `watchMainViewSize`（root 布局监听）双路上报 `nativeSurfaceChanged` →
  `AndroidSetScreenMetrics` → `FPGM_RESIZE`；Pascal 按物理尺寸去重。实测
  `wm size 1280x720` → `Resize: phys=1280x684 logical=853x456`，恢复 1600x900 →
  `Resize: phys=1600x864 logical=1067x576`，主窗体与右下锚定按钮均跟随。
- **wtPopup（菜单/下拉/提示）**：`FpSubWindow`（`PopupWindow` + 普通 `View`）——
  应用内浮动窗口，**创建在宿主窗口所属 Activity**：Pascal 在
  `DoAllocateWindowHandle` 取 `TfpgPopupWindow.PopupWidget.Window.SubWindowId` 作为
  `AOwnerId` 传给 Java；主窗弹窗锚定主视图，对话框弹窗锚定该对话框的 `FpWindowView`，
  保证 z 序在宿主之上。子窗注册表 `sSubWindows` 为进程级（JNI present/move/show/
  destroy 统一按 id 查找）。
- **坐标**：Pascal 弹窗坐标仍是主窗内容原点基准的物理像素；`FpSubWindow.toAnchorWindow`
  换算到 anchor 所在窗口：`mainLoc + (x,y) - (anchorScreen - anchorInWindow)`。
- **外部点击穿透 + A1**：`PopupWindow.setOutsideTouchable(false)`——外部点击不被消费，
  主窗/对话框收到 DOWN 后由 Pascal A1 关闭菜单链并派发该点击（点击其它主菜单直接
  切换、点击菜单栏/控件穿透生效）。
- **对话框/窗体**：freeform 系统窗口不变（可拖动/缩放、B2 同步、系统标题栏）；模态
  强阻塞（`FLAG_NOT_TOUCHABLE` + `moveTaskToFront`）不变；无 freeform 设备仍回退
  `FpSubWindow`。
- **已知限制**：应用内弹窗属于某个 Activity 的窗口，主窗菜单无法显示在 freeform
  对话框之上（不同 task）；模态期间主窗事件被 Pascal 丢弃，该场景不出现。

### 9.2 被 v4 取代/移除的 v3 弹窗补丁

- 弹窗 freeform 启动 + 顶部 48dp 透明 padding（`POPUP_PAD_DP`/`EXTRA_PAD_TOP`）删除；
- `FpWindowView` 的 `padTop`/装饰带事件转发删除（仅对话框使用，填满窗口）；
- 主窗 freeform 重启、reattach、`AndroidMainBorderlessProc` 调用删除。

**保留**：`onHoverEvent` 悬停路由（菜单栏/菜单项悬停）、鼠标按键取
`ACTION_BUTTON_PRESS/RELEASE`（右键菜单）、弹窗不做尺寸反向同步、首帧重绘
（onAttached/onSizeChanged）、主窗尺寸兜底监听。

### 9.3 实测（LDPlayer9，2026-10-02）

- 主窗：`AndroidSetMainSurface 1600x864`、逻辑屏 1067x576、无系统标题栏、内容铺满；
- 菜单：MenuTest 打开应用内弹窗，位置正确（虚拟 (200,260) → 屏幕 (300,426)）、无留白；
  菜单打开时点击 WindowTest → A1 关链且按钮触发（对话框 subId=2/3 + 新菜单 subId=4）；
- 尺寸：`wm size` 双向变化均收到 `Resize:` 日志，窗体与锚定按钮跟随；
- 对话框：Dialog A/B 仍为 freeform 系统窗口，正常显示。

### 9.4 freeform 对话框入场/留白/主窗标题栏（2026-10-02 追加）

1. **对话框入场跳动**：freeform task 创建时先出现在屏顶再移到 launch bounds，动画
   可见。修复：所有 freeform 次级窗口（不只 borderless）在 onCreate 设 `alpha=0`，
   `FpWindowView` 首帧到达后 `revealWindow()` 置 1（800ms 兜底），入场过程不可见。
2. **对话框比 fpGUI 窗口大/底部白条**：`DECOR_DP=48` 估算（72px）大于实际标题栏
   （LDPlayer 实测 64px），task 内容比请求高 8px；B2 尺寸反向同步又把 fpGUI 窗口
   放大到内容尺寸，底部出现白条。修复：
   - `createSubWindow` 非 borderless 对话框按「内容 + 装饰」启动，并把 launch y 上移
     装饰高度，使**内容**落在 fpGUI 请求位置；
   - `initSecondaryWindow` 布局后实测 `decor = decorView.Height - windowView.Height`，
     把窗口 `lp.height` 校正为 `ch + decor`（`gravity=TOP|LEFT`），并记录
     `sDecorHeight` 供后续对话框直接使用（首个窗口用估算值，随后校正一次）。
     实测 Dialog A/B frame 高度 274 = 内容 210 + 标题栏 64，白条消失。
3. **主窗标题栏规则**：Manifest 主题改 `Theme.DeviceDefault.NoActionBar`（启动
   starting window 不再闪现标题栏）；Pascal 主窗分配时经
   `AndroidSetMainDecorationProc(borderless, fullscreen, title)` 通知 Java：
   - `waBorderless`：无标题栏（默认即无，无闪烁）；
   - `waFullScreen`：无标题栏 + `FLAG_FULLSCREEN`/systemUiVisibility 隐藏状态栏；
   - 其它：保留系统标题栏——一次性重启 Activity 并用普通主题（带 ActionBar），
     Pascal 应用不中断（`skipNativeStop` 防误停 + surface 按 token 重挂载），
     ActionBar 标题取 fpGUI 窗口标题（`SetWindowParameters` → FTitle）。
     实测 pkeditor（默认属性）标题栏显示 "fpGUI Documentation Editor"，内容区
     1600x768 并收到 Resize 反向通知；helloworld（waBorderLess）无标题栏。

### 9.5 主窗初始尺寸通知 / Quit 退出（2026-10-02 追加）

1. **主窗初始尺寸未通知到 fpGUI**：Java 在 Pascal 应用对象存在之前就上报了
   surface 尺寸（`AndroidSetScreenMetrics` 中 `app = nil` → 事件被丢弃），启动后
   主窗体一直保持设计尺寸（`SetPosition(10,50,900,550)`），锚定控件（如 Quit）
   不动。修复：
   - `AndroidSetScreenMetrics` 记录全局物理尺寸 `gAndroidPhysW/H`；
   - `TfpgAndroidApplication.Create` 若屏幕已有效则入队一次初始 resize；
   - `ProcessQueuedResizeEvents` 的去重条件增加"主控件尺寸与窗口一致"检查，
     否则主控件仍是设计尺寸时也照常下发 `FPGM_RESIZE`。
     实测启动即 `Resize: phys=1600x864 logical=1067x576`，Quit 等右下锚定按钮跟随。
2. **点 Quit 程序不退出**：`TfpgBaseForm.Close` 对主窗体执行
   `fpgApplication.Terminate`，Pascal 循环退出，但从未调用 `AndroidFinishProc`，
   Java Activity 留在前台。修复：`DoWaitWindowMessage` 在两波事件处理后检测
   `Terminated` 并调用 `AndroidFinishProc`（`finishActivity`），确保 Activity 结束。
   实测点 Quit 后 `Pascal app thread finished` → surface detach → `nativeStop`，
   焦点回到 Launcher。
3. **退出后无法再次启动（同进程重启）**：Quit 后进程被系统缓存，静态
   `sAppStarted=true` 使下次启动被当作"重复 Launcher 启动"直接 finish；且
   `fpgApplication` 单例的 `MainForm` 仍指向已释放的旧窗体，重启后新窗体被
   当成次级窗口（`AllocateWindowHandle sub`）。修复：
   - Java `onDestroy`（非装饰重启）重置 `sAppStarted/sMainView/sMainActivity/
     sMainTitleApplied/sMainTitleText/sModalWindowId/sSubWindows`；
   - 后端重启 worker 前 `fpgApplication.MainForm := nil` 并清 `gFocusedWinHandle`。
   实测：启动 → Quit 退出 → 再启动，`AllocateWindowHandle MAIN` 正常、窗体尺寸
   正确（1067x576）、锚定按钮就位。

### 9.6 子窗口显示前的"跳动"消除（2026-10-02 追加）

**根因（与标题栏无关）**：
1. 系统 freeform 任务入场动画：窗口动画样式 `Animation.Material.Activity` 的
   `taskOpenEnterAnimation = @anim/task_open_enter`（alpha 1→1、translate 1.05%→0、
   scale 1.0526→1，约 217–383ms），窗口在缩放/平移中可见；
2. 系统 starting window（Splash 预览窗）不受 Activity 窗口 `alpha=0` 影响；弹窗小于
   freeform 最小尺寸（220dp）时 task 被钳制放大，预览窗随之移动；
3. 自身两次尺寸修正：启动 bounds 用估算装饰（72px）→ 布局后 ~200ms 校正为实测
   （64px）；B2 同步可能再调一次。且原实现在首帧（~100–200ms）就 `revealWindow()`，
   入场动画尚未结束。

**修复（A+B）**：
- A：`initSecondaryWindow` 调 `getWindow().setWindowAnimations(0)` —— 实测次级窗口
  `mAttrs` 中 `wanim` 属性消失，窗口/任务入场动画关闭；
- B：`revealWindow()` 不再由 `FpWindowView.presentFrame` 首帧触发，改由
  `initSecondaryWindow` 在装饰校正之后延迟 400ms 统一显形（原 800ms 兜底由该定时器
  取代）。窗口在 task 定位/钳制与尺寸校正全部结束后一次性出现在最终位置。

- C：彻底禁用 starting window（Splash 预览窗）。新增应用资源
  `app/res/values/styles.xml`：`FpTheme`（parent `Theme.DeviceDefault.NoActionBar`
  + `android:windowDisablePreview=true`），Manifest 的 Activity 主题改
  `@style/FpTheme`；`build.bat` 增加 `aapt2 compile --dir app\res -o out\res.zip`
  并把 `res.zip` 传给 `aapt2 link`（注意路径含空格时 RESZIP 需自带引号）。
  实测启动/弹窗日志与 SurfaceFlinger 层列表中不再出现 `Splash Screen`，
  闪黑消失；子窗口在 A+B 基础上一次性补齐。

### 9.7 鼠标按键映射（2026-10-02 追加，右键菜单修复）

**实测 LDPlayer 鼠标事件序列**（sendevent BTN_MOUSE/BTN_RIGHT + logcat）：
一次点击只发 **`ACTION_DOWN`（`buttonState` 携带按键位，右键=2）+ `ACTION_UP`**，
**没有** `ACTION_BUTTON_PRESS/RELEASE`；且左键可被 LDPlayer 映射为触摸事件。
此前"只用 BUTTON_PRESS/RELEASE、丢弃 DOWN/UP"的映射因此把右键全部丢掉
（日志无 `TfpgPopupMenu` 创建），编辑框右键菜单不弹。

**修复**：新增 `FpMouseGesture`（FpMouseGesture.java）状态机，三处输入入口
（`FpSurfaceView/FpWindowView/FpSubWindow`）统一使用：
- `ACTION_DOWN`：记录 `pendingDown/pendingButton`，暂不发送；
- `ACTION_BUTTON_PRESS`：用 `actionButton` 补发唯一的 DOWN；
- `ACTION_MOVE/UP/BUTTON_RELEASE/CANCEL`：若 DOWN 仍未发则先按 `buttonState`
  补发，再发对应事件；重复的 DOWN/UP 被抑制。

对三种序列均恰好产生一对带正确按键的 DOWN/UP：
①仅 `DOWN(bs=2)+UP`（LDPlayer 虚拟鼠标注入，实测右键弹菜单 pos=400,103、
左键点 MenuTest 弹 pos=200,260）；②`DOWN+BUTTON_PRESS/RELEASE+UP`；
③`DOWN(bs=0)+BUTTON_PRESS(2)`。触摸（非 mouse）路径不变。

**真机验证（Android 16 / arm64，鼠标）**：`TOUCH src=8194`（SOURCE_MOUSE）
`bs=2 tool=3` → `MOUSE raw=0 bs=2` → `TfpgPopupMenu` 正常创建，右键菜单可用；
无 freeform 的设备走 PopupWindow 回退路径同样正常。

**LDPlayer 实测限制**：LDPlayer 把宿主机"右键"翻译为**触摸**事件
（`src=4098`=TOUCHSCREEN、`tool=1`、`bs=0`），应用无法区分它和左键——
这是模拟器行为，非应用缺陷；真机鼠标（或 LDPlayer 的虚拟鼠标注入）才能得到
真正的 `SOURCE_MOUSE` 右键事件。
