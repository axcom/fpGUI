# Embedded UI Extension — TfpgForm in Embedded XComponent

> 目标：把 fpGUI 的 `TfpgForm`（Pascal）渲染到 ArkUI 页面里一个**预创建的 XComponent**（surface）中，
> 并让触摸/鼠标/滚轮事件坐标与窗口内容 1:1 对齐。
>
> 适用范围：HarmonyOS/OpenHarmony 设备 + fpGUI(OHOS) + `libfp_bridge.so`。
>
> 参考实现：`F:\Huawei\lazQtOHOS_Demo\fpGUI_Demo`（entry 模块）+ `D:\fpGUI\fpGUI-2.1.0\test\helloworld`。

---

## 目录

1. [核心原理](#1-核心原理)
2. [完整调用链 / 时序](#2-完整调用链--时序)
3. [关键设计决策](#3-关键设计决策)
4. [代码清单](#4-代码清单)
5. [从零接入步骤](#5-从零接入步骤)
6. [最小示例](#6-最小示例)
7. [常见问题与坑](#7-常见问题与坑)
8. [验证检查点](#8-验证检查点)

---

## 1. 核心原理

### 1.1 进程与 surface 归属（最重要）

- Pascal 应用（`libhelloworld.so`）与 `libfp_bridge.so` 运行在 **entry 主进程**。
- ArkUI 页面里的 `XComponent(type: SURFACE)` 也创建在**同一个主进程**，其
  `controller.getXComponentSurfaceId()` 返回**真实 surfaceId**（uint64，十进制字符串）。
- C++ 侧用 `OH_NativeWindow_CreateNativeWindowFromSurfaceId(sid, &win)` 把该 surface
  包装成 `OHNativeWindow*`，作为 Pascal 的渲染目标（buffer 提交目标）。

> ⚠️ **跨进程 surface 不可共享**。若把渲染放到 `embeddedUI` 扩展进程（`extensionProcessMode`
> 为 `instance`/`bundle`，实测 `runWithMainProcess` 也不生效），主进程无法绑定该 surface。
> 因此本方案**不使用扩展进程渲染**，surface 一律由主进程页面预创建。

### 1.2 谁决定渲染目标

```
ArkUI 预创建 XComponent ──(onLoad: 真实 sid + 尺寸)──▶ dispatch('showSecondForm')
        ▲                                                     │
        │                                                     ▼
        │                                            Pascal: form.EmbeddedSurfaceId = sid
        │                                                     │  form.Width/Height = 尺寸(vp)
        │                                                     ▼
        │                                            form.Show → DoAllocateWindowHandle
        │                                                     │  opts.SurfaceID = EmbeddedSurfaceId
        │                                                     ▼
        │                                     C++ ohos_create_window → createWindowFromNative(sid)
        │                                                     │
        └────────── onSurfaceReady(reqId, xcId, sid) ◀────────┘
                                （ETS 侧把 sid 交回 C++）
                                                     │
                                                     ▼
                                  C++ SurfaceIdToWindow(sid) → Pascal 拿到句柄
                                                     │
                                                     ▼
                                         TfpgForm 渲染进该 XComponent
```

**要点**：`surfaceId` 是"预创建 surface"的真实 id，不是 reqId、也不是占位哨兵。

### 1.3 尺寸：由 XComponent 决定

- XComponent 的布局尺寸（vp）随 `onLoad`/`onAreaChange` 一起上报。
- Pascal 把 `form.Width/Height` 设为该 vp 值；`DoAllocateWindowHandle` 计算
  `opts.width/height = vp × gScaleFactorX × gScaleFactor` = 物理像素 = surface 像素。
- 结果：Pascal 的 buffer 与 XComponent surface **1:1**，无拉伸、无错位。

### 1.4 事件坐标：组件本地 vp，C++ 统一转 px

| 环节 | 坐标系 |
|---|---|
| ArkUI `onTouch` → `t.x / t.y` | 组件本地 **vp** |
| ArkUI `onMouse` → `event.x / event.y` | 组件本地 **vp** |
| C++ `OnTouchEvent/OnMouseEvent` | `px = vp × g_density` |
| Pascal | 物理像素，相对窗口客户区 |

> ⚠️ **不要在 ETS 侧再乘 `densityPixels`**，否则会被 C++ 二次缩放 → 鼠标位置整体错位。

---

## 2. 完整调用链 / 时序

```
① ArkUI 页面构建
   EmbeddedFormHost (XComponent, SURFACE)
     ├─ onLoad        → sid = xcCtrl.getXComponentSurfaceId()
     └─ onAreaChange  → areaW/areaH (vp)
   两者齐备 → tryFire() → onSurfaceCreated(sid, areaW, areaH)

② 页面回调
   Index.onEmbeddedSurfaceCreated(sid, wVp, hVp)
     → triggerShowSecondForm()
     → fpbridge.dispatch('showSecondForm', {"surfaceId":"<sid>","width":w,"height":h})

③ Pascal（主进程，dispatch 同步执行 handler）
   HandleShowSecondForm(params)
     → ParseJsonNum: surfaceId / width / height
     → form.Width := wVp; form.Height := hVp
     → form.EmbeddedSurfaceId := sid
     → form.Show
          └─ TfpgWidget.InternalHandleShow → AllocateWindowHandle
               ├─ TfpgWidget.DoAllocateWindowHandle   (创建 FWindow)
               └─ TfpgOhosWindow.DoAllocateWindowHandle
                    ├─ if TfpgWidgetBase(Owner).EmbeddedSurfaceId <> 0
                    │     then opts.SurfaceID := EmbeddedSurfaceId
                    └─ _ohos_create_window(@opts)   ← C++ 阻塞等待 surface

④ C++ ohos_create_window
   reqId 分配 → cmd->surfaceId = opts->surfaceId
   → SendNativeCommand(NATIVE_CMD_CREATE_WINDOW)  (TSFN → JS 线程)
   → 等待 g_xcCV（req->done）

⑤ ETS createWindowFromNative(reqId, …, surfaceId)
   if surfaceId > '0'  → 嵌入模式
     ├─ AppStorage['embeddedWinReqId'] = reqId      (供事件转发)
     └─ fpbridge.onSurfaceReady(reqId, xcId, surfaceId)

⑥ C++ OnSurfaceReady
   SurfaceIdToWindow(sid, w, h) → OHNativeWindow*
   → req->nativeWin / req->done = true → 唤醒 ④
   → Pascal 获得 FWinHandle，开始渲染

⑦ 事件
   EmbeddedFormHost.onTouch/onMouse (本地 vp)
     → fpbridge.onTouchEvent/onMouseEvent(reqId, vp…)
     → C++ ×g_density → Pascal EnqueueMouseEvent → 派发到控件
```

---

## 3. 关键设计决策

### 3.1 为什么 `EmbeddedSurfaceId` 放在 `TfpgWidgetBase`，而不是全局变量

窗口对象在 `Show` 时才创建（`TfpgWidget.InternalHandleShow → AllocateWindowHandle`），
`Show` 之前 `form.Window` 为 `nil`，没有窗口字段可写。早期用全局变量
`g_embedded_surface_id` 暂存"下一个窗口的 surfaceId"，不优雅。

最终方案：把字段放在 **Form 自身**（`TfpgWidgetBase`），窗口分配时从 `Owner` 读取：

```pascal
// fpg_base.pas
TfpgWidgetBase = class(...)
public
  EmbeddedSurfaceId: UInt64;   // 0 = 普通窗口；≠0 = 渲染到该 surface
end;

// fpg_ohos.pas — TfpgOhosWindow.DoAllocateWindowHandle
if (Owner is TfpgWidgetBase) and (TfpgWidgetBase(Owner).EmbeddedSurfaceId <> 0) then
  opts.SurfaceId := TfpgWidgetBase(Owner).EmbeddedSurfaceId;
```

无全局、无消息、无耦合（corelib 只依赖 `TfpgWidgetBase`）。

### 3.2 为什么 surfaceId 以字符串传递

- `OH_NativeWindow_CreateNativeWindowFromSurfaceId` 接收 `uint64_t`。
- 但跨 NAPI/JSON 传输时，用**十进制字符串**最稳（避免 double 精度、FPC 交叉编译
  `Val`/`StrToQWord` 兼容问题）。
- C++ 序列化：`snprintf(buf, "%llu", cmd->surfaceId)`。
- Pascal 解析：手动逐字符扫描数字（`ParseJsonNum`），不用 `Val` 直接读 UInt64。

### 3.3 事件 reqId 的传递

`createWindowFromNative` 拿到的 `reqId` 由 C++ 分配。ETS 把它写入
`AppStorage['embeddedWinReqId']`，`EmbeddedFormHost` 的事件处理器据此转发。

---

## 4. 代码清单

### 4.1 框架侧（fpGUI）

**`framework/src/main/pascal/corelib/fpg_base.pas`**

```pascal
TfpgWidgetBase = class(TfpgObject)
  ...
public
  EmbeddedSurfaceId: UInt64;   // 0 = 普通窗口；≠0 = 嵌入到该 surface
```

**`framework/src/main/pascal/corelib/ohos/fpg_ohos.pas`**（`TfpgOhosWindow.DoAllocateWindowHandle`）

```pascal
opts.left := Round(FPosition.X * gScaleFactorX);
opts.top  := Round(FPosition.Y * gScaleFactorY);

// 嵌入模式：从 Owner（Form）读取目标 surface
if (Owner is TfpgWidgetBase) and (TfpgWidgetBase(Owner).EmbeddedSurfaceId <> 0) then
  opts.SurfaceId := TfpgWidgetBase(Owner).EmbeddedSurfaceId;

if Assigned(_ohos_create_window) then
begin
  FWinHandle := _ohos_create_window(@opts);
  FPhysicalWidth  := opts.width;
  FPhysicalHeight := opts.height;
end;

if (FWinHandle <> nil) then
begin
  if opts.SurfaceId = 0 then   // 嵌入窗不做系统窗口定位
    DoUpdateWindowPosition;
  ...
end;
```

> `TOHOSWindowOptions.SurfaceID: UInt64` 与 C++ `WindowOptions.surfaceId` 必须保持配对
> （ABI 对齐，`{$packrecords C}`）。

### 4.2 C++ 桥（`libfp_bridge`）

**`WindowOptions`（Pascal ↔ C++ ABI）**

```cpp
#pragma pack(push, 4)
struct WindowOptions {
    int32_t windowType;
    int32_t windowAttributes;
    int32_t windowState;
    int32_t isMainform;
    int32_t mouseCursor;
    float   opacity;
    int32_t left, top, width, height;
    char    title[256];
    uint64_t surfaceId;      // 嵌入模式目标 surface
};
#pragma pack(pop)
```

**`ohos_create_window`**（透传 surfaceId 给 ETS）

```cpp
cmd->surfaceId = opts->surfaceId;     // 原样带给 ETS
```

**`NativeCallbackCallJS`**（uint64 → 字符串）

```cpp
char sidBuf[32];
snprintf(sidBuf, sizeof(sidBuf), "%llu", (unsigned long long)cmd->surfaceId);
napi_create_string_utf8(env, sidBuf, NAPI_AUTO_LENGTH, &sidVal);
napi_set_named_property(env, arg, "surfaceId", sidVal);
```

**`OnSurfaceReady(reqId, xcId, sid)`**（把 sid 绑成 native window）

```cpp
OHNativeWindow* nativeWin = nullptr;
if (sid[0] != '\0') {
    uint64_t surfaceId = std::strtoull(sid, nullptr, 10);
    nativeWin = SurfaceIdToWindow(surfaceId, physW, physH);   // CreateNativeWindowFromSurfaceId
}
// 回填 req->nativeWin / req->done，唤醒阻塞中的 ohos_create_window
```

**事件 vp → px**

```cpp
// OnTouchEvent / OnMouseEvent
float px = (float)(x * g_density);
float py = (float)(y * g_density);
```

**NAPI 声明（`types/libfp_bridge/Index.d.ts`）**

```typescript
export const onSurfaceReady: (reqId: number, xcId: string, surfaceId: string) => void;
export const onTouchEvent: (reqId: string, x: number, y: number, action: number) => void;
export const onMouseEvent: (reqId: string, x: number, y: number, action: number, button: number) => void;
export const onWheelEvent: (reqId: string, x: number, y: number, delta: number) => void;
export const dispatch: (op: string, params: string) => Promise<string>;
```

### 4.3 ArkUI 侧（entry）

**`entry/src/main/ets/common/EmbeddedFormHost.ets`**（预创建 XComponent + 事件转发）

```typescript
import fpbridge from 'libfp_bridge.so';
import { display } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const MOUSE_ACTION_PRESS = 1;
const MOUSE_ACTION_RELEASE = 2;
const MOUSE_ACTION_MOVE = 3;
const MOUSE_ACTION_HOVER = 4;

@Component
export struct EmbeddedFormHost {
  // 回调：surface 就绪（sid + 尺寸 vp）
  onSurfaceCreated: (sid: string, wVp: number, hVp: number) => void =
    (_sid: string, _w: number, _h: number): void => {};
  private xcCtrl: XComponentController = new XComponentController();
  private sid: string = '';
  private areaW: number = 0;
  private areaH: number = 0;
  private fired: boolean = false;

  private tryFire(): void {
    if (this.fired) return;
    if (this.sid === '' || this.areaW <= 0 || this.areaH <= 0) return;
    this.fired = true;
    this.onSurfaceCreated(this.sid, this.areaW, this.areaH);
  }

  private eventReqId(): number {
    return AppStorage.get<number>('embeddedWinReqId') ?? 0;
  }

  build() {
    XComponent({ id: 'xc_embedded_host', type: XComponentType.SURFACE, controller: this.xcCtrl })
      .width('100%').height('100%')
      .onLoad(() => {
        this.sid = this.xcCtrl.getXComponentSurfaceId();   // 真实 surfaceId
        this.tryFire();
      })
      .onAreaChange((_o: Area, n: Area) => {
        this.areaW = Math.round(Number(n.width) || 0);
        this.areaH = Math.round(Number(n.height) || 0);
        this.tryFire();
      })
      .onTouch((event: TouchEvent) => {
        const rid = this.eventReqId();
        if (rid <= 0 || event.touches.length === 0) return;
        const t = event.touches[0];
        const sx = Math.round(t.x ?? 0);      // 本地 vp（C++ ×density）
        const sy = Math.round(t.y ?? 0);
        if (event.type === TouchType.Down) fpbridge.onTouchEvent(String(rid), sx, sy, 0);
        else if (event.type === TouchType.Move) fpbridge.onTouchEvent(String(rid), sx, sy, 1);
        else if (event.type === TouchType.Up) fpbridge.onTouchEvent(String(rid), sx, sy, 2);
      })
      .onMouse((event: MouseEvent) => {
        const rid = this.eventReqId();
        if (rid <= 0) return;
        const btn = event.button as number;
        const ma = event.action as number;
        let act = 1;
        if (ma === MOUSE_ACTION_PRESS) act = 0;
        else if (ma === MOUSE_ACTION_RELEASE) act = 2;
        const mx = Math.round(event.x ?? 0);  // 本地 vp
        const my = Math.round(event.y ?? 0);
        fpbridge.onMouseEvent(String(rid), mx, my, act, btn);
      })
      .onAxisEvent((event: AxisEvent) => {
        const rid = this.eventReqId();
        if (rid <= 0) return;
        const v = event.axisVertical ?? 0;
        if (v === 0) return;
        fpbridge.onWheelEvent(String(rid), Math.round(event.x ?? 0),
          Math.round(event.y ?? 0), v > 0 ? 1 : -1);
      })
  }
}
```

**`entry/src/main/ets/pages/Index.ets`**（页面接入）

```typescript
import { EmbeddedFormHost } from '../common/EmbeddedFormHost';

// 嵌入窗在页面中的位置/尺寸（vp）
const EMBED_POS_X: number = 120;
const EMBED_POS_Y: number = 38;
const EMBED_W: number = 300;
const EMBED_H: number = 200;

interface ShowSecondFormParams {
  surfaceId: string;
  width: number;
  height: number;
}

@Entry
@Component
struct Index {
  @State embedSurfaceId: string = '';
  @State embedSurfaceW: number = 0;
  @State embedSurfaceH: number = 0;

  private onEmbeddedSurfaceCreated(sid: string, wVp: number, hVp: number): void {
    this.embedSurfaceId = sid;
    this.embedSurfaceW = wVp;
    this.embedSurfaceH = hVp;
    this.triggerShowSecondForm();
  }

  private triggerShowSecondForm(): void {
    if (this.embedSurfaceId === '') return;
    const p: ShowSecondFormParams = {
      surfaceId: this.embedSurfaceId,
      width: this.embedSurfaceW,
      height: this.embedSurfaceH
    };
    fpbridge.dispatch('showSecondForm', JSON.stringify(p));
  }

  build() {
    Stack() {
      // ... 主窗 FpgSurface 等 ...

      EmbeddedFormHost({
        onSurfaceCreated: (sid: string, wVp: number, hVp: number): void => {
          this.onEmbeddedSurfaceCreated(sid, wVp, hVp);
        }
      })
        .width(EMBED_W).height(EMBED_H)
        .position({ x: EMBED_POS_X, y: EMBED_POS_Y })

      // 可选：手动触发按钮
      Button('显示嵌入窗体')
        .position({ x: EMBED_POS_X, y: EMBED_POS_Y + EMBED_H + 12 })
        .onClick(() => { this.triggerShowSecondForm(); })
    }
  }
}
```

**`createWindowFromNative` 嵌入分支**（关键：绑定预创建 surface）

```typescript
if (surfaceId !== undefined && surfaceId > '0') {   // 字符串比较：非 '0' 即嵌入
  AppStorage.setOrCreate<number>('embeddedWinReqId', reqId);   // 供事件转发
  AppStorage.setOrCreate<number>('winClientW_' + reqId, width);
  AppStorage.setOrCreate<number>('winClientH_' + reqId, height);
  fpbridge.onSurfaceReady(reqId, xcId, surfaceId);             // 把 sid 交回 C++ 绑定
  return;
}
```

### 4.4 Pascal 应用侧

**`test/helloworld/helloworld.lpr`**

```pascal
{ 简易 JSON 数值字段提取：支持 "key":123 与 "key":"123" }
function ParseJsonNum(const Params, AKey: string; out AValue: Int64): Boolean;
var
  p, i: Integer;
  s: string;
  code: Integer;
begin
  Result := False;
  AValue := 0;
  p := Pos(AKey, Params);
  if p <= 0 then Exit;
  i := p + Length(AKey);
  while (i <= Length(Params)) and (Params[i] <> ':') do Inc(i);
  if i > Length(Params) then Exit;
  Inc(i);
  while (i <= Length(Params)) and ((Params[i] = ' ') or (Params[i] = '"')) do Inc(i);
  s := '';
  while (i <= Length(Params)) and (Params[i] >= '0') and (Params[i] <= '9') do
  begin
    s := s + Params[i];
    Inc(i);
  end;
  if s = '' then Exit;
  Val(s, AValue, code);
  Result := (code = 0);
end;

function HandleShowSecondForm(const Params: string): string;
var
  sid: UInt64;
  v: Int64;
  wVp, hVp: Integer;
begin
  sid := 0;
  if ParseJsonNum(Params, 'surfaceId', v) then sid := UInt64(v);
  wVp := 0;
  hVp := 0;
  if ParseJsonNum(Params, 'width', v)  then wVp := Integer(v);
  if ParseJsonNum(Params, 'height', v) then hVp := Integer(v);
  fpGUI_Hilog(LOG_INFO, format('showSecondForm: sid=%s size=%dx%d(vp)',
    [UIntToStr(sid), wVp, hVp]));

  if gMainForm = nil then
    gMainForm := TMainForm.Create(nil);
  with gMainForm do
  begin
    { 嵌入窗口大小完全由预创建 XComponent 的尺寸(vp)决定 }
    if (wVp > 0) and (hVp > 0) then
    begin
      Width  := wVp;
      Height := hVp;
    end;
    EmbeddedSurfaceId := sid;   // TfpgWidgetBase 字段
    Show;                       // Show 时窗口分配并消费 EmbeddedSurfaceId
  end;

  Result := '{"ok":true}';
end;

procedure RegisterMyHandlers;
begin
  RegisterSync('showSecondForm', @HandleShowSecondForm);
end;
```

> `EmbeddedSurfaceId` 必须在 `Show` **之前**设置（窗口句柄在 `Show` 时创建）。
> 任意 `TfpgForm` 均可，把上例的 `gMainForm` 换成你的窗体即可。

---

## 5. 从零接入步骤

1. **框架（fpGUI）**
   - `fpg_base.pas`：`TfpgWidgetBase` 增加 `EmbeddedSurfaceId: UInt64`。
   - `fpg_ohos.pas`：`TOHOSWindowOptions` 增加 `SurfaceID: UInt64`；
     `TfpgOhosWindow.DoAllocateWindowHandle` 从 `Owner` 读取并写入 `opts.SurfaceID`；
     嵌入窗跳过 `DoUpdateWindowPosition`。
2. **C++ 桥（`libfp_bridge`）**
   - `WindowOptions.surfaceId`（uint64，保持与 Pascal 记录 ABI 对齐）。
   - `ohos_create_window`：`cmd->surfaceId = opts->surfaceId`。
   - `NativeCallbackCallJS`：`surfaceId` 序列化为**字符串**。
   - `OnSurfaceReady`：`SurfaceIdToWindow(sid)` 绑定。
   - 事件：`px = vp × g_density`。
3. **ArkUI（entry）**
   - 新增 `EmbeddedFormHost.ets`（预创建 XComponent + onLoad/onAreaChange + 事件转发）。
   - `Index.ets`：渲染 `EmbeddedFormHost`；`createWindowFromNative` 加嵌入分支
     （`surfaceId > '0'` → `onSurfaceReady` + 记录 `embeddedWinReqId`）。
4. **Pascal 应用**
   - 注册 `showSecondForm` handler，解析 `surfaceId/width/height`，
     设置 `form.Width/Height` 与 `form.EmbeddedSurfaceId`，`Show`。
5. **构建顺序**
   1) Pascal → `libhelloworld.so`
   2) `libfp_bridge.so`（若改了 C++）
   3) HAP/App（`hvigorw assembleApp`）

---

## 6. 最小示例

**目标**：在页面 `(120,38)` 处嵌入一个 `300×200(vp)` 的 `TfpgForm`。

```typescript
// Index.ets build()
EmbeddedFormHost({
  onSurfaceCreated: (sid, w, h) => this.onEmbeddedSurfaceCreated(sid, w, h)
})
  .width(300).height(200)
  .position({ x: 120, y: 38 })
```

```pascal
// Pascal
EmbeddedSurfaceId := sid;
Width  := wVp;    // 300
Height := hVp;    // 200
Show;
```

**预期日志**

```
EmbeddedFormHost surface ready sid=2194728288595 size=300x200(vp)
dispatch showSecondForm surfaceId=2194728288595 size=300x200(vp)
showSecondForm: sid=2194728288595 size=300x200(vp)
ohos_create_window- type=1 wdg=(300,200) ... opts=(0,0,570,380)
ohos_create_window: req=2 xcId=xc_fpg_2 w=570 h=380
createEmbeddedWin req=2 surfaceId=2194728288595 size=570x380
SurfaceIdToWindow: sid=2194728288595 w=570 h=380
ohos_create_window SUCCESS: req=2
```

`570×380 px = 300×200 vp × 1.9(density)` → 尺寸一致。

---

## 7. 常见问题与坑

| 现象 | 根因 | 解决 |
|---|---|---|
| **鼠标点击位置错位（整体偏大/偏移）** | ETS 侧 `event.x/y × densityPx`，C++ 又 `× g_density` → **双重缩放** | ETS 只上报**组件本地 vp**（`t.x`/`event.x`），不乘 density |
| **内容被拉伸/裁切** | Pascal 窗口 buffer 尺寸 ≠ surface 尺寸 | 用 XComponent 的 `onAreaChange` 尺寸(vp) 设置 `form.Width/Height` |
| **surface 绑定失败 `OnSurfaceReady FAILED`** | 在窗口创建前调用了 `onSurfaceReady`（`g_xcReqs[reqId]` 不存在），或跨进程 | 只在 `createWindowFromNative` 收到 sid 后调用；确保同进程 |
| **`dispatch not connected` / `NOT_CONNECTED`** | `ohos_bridge_connect` 里 `FillChar(pascalApi,...)` 把 `dispatch`/`dispatch_free` 清零 | 在 `FillChar` 前保存、之后恢复这两个字段 |
| **`showSecondForm` 未注册 / 不执行** | handler 未注册，或注册晚于首次 dispatch | 在 `MainProc` 开始处 `RegisterMyHandlers` |
| **surfaceId 解析为 0** | FPC 交叉编译下 `s[p] in ['0'..'9']` / `Copy` 行为异常；或 uint64 用 `Val` 失败 | 手动逐字符扫描数字 + `Val(Int64)`（见 `ParseJsonNum`） |
| **Show 前设置 `Window.EmbeddedSurfaceId` 无效** | `Show` 前 `form.Window` 为 `nil` | 用 `form.EmbeddedSurfaceId`（Form 自身字段），分配时由窗口读取 |
| **`assembleApp` 报 `Compress failed`（偶发）** | 旧产物/文件被占用 | 重试；必要时删除 `build/outputs` 后重建 |
| **两个 HAP 都带同名 `.so` 导致行为异常** | 多模块同名 native 库解析歧义 | 只在需要的模块保留 `libfp_bridge.so` |

---

## 8. 验证检查点

1. `EmbeddedFormHost surface ready sid=<sid> size=<w>x<h>(vp)` — 预创建 surface 就绪。
2. `dispatch showSecondForm surfaceId=<sid> size=<w>x<h>(vp)` — 携带**真实** sid。
3. `showSecondForm: sid=<sid> size=<w>x<h>(vp)` — Pascal 收到并解析成功。
4. `ohos_create_window- ... opts=(0,0,<pxW>,<pxH>)` — `pxW = w × density`。
5. `createEmbeddedWin req=<n> surfaceId=<sid>` — ETS 进入嵌入分支。
6. `SurfaceIdToWindow: sid=<sid>` — C++ 绑定到**同一个** sid。
7. 点击嵌入区域，日志 `MouseEvent: req=<n> xy=(px,py)`，且 `px ≈ 点击处相对 XComponent 的 vp × density`。

---

## 附：涉及文件一览

| 层 | 文件 |
|---|---|
| 框架 | `framework/src/main/pascal/corelib/fpg_base.pas` |
| 框架 | `framework/src/main/pascal/corelib/ohos/fpg_ohos.pas` |
| 桥 | `lib_fp_bridge/fp_bridge/src/main/cpp/napi_init.cpp` |
| 桥 | `lib_fp_bridge/fp_bridge/src/main/cpp/fp_bridge.h` |
| ArkUI | `fpGUI_Demo/entry/src/main/ets/common/EmbeddedFormHost.ets` |
| ArkUI | `fpGUI_Demo/entry/src/main/ets/pages/Index.ets` |
| 声明 | `fpGUI_Demo/entry/src/main/cpp/types/libfp_bridge/Index.d.ts` |
| 应用 | `fpGUI-2.1.0/test/helloworld/helloworld.lpr` |
