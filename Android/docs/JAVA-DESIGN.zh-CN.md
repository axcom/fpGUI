# fpGUI Android Java 层设计说明

# （JAVA-DESIGN.zh-CN.md）

> 适用代码：`test/android/app/java/com/fpgui/`（helloworld 测试工程，主版本）。
> `test/android - 2/`（pkeditor）为镜像副本，6 个文件内容一致，改动需同步（见 §13）。
> 相关文档：
> - `framework/src/main/pascal/corelib/android/DESIGN.zh-CN.md`（总体设计）
> - `framework/src/main/pascal/corelib/android/FREEFORM-DESIGN.zh-CN.md`（多窗口/自由窗口）
> - `framework/src/main/pascal/corelib/android/FRAMEWORK-CHANGES.zh-CN.md`（改动记录）
> - `test/android/README.md`（构建与验证）

---

## 1. 总体架构

### 1.1 职责边界

Java 层是 Pascal 后端（`lib<app>.so`，`JNI_OnLoad` 位于 `fpg_android_bridge.pas`）
与 Android 系统之间的"薄壳"，本身不做任何控件逻辑与绘制：

| 方向 | 机制 |
|---|---|
| Java → Pascal | 各类 `native*` 方法（输入、surface、窗口事件），由 `JNI_OnLoad` 用 `RegisterNatives` 按 **名称+签名** 注册（`fpg_android_bridge.pas:678-774`） |
| Pascal → Java | 通过缓存的 `jmethodID` 调用公开方法：呈现帧、IME、子窗口、模态、装饰、剪贴板等 |

Java 层的四项职责：

1. **容器**：提供 Activity/View/Surface 承载 fpGUI 窗口；
2. **输入翻译**：把 Android 的触摸/鼠标/键盘事件翻译成 fpGUI 语义
   （鼠标按键识别、长按=右键、悬停、滚轮）；
3. **多窗口托管**：主窗口 = 全屏 Activity；次级窗口 = freeform Activity
   （不支持 freeform 的设备回退为应用内 PopupWindow）；wtPopup 菜单 = 始终应用内 PopupWindow；
4. **系统服务**：剪贴板、URL 打开、软键盘。

### 1.2 类关系

```
FpActivity（每个窗口一个实例）
├─ 主窗口 (windowId=0)
│   └─ FpSurfaceView        SurfaceHolder 渲染 + 输入 + IME
├─ 次级窗口 (windowId>0，freeform Activity 或 PopupWindow 回退)
│   └─ FpWindowView         纯 View + bitmap 呈现 + 输入 + IME
└─ 子窗口表 sSubWindows（wtPopup 菜单/下拉，始终应用内）
    └─ FpSubWindow (PopupWindow)
        └─ FrameView（内部类，纯 View）

输入翻译（被三个 View 复用）：
FpMouseGesture      鼠标 MotionEvent → 单一 DOWN/UP 对 + 正确按键
FpLongPressGesture  触摸长按 → 右键 DOWN/UP 对
```

### 1.3 线程模型

| 线程 | 工作 |
|---|---|
| **Java UI 线程** | Activity 生命周期、全部 View 回调（触摸/按键/IME/布局/焦点）、PopupWindow 操作、`setModalWindow`/`setMainDecoration` |
| **Pascal 渲染/主循环线程** | 直接调用 `presentFrame`/`presentSubFrame`（单生产者：`lockCanvas` 与 bitmap 写入安全）；`createSubWindow`/`moveSubWindow`/`setSubWindowVisible`/`destroySubWindow` 内部自动切 UI 线程 |
| 输入方向 | 事件在 UI 线程到达 → 入队 → 唤醒 Pascal 主循环处理 |

- 进程级静态表 `sSubWindows`/`sWindowActivities`：UI 线程写；渲染线程只读自己的条目。
- 静态状态在 `onDestroy`（主窗口）重置，避免进程缓存后再次启动被误判为重复启动。

---

## 2. 文件清单

| 文件 | 行数 | 职责 |
|---|---|---|
| `FpActivity.java` | 718 | 窗口宿主：生命周期、主/次级窗口初始化、freeform 启动、模态、装饰、子窗口管理、系统服务 |
| `FpSurfaceView.java` | 301 | 主窗口 SurfaceView：渲染回调、输入、IME、Java Canvas 呈现回退 |
| `FpWindowView.java` | 331 | freeform 次级窗口内容 View：bitmap 呈现、bounds/焦点上报、输入、IME |
| `FpSubWindow.java` | 269 | 应用内浮动窗（PopupWindow）：坐标换算、生命周期、输入 |
| `FpMouseGesture.java` | 146 | 鼠标手势状态机：DOWN 延迟到按键确定，保证右键可识别 |
| `FpLongPressGesture.java` | 100 | 触摸长按 → 鼠标右键映射 |

---

## 3. FpActivity.java

每窗口一个实例。`windowId==0` 为主窗口；`>0` 为次级窗口（freeform 或
PopupWindow 回退）。wtPopup（菜单）不建 Activity，而是建 `FpSubWindow`。

### 3.1 进程级静态状态（`FpActivity.java:59-80`）

| 字段 | 含义 |
|---|---|
| `sAppStarted` | 应用是否已启动；重复 launcher 启动先 `moveTaskToFront` 主任务再 `finish()` 丢弃 |
| `sMainTitleApplied` | 是否已为标题栏重启过（仅供已注释的标题栏重启逻辑使用） |
| `sInstanceCounter` / `instanceToken` | 实例自增号；Pascal 侧据此忽略被替换实例（如重启）的 surface/stop 回调 |
| `sDecorHeight` | 实测 freeform 系统标题栏高度（像素，0=未测）；首个对话框布局后测量并复用 |
| `sMainTitleText` | fpGUI 主窗标题（用于系统 ActionBar） |
| `sWindowActivities` | `windowId → FpActivity`（次级 freeform 窗口表） |
| `sSupportsFreeform` | `hasSystemFeature("android.software.freeform_window_management")` 缓存 |
| `sMainView` / `sMainActivity` | 主窗口的 SurfaceView / Activity（虚拟屏幕原点、输入转发目标） |
| `sModalWindowId` | 当前模态次级窗口 id（0=无）；模态期间其余窗口加 `FLAG_NOT_TOUCHABLE` |
| `sSubWindows` | `id → FpSubWindow`（应用内浮动窗表） |

### 3.2 实例状态与包元数据

- `windowId`、`instanceToken`、`borderless`、`skipNativeStop`（仅标题栏重启用）、
  `view`（主窗）、`windowView`（次级窗）。
- `getPresenterMode()`（`:89`）：读 manifest meta `com.fpgui.presenter`，
  `"native"` → 1（ANativeWindow 直写），否则 0（Java Canvas，默认）。
- `getLibraryName()`（`:105`）：读 meta `com.fpgui.lib_name`，默认 `"helloworld"`。
- `supportsFreeform(ctx)`（`:121`）：平台能力探测，进程内缓存。
- `inFreeform()`（`:129`）：`SDK>=24 && isInMultiWindowMode()`。
- `decorEstimate()`（`:147`）：`DECOR_DP(48dp) × density` 的标题栏高度初值。

### 3.3 窗口形态决策

| fpGUI 窗口 | 平台支持 freeform | Java 实现 |
|---|---|---|
| 主窗口（0） | — | 全屏 `FpActivity` + `FpSurfaceView` |
| wtPopup（`dismissOnOutside=true`） | 任意 | 始终 `FpSubWindow`（PopupWindow），建在其 owner 窗口的 Activity 内 |
| 对话框/窗体（`dismissOnOutside=false`） | 是 | 新 `FpActivity`，freeform 系统窗口（可拖动/缩放，带系统标题栏；borderless 除外） |
| 对话框/窗体 | 否 | 回退 `FpSubWindow`（应用内浮动窗） |

### 3.4 生命周期

**`onCreate`（`:197`）**

- `mainTitle` extra → `setTheme(Theme_DeviceDefault)`（标题栏重启路径，当前用户已停用，见 §3.7）。
- 主窗口：若 `sAppStarted && !mainTitle` → 先 `moveTaskToFront` 把运行中的主任务
  拉到前台，再 `finish()`（重复启动丢弃）；否则 `initMainWindow()` 并置 `sAppStarted=true`。
- 次级窗口：`initSecondaryWindow()`。

**`onDestroy`（`:503`）**

- 主窗口：`skipNativeStop=false` 时调 `nativeStop(instanceToken)`，并重置全部进程级状态
  （`sAppStarted=false`、`sMainView=null`、`sSubWindows.clear()` 等），保证进程被缓存后再次启动正常。
- 次级窗口：从 `sWindowActivities` 移除，并 `nativeWindowClosed(windowId)` 通知 Pascal。

**`onBackPressed`（`:533`）**

- 次级窗口：先 `windowView.handleBack()`（Pascal 关窗/关菜单链），未消费则 `super`（finish Activity）。
- 主窗口：`view.handleBack()` 未消费则 `super`（退出应用）。

### 3.5 主窗口初始化 `initMainWindow`（`:233`）

1. `requestWindowFeature(FEATURE_NO_TITLE)`（非标题栏重启时）；
2. `System.loadLibrary(getLibraryName())`；
3. `FrameLayout root` + `FpSurfaceView view`（MATCH_PARENT），注册 `watchMainViewSize`；
4. 非 freeform 时用 `OnApplyWindowInsetsListener` 给 root 加系统栏 padding（edge-to-edge）；
5. `setContentView(root)`；
6. 标题栏重启时设置 ActionBar 标题；
7. `view.nativeInit(activity, view, filesDir, cacheDir, externalDir, density, presenter, supportsFreeform)`；
8. **先** `view.nativeSurfaceChanged(token, dm.widthPixels, dm.heightPixels, dm.density)`
   预上报屏幕尺寸——保证 Pascal 主窗体在首个 `surfaceChanged` 到达前就按正确尺寸布局；
9. `view.requestFocus()`。

`watchMainViewSize`（`:379`）：`OnLayoutChangeListener` 在尺寸变化时补报
`nativeSurfaceChanged`（覆盖 surface 回调不触发的强制/最大化 resize 路径；
Pascal 按物理尺寸去重，重复上报无害）。

### 3.6 次级窗口初始化 `initSecondaryWindow`（`:285`）

1. `borderless` → `applyBorderlessTheme()`（`Theme_DeviceDefault_Dialog` + 无标题，
   必须在 `setContentView` 前）；否则 `FEATURE_NO_TITLE`；
2. 读取 `contentW/contentH` extras，创建 `FpWindowView` 并 `setContentView`；
3. borderless：`finishBorderlessWindow(w,h)`（透明背景、`setFinishOnTouchOutside(false)`、
   窗口尺寸=内容尺寸、`gravity=TOP|LEFT`）；
4. 带系统标题栏的对话框：`finishDialogWindow(cw, ch, sDecorHeight>0?sDecorHeight:decorEstimate())`
   （窗口高=内容+标题栏，`gravity=TOP|LEFT`）；
5. `setWindowAnimations(0)` 关闭 freeform 任务入场动画；
6. `alpha=0`，400ms 后 `revealWindow()`——等入场/尺寸校正完成再显示，避免看到窗口移动/空白；
7. 非 borderless 时 200ms 后测量真实标题栏高度（`frameH - viewH`，最多重试 10×100ms），
   写入 `sDecorHeight` 并把窗口高度校正为 `ch + decor`；
8. 若当前有模态且本窗口非模态本身且非 wtPopup → 立即 `applyModalTouchability(true)`；
9. `sWindowActivities.put(windowId, this)`；`windowView.nativeWindowAttached(...)` 通知 Pascal 重新推帧。

`freeformOptions`（`:154`）：`setLaunchBounds(Rect(x,y,x+w,y+h))` +
反射调用隐藏 `@SystemApi setLaunchWindowingMode(WINDOWING_MODE_FREEFORM=5)`；失败则回退 PopupWindow。

`finishBorderlessWindow`（`:176`）/ `finishDialogWindow`（`:365`）都做了两件事：

- `gravity = TOP|LEFT` + `decorView.setMinimumWidth/Height(0)`：freeform 任务有
  **220dp 最小尺寸**，窗口更小时系统会把内容居中导致弹窗位置偏移半个差值；
- 窗口尺寸按"内容（+标题栏）"精确设置，避免空白条带与 Pascal 侧尺寸回传被放大。

### 3.7 主窗口装饰 `setMainDecoration`（`:447`）

Pascal 在得知主窗属性后调用，UI 线程执行：

- 非主窗口直接忽略；
- 有标题 → 记录 `sMainTitleText`，更新 ActionBar；
- `fullscreen` → `FLAG_FULLSCREEN` + `SYSTEM_UI_FLAG_FULLSCREEN|LAYOUT_STABLE`，返回；
- `borderless` / 普通标题栏分支：**当前整段被注释**（`:468-479`）。
  原逻辑是"用普通主题重启一次 Activity 以获得系统标题栏，Pascal 应用保持运行并重新附着 surface"。
  用户已决定不启用该重启路径（`test/android - 2` 同样注释）。
  **修改时不要删除或取消注释这段代码**，除非明确要恢复标题栏重启行为；
  `skipNativeStop`、`sMainTitleApplied`、`EXTRA_MAIN_TITLE` 均为该路径的遗留支持。

### 3.8 模态阻塞 `setModalWindow`（`:398`）

Pascal 主循环在模态变化时调用（UI 线程执行）：

1. 记录 `sModalWindowId`；
2. 对每个次级窗口 `applyModalTouchability(a.windowId != id)`；
3. 主窗口 `applyModalTouchability(id != 0)`；
4. 模态窗口存在时 `ActivityManager.moveTaskToFront(modal.getTaskId(), 0)` 置顶。

`applyModalTouchability`（`:430`）用 `FLAG_NOT_TOUCHABLE` 加/清标志——
连系统标题栏按钮也一起禁用，实现"强阻塞"。

### 3.9 子窗口管理（Pascal → Java 入口）

| 方法 | 行 | 行为 |
|---|---|---|
| `createSubWindow(id,x,y,w,h,dismissOnOutside,borderless,ownerId)` | `:610` | UI 线程。已存在则忽略。`!dismissOnOutside && supportsFreeform` → 计算主窗原点，`startActivity` freeform（非 borderless 时 y 上移 decor、高度加 decor，使**内容**落在请求点）；异常回退 PopupWindow。PopupWindow 的 owner = `ownerId>0 ? sWindowActivities.get(ownerId) : this`，anchor = owner 的 `windowView` 或主 `view` |
| `moveSubWindow(id,x,y,w,h)` | `:669` | PopupWindow → `moveTo`；freeform 无公开移动 API（位置已在 launch bounds 中携带），no-op |
| `setSubWindowVisible(id,visible)` | `:679` | PopupWindow → `setVisible`；freeform 生命周期即创建/销毁，no-op |
| `destroySubWindow(id)` | `:687` | UI 线程。PopupWindow → `destroy` + 移表；否则 freeform Activity `finish()` |
| `presentSubFrame(id,pixels,w,h)` | `:707` | 渲染线程。PopupWindow → `presentFrame`；否则路由到 `windowView.presentFrame` |

坐标：`createSubWindow` 中 `ox/oy = view.getLocationOnScreen()`（主窗内容原点），
freeform launch bounds = `ox+x, oy+y(-decor)`——fpGUI 坐标是相对主窗内容原点的虚拟屏幕坐标。

### 3.10 系统服务

| 方法 | 行 | 说明 |
|---|---|---|
| `getClipboard()` | `:551` | `ClipboardManager` 读主剪贴板文本，空返回 `""` |
| `setClipboard(text)` | `:563` | UI 线程写主剪贴板 |
| `openUrl(url)` | `:577` | UI 线程 `ACTION_VIEW` + `NEW_TASK`；无 handler 时静默 |
| `finishActivity()` | `:593` | UI 线程 `finish()`（Pascal 退出应用路径） |
| `revealWindow()` | `:486` | 次级窗口 `alpha=1`（仅由 400ms 定时器调用；FpWindowView 首帧不再触发） |

---

## 4. FpSurfaceView.java

主窗口的 `SurfaceView`：渲染目标 + 主窗口输入源。所有 native 方法注册在
**FpSurfaceView 类**上（`fpg_android_bridge.pas:679-716`）。

### 4.1 渲染

- `surfaceCreated/Changed/Destroyed`（`:168/173/179`）→ `nativeSurfaceCreated/Changed/Destroyed`
  （携带 `instanceToken`，Pascal 忽略过期实例）。
- **Java Canvas 回退呈现** `presentFrame`（`:273`）：Pascal 检测到 ANativeWindow
  缓冲不可 CPU 映射时（如 LDPlayer 极速模式）走此路径——
  `holder.lockCanvas()` → 复用/新建 `ARGB_8888` Bitmap（与后端 RGBA 字节序一致）
  → `copyPixelsFromBuffer` → `drawBitmap` → `unlockCanvasAndPost`。
  异常（surface 消失等）只跳过当前帧。单生产者（Pascal 渲染线程），`lockCanvas` 线程安全。

### 4.2 输入

| 事件 | 处理 | 去向 |
|---|---|---|
| `onTouchEvent`（`:184`） | 鼠标（`SOURCE_MOUSE`）→ `FpMouseGesture`；触摸 → `FpLongPressGesture`（吞掉返回 true 的事件）；否则原样转发 | `nativeTouch(action, x, y, button)` |
| `onHoverEvent`（`:204`） | 仅鼠标；`ACTION_HOVER_MOVE` | `nativeHover(x, y)` |
| `onGenericMotionEvent`（`:218`） | 仅鼠标；`ACTION_SCROLL`，`AXIS_VSCROLL>0` → 滚轮上（-1） | `nativeWheel(delta)` |
| `onKeyDown/Up`（`:240/248`） | 先给 Pascal，未消费再 `super` | `nativeKey(keyCode, down, meta, unicode)` |
| `handleBack`（`:257`） | Back 键先给 Pascal（关弹窗/模态） | `nativeBack()` |

### 4.3 IME

- `onCheckIsTextEditor()` 恒 true；`onCreateInputConnection` 返回自定义
  `FpInputConnection`（`TYPE_CLASS_TEXT`，`IME_ACTION_DONE|NO_EXTRACT_UI|NO_FULLSCREEN`）。
- `commitText` → `nativeText`；`deleteSurroundingText` → `nativeDelete`；
  `sendKeyEvent` → `nativeKey`；`setComposingText` 不预览（等 commit）。
- `setKeyboardVisible(visible)`（`:90`）：post 到 UI 线程，`restartInput` + `showSoftInput`
  或 `hideSoftInputFromWindow`；由 Pascal 焦点变化驱动。

### 4.4 native 方法签名（必须与 bridge 注册一致）

| 方法 | 签名 |
|---|---|
| `nativeInit` | `(Landroid/app/Activity;Landroid/view/View;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;FIZ)V` |
| `nativeSurfaceCreated` | `(ILandroid/app/Activity;Landroid/view/Surface;)V` |
| `nativeSurfaceChanged` | `(IIIF)V` |
| `nativeSurfaceDestroyed` | `(I)V` |
| `nativeTouch` | `(IFFI)V` |
| `nativeHover` | `(FF)V` |
| `nativeWheel` | `(I)V` |
| `nativeKey` | `(IZII)Z` |
| `nativeText` | `(Ljava/lang/String;)V` |
| `nativeDelete` | `(II)V` |
| `nativeBack` | `()Z` |
| `nativeStop` | `(I)V` |

---

## 5. FpWindowView.java

freeform 次级窗口的内容 View（`windowId>0`）。

### 5.1 设计选择：为什么用纯 View 而不是 SurfaceView

销毁 `SurfaceView` 会让带宿主侧 GL 转译的模拟器（LDPlayer）重连渲染管道并崩溃。
纯 View 没有自己的 surface，显示/隐藏/销毁永远安全；帧经 bitmap 呈现。

### 5.2 渲染

- `presentFrame`（`:67`）：渲染线程调用。`synchronized` 内按需重建
  `ARGB_8888` bitmap、`copyPixelsFromBuffer`，随后 `postInvalidate()`。
  **不在首帧显示窗口**——显示由 `FpActivity` 400ms 后统一 `revealWindow()`。
- `onDraw`（`:57`）：`synchronized` 绘制 bitmap。
- `onSizeChanged`（`:189`）：若已有 bitmap 则重绘（首帧可能早于布局，
  `postInvalidate` 会丢失）；并 `reportBounds()`。

### 5.3 几何与焦点上报

- `reportBounds()`（`:161`）：取 `getLocationOnScreen`，**减去主窗内容原点**
  （`FpActivity.getMainViewLocation`）得到虚拟屏幕坐标；内容尺寸优先用 bitmap
  尺寸（freeform 任务可能被系统放大到最小尺寸）。与上次值相同则跳过；
  变化时 `nativeWindowBoundsChanged(id, x, y, w, h)`。
  相对（而非绝对屏幕）坐标可避免 `createSubWindow` 再加原点时双重累加（子菜单曾因此偏移）。
- `boundsPoll`（`:201`）：attach 后每 250ms 上报一次——拖动系统标题栏移动窗口
  只改位置不改尺寸，`onSizeChanged` 不触发，需要轮询。
- `onWindowFocusChanged(true)` → `nativeWindowFocused(id)`（Pascal 据此切焦点/键盘）。

### 5.4 输入与 IME

- `onTouchEvent`（`:249`）：鼠标 → `FpMouseGesture`；触摸 → `FpLongPressGesture`；
  否则 `nativeWindowTouch(id, action, x, y, 0)`。
- `onHoverEvent`（`:266`）→ `nativeWindowHover`；`onGenericMotionEvent`（`:279`）
  `ACTION_SCROLL` → `nativeWindowWheel`（滚轮上 = -1）。
- `onKeyDown/Up` → `nativeWindowKey`；`handleBack` → `nativeWindowBack(id)`。
- IME 与 FpSurfaceView 同构（`setKeyboardVisible`/`FpInputConnection` → `nativeWindowText/Delete/Key`）。

### 5.5 native 方法签名

| 方法 | 签名 |
|---|---|
| `nativeWindowAttached` | `(ILcom/fpgui/FpActivity;Lcom/fpgui/FpWindowView;)V` |
| `nativeWindowTouch` | `(IIFFI)V` |
| `nativeWindowHover` | `(IFF)V` |
| `nativeWindowWheel` | `(II)V` |
| `nativeWindowText` | `(ILjava/lang/String;)V` |
| `nativeWindowKey` | `(IIZII)Z` |
| `nativeWindowDelete` | `(III)V` |
| `nativeWindowBack` | `(I)Z` |
| `nativeWindowBoundsChanged` | `(IIIII)V` |
| `nativeWindowClosed` | `(I)V` |
| `nativeWindowFocused` | `(I)V` |

---

## 6. FpSubWindow.java

一个应用内浮动窗 = `PopupWindow` + 纯 `View`（`FrameView`）。
每个 fpGUI 次级窗口（菜单、下拉、无 freeform 时的对话框）都有真实窗口，
而不是合成进主窗缓冲，因此：主窗重绘不会擦掉覆盖的对话框；每个窗口收到
局部坐标的指针事件；z 序与外部触摸行为遵循 PopupWindow 规则。

### 6.1 关键属性（构造函数 `:116`）

| 属性 | 值 | 原因 |
|---|---|---|
| `setFocusable(false)` | 不可聚焦 | 键盘/IME 焦点始终留在主 SurfaceView；按键由 Pascal 路由到活动模态窗体 |
| `setTouchable(true)` | 可触摸 | 自身内容接收事件 |
| `setOutsideTouchable(false)` | 外部触摸**穿透** | 点击落在下层窗口（菜单栏/编辑框/对话框），由 Pascal 的 A1 逻辑关闭弹窗链并投递该点击——桌面式菜单切换 |
| `OnDismissListener` | `dismissed=true; visible=false; nativeSubWindowDismissed(id)` | 通知 Pascal |

`dismissOnOutside` 参数保留在 API 中但已不影响外部触摸行为（注释 `:123-124`）。

### 6.2 坐标换算 `toAnchorWindow`（`:159`）

```
out = mainLoc + (x, y) - anchorScreen + anchorWindow
```

- 输入 `(x,y)`：相对主窗内容原点（fpGUI 虚拟屏幕坐标，设备像素）；
- `mainLoc`：主窗内容原点在屏幕上的位置；
- `anchorScreen`/`anchorWindow`：anchor（所属窗口的 View）的屏幕位置/窗内位置；
- 结果：PopupWindow `showAtLocation(anchor, NO_GRAVITY, ...)` 所需的 anchor 窗口内坐标。
  支持弹窗属于次级 freeform 窗口（子菜单等）的情形。

### 6.3 生命周期

| 方法 | 行 | 说明 |
|---|---|---|
| `showAt` | `:170` | UI 线程。已显示则返回；`showAtLocation`；异常（window token 未就绪）50ms 后重试 |
| `moveTo` | `:197` | UI 线程 `popup.update(loc, w, h)` |
| `setVisible` | `:213` | show：未显示则 `showAt(0,0)`（调用方应先 move）；hide：`dismiss()` |
| `destroy` | `:231` | UI 线程：dismiss、摘除 listener、释放 bitmap |
| `presentFrame` | `:249` | 渲染线程：`!visible||dismissed` 丢弃；synchronized 写 bitmap + `postInvalidate` |
| `FrameView.onAttachedToWindow` | `:61` | `nativeSubWindowAttached(id)` 请求重绘（首帧可能早于 View 存在） |

### 6.4 输入

- `dispatchTouch`（`:146`）：鼠标 → `FpMouseGesture` → `nativeSubTouch`；触摸 →
  `nativeSubTouch(id, action, x, y, 0)`。**注意：应用内浮动窗不做长按=右键**
  （其内容本身就是弹出交互，Pascal 侧也未挂右键菜单）。
- `onHoverEvent` → `nativeSubHover`；`onGenericMotionEvent` → `nativeSubWheel`（上 = -1）。

### 6.5 native 方法签名（静态方法，注册在 FpSubWindow 类）

| 方法 | 签名 |
|---|---|
| `nativeSubWindowAttached` | `(I)V` |
| `nativeSubWindowDismissed` | `(I)V` |
| `nativeSubTouch` | `(IIFFI)V` |
| `nativeSubHover` | `(IFF)V` |
| `nativeSubWheel` | `(II)V` |

---

## 7. FpMouseGesture.java

### 7.1 背景问题

Android 的鼠标点击事件序列不统一：

- 标准：`ACTION_DOWN` + `ACTION_BUTTON_PRESS`（按下），
  `ACTION_BUTTON_RELEASE` + `ACTION_UP`（抬起）；
- 部分设备/模拟器的裸 `ACTION_DOWN/UP` 的 `getButtonState()` 为空；
- 某些模拟器只发其中一种序列。

若在 `ACTION_DOWN` 立即转发，会因按键未知被当成 0（普通触摸），
右键菜单无法识别。因此 **DOWN 延迟到按键确定**（BUTTON_PRESS / MOVE / UP），
并抑制重复，保证 Pascal 每个手势恰好收到一对带正确按键的 DOWN/UP。

### 7.2 按键映射

| 方法 | 行 | 映射 |
|---|---|---|
| `isMouse(event)` | `:28` | `(source & SOURCE_MOUSE) == SOURCE_MOUSE` |
| `actionButtonToId` | `:32` | `BUTTON_SECONDARY→2`，`BUTTON_TERTIARY→3`，`BUTTON_PRIMARY→1`，否则 0 |
| `buttonStateToId` | `:45` | 同上（位测试，优先级 2 > 3 > 1） |
| `pendingOrPrimary` | `:59` | 延迟期间按键未知时用 1（左键）兜底 |

fpGUI 约定：`button` 0=普通触摸，1=左，2=右，3=中（见 `nativeTouch` 注释）。

### 7.3 状态机 `handle`（`:63`）

| 事件 | 行为 |
|---|---|
| `ACTION_DOWN` | 已 active 则忽略；否则 `active=true; pendingDown=true; pendingButton=buttonStateToId(...)`，**不发送** |
| `ACTION_BUTTON_PRESS` | 有 pendingDown → 发 `DOWN(b)` 并清 pending；否则若未 active → 直接发 `DOWN(b)` |
| `ACTION_MOVE` | 有 pendingDown → 先补发 `DOWN(pendingOrPrimary)`；再发 `MOVE(lastButton)` |
| `ACTION_BUTTON_RELEASE` | 有 pendingDown → 先补发 DOWN；更新 `lastButton`；active 则发 `UP` 并复位 |
| `ACTION_UP` | 有 pendingDown → 先补发 DOWN；active 则发 `UP` 并复位 |
| `ACTION_CANCEL` | 有 pendingDown → 先补发 DOWN；active 则发 `CANCEL` 并复位 |
| 其它 | 忽略 |

### 7.4 实测事件序列对照

| 来源 | 序列 | 结果 |
|---|---|---|
| 真机鼠标（SOURCE_MOUSE） | `DOWN(bs=2)` → `UP` | 补发 DOWN(2) → UP(2)，右键菜单打开 |
| LDPlayer 虚拟鼠标（sendevent 注入） | `DOWN(bs=按键)` + `UP`，无 BUTTON_PRESS/RELEASE | 同上 |
| 标准序列 | `DOWN` + `BUTTON_PRESS` + `MOVE…` + `BUTTON_RELEASE` + `UP` | DOWN 在 BUTTON_PRESS 发出，UP 在 BUTTON_RELEASE 发出，无重复 |
| LDPlayer 宿主右键 | 被转译为**触摸**事件（`src=4098/tool=1/bs=0`），应用无法区分 | 走触摸路径（模拟器固有限制） |

---

## 8. FpLongPressGesture.java

### 8.1 需求与设计

触摸设备没有右键，长按映射为鼠标右键点击：

- DOWN 仍原样转发（用于焦点/光标定位，由调用方转发）；
- 超过 `ViewConfiguration.getLongPressTimeout()`（通常 500ms）未移动且未抬起 →
  在按下点发送完整右键点击 `DOWN(2)+UP(2)`（fpGUI 在右键 release 时打开上下文菜单，
  如 `TfpgBaseEdit.HandleRMouseUp`）；
- 触发后吞掉后续 MOVE/UP，避免再产生左键点击；
- 移动超过 `getScaledTouchSlop()` 视为拖动，取消定时器；
- 仅处理非鼠标事件（真实鼠标保留自己的按键）；
- 无右键菜单的控件：右键点击无效果（用户确认的目标行为）。

### 8.2 状态机 `handle`（`:64`）

| 事件 | 行为 | 返回值 |
|---|---|---|
| `ACTION_DOWN` | `down=true; fired=false`，记录坐标，重启定时器 | false（调用方照常转发 DOWN） |
| `ACTION_MOVE` | 已 fired → 吞；超 slop → 取消定时器（拖动） | fired |
| `ACTION_UP`/`CANCEL` | 取消定时器，`down=false`，返回是否已 fired 并复位 | fired（吞） |
| 其它 | — | fired |

定时器 `fire`（`:38`）：`down && !fired` 时 `fired=true`，发送
`DOWN(2, downX, downY)` + `UP(2, downX, downY)`。

### 8.3 接入点与行为边界

- 接入 `FpSurfaceView.onTouchEvent`（`:184`）与 `FpWindowView.onTouchEvent`（`:249`），
  在非鼠标分支中先调用；返回 true 时吞掉事件。
- **不接入** `FpSubWindow`（应用内菜单/下拉自身即弹出交互）。
- 长按触发后本次手势的所有后续事件都被吞掉，因此不会触发控件的左键 OnClick。
- `ViewConfiguration` 的 timeout/slop 随设备密度缩放，无需手工换算像素。

---

## 9. 输入事件端到端流程

### 9.1 触摸 / 鼠标（主窗与次级窗）

```
MotionEvent (UI thread)
└─ View.onTouchEvent
   ├─ SOURCE_MOUSE ? ──→ FpMouseGesture ──→ nativeTouch / nativeWindowTouch(button=1/2/3)
   └─ 触摸
      ├─ FpLongPressGesture.handle == true ? → 吞掉（长按已转右键）
      └─ 否 → nativeTouch / nativeWindowTouch(button=0)
```

应用内浮动窗：`FpSubWindow.FrameView.onTouchEvent` → 鼠标走 FpMouseGesture，
触摸直接 `nativeSubTouch`（无长按）。

Pascal 侧：事件入队 → 主循环分发到控件 → 右键 release 触发上下文菜单。

### 9.2 悬停 / 滚轮

仅 `SOURCE_MOUSE`；悬停必须走 `onHoverEvent`（Android 不通过 `onGenericMotionEvent`
投递 `ACTION_HOVER_MOVE`），滚轮走 `onGenericMotionEvent` 的 `ACTION_SCROLL`
（`AXIS_VSCROLL>0` = 滚轮上 = -1）。

### 9.3 键盘 / IME

物理键：`onKeyDown/Up` → `nativeKey`/`nativeWindowKey`（返回 true 消费）。
软键盘：`FpInputConnection.commitText → nativeText`、`deleteSurroundingText → nativeDelete`、
`sendKeyEvent → nativeKey`；焦点切换由 Pascal 调 `setKeyboardVisible`。

### 9.4 Back

`FpActivity.onBackPressed` → 主窗 `FpSurfaceView.handleBack()`（`nativeBack`）/
次级窗 `FpWindowView.handleBack()`（`nativeWindowBack`）→ Pascal 关闭弹窗/模态；
未消费才 `super.onBackPressed()`（结束 Activity）。

---

## 10. JNI 契约总表

### 10.1 Pascal → Java（`jmethodID` 调用）

| Java 方法 | 签名 | 说明 |
|---|---|---|
| `FpSurfaceView.setKeyboardVisible` | `(Z)V` | 主窗软键盘 |
| `FpWindowView.setKeyboardVisible` | `(Z)V` | 次级窗软键盘 |
| `FpActivity.getClipboard` | `()Ljava/lang/String;` | 读剪贴板 |
| `FpActivity.setClipboard` | `(Ljava/lang/String;)V` | 写剪贴板 |
| `FpActivity.openUrl` | `(Ljava/lang/String;)V` | ACTION_VIEW |
| `FpActivity.finishActivity` | `()V` | 退出应用 |
| `FpSurfaceView.presentFrame` | `(Ljava/nio/ByteBuffer;II)V` | 主窗 Java Canvas 帧 |
| `FpActivity.createSubWindow` | `(IIIIIZZI)V` | 创建次级/浮动窗口 |
| `FpActivity.moveSubWindow` | `(IIIII)V` | 移动浮动窗 |
| `FpActivity.setSubWindowVisible` | `(IZ)V` | 显示/隐藏浮动窗 |
| `FpActivity.destroySubWindow` | `(I)V` | 销毁窗口 |
| `FpActivity.presentSubFrame` | `(ILjava/nio/ByteBuffer;II)V` | 次级/浮动窗帧 |
| `FpActivity.setModalWindow` | `(I)V` | 模态阻塞 |
| `FpActivity.setMainDecoration` | `(ZZLjava/lang/String;)V` | 主窗装饰/标题 |

### 10.2 Java → Pascal（`RegisterNatives`，见 §4.4/§5.5/§6.5）

三组注册表分别在 `fpg_android_bridge.pas` 的
`NativeMethods`（FpSurfaceView）、`SubNativeMethods`（FpSubWindow）、
`WindowNativeMethods`（FpWindowView）。**Java 声明与 Pascal 注册的签名必须逐字一致**，
否则 `JNI_OnLoad` 注册失败、应用启动即崩。

---

## 11. 坐标系统

| 坐标系 | 定义 | 使用处 |
|---|---|---|
| **虚拟屏幕坐标** | 原点 = 主窗内容（`FpSurfaceView`）左上角；fpGUI/Pascal 全用此系 | Pascal `FPosition`、子窗口 x/y |
| **屏幕像素** | 虚拟坐标 + 主窗内容原点（`getMainViewLocation`） | freeform launch bounds、PopupWindow 定位 |
| **anchor 窗口坐标** | `mainLoc + (x,y) - anchorScreen + anchorWindow` | `PopupWindow.showAtLocation` |

规则：

- 次级窗口上报 bounds 时**减去**主窗原点（`FpWindowView.reportBounds`），保持虚拟坐标；
- 创建 freeform 窗口时**加上**主窗原点（`createSubWindow`）；
- 两者必须成对，否则连续创建（子菜单）会双重累加原点；
- 所有数值均为**设备像素**（Pascal 传入的 w/h/x/y 已由后端乘过 density）。

---

## 12. 关键设计决策与陷阱（防回归）

1. **次级窗/浮动窗一律纯 View + bitmap**：销毁 SurfaceView 会让 LDPlayer 等
   宿主侧 GL 转译模拟器重连渲染管道而崩溃。
2. **浮动窗不可聚焦**：IME 焦点留在主 SurfaceView，按键由 Pascal 路由到活动模态窗体；
   同时 `setOutsideTouchable(false)` 让外部点击穿透到下层窗口，由 Pascal 的 A1 逻辑
   关链并投递点击（桌面式菜单切换）。
3. **freeform 入场不可见**：`setWindowAnimations(0)` + `alpha=0` + 400ms 后 reveal，
   掩盖任务入场动画与标题栏高度校正；`sDecorHeight` 测量一次后复用。
4. **220dp 最小任务尺寸**：小窗口必须 `gravity=TOP|LEFT` + `setMinimumWidth/Height(0)`，
   否则内容被居中，弹窗位置偏移半个差值。
5. **标题栏高度**：非 borderless 对话框窗口高 = 内容 + 实测标题栏；
   launch y 上移 decor 使**内容**落在请求点；Pascal 收到的 bounds 因此不含空白条带。
6. **主窗尺寸双路上报**：`nativeSurfaceChanged`（预上报显示指标 + surface 回调）+
   `watchMainViewSize`（布局监听），Pascal 按物理尺寸去重。
7. **进程状态重置**：`onDestroy` 清 `sAppStarted` 等，保证进程缓存后重新启动不被当作重复启动。
8. **鼠标 DOWN 延迟**：右键识别的前提；不要在 `ACTION_DOWN` 立即发送。
9. **长按吞事件**：fired 后必须吞掉 MOVE/UP，否则长按会额外产生一次左键点击。
10. **悬停必须走 `onHoverEvent`**：否则菜单栏收不到指针，无法切换已打开菜单。
11. **`setMainDecoration` 注释块**：标题栏重启逻辑已被用户停用，保留注释与
    `skipNativeStop`/`sMainTitleApplied`/`EXTRA_MAIN_TITLE` 支持，勿删。
12. **freeform 反射**：`setLaunchWindowingMode` 是隐藏 API，失败必须回退 PopupWindow，
    不能假设设备一定支持。

---

## 13. 修改指南

1. **新增 Java 文件**：必须加入 `build.bat` 的 `javac` 文件列表
   （当前已含 `FpMouseGesture.java`、`FpLongPressGesture.java`，见 `build.bat:88-89`），
   并同步 `test/android - 2/build.bat`。
2. **改动 Java 后**：在 `test/android` 运行 `build.bat all` 重新编译
   （javac → d8 → aapt2 → zipalign → apksigner）；两个测试目录（`android` 与
   `android - 2`）的 `app/java/com/fpgui/` 文件需保持同步。
3. **修改 native 方法签名**：必须同步修改 `fpg_android_bridge.pas` 中对应注册表
   （`NativeMethods`/`SubNativeMethods`/`WindowNativeMethods`），
   Pascal 库也要重新编译（build.bat 会重建）。
4. **多设备安装**：`build.bat -i` 内部裸 `adb install` 在多设备时会失败；
   用 `adb -s <serial> install -r <apk>` 手动安装。
5. **调试输入事件**：临时在 `onTouchEvent`/`onGenericMotionEvent` 打印
   `event.getSource()/getActionMasked()/getButtonState()/getActionButton()`，
   可快速区分触摸/鼠标与事件序列（排查后记得删除，避免刷屏）。
6. **不要给 `FpSubWindow` 加长按=右键**；不要取消 `setMainDecoration` 的注释块；
   不要假设 freeform 一定可用。
