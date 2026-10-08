# fpGUI OHOS 系统拖拽（Unified Drag & Drop）使用手册

> 目标：在 fpGUI(OHOS) 中使用 HarmonyOS **统一拖拽（Unified Drag & Drop）**，
> 支持应用内拖拽、跨应用拖入/拖出，数据类型覆盖 文本 / HTML / 图片 / 文件(URI)。
>
> 参考实现：
> - 框架：`fpGUI-2.1.0/framework/src/main/pascal/corelib/ohos/fpg_ohos.pas`
> - 示例：`fpGUI-2.1.0/examples/gui/drag_n_drop/helloworld.lpr`
> - 桥：`lib_fp_bridge/fp_bridge/src/main/cpp/napi_init.cpp`
> - ArkUI：`fpGUI_Demo/entry/src/main/ets/pages/Index.ets`、`common/FpgSurface.ets`

---

## 目录

1. [概述](#1-概述)
2. [架构总览](#2-架构总览)
3. [核心原理](#3-核心原理)
4. [完整时序](#4-完整时序)
5. [应用开发指南（Pascal）](#5-应用开发指南pascal)
6. [示例代码](#6-示例代码)
7. [跨层桥接契约](#7-跨层桥接契约)
8. [常见问题与坑](#8-常见问题与坑)
9. [验证检查点](#9-验证检查点)

---

## 1. 概述

fpGUI 的 DND 抽象与桌面版（X11/GDI）一致，**应用层 API 完全相同**：

| 角色 | 应用侧入口 | 说明 |
|---|---|---|
| **拖拽源**（Source） | `TfpgWidget.OnDragStartDetected` → `TfpgDrag.Execute` | 用户拖拽起点，提供 `TfpgMimeData` |
| **拖入目标**（Target） | `TfpgWidget.DropHandler := TfpgDropEventHandler.Create(...)` | 接收 `Enter/Move/Leave/Drop` 回调 |

OHOS 后端把两者分别桥接到 ArkUI 的：

- 起拖：`UIContext.getDragController().executeDrag(...)`
- 拖入：`XComponent.allowDrop([...])` + `.onDragEnter / onDragMove / onDragLeave / onDrop`

**支持的动作**：`daCopy / daMove / daLink / daAsk`（`daMove` 在 OHOS 上精确支持）。

---

## 2. 架构总览

```
┌─────────────────────────────── 主进程 ───────────────────────────────┐
│  Pascal 应用 (libhelloworld.so)                                       │
│    ├─ 源:  OnDragStartDetected → TfpgDrag.Execute                     │
│    └─ 目标: DropHandler.Enter/Move/Leave/Drop                         │
│                              │  ▲                                     │
│                    (cpp_api) │  │ (pascalApi)                          │
│                              ▼  │                                     │
│  fpg_ohos.pas（框架 OHOS 后端）                                        │
│    ├─ TfpgOhosDrag.Execute  （模态泵循环）                             │
│    ├─ TfpgOhosDrop          （拖入会话 + 应答）                         │
│    └─ ohos_inject_drag_event / ohos_drag_process_drop / inject_drag_end│
│                              │  ▲                                     │
│                              ▼  │                                     │
│  libfp_bridge.so (C++)                                                │
│    ├─ ohos_drag_start / ohos_set_dnd_enabled                          │
│    ├─ OnDragEvent / OnDropEvent / OnDragEnd / IsDndEnabled            │
│    └─ 命令通道 TSFN → ETS                                             │
│                              │  ▲                                     │
│                              ▼  │                                     │
│  ArkUI (entry)                                                        │
│    ├─ Index.startSystemDrag → dragController.executeDrag              │
│    └─ FpgSurface: allowDrop + onDragEnter/Move/Leave/Drop             │
└───────────────────────────────────────────────────────────────────────┘
```

**关键点**：全部在**同一进程**内，不存在跨进程 surface/IPC 问题。

---

## 3. 核心原理

### 3.1 拖拽源（Drag Source）

应用只负责构造数据并调用 `Execute`：

```pascal
procedure TForm.LabelDragStartDetected(Sender: TObject);
var
  m: TfpgMimeData;
  d: TfpgDrag;
begin
  m := TfpgMimeData.Create;
  m.Text := 'My name is Earl';
  m.HTML := 'My name is <b>Earl</b>';

  d := TfpgDrag.Create(Sender as TfpgWidgetBase);
  d.MimeData := m;               // TfpgDrag 接管 m 的所有权
  d.Execute([daCopy]);           // 阻塞直到拖拽结束，返回最终动作
end;
```

框架侧 `TfpgOhosDrag.Execute`（`fpg_ohos.pas`）：

1. 重入保护（`FDragging`）。
2. **隐藏 fpGUI 自身预览窗**：`TfpgDrag.Execute` 会先 Show 一个 40% 透明 popup，
   与系统跟手预览"双图"冲突 → 置 `Visible := False`（经 `TDragHack` 访问 protected `FPreviewWin`）。
3. 序列化：`OhosMimeDataToJson(FMimeData)` → `dataJson`；动作集 → `extraJson`。
4. 建立会话（`gDragSession`：Active/SessionId/EndEvent/DragRef…）。
5. `_ohos_drag_start(dataJson, extraJson)` → C++ → ETS `executeDrag`（异步），**同步返回 sessionId**。
6. **模态泵循环**（X11 同式）：

```pascal
while gDragSession.Active and (SessionId <> 0) do
begin
  if EndEvent.WaitFor(50) = wrSignaled then Break;
  app.PumpEvents(50);      // 期间正常处理 enter/move/leave/drop
end;
```

7. 结束：ETS `executeDrag` 回调 → `fpbridge.onDragEnd` → `ohos_inject_drag_end`
   → 置 `Result` + `EndEvent.SetEvent`。
8. 映射：`SUCCESS → DropAction`；否则 `daIgnore`。

> ⚠️ **取消/失败路径也必须回调 `onDragEnd`**，否则 `Execute` 会一直阻塞在泵循环。

### 3.2 拖入目标（Drop Target）

应用注册 `DropHandler`：

```pascal
Edit1.DropHandler := TfpgDropEventHandler.Create(
  @Edit1DragEnter, nil, @Edit1DragDrop, nil);   // (OnEnter, OnLeave, OnDrop, OnMove)
```

框架侧（`fpg_ohos.pas`）：

- **开关**：挂 `DropHandler`（或 `AddDropableWidget`）触发
  `TfpgOhosWindow.DoDNDEnabled(True)` → `_ohos_set_dnd_enabled` →
  C++ `g_dndEnabled[reqId]=true`，ETS 侧 `allowDrop` 生效。
- **进入/移动/离开**：
  ETS `onDragEnter/onDragMove/onDragLeave` →
  `fpbridge.onDragEvent(reqId, kind, x, y, summaryJson)` →
  C++ `OnDragEvent`（先查 `g_dndEnabled`，禁用则丢弃）→
  `ohos_inject_drag_event` → `EnqueueDragEvent` →
  `TfpgOhosApplication.ProcessDragEvents` → `TfpgOhosDrop.HandlePosition`
  → 核心引擎 `SetPosition` 路由 `Enter/Leave/Move`（触发 `DropHandler`）。
- **落下**：
  ETS `onDrop` → `fpbridge.onDropEvent(reqId, x, y, recordsJson)` →
  C++ `OnDropEvent` → `ohos_drag_process_drop`（**同步阻塞 ≤2.5s**）→
  win-cmd 队列 `case 4` → `HandleDrop` → `DataDropComplete` →
  返回 `(accept<<8) | Ord(DropAction)`。

拖入会话生命周期（`TfpgOhosDrop`）：

| 阶段 | 动作 |
|---|---|
| enter | `EnsureDropSession` 创建 `TfpgOhosDrop`；装载 `Mimetypes`（summary / 源 / records 兜底） |
| move | `HandlePosition` → 按 `Mimetypes` 路由 `Enter/Leave/Move` |
| leave | `HandleLeave` → `TargetWidget := nil`（触发旧控件 `Leave`） |
| drop | `HandleDrop`（重路由 + `DataDropComplete`）→ 回填 `DropAccept/DropAction` |

### 3.3 数据表示

| 名称 | 产生方 | 结构 |
|---|---|---|
| `TfpgMimeData` | 应用 | `Text` / `HTML` / `urls` / `Formats`（mime 字符串列表） |
| `dataJson` | Pascal | `{"text":"…","html":"…","uris":[…],"types":[…]}` |
| `summaryJson` | ETS | `{"types":[{"utd":"general.plain-text","mime":"text/plain"}, …]}` |
| `recordsJson` | ETS | UnifiedData records：`{"type":"…","textContent":"…","htmlContent":"…","uri":"…"}` |

**内部拖拽**（同应用）优先从源 `MimeData` 读数据（精确）；
**跨应用**拖入由 `recordsJson` 推导（`SetDropDataFromRecords` + `LoadMimeTypesFromRecords`）。

### 3.4 坐标换算

```
ArkUI DragEvent.getX()/getY()   组件相对（含标题栏）vp
  − decW / decTop               → 客户区 vp        (FpgSurface.dragCoords)
  × g_density                   → 客户区 px         (C++ OnDragEvent/OnDropEvent)
  ÷ gScaleFactorX/Y             → 客户区逻辑坐标     (Pascal ProcessDragEvents)
```

### 3.5 应答协议

`OnDropEvent` 返回值：

```
bit 8+ : accept (1=接受, 0=拒绝)
bit 0-7: TfpgDropAction (0=daIgnore,1=daCopy,2=daMove,3=daLink,4=daAsk)
```

ETS 据此 `ev.setResult(accept ? DRAG_SUCCESSFUL : DRAG_FAILED)`。

---

## 4. 完整时序

### 4.1 起拖（Pascal → 系统）

```
应用  OnDragStartDetected
  └─ TfpgDrag.Create + MimeData + Execute([daCopy])
       └─ TfpgOhosDrag.Execute
            ├─ 隐藏 FPreviewWin
            ├─ OhosMimeDataToJson
            ├─ _ohos_drag_start ─▶ C++ ohos_drag_start
            │                       └─ NATIVE_CMD_DRAG_START(13) ─▶ ETS
            │                            └─ dragController.executeDrag
            │                                 ├─ 跟手预览 DragPreviewBuilder
            │                                 └─ 回调 → fpbridge.onDragEnd
            │                                      └─ C++ OnDragEnd
            │                                           └─ ohos_inject_drag_end
            │                                                └─ EndEvent.SetEvent
            └─ while Active: PumpEvents(50)
       ◀─ Result = SUCCESS ? DropAction : daIgnore
```

### 4.2 拖入（系统 → Pascal）

```
指针进入 XComponent
  └─ ArkUI onDragEnter/Move
       └─ fpbridge.onDragEvent(reqId, kind, x, y, summary)
            └─ C++ OnDragEvent（g_dndEnabled 检查；×g_density）
                 └─ ohos_inject_drag_event → EnqueueDragEvent
                      └─ ProcessDragEvents（÷gScaleFactor）
                           ├─ EnsureDropSession（新建 TfpgOhosDrop + Mimetypes）
                           └─ HandlePosition → 核心引擎 → DropHandler.Enter/Move

指针离开
  └─ onDragLeave → onDragEvent(kind=2) → HandleLeave → DropHandler.Leave

落下
  └─ ArkUI onDrop
       └─ fpbridge.onDropEvent(reqId, x, y, recordsJson)
            └─ C++ OnDropEvent → ohos_drag_process_drop（阻塞等待应答）
                 └─ win-cmd case 4 → HandleDrop → DataDropComplete
                      └─ DropHandler.Drop(AData)   ← 应用写入数据
                 ◀─ (accept<<8)|action
            ◀─ ev.setResult(DRAG_SUCCESSFUL / DRAG_FAILED)
```

---

## 5. 应用开发指南（Pascal）

### 5.1 作为拖入目标

**1) 创建回调**（签名固定）：

```pascal
procedure TForm.MyDragEnter(Sender: TfpgDrop);
begin
  ShowMimeList(Sender.Mimetypes);                            // 可用类型
  Sender.CanDrop := Sender.AcceptMimeType(['text/plain']);   // 接受判定
end;

procedure TForm.MyDragLeave(Sender: TfpgDrop);
begin
  // 还原高亮
end;

procedure TForm.MyDragDrop(Sender: TfpgDrop; AData: Variant);
begin
  MyEdit.Text := AData;                                      // 落下的数据
end;

procedure TForm.MyDragMove(Sender: TfpgDrop; X, Y: TfpgCoord);
begin
  // 可选：跟随位置提示
end;
```

**2) 挂到控件**：

```pascal
MyEdit.DropHandler := TfpgDropEventHandler.Create(
  @MyDragEnter, @MyDragLeave, @MyDragDrop, @MyDragMove);
// 传 nil 表示不关心该回调
```

> 挂上 `DropHandler` 后，OHOS 后端会自动打开该窗口的拖入开关（`set_dnd_enabled`）。

### 5.2 作为拖拽源

```pascal
procedure TForm.SourceDragStartDetected(Sender: TObject);
var
  m: TfpgMimeData;
  d: TfpgDrag;
begin
  m := TfpgMimeData.Create;
  m.Text := 'Hello DnD';
  m.HTML := '<b>Hello DnD</b>';

  d := TfpgDrag.Create(Sender as TfpgWidgetBase);
  d.MimeData := m;                 // 所有权转移
  d.Execute([daCopy, daMove], daCopy);
end;

// 控件关联：
MyLabel.OnDragStartDetected := @SourceDragStartDetected;
```

### 5.3 关键 API 速查

| API | 位置 | 说明 |
|---|---|---|
| `TfpgMimeData.Text / HTML / urls / Formats / SetData / HasFormat / GetData` | `fpg_main.pas` | 数据容器 |
| `TfpgDrag.Create(Source)` / `.MimeData` / `.Execute(actions, default)` | `fpg_main.pas` | 起拖 |
| `TfpgDrop.Mimetypes` | `fpg_main.pas` | 源支持的 mime 列表 |
| `TfpgDrop.AcceptMimeType([...])` | `fpg_main.pas` | 按兼容 mime 判定接受 |
| `TfpgDrop.CanDrop` | `fpg_main.pas` | 置 `True/False` 决定接受 |
| `TfpgDrop.MimeChoice` | `fpg_base.pas` | 选中要取数据的 mime |
| `TfpgDrop.MousePos` | `fpg_base.pas` | 落下坐标（客户区逻辑坐标） |
| `TfpgDrop.DropAction` | `fpg_base.pas` | 协商动作（daCopy/daMove…） |
| `TfpgDropHandler` (Enter/Leave/Move/Drop) | `fpg_main.pas` | 抽象基类，可自定义子类 |
| `TfpgDropEventHandler.Create(OnEnter,OnLeave,OnDrop,OnMove)` | `fpg_main.pas` | 事件式实现 |

---

## 6. 示例代码

### 6.1 拖入目标（Edit 接受 text/plain）

```pascal
type
  TMainForm = class(TfpgForm)
  private
    Edit1: TfpgEdit;
    procedure Edit1DragEnter(Sender: TfpgDrop);
    procedure Edit1DragDrop(Sender: TfpgDrop; AData: variant);
  public
    procedure AfterCreate; override;
  end;

procedure TMainForm.Edit1DragEnter(Sender: TfpgDrop);
begin
  Sender.CanDrop := Sender.AcceptMimeType(['text/plain']);
end;

procedure TMainForm.Edit1DragDrop(Sender: TfpgDrop; AData: variant);
begin
  Edit1.Text := AData;
end;

procedure TMainForm.AfterCreate;
begin
  inherited AfterCreate;
  Edit1 := TfpgEdit.Create(self);
  Edit1.SetPosition(8, 156, 240, 24);
  Edit1.DropHandler := TfpgDropEventHandler.Create(
    @Edit1DragEnter, nil, @Edit1DragDrop, nil);
end;
```

### 6.2 拖拽源（Label "Drag Me!"）

```pascal
procedure TMainForm.LabelDragStartDetected(Sender: TObject);
var
  m: TfpgMimeData;
  d: TfpgDrag;
begin
  m := TfpgMimeData.Create;
  m.Text := 'My name is Earl';
  m.HTML := 'My name is <b>Earl</b>';

  d := TfpgDrag.Create(Sender as TfpgWidgetBase);
  d.MimeData := m;
  d.Execute([daCopy]);
end;

// AfterCreate 中：
MyDragSourceLabel.OnDragStartDetected := @LabelDragStartDetected;
```

### 6.3 高亮反馈（Enter 变红 / Leave 还原）

```pascal
procedure TMainForm.PanelDragEnter(Sender: TfpgDrop);
begin
  Sender.CanDrop := Sender.AcceptMimeType(['text/html']);
  if Sender.CanDrop then
    Bevel1.BackgroundColor := clRed;
end;

procedure TMainForm.PanelDragLeave(Sender: TfpgDrop);
begin
  Bevel1.BackgroundColor := clWindowBackground;
end;

procedure TMainForm.PanelDragDrop(Sender: TfpgDrop; AData: variant);
begin
  Bevel1.Text := Format('Drop at (%d,%d): %s',
    [Sender.MousePos.X, Sender.MousePos.Y, string(AData)]);
  PanelDragLeave(nil);
end;
```

### 6.4 ArkUI 侧接入（集成 / 移植用）

**起拖（`Index.ets`）**

```typescript
private async startSystemDrag(sessionId: number, dataJson: string, extraJson: string): Promise<void> {
  try {
    const data = JSON.parse(dataJson) as DragPayload;
    const unified = new unifiedDataChannel.UnifiedData();
    if (data.text) {
      const rec = new unifiedDataChannel.PlainText();
      rec.textContent = data.text;
      rec.abstract = data.text.slice(0, 32);
      unified.addRecord(rec);
    }
    if (data.html) {
      const rec = new unifiedDataChannel.HTML();
      rec.htmlContent = data.html;
      unified.addRecord(rec);
    }
    if (data.uris) {
      for (const u of data.uris) {
        const rec = new unifiedDataChannel.File();
        rec.uri = u;
        unified.addRecord(rec);
      }
    }
    const extra: DragExtraParams = {
      session: sessionId, actions: data.actions ?? 1, default: data.default ?? 1
    };
    const info: dragController.DragInfo = {
      pointerId: 0, data: unified, extraParams: JSON.stringify(extra)
    };
    this.getUIContext().getDragController().executeDrag(() => {
      this.DragPreviewBuilder();
    }, info, (err, res) => {
      let result = DragResult.DRAG_CANCELED;
      if (!err && res?.event) result = res.event.getResult();
      fpbridge.onDragEnd(sessionId, this.dragResultToCode(result));
    });
  } catch (e) {
    fpbridge.onDragEnd(sessionId, 2);   // CANCELED：保证 Pascal Execute 不卡死
  }
}
```

**拖入（`FpgSurface.ets`，挂在 XComponent 上）**

```typescript
.allowDrop([
  uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
  uniformTypeDescriptor.UniformDataType.HTML,
  uniformTypeDescriptor.UniformDataType.FILE,
  uniformTypeDescriptor.UniformDataType.IMAGE
])
.onDragEnter((ev: DragEvent) => { this.forwardDrag(ev, 0); })
.onDragMove((ev: DragEvent) => {
  ev.setResult(DragResult.DROP_ENABLED);     // 乐观置位；精确判定在 onDrop
  this.forwardDrag(ev, 1);
})
.onDragLeave(() => {
  if (!this.dragEnabled()) return;
  fpbridge.onDragEvent(String(this.reqId), 2, 0, 0, '');
})
.onDrop((ev: DragEvent) => {
  if (!this.dragEnabled()) { ev.setResult(DragResult.DRAG_FAILED); return; }
  const records = ev.getData().getRecords();
  const pt = this.dragCoords(ev);
  const recs = this.serializeRecords(records);
  const ret = fpbridge.onDropEvent(String(this.reqId), pt.x, pt.y, recs) as number;
  const accept = (ret >> 8) & 0xFF;
  ev.setResult(accept === 1 ? DragResult.DRAG_SUCCESSFUL : DragResult.DRAG_FAILED);
})
```

**坐标补偿（客户区 vp）**

```typescript
private dragCoords(ev: DragEvent): DragPoint {
  const decH = this.compensateTop();                         // 标题栏 vp
  const decW = AppStorage.get<number>('decW_' + this.reqId) ?? 0;
  const decTop = decH - decW;
  return { x: ev.getX() - decW, y: ev.getY() - decTop };
}
```

---

## 7. 跨层桥接契约

| 方向 | 名称 | 签名 | 作用 |
|---|---|---|---|
| Pascal→C++ | `drag_start` | `function(dataJson, extraJson: PChar): Int64 cdecl` | 起拖，同步返回 sessionId |
| Pascal→C++ | `set_dnd_enabled` | `procedure(handle: Pointer; enabled: Integer) cdecl` | 窗口拖入开关 |
| C++→Pascal | `inject_drag_event` | `function(win, kind, x, y: Single, summary: PChar): Integer cdecl` | enter(0)/move(1)/leave(2) |
| C++→Pascal | `drag_process_drop` | `function(win, x, y: Single, records: PChar): Integer cdecl` | drop 同步应答 |
| C++→Pascal | `inject_drag_end` | `function(sessionId: Int64; result: Integer): Integer cdecl` | 会话结束（置 EndEvent） |

**NAPI（ETS ↔ C++）**

| 函数 | 签名 |
|---|---|
| `onDragEvent` | `(reqId: string, kind: number, x: number, y: number, summaryJson: string)` |
| `onDropEvent` | `(reqId: string, x: number, y: number, recordsJson: string) => number` |
| `onDragEnd` | `(sessionId: number, result: number)` |
| `isDndEnabled` | `(reqId: number) => boolean` |

**C++ 命令类型**：`NATIVE_CMD_DRAG_START = 13`、`NATIVE_CMD_SET_DND_ENABLED = 14`。

**结果码**：`OHOS_DRAG_RESULT_FAILED=0 / SUCCESS=1 / CANCELED=2`
（ETS `DragResult` → `dragResultToCode`：SUCCESSFUL→1，FAILED→0，其余→2）。

**应答位打包**：`OHOS_DROP_ACCEPT_SHIFT = 8`，`ret = (accept << 8) | action`。

**mime ↔ UTD 映射**（`LoadMimeTypesFromRecords`）：

| UTD 前缀 | fpGUI mime |
|---|---|
| `general.plain-text` / `general.text` / `general.hyperlink` | `text/plain` |
| `general.html` | `text/html` |
| `general.file` / `general.image` / `general.video` / `general.audio` / `general.folder` | `text/uri-list` |

---

## 8. 常见问题与坑

| 现象 | 根因 | 解决 |
|---|---|---|
| **拖入无反应（onDragEnter 不触发）** | 窗口未开拖入开关（`g_dndEnabled[reqId]=false`）；或 XComponent 未 `allowDrop` | 目标控件挂 `DropHandler`；XComponent 配 `allowDrop([...])` |
| **落下偶发被拒 / `drop-DROPPED`** | move 阶段 `Mimetypes` 空（summary 的 key 是数字索引无法映射），控件已 Reject，drop 时不再重入 Enter | 框架 `HandleDrop` 强制清空目标重路由；内部拖拽 enter 阶段 `LoadMimeTypesFromSource` 补齐 |
| **外部文本拖入 mimes 空被拒** | UTD 带数字后缀（如 `general.plain-text-65`）；`general.plain-text` 不以 `general.text` 开头 | 前缀匹配并单列 `general.plain-text` |
| **`Execute` 卡住 60s** | 取消/失败路径未回调 `onDragEnd` | ETS `startSystemDrag` catch 分支必须 `fpbridge.onDragEnd(sessionId, 2)` |
| **跟手预览"双图"** | fpGUI `FPreviewWin` 与系统预览重叠 | 框架在 `Execute` 中隐藏 `FPreviewWin` |
| **长按自动起拖 + 程序化起拖 双触发** | XComponent 设了 `.draggable(true)` | **不要**设 `.draggable(true)` |
| **drop 坐标偏移** | 未扣除标题栏/左边框 | `dragCoords`：`getX()-decW`、`getY()-(decH-decW)`；C++ ×density、Pascal ÷gScaleFactor |
| **`onDropEvent` 超时返回拒绝** | Pascal loop 线程忙 / 队列积压 | 应答上限 2.5s；确认主循环未长时间阻塞 |
| **`drag_process_drop` 悬空** | 超时后 loop 线程又 `SetEvent` | 超时 `ev` **不 Free**（与 `can_close` 同式） |
| **跨应用拿不到数据** | 未从 `recordsJson` 填充 | `HandleDrop` 中 `SetDropDataFromRecords(records)` |
| **`g_dndEnabled` 未上报** | `DoDNDEnabled` 在句柄创建前调用 | 框架已暂存 `FDNDEnabledQueued`，句柄创建后补发 |
| **`set_dnd_enabled: no reqId for handle`** | 调用时窗口句柄尚未注册 | 同上；或在 `DoAllocateWindowHandle` 末尾补发 |

---

## 9. 验证检查点

**起拖**

```
ohos_drag_start: session=<id>
OnDragEnd: session=<id> result=<0|1|2>
```

**拖入**

```
drag-session created h=<handle> class=<TfpgXXX> mimes=<n> summary=...
drag-evt kind=0 h=<handle> client=(<lx>,<ly>) mimes=<n>     ← enter
drag-evt kind=1 ...                                          ← move
drag-evt kind=2 h=<handle>                                   ← leave
```

**落下**

```
OnDragEvent: req=<n> kind=<0|1> vp=(<x>,<y>) summary=...    （仅 enter/leave 打印）
DRAG drop req=<n> pt=(<x>,<y>) records=...
drop-done h=<handle> client=(<lx>,<ly>) mimes=[...] accept=<0|1> action=<n>
OnDropEvent: result=<(accept<<8)|action>
DRAG drop req=<n> reply=<ret> accept=<0|1>
```

**判定要点**

- `mimes=[...]` 非空且与 `AcceptMimeType` 匹配 → `accept=1`。
- `client=(lx,ly)` 应落在目标控件范围内（客户区逻辑坐标）。

---

## 附：涉及文件一览

| 层 | 文件 |
|---|---|
| 框架 | `framework/src/main/pascal/corelib/fpg_base.pas`（`TfpgDropBase`/`TfpgDragBase`/`TfpgMimeDataBase`） |
| 框架 | `framework/src/main/pascal/corelib/fpg_main.pas`（`TfpgDrag`/`TfpgDrop`/`TfpgDropHandler`/`TfpgDropEventHandler`） |
| 框架 | `framework/src/main/pascal/corelib/ohos/fpg_ohos.pas`（`TfpgOhosDrag`/`TfpgOhosDrop`/注入/泵循环） |
| 桥 | `lib_fp_bridge/fp_bridge/src/main/cpp/napi_init.cpp`（`ohos_drag_start`/`OnDragEvent`/`OnDropEvent`/`OnDragEnd`/`IsDndEnabled`） |
| 桥 | `lib_fp_bridge/fp_bridge/src/main/cpp/fp_bridge.h`（`drag_start`/`set_dnd_enabled`/`inject_drag_*`） |
| ArkUI | `fpGUI_Demo/entry/src/main/ets/pages/Index.ets`（`startSystemDrag`/cmd case 13/14） |
| ArkUI | `fpGUI_Demo/entry/src/main/ets/common/FpgSurface.ets`（`allowDrop`/`onDrag*`/`onDrop`/`dragCoords`） |
| 声明 | `fpGUI_Demo/entry/src/main/cpp/types/libfp_bridge/Index.d.ts`（`onDragEvent`/`onDropEvent`/`onDragEnd`/`isDndEnabled`） |
| 示例 | `fpGUI-2.1.0/examples/gui/drag_n_drop/helloworld.lpr` |


