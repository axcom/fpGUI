# fpGUI OHOS (OpenHarmony) IPC 使用说明手册

> 适用范围：fpGUI 2.1.0 OHOS 移植版（`examples/apps/debugserver` 测试工程，`libhelloworld.so`）
> 代码位置：
> - 传输层实现：`framework/src/main/pascal/corelib/ohos/fpg_simpleipc_ohos.pas`
> - Binder 后端：`framework/src/main/pascal/corelib/ohos/fpg_simpleipc_ohos_binder.pas`、`fpg_ohos_ipc_kit.pas`
> - 调试工具（PC 端）：`examples/apps/debugserver/dbugsrv_tcp.lpr`、`dbgclienttest.lpr`、`ipcsmoke.lpr`
> - C++ 桥：`F:\Huawei\lazQtOHOS_Demo\lib_fp_bridge\fp_bridge\src\main\cpp\binder_bridge.cpp`

---

## 目录

- [1. 概述与架构](#1-概述与架构)
- [2. 快速开始（前置条件）](#2-快速开始前置条件)
- [3. 后端一：TCP loopback（默认）](#3-后端一tcp-loopback默认)
  - [3.1 服务器端示例](#31-服务器端示例)
  - [3.2 客户端示例（fpg_dbugintf）](#32-客户端示例fpg_dbugintf)
  - [3.3 PC 端调试链路（hdc 转发）](#33-pc-端调试链路hdc-转发)
- [4. 后端二：AF_UNIX（同应用多进程）](#4-后端二af_unix同应用多进程)
- [5. 后端三：Binder（IPC Kit）](#5-后端三binderipc-kit)
  - [5.1 P1 原生子进程宿主](#51-p1-原生子进程宿主)
  - [5.2 P2 ServiceExtensionAbility 客户端钩子](#52-p2-serviceextensionability-客户端钩子)
  - [5.3 平台限制说明](#53-平台限制说明)
- [6. PC 端调试工具](#6-pc-端调试工具)
- [7. 完整示例：nanoedit 单实例模式](#7-完整示例nanoedit-单实例模式)
- [8. 完整测试流程](#8-完整测试流程)
- [9. 常见问题排查](#9-常见问题排查)
- [10. 源码与构建](#10-源码与构建)

---

## 1. 概述与架构

OHOS 的 IPC 传输层完全复用 **FPC SimpleIPC 的公开 API 与消息协议**（`TSimpleIPCServer` / `TSimpleIPCClient` / `TMsgHeader`），只替换了平台通信层（通过官方扩展点 `DefaultIPCServerClass` / `DefaultIPCClientClass` 注入），因此**业务代码与桌面端完全一致**。

```
┌─ 应用进程 ──────────────────────────────────────────────┐
│  TSimpleIPCServer / TSimpleIPCClient（API 不变）          │
│      │ 注入（DefaultIPC*Class）                          │
│  ┌────┴──────────────────────────────────────────────┐  │
│  │ fpg_simpleipc_ohos（TCP loopback / AF_UNIX）       │  │
│  │ fpg_simpleipc_ohos_binder（Binder / IPC Kit）      │  │
│  └───────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

### 后端选择矩阵

| 后端 | 选择方式 | 适用场景 | 跨应用 | 需要权限 |
|---|---|---|---|---|
| **TCP loopback**（默认） | 服务器 `Global := True`；客户端 `SystemGlobal := True` | 设备内通用、跨应用、PC 调试链路 | 是 | `ohos.permission.INTERNET` |
| **AF_UNIX** | 服务器 `Global := False`；客户端 `SystemGlobal := False` | 同应用（同 bundle）多进程，最快最安全 | 否（沙箱隔离） | 无 |
| **Binder（IPC Kit）** | `OHOSIPCEnableBinder` + 桥接 | 同应用子进程（P1）；系统服务客户端（P2） | 是（系统服务） | 无（依赖 IPC Kit 系统库，API 12+） |

### 消息协议（与桌面端兼容）

每条消息 = 定长 `TMsgHeader`（`Version`(1) + `MsgType`(4) + `MsgLen`(4)，共 9 字节）+ 原始负载。PC 端 `dbugsrv_tcp` 与设备端互操作无需转换。

### ServerID → 端口映射

`ServerID`（可带 `-instance` 后缀）经 CRC32 哈希映射到 `40000 + (hash mod 10000)`：

- `DebugServerID = 'fpgDebugServer'` → **端口 48412**
- `'nanoedit'` → **端口 48408**
- 服务器 `Global=False` 时端口附加 `-<PID>` 后缀；客户端通过 `ServerInstance` 指定

---

## 2. 快速开始（前置条件）

### 2.1 HAP 网络权限

TCP loopback 需要网络权限，在 `fp_bridge/src/main/module.json5` 的 `"module"` 节点添加：

```json5
"requestPermissions": [
  { "name": "ohos.permission.INTERNET" }
],
```

> 缺失时 `socket()` 返回 **EPERM（错误码 1）**，日志表现为：
> `fpGUI: StartServer failed: EIPCError: Failed to create IPC socket: 1`

### 2.2 应用入口接线（重要）

`ohos_bridge_connect`（反向桥接）**必须在 `fpgApplication.Initialize` 之后显式调用**，绝不能放在 `TfpgOhosApplication.Create` / `AfterConstruction` 内（会导致单例 getter 递归创建 → 日志出现两次 `fp_bridge_init OK` → 单例混乱）：

```pascal
procedure MainProc;
begin
  fpgApplication.Initialize;
  ohos_bridge_connect;          // 必须在单例就绪后调用
  frm := TMainForm.Create(nil);
  frm.Show;
  fpgApplication.Run;
end;
```

### 2.3 编译选项

- **不要使用 `-gl`**（DWARF 行号信息）：FPC 3.3.1 在 OHOS 目标上 LNFODWRF 单元初始化会确定性栈崩溃。保留 `-g`（调试符号）即可。
- 构建脚本：`examples/apps/debugserver/build.bat`（产物 `libhelloworld.so`，自动拷贝到 HAP 的 `fp_bridge/libs/x86_64/`）。

---

## 3. 后端一：TCP loopback（默认）

### 3.1 服务器端示例

```pascal
uses
  Classes, SysUtils, simpleipc, fpg_dbugmsg;

var
  Srv: TSimpleIPCServer;

// 消息到达回调（简单起见直接打印；GUI 应用可在此刷新界面）
procedure OnMessage(Sender: TObject);
begin
  WriteLn(stderr, 'msg type=', Srv.MsgType, ' len=', Srv.MsgData.Size);
end;

procedure StartMyServer;
begin
  Srv := TSimpleIPCServer.Create(nil);
  Srv.ServerID := 'myDebugService';      // → 端口 = 40000 + CRC32 mod 10000
  Srv.Global := True;                    // TCP loopback 后端
  Srv.OnMessage := @OnMessage;
  Srv.StartServer;                       // 注意：不要同时设 Active := True
end;
```

> **坑**：`Active := True` 与 `StartServer` 是等价启动方式，**同时调用**会抛
> `EIPCError: This operation is illegal when the server is active.`

消息轮询（非线程模式）：

```pascal
procedure PollMessages;
begin
  while Srv.PeekMessage(1, True) do
  begin
    if Srv.MsgData = nil then
      Break;   // TCP 后端：accept 后数据未到/连接被消费时本轮无消息
    // 处理 Srv.MsgData（TStream）
  end;
end;
```

### 3.2 客户端示例（fpg_dbugintf）

```pascal
uses fpg_dbugintf;

SendDebug('hello from device');
SendDebugFmt('pid=%d', [GetProcessID]);
SendInteger('counter', 42);
SendMethodEnter('MyProc');
// ... 业务代码 ...
SendMethodExit('MyProc');
```

> **时序坑**：`SendDebug` 惰性初始化时会做 `ServerRunning` 探测；**服务器未启动时探测失败 → `DebugDisabled` 永久置位**，后续所有 `SendDebug` 被跳过。务必确保服务器先启动。

手动客户端（`TSimpleIPCClient`）：

```pascal
uses
  Classes, SysUtils, simpleipc, fpg_dbugmsg, fpg_simpleipc_ohos;

procedure SendOneMessage(const AText: String);
var
  Cli: TSimpleIPCClient;
  S: TMemoryStream;
  Msg: TDebugMessage;
begin
  Cli := TSimpleIPCClient.Create(nil);
  try
    Cli.ServerID := DebugServerID;      // 'fpgDebugServer' → 48412
    Cli.SystemGlobal := True;           // TCP loopback 后端
    if not Cli.ServerRunning then
    begin
      WriteLn('server not running');
      Exit;
    end;
    Cli.Connect;
    Msg.MsgType := 1;                   // dlInformation
    Msg.MsgTimeStamp := Now;
    Msg.MsgTitle := 'app';
    Msg.Msg := AText;
    S := TMemoryStream.Create;
    try
      WriteDebugMessageToStream(S, Msg);
      Cli.SendMessage(mtUnknown, S);    // 单向发送（ASYNC）
    finally
      S.Free;
    end;
    Cli.Disconnect;
  finally
    Cli.Free;
  end;
end;
```

### 3.3 PC 端调试链路（hdc 转发）

设备端应用（`SendDebug*`）与 PC 端工具通过端口转发互通，**协议零转换**。

#### 场景 A：设备服务器 ← PC 客户端（验证设备端接收）

```bash
# 主机 48412 → 设备 48412
hdc fport tcp:48412 tcp:48412

# PC 运行客户端（模拟 fpg_dbugintf 消息格式，发 10 条）
examples/apps/debugserver/dbgclienttest.exe
# → 设备端 frm_main 调试服务器窗口显示消息
```

#### 场景 B：设备客户端 → PC 服务器（完整调试链路）

```bash
# 先移除 fport，再反向转发：设备 48412 → 主机 48412
hdc fport -rm tcp:48412 tcp:48412
hdc rport tcp:48412 tcp:48412

# PC 运行 TCP 调试服务器
examples/apps/debugserver/dbugsrv_tcp.exe [logfile.txt]
# → PC 窗口显示设备端 SendDebug* 输出
```

> **限制**：rport 仅当设备端 48412 **无本机监听**时生效（本机监听优先）。
> 设备端 `frm_main` 调试服务器占用 48412 时，消息被本机服务器接收（自发自收），不会转发到 PC。

#### 场景 C：设备自发自收（快速验证设备端链路）

`helloworld.lpr` 启动后自动发送：

```
Information device startup: bridge connected
Information device pid=<pid>
```

（实现于 `MainProc`，位于 `frm.Show` 之后——确保服务器已就绪。）

---

## 4. 后端二：AF_UNIX（同应用多进程）

同 bundle 的多 HAP/多进程共享应用沙箱，可用 AF_UNIX 流式 socket 实现零端口冲突、最安全的进程间通信。socket 文件位于沙箱 `.ipc` 目录（`/data/storage/el2/base/files/.ipc/` 优先）。

```pascal
// 服务器（Global = False → AF_UNIX）
Srv := TSimpleIPCServer.Create(nil);
Srv.ServerID := 'myInternalSvc';
Srv.Global := False;          // ← AF_UNIX 后端
Srv.StartServer;

// 客户端（SystemGlobal = False → AF_UNIX）
Cli := TSimpleIPCClient.Create(nil);
Cli.ServerID := 'myInternalSvc';
Cli.SystemGlobal := False;    // ← AF_UNIX 后端
Cli.Connect;
```

> 全局规则（与 TCP 对应）：
> - 服务器 `Global = True`  ⟷ 客户端 `SystemGlobal = True` → TCP loopback
> - 服务器 `Global = False` ⟷ 客户端 `SystemGlobal = False` → AF_UNIX

---

## 5. 后端三：Binder（IPC Kit）

Binder 走官方 IPC 框架（Binder 驱动），带 PID/UID 鉴权、无端口冲突、不依赖网络权限。要求设备具备 IPC Kit（API 12+ 系统库），**NDK 头文件与 `libipc_capi.so` 随 SDK 提供**。

### 5.1 P1 原生子进程宿主

**原理**：应用通过 `OH_Ability_CreateNativeChildProcess` 拉起 `libhelloworld.so` 作为原生子进程；子进程导出 `NativeChildProcess_OnConnect`（返回 `OHIPCRemoteStub*`）与 `NativeChildProcessMainProc`（服务器循环）；主进程回调拿到 `OHIPCRemoteProxy*` 交给 Pascal。

**子进程侧**（`helloworld.lpr` 已实现）：

```pascal
{ 子进程：返回 Stub（内部创建 Threaded 的 Binder SimpleIPC 服务器） }
function NativeChildProcess_OnConnect: Pointer; cdecl; export;
begin
  Result := OHOSBinderStartChildServer(DebugServerID, @ChildOnMessage);
end;

{ 子进程主循环 }
procedure NativeChildProcessMainProc; cdecl; export;
begin
  OHOSBinderRunChildLoop(1000);
  OHOSBinderStopChildServer;
end;
```

**主进程侧**（启用 Binder 并拉起子进程）：

```pascal
uses fpg_simpleipc_ohos_binder;

OHOSIPCEnableBinder;              // 注入 Binder 后端
if not OHOSBinderSpawnServer then // 拉起子进程（C++ 桥：binder_bridge.cpp）
  WriteLn('spawn binder server failed');

// 等待子进程就绪（proxy 经 ohos_binder_on_proxy 回调送达）
if OHOSIPCBinderWaitProxy(5000) then
begin
  Cli := TSimpleIPCClient.Create(nil);
  Cli.ServerID := DebugServerID;
  Cli.Connect;                    // Binder 后端
  Cli.SendStringMessage('hello via binder');
end;
```

**桥接依赖**（`lib_fp_bridge` 工程已配置）：
- `CMakeLists.txt` 链接 `libipc_capi.so`、`libchild_process.so`
- `binder_bridge.cpp` 导出 `ohos_binder_spawn_server` / `ohos_binder_set_proxy` / `ohos_binder_get_proxy` / `ohos_binder_proxy_destroy`
- Pascal 导出 `ohos_binder_on_proxy` / `ohos_binder_on_dead`（`libhelloworld.so`）

### 5.2 P2 ServiceExtensionAbility 客户端钩子

客户端若需连接**系统提供的** ServiceExtensionAbility（如系统服务），桥已预留代理接入点：

- C++：`ohos_binder_set_proxy(void*)` —— ETS 侧 `connectServiceExtensionAbility` 拿到 `rpc.IRemoteObject` 后经 NAPI 传入（ETS 接线由应用自行实现）
- Pascal：`ohos_binder_on_proxy` 回调自动收到代理句柄

```typescript
// ETS 侧（示意）
connectServiceExtensionAbility(want, {
  onConnect: (_e, remote) => {
    testNapi.binderSetProxy(remote as Object);  // 需自定义 NAPI 桥
  },
  ...
});
```

### 5.3 平台限制说明

- **第三方应用不能自己宿主 ServiceExtensionAbility**（系统应用/Sample 专属）——跨应用 Binder 服务器对三方应用仅限"原生子进程"方式（P1）。
- **设备镜像可能缺 IPCKit 系统库**（如 6.1 dev-preview 模拟器无 `/system/lib64/libipc_capi.so`）：
  - 传输层已**懒加载**（dlopen+dlsym），缺库时 `libhelloworld.so` 照常加载，Binder 调用返回清晰错误（`IPC Kit not available ...`）；
  - 如需 Binder，需把 `libipc_capi.so`、`libchild_process.so` 随 HAP 打包（放入 `fp_bridge/libs/x86_64/`）。
- Binder 单事务默认约 1MB 上限（`BINDER_MAX_MESSAGE` 防护，超限报错）。

---

## 6. PC 端调试工具

| 工具 | 源码 | 用途 |
|---|---|---|
| `dbugsrv_tcp.exe` | `dbugsrv_tcp.lpr` | TCP 调试服务器（监听 127.0.0.1:48412），接收设备端 `SendDebug*` |
| `dbgclienttest.exe` | `dbgclienttest.lpr` | 测试客户端：模拟 `fpg_dbugintf` 消息格式发 10 条消息 |
| `ipcsmoke` | `ipcsmoke.lpr` | 本机协议冒烟套件（字符串/10 万字节二进制/多客户端/重启/双服务器拒绝/断线异常） |

重新编译（win64）：

```bat
examples/apps/debugserver/build-win-tools.bat
```

`dbugsrv_tcp` 输出示例：

```
dbugsrv_tcp: listening on 127.0.0.1:48412 (ServerID="fpgDebugServer")
  On the OHOS device/emulator, run:  hdc rport tcp:48412 tcp:48412
11:02:33.125: Information device startup: bridge connected
11:02:33.126: Information device pid=7018
```

---

## 7. 完整示例：nanoedit 单实例模式

> 工程：`examples/apps/nanoedit`（OHOS 产物 `libhelloworld.so`，构建 `build.bat`）
> 场景：编辑器同一时间只运行一个实例；**再次启动并携带文件参数时，把文件路径转发给已运行的实例打开**，新进程退出。这是 SimpleIPC 在桌面 fpGUI 中的经典用法，本手册将其移植到 OHOS 并修正了平台适配问题。

### 7.1 流程

```
第 2 次启动（带文件参数）
  → NotifyAnotherInstance：
      ServerRunning 探测 'nanoedit'（TCP 48408）→ 有实例？
        ├─ 是：SendStringMessage(1, 文件路径) → 已运行实例打开文件 → 本进程退出
        └─ 否：启动新实例（自身成为服务器，监听 'nanoedit'）
```

### 7.2 服务器端（mainfrm.pas）

```pascal
procedure TMainForm.StartIPCServer;
begin
  try
    FIPCServer := TSimpleIPCServer.Create(self);
    FIPCServer.ServerID := 'nanoedit';
    FIPCServer.Global := True;        { OHOS: True = TCP loopback 后端 }
    FIPCServer.StartServer;           { 勿同时设 Active := True }
    fpgApplication.OnIdle := @CheckIPCMessages;
  except
    on E: Exception do
    begin
      WriteLn(stderr, 'nanoedit: StartIPCServer failed: ', E.ClassName, ': ', E.Message);
      FreeAndNil(FIPCServer);         { 降级：编辑功能不受影响 }
    end;
  end;
end;

procedure TMainForm.CheckIPCMessages(Sender: TObject);
begin
  if FIPCServer = nil then Exit;
  try
    while FIPCServer.PeekMessage(1, True) do
    begin
      if FIPCServer.MsgData = nil then
        Break;   { TCP 后端空返回防御（accept 后数据未到） }
      IPCMessageReceived;
    end;
  except
  end;           { 异常静默，idle 轮询继续 }
end;

procedure TMainForm.IPCMessageReceived;
begin
  case FIPCServer.MsgType of
    0: BringToFront;                              { 唤醒 }
    1: begin
         LoadFile(FIPCServer.StringMessage);       { 打开转发的文件 }
         BringToFront;
       end;
  end;
end;
```

### 7.3 客户端（helloworld.lpr）

```pascal
function NotifyAnotherInstance(CmdIntf: ICmdLineParams): Boolean;
var
  aClient: TSimpleIPCClient;
begin
  if (CmdIntf.ParamCount > 0) then
  begin
    aClient := TSimpleIPCClient.Create(nil);
    try
      aClient.ServerID := 'nanoedit';
      { OHOS 后端配对：服务器 Global=True → TCP，客户端必须
        SystemGlobal=True（默认 False = AF_UNIX，单实例探测会失效） }
      aClient.SystemGlobal := True;
      Result := aClient.ServerRunning;   // 有另一实例在跑？
      if Result then
      begin
        aClient.Connect;
        try
          aClient.SendStringMessage(1, CmdIntf.Params[1]);
        finally
          aClient.Disconnect;
        end;
      end
    finally
      aClient.Free;
    end;
  end
  else
    Result := False;
end;

function RunLazarus(argc: Integer; argv: PPChar): Integer; cdecl; export;
begin
  Result := 0;
  try
    fpgApplication.Initialize;
    ohos_bridge_connect;      { 单例就绪后显式调用（不能放构造链内） }
    MainProc0;                { 命令行 → 通知已有实例 / 启动新实例 }
  except
    on E: Exception do
      fpGUI_Hilog(LOG_ERROR, 'RunLazarus exception: ' + E.ClassName + ': ' + E.Message);
  end;
end;
```

### 7.4 修正清单（OHOS 移植时已处理）

| # | 问题 | 修正 |
|---|---|---|
| 1 | 客户端未设 `SystemGlobal := True` → 探测走 AF_UNIX，与服务器 TCP 不匹配，单实例失效 | 客户端补 `SystemGlobal := True` |
| 2 | `RunLazarus` 直接调 `MainProc`，命令行单实例逻辑（`MainProc0`）从未执行 | 改为 `Initialize + ohos_bridge_connect + MainProc0` |
| 3 | `ohos_bridge_connect` 缺失（反向桥接未接线，窗口回调未装载） | 显式调用（2.2） |
| 4 | `CheckIPCMessages` 未防御 `PeekMessage` 空返回（TCP accept 后数据未到 → `MsgData=nil`） | `MsgData=nil → Break` |
| 5 | `StartIPCServer` 无异常保护（端口占用等会阻断编辑器启动） | try/except 降级 + `FreeAndNil` |
| 6 | `Destroy` 中 `FIPCServer.StopServer` 无 nil 保护（StartServer 失败后崩溃） | `if FIPCServer <> nil` |

### 7.5 测试

```bash
# 1. 启动第一个实例（HAP 运行）→ 窗口正常，hilog 无异常

# 2. 模拟"第二次启动携带文件参数"：由应用入口注入参数（ETS 启动载荷
#    / 命令行参数），或直接验证 IPC 链路：
hdc fport tcp:48408 tcp:48408        # 'nanoedit' → 40000 + CRC32('nanoedit') % 10000 = 48408
# 自定义客户端发 MsgType=1 + 文件路径
# → 已运行实例窗口 BringToFront 并打开该文件

# 3. 退出实例 → 再发消息 → 无接收者（ServerRunning=False）
```

> 'nanoedit' ServerID 对应端口：`OHOSIPCGetPort('nanoedit')` = 48408（可用工具打印确认）。

---

## 8. 完整测试流程

```bash
# 0. 部署并启动（预期：无异常日志、connected OK）
hdc hilog -r
# DevEco Run
hdc hilog -z 5000 | grep -E 'A0ff00|A00000'

# 1. 设备自发自收（debugserver：启动即触发，frm_main 窗口显示 2 条 device 消息）

# 2. PC 客户端 → 设备服务器
hdc fport tcp:48412 tcp:48412
dbgclienttest.exe                      # 设备窗口显示 10 条 client 消息

# 3. 设备 → PC 服务器（需设备端无 48412 监听）
hdc fport -rm tcp:48412 tcp:48412
hdc rport tcp:48412 tcp:48412
dbugsrv_tcp.exe                        # PC 窗口显示设备消息

# 4. UI 交互：btnPause（暂停/恢复）、btnClear（清空）、btnLiveView、btnExpandView

# 5. nanoedit 单实例：fport 48408 + 自定义客户端发 MsgType=1 → 已运行实例打开文件

# 6.（可选）Binder P1：确认 HAP 打包了 libipc_capi.so/libchild_process.so 后
#    OHOSIPCEnableBinder + OHOSBinderSpawnServer → hilog 出现 [binder-child] stub 日志
```

---

## 9. 常见问题排查

| 现象 | 原因 | 处理 |
|---|---|---|
| `Failed to create IPC socket: 1` | 缺 `ohos.permission.INTERNET` | module.json5 加权限（2.1） |
| `This operation is illegal when the server is active` | `Active := True` 与 `StartServer` 同时调用 | 二选一（3.1） |
| 消息到达后崩溃（`MsgData` 为 nil） | TCP 后端 `PeekMessage` 空返回（accept 后数据未到） | 轮询循环 `MsgData=nil → Break`（3.1） |
| `SendDebug` 无输出 | 服务器未启动时客户端探测失败 → `DebugDisabled` 置位 | 确保服务器先启动（3.2） |
| `Failed to initialize the Application object!` | 编译选项问题（构建选项/define 不一致） | 核对 `fpg_defines.inc` / 构建命令；`Initialize` 须在单例就绪后 |
| 启动崩溃：LNFODWRF `INITIALIZEAFTERUNITS` 栈溢出 | `-gl` 行号信息在 OHOS 上的 FPC 3.3.1 问题 | 去掉 `-gl`，保留 `-g`（2.3） |
| `fp_bridge_init OK` 出现两次、单例混乱 | `ohos_bridge_connect` 放在构造链内（AfterConstruction） | MainProc 显式调用（2.2） |
| `Binder: IPC Kit not available` | 设备缺 IPCKit 系统库 | HAP 自带 `libipc_capi.so` 或改用 TCP/AF_UNIX（5.3） |
| rport 转发不生效 | 设备端 48412 已被本机服务器监听 | 先停用设备端服务器（3.3 场景 B 说明） |
| nanoedit 单实例失效（每次都开新实例） | 客户端未设 `SystemGlobal := True`（后端不配对） | 客户端补 `SystemGlobal := True`（7.3） |
| 端口被占/残留 | 崩溃进程的 TIME_WAIT | `SO_REUSEADDR` 已启用；必要时换 ServerID（端口随之变化） |

---

## 10. 源码与构建

| 文件 | 说明 |
|---|---|
| `corelib/ohos/fpg_simpleipc_ohos.pas` | TCP loopback + AF_UNIX 传输层（`TOHOSServerComm`/`TOHOSClientComm`、`OHOSIPCGetPort`、`OHOSIPCDataDir`） |
| `corelib/ohos/fpg_ohos_ipc_kit.pas` | IPCKit C API 懒加载绑定（dlopen `libipc_capi.so`） |
| `corelib/ohos/fpg_simpleipc_ohos_binder.pas` | Binder 后端（`TOHOSBinderServerComm`/`TOHOSBinderClientComm`、`OHOSIPCEnableBinder`、子进程宿主编排） |
| `corelib/fpg_dbugintf.pas` | 调试客户端（OHOS 分支：TCP 后端、hdc 提示） |
| `examples/apps/debugserver/helloworld.lpr` | 设备端示例：frm_main 调试服务器 GUI + Binder 子进程导出 + SendDebug 测试 |
| `examples/apps/debugserver/dbugsrv_tcp.lpr` | PC 端 TCP 调试服务器 |
| `examples/apps/debugserver/dbgclienttest.lpr` | PC 端测试客户端 |
| `examples/apps/debugserver/ipcsmoke.lpr` | 本机协议冒烟测试 |
| `examples/apps/nanoedit/helloworld.lpr` | 单实例 IPC 客户端（转发文件打开请求） |
| `examples/apps/nanoedit/mainfrm.pas` | 单实例 IPC 服务器（接收文件打开请求） |
| `binder_bridge.cpp`（HAP 工程） | C++ 桥：子进程拉起 + proxy 交接 |

构建命令：

```bat
rem 设备端 libhelloworld.so（OHOS x86_64）
examples/apps/debugserver/build.bat
examples/apps/nanoedit/build.bat

rem PC 端工具（win64）
examples/apps/debugserver/build-win-tools.bat

rem HAP 侧（DevEco Studio）：打开 lib_fp_bridge 工程构建运行
```