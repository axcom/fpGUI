# fpGUI Dispatch 动态分发 · 使用手册

> 版本：OHOS_BRIDGE_VERSION = 7 ｜ 适用：fpGUI(OHOS) + libfp_bridge.so + ArkTS
> 关联文档：`fp_bridge_dispatch_plan.md`（实现计划/记录）、`fp_bridge_integration.md`（桥接集成）

---

## 目录

1. [概述与适用场景](#1-概述与适用场景)
2. [实现原理](#2-实现原理)
3. [快速开始](#3-快速开始)
4. [Pascal API 参考](#4-pascal-api-参考)
5. [ArkTS API 参考](#5-arkts-api-参考)
6. [结果信封与错误码](#6-结果信封与错误码)
7. [使用技巧与模式](#7-使用技巧与模式)
8. [跨进程使用（StatusBarView）](#8-跨进程使用statusbarview)
9. [注意事项与限制](#9-注意事项与限制)
10. [故障排查](#10-故障排查)
11. [完整示例](#11-完整示例)
12. [构建与版本](#12-构建与版本)

---

## 1. 概述与适用场景

**Dispatch** 是 fpGUI 为 ArkTS 提供的一个**统一动态调用入口**：ArkTS 只调用
`fpbridge.dispatch(opType, paramsJson)`，Pascal 侧用 `RegisterSync/RegisterAsync`
把自己的处理函数注册到某个 `opType` 上，框架负责路由、线程编组、异常隔离与结果回传。

```
ArkTS  ──dispatch(op, params)──►  框架层（路由/编组/异常/异步）  ──►  业务 Handler
       ◄──────────── JSON 结果 ────────────────────────────────────────
```

**适合**：
- 用 HAP/ArkTS 触发 fpGUI 原生界面操作（读写控件、显示窗口、更新标题等）。
- 不想为每个功能都加一对 NAPI 导出函数，而是走一个通用通道 + 动态注册。
- 需要“同步立即返回”或“异步后台执行、完成再回传”两种语义。
- 跨进程（如状态栏扩展进程）需要调用主进程里运行的 Pascal 应用。

**不适合**：
- 高频、大吞吐的数据流（跨进程走 commonEvent；单进程也有队列开销）。
- 需要双向流式/长连接的场景。

---

## 2. 实现原理

### 2.1 分层架构

```
┌─ ArkTS ────────────────────────────────────────────────────────────┐
│  同进程：fpbridge.dispatch(op, json)                                │
│  扩展进程：FpDispatchProxy.dispatchViaMain(op, json)                │
└───────────────┬───────────────────────────────┬────────────────────┘
                │ NAPI（ArkTS 线程）             │ commonEvent（跨进程）
┌───────────────▼───────────────┐   ┌────────────▼────────────────────┐
│ libfp_bridge.so  Dispatch NAPI│   │ 主进程 FpDispatchRelay           │
│  • 参数校验                    │   │  • 订阅 DISPATCH_REQ             │
│  • 建 Promise + pending 表     │   │  • 调本进程 fpbridge.dispatch     │
│  • 持久 TSFN 回传              │   │  • 发回 DISPATCH_RESP            │
└───────────────┬───────────────┘   └─────────────────────────────────┘
                │ 导出表 dispatch / dispatch_free
┌───────────────▼────────────────────────────────────────────────────┐
│ Pascal 框架 fpg_ohos_dispatch.pas                                   │
│  注册表(op→Entry)  作业表(jobId→Job)  队列(Queue)  异步 Worker 池     │
│  fpgui_dispatch_entry（任意线程受理）                                │
│  fpgui_dispatch_pump（fpGUI 主线程消费队列）                         │
│  超时守护 / 看门狗 / 取消                                           │
└───────────────┬────────────────────────────────────────────────────┘
                │ 主循环 DoWaitWindowMessage → pump
┌───────────────▼────────────────────────────────────────────────────┐
│ 业务 Handler：同步(RunOnUI) / 异步(TAsyncWorker)                     │
└────────────────────────────────────────────────────────────────────┘
```

### 2.2 线程模型

| 线程 | 角色 |
|---|---|
| ArkTS/JS 线程 | 调 `dispatch`；**不阻塞**：入口立即返回 jobId 信封，结果经 TSFN 异步回传 |
| fpGUI 主线程（UI 线程） | `fpgui_dispatch_pump` 消费队列：执行**同步 Handler**、启动**异步 Worker**、执行 UI 编组任务 |
| 异步 Worker 线程 | 执行**异步 Handler**（并发上限，默认 4） |
| 守护线程 | 每 1s 扫描作业表：超时/取消回收 |

> `fpgui_dispatch_entry` 可在任意线程调用，只做“查表 + 入队 + 唤醒”，**绝不阻塞**。

### 2.3 作业生命周期与所有权

```
受理(entry) ── 生成 jobId、加入作业表、入队、wake
   │
pump(UI 线程)
   ├─ 同步：执行 Handler → EmitResult（恰好一次回传）→ 释放 Job
   └─ 异步：StartAsyncJob → TAsyncWorker 执行
             Handler 完成 → CompleteJob/FailJob → EmitResult
             Worker 返回后若仍未完成 → INTERNAL 错误并回传
             Worker 在 finally 释放 Job、回退并发计数、启动下一个等待作业
```

- 回传用 `TakeJob`（先移除再回传）保证**恰好一次**：超时/取消/完成/异常四方竞争不会重复回传。
- 作业所有权：同步作业由 pump 释放；异步作业由 Worker 释放；超时守护**只回传不释放**。

### 2.4 结果回传

Pascal `CompleteJob/FailJob` → C++ `ohos_dispatch_result(jobId, json, failed)`
→ `napi_call_threadsafe_function`（持久 TSFN）→ JS 线程 `resolve`。

### 2.5 跨进程模型

`statusBarView` 扩展（`MyStatusBarViewAbility`）默认运行在**独立进程**
`<bundle>:statusBarView`，该进程没有启动 Pascal 应用，直接调 `fpbridge.dispatch`
会得到 `NOT_CONNECTED`。因此：
- 扩展进程用 `FpDispatchProxy.dispatchViaMain()` 经 **commonEvent** 中继；
- 主进程 `FpDispatchRelay`（随 `Fp_bridgeAbility` 生命周期启停）转发到真正的
  `fpbridge.dispatch`。

---

## 3. 快速开始

### 3.1 Pascal 侧：注册 Handler

在应用 `.lpr` 的 `MainProc` 开头注册（桥可能直接 `dlsym("MainProc")`，务必放这里）：

```pascal
uses
  ..., fpg_ohos, fpg_ohos_dispatch;

{ 同步 Handler：在 fpGUI UI 线程执行，必须快速返回，返回 JSON 字符串 }
function HandlePing(const Params: string): string;
begin
  Result := '{"ok":true,"from":"pascal"}';
end;

{ 异步 Handler：在后台线程执行；完成后必须 CompleteJob/FailJob }
procedure HandleTask(const Params: string; const JobId: string);
begin
  // ... 耗时工作 ...
  CompleteJob(JobId, '{"ok":true,"done":true}');
end;

procedure MainProc;
begin
  RegisterSync ('statusbar.ping', @HandlePing);
  RegisterAsync('statusbar.task', @HandleTask);
  fpgApplication.Initialize;
  ...
end;
```

### 3.2 ArkTS 侧：调用（主进程）

```typescript
import fpbridge from 'libfp_bridge.so';

const raw: string = await fpbridge.dispatch('statusbar.ping', JSON.stringify({ a: 1 }));
const obj = JSON.parse(raw);
if (obj.ok) { console.info('成功: ' + JSON.stringify(obj)); }
else { console.error('失败: ' + obj.code + ' ' + obj.error); }
```

或使用便捷包装：

```typescript
import { dispatchAsync } from '../common/FpDispatch';
const r = await dispatchAsync('statusbar.ping', { a: 1 });  // 直接得到对象
```

### 3.3 扩展进程（StatusBarView）

```typescript
import { dispatchViaMain } from '../common/FpDispatchProxy';
const raw = await dispatchViaMain('statusbar.ping', JSON.stringify({ from: 'StatusBarView' }));
```

---

## 4. Pascal API 参考

单元：`fpg_ohos_dispatch.pas`（`uses fpg_ohos_dispatch`）

### 4.1 类型

```pascal
TfpguiHandlerFn      = function(const Params: string): string;                  // 同步
TfpguiAsyncHandlerFn = procedure(const Params: string; const JobId: string);    // 异步
TUIWorkProc          = procedure;                                               // UI 编组
TStringFunc          = function: string;                                        // UI 编组（取值）

TfpguiParamType = (ptString, ptNumber, ptBoolean, ptObject, ptArray, ptAny);
TfpguiParamSpec = record Name: string; ParamType: TfpguiParamType; Required: Boolean; DefaultValue: string; end;
TfpguiParamSchema = array of TfpguiParamSpec;
function Param(const AName: string; AType: TfpguiParamType;
  ARequired: Boolean = True; const ADefault: string = ''): TfpguiParamSpec;
```

### 4.2 注册 / 注销

```pascal
procedure RegisterSync (const OpType: string; Handler: TfpguiHandlerFn);
procedure RegisterSync (const OpType: string; Handler: TfpguiHandlerFn; const Schema: TfpguiParamSchema);
procedure RegisterAsync(const OpType: string; Handler: TfpguiAsyncHandlerFn);
procedure RegisterAsync(const OpType: string; Handler: TfpguiAsyncHandlerFn; const Schema: TfpguiParamSchema);
procedure UnregisterHandler(const OpType: string);
function  IsRegistered(const OpType: string): Boolean;
```
- `OpType` **大小写不敏感**（内部小写化并 trim）。
- 重复注册同名 op 会**替换**旧 Handler（旧的在途作业不受影响，因为作业受理时已拷贝 Handler）。

### 4.3 异步完成 / 取消

```pascal
procedure CompleteJob(const JobId, ResultJson: string);   // 成功回传（ResultJson 需为 JSON）
procedure FailJob(const JobId, ErrorMsg: string);         // 失败回传（自动包成 INTERNAL 信封）
function  IsJobCancelled(const JobId: string): Boolean;   // 合作式取消查询
```
- 异步 Handler **必须**在返回前调用 `CompleteJob` 或 `FailJob`；否则 Worker 返回时视为错误
  （`INTERNAL: async handler returned without CompleteJob`）。

### 4.4 UI 线程编组（异步 Handler 中操作 UI）

```pascal
procedure RunOnUIThreadAsync(AProc: TUIWorkProc);                          // fire-and-forget
procedure RunOnUIThreadSync (AProc: TUIWorkProc; TimeoutMs: Cardinal = 5000);
function  RunOnUIThreadString(AFunc: TStringFunc; TimeoutMs: Cardinal = 5000): string;
```
- 已在 UI 线程时直接执行；否则投递到主循环队列。
- `RunOnUIThreadString` 超时/异常返回 `''`（当前不区分“空值”与“超时”）。

### 4.5 设置（一般由 `fpg_ohos.pas` 自动调用）

```pascal
procedure SetDispatchWake(AWake: TDispatchWakeProc);            // 由框架注入
procedure SetDispatchResultSink(ASink: TDispatchResultSink);    // 由框架注入
procedure SetDispatchLog(AProc: TDispatchLogProc);              // 由框架注入
procedure SetDispatchUIThreadId(AId: TThreadID);
procedure SetDispatchTimeout(ATimeoutMs: Cardinal);             // 0 = 禁用超时
procedure SetMaxAsyncJobs(AMax: Integer);                       // 异步并发上限，默认 4
```
在 `fpg_ohos.pas` 中通过常量集中配置：

```pascal
OHOS_DISPATCH_TIMEOUT_MS = 30000;  // 0 = 禁用超时处理
OHOS_DISPATCH_MAX_ASYNC  = 4;      // 异步并发上限
```

### 4.6 框架内部入口（C++ 调用，业务一般不用）

```pascal
function  fpgui_dispatch_entry(opType, params: PChar): PChar; cdecl;  // 受理，返回堆分配信封
procedure fpgui_dispatch_free(p: PChar); cdecl;                       // 释放上者返回值
procedure fpgui_dispatch_pump;                                        // 主循环调用
function  fpgui_dispatch_has_pending: Boolean;
```
> `fpgui_dispatch_entry` 每次返回**独立分配**的缓冲区，调用方必须用
> `fpgui_dispatch_free` 释放（C++ 已按 v7 契约处理）。

---

## 5. ArkTS API 参考

### 5.1 `libfp_bridge.so`（`Index.d.ts`）

```typescript
export const dispatch: (op: string, params: string) => Promise<string>;
export const dispatchCancel: (jobId: string) => void;
```
- `params`：JSON 字符串；无参可传 `'{}'`（省略时 C++ 默认 `"{}"`）。
- 返回 Promise：
  - **resolve**：JSON 字符串（成功或失败信封，见 §6）；
  - **reject**：仅入参/连接类错误（`BAD_ARGS` / `NOT_CONNECTED`）。

### 5.2 `common/FpDispatch.ets`（主进程便捷包装）

```typescript
import {
  dispatchAsync,        // (op, params: object) => Promise<object>
  dispatchObject,       // <T>(op, params: object) => Promise<T>
  dispatchAsyncText,    // (op, paramsJson) => Promise<string>
  dispatchRaw,          // (op, paramsJson) => Promise<string>
  dispatchCancel        // (jobId) => void
} from '../common/FpDispatch';
```

### 5.3 `common/FpDispatchProxy.ets`（扩展进程/跨进程）

```typescript
dispatchViaMain(op: string, params: string, timeoutMs: number = 8000): Promise<string>;
cancelViaMain(jobId: string, timeoutMs: number = 3000): Promise<string>;
```

### 5.4 `common/FpDispatchRelay.ets`（主进程）

```typescript
startDispatchRelay(): void;   // 由 Fp_bridgeAbility.onCreate 调用
stopDispatchRelay(): void;    // 由 Fp_bridgeAbility.onDestroy 调用
```

### 5.5 保留 op（以 `__` 开头）

| op | 作用 | 返回 |
|---|---|---|
| `__ping` | 连通性探测 | `{"ok":true,"pong":true}` |
| `__ops` | 列出已注册 op 及同步/异步 | `{"ok":true,"ops":[{"op":"...","async":false},...]}` |
| `__stats` | 队列/在制/并发统计 | `{"ok":true,"queued":N,"pending":N,"asyncActive":N,...}` |
| `__cancel` | 取消指定 jobId | `{"ok":true,"cancelRequested":true/false}` |

> 业务 op 名**不要**以 `__` 开头，避免与保留字冲突。

---

## 6. 结果信封与错误码

**受理成功（起步响应，内部解析 jobId）**
```json
{"ok":true,"async":true,"jobId":"job_1"}
```

**失败信封**
```json
{"ok":false,"code":"NO_HANDLER","error":"no handler: xxx"}
```

| code | 含义 | 触发点 |
|---|---|---|
| `NO_HANDLER` | op 未注册 | 受理时查表失败 |
| `SCHEMA_FAIL` | 参数校验失败 | Schema 校验 |
| `TIMEOUT` | 异步作业超时/取消宽限到期 | 超时守护（0 时禁用） |
| `INTERNAL` | Handler 异常 / 异步未 CompleteJob | 执行期 |
| `CANCELLED` | 显式取消 | `dispatchCancel` |
| `BAD_ARGS` | op 为空/超长、params 非字符串 | NAPI 边界（reject） |
| `NOT_CONNECTED` | 桥/Pascal 未连接 | NAPI 边界（reject） |
| `RELAY` | 跨进程中继层错误 | Proxy/Relay |

**约定**：业务结果与失败都走 resolve 信封；调用方应统一 `JSON.parse` 后判断 `ok`。

---

## 7. 使用技巧与模式

### 7.1 同步 vs 异步怎么选

| 场景 | 选择 |
|---|---|
| 读写控件、发通知、改标题等**轻量且立即完成** | `RegisterSync`（UI 线程） |
| 文件/网络/计算等**耗时** | `RegisterAsync`（后台线程） |
| 异步里要改 UI | 在 Handler 内 `RunOnUIThreadAsync/Sync` |

> 同步 Handler **运行在 UI 线程**，超过 200ms 会打 `dispatch WARN: sync handler ... took Nms`。

### 7.2 Schema 参数校验（可选）

```pascal
RegisterSync('setText', @HandleSetText, [
  Param('text',  ptString, True),
  Param('size',  ptNumber, False),
  Param('bold',  ptBoolean, False)
]);
```
- 未通过时回传 `SCHEMA_FAIL: missing required param: text`。
- 内置实现为**轻量、扁平**解析：按 `"key"` + `:` 定位，按首字符判类型。
  仅适合**顶层扁平对象**；嵌套/字符串内出现同名 key 可能误判，复杂参数请自行解析。
- `Param` 的 `DefaultValue` 仅为声明（当前不自动注入默认值）。

### 7.3 动态注册/注销

```pascal
RegisterSync('op.x', @H);      // 运行时随时注册
UnregisterHandler('op.x');     // 注销；已受理的在途作业继续执行（已拷贝 Handler）
if IsRegistered('op.x') then ...
```

### 7.4 取消（合作式）

```pascal
procedure HandleBig(const Params: string; const JobId: string);
var i: Integer;
begin
  for i := 1 to 100000 do
  begin
    if IsJobCancelled(JobId) then      // 作业被取消/超时/完成 → 尽早退出
    begin
      FailJob(JobId, 'cancelled');
      Exit;
    end;
    // ... 分片工作 ...
  end;
  CompleteJob(JobId, '{"ok":true}');
end;
```
ArkTS 侧（需持有 jobId）：
```typescript
fpbridge.dispatchCancel(jobId);
```
> **当前限制**：`fpbridge.dispatch` 直接 resolve 最终结果，**不回传起步 jobId**，
> 故 ArkTS 侧通常拿不到 jobId 去取消；取消主要用于“框架内部超时/宽限回收”与
> 已有 jobId 的场景（日志/后续扩展）。取消后超过 1s 宽限会被守护回传 `TIMEOUT`。

### 7.5 异步任务里更新 UI

```pascal
procedure HandleLoad(const Params: string; const JobId: string);
var content: string;
begin
  content := ReadFileToString(...);           // 后台线程
  RunOnUIThreadAsync(procedure
    begin
      // 这里已在 UI 线程，可安全操作控件
      MainForm.Memo.Text := content;
    end);
  CompleteJob(JobId, '{"ok":true}');
end;
```

### 7.6 内省与健康检查

```typescript
await fpbridge.dispatch('__ping',  '{}');      // 连通性
await fpbridge.dispatch('__ops',   '{}');      // 已注册 op 列表
await fpbridge.dispatch('__stats', '{}');      // 队列/在制/并发
```

### 7.7 泛型结果（ArkTS）

```typescript
import { dispatchObject } from '../common/FpDispatch';
interface TitleResult { ok: boolean; title?: string; }
const r = await dispatchObject<TitleResult>('getTitle', {});
```

### 7.8 参数/返回值约定

- **入参**：始终 JSON 对象字符串（`JSON.stringify({...})`）。
- **返回值**：始终 JSON 字符串。简单结果用 `{"ok":true,...}`；错误会自动包 `{"ok":false,"code":...,"error":...}`。
- 返回含中文/引号时由框架统一转义（`JsonEscape`）。

### 7.9 异步并发上限与排队

- 默认最多 4 个异步 Handler 同时运行；超出的受理后排队，Worker 空出即启动。
- 可用 `SetMaxAsyncJobs(n)` 调整；`__stats` 的 `asyncWaiting` 反映排队数。

---

## 8. 跨进程使用（StatusBarView）

**背景**：状态栏快捷面板是 `StatusBarViewExtensionAbility`，运行在独立进程，不能直接命中
主进程的 Pascal。示例工程已内置：

- 扩展页 `pages/StatusBarView.ets` 使用 `FpDispatchProxy.dispatchViaMain(...)`。
- 主进程 `Fp_bridgeAbility.onCreate` 调 `startDispatchRelay()`，`onDestroy` 调 `stopDispatchRelay()`。

```typescript
// 扩展进程页面
import { dispatchViaMain } from '../common/FpDispatchProxy';
const raw = await dispatchViaMain('statusbar.ping', JSON.stringify({ from: 'panel' }), 8000);
```

中继事件：
- 请求 `com.example.ax.fpGUI.DISPATCH_REQ`（参数：`clientId/reqId/kind/op/params/jobId`）
- 响应 `com.example.ax.fpGUI.DISPATCH_RESP`（参数：`clientId/reqId/result`）

> 若主进程未运行/未连接，`dispatchViaMain` 会在超时后 reject（`dispatchViaMain timeout`）。

---

## 9. 注意事项与限制

1. **同步 Handler 禁止耗时**：它在 fpGUI UI 线程执行，会阻塞界面；超过 200ms 会告警。
2. **异步 Handler 必须回传**：返回前调 `CompleteJob`/`FailJob`，否则报 `INTERNAL`。
3. **超时**：异步作业默认 30s 超时（`OHOS_DISPATCH_TIMEOUT_MS`，C++ 兜底 35s）。
   **设为 0 即禁用超时处理**（取消宽限仍生效）。
4. **超时≠杀线程**：超时只回传结果，卡住的 Worker 仍占用一个并发位（上限默认 4）；
   多个卡死任务会耗尽并发槽。长任务请实现 `IsJobCancelled` 协作退出。
5. **取消是合作式**：框架不强行终止线程。
6. **跨进程开销**：走 commonEvent 广播，适合控制信令，不适合高频/大数据。
7. **保留前缀**：业务 op 不要以 `__` 开头。
8. **Handler 注册位置**：桥可能直接调用 `MainProc`，务必在 `MainProc`（或更早）注册。
9. **ABI 版本**：dispatch 属 v7 契约；`lib<app>.so` 与 `libfp_bridge.so` 必须同版本重编。
10. **框架单元改动需全量重编**：`build.bat -B`（否则 PPU 级联可能触发 FPC 编译器崩溃）。
11. **中继来源**：当前中继未校验发布者 bundleName，commonEvent 为全局事件；生产环境建议
    在 Relay/Proxy 中校验 `data.bundleName`。
12. **Schema 能力有限**：仅顶层扁平对象的键存在性与基本类型。

---

## 10. 故障排查

| 现象 | 可能原因 / 处理 |
|---|---|
| `{"ok":false,"code":"NO_HANDLER"}` | op 未注册或拼写/大小写不一致；核对 `RegisterSync/Async` 与 `__ops` |
| `{"ok":false,"code":"SCHEMA_FAIL"}` | 缺少必填参数或类型不符；核对 Schema |
| `{"ok":false,"code":"TIMEOUT"}` | 异步 Handler 未在超时内完成；检查长任务/死锁；或调大/禁用超时 |
| `{"ok":false,"code":"INTERNAL","error":"...returned without CompleteJob"}` | 异步 Handler 忘了 `CompleteJob` |
| reject `NOT_CONNECTED` | 桥未连接/进程不对：扩展进程应走 `FpDispatchProxy` |
| reject `BAD_ARGS` | op 为空/超 255 字符，或 params 非字符串 |
| 扩展面板点按钮报 `dispatchViaMain timeout` | 主进程未运行/中继未启动 |
| 改了 `fpg_ohos*.pas` 后编译崩溃 | 用 `build.bat -B` 全量重编 |
| 异步不并发 | 检查 `__stats` 的 `asyncActive/asyncWaiting`；可能已达 `maxAsync` |

**hilog 关键字**（tag `fpGUI` / `fpGUI-test`）：
```
dispatch: op=<op> job=<jobId>
dispatch: handlers registered (sync+async+stuck)
dispatch WARN: sync handler "<op>" took <ms> ms (blocks UI thread)
dispatch WARN: job timeout/cancelled -> <jobId>
FpDispatchRelay: relay req ...
FpDispatchProxy / fpGUI-test: <op> <ms>: <json>
```

---

## 11. 完整示例

### 11.1 Pascal（`test/helloworld/helloworld.lpr` 摘录）

```pascal
uses
  ..., fpg_ohos, fpg_ohos_dispatch, sysutils;

var
  gDispatchCount: Integer = 0;

{ 同步：立即返回，在 UI 线程执行 }
function HandleStatusBarPing(const Params: string): string;
begin
  Inc(gDispatchCount);
  Result := format('{"ok":true,"from":"pascal","count":%d}', [gDispatchCount]);
end;

{ 异步：后台线程耗时 1.5s 后回传 }
procedure HandleAsyncTask(const Params: string; const JobId: string);
begin
  Sleep(1500);
  CompleteJob(JobId, '{"ok":true,"delayMs":1500,"job":"' + JobId + '"}');
end;

procedure RegisterMyHandlers;
begin
  RegisterSync ('statusbar.ping',      @HandleStatusBarPing);
  RegisterSync ('dispatch.selftest',   @HandleSelfTest);
  RegisterAsync('statusbar.asyncTask', @HandleAsyncTask);
end;

procedure MainProc;
begin
  RegisterMyHandlers;          // 必须在 MainProc 开头（桥优先直调 MainProc）
  fpgApplication.Initialize;
  ...
end;
```

### 11.2 ArkTS（主进程）

```typescript
import fpbridge from 'libfp_bridge.so';

async function demo(): Promise<void> {
  // 同步
  const syncRaw = await fpbridge.dispatch('statusbar.ping', JSON.stringify({ from: 'ets' }));
  console.info('sync:', syncRaw);

  // 异步
  const asyncRaw = await fpbridge.dispatch('statusbar.asyncTask', '{}');
  console.info('async:', asyncRaw);

  // 内省
  console.info('ops:', await fpbridge.dispatch('__ops', '{}'));
}
```

### 11.3 ArkTS（扩展进程页面）

```typescript
import { dispatchViaMain } from '../common/FpDispatchProxy';

private async callPascal(): Promise<void> {
  try {
    const raw = await dispatchViaMain('statusbar.ping', JSON.stringify({ from: 'panel' }), 8000);
    this.reply = raw;
  } catch (e) {
    this.reply = 'ERR: ' + ((e as Error).message ?? JSON.stringify(e));
  }
}
```

---

## 12. 构建与版本

### 12.1 文件与依赖

| 侧 | 文件 |
|---|---|
| Pascal 框架 | `framework/.../corelib/ohos/fpg_ohos_dispatch.pas`、`fpg_ohos.pas` |
| C++ 桥 | `lib_fp_bridge/.../cpp/fp_bridge.h`、`napi_init.cpp`（v7） |
| ArkTS | `cpp/types/libfp_bridge/Index.d.ts`、`ets/common/FpDispatch.ets`、`FpDispatchProxy.ets`、`FpDispatchRelay.ets` |
| 业务示例 | `fpGUI-2.1.0/test/helloworld/helloworld.lpr` |

### 12.2 构建步骤

```powershell
# 1) Pascal 应用（改框架单元后务必 -B 全量重编）
cd D:\fpGUI\fpGUI-2.1.0\test\helloworld
cmd /c "build.bat -B"

# 2) HAP（DevEco 或 CLI）
$env:DEVECO_SDK_HOME='F:\Huawei\DevEcoStudio\sdk'
$env:JAVA_HOME='F:\Huawei\DevEcoStudio\jbr'
$env:NODE_HOME='F:\Huawei\DevEcoStudio\tools\node'
& 'F:\Huawei\DevEcoStudio\tools\hvigor\bin\hvigorw.bat' --mode module -p product=default assembleHap --no-daemon
```

### 12.3 版本约定
- `OHOS_BRIDGE_VERSION = 7`：`fp_bridge.h`、`fpg_ohos.pas`、两表 `version` 三处同步。
- 表结构/成员变更时三处同时 +1，并重编所有使用该桥的应用库。

---

_本手册对应实现：P0–P3 优化版（超时/取消/并发上限/看门狗/Schema/内省/UI 编组/跨进程中继）。_
