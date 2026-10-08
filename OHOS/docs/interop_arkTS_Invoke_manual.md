# arkTS_Invoke 使用说明（Pascal → ArkTS 反向调用）

> 版本：v13（`OHOS_BRIDGE_VERSION = 13`，C++ 与 Pascal 两侧必须一致）
> 关联文档：《arkTS_Invoke实现文档.md》（设计与实现规范）
> 适用工程：`F:\Huawei\lazQtOHOS_Demo\lib_fp_bridge`（HAP/C++/ArkTS）+ `D:\fpGUI\fpGUI-2.1.0`（Pascal 框架）

---

## 1. 这是什么

`arkTS_Invoke` 让 **Pascal（fpGUI）代码调用 ArkTS（ArkUI）侧注册的方法**，并同步取回结果。方向与 `dispatch` 相反：

| 能力 | 方向 | 典型场景 | 单元/接口 |
|---|---|---|---|
| `dispatch` | ArkTS → Pascal | ArkTS 按钮触发 Pascal 业务 | `fpbridge.dispatch(op, params)` / `fpg_ohos_dispatch.pas` |
| **`arkTS_Invoke`** | **Pascal → ArkTS** | **Pascal 弹 Toast、调用系统 UI/存储能力** | `ArkTS_Invoke(...)` / `fpg_ohos_invoke.pas` |

Pascal 侧三个入口（`fpg_ohos_invoke.pas`）：

```pascal
function ArkTS_InvokeReady: Boolean;
{ 同步调用：登记 pending → 投递 → 等待结果。默认超时 5000ms。
  返回：ArkTS 方法的原始返回串；失败见 §5 错误信封。可从任意线程调用。 }
function ArkTS_Invoke(const Method, Params: string;
  TimeoutMs: Cardinal = 5000): string;

{ 即发即忘：不等待结果。返回 C++ 受理码 0/-1/-2/-3/-4（见 §5）。 }
function ArkTS_InvokeAsync(const Method, Params: string): Integer;
```

---

## 2. 原理

### 2.1 链路全景

```
Pascal 任意线程                         C++ (libfp_bridge.so)                      JS 线程 (ArkTS)
────────────────                       ─────────────────────                      ────────────────
ArkTS_Invoke(method,params)
  ① 生成 callId 'p_N'                  ohos_arkts_invoke(callId,method,params)
  ② 登记 pending 表 ──────────────────►  ③ 名字归一 + 存在性快查
  ④ 调用 C++ 槽位                       ④ 分路径：
       │                                ┌─ 本线程==JS线程 → 内联直执行（零排队）
       │                                └─ 其它线程 → TSFN(napi_tsfn_blocking) 投递
       │                                          │
  ⑤ WaitFor(TimeoutMs) ◄── SetEvent ── ArkInvokeCallJS(JS线程)
                                            ExecuteInvoke(查注册表/内置/dispatcher)
                                            方法执行 → 结果转换
                                            DeliverResult → g_pascal.arkts_invoke_result
                                                          → InvokeResultCallback
                                                            持锁摘 pending → 写结果 → SetEvent
```

### 2.2 五个核心机制

1. **v13 双向槽位**：`TOHOSBridgeCallbacks.arkts_invoke`（Pascal→C++ 调用入口）+ `TOHOSExportTable.arkts_invoke_result`（C++→Pascal 结果回传），均为结构体**尾追**字段，版本号两侧强制同步（不一致则整桥拒绝连接）。
2. **方法注册表**（C++ 全局，仅 JS 线程读写 → 天然无锁）：ArkTS 侧用 `registerInvoke*` 把函数以**小写 key** 存入 `std::map`，持有 `napi_ref` 强引用防 GC。`g_reg.names`（锁保护的集合）供任意线程做投递前存在性快查，避免无谓投递。
3. **单 TSFN**：`ArkInvokeInit` 在 JS 线程（NAPI `Init`）创建一次，资源名 `"arkTS_Invoke"`，`max_queue_size=0`（无上限）+ `napi_tsfn_blocking`（背压阻塞）→ **不丢、FIFO 保序**。投递数据 `InvokePayload` 是纯 STL 字符串，**不含任何 NAPI 句柄**（跨线程只传字符串）。
4. **内联快路径**（防死锁关键）：若调用方就在 JS 线程（`can_close` / `drag_process_drop` / `notifyFilePickerResult` 等 NAPI 同步回调上下文），走 TSFN 投递再等待 = 等自己 → 必然超时。C++ 用 `pthread_equal` 判定，命中则**同线程直接执行并立即回结果**，不投递、零等待。
5. **相关性 id 由 Pascal 先生成**：`ArkTS_Invoke` **先**登记 pending **再**调 C++，杜绝"结果先于登记被当迟到回传丢弃"的竞态（与 filepicker 模式逐字一致）。超时/出错由 `finally` 持锁摘除，之后迟到的回调查不到 pending 即安全丢弃（UAF 防护）。

### 2.3 执行顺序语义

内联路径在调用方线程同步执行，跨线程路径经 TSFN 排队执行；两条路径相对顺序不做强保证。**业务不得依赖"跨入口严格有序"**。

---

## 3. ArkTS 侧接口（`fpbridge.*`，7 个 NAPI）

```typescript
import fpbridge from 'libfp_bridge.so';
```

### 3.1 注册

| 函数 | 签名 | 功能 |
|---|---|---|
| `registerInvokeMethod` | `(name: string, fn: (params: string) => string) => void` | 注册单个方法，`name` 为点分路径（如 `'ui.showToast'`） |
| `registerInvokeNamespace` | `(prefix: string, obj: object \| Function) => void` | **推荐**：整体对象注册，沿**原型链**取自有属性（含非枚举的 class 方法），递归为 `prefix.key` / `prefix.sub.key`；传 function 时退化为单方法注册 |
| `registerInvokeDispatcher` | `(fn: (method: string, params: string) => string) => void` | 可选统一分发器：所有未命中的方法以 `(method, params)` 交它处理 |

### 3.2 管理与直查

| 函数 | 签名 | 功能 |
|---|---|---|
| `unregisterInvokeMethod` | `(name: string) => void` | 注销单个（释放 `napi_ref`） |
| `clearInvokeMethods` | `() => void` | 全清：方法表 + 分发器（页面销毁/热重启时调用） |
| `listInvokeMethods` | `() => string[]` | 已注册方法的**原始大小写**展示名列表 |
| `invokeLocal` | `(method: string, params: string) => string` | JS 线程直查注册表**同步执行**（跨进程 relay / 自测用；永不抛异常，失败返回错误信封） |

### 3.3 注册规则（`registerInvokeNamespace` 深入）

- **大小写归一**：注册与调用两侧都转小写比较（`UI.ShowToast` 能命中 `ui.showToast`）；
- **class 实例可用**：内部用 `napi_get_all_property_names(own_only, all_properties|skip_symbols)` 沿原型链逐层取自有属性——class 方法挂在原型上且**非枚举**，普通 `get_property_names` 拿不到；`Object.prototype` 不入链（`constructor`/`toString` 不外露）；
- **`this` 绑定**：函数自动 `bind` 到**注册时的根对象**（实例），不是原型；
- **覆盖语义**：同名后注册覆盖先注册（先释放旧 ref）；
- **深度 ≤ 8、方法总数 ≤ 512、名字 ≤ 128 字符**；`_` 前缀键跳过；`constructor` 跳过；
- **循环引用安全**（`a.self = a`）：深度上限截断，不会死循环；
- **getter 异常**：取值时 getter 抛错会被清掉并跳过该键，不污染后续 NAPI 调用。

### 3.4 注册时机与生命周期

在 `Fp_bridgeAbility.onCreate`（`start()` 之前）注册 Ability 级 service 对象：

```typescript
import { registerAllInvokeServices } from '../common/FpInvokeServices';

try {
  registerAllInvokeServices();
  hilog.info(DOMAIN, 'testTag', 'invoke services registered: %{public}s',
    JSON.stringify(fpbridge.listInvokeMethods()));
} catch (err) {
  hilog.error(DOMAIN, 'testTag', 'register invoke services failed: %{public}s', JSON.stringify(err));
}
```

> **`napi_ref` 强持有注册对象** —— 只注册 Ability 级 service，**不要**注册带页面引用（组件、页面 `this`）的对象；需释放时调 `fpbridge.clearInvokeMethods()`。

### 3.5 内置元方法（C++ 直接应答，免注册）

| 方法 | 返回 |
|---|---|
| `ArkTS_Invoke('__ping', '{}')` | `{"ok":true,"pong":true}` |
| `ArkTS_Invoke('__list', '{}')` | `{"ok":true,"methods":["ui.showToast", ...]}` |

---

## 4. Pascal 侧用法

### 4.1 前置条件

1. `uses` 中**`fpg_ohos` 必须在 `fpg_ohos_invoke` 之前**（单元 initialization 顺序依赖）：

```pascal
uses
  fpg_ohos, fpg_ohos_dispatch, fpg_ohos_invoke, ...;
```

2. 两侧 `OHOS_BRIDGE_VERSION = 13` 一致（否则 `fp_bridge_init` 返回 -1，整桥拒绝连接）；
3. ArkTS 侧已完成方法注册（未注册且无 dispatcher → 立即 `NO_METHOD`）。

### 4.2 同步调用 `ArkTS_Invoke`

```pascal
var
  R: string;
begin
  R := ArkTS_Invoke('ui.showToast', '{"msg":"hello from Pascal"}');
  // R = '{"ok":true,"msg":"hello from Pascal"}'
end;
```

- `Params` 传 `''` 或 `'{}'` 均可（空串按 `'{}'` 兜底送达）；
- **成功**：返回 ArkTS 方法原始返回串（推荐 JSON）；
- **失败**：返回桥接层错误信封（§5），**不抛异常**；
- 可从 fpGUI 任意线程调用；JS 线程重入场景由 C++ 内联快路径化解（立即返回）。

### 4.3 推荐封装：解析结果

```pascal
type
  TInvokeOutcome = record
    Ok: Boolean;
    Code: string;     // 成功时为空；失败为 BAD_ARGS/NO_METHOD/TIMEOUT/...
    Msg: string;      // 失败时的 error 文本
    Raw: string;      // 原始返回（排障用）
    Value: string;    // 业务 ok 时的载体（自行按 JSON 组织）
  end;

function InvokeOk(const Json: string): Boolean;
begin
  Result := (Pos('"ok":true', Json) > 0);   // 简易判定；严谨建议引入 JSON 库
end;

procedure ShowToast(const AMsg: string);
var
  R: string;
begin
  R := ArkTS_Invoke('ui.showToast', '{"msg":"' + AMsg + '"}', 2000);
  if not InvokeOk(R) then
    fpGUI_Hilog(LOG_WARN, 'invoke toast failed: ' + R);
end;
```

> **约定**（与 dispatch 一致）：**业务结果与业务失败都在原文里表达**（看 JSON 的 `ok` 字段）；只有桥接层故障才出现 `"ok":false` + `code`。

### 4.4 即发即忘 `ArkTS_InvokeAsync`

```pascal
case ArkTS_InvokeAsync('ui.showToast', '{"msg":"fire & forget"}') of
  0: ;                       // 已受理（结果无 pending 命中即丢弃）
  -2: fpGUI_Hilog(LOG_WARN, 'bridge not initialized');
  -3: fpGUI_Hilog(LOG_WARN, 'method not registered');
end;
```

用于通知型调用，不阻塞、不关心结果。

### 4.5 可用性检查 `ArkTS_InvokeReady`

```pascal
if not ArkTS_InvokeReady then
  fpGUI_Hilog(LOG_WARN, 'arkTS_Invoke slot not loaded (bridge v13?)');
```

槽位优先（v13 正式通路），未填时回退 dlsym `ohos_arkts_invoke`（覆盖开发期中间态）。

### 4.6 线程与超时建议

| 调用方 | 说明 | 建议 TimeoutMs |
|---|---|---|
| fpGUI 后台/异步 Worker | 经 TSFN 排队到 JS 线程执行 | 5000（默认） |
| fpGUI UI 线程轻量方法 | toast/save 等 | 1000~3000 |
| **JS 线程重入上下文**（`can_close`、`drag_process_drop` 等 NAPI 回调内调用） | **内联直执行，立即返回**，不排队不死锁 | 任意（形同虚设） |

---

## 5. 错误码与信封

### 5.1 C++ `ohos_arkts_invoke` 返回码（同步、立即）

| 码 | 含义 | Pascal 信封 code |
|---|---|---|
| 0 | 已受理（结果异步/内联回传） | — |
| -1 | 入参错误（callId/method 空、method >128 字符） | `BAD_ARGS` |
| -2 | 未初始化（`ArkInvokeInit` 未执行）；或非内联线程且 TSFN 不可用。**内联路径只依赖 `g_jsEnv`，不受 TSFN 影响** | `NOT_CONNECTED` |
| -3 | 方法未注册且无 dispatcher（**投递前即拒绝**） | `NO_METHOD` |
| -4 | TSFN 关闭中 / 投递失败 | `QUEUE_FULL` |

### 5.2 `ArkTS_Invoke` 返回信封

| code | 触发点 |
|---|---|
| `BAD_ARGS` | method 为空 / C++ 返回 -1 |
| `NOT_CONNECTED` | 桥未连接（槽位 nil）或 C++ 返回 -2 |
| `NO_METHOD` | 表中无此名且无 dispatcher（C++ 返回 -3） |
| `QUEUE_FULL` | C++ 返回 -4 |
| `TIMEOUT` | `WaitFor` 超时（默认 5000ms）；pending 已摘，迟到回传被丢弃 |
| `JS_EXCEPTION` | ArkTS 方法抛异常（`failed=1`，C++ 生成，异常已 `get_and_clear`，**不污染后续桥调用**） |
| `CALL_FAIL` | `napi_call_function` 非预期状态码 |

信封统一形态：

```json
{"ok":false,"code":"NO_METHOD","error":"no such method: no.such"}
```

### 5.3 ArkTS 方法返回值转换

| ArkTS 方法返回 | Pascal 收到 |
|---|---|
| `string`（含 JSON 文本） | 原样返回 |
| `object` / `array` / `number` / `boolean` | `JSON.stringify` 结果（失败则 `napi_coerce_to_string` 兜底） |
| `undefined` / `null`（无 return） | `{"ok":true}` |
| `throw new Error('boom')` | `{"ok":false,"code":"JS_EXCEPTION","error":"<message或stack>"}` |

---

## 6. 跨进程调用（StatusBarView 扩展进程）

扩展进程无 Pascal、无注册表，经 commonEvent 中继到主进程执行（`FpInvokeProxy.ets` + `FpDispatchRelay.ets`）：

```typescript
import { invokeViaMain } from '../common/FpInvokeProxy';

// 成功与错误信封统一 resolve；超时/发布失败才 reject
invokeViaMain('ui.showToast', '{"msg":"from extension"}')
  .then((r: string) => {
    const obj = JSON.parse(r) as Record<string, Object>;
    if (obj['ok'] === true) { /* 成功 */ }
  })
  .catch((e: Error) => hilog.warn(0x0000, 'App', 'invoke failed: %{public}s', e.message));
```

- 请求走既有 `DISPATCH_REQ`（`kind='invoke'`），回程走**专用** `INVOKE_RESP`；
- **与 `FpDispatchProxy` 结构性隔离**：两者互订不同事件，clientId/reqId 同值也互不可见（`FpDispatchProxy` 零改动）；
- 默认超时 8000ms（可传第三参），超时 reject、pending 清理；
- 主进程 relay 侧用 `fpbridge.invokeLocal` 直查注册表同步执行（不经 TSFN、不绕 Pascal、无排队）。

---

## 7. 完整使用例子

### 7.1 ArkTS：定义业务方法（`ets/common/FpInvokeServices.ets`）

```typescript
import fpbridge from 'libfp_bridge.so';
import { promptAction } from '@kit.ArkUI';

interface ToastParams {
  msg?: string;
}
interface ConfirmParams {
  title: string;
}

class DialogsService {
  confirm(params: string): string {
    const p = JSON.parse(params) as ConfirmParams;
    return JSON.stringify({ ok: true, title: p.title });
  }
}

class UiService {
  dialogs: DialogsService = new DialogsService();

  showToast(params: string): string {
    const p = JSON.parse(params) as ToastParams;
    promptAction.showToast({ message: p.msg ?? '', duration: 2000 });
    return JSON.stringify({ ok: true, msg: p.msg ?? '' });
  }
}

const kvStore: Map<string, string> = new Map<string, string>();

class StorageService {
  save(params: string): string {
    const p = JSON.parse(params) as { key: string, value?: string };
    if (p.key === undefined || p.key === '') {
      return '{"ok":false,"code":"BAD_ARGS","error":"key required"}';
    }
    kvStore.set(p.key, p.value ?? '');
    return JSON.stringify({ ok: true, key: p.key });
  }
}

export function registerAllInvokeServices(): void {
  fpbridge.registerInvokeNamespace('ui', new UiService());            // → ui.showToast / ui.dialogs.confirm
  fpbridge.registerInvokeNamespace('storage', new StorageService());  // → storage.save / storage.load
}
```

> ArkTS 规则：对象字面量必须对应显式声明的 class/interface（`arkts-no-untyped-obj-literals`），故业务对象一律用 **class** 表达；class 实例可被 `registerInvokeNamespace` 沿原型链注册。

### 7.2 ArkTS：注册与清理（`Fp_bridgeAbility.ets`）

```typescript
import { registerAllInvokeServices } from '../common/FpInvokeServices';

// onCreate（start() 之前）：
try {
  registerAllInvokeServices();
  hilog.info(DOMAIN, 'testTag', 'invoke services registered: %{public}s',
    JSON.stringify(fpbridge.listInvokeMethods()));
} catch (err) {
  hilog.error(DOMAIN, 'testTag', 'register invoke services failed: %{public}s', JSON.stringify(err));
}

// onDestroy（如需释放强引用）：
// fpbridge.clearInvokeMethods();
```

### 7.3 ArkTS：统一分发器（可选兜底）

```typescript
fpbridge.registerInvokeDispatcher((method: string, params: string): string => {
  if (method === 'sys.battery') {
    return JSON.stringify({ ok: true, level: 87 });
  }
  return JSON.stringify({ ok: false, code: 'NO_METHOD', error: 'unhandled: ' + method });
});
```

### 7.4 Pascal：按钮点击调 Toast

```pascal
procedure TMainForm.BtnShowClick(Sender: TObject);
var
  R: string;
begin
  R := ArkTS_Invoke('ui.showToast', '{"msg":"hello from fpGUI"}');
  fpGUI_Hilog(LOG_INFO, 'invoke result: ' + R);
end;
```

### 7.5 Pascal：带业务错误处理的完整调用

```pascal
function SaveSetting(const Key, Value: string): Boolean;
var
  R: string;
begin
  R := ArkTS_Invoke('storage.save',
    Format('{"key":"%s","value":"%s"}', [Key, Value]), 3000);
  { 统一判定：看 JSON 的 ok 字段（业务失败与桥接故障都是 ok:false + code，
    仅 code 取值不同：桥接层 BAD_ARGS/NOT_CONNECTED/NO_METHOD/QUEUE_FULL/
    TIMEOUT/JS_EXCEPTION/CALL_FAIL；其余 code 为业务自定义，如 NOT_FOUND） }
  Result := Pos('"ok":true', R) > 0;
  if not Result then
    fpGUI_Hilog(LOG_WARN, 'save failed: ' + R);   // 原文含 code，排障时据此分流
end;
```

### 7.6 Pascal：后台线程并发调用（100 次压测样例）

```pascal
procedure StressTest;
var
  i: Integer;
  R: string;
begin
  for i := 1 to 100 do
  begin
    R := ArkTS_Invoke('ui.showToast', Format('{"msg":"n=%d"}', [i]));
    // callId 'p_N' 一一对应，FIFO 保序，结果不错配
    if Pos('"ok":true', R) = 0 then
      fpGUI_Hilog(LOG_WARN, format('stress #%d failed: %s', [i, R]));
  end;
end;
```

### 7.7 Pascal：JS 线程重入上下文调用（内联快路径）

```pascal
{ 在 can_close / drag_process_drop 等 NAPI 同步回调里调用是安全的：
  C++ 判定命中 JS 线程 → 内联直执行 → 立即返回，不投递不排队不死锁。
  hilog 会显示 'arkTS_Invoke inline: method=... callId=...' }
function OhosCanCloseHandler: Integer;
var
  R: string;
begin
  R := ArkTS_Invoke('ui.dialogs.confirm', '{"title":"确定退出?"}');
  if Pos('"ok":true', R) > 0 then
    Result := 1
  else
    Result := 0;
end;
```

### 7.8 Pascal：即发即忘通知

```pascal
if ArkTS_InvokeAsync('ui.showToast', '{"msg":"后台任务完成"}') <> 0 then
  fpGUI_Hilog(LOG_WARN, 'async invoke rejected');
```

### 7.9 跨进程：扩展进程调用（`FpInvokeProxy.ets` 消费方）

```typescript
invokeViaMain('storage.load', '{"key":"theme"}', 8000)
  .then((r: string) => {
    const obj = JSON.parse(r) as Record<string, Object>;
    if (obj['ok'] === true) {
      const v = obj['value'] as string;
      // 使用结果
    }
  })
  .catch((e: Error) => {
    hilog.warn(0x0000, 'StatusBar', 'invokeViaMain: %{public}s', e.message);
  });
```

---

## 8. 要点（Key Points）

1. **同步契约**：ArkTS 可 invoke 方法必须**毫秒级同步完成**、同步返回 string；长任务（网络、选文件）返回 `{ok:true, jobId:...}` 信封，结果另走异步通道（如 `dispatch` 反向通知）。
2. **禁止在方法内 `await`**：契约是同步返回，`await fpbridge.dispatch(...)` 无法等完；dispatch 起步入队即返不阻塞 JS 线程，但方法本身不会等它的完成。
3. **注册时机**：Ability `onCreate`、`start()` 之前；注册晚于 Pascal 首次调用 → 首次 `NO_METHOD`，注册后恢复（无崩溃）。
4. **命名规范**：点分路径、大小写不敏感（两侧小写归一）、≤128 字符、`_` 前缀不外露。
5. **强引用生命周期**：`napi_ref` 持有注册对象 —— 只注册 Ability 级 service；页面级对象销毁前 `clearInvokeMethods()`。
6. **超时必须存在**：JS 线程长帧/同步 IO 会放大跨线程等待；`TIMEOUT` 后 pending 已摘，**迟到回传被安全丢弃、无 UAF**。
7. **异常隔离**：方法抛错 → `JS_EXCEPTION` 信封 + `failed=1`；C++ 必 `napi_get_and_clear_last_exception`，**后续其它桥调用（filepicker 等）不受污染**。
8. **内联快路径不依赖 TSFN**：即便 TSFN 创建失败，JS 线程重入调用照常工作；只有跨线程投递才要求 TSFN 可用。
9. **保序性**：`napi_tsfn_blocking` + FIFO → 跨线程调用按投递顺序执行（不同入口进入事件循环的相对顺序不保证）。
10. **版本红线**：C++ `fp_bridge.h` 与 Pascal `fpg_ohos.pas` 的 `OHOS_BRIDGE_VERSION` 必须同为 13；结构体字段**严格尾追**（两侧字段数、顺序一一对应）。
11. **排障关键字**（hilog 过滤 `fpGUI`）：
    - `arkTS_Invoke TSFN created: 0x...`（Init 成功）
    - `fp_bridge: connected OK (v13)`（Pascal 连接）
    - `invoke services registered: [...]`（Ability 注册）
    - `arkTS_Invoke queued: method=... callId=...`（跨线程投递）
    - `arkTS_Invoke inline: method=... callId=...`（JS 线程内联）

---

## 9. 限制（Limitations）

1. **仅同步返回**：ArkTS 方法返回 `Promise` 会被 `JSON.stringify` 成 `{}`（或 stringify 得 `undefined` → 兜底 `{"ok":true}`）——**语义错误**，属 review 检查项；异步结果需另行设计（本期不做）。
2. **`ArkTS_InvokeAsync` 结果无人认领**：设计如此（不登记 pending），迟到结果直接丢弃。
3. **无独立超时 janitor**：`ArkTS_Invoke` 超时由 `WaitFor` 自身兜底；无守护线程回收。
4. **注册表无持久化**：进程重启需重新注册（Ability onCreate 保证）。
5. **仅主进程有注册表**：其它进程（如 StatusBarView 扩展进程）必须走 `invokeViaMain` relay。
6. **容量上限**：方法总数 ≤ 512、命名空间递归深度 ≤ 8、名字 ≤ 128 字符；`max_queue_size=0` 无上限 → JS 线程长期占死时投递方会被 `napi_tsfn_blocking` 挂住（受 `TimeoutMs` 约束的是 Pascal 等待方，投递本身也可能阻塞）。
7. **交叉等待残余风险**：Pascal UI 线程同步 invoke（等 JS 线程）× JS 线程某 NAPI 回调内部又同步等待 Pascal UI 线程 → 互等靠 `TimeoutMs` 解除，最长一个超时周期卡顿。**避免在 JS 线程回调里做同步等待 Pascal UI 线程的操作**。
8. **dlsym 兜底不跨版本**：版本严格相等检查失败即整体拒绝连接；兜底只覆盖"版本一致但槽位未填"的中间态。
9. **d.ts 契约提醒**：`registerInvokeMethod` 的 `fn` 需要 `this` 时先 `.bind(obj)`（`registerInvokeNamespace` 已自动 bind，无需手动）。

---

## 10. 验证与测试对照

设计文档 §12 含 22 条测试用例（基本调用/命名空间/大小写/NO_METHOD/异常/超时/跨线程/内联重入/内置方法/GC/class 实例/原型链覆盖/跨进程隔离等）。本机已通过构建验证：

| 步骤 | 命令 | 状态 |
|---|---|---|
| 版本同步 | 两处 grep `OHOS_BRIDGE_VERSION` 均为 13 | ✅ |
| C++/ArkTS | `hvigorw --mode project assembleApp`（需 `DEVECO_SDK_HOME`、node、jbr\bin 在 PATH；改环境后先 `--stop-daemon`） | ✅ BUILD SUCCESSFUL |
| Pascal | `D:\fpGUI\fpGUI-2.1.0\test\helloworld\build.bat -B`（框架单元变更必须 `-B` 全量重编） | ✅ 测试通过 |
| 真机联调 | `hdc` 安装 HAP → hilog 过滤 `fpGUI`，核对 §8 第 11 条关键字 | ✅ 测试通过 |
