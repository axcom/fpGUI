# fpGUI HarmonyOS GL 界面绘制

> 适用范围：fpGUI 2.1.0 / HarmonyOS (OHOS) 后端
> 相关构建开关：`-dGLPresenter`（Phase 1）、`-dGLBackend`（Phase 2）
> 文档日期：2026-11-12

---

## 1. 概述

本次修改把 fpGUI 在 HarmonyOS 上的**最终上屏与控件绘制**从软件位图路径切换为 EGL/GLES 渲染，同时保留完整软件回退。工作分为两个阶段：

| 阶段 | 开关 | 内容 | 上屏方式 |
|---|---|---|---|
| Phase 1 | `-dGLPresenter` | 保留原软件画布（native_drawing / AggPas），只替换最后一步 | CPU 像素 → GL 纹理 → 全屏四边形 → `eglSwapBuffers` |
| Phase 2 | `-dGLBackend` | 新增 `TfpgGLCanvas`，所有控件直接用 GL 绘制到每窗口 FBO | FBO → 全屏四边形 → `eglSwapBuffers` |

约束：**开启 `GLBackend` 时一定同时开启 `GLPresenter`**（由 `fpg_defines.inc` 自动保证），因此两阶段共用同一套 EGL 窗口、首帧通知与 hide/show 生命周期。

默认（不加开关仅启用 GLPresenter）；EGL/GLES 初始化失败时会自动回退，仍走原软件路径。

---

## 2. 构建开关与后端选择

### 2.1 开关

| 开关 | 效果 |
|---|---|
| 无 | 软件画布：定义了 `AggCanvas` 时用 `TOhosHybridCanvas`，否则 `TfpgOhosCanvas` |
| `-dGLPresenter` | 软件画布 + Phase 1 GL 上屏（`TfpgOhosCanvas.DoPutBufferToScreen` → `TryPresentGL`） |
| `-dGLBackend` | 自动定义 `GLPresenter`；画布切换为 `TfpgGLCanvas`（Phase 2） |

### 2.2 选择逻辑（`fpg_interface.pas`）

```pascal
{$ifdef GLBackend}
  if TfpgOhosGLDisplay.Instance.TryInitialize then
  begin
    DefaultCanvasClass   := TfpgGLCanvas;
    AggFontResourceClass := TfpgOhosAggFontResource;
  end
  else
  begin
    { EGL/GLES 不可用：保留软件后端 }
    {$ifdef AGGCanvas}
    DefaultCanvasClass   := TOhosHybridCanvas;
    CreateBufferManager  := @CreateOhosBufferManager;
    AggFontResourceClass := TfpgOhosAggFontResource;
    {$else}
    DefaultCanvasClass   := TfpgOhosCanvas;
    {$endif}
  end;
{$endif}
```

### 2.3 构建命令

```bat
rem Phase 2（推荐）：GLBackend 会自动启用 GLPresenter
set FPCEXTRA=-dGLBackend
build.bat x86_64 helloworld.lpr
build.bat arm64-v8a helloworld.lpr
```

---

## 3. 总体架构与渲染流程

```
应用 TfpgCanvas 调用
        │
        ▼
TfpgGLCanvas（Phase 2 画布）
  ├─ 纯色/渐变/三角形/线段/多边形/文字/图片
  ├─ 子控件共享父窗口 FBO，用 glScissor 裁剪
  └─ 图元由 TfpgOhosGLDraw 立即模式绘制
        │
        ▼
TfpgOhosGLWindow（每 OHNativeWindow 一个）
  ├─ EGLSurface / EGLContext
  ├─ FBO：RGBA8 颜色 + STENCIL8
  └─ PresentTexture：FBO 纹理 → 全屏四边形 → eglSwapBuffers
        │
        ▼
屏幕
```

Phase 1 的 `TfpgOhosGLPresenter` 则把软件画布产出的 CPU 像素上传为纹理，再走同一个 `TfpgOhosGLWindow` 上屏。

---

## 4. 文件清单

### 4.1 新增单元（`framework/src/main/pascal/corelib/ohos/`）

| 文件 | 作用 |
|---|---|
| `fpg_ohos_egl.pas` | EGL / GLES 常量与函数绑定 |
| `fpg_ohos_gl.pas` | `TfpgOhosGLDisplay`（EGL 初始化、能力探测）、`TfpgOhosGLWindow`（EGLSurface、FBO、present 着色器） |
| `fpg_ohos_gl_shaders.pas` | present / solid / textured 着色器源码（ES3 与 ES2 两套） |
| `fpg_ohos_gl_iface.pas` | 平台层与 GL 层之间的窗口生命周期事件接口（避免循环引用） |
| `fpg_ohos_gl_presenter.pas` | Phase 1 presenter：CPU 缓冲 → 纹理 → 全屏四边形 → swap |
| `fpg_ohos_gl_draw.pas` | Phase 2 立即模式绘制助手：纯色/渐变/纹理四边形、三角形、线段、模板缓冲多边形、像素读写、同窗口 CopyRect |
| `fpg_ohos_gl_text.pas` | 文本 Run 纹理缓存（复用 `DrawTextToBuffer`） |
| `fpg_ohos_gl_texture.pas` | `TfpgImageBase` → RGBA 纹理缓存（支持 mask 与 `Generation` 失效） |
| `fpg_ohos_gl_canvas.pas` | `TfpgGLCanvas`（Phase 2 全局 GL 画布）+ 每窗口 GL 窗口注册表 |

### 4.2 修改文件

| 文件 | 修改 |
|---|---|
| `corelib/fpg_defines.inc` | `GLBackend` 自动 `{$define GLPresenter}` |
| `corelib/ohos/fpg_interface.pas` | `GLBackend` 选择 `TfpgGLCanvas`；EGL 失败回退；注册 `TfpgOhosAggFontResource` |
| `corelib/fpg_base.pas` | `TfpgImageBase` 增加 `Generation` 与轻量 `Invalidate`；`UpdateImage` 复用 `Invalidate` |
| `corelib/ohos/fpg_ohos.pas` | 接入：`DoPutBufferToScreen` 中 `TryPresentGL`；resize/show/hide/destroy 时 `NotifyGLWindow`；首帧通知 `GLNotifyFirstFrame` |

---

## 5. 关键实现说明

### 5.1 每窗口 FBO 与子控件裁剪

- 每个 `OHNativeWindow` 对应一个 `TfpgOhosGLWindow`，内部持有：
  - `FBO`（`GL_RGBA8` + `GL_STENCIL_INDEX8`）
  - 颜色纹理 `ColorTexture`（用于上屏）
- 顶层窗口把整个窗口绘制到自己的 FBO；**子控件共享父窗口 FBO**，通过 `glScissor` 限定绘制区域，因此 fpGUI 的 alien-widget（虚拟子控件）模型无需改动。
- 每个绘制入口都会重新应用当前 canvas 的裁剪，避免子控件裁剪泄漏到父控件。

### 5.2 坐标系契约（重要）

这是 Phase 2 最容易踩坑的地方，已修复并固定为契约：

1. **`GetClipRect` 必须返回控件本地坐标**（与软件画布一致）。
   - `TfpgBaseTextEdit.HandlePaint` 用 `GetClipRect.Top/Left` 计算文本基线与光标位置。
   - 若返回窗口坐标，文字会被画到控件下方并被 `glScissor` 裁掉，表现为“编辑框空白、无光标、无法录入”。
   - 现实现：`FClipRect` 存本地坐标，仅在 `UpdateScissor` 中偏移 `FDeltaX/FDeltaY` 再转 FBO 坐标。

2. **`ReadPixel` / `CopyRect` 必须对逻辑坐标应用 `gHiDPIScaleFactor`**。
   - 绘制层（`NdcX/NdcY`、`DrawSolidQuad`）已缩放；若 readback 用原始逻辑坐标，XOR 读回与写入会落在不同物理像素。
   - 症状：光标可见但**不闪烁**（XOR 永远读回同一像素）。
   - 修正后 XOR 在黑白之间交替，每 500 ms 触发一次 `GL Present`。

### 5.3 文字渲染

- 复用现有 `TfpgFontResourceBase.DrawTextToBuffer`（OHOS 上是 `TfpgOhosAggFontResource`，支持 CJK/emoji 回退）。
- `DrawTextToBuffer` 输出 RGB 覆盖率但不写 alpha（原本面向不透明缓冲）。文本缓存把 RGB 覆盖率转成 alpha，并把 RGB 置白，供着色器用当前文字色 tint。
- Phase 3 已改为**字形图集**：每个 UTF-8 码点渲染一次到共享 RGBA 图集（白色 RGB + 覆盖率 alpha）；文本 Run 变成每字形一个 quad，全部共享图集纹理，配合批处理一次 draw call。

### 5.4 图片渲染

- `TfpgImageBase` 内部为 `$AARRGGBB`；纹理缓存转换为 RGBA8888。
- 1-bit mask：mask 位为 0 时 alpha=0。
- `TfpgImageBase.Generation` 在 `UpdateImage`/`AllocateImage`/`FreeImage`/`SetColor`/`Invalidate` 时递增，纹理缓存据此失效。
- **直接修改 `ImageData` 的应用**（如终端网格）在修改后必须调用 `Invalidate`（轻量，只递增代数）或 `UpdateImage`（会同步原生位图）。
- 非 32 位（8/16/24）图片通过 `Colors[x,y]` 统一转换；同尺寸内容变化用 `glTexSubImage2D` 原地更新；`UpdateImageRegion` 支持脏矩形局部上传。

### 5.5 窗口生命周期

- `gleResize`：更新 EGLSurface 尺寸并重建 FBO。
- `gleHide` / `gleDestroy`：`Suspend`（不立即释放 GL 窗口，避免 canvas 持有已释放的窗口）。
- `GetOrCreateGLWindow`：窗口非 `glsReady` 时调用 `Recover` 重建 EGLSurface/FBO，并清空文本/图片纹理缓存（上下文丢失恢复）。
- 首帧成功 `eglSwapBuffers` 后通过 `GLNotifyFirstFrame` 通知平台，消除 XComponent 黑屏闪现。

### 5.6 回退机制

- `TfpgOhosGLDisplay.TryInitialize` 失败 → `DefaultCanvasClass` 保持软件画布。
- `TryPresentGL` 返回 False 时继续走原 `RequestBuffer/mmap/memcpy/FlushBuffer` 路径。
- 非 32 位图片已由纹理缓存统一转换；仅当 `GetTexture` 返回 0（无 `ImageData`）时才回退基类。
- 跨窗口 `CopyRect` 已通过共享 EGL 上下文 + 纹理中转实现；仅在源不是 GL canvas 时回退基类。

---

## 6. 应用开发指南

### 6.1 应用代码是否需要改？

**普通应用不需要改**。`TfpgCanvas` 的公开接口保持不变，控件、样式、布局、事件代码无需调整；只需用 `-dGLBackend` 重新编译。

### 6.2 推荐构建

```bat
set FPCEXTRA=-dGLBackend
build.bat x86_64 helloworld.lpr
build.bat arm64-v8a helloworld.lpr
```

部署后可通过 hilog 过滤 `fpGUI-GL` 确认：

```
EGL 1.5 ES3=True GL=OpenGL ES 3.2 renderer=Mali-G77
```

### 6.3 设备尺寸位图（终端类应用）

如果应用把内容烘焙成一张**物理尺寸**（`gHiDPIScaleFactor`）的 `TfpgImage`，再整张贴到画布：

- ✅ 使用 `Canvas.StretchDraw(0, 0, 逻辑宽, 逻辑高, Img)`：
  整图映射到逻辑矩形，GL 层再缩放到物理尺寸（`DevScale == gHiDPIScaleFactor` 时 1:1）。
- ❌ 不要用 `Canvas.DrawImagePart(0,0,Img,0,0,逻辑宽,逻辑高)`：
  GL 画布会把参数当逻辑尺寸并据此计算 UV，只采样到图片左上 `1/DevScale`。
- 原地修改 `ImageData` 后，调用 `Img.Invalidate`（或 `UpdateImage`）让纹理缓存重新上传。

示例（终端 `BlitGrid`）：

```pascal
if Canvas.ClassName = 'TfpgGLCanvas' then
begin
  Canvas.StretchDraw(0, 0, FGridW, FGridH, FGridImage);
  Exit;
end;
```

### 6.4 注意事项

| 场景 | 建议 |
|---|---|
| 光标 XOR / 取色 | `XORFillRectangle`/`GetPixel`/`SetPixel` 走 FBO readback，仅适合小区域（光标） |
| 大区域滚动 | 同窗口 `CopyRect` 有快速路径；跨窗口会回退逐像素 |
| 频繁更新的整图 | 目前整图重传纹理；大图高频刷新建议等待 Phase 3 的局部更新 |
| 线型 | dash/dot 目前按实线绘制 |
| 透明窗口 | 暂未实现 |

---

## 7. 验证结果

环境：x86_64 模拟器（EGL 1.5 / GLES 3.2 / Mali-G77），`-dGLBackend`。

| 测试程序 | 验证内容 | 结果 |
|---|---|---|
| `examples/apps/docedit` | 主窗口、菜单栏、弹出菜单、文件对话框、Options 子窗口、文字/图片/列表 | 正常 |
| `examples/gui/customwindow` | 树、表格、按钮、`TfpgFileNameEdit`：初始文本、焦点、光标闪烁、键盘输入 | 正常 |
| 终端模拟器 | toybox 提示、绿色提示符、`ls -l` 输出、输入回显、块状光标 | 正常 |

补充：

- 光标每 500 ms 在黑白间切换并上屏（hilog 可见 XOR 交替 + `GL Present`）。
- 默认构建、`-dGLPresenter`、`-dGLBackend`（x86_64 + arm64-v8a）均编译通过。
- 未发现崩溃或黑屏；resize / hide-show 由 GL 窗口注册表重建 FBO。

---

## 8. 已知限制与后续计划（Phase 3）

## 8. Phase 3 实施记录

已实现：

| 项 | 实现 |
|---|---|
| 顶点批处理 | `TfpgOhosGLDraw` 累积顶点，按 program/纹理/scissor 状态变化或容量（4096 顶点）一次性 `glBufferData` + `glDrawArrays` |
| 字形图集 | `fpg_ohos_gl_text.pas` 重写为共享 RGBA 图集；每字形一个 quad，全部共享图集纹理 |
| 线型 | `TfpgGLCanvas.DrawStyledLine` 支持 `lsDash`/`lsDot`/`lsDashDot`/`lsDashDotDot` |
| 跨窗口 CopyRect | 共享 EGL 上下文下把源 FBO 复制到临时纹理，再画到目标 FBO |
| 非 32 位图片 | 纹理缓存通过 `Colors[x,y]` 统一转换为 RGBA |
| 纹理缓存 | 上限可配置（`GLTextureCacheLimit`，默认 512）；同尺寸内容变化用 `glTexSubImage2D` 原地更新 |
| 脏矩形上传 | `TfpgCanvasBase.UpdateImageRegion` → `GLTextureCache.UpdateRegion`；终端按脏行调用 |
| 上下文丢失恢复 | `TfpgOhosGLWindow.Recover` 重建 surface/FBO，并清空文本/图片纹理缓存 |
| VSync 提交合并 | `DoPutBufferToScreen` 只标记 pending；消息泵每轮通过 `GLFlushPresents` 统一上屏一次 |
| 非阻塞交换 | `GLVSyncEnabled`（默认 True）控制 `eglSwapInterval` |

暂未实现（及原因）：

- **桌面 GL 4.2**：暂不实现。
- **多线程 Present**：EGL 上下文与 UI 线程绑定，跨线程 present 需要上下文乒乓或双上下文，风险高；当前用“合并上屏 + 可选非阻塞交换（`GLVSyncEnabled := False`）”达到等效的低延迟目标。
- **透明窗口**：EGL 配置已带 `EGL_ALPHA_SIZE=8`，GL 侧 FBO 也是 RGBA8；但窗口属性 `waTransparent` 需要 ETS/ArkUI 侧配合（XComponent 背景与合成），当前桥接工程未实现，暂缓。

---

## 9. 常见问题（FAQ）

**Q1：开启 `-dGLBackend` 后界面空白/黑屏？**
先确认 hilog 有 `EGL ... ES3=True GL=...`。若没有，说明 EGL 初始化失败，程序已回退软件路径；检查 HAP 的 XComponent/OHNativeWindow 是否正常创建。

**Q2：终端/自绘大图只显示左上角一块？**
设备尺寸位图不要用 `DrawImagePart` 传逻辑尺寸，改用 `StretchDraw`（整图 → 逻辑矩形），并在原地改像素后调用 `Invalidate`。

**Q3：如何回到纯软件渲染？**
去掉所有 GL 开关（GLBackend、GLPresenter）重新编译即可；或在运行时让 EGL 初始化失败自动回退。

注：在非GL模式，局部刷新时，PutBufferToScreen只拷贝修改的区域到NativeWindow buffer。但OHOS的多缓冲机制意味着每次RequestBuffer可能拿到不同的buffer，而新buffer的其他区域可能包含旧内容（上次提交的内容）。当光标闪烁（XOR操作）时，如果新buffer的字符区域没有被正确同步，会导致字符也跟着闪烁。

---

