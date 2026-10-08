# fpGUI OHOS 命令行参数与 Want 载荷使用手册

> 版本：2026-09-18  
> 适用范围：fpGUI for HarmonyOS（fp_bridge v9+）

---

## 目录

1. [概述](#1-概述)
2. [架构总览](#2-架构总览)
3. [Want JSON 载荷结构](#3-want-json-载荷结构)
4. [APP_ARGS 静态参数](#4-app_args-静态参数)
5. [占位符替换机制](#5-占位符替换机制)
6. [Pascal ICmdLineParams 接口](#6-pascal-icmdlineparams-接口)
7. [冷启动完整流程](#7-冷启动完整流程)
8. [热启动（onNewWant）流程](#8-热启动onnewwant流程)
9. [ETS 配置参考](#9-ets-配置参考)
10. [Pascal 应用接入示例](#10-pascal-应用接入示例)
11. [API 参考](#11-api-参考)
12. [FAQ / 常见问题](#12-faq--常见问题)

---

## 1. 概述

fpGUI 的 HarmonyOS 桥接层（`libfp_bridge.so`）提供一套完整的命令行参数注入机制，将 ArkTS 的 `Want` 对象（启动意图）转化为 Pascal 应用可消费的命令行参数。

**核心设计**：

- **`gLaunchParams`**（Pascal 全局）：存储完整的 want JSON 原文
- **`OhosArgs`**（Pascal 全局）：存储经 `%placeholder%` 替换后的空格分隔命令行参数
- 两者由 `TfpgOhosCmdLineParams` 合并解析，统一通过 `ICmdLineParams` 接口暴露给应用代码

**两个独立的传递通道**：

| 通道 | 来源 | 目标 | 说明 |
|------|------|------|------|
| payload JSON | `want` 对象整体序列化 | `gLaunchParams` | 包含 uri/action/entities/parameters 全量信息 |
| appArgs | `APP_ARGS` + want `fpArgs` 合并，经占位符替换 | `OhosArgs` | 空格分隔的命令行参数，支持 `-b debug` 和 `key=value` 两种风格 |

---

## 2. 架构总览

```
┌─────────────────────────────────────────────────────────────┐
│                       ETS 层                                │
│                                                             │
│  FpAppConfig.ets                                           │
│    APP_LIB_NAME = 'helloworld'      ← Pascal .so 库名       │
│    APP_ARGS = '-style'              ← 静态命令行参数         │
│    WANT_PARAM_ARGS = 'fpArgs'       ← want 中动态参数的 key  │
│                                                             │
│  Fp_bridgeAbility.ets                                      │
│    buildLaunchPayload(want)  → JSON string                  │
│    buildMergedArgs(want)     → mergedArgs string            │
│                                                             │
│  Index.ets                                                 │
│    fpbridge.start(APP_LIB_NAME, payload, mergedArgs)        │
│        │           │              │          │               │
│        │           │              │          └─ 第3参数：命令行参数
│        │           │              └─ 第2参数：want JSON 载荷  │
│        │           └─ 第1参数：Pascal .so 库名               │
└────────┼──────────┼──────────────┼──────────────────────────┘
         │          │              │
         ▼          ▼              ▼
┌─────────────────────────────────────────────────────────────┐
│                       C++ 层                                │
│                                                             │
│  napi_init.cpp — Start()                                   │
│    → 解析 3 个参数                                          │
│    → 创建 PascalThread                                     │
│                                                             │
│  PascalThread:                                             │
│    resolvedArgs = replacePlaceholders(appArgs, payload)     │
│      → 将 appArgs 中的 %xxx% 替换为 payload JSON 中的值    │
│                                                             │
│    g_inject_app_args(payload, resolvedArgs)                │
│      → 通过 FpBridgePascalApi 直接调用 Pascal 导出函数      │
│                                                             │
│    pro() 或 run(argc, argv)                                │
│      → 启动 Pascal 应用                                     │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                      Pascal 层                              │
│                                                             │
│  ohos_inject_app_args(payload, appArgs)                    │
│    → gLaunchParams := payload   (want JSON 原文)           │
│    → OhosArgs := resolvedArgs   (已替换 %xxx% 的参数串)    │
│                                                             │
│  TfpgOhosCmdLineParams.Create(OhosArgs, gLaunchParams)     │
│    → FItems = OhosArgs 按空格分割                           │
│    → ParsePayload(gLaunchParams) → key=value 追加到 FItems │
│                                                             │
│  fpgApplication.CmdLineParams                               │
│    → ICmdLineParams 接口（HasOption / GetOptionValue ...） │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Want JSON 载荷结构

### 3.1 JSON 格式

```json
{
  "uri": "<string>",
  "action": "<string>",
  "entities": ["<string>", ...],
  "parameters": {
    "key1": "value1",
    "key2": 123,
    ...
  }
}
```

所有字段均为**可选**，空字段会被省略（不出现空数组/空对象）。

### 3.2 字段说明

| 字段 | 类型 | 对应 Want 属性 | 说明 |
|------|------|---------------|------|
| `uri` | `string` | `want.uri` | 资源标识符，如 `file:///data/...`、`content://...`、自定义 scheme `myapp://open` |
| `action` | `string` | `want.action` | 操作类型，如 `ohos.want.action.viewData`、`ohos.want.action.select` |
| `entities` | `string[]` | `want.entities` | 实体列表，如 `["entity.browsable"]` |
| `parameters` | `Record<string, any>` | `want.parameters` | 键值对参数，支持任意类型（序列化为 JSON） |

### 3.3 典型场景的 Want 示例

#### 打开文件

```json
{
  "uri": "file:///data/app/el2/0/base/com.example/files/doc.pdf",
  "action": "ohos.want.action.viewData"
}
```

#### 分享内容（Want + parameters）

```json
{
  "action": "ohos.want.action.send",
  "parameters": {
    "key_text": "Hello from fpGUI",
    "key_uri": "file:///data/.../image.png"
  }
}
```

#### 自定义 Scheme 打开（Deep Link）

```json
{
  "uri": "myapp://open?file=/path/to/data.txt&mode=edit",
  "action": "ohos.want.action.viewData"
}
```

#### 启动参数传递（fpArgs）

在 `want.parameters` 中携带 `fpArgs` 键：

```json
{
  "action": "ohos.want.action.viewData",
  "parameters": {
    "fpArgs": "-theme dark -debug -file /data/app.txt"
  }
}
```

#### 纯 key=value 参数

```json
{
  "parameters": {
    "theme": "dark",
    "lang": "zh_CN",
    "debug": "1",
    "file": "/data/test.txt"
  }
}
```

---

## 4. APP_ARGS 静态参数

### 4.1 定义位置

`FpAppConfig.ets`：

```typescript
// fpGUI 应用库配置
export const APP_LIB_NAME: string = 'helloworld';
export const APP_ARGS: string = '-style';
export const WANT_PARAM_ARGS: string = 'fpArgs';
```

### 4.2 参数格式

APP_ARGS 是**空格分隔**的字符串，支持两种风格混用：

#### 风格一：短选项（`-key value`）

```typescript
APP_ARGS = '-style -b debug'
```

解析结果：

| 位置 | 值 |
|------|---|
| `Params[0]` | `-style` |
| `Params[1]` | `-b` |
| `Params[2]` | `debug` |

#### 风格二：键值对（`key=value`）

```typescript
APP_ARGS = 'theme=light lang=zh_CN'
```

解析结果：

| 位置 | 值 |
|------|---|
| `Params[0]` | `theme=light` |
| `Params[1]` | `lang=zh_CN` |

#### 混用

```typescript
APP_ARGS = '-style -b debug theme=dark file=/data/test.txt'
```

### 4.3 动态参数合并

ETS 层的 `buildMergedArgs()` 会将 `want.parameters["fpArgs"]` 合并到 `APP_ARGS`：

```typescript
function buildMergedArgs(want: Want | null): string {
  let args = APP_ARGS;   // 静态: '-style'
  if (want?.parameters?.[WANT_PARAM_ARGS]) {
    const dynamicArgs = String(want.parameters[WANT_PARAM_ARGS] || '');
    if (dynamicArgs.length > 0) {
      args = args.length > 0 ? args + ' ' + dynamicArgs : dynamicArgs;
    }
  }
  return args;
}
```

**示例**：

- `APP_ARGS = '-style'`，无 want 参数 → `'-style'`
- `APP_ARGS = '-style'`，`fpArgs = '-theme dark'` → `'-style -theme dark'`

---

## 5. 占位符替换机制

### 5.1 语法

在 `APP_ARGS` 中使用 `%key%` 引用 want JSON 中的字段值：

```typescript
APP_ARGS = '-uri %uri% -action %action% -theme %parameters.theme%'
```

### 5.2 替换规则

C++ 层的 `replacePlaceholders()` 函数执行替换：

1. 扫描 `APP_ARGS`，遇到 `%key%` 时在 payload JSON 中查找对应字段
2. 找到：替换为值；未找到：保留 `%key%` 原文
3. 支持嵌套：`%parameters.theme%` 查找 `{"parameters":{"theme":"dark"}}` 中的 `theme` 值

### 5.3 示例

| APP_ARGS | Payload JSON | 结果 |
|----------|-------------|------|
| `'-uri %uri%'` | `{"uri":"file:///a.txt"}` | `'-uri file:///a.txt'` |
| `'-action %action%'` | `{"action":"ohos.want.action.view"}` | `'-action ohos.want.action.view'` |
| `'-theme %parameters.theme%'` | `{"parameters":{"theme":"dark"}}` | `'-theme dark'` |
| `'-uri %uri%'` | `{}`（无 uri） | `'-uri %uri%'`（保留原文） |
| `'-key value'` | 任意 | `'-key value'`（无占位符，不变） |

### 5.4 支持的占位符 key

| 占位符 | 对应 payload JSON 路径 | 示例值 |
|--------|----------------------|--------|
| `%uri%` | `$.uri` | `file:///data/test.txt` |
| `%action%` | `$.action` | `ohos.want.action.viewData` |
| `%entities%` | `$.entities` | （数组序列化） |
| `%parameters.xxx%` | `$.parameters.xxx` | 任意值 |

---

## 6. Pascal ICmdLineParams 接口

### 6.1 获取方式

```pascal
var cmd: ICmdLineParams;
cmd := fpgApplication.CmdLineParams;
```

`CmdLineParams` 首次访问时创建 `TfpgOhosCmdLineParams.Create(OhosArgs, gLaunchParams)`，结果缓存。

### 6.2 方法一览

| 方法 | 说明 | 示例 |
|------|------|------|
| `HasOption(S)` | 检查是否有 `-S` 或 `S=xxx` | `HasOption('b')` 查找 `-b` |
| `HasOption(C, S)` | 同上（短字符 + 长选项） | `HasOption('b', 'debug')` |
| `GetOptionValue(S)` | 获取 `S=xxx` 中的 `xxx` | `GetOptionValue('theme')` → `'dark'` |
| `GetOptionValue(C, S)` | 同上（委托给 S 版本） | `GetOptionValue('t', 'theme')` |
| `GetOptionValues(C, S)` | 返回单元素数组 | `['dark']` |
| `Params[i]` | 获取第 i 个参数（原始值） | `Params[0]` → `'-style'` |
| `ParamCount` | 参数总数 | 返回 FItems.Count |
| `OptionChar` | 选项前导字符（默认 `'-'`） | 可读写 |
| `CaseSensitiveOptions` | 选项名是否区分大小写 | 默认 False |

### 6.3 数据源合并

`TfpgOhosCmdLineParams.Create(OhosArgs, gLaunchParams)` 将两个数据源合并到同一个 `FItems: TStringList`：

**来源 1 — OhosArgs**（按空格分割）：

```
FItems[0] = '-style'
FItems[1] = '-b'
FItems[2] = 'debug'
FItems[3] = 'theme=dark'
```

**来源 2 — gLaunchParams**（JSON 解析，`key=value` 格式追加）：

```
FItems[4] = 'uri=myapp://open'
FItems[5] = 'action=ohos.want.action.view'
FItems[6] = 'parameters.theme=dark'
```

---

## 7. 冷启动完整流程

```
1.  Ability.onCreate(want)
    │
    ├─ setLaunchPayload(want)
    │   └─ gLaunchPayload = buildLaunchPayload(want)  // JSON 序列化
    │
    ├─ gMergedArgs = buildMergedArgs(want)  // APP_ARGS + want.fpArgs
    │
2.  Index.ets.aboutToAppear()
    │
    ├─ fpbridge.setEtsReady()    → C++ g_etsReady = true
    │
    └─ fpbridge.start('helloworld', payload, mergedArgs)
           │
           │  [C++ Start() 创建 PascalThread]
           │
3.  PascalThread
    │
    ├─ resolvedArgs = replacePlaceholders(mergedArgs, payload)
    │   // 将 '-uri %uri% -theme %parameters.theme%'
    │   //   替换为 '-uri myapp://open -theme dark'
    │
    ├─ dlopen("libhelloworld.so")
    │
    ├─ g_inject_app_args(payload, resolvedArgs)
    │   │
    │   └─ [Pascal] ohos_inject_app_args()
    │       ├─ gLaunchParams := payload      // want JSON 原文
    │       └─ OhosArgs := resolvedArgs      // 已替换 %xxx% 的参数串
    │
    ├─ dlsym("MainProc") → pro()           // 或 main(argc, argv)
    │
4.  fp_bridge_init(version, pascalApi, cppApi)
    │
    ├─ g_pascal = *pascalApi               // 缓存所有 Pascal 导出函数
    ├─ g_inject_app_args = pascalApi.inject_app_args
    │
5.  应用代码
    │
    └─ cmd := fpgApplication.CmdLineParams
       // 创建 TfpgOhosCmdLineParams.Create(OhosArgs, gLaunchParams)
       // → 合并解析 → 统一通过 ICmdLineParams 访问
```

---

## 8. 热启动（onNewWant）流程

```
1.  Ability.onNewWant(want)
    │
    ├─ setLaunchPayload(want)
    │   │
    │   ├─ gLaunchPayload = buildLaunchPayload(want)
    │   │
    │   └─ fpbridge.setLaunchParams(payload)   // NAPI 调用
    │       │
    │       └─ [C++] OnSetLaunchParams()
    │           ├─ 如果 Pascal 未就绪：缓存到 g_pendingLaunchParams
    │           └─ 如果已就绪：调用 g_set_launch_params(payload)
    │               │
    │               └─ [Pascal] ohos_set_launch_params()
    │                   └─ EnqueueLaunchParamsEvent(payload)
    │                       │
    │                       └─ HandleLaunchParamsEvent (UI 线程)
    │                           ├─ gLaunchParams := payload  // 更新全局
    │                           └─ OnOhosLaunchParams(payload)  // 应用回调
    │
2.  注意：热启动不重新注入 OhosArgs（命令行参数不更新）
    │   CmdLineParams 已缓存，如需更新需重建
```

---

## 9. ETS 配置参考

### 9.1 FpAppConfig.ets

```typescript
// Pascal .so 库名（不含 lib 前缀和 .so 后缀）
export const APP_LIB_NAME: string = 'helloworld';

// 静态命令行参数（空格分隔）
// 支持：-b debug（短选项）、key=value（键值对）、混合
export const APP_ARGS: string = '-style';

// 动态参数的 want key 名
// 对应 want.parameters['fpArgs']
export const WANT_PARAM_ARGS: string = 'fpArgs';
```

### 9.2 启动调用（Index.ets）

```typescript
fpbridge.start(APP_LIB_NAME, getLaunchPayload(), getMergedArgs());
```

### 9.3 NAPI 类型声明（Index.d.ts）

```typescript
export const start: (
  appLibName: string,
  launchPayload?: string,   // want JSON，可选
  appArgs?: string          // 命令行参数，可选
) => void;
```

---

## 10. Pascal 应用接入示例

### 10.1 基本用法

```pascal
uses
  fpg_main, fpg_base, fpg_cmdlineparams, ...;

var
  cmd: ICmdLineParams;
begin
  fpgApplication.Initialize;

  cmd := fpgApplication.CmdLineParams;

  // 检查标志
  if cmd.HasOption('b') then
    EnableDebugMode;

  // 读取键值
  if cmd.GetOptionValue('theme') <> '' then
    ApplyTheme(cmd.GetOptionValue('theme'));

  if cmd.GetOptionValue('file') <> '' then
    OpenFile(cmd.GetOptionValue('file'));

  fpgApplication.Run;
end;
```

### 10.2 读取 Want JSON（完整载荷）

```pascal
var
  payload: string;
begin
  payload := gLaunchParams;  // 全局变量，存储 want JSON 原文
  if payload <> '' then
    WriteLn('Raw want payload: ', payload);
end;
```

### 10.3 注册热启动回调

```pascal
procedure OnHotLaunch(const APayload: string);
begin
  // APayload 是新的 want JSON
  // gLaunchParams 已自动更新
  WriteLn('Hot launch: ', APayload);
end;

initialization
  OnOhosLaunchParams := @OnHotLaunch;
end.
```

### 10.4 综合示例：文件打开应用

```pascal
procedure TForm1.HandleCmdLine;
var
  cmd: ICmdLineParams;
  uri, action, filePath, mode: string;
begin
  cmd := fpgApplication.CmdLineParams;

  // 从 OhosArgs 获取
  filePath := cmd.GetOptionValue('file');
  mode := cmd.GetOptionValue('mode');

  // 从 gLaunchParams 获取（JSON 原文）
  // 或通过占位符在 APP_ARGS 中引用：%uri% / %action%
  uri := cmd.GetOptionValue('uri');

  if filePath <> '' then
    DoOpenFile(filePath, mode)
  else if uri <> '' then
    DoOpenUri(uri)
  else
    ShowWelcome;
end;
```

---

## 11. API 参考

### 11.1 Pascal 导出函数

| 函数 | 签名 | 说明 |
|------|------|------|
| `ohos_inject_app_args` | `procedure(payload, appArgs: PChar); cdecl; export` | 冷启动注入：设置 gLaunchParams + OhosArgs |
| `ohos_set_launch_params` | `procedure(payload: PChar); cdecl; export` | 热启动注入：更新 gLaunchParams + 触发 OnOhosLaunchParams 回调 |

### 11.2 Pascal 全局变量

| 变量 | 类型 | 说明 |
|------|------|------|
| `OhosArgs` | `string` | 命令行参数（已替换 %placeholder%），空格分隔 |
| `gLaunchParams` | `string` | want JSON 原文 |
| `OnOhosLaunchParams` | `procedure(const APayload: string)` | 热启动回调（UI 线程） |

### 11.3 C++ 桥接结构（fp_bridge.h）

```c
typedef struct {
    int32_t version;
    // ... 其他字段 ...
    void* set_launch_params;     // → ohos_set_launch_params
    void* inject_app_args;       // → ohos_inject_app_args
    // ...
} FpBridgePascalApi;
```

### 11.4 ETS 函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `buildLaunchPayload(want)` | Fp_bridgeAbility.ets | 将 Want 序列化为 JSON |
| `buildMergedArgs(want)` | Fp_bridgeAbility.ets | 合并 APP_ARGS + want.fpArgs |
| `setLaunchPayload(want)` | Fp_bridgeAbility.ets | 存储 + 热启动推送到 C++ |
| `getLaunchPayload()` | Fp_bridgeAbility.ets | 获取当前 payload JSON |
| `getMergedArgs()` | Fp_bridgeAbility.ets | 获取当前合并后参数 |

---

## 12. FAQ / 常见问题

### Q: `%uri%` 占位符没有替换，保留了原文？

**A**: payload JSON 中没有 `uri` 字段（want 未携带 uri）。检查 `want.uri` 是否为空。

### Q: 热启动时 OhosArgs 会更新吗？

**A**: 不会。热启动只更新 `gLaunchParams`（want JSON）。`OhosArgs` 仅在冷启动时注入。如需热启动传递参数，使用 `want.parameters` 并通过 `OnOhosLaunchParams` 回调解析。

### Q: 如何在应用中区分冷启动和热启动？

**A**: 在 `OnOhosLaunchParams` 回调中处理热启动（该回调仅在 `onNewWant` 时触发）。冷启动时该回调不触发。

### Q: APP_ARGS 中的空格会怎么处理？

**A**: C++ 层按空格分割 resolvedArgs 构建 `argv[]`；Pascal 层 `TfpgOhosCmdLineParams` 按空格分割存入 `FItems`。每个独立项成为一个参数。

### Q: parameters 是嵌套对象时怎么读取？

**A**: `ParsePayload` 支持一级嵌套，生成 `key.subkey=value` 格式。如 `{"parameters":{"theme":"dark"}}` → `parameters.theme=dark`。应用用 `GetOptionValue('parameters.theme')` 读取。

### Q: `ICmdLineParams.HasOption` 和 `GetOptionValue` 的区别？

**A**: `HasOption('b')` 检查是否有 `-b` 这个标志（不关心值）；`GetOptionValue('theme')` 查找 `theme=xxx` 并返回 `xxx`。

### Q: 如何传递多 word 的值（含空格）？

**A**: 当前设计不支持单个值内含空格（空格是分隔符）。建议用 `_` 代替空格，或使用 URL 编码。

---

## 附录：文件清单

| 文件 | 路径 | 角色 |
|------|------|------|
| FpAppConfig.ets | `ets/common/FpAppConfig.ets` | 常量定义 |
| Fp_bridgeAbility.ets | `ets/fp_bridgeability/Fp_bridgeAbility.ets` | Want 处理、参数合并 |
| Index.ets | `ets/pages/Index.ets` | 启动调用 |
| Index.d.ts | `cpp/types/libfp_bridge/Index.d.ts` | NAPI 类型声明 |
| napi_init.cpp | `cpp/napi_init.cpp` | C++ 桥接核心 |
| fp_bridge.h | `cpp/fp_bridge.h` | C 桥接 ABI 定义 |
| fpg_ohos.pas | `pascal/corelib/ohos/fpg_ohos.pas` | Pascal 参数实现 |
| fpg_cmdlineparams.pas | `pascal/corelib/fpg_cmdlineparams.pas` | ICmdLineParams 接口定义 |
