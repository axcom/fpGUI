# fpGUI 完整开发参考手册

> **版本**: 基于 fpGUI 2.1.0 源码
> **语言**: Free Pascal (FPC) / Object Pascal
> **源码路径**: `framework/src/main/pascal/`
> **手册语言**: 中文叙述 + Pascal 代码 + 中文注释
> **最后更新**: 2026-09-01
>

---

## 目录

- [模块1：fpGUI 框架基础概述](#模块1fpgui-框架基础概述)
  - [1.1 fpGUI 简介、特性、优势与适用场景](#11-fpgui-简介特性优势与适用场景)
  - [1.2 fpGUI 与 Lazarus LCL 的区别与选型建议](#12-fpgui-与-lazarus-lcl-的区别与选型建议)
  - [1.3 开发环境搭建（Free Pascal + fpGUI 安装、配置、编译）](#13-开发环境搭建free-pascal--fpgui-安装配置编译)
  - [1.4 首个 fpGUI 窗口程序（helloworld.lpr）](#14-首个-fpgui-窗口程序helloworldlpr)
  - [1.5 核心运行机制、窗体生命周期与消息机制](#15-核心运行机制窗体生命周期与消息机制)
  - [1.6 Lazarus IDE 集成与配置](#16-lazarus-ide-集成与配置)
  - [1.7 自带工具与配套应用](#17-自带工具与配套应用)
- [模块2：全局基础通用规范](#模块2全局基础通用规范)
  - [2.1 基础数据类型](#21-基础数据类型)
  - [2.2 通用常量（命名颜色 / 键盘常量）](#22-通用常量命名颜色--键盘常量)
  - [2.3 枚举类型（TAlign / TLayout / TAnchor / TMouseButton / TWindowState / TWindowType / TArrowDirection）](#23-枚举类型)
  - [2.4 Shift state flags](#24-shift-state-flags)
  - [2.5 统一命名规范、组件使用规范、编码规范](#25-统一命名规范组件使用规范编码规范)
  - [2.6 窗口、画布、颜色、字体、坐标系统通用规则](#26-窗口画布颜色字体坐标系统通用规则)
  - [2.7 全局函数](#27-全局函数)
  - [2.8 异常处理、日志与调试方法](#28-异常处理日志与调试方法)
  - [2.9 国际化与多语言支持（编译时/运行时）](#29-国际化与多语言支持编译时运行时)
  - [2.10 命令行参数解析与命令模式](#210-命令行参数解析与命令模式)
  - [2.11 布局管理器（MigLayout / FlowLayout / BorderLayout）](#211-布局管理器miglayout--flowlayout--borderlayout)
- [模块3：核心基础组件全解](#模块3核心基础组件全解)
  - [3.1 窗口 — TfpgWindowBase / TfpgWindow / TfpgBaseForm / TfpgForm](#31-窗口--tfpgwindowbase--tfpgwindow--tfpgbaseform--tfpgform)
  - [3.2 文本 — TfpgLabel / TfpgEdit / TfpgEditInteger / TfpgEditFloat / TfpgMemo / TfpgSpinEdit / TfpgEditButton / TfpgEditCombo / TfpgHyperlink](#32-文本)
  - [3.3 按钮 — TfpgButton / TfpgSpeedButton / TfpgCheckBox / TfpgRadioButton / TfpgToggle](#33-按钮)
  - [3.4 选择 — TfpgComboBox / TfpgListBox / TfpgColorListBox / TfpgListView / TfpgTreeView / TfpgStringGrid / TfpgFileGrid / TfpgHexView](#34-选择)
  - [3.5 容器 — TfpgPanel / TfpgGroupBox / TfpgBevel / TfpgFrame / TfpgPageControl / TfpgScrollBar / TfpgScrollFrame / TfpgSplitter](#35-容器)
  - [3.6 弹窗 — TfpgMessageBox / TfpgMessageDialog / TfpgOpenDialog / TfpgSaveDialog / TfpgSelectFolderDialog / TfpgColorDialog / TfpgFontDialog / TfpgPromptDialog](#36-弹窗)
  - [3.7 进度状态 — TfpgProgressBar / TfpgGauge / TfpgTrackBar / TfpgMenuBar / TfpgPopupMenu / TfpgMenuItem / TfpgSystemTrayIcon](#37-进度状态)
  - [3.8 图像绘图 — TfpgImage / TfpgCanvas / TfpgPaintBox 替代方案](#38-图像绘图)
  - [3.9 时间日期 — TfpgCalendar / TfpgPopupCalendar / TfpgDateTimePicker 替代方案](#39-时间日期)
  - [3.10 拓展 — TfpgHintWindow / TfpgAnimation / TfpgLEDMatrix / TfpgColorWheel / TfpgReadOnly / TfpgImgAnim / TfpgFileNameEdit](#310-拓展)
- [模块4：组件属性详细说明（统一规范）](#模块4组件属性详细说明统一规范)
  - [4.1 通用属性统一汇总](#41-通用属性统一汇总)
  - [4.2 属性数据类型系统](#42-属性数据类型系统)
  - [4.3 通用属性命名与读写模式](#43-通用属性命名与读写模式)
  - [4.4 通用属性跨组件参照表](#44-通用属性跨组件参照表)
- [模块5：方法与函数详细说明（核心重点）](#模块5方法与函数详细说明核心重点)
  - [5.1 组件生命周期方法](#51-组件生命周期方法)
  - [5.2 刷新重绘方法](#52-刷新重绘方法)
  - [5.3 焦点方法](#53-焦点方法)
  - [5.4 位置尺寸方法](#54-位置尺寸方法)
  - [5.5 数据操作方法（剪贴板 / 列表 / 文本）](#55-数据操作方法剪贴板--列表--文本)
  - [5.6 对话框方法与函数](#56-对话框方法与函数)
  - [5.7 文件操作方法](#57-文件操作方法)
  - [5.8 绘图方法（TfpgCanvas）](#58-绘图方法tfpgcanvas)
  - [5.9 全局工具函数](#59-全局工具函数)
  - [5.10 便捷工厂函数](#510-便捷工厂函数)
- [模块6：事件机制详解](#模块6事件机制详解)
  - [6.1 事件运行原理（消息派发链）](#61-事件运行原理消息派发链)
  - [6.2 所有组件事件统一参考](#62-所有组件事件统一参考)
  - [6.3 事件参数类型签名](#63-事件参数类型签名)
  - [6.4 事件触发时机](#64-事件触发时机)
  - [6.5 事件绑定 / 解绑 / 自定义事件](#65-事件绑定--解绑--自定义事件)
  - [6.6 实战代码示例（参考 examples/corelib/eventtest）](#66-实战代码示例参考-examplescorelibeventtest)
- [模块7：实战案例与常见问题汇总](#模块7实战案例与常见问题汇总)
  - [7.1 常用功能实战案例](#71-常用功能实战案例)
  - [7.2 布局适配、窗口缩放、控件居中、自适应方案](#72-布局适配窗口缩放控件居中自适应方案)
  - [7.3 常见报错、编译错误、运行异常解决方案](#73-常见报错编译错误运行异常解决方案)
  - [7.4 性能优化、界面卡顿解决、内存优化](#74-性能优化界面卡顿解决内存优化)
  - [7.5 开发避坑总结](#75-开发避坑总结)
- [附录](#附录)
  - [A. 完整组件清单](#a-完整组件清单)
  - [B. 源码文件索引](#b-源码文件索引)
  - [C. 示例项目索引](#c-示例项目索引)

---

## 模块1：fpGUI 框架基础概述

### 1.1 fpGUI 简介、特性、优势与适用场景

fpGUI 是一个基于 Free Pascal 的跨平台 GUI 工具包，采用 LGPL 授权。它不依赖任何外部 GUI 库（如 GTK、Qt、Win32 原生控件），而是自行绘制所有界面元素，因此在不同平台上具有完全一致的外观和行为。

**核心特性**：

- 完全用 Object Pascal 编写，支持 FPC 编译器
- 跨平台支持：Windows、Linux (X11)、macOS (Cocoa)、OHOS (鸿蒙) 等
- 自绘式渲染引擎（支持原生 Canvas 和 AGG Canvas 两种模式）
- 组件化设计，支持事件驱动编程模型
- 内置布局管理器（Align 锚点 + MigLayout 网格布局 + BorderLayout + FlowLayout）
- 支持自定义样式（Style）系统（Fusion/Carbon/Motif/Plastic/Win2k/Win8）
- 内置 HVIF 矢量图标支持、PNG/BMP/JPG 图像格式
- 国际化支持（PO 文件翻译）、HiDPI 缩放支持
- 完整的命令模式（ICommand）与拖放支持

**适用场景**：

- 需要跨平台一致 UI 的桌面工具/编辑器/查看器
- 嵌入式 / OHOS 等无原生控件环境下的图形界面
- 与 Free Pascal / Lazarus 工具链深度集成的应用
- 对自绘风格、自定义主题有强需求的桌面程序

### 1.2 fpGUI 与 Lazarus LCL 的区别与选型建议

| 维度 | fpGUI | Lazarus LCL |
|------|-------|-------------|
| 渲染方式 | 自绘（Canvas/AGG） | 包装原生控件（Win32/Gtk/Qt） |
| 跨平台一致性 | 完全一致 | 各平台外观有差异 |
| 依赖 | 仅 Free Pascal + 平台底层 API | 同上，但依赖更多原生库 |
| 控件数量 | 较精简，覆盖常用控件 | 极丰富，包罗万象 |
| 布局能力 | Align + Anchors + MigLayout | Anchors + 多种布局控件 |
| 样式系统 | 完全可定制（fpgStyle） | 主题/风格有限 |
| 学习曲线 | 中等，需理解消息机制 | 平缓，类似 Delphi VCL |
| 集成 IDE | 自带 uidesigner | Lazarus IDE |

**选型建议**：

- 需要原生平台外观、海量现成控件 → 选 LCL
- 需要完全一致的跨平台 UI、自定义视觉、自绘控件、嵌入式环境 → 选 fpGUI
- 二者可同时安装于同一 FPC 环境，互不冲突

### 1.3 开发环境搭建（Free Pascal + fpGUI 安装、配置、编译）

**步骤一：安装 Free Pascal 编译器**

下载并安装 FPC（推荐 3.2.2 或更高版本）。Windows 下安装时勾选"Add to PATH"。

**步骤二：获取 fpGUI 源码**

获取 fpGUI 2.1.0 源码包并解压，例如 `D:\fpcupdeluxe34_new\fpGUI-2.1.0\`。源码目录结构：

```
fpGUI-2.1.0/
├── framework/src/main/pascal/
│   ├── corelib/        — 核心库（fpg_base/fpg_main/fpg_widget 等）
│   └── gui/           — 控件库（fpg_form/fpg_button 等）
├── examples/          — 示例工程
│   ├── corelib/       — 核心库示例
│   └── gui/           — 控件示例
├── docs/              — 文档
├── ide/               — 集成设计器
└── tools/             — 辅助工具
```

**步骤三：编译 fpGUI 框架**

进入 `framework/` 目录，使用 fpGUI 自带构建脚本或直接使用 fpc 编译单元。最简方式是直接编译示例工程，FPC 会自动定位单元路径。

**步骤四：编译最小 uses 列表**

```pascal
uses
  Classes,        // 基础类库
  fpg_base,       // 核心类型定义
  fpg_main,       // 应用程序类、Canvas、Style
  fpg_form;       // 窗口/表单
```

**步骤五：常用编译指令**

```pascal
{$mode objfpc}{$H+}          // 使用 objfpc 模式，启用 AnsiString
{$I fpg_defines.inc}         // 包含 fpGUI 平台条件编译定义
```

**步骤六：编译并运行示例**

```
cd examples\gui\helloworld
fpc -MObjFPC -Sh helloworld.lpr
helloworld   (Windows)  或  ./helloworld  (Linux/macOS)
```

> **避坑:** 必须先编译/链接 fpGUI 单元后再编译用户工程；若 FPC 报"unit not found"，将 `framework/src/main/pascal/corelib` 与 `framework/src/main/pascal/gui` 加入 `-Fu` 单元搜索路径。

### 1.4 首个 fpGUI 窗口程序（helloworld.lpr）

以下代码来自 `examples/gui/helloworld/helloworld.lpr`，是一个完整可编译的 fpGUI 程序：

```pascal
program helloworld;

{$mode objfpc}{$H+}

uses
  Classes,
  fpg_base,
  fpg_main,
  fpg_form,
  fpg_button;

type

  { THelloWorldForm }

  THelloWorldForm = class(TfpgForm)
    procedure ButtonClick(Sender: TObject);
  private
    Button: TfpgButton;
  public
    procedure AfterCreate; override;
  end;

procedure MainProc;
var
  frm: THelloWorldForm;
begin
  fpgApplication.Initialize;          // 初始化 fpGUI 运行时
  frm := THelloWorldForm.Create(nil); // 创建主窗口
  try
    frm.Show;                         // 非模态显示窗口
    fpgApplication.Run;               // 进入消息循环
  finally
    frm.Free;                         // 释放窗口
  end;
end;

{ THelloWorldForm }

procedure THelloWorldForm.ButtonClick(Sender: TObject);
begin
  Close;                              // 关闭窗口，退出消息循环
end;

procedure THelloWorldForm.AfterCreate;
begin
  inherited AfterCreate;
  Width := 300;                       // 窗口宽度
  Height := 200;                      // 窗口高度
  WindowTitle:='Hello World!';        // 窗口标题
  Button := TfpgButton.Create(Self);  // 创建按钮，Self 为所有者
  Button.Text:='Hello World!';        // 按钮文本
  Button.ShowHint:=True;              // 启用提示
  Button.Hint:='Click to Quit';       // 提示文本
  Button.Align:=alClient;             // 填充整个客户区
  Button.OnClick:=@ButtonClick;       // 绑定点击事件
end;

begin
  MainProc;
end.
```

**要点解析**：

| 步骤 | 说明 |
|------|------|
| `fpgApplication.Initialize` | 初始化底层平台（创建窗口系统、字体管理器等） |
| `TfpgForm.Create(nil)` | 构造函数创建窗口，`nil` 表示无所有者 |
| `AfterCreate` | 虚方法，在窗口构造完成后调用，用于初始化子控件 |
| `frm.Show` | 显示窗口（非模态） |
| `fpgApplication.Run` | 进入消息循环，阻塞直到所有窗口关闭 |
| `Button.OnClick := @ButtonClick` | Pascal 使用 `@` 取方法地址赋值给事件属性 |

### 1.5 核心运行机制、窗体生命周期与消息机制

**架构总览**：

```
fpGUI 架构层次
├── CoreLib (核心库)
│   ├── fpg_base.pas        — 基础类型、消息常量、键盘定义
│   ├── fpg_main.pas        — 应用程序类、Canvas、Style、Timer 等
│   ├── fpg_impl.pas        — 平台抽象接口 (Impl 模式)
│   ├── fpg_widget.pas      — 所有控件的基类 TfpgWidget
│   ├── fpg_fontmanager.pas — 字体管理
│   ├── keys.inc            — 键盘扫描码定义
│   └── predefinedcolors.inc— 系统与 HTML 颜色常量
├── GUI (控件库)
│   ├── fpg_form.pas        — 窗口/表单
│   ├── fpg_button.pas      — 按钮
│   ├── fpg_label.pas       — 标签
│   ├── fpg_edit.pas        — 单行文本编辑
│   ├── fpg_memo.pas        — 多行文本编辑
│   ├── fpg_panel.pas       — 面板/分组框/斜面
│   ├── fpg_tab.pas         — 页面控件
│   ├── fpg_listview.pas    — 列表视图
│   ├── fpg_tree.pas        — 树视图
│   ├── fpg_grid.pas        — 网格/表格
│   ├── fpg_menu.pas        — 菜单
│   ├── fpg_dialogs.pas     — 标准对话框
│   └── ...                 — 更多控件
└── Layout (布局库)
    ├── fpg_miglayout.pas   — MigLayout 布局管理器
    └── fpg_layouttypes.pas — 布局类型定义
```

**应用程序生命周期（标准五步）**：

```pascal
procedure MainProc;
var
  frm: TfpgForm;
begin
  // 第一步：初始化运行时
  fpgApplication.Initialize;

  // 第二步：创建主窗口
  frm := TfpgForm.Create(nil);
  try
    // 第三步：显示窗口
    frm.Show;

    // 第四步：进入消息循环（阻塞）
    fpgApplication.Run;

  finally
    // 第五步：清理资源
    frm.Free;
  end;
end;
```

**窗体生命周期回调**（按时间顺序）：

| 阶段 | 触发回调 / 事件 | 说明 |
|------|----------------|------|
| 构造 | `Create` → `AfterConstruction` → `AfterCreate` | 在 `AfterCreate` 中初始化子控件 |
| 显示前 | `OnCreate` 事件 | 适合绑定设计期数据 |
| 显示 | `Show` → `OnShow` 事件 | 窗口即将可见 |
| 激活 | `OnActivate` 事件 | 窗口获得焦点 |
| 交互 | `OnPaint` / `OnResize` / `OnKeyPress` 等 | 用户交互 |
| 关闭查询 | `CloseQuery` → `OnCloseQuery` | 返回 False 可阻止关闭 |
| 关闭 | `Close` → `OnClose` | 通过 CloseAction 决定 Hide/Free |
| 销毁 | `OnDestroy` 事件 → `Destroy` | 释放资源 |

**消息机制（核心）**：

fpGUI 使用平台无关的消息系统驱动控件行为。每个消息对应一个整数常量，定义于 `corelib/fpg_base.pas`：

```pascal
const
  FPGM_PAINT          = 1;   // 绘制请求
  FPGM_ACTIVATE       = 2;   // 窗口激活
  FPGM_DEACTIVATE     = 3;   // 窗口取消激活
  FPGM_KEYPRESS       = 4;   // 键盘按下
  FPGM_KEYRELEASE     = 5;   // 键盘释放
  FPGM_KEYCHAR        = 6;   // 字符输入
  FPGM_MOUSEDOWN      = 7;   // 鼠标按下
  FPGM_MOUSEUP        = 8;   // 鼠标释放
  FPGM_MOUSEMOVE      = 9;   // 鼠标移动
  FPGM_DOUBLECLICK    = 10;  // 双击
  FPGM_MOUSEENTER     = 11;  // 鼠标进入控件
  FPGM_MOUSEEXIT      = 12;  // 鼠标离开控件
  FPGM_CLOSE          = 13;  // 窗口关闭
  FPGM_SCROLL         = 14;  // 垂直滚动
  FPGM_RESIZE         = 15;  // 尺寸改变
  FPGM_MOVE           = 16;  // 位置移动
  FPGM_POPUPCLOSE     = 17;  // 弹出窗口关闭
  FPGM_HINTTIMER      = 18;  // 提示计时器
  FPGM_FREEME         = 19;  // 延迟释放
  FPGM_DROPENTER      = 20;  // 拖放进入
  FPGM_DROPEXIT       = 21;  // 拖放退出
  FPGM_DROPMOVE       = 22;  // 拖放移动
  FPGM_DROPDROP       = 23;  // 拖放释放
  FPGM_HSCROLL        = 24;  // 水平滚动
  FPGM_ABOUT          = 25;  // 关于消息
  FPGM_WINDOW_ALLOCATED = 26; // 窗口句柄已分配
  FPGM_USER           = 50000; // 用户自定义消息起始值
  FPGM_KILLME         = MaxInt;  // 立即销毁消息
```

消息机制完整派发链详见 [模块6 §6.1](#61-事件运行原理消息派发链)。

### 1.6 Lazarus IDE 集成与配置

> 源码位置：`extras/lazarus_ide/`、`extras/aggpas/`

fpGUI 为 Lazarus IDE 提供了完整的包集成，安装后可在 IDE 中直接新建 fpGUI 工程、运行 FPCUnit 测试、查阅 fpGUI 帮助。本节说明各 `.lpk` 包的作用、安装步骤及平台选择。

#### 1.6.1 Lazarus 包清单

| 包名 | 文件路径 | 类型 | 作用 |
|------|----------|------|------|
| `fpgui_ide` | `extras/lazarus_ide/fpgui_ide.lpk` | DesignTime | 在 Lazarus "File \| New" 菜单注册 "fpGUI Application" / "fpGUI+Agg2D Application" / "Console Agg2d Application" 三种工程模板 |
| `fpgui_toolkit` | `extras/lazarus_ide/<平台>/fpgui_toolkit.lpk` | RunAndDesignTime | fpGUI 运行时核心包，按平台分目录提供（gdi/x11/cocoa/ohos），声明 130+ 单元与 Agg2D/布局/样式等 |
| `aggpas` | `extras/aggpas/aggpas.lpk` | RunTime | AggPas 2D 渲染库（fpGUI fork），134 个 agg_* 单元，`fpgui_toolkit` 依赖之 |
| `idefpguitestrunner` | `extras/lazarus_ide/idefpguitestrunner.lpk` | RunAndDesignTime | 注册 FPCUnit 测试工程模板，用 fpGUI 作为测试运行器前端 |
| `fpGUIHelpIntegration` | `extras/lazarus_ide/fpGUIHelpIntegration.lpk` | DesignTime | 在 Lazarus 帮助系统中集成 fpGUI API 文档 |

#### 1.6.2 平台特定的 fpgui_toolkit 包

`fpgui_toolkit` 按目标平台分目录存放，每个目录的 `.lpk` 仅替换 `fpg_impl.pas` / `fpg_interface.pas` 等平台适配单元，公共单元（`fpg_base`、`fpg_main`、`fpg_widget`、所有 `fpg_*` 控件）保持一致：

| 平台 | 目录 | 平台单元 | 关键定义 | 备注 |
|------|------|----------|----------|------|
| Windows (GDI) | `extras/lazarus_ide/gdi/` | `fpg_gdi.pas`、`fpg_impl.pas`(gdi)、`fpg_interface.pas`(gdi) | `-dAggCanvasX`（关闭 AGG Canvas，走 GDI） | 默认 Windows 开发选此包 |
| Linux (X11) | `extras/lazarus_ide/x11/` | `fpg_x11.pas`、`fpg_netlayer_x11.pas`、`fpg_keyconv_x11.pas`、`fpg_xft_x11.pas` | `-dAggCanvasX` | 含 X11 网络层与 Xft 字体支持 |
| macOS (Cocoa) | `extras/lazarus_ide/cocoa/` | `fpg_cocoa.pas`、`fpg_impl.pas`(cocoa) | `-dAggCanvas`（启用 AGG Canvas） | Cocoa 原生后端 + AGG 渲染 |
| HarmonyOS (OHOS) | `extras/lazarus_ide/ohos/` | `fpg_ohos.pas`、`fpg_ohos_buffer_manager.pas`、`fpg_interface.pas`(ohos) | `-dAggCanvas`（启用 AGG Canvas） | 鸿蒙 native_drawing + AGG 混合画布 |

> **注意**：OHOS 平台包额外包含 `fpg_ohos_buffer_manager.pas`、`fpg_hybrid_canvas.pas`、`fpg_freetype_agg_fontresource.pas`、`fpg_wakechannel.pas`、`fpg_format.pas` 等 OHOS 专用单元，且不包含 `fpg_fontcache.pas`（OHOS 使用 native_drawing 字体而非 AggPas FreeType）。单元输出目录统一为 `framework/target/units`。

#### 1.6.3 安装步骤

**前置条件**：已安装 Lazarus（推荐 2.2.x 或更高）和 Free Pascal Compiler（3.2.2+）。

**步骤一：安装 aggpas 包**

1. Lazarus 菜单：`Package → Open Package File (.lpk)`
2. 选择 `D:\fpcupdeluxe34_new\fpGUI-2.1.0\extras\aggpas\aggpas.lpk`
3. 在打开的包编辑器中点击 `Compile`（编译，无需安装，运行时包）
4. 编译成功后会在 `framework/target/units/` 生成 `.ppu`/`.o` 文件

**步骤二：安装目标平台的 fpgui_toolkit 包**

1. `Package → Open Package File (.lpk)`
2. 按目标平台选择（开发期可只装一个）：
   - Windows：`extras/lazarus_ide/gdi/fpgui_toolkit.lpk`
   - Linux：`extras/lazarus_ide/x11/fpgui_toolkit.lpk`
   - macOS：`extras/lazarus_ide/cocoa/fpgui_toolkit.lpk`
   - OHOS：`extras/lazarus_ide/ohos/fpgui_toolkit.lpk`
3. 点击 `Compile` 编译；如需在 IDE 中可视化设计，点击 `Use → Add to project` 将其加入当前工程

**步骤三：安装 fpgui_ide 设计时包（必需）**

1. `Package → Open Package File (.lpk)`
2. 选择 `extras/lazarus_ide/fpgui_ide.lpk`
3. 点击 `Compile` 编译
4. 点击 `Use → Install`（此操作会触发 Lazarus 重新编译自身）
5. 重启 Lazarus 后，`File → New...` 弹窗中将出现 "fpGUI Application" 等模板

**步骤四（可选）：安装 FPCUnit 测试运行器与帮助集成**

- 测试运行器：打开 `idefpguitestrunner.lpk` → `Compile` → `Use → Install`
- 帮助集成：打开 `fpGUIHelpIntegration.lpk` → `Compile` → `Use → Install`

#### 1.6.4 从 IDE 新建 fpGUI 工程

安装 `fpgui_ide` 后，`File → New Project...` 会显示三种模板：

| 模板 | 描述 | 适用场景 |
|------|------|----------|
| **fpGUI Application** | 纯 fpGUI Toolkit 应用，使用平台默认 Canvas（GDI/X11/Cocoa） | Windows/Linux 常规桌面程序 |
| **fpGUI+Agg2D Application** | 在 fpGUI 应用中实例化 `TAgg2D`，用于高级矢量绘图 | 需要渐变、抗锯齿、路径变换的程序 |
| **Console Agg2d Application** | 控制台程序内嵌 Agg2D，无 fpGUI 窗口系统 | 纯离线渲染、图像生成工具 |

模板由 `fpguilazideintf.pas` 中的 `TfpGUIApplicationDescriptor` / `TfpGUIAgg2dApplicationDescriptor` / `TConsoleAgg2dApplicationDescriptor` 三个描述符类注册，`InitProject` 负责生成初始 `.lpr` 与单元文件。

#### 1.6.5 手动配置工程依赖

若不使用 IDE 模板（例如命令行构建或 OHOS 交叉编译），可在 `.lpr` 中显式声明依赖：

```pascal
program myapp;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX} cthreads, {$ENDIF}
  Classes,
  fpg_base,
  fpg_main,
  fpg_form,
  fpg_button;
  // fpgui_toolkit 包会自动引入以上单元；Agg2D 通过 aggpas 包引入

begin
  fpgApplication.Initialize;
  // ...
end.
```

命令行编译时需指定单元路径：

```bat
fpc -MObjFPC -Sh -Fu<fpGUI>\framework\target\units myapp.lpr
```

#### 1.6.6 常见配置问题

| 问题 | 原因 | 解决 |
|------|------|------|
| `unit fpg_impl not found` | 未安装对应平台的 `fpgui_toolkit` 包 | 按目标平台打开 `gdi/`、`x11/`、`cocoa/` 或 `ohos/` 下的 `.lpk` |
| `unit Agg2D not found` | 未编译 `aggpas` 包 | 先 `Open` + `Compile` `extras/aggpas/aggpas.lpk` |
| `unit fpguilazideintf not found` | 未安装 `fpgui_ide` 设计时包 | 打开 `fpgui_ide.lpk` → `Use → Install` → 重启 IDE |
| Windows 下菜单图标模糊 | 使用了 GDI 包但 HiDPI 未启用 | 在工程选项 `Compiler Options → Custom Options` 添加 `-dEnableHiDPI` |
| OHOS 工程缺少 `fpg_ohos_*` 单元 | 误用了非 OHOS 平台包 | 改用 `extras/lazarus_ide/ohos/fpgui_toolkit.lpk`，其 `OtherUnitFiles` 已包含 `corelib/ohos` 路径 |
| 多平台包冲突 | 同时安装了 gdi 与 x11 的 `fpgui_toolkit` | Lazarus 同名包只能安装一个；切换平台时先 `Uninstall` 旧包 |
| Agg2D 文字不显示 | OHOS 上 AggPas FreeType 字体引擎不可用 | OHOS 包已改用 `fpg_ohos_agg_fontresource`（native_drawing 字体）；确保 `-dAggCanvas` 已定义 |

#### 1.6.7 包文件关键字段速查

以 `extras/lazarus_ide/ohos/fpgui_toolkit.lpk` 为例：

```xml
<SearchPaths>
  <IncludeFiles Value="..\..\..\framework\src\main\pascal\corelib;
      ..\..\..\framework\src\main\pascal\corelib\ohos;
      ..\..\..\framework\src\main\pascal\corelib\render\software;
      ..\..\..\framework\src\main\pascal\gui;
      ..\..\..\framework\src\main\pascal;
      ..\..\..\framework\src\main\resources"/>
  <OtherUnitFiles Value="..\..\..\framework\src\main\pascal\corelib;
      ..\..\..\framework\src\main\pascal\corelib\ohos;
      ..\..\..\framework\src\main\pascal\gui;
      ..\..\..\framework\src\main\pascal\gui\db;
      ..\..\..\framework\src\main\pascal\corelib\render\software;
      ..\..\..\framework\src\main\pascal\reportengine;
      ..\..\..\framework\src\main\pascal\3rdparty\regex"/>
  <UnitOutputDirectory Value="..\..\..\framework\target\units"/>
</SearchPaths>
...
<Other>
  <CustomOptions Value="-dAggCanvas"/>   <!-- OHOS 启用 AGG Canvas -->
</Other>
...
<RequiredPkgs Count="2">
  <Item1><PackageName Value="aggpas"/></Item1>
  <Item2><PackageName Value="FCL"><MinVersion Major="1" Valid="True"/></PackageName></Item2>
</RequiredPkgs>
```

- `IncludeFiles`：`.inc` 文件搜索路径（平台 `corelib/<平台>` + 公共 `corelib` + `gui` + `resources`）
- `OtherUnitFiles`：`.pas` 单元搜索路径（比 IncludeFiles 多 `gui/db`、`reportengine`、`3rdparty/regex`）
- `UnitOutputDirectory`：编译产物统一输出到 `framework/target/units`
- `CustomOptions`：传给 FPC 的自定义指令，OHOS 为 `-dAggCanvas`，GDI/X11 为 `-dAggCanvasX`
- `RequiredPkgs`：声明依赖，`fpgui_toolkit` 依赖 `aggpas` + `FCL`；`fpgui_ide` 依赖 `IDEIntf` + `FCL`

### 1.7 自带工具与配套应用

> 源码位置：`ide/`、`uidesigner/`、`docview/`

fpGUI 源码树附带三个独立应用，分别用于 IDE 开发、可视化设计与帮助文档查看。三者均为标准 FPC 工程，编译产物为 `*.exe`(Windows) 或无扩展名可执行文件(Linux/macOS)。

#### 1.7.1 工具清单

| 工具 | 源码目录 | 可执行文件名 | 主程序文件 | 授权 | 状态 |
|------|----------|--------------|------------|------|------|
| **fpGUI IDE (Maximus)** | `ide/` | `maximus` | `ide/src/main/pascal/ide.main.pas` | BSD-3-Clause | 开发中（WIP） |
| **UI Designer (VFD)** | `uidesigner/` | `uidesigner` | `uidesigner/src/main/pascal/uidesigner.lpr` | BSD-3-Clause | 可用 |
| **DocView (帮助查看器)** | `docview/` | `docview` | `docview/src/main/pascal/docview.lpr` | BSD-3-Clause | 可用 |

#### 1.7.2 fpGUI IDE — Maximus

**定位**：轻量级 Pascal IDE，作为 fpGUI 组件的展示与测试平台，长期演进中。

**入口**：`ide.main.pas`（`program maximus`），主窗体 `ide.form.main.TMainForm`。

**核心单元**（`ide/src/main/pascal/`）：

| 单元 | 作用 |
|------|------|
| `ide.form.main` | 主窗体，集成编辑器、工程树、菜单 |
| `ide.project` / `ide.project.backend` / `ide.project.pasbuild` | 工程模型与 FPC 构建调度 |
| `ide.builder.thread` / `ide.runner.thread` | 后台编译与运行线程 |
| `ide.editor.tabs` / `ide.editor.undo` / `ide.editor.theme` | 多标签编辑器、撤销栈、主题 |
| `ide.highlighter` / `ide.highlighter.xml` / `ide.highlighter.ini` | 语法高亮（Pascal/XML/INI） |
| `ide.highlight.renderer` | 高亮渲染器 |
| `ide.pascal.tokeniser` | Pascal 词法分析 |
| `ide.debug.adapter` / `ide.debug.worker` | 调试适配器（DAP）与调试工作线程 |
| `ide.breakpoint` / `ide.watches` / `ide.variables` / `ide.callstack` | 断点/监视/变量/调用栈 |
| `ide.navigation` / `ide.symbolfinder` / `ide.declaration` | 符号导航、查找声明 |
| `ide.findusages` / `ide.filefinder` / `ide.filemonitor` | 查找引用、文件查找、文件监控 |
| `ide.session` / `ide.profiles` | 会话持久化与多 profile |
| `ide.quickdoc` / `ide.cursorhistory` / `ide.bracketmatch` | 快速文档、光标历史、括号匹配 |
| `fpg_textedit` | 基于 fpGUI 的文本编辑控件（复用单元） |

**资源**：
- `ide/src/main/resources/editor-themes/`：`default.ini` / `dark.ini` / `solarized-light.ini` / `solarized-dark.ini`
- `ide/target/editor-themes/`：运行时主题输出目录
- `ide/templates/`：工程模板（`default/`、`fpgui/`、`fptest/`）
- `ide/images/`：编辑器图标（构造函数/析构函数/方法/齿轮）
- `ide/docs/ide_mvp_plan.adoc`：MVP 规划文档

**构建**：`project.xml` 中 `<executableName>maximus</executableName>`，依赖 `../framework`。

**测试**：`ide/src/test/pascal/` 下 27 个 `ide.test.*.pas` FPCUnit 测试单元，覆盖 tokeniser、highlighter、editor undo、project tree、breakpoint、debug adapter 等，`TestRunner.pas` 为入口。

> **注意**：README 明确标注 "WORK IN PROGRESS, NOT ready for usage"，仅作为研究/试验用途。

#### 1.7.3 UI Designer — VFD 移植版

**定位**：fpGUI 可视化窗体设计器，源自 Nagy Viktor 2003 年的 VFD，由 Graeme 移植到 fpGUI。

**入口**：`uidesigner.lpr`（`program uidesigner`），主窗体 `frm_main.TMainForm`。

**核心单元**（`uidesigner/src/main/pascal/`，统一 `vfd_*` 前缀）：

| 单元 | 作用 |
|------|------|
| `vfd_main` | 设计器入口与全局协调 |
| `vfd_designer` | `TMainDesigner` 设计器核心 |
| `vfd_widgets` | 控件注册表（`RegisterWidgets`） |
| `vfd_widgetclass` | 控件元信息（类名、属性、事件） |
| `vfd_props` / `vfd_propeditgrid` | 属性列表模型与属性编辑网格 |
| `vfd_editors` | 属性编辑器（字符串/整数/枚举/颜色/字体等） |
| `vfd_resizer` | 设计时选取框与缩放器 |
| `vfd_forms` / `vfd_formparser` | 表单管理与 Pascal 源码解析/回写 |
| `vfd_file` | 工程文件读写（`.prj`） |
| `vfd_utils` / `vfd_constants` | 工具函数与常量 |
| `frm_main` | 主窗体 UI |

**关键特性**（见 [README.txt](file:///D:/fpcupdeluxe34_new/fpGUI-2.1.0/uidesigner/README.txt)）：
- **不生成外部 `.dfm`/`.lfm`**，直接读写 Pascal 源码单元，用注释标记设计器管理区域
- **支持未知控件**：未识别组件绘制绿色矩形占位；未识别属性写入"Unknown"备忘录原样回写
- **一个单元多个表单**：支持单文件多表单管理
- **可接入既有代码**：手动添加标记后即可让设计器接管已有表单

**资源**：
- `src/main/resources/images/`：控件调色板图标（40+ 控件 bitmap，含 align 方向箭头）
- `src/main/resources/languages/`：10 种语言 `.po`（af/en/et/ms/pl/pt/pt_BR/ru/uk）
- `scripts/localize.{sh,bat}`：i18n 字符串提取脚本
- `uidesigner.prj` / `uidesigner_clean.prj`：工程文件

**构建**：`project.xml` 中 `<executableName>uidesigner</executableName>`，依赖 `../framework`；`src/main/pascal/build.bat` 为 Windows 构建脚本，`extrafpc.cfg` 为 FPC 配置。

**运行**：

```bat
cd uidesigner\src\main\pascal
build.bat
uidesigner.exe
```

命令行参数：传入 `.pas`/`.prj` 文件路径直接加载。

#### 1.7.4 DocView — 帮助文档查看器

**定位**：跨平台帮助查看器，支持 IPF/INF/HLP 帮助文件格式，源自 OS/2 View 理念，内置 RichTextView 组件。

**入口**：`docview.lpr`（`program docview`），主窗体 `frm_main.TMainForm`。

**核心单元**（`docview/src/main/pascal/`）：

| 单元 | 作用 |
|------|------|
| `frm_main` | 主窗体（目录树+内容查看） |
| `frm_text` / `frm_note` / `frm_bookmarks` / `frm_configuration` | 文本/便签/书签/设置子窗 |
| `HelpFile` / `HelpTopic` / `HelpBitmap` / `HelpNote` / `HelpBookmark` | 帮助文件模型（文件/主题/位图/便签/书签） |
| `HelpWindowDimensions` | 窗口尺寸持久化 |
| `IPFFileFormatUnit` / `IPFEscapeCodes` / `lzwdecompress` | IPF 格式解析与 LZW 解压 |
| `SearchUnit` / `SearchTable` / `TextSearchQuery` / `CompareWordUnit` | 全文检索引擎 |
| `SettingsUnit` | 用户偏好持久化 |
| `dvHelpers` / `nvUtilities` / `dvconstants` | 工具函数与常量 |

**RichTextView 子系统**（`docview/src/main/pascal/richtext/`）：

| 单元 | 作用 |
|------|------|
| `RichTextView` | 富文本视图控件（可复用） |
| `RichTextDocumentUnit` | 文档模型 |
| `RichTextStyleUnit` | 字符/段落样式 |
| `RichTextLayoutUnit` | 布局计算 |
| `RichTextDisplayUnit` | 显示渲染 |
| `RichTextPrintUnit` | 打印支持 |
| `CanvasFontManager` | 字体管理 |
| `ACLStringUtility` | 字符串工具 |

RichTextView 作为独立 Lazarus 包发布：[fpgui_richtext.lpk](file:///D:/fpcupdeluxe34_new/fpGUI-2.1.0/docview/extras/fpgui_richtext.lpk)，包含 7 个单元，依赖 `fpgui_toolkit` + `FCL`，可供第三方工程复用。

**配套工具**：
- `src/docdump/`：IPF 文件 dump 工具（`docdump.lpr`），含 `readtoc`/`readstrings`/`readheader`/`readfonts`/`readextfiles`/`readdictionary`/`readcontrols`/`readnlsdata` 等读取器
- `extras/testedit/`：RichTextView 测试编辑器，含 bold/italic/align/color/font/hyperlink/image 等格式按钮
- `extras/testapp/`：最小嵌入示例
- `extras/fpgui_richtext.pas`：RichTextView 包入口单元

**资源**：
- `src/main/resources/images/`：导航图标（go-up/down/previous/next、notegreen、missing）
- `src/main/ipf/docview.ipf`：DocView 自身的帮助文档源
- `docs/`：IPF 格式参考文档（`IPFREF_v4.INF`、`INF_article.txt`、`INFFILE.INF`、`inf04.txt`）
- `test/`：测试用例（`testcase1.ipf`、`testcase1.hlp`、`newview.inf`）
- `install/`：Linux 安装脚本与 `.desktop` 文件、MIME 类型扩展

**构建**：

```bat
cd docview\src\main\pascal
build-win.bat   :: Windows
build.bat       :: 通用
```

命令行支持：显示主题 by ID、打开最近文件、搜索等。

#### 1.7.5 工具间关系

```
            ┌────────────────────┐
            │  fpGUI framework   │  (corelib + gui + aggpas)
            └─────────┬──────────┘
                      │ 依赖
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
   ┌─────────┐  ┌──────────┐  ┌──────────┐
   │  IDE    │  │ UIDesigner│  │ DocView  │
   │ maximus │  │  (VFD)   │  │          │
   └────┬────┘  └────┬─────┘  └────┬─────┘
        │            │              │
        │            │ 读写 .pas    │ 含 RichTextView
        │            ▼              ▼ 独立 lpk
        │      ┌──────────┐  ┌──────────────┐
        │      │ 用户工程 │  │fpgui_richtext│
        │      │  .lpr     │  │   .lpk       │
        │      └──────────┘  └──────────────┘
        │
        ▼ 调用（可选）
   ┌──────────┐
   │ DocView  │  作为帮助查看器
   └──────────┘
```

- **framework** 是三者共同依赖
- **UIDesigner** 产出标准 Pascal 单元，可直接被 IDE 或命令行工程使用
- **DocView** 内嵌的 RichTextView 可作为独立包被任意 fpGUI 工程复用
- **IDE** 可在运行时调用 DocView 作为帮助系统（对应 1.6 节 `fpGUIHelpIntegration` 包）

#### 1.7.6 构建与运行

三者均依赖 `framework` 预先编译（见 [1.3 节](#13-开发环境搭建free-pascal--fpgui-安装配置编译)）：

```bat
:: 1. 先编译 framework（产生 framework/target/units 下的 .ppu）
cd framework
:: 执行 fpGUI 自带构建脚本

:: 2. 编译 UI Designer
cd ..\uidesigner\src\main\pascal
build.bat
:: 产物：uidesigner.exe

:: 3. 编译 DocView
cd ..\..\docview\src\main\pascal
build-win.bat
:: 产物：docview.exe

:: 4. 编译 IDE Maximus（需 FPC 3.2.2+，依赖较多单元）
cd ..\..\ide\src\main\pascal
fpc -MObjFPC -Sh -Fu..\..\..\framework\target\units ide.main.pas
:: 产物：maximus.exe
```

> **避坑**：IDE 与 UIDesigner 在 Windows 下若启用 GDI 包需 `-dAggCanvasX`；若启用 AGG Canvas 需 `-dAggCanvas`。OHOS 平台不支持运行这三个桌面工具（它们是开发期工具，不在目标设备运行）。

---

## 模块2：全局基础通用规范

### 2.1 基础数据类型

> 源码位置：`corelib/fpg_base.pas`

#### 2.1.1 坐标与尺寸类型

```pascal
type
  TfpgCoord = integer;  // 坐标类型（整数），所有控件位置和尺寸的基础类型
```

#### 2.1.2 颜色类型

```pascal
type
  TfpgColor = type longword;  // 颜色格式：AARRGGBB（Alpha, Red, Green, Blue）
```

颜色值的 32 位结构：

| 位置 | Bit 31-24 | Bit 23-16 | Bit 15-8 | Bit 7-0 |
|------|-----------|-----------|----------|---------|
| 含义 | Alpha 通道 | Red 红色 | Green 绿色 | Blue 蓝色 |
| 示例 | $FF = 不透明 | $FF = 全红 | $00 | $00 |

#### 2.1.3 字符串类型

```pascal
type
  TfpgString = type AnsiString;        // fpGUI 字符串类型
  TfpgChar   = type ShortString4;      // 单字符类型（用于键盘输入）
```

#### 2.1.4 几何类型

```pascal
type
  TfpgPoint = object  // 静态分配的点对象
    X, Y: integer;
    procedure SetPoint(AX, AY: integer);
    function  ManhattanLength: integer;
    function  ManhattanLength(const PointB: TfpgPoint): integer;
  end;

  TfpgRect = object   // 静态分配的矩形对象
    Top, Left, Width, Height: TfpgCoord;
    procedure SetRect(const aleft, atop, awidth, aheight: TfpgCoord);
    function  Bottom: TfpgCoord;
    function  Right: TfpgCoord;
    procedure SetBottom(Value: TfpgCoord);
    procedure SetRight(Value: TfpgCoord);
    function  CenterPoint: TPoint;
    function  CopyRect(out Dest: TfpgRect): Boolean;
    function  ContainsPoint(APoint: TfpgPoint): Boolean;
    function  IntersectRect(out ARect: TfpgRect; const r2: TfpgRect): Boolean;
    function  UnionRect(out ARect: TfpgRect; const r2: TfpgRect): Boolean;
    function  IsRectEmpty: Boolean;
    function  IsUnassigned: Boolean;
    function  OffsetRect(const dx: Integer; const dy: Integer): Boolean;
    function  InflateRect(const dx: Integer; const dy: Integer): Boolean;
    function  PointInRect(const APoint: TPoint): Boolean;
    procedure Clear;
    function  ToString: TfpgString;
  end;
  PfpgRect = ^TfpgRect;

  TfpgSize = object   // 静态分配的尺寸对象
    W, H: integer;
    procedure SetSize(AWidth, AHeight: integer);
  end;
```

**辅助构造函数**：

```pascal
function fpgPoint(AX, AY: integer): TfpgPoint;    // 快速构造点
function fpgRect(ALeft, ATop, AWidth, AHeight: integer): TfpgRect; // 快速构造矩形
function fpgSize(AWidth, AHeight: integer): TfpgSize;  // 快速构造尺寸
```

> **说明:** 现代 fpGUI 推荐直接使用 `TfpgRect.SetRect` / `TfpgPoint.SetPoint` / `TfpgSize.SetSize` 方法；`fpgRect`/`fpgPoint`/`fpgSize` 辅助函数仍保留以兼容旧代码。

### 2.2 通用常量（命名颜色 / 键盘常量）

#### 2.2.1 预定义颜色常量

> 源码位置：`corelib/predefinedcolors.inc`

```pascal
// 系统颜色
clBlack             = TfpgColor($ff000000);  // 纯黑
clWhite             = TfpgColor($ffffffff);  // 纯白
clRed               = TfpgColor($ffff0000);  // 纯红
clGreen             = TfpgColor($ff00ff00);  // 纯绿
clBlue              = TfpgColor($ff0000ff);  // 纯蓝
clMagenta           = TfpgColor($ffff00ff);  // 品红
clCyan              = TfpgColor($ff00ffff);  // 青色
clYellow            = TfpgColor($ffffff00);  // 黄色
clGray              = TfpgColor($ff808080);  // 灰色
clLime              = TfpgColor($ff00ff00);  // 柠檬绿（同 clGreen）

// 系统命名颜色（由样式决定）
clWindowBackground   = TfpgColor(cl_BaseNamedColor + 1);  // 窗口背景
clButtonFace         = TfpgColor(cl_BaseNamedColor + 3);  // 按钮表面
clText1              = TfpgColor(cl_BaseNamedColor + 5);  // 主文本色
clHilite1            = TfpgColor(cl_BaseNamedColor + 7);  // 高亮色1
clHilite2            = TfpgColor(cl_BaseNamedColor + 8);  // 高亮色2
clBoxColor           = TfpgColor(cl_BaseNamedColor + 9);  // 输入框背景
clListBox            = TfpgColor(cl_BaseNamedColor + 11); // 列表框背景
clHyperLink          = TfpgColor(cl_BaseNamedColor + 13); // 超链接色
clShadow1            = TfpgColor(cl_BaseNamedColor + 15); // 阴影色
clSplitterGrabBar    = TfpgColor(cl_BaseNamedColor + 17); // 分隔条色

// 特殊值
clDefault            = TfpgColor($00000000);  // 默认色（由样式决定）
```

#### 2.2.2 键盘常量

> 源码位置：`corelib/keys.inc`

```pascal
// 功能键
keyF1        = $e101;
keyF2        = $e102;
keyF3        = $e103;
keyF4        = $e104;
keyF5        = $e105;
keyF6        = $e106;
keyF7        = $e107;
keyF8        = $e108;
keyF9        = $e109;
keyF10       = $e10a;
keyF11       = $e10b;
keyF12       = $e10c;

// 编辑键
keyBackSpace = $08;
keyTab       = $09;
keyReturn    = $0d;
keyEnter     = keyReturn;  // 别名
keyEscape    = $1b;
keySpace     = $20;

// 方向键
keyLeft      = $e034;
keyRight     = $e035;
keyUp        = $e036;
keyDown      = $e037;

// 修饰键
keyShift     = $e038;
keyCtrl      = $e039;
keyAlt       = $e03a;

// 编辑操作键
keyHome      = $e040;
keyEnd       = $e041;
keyPageUp    = $e042;
keyPageDown  = $e043;
keyInsert    = $e044;
keyDelete    = $e045;
```

> **说明:** `KeycodeToText(keycode, [])` 函数可把扫描码转换为可读文本（用于事件日志）。

#### 2.2.3 鼠标按键常量

```pascal
const
  MOUSE_LEFT   = 1;
  MOUSE_RIGHT  = 3;
  MOUSE_MIDDLE = 2;
```

### 2.3 枚举类型

> 源码位置：`corelib/fpg_main.pas`

```pascal
type
  // 对齐方式（TAlign 用于 Align 属性）
  TAlign = (alNone, alTop, alBottom, alLeft, alRight, alClient);

  // 垂直布局（用于 Layout 属性）
  TLayout = (tlTop, tlCenter, tlBottom);

  // 复选框/单选按钮的方框位置
  TBoxLayout = (tbLeftBox, tbRightBox);

  // 锚点（用于 Anchors 属性，实现窗口缩放时的相对定位）
  TAnchor  = (anLeft, anRight, anTop, anBottom);
  TAnchors = set of TAnchor;

  // 方向
  TOrientation = (orVertical, orHorizontal);

  // 鼠标按键
  TMouseButton = (mbLeft, mbRight, mbMiddle);

  // 箭头方向
  TArrowDirection = (adUp, adDown, adLeft, adRight);

const
  AllAnchors = [anLeft, anRight, anTop, anBottom];
```

```pascal
type
  // 窗口类型
  TWindowType = (wtChild, wtWindow, wtModalForm, wtPopup);

  // 窗口状态
  TfpgWindowState = (wsNormal, wsMinimized, wsMaximized);

  // 窗口属性
  TWindowAttribute = (waSizeable, waAutoPos, waStayOnTop,
      waFullScreen, waBorderless, waUnblockableMessages,
      waX11SkipWMHints, waSystemStayOnTop);
  TWindowAttributes = set of TWindowAttribute;

  // 鼠标光标
  TMouseCursor = (mcDefault, mcArrow, mcCross, mcIBeam, mcSizeEW, mcSizeNS,
      mcSizeNWSE, mcSizeNESW, mcSizeSWNE, mcSizeSENW, mcMove, mcHourGlass,
      mcHand, mcDrag, mcNoDrop, mcNone);

  // 渐变方向
  TGradientDirection = (gdVertical, gdHorizontal);

  // 编辑框边框样式
  TfpgEditBorderStyle = (ebsNone, ebsDefault, ebsSingle);

  // 标签页样式
  TfpgTabStyle    = (tsTabs, tsButtons, tsFlatButtons);
  TfpgTabPosition = (tpTop, tpBottom, tpLeft, tpRight, tpNone);

  // 文本编码
  TfpgTextEncoding = (encUTF8, encCP437, encCP850, encCP866, encCP1250, encIBMGraph);

  // 字体属性
  TfpgFontAttribute  = (fpgFontBold, fpgFontItalic, fpgFontUnderline);
  TfpgFontAttributes = set of TfpgFontAttribute;
```

**Align 对齐方式说明**：

| 值 | 说明 | 典型用途 |
|------|------|---------|
| `alNone` | 无对齐，使用手动坐标 | 精确定位控件 |
| `alTop` | 顶部对齐，宽度填充父容器 | 工具栏、菜单栏 |
| `alBottom` | 底部对齐，宽度填充父容器 | 状态栏 |
| `alLeft` | 左侧对齐，高度填充父容器 | 侧边栏 |
| `alRight` | 右侧对齐，高度填充父容器 | 属性面板 |
| `alClient` | 填充剩余客户区 | 主内容区域 |

**模态结果类型**：

```pascal
type
  TfpgModalResult = (mrNone, mrOK, mrCancel, mrYes, mrNo, mrAbort,
      mrRetry, mrIgnore, mrAll, mrNoToAll, mrYesToAll, mrHelp);
```

### 2.4 Shift state flags

> 源码位置：`corelib/fpg_base.pas`（继承自 FPC `Classes` 单元）

`TShiftState` 是一组集合，用于描述鼠标/键盘事件发生时的修饰键状态：

| 标志位 | 含义 |
|--------|------|
| `ssShift` | Shift 键按下 |
| `ssCtrl` | Ctrl 键按下 |
| `ssAlt` | Alt 键按下 |
| `ssLeft` | 鼠标左键按下 |
| `ssRight` | 鼠标右键按下 |
| `ssMiddle` | 鼠标中键按下 |
| `ssDouble` | 双击事件 |
| `ssTriple` | 三击事件 |

> **说明:** fpGUI 还扩展了 `ssMeta`/`ssSuper`/`ssHyper`/`ssAltGr`/`ssCaps`/`ssNum`/`ssScroll` 等修饰键，详见 `examples/corelib/eventtest` 的 `ShiftStateToStr` 函数。

**判断修饰键示例**：

```pascal
if (KeyCode = keyS) and (ssCtrl in ShiftState) then
begin
  SaveFile;
  Consumed := True;
end;
```

### 2.5 统一命名规范、组件使用规范、编码规范

**命名规范**：

| 类别 | 前缀/规则 | 示例 |
|------|----------|------|
| 控件类 | `Tfpg` 前缀 | `TfpgButton`、`TfpgEdit` |
| 接口 | `I` 前缀 | `ILayoutManager`、`ICommand` |
| 枚举值 | 2~3 字母前缀 | `alTop`、`mrOK`、`wsNormal`、`mbLeft` |
| 颜色常量 | `cl` 前缀 | `clBlack`、`clWindowBackground` |
| 键盘常量 | `key` 前缀 | `keyF1`、`keyReturn` |
| 消息常量 | `FPGM_` 前缀 | `FPGM_PAINT`、`FPGM_MOUSEDOWN` |
| 全局变量 | `fpg` 前缀 | `fpgApplication`、`fpgStyle`、`fpgImages` |
| 全局函数 | `fpg` 前缀 | `fpgMessageDlg`、`fpgSelectColorDialog` |

**组件使用规范**：

1. **Owner vs Parent**：`Create(AOwner)` 设置所有者（自动释放）；`Parent` 设置可视父控件。Owner 为 `TfpgWidget` 时会自动设置 Parent。
2. **事件赋值**：`{$mode objfpc}` 下事件赋值必须使用 `@` 运算符：`btn.OnClick := @ButtonClick`。
3. **子控件初始化**：在窗体中重写 `AfterCreate` 初始化子控件，不要在构造函数 `Create` 中做（此时窗体尚未完成布局）。
4. **资源释放**：模态窗口在 `ShowModal` 返回后必须 `Free`，使用 `try...finally`。

**编码规范**：

1. 单元命名以 `fpg_` 前缀开头；类型以 `Tfpg` 开头。
2. 字符串使用 `TfpgString`（= AnsiString）保持跨平台一致性。
3. 颜色使用 `TfpgColor`（AARRGGBB），避免直接传 `$RRGGBB` 形式。
4. 处理大量数据时使用 `BeginUpdate`/`EndUpdate` 包裹批量操作。
5. 长时间操作中调用 `fpgApplication.ProcessMessages` 保持 UI 响应。

### 2.6 窗口、画布、颜色、字体、坐标系统通用规则

**窗口规则**：

- 窗口分两层：逻辑层顶层窗口基类为 `TfpgWindow`（派生 `TfpgBaseForm`/`TfpgForm`）；原生层抽象基类为 `TfpgWindowBase`（派生 `TfpgGDIWindow` 等平台类，经 `TfpgNativeWindow` 暴露）。窗体逻辑对象通过 `HasOwnWindow` 拥有唯一原生窗口，子控件为无句柄轻量控件。详见 3.1.1。
- 窗口标题使用 `WindowTitle` 属性（不是 `Text`）。
- 窗口位置策略由 `WindowPosition` 控制；窗口状态由 `WindowState` 控制。

**画布规则**：

- `TfpgCanvas` 通过控件的 `Canvas` 属性获得，仅在 `HandlePaint` 或 `OnPaint` 事件中可用。
- 绘制顺序：先 `BeginDraw`/`Clear` 背景 → 设置颜色/字体 → 绘制图形/文本 → `EndDraw`。
- 不要在 `HandlePaint` 内部调用 `Invalidate`，会导致无限循环。

**颜色规则**：

- 颜色格式 `$AARRGGBB`（Alpha=最高字节）。
- Alpha=`$FF` 表示不透明，`$00` 表示完全透明。
- 系统命名颜色（如 `clWindowBackground`）由当前样式动态解析，可通过 `fpgGetNamedColor` 获取实际 RGB。

**字体规则**：

- 字体描述字符串格式：`字体名-字号:属性1=true:属性2=true`
- 平台默认字体：

| 平台 | 默认 Sans | 默认 Fixed |
|------|-----------|------------|
| Windows | Arial-8 | Courier New-10 |
| Linux | Liberation Sans-10 | Liberation Mono-10 |
| OHOS | HarmonyOS Sans-12 | HarmonyOS Sans Mono-12 |

- 字体描述示例：
  - `'Arial-8:antialias=true'`
  - `'Liberation Sans-10:bold:italic:antialias=true'`
  - `'Courier New-10'`（等宽）

**坐标系统规则**：

- 坐标原点在父控件客户区左上角，X 向右、Y 向下递增。
- 控件位置由 `Left`/`Top` 表示，尺寸由 `Width`/`Height` 表示。
- 矩形使用 `TfpgRect`（`Top`/`Left`/`Width`/`Height` 而非 `Top/Left/Right/Bottom`）。

### 2.7 全局函数

> 源码位置：`corelib/fpg_main.pas`

```pascal
function fpgApplication: TfpgApplication;     // 全局应用程序对象
function fpgClipboard: TfpgClipboard;         // 全局剪贴板对象
```

**颜色函数**：

```pascal
function fpgColorToRGB(col: TfpgColor): TfpgColor;       // 命名颜色解析为实际 RGB
function fpgGetNamedColor(col: TfpgColor): TfpgColor;    // 获取命名颜色当前 RGB 值
procedure fpgSetNamedColor(colorid, rgbvalue: longword); // 设置命名颜色 RGB
function fpgIsNamedColor(col: TfpgColor): boolean;       // 判断是否为命名颜色
```

**矩形/点辅助函数**：

```pascal
function fpgPoint(const AX, AY: integer): TfpgPoint;
function fpgRect(ALeft, ATop, AWidth, AHeight: integer): TfpgRect; deprecated 'Use TfpgRect.SetRect() instead.';
function fpgSize(const AWidth, AHeight: integer): TfpgSize;
function fpgRectToRect(const ARect: TfpgRect): TRect;     // fpGUI 矩形转 FCL 矩形

function CopyRect(out Dest: TfpgRect; const Src: TfpgRect): Boolean; deprecated;
function InflateRect(var Rect: TfpgRect; dx, dy: Integer): Boolean; deprecated;
function IntersectRect(out ARect: TfpgRect; const r1, r2: TfpgRect): Boolean; deprecated;
function IsRectEmpty(const ARect: TfpgRect): Boolean; deprecated;
function OffsetRect(var Rect: TfpgRect; dx, dy: Integer): Boolean; deprecated;
function PtInRect(const ARect: TfpgRect; const APoint: TPoint): Boolean; deprecated;
function UnionRect(out ARect: TfpgRect; const R1, R2: TfpgRect): Boolean; deprecated;
function CenterPoint(const Rect: TfpgRect): TPoint; deprecated;
```

> **说明:** 全局 `CopyRect/InflateRect/IntersectRect/IsRectEmpty/OffsetRect/PtInRect/UnionRect/CenterPoint` 已标记 deprecated，现代代码应使用 `TfpgRect` 对象上的同名方法（如 `R.IntersectRect(out, r2)`、`R.OffsetRect(dx, dy)`）。

**消息分发函数**：

```pascal
procedure fpgPostMessage(Sender, Dest: TObject; MsgCode: integer; var aparams: TfpgMessageParams); overload;
procedure fpgPostMessage(Sender, Dest: TObject; MsgCode: integer); overload;
procedure fpgSendMessage(Sender, Dest: TObject; MsgCode: integer; var aparams: TfpgMessageParams); overload;
procedure fpgSendMessage(Sender, Dest: TObject; MsgCode: integer); overload;
function  fpgPeekMessage(Dest: TObject; MsgCode: integer; Msg: PfpgMessageRec = nil): Boolean;
procedure fpgDeliverMessage(var msg: TfpgMessageRec);
procedure fpgDeliverMessages;
procedure fpgCoalesceMessages;
function  fpgGetFirstMessage: PfpgMessageRec;
procedure fpgDeleteFirstMessage;
procedure fpgDeleteMessagesForTarget(Dest: TObject; MsgCode: integer = -1);
procedure fpgWaitWindowMessage;
```

**时间/暂停函数**：

```pascal
function fpgGetTickCount: QWord;            // 系统时钟（毫秒）
procedure fpgPause(MilliSeconds: Cardinal);// 暂停指定毫秒
function fpgCheckTimers: Boolean;           // 检查定时器队列
procedure fpgResetAllTimers;
function fpgClosestTimer(ctime: QWord; amaxtime: integer): integer;
```

### 2.8 异常处理、日志与调试方法

#### 2.8.1 异常处理

```pascal
// 设置全局异常处理
fpgApplication.OnException := @MyExceptionHandler;
fpgApplication.StopOnException := False;  // 异常时不停止消息循环

procedure MyExceptionHandler(Sender: TObject; E: Exception);
begin
  WriteLn('捕获到异常: ', E.Message);
end;
```

显示异常对话框：

```pascal
fpgApplication.ShowException(E);    // 显示标准异常对话框
fpgApplication.ShowBacktrace;       // 显示调用栈回溯
```

#### 2.8.2 日志（fpg_dbugintf.pas）

> 源码位置：`corelib/fpg_dbugintf.pas`

```pascal
uses fpg_dbugintf;

// 启动日志输出
InitializeDebugOutput;             // 初始化调试输出（写入 debug.ini 或控制台）
DebugLn('程序启动');
DebugLn('用户:', UserName);
DebugLnFmt('处理 %d 条记录', [Count]);
DebugMethodEnter('MyProcedure');  // 进入方法日志
DebugSeparator;                   // 输出分隔线
DebugWrite('逐字符');              // 不带换行
DumpStack;                        // 转储调用栈
PrintRect(r);                     // 打印矩形
PrintCoord(x, y);                  // 打印坐标
PrintCallTraceDbgLn('进入循环');   // 打印调用追踪
FinalizeDebugOutput;               // 关闭日志输出
```

#### 2.8.3 调试技巧

1. 使用 `fpgApplication.OnException` 捕获全局异常。
2. 在事件处理函数中插入 `DebugLn` 输出消息流向。
3. 如界面不刷新，检查是否调用了 `Invalidate` 而非直接绘制。
4. 长时间操作中调用 `fpgApplication.ProcessMessages` 保持 UI 响应。
5. 使用 `examples/corelib/eventtest` 工程观察每条消息触发时机。

### 2.9 国际化与多语言支持（编译时/运行时）

fpGUI 提供两种独立的本地化机制：**编译时 `.inc` 包含**和**运行时 `.po` 文件加载**。两者覆盖的都是 `fpg_constants.pas` 中以 `resourcestring` 声明的框架内置文本（按钮标题、月份/星期名、错误提示等），可按项目需求选择其一或组合使用。

源码位置：
- `corelib/fpg_constants.pas` — 资源字符串定义 + `{$DEFINE}` 开关
- `corelib/lang_*.inc` — 编译时翻译文件（每语言一个）
- `corelib/fpg_translations.pas` — 运行时 PO 文件加载
- `corelib/fpg_pofiles.pas` — PO 文件解析支持
- `framework/src/main/resources/languages/` — 随附 PO 文件

#### 2.9.1 支持的语言列表

| 语言 ID | 语言名称 | `.inc` 文件 | `.po` 文件 |
|---------|----------|------------|-----------|
| `en` | English（默认） | `lang_en.inc` | `fpgui.en.po` |
| `de` | German | `lang_de.inc` | `fpgui.de.po` |
| `fr` | French | `lang_fr.inc` | `fpgui.fr.po` |
| `ru` | Russian | `lang_ru.inc` | `fpgui.ru.po` |
| `pt` | Portuguese (Portugal) | `lang_pt.inc` | `fpgui.pt.po` |
| `pt_BR` | Portuguese (Brazil) | `lang_pt_BR.inc` | `fpgui.pt_BR.po` |
| `es` | Spanish | `lang_es.inc` | `fpgui.es.po` |
| `it` | Italian | `lang_it.inc` | `fpgui.it.po` |
| `af` | Afrikaans | `lang_af.inc` | `fpgui.af.po` |
| `pl` | Polish | `lang_pl.inc` | `fpgui.pl.po` |
| `et` | Estonian | `lang_et.inc` | `fpgui.et.po` |
| `uk` | Ukrainian | `lang_uk.inc` | `fpgui.uk.po` |
| `ms` | Malay | `lang_ms.inc` | `fpgui.ms.po` |
| `zh_CN` | 简体中文 | `lang_zh_CN.inc` | `fpgui.zh_CN.po` |
| `lo` | Lao | `lang_lo.inc` | `fpgui.lo.po` |
| `he` | Hebrew | `lang_he.inc` | `fpgui.he.po` |

#### 2.9.2 方式一：编译时指定语言（`.inc` 包含）

在 `fpg_constants.pas` 中通过条件编译指令 `{$DEFINE}` 选择语言。未定义任何符号时默认使用英语 `lang_en.inc`。

**机制**：`fpg_constants.pas` 的 `{$IF defined(xxx)}` 链会 `{$I lang_xx.inc}` 包含对应翻译文件，将 `resourcestring` 常量直接替换为目标语言文本，编译后内嵌于二进制中，无运行时文件依赖。

**方法 A — 修改源文件**：取消 `fpg_constants.pas` 中对应语言的注释：

```pascal
{ fpg_constants.pas 片段 }
{.$DEFINE de}     // 德语
{.$DEFINE zh_CN}  // 简体中文 — 取消注释即启用
```

**方法 B — 命令行编译时传递宏定义**（推荐，不修改源文件）：

```bash
# fpc 编译时通过 -d 传入语言符号
fpc -dzh_CN myapp.lpr
```

```bash
# 英文（默认，无需额外参数）
fpc myapp.lpr
```

```bash
# 多语言构建脚本示例
# 编译中文版
fpc -dzh_CN -oMyAppCN myapp.lpr
# 编译俄语版
fpc -dru -oMyAppRU myapp.lpr
```

> **避坑:** `lang_*.inc` 文件头部注释标注"This file is auto generated! DO NOT EDIT."（`lang_en.inc` 除外）。如需修改翻译，应编辑对应的 `.po` 文件后用工具重新生成 `.inc`，或直接编辑 `lang_en.inc`（英语为基准）。

#### 2.9.3 方式二：运行时加载 `.po` 文件

使用 `fpg_translations` 单元的 `TranslateResourceStrings` 过程在程序启动时动态加载 PO 翻译文件，无需重新编译，可在运行时切换语言。

**核心函数签名**：

```pascal
procedure TranslateResourceStrings(
  const BaseAppName,    // PO 文件名前缀，如 'fpgui'
  BaseDirectory,         // PO 文件所在目录（末尾可不带路径分隔符）
  CustomLang: string    // 自定义语言 ID；传 '' 则自动检测系统语言
);
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `BaseAppName` | `string` | 是 | PO 文件名前缀，实际文件名为 `<BaseAppName>.<lang>.po` |
| `BaseDirectory` | `string` | 是 | 搜索根目录；函数会优先查找 `<BaseDirectory>/languages/` 子目录 |
| `CustomLang` | `string` | 否 | 指定语言 ID（如 `'zh_CN'`）；传空串 `''` 则使用 `GetLanguageIDs` 自动检测系统语言 |

**PO 文件查找规则**：
1. 先搜索 `<BaseDirectory>/languages/<BaseAppName>.<lang>.po`
2. 若 `languages` 子目录不存在，回退到 `<BaseDirectory>/<BaseAppName>.<lang>.po`
3. `CustomLang` 为空时，使用 `GetText` 单元的 `GetLanguageIDs` 获取系统语言 ID 和回退语言 ID

**辅助函数**：

```pascal
function fpgMatchLocale(const ALanguageID: TfpgString): boolean;
```
比较给定语言 ID 是否与当前系统语言匹配，用于条件化 UI 逻辑。

**完整示例 — 运行时加载中文**：

```pascal
program PoDemo;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils,
  fpg_main,           // TfpgApplication
  fpg_form,           // TfpgForm
  fpg_button,        // TfpgButton
  fpg_translations;  // TranslateResourceStrings

type
  TMainForm = class(TfpgForm)
  public
    procedure AfterCreate; override;
  end;

  procedure TMainForm.AfterCreate;
  begin
    Name := 'frmMain';
    Width := 400;
    Height := 200;
    WindowTitle := 'PO 加载演示';
    // 调用 ShowMessage 时，按钮文本来自 resourcestring（rsOK, rsCancel 等）
    ShowMessage('启动成功！点击确定继续。');
  end;

var
  frm: TMainForm;
begin
  // 运行时加载中文 PO 文件
  // PO 文件位于 <程序目录>/languages/fpgui.zh_CN.po
  TranslateResourceStrings(
    'fpgui',            { BaseAppName }
    ExtractFilePath(ParamStr(0)),  { BaseDirectory = 程序所在目录 }
    'zh_CN'             { CustomLang = 指定中文 }
  );

  fpgApplication.Initialize;
  frm := TMainForm.Create(nil);
  frm.Show;
  fpgApplication.Run;
end.
```

**完整示例 — 自动检测系统语言**：

```pascal
begin
  // CustomLang 传空串，自动读取系统语言
  TranslateResourceStrings('fpgui', ExtractFilePath(ParamStr(0)), '');
  fpgApplication.Initialize;
  // ...
end.
```

> **避坑:**
> - PO 文件命名必须为 `<BaseAppName>.<lang>.po`（如 `fpgui.zh_CN.po`），否则 `TranslateResourceStrings` 找不到。
> - `languages/` 子目录是约定路径，优先于此目录下的 PO 文件被搜索。
> - OHOS/HarmonyOS 平台下 PO 文件需通过 C++ 桥接释放到沙箱 `files/languages/` 目录后传入该路径。
> - `TranslateResourceStrings` 应在 `fpgApplication.Initialize` 之前调用。
> - 运行时 PO 加载会覆盖编译时 `.inc` 的翻译结果（如果两者同时使用）。

#### 2.9.4 两种方式对比与选型建议

| 维度 | 编译时 `.inc` | 运行时 `.po` |
|------|--------------|-------------|
| 依赖文件 | 无（内嵌于二进制） | 需随程序分发 `.po` 文件 |
| 语言切换 | 需重新编译 | 运行时动态切换 |
| 二进制大小 | 略增（翻译文本内嵌） | 不变（运行时读文件） |
| 翻译修改 | 需重新编译 | 替换 `.po` 即可 |
| 适用场景 | 单语言固定发布、嵌入式/移动端 | 多语言桌面应用、需运行时切换 |
| OHOS 推荐 | 推荐（无沙箱文件依赖） | 需 C++ 桥接释放文件 |

> **最佳实践:** 桌面应用推荐运行时 `.po`（灵活性高）；OHOS/嵌入式推荐编译时 `.inc`（零运行时依赖）。两者可共存——先用 `.inc` 内嵌基础语言作为 fallback，再用 `.po` 按需覆盖。

### 2.10 命令行参数解析与命令模式

fpGUI 提供两套与"命令"相关的工具：**命令行参数解析**（`fpg_cmdlineparams` 单元）用于解析程序启动时的命令行参数；**命令模式**（`fpg_command_intf` 单元）是基于 Command 设计模式的 UI 动作抽象，类似 Delphi 的 `TAction`。

源码位置：
- `corelib/fpg_cmdlineparams.pas` — `ICmdLineParams` 接口与 `TfpgCmdLineParams` 实现类
- `corelib/fpg_command_intf.pas` — `ICommand` / `ICommandHolder` 命令模式接口
- `corelib/fpg_base.pas` — `TfpgApplicationBase` 实现 `ICmdLineParams`（通过 `Supports` 获取）

#### 2.10.1 命令行参数解析（fpg_cmdlineparams）

`TfpgApplicationBase` 实现了 `ICmdLineParams` 接口，因此可通过 `Supports(fpgApplication, ICmdLineParams, cmd)` 获取命令行参数解析器实例，无需手动创建。

**接口定义**：

```pascal
ICmdLineParams = interface
  function  GetOptionValue(const S: string): string;                    { 长选项值 }
  function  GetOptionValue(const C: char; const S: string): string;     { 短/长选项值 }
  function  GetOptionValues(const C: Char; const S: string): TStringArray; { 多次出现的选项值数组 }
  function  HasOption(const S: string): Boolean;                        { 长选项是否存在 }
  function  HasOption(const C: char; const S: string): Boolean;         { 短/长选项是否存在 }
  function  CheckOptions(const ShortOptions: string; const LongOpts: ...): string; { 校验参数合法性 }
  function  GetNonOptions(const ShortOptions: string; const LongOpts: ...): TStringArray; { 获取非选项参数 }
  procedure GetNonOptions(...; NonOptions: TStrings);                    { 同上，输出到 TStrings }
  property  OptionChar: char;           { 选项前缀字符，默认 '-' }
  property  CaseSensitiveOptions: Boolean; { 选项是否区分大小写，默认 True }
  property  Params[Index: integer]: string; { 原始参数（0 = 程序名） }
  property  ParamCount: integer;          { 参数个数（不含程序名） }
end;
```

**属性与方法详解**：

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `OptionChar` | `char` | 读写 | `'-'` | 选项前缀字符，OHOS/Windows 常用 `-`，也可改为 `/` |
| `CaseSensitiveOptions` | `Boolean` | 读写 | `True` | 选项是否区分大小写；设为 `False` 则 `-H` 和 `-h` 等价 |
| `Params[Index]` | `string` | 只读 | — | 原始命令行参数，`Params[0]` 为程序路径 |
| `ParamCount` | `integer` | 只读 | — | 参数个数（不含程序名），等价 `System.ParamCount` |
| `HasOption(S)` | `Boolean` | — | — | 检查长选项 `--S` 是否存在 |
| `HasOption(C, S)` | `Boolean` | — | — | 检查短选项 `-C` 或长选项 `--S` 是否存在 |
| `GetOptionValue(S)` | `string` | — | — | 获取长选项 `--S=value` 的值；无值返回空串 |
| `GetOptionValue(C, S)` | `string` | — | — | 优先找短选项 `-C value`，再找长选项 `--S=value` |
| `GetOptionValues(C, S)` | `TStringArray` | — | — | 获取同一选项多次出现的所有值 |
| `CheckOptions(...)` | `string` | — | — | 校验参数合法性，返回错误信息（空串=合法） |
| `GetNonOptions(...)` | `TStringArray`/`TStrings` | — | — | 提取非选项参数（如文件路径） |

**选项格式约定**：
- 短选项：`-n value`（选项字符 + 空格 + 值）
- 长选项：`--newinstance`（开关型，无值）或 `--file=path.txt`（带值型，用 `=` 连接）
- 非选项：不以 `OptionChar` 开头的参数，通常是文件路径等

**完整示例 — 解析命令行参数**（取自 `examples/apps/nanoedit/helloworld.lpr`）：

```pascal
program CmdLineDemo;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils,
  fpg_main,             // fpgApplication
  fpg_cmdlineparams;    // ICmdLineParams

var
  cmd: ICmdLineParams;
  i: Integer;
  nonOpts: TStringArray;
begin
  fpgApplication.Initialize;

  // 通过 Supports 获取 ICmdLineParams 接口
  if Supports(fpgApplication, ICmdLineParams, cmd) then
  begin
    // 检查短选项 -n 或长选项 --newinstance 是否存在
    if cmd.HasOption('n', 'newinstance') then
      WriteLn('启动新实例模式')
    else
      WriteLn('普通启动模式');

    // 获取长选项值: myapp --config=/etc/myapp.ini
    if cmd.HasOption('config') then
      WriteLn('配置文件: ', cmd.GetOptionValue('config'));

    // 获取短选项值: myapp -f data.txt
    if cmd.HasOption('f', 'file') then
      WriteLn('文件参数: ', cmd.GetOptionValue('f', 'file'));

    // 遍历所有非选项参数（文件路径）
    nonOpts := cmd.GetNonOptions('f', ['config', 'newinstance']);
    for i := 0 to High(nonOpts) do
      WriteLn('非选项参数[', i, ']: ', nonOpts[i]);

    // 校验参数合法性
    // ShortOptions: 'f:' 表示 -f 需要参数; 无冒号=开关型
    // LongOpts: 数组形式，'config:' 需要参数，'newinstance' 开关型
    WriteLn('校验结果: ', cmd.CheckOptions('f:', ['config:', 'newinstance']));
  end;

  fpgApplication.Run;
end.
```

**CheckOptions 语法规则**：
- 短选项字符串格式与 GNU getopt 兼容：`'f:'` 表示 `-f` 需要参数；`'v'` 表示 `-v` 是开关型
- 长选项数组格式：`'config:'` 需要参数；`'verbose'` 开关型；`'debug::'` 可选参数
- 返回空串表示全部合法；返回非空串为格式化的错误信息
- 设 `AllErrors := True` 可收集所有错误（默认只报第一个）

> **避坑:**
> - `Params[0]` 是程序路径，`Params[1]` 才是第一个用户参数。
> - 短选项值通过空格分隔（`-f file.txt`），长选项值通过 `=` 连接（`--file=file.txt`），不可混用。
> - `CaseSensitiveOptions` 默认为 `True`，若希望 `-H` 和 `-h` 等价需手动设为 `False`。
> - `GetOptionValue` 在选项不存在时返回空串，需配合 `HasOption` 先检查。
> - 获取 `ICmdLineParams` 必须用 `Supports(fpgApplication, ICmdLineParams, cmd)`，不能直接 `TfpgCmdLineParams.Create`（虽然语法允许，但会绕过框架的参数注入）。

#### 2.10.2 命令模式（fpg_command_intf）

基于 Command 设计模式，将 UI 动作封装为独立对象，实现调用者与接收者解耦，类似 Delphi 的 `TAction`。

**接口定义**：

```pascal
ICommand = interface(IInterface)
  procedure Execute;    { 执行命令 }
end;

ICommandHolder = interface(IInterface)
  function  GetCommand: ICommand;        { 获取关联的命令对象 }
  procedure SetCommand(ACommand: ICommand); { 设置关联的命令对象 }
end;
```

| 接口 | 方法 | 说明 |
|------|------|------|
| `ICommand` | `Execute` | 执行封装的动作；由菜单项、按钮等控件在用户交互时调用 |
| `ICommandHolder` | `GetCommand` | 获取控件持有的命令对象 |
| `ICommandHolder` | `SetCommand(ACommand)` | 将命令对象绑定到控件；控件触发时自动调用 `Execute` |

**使用场景**：
- 菜单项和工具栏按钮共享同一动作（如"保存"命令同时出现在菜单和工具栏）
- 撤销/重做栈（将每个操作封装为 `ICommand` 压入栈中）
- 宏录制（按顺序执行一系列 `ICommand`）
- 跨组件复用业务逻辑

**完整示例 — 自定义命令**：

```pascal
program CommandPatternDemo;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils,
  fpg_main,
  fpg_form,
  fpg_button,
  fpg_command_intf;  // ICommand, ICommandHolder

type
  { 具体命令：退出程序 }
  TExitCommand = class(TInterfacedObject, ICommand)
    procedure Execute;
  end;

  { 具体命令：显示消息 }
  TShowMsgCommand = class(TInterfacedObject, ICommand)
    private
      FMsg: string;
    public
      constructor Create(const AMsg: string);
      procedure Execute;
    end;

  TMainForm = class(TfpgForm)
    btnExit: TfpgButton;
    btnMsg: TfpgButton;
    procedure AfterCreate; override;
  end;

  procedure TExitCommand.Execute;
  begin
    fpgApplication.Terminate;
  end;

  constructor TShowMsgCommand.Create(const AMsg: string);
  begin
    FMsg := AMsg;
  end;

  procedure TShowMsgCommand.Execute;
  begin
    ShowMessage(FMsg);
  end;

  procedure TMainForm.AfterCreate;
  var
    cmdExit: ICommand;
    cmdMsg: ICommand;
  begin
    Width := 300;
    Height := 150;
    WindowTitle := 'Command 模式演示';

    btnExit := TfpgButton.Create(self);
    btnExit.Text := '退出';
    btnExit.Top := 20;
    btnExit.Left := 50;
    btnExit.Width := 200;

    btnMsg := TfpgButton.Create(self);
    btnMsg.Text := '显示消息';
    btnMsg.Top := 60;
    btnMsg.Left := 50;
    btnMsg.Width := 200;

    // 将命令绑定到按钮（如果按钮实现了 ICommandHolder）
    cmdExit := TExitCommand.Create;
    cmdMsg := TShowMsgCommand.Create('Hello from Command!');
    // 通过 OnClick 也可以触发命令
    btnExit.OnClick := @btnExitClick;
  end;

var
  frm: TMainForm;
begin
  fpgApplication.Initialize;
  frm := TMainForm.Create(nil);
  frm.Show;
  fpgApplication.Run;
end.
```

> **避坑:**
> - `ICommand` 实现类必须继承 `TInterfacedObject`（或实现 `IInterface` 的引用计数），否则接口对象会被提前释放。
> - `Execute` 无参数无返回值；如需传递上下文数据，应在命令对象构造时注入。
> - `ICommandHolder` 是可选接口——控件不强制实现它；对于不实现该接口的控件（如 `TfpgButton`），可通过 `OnClick` 事件手动调用 `cmd.Execute`。

### 2.11 布局管理器（MigLayout / FlowLayout / BorderLayout）

fpGUI 提供三种布局管理器，均实现 `ILayoutManager` 接口，通过 `TfpgWidget.LayoutManager` 属性挂载到任意容器控件。布局管理器负责自动计算子控件的位置和大小，替代手动设置 `Left`/`Top`/`Width`/`Height`。

源码位置：
- `corelib/fpg_layouttypes.pas` — `ILayoutManager` 接口、`TfpgLayoutConstraint` 基类
- `corelib/fpg_layoutmanager.pas` — `TfpgBaseLayoutManager` 抽象基类
- `corelib/fpg_miglayout.pas` — MigLayout（移植自 Java MigLayout v11.4.2）
- `corelib/fpg_flowlayout.pas` — FlowLayout
- `corelib/fpg_borderlayout.pas` — BorderLayout

#### 2.11.0 通用架构

所有布局管理器实现 `ILayoutManager` 接口：

```pascal
ILayoutManager = interface
  procedure LayoutContainer(AContainer: TfpgWidgetBase);
  function GetPreferredSize(AContainer: TfpgWidgetBase): TfpgSize;
  function GetMinimumSize(AContainer: TfpgWidgetBase): TfpgSize;
  procedure AddLayoutComponent(AWidget: TfpgWidgetBase; AConstraint: TfpgLayoutConstraint);
  procedure RemoveLayoutComponent(AWidget: TfpgWidgetBase);
  procedure InvalidateLayout(AContainer: TfpgWidgetBase);
  procedure PaintDebug(AWidget: TfpgWidgetBase; ACanvas: TfpgCanvasBase);
end;
```

| 方法 | 说明 |
|------|------|
| `LayoutContainer` | 执行布局：遍历子控件，根据约束设置位置和大小 |
| `GetPreferredSize` | 计算容器理想尺寸（含所有子控件的 PreferredSize） |
| `GetMinimumSize` | 计算容器最小尺寸 |
| `AddLayoutComponent(AWidget, AConstraint)` | 将子控件加入布局，附带约束对象 |
| `RemoveLayoutComponent(AWidget)` | 从布局中移除子控件 |
| `InvalidateLayout` | 标记布局脏，下次绘制时重新计算 |
| `PaintDebug` | 绘制调试可视化（网格线、单元格边界） |

**挂载方式**：

```pascal
var
  lm: ILayoutManager;
begin
  lm := TfpgMigLayoutManager.Create as ILayoutManager;
  Self.LayoutManager := lm;  // 赋值给容体的 LayoutManager 属性
end;
```

> **避坑:** 设置 `LayoutManager` 后，子控件必须通过 `AddLayoutComponent` 而非 `Parent := Self` 加入容器（`Parent` 仅建立父子关系，不触发布局约束注册）。

#### 2.11.1 MigLayout（移植自 Java）

MigLayout 是最强大的布局管理器，移植自 Java MigLayout v11.4.2，支持网格布局、跨单元格（span）、对齐、间距、增长/收缩权重、停靠（dock）等。采用**流式 API**（Fluent API）配置约束。

**核心类**：`TfpgMigLayoutManager`（继承 `TfpgBaseLayoutManager`）

**构造与属性**：

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `LC` | `TfpgMigLC` | 读写 | 新建 | 容器级布局约束（流向、网格、间距、填充、调试等） |
| `RowConstraints` | `TfpgMigAC` | 读写 | 新建 | 行级约束数组（每行的间距/增长/对齐） |
| `ColumnConstraints` | `TfpgMigAC` | 读写 | 新建 | 列级约束数组（每列的间距/增长/对齐） |

**TfpgMigLC — 容器级约束（流式 API）**：

| 方法 | 说明 | 示例 |
|------|------|------|
| `WrapAfter(ACount)` | N 个组件后自动换行（定义列数） | `mig.LC.WrapAfter(2)` → 2 列 |
| `Wrap` | 启用自动换行 | `mig.LC.Wrap` |
| `Fill` | 单元格填充容器（X+Y） | `mig.LC.Fill` |
| `FillX` / `FillY` | 仅水平/垂直填充 | `mig.LC.FillX` |
| `FlowX` | 水平流向（默认） | `mig.LC.FlowX` |
| `FlowY` | 垂直流向 | `mig.LC.FlowY` |
| `GridGap(X, Y)` | 设置单元格间距 | `mig.LC.GridGap('10', '10')` |
| `Insets(T, L, B, R)` | 容器内边距 | `mig.LC.Insets('10', '5', '10', '5')` |
| `InsetsAll(S)` | 四边统一内边距 | `mig.LC.InsetsAll('10')` |
| `AlignX(S)` / `AlignY(S)` | 整体对齐 | `mig.LC.AlignX('center')` |
| `Width(S)` / `Height(S)` | 容器固定尺寸 | `mig.LC.Width('400')` |
| `MinWidth(S)` / `MaxWidth(S)` | 容器最小/最大尺寸 | `mig.LC.MinWidth('300')` |
| `Pack` | 收缩容器到首选尺寸 | `mig.LC.Pack` |
| `Debug` | 启用调试可视化 | `mig.LC.Debug` |
| `NoGrid` | 禁用网格（纯流式） | `mig.LC.NoGrid` |
| `LeftToRight(B)` / `RightToLeft` | 流向方向 | `mig.LC.RightToLeft` |
| `TopToBottom` / `BottomToTop` | 垂直流向方向 | `mig.LC.BottomToTop` |
| `HideMode(AMode)` | 隐藏组件的处理方式 | `mig.LC.HideMode(0)` |

**TfpgMigCC — 组件级约束（流式 API，79 个方法）**：

| 分类 | 方法 | 说明 |
|------|------|------|
| **尺寸** | `Width(S)` / `Height(S)` | 设置宽/高（格式 `min:pref:max`） |
| | `MinWidth(S)` / `MaxWidth(S)` | 最小/最大宽度 |
| | `MinHeight(S)` / `MaxHeight(S)` | 最小/最大高度 |
| **增长** | `GrowX` / `GrowY` | 水平/垂直增长（权重 100） |
| | `GrowX(W)` / `GrowY(W)` | 指定增长权重 |
| | `Grow(WX, WY)` | 双向增长 |
| | `GrowPrioX(P)` / `GrowPrioY(P)` | 增长优先级 |
| **收缩** | `ShrinkX(W)` / `ShrinkY(W)` | 水平/垂直收缩权重 |
| | `Shrink(WX, WY)` | 双向收缩 |
| | `ShrinkPrioX(P)` / `ShrinkPrioY(P)` | 收缩优先级 |
| **对齐** | `AlignX(S)` / `AlignY(S)` | 水平/垂直对齐（`'left'`/`'center'`/`'right'`/`'fill'`，垂直含 `'top'`/`'bottom'`/`'baseline'`） |
| **间距** | `GapX(B, A)` / `GapY(B, A)` | 水平/垂直前后间距 |
| | `GapBefore(S)` / `GapAfter(S)` | 前方/后方间距 |
| | `GapTop(S)` / `GapBottom(S)` | 顶部/底部间距 |
| | `GapLeft(S)` / `GapRight(S)` | 左/右间距 |
| **跨格** | `SpanX(N)` / `SpanY(N)` | 水平/垂直跨 N 个单元格 |
| | `Span(X, Y)` | 双向跨格 |
| | `Split(N)` | 将当前单元格拆分为 N 列 |
| | `Skip(N)` | 跳过 N 个单元格 |
| **换行** | `Wrap` / `Wrap(Gap)` | 此组件后换行 |
| | `Newline` / `Newline(Gap)` | 此组件前换行 |
| **停靠** | `DockNorth` / `DockSouth` | 停靠到北/南边 |
| | `DockWest` / `DockEast` | 停靠到西/东边 |
| **绝对定位** | `Pos(X1, Y1)` / `Pos(X1, Y1, X2, Y2)` | 绝对位置 |
| | `X(S)` / `X2(S)` / `Y(S)` / `Y2(S)` | 单边绝对位置 |
| **分组** | `SizeGroupX(G)` / `SizeGroupY(G)` | 同尺寸组 |
| | `EndGroupX(G)` / `EndGroupY(G)` | 末端对齐组 |
| **其他** | `Cell(Col, Row)` | 指定单元格位置 |
| | `Tag(S)` | 逻辑标签 |
| | `Id(S)` | 组件 ID（用于链接） |
| | `Pad(S)` / `Pad(T, L, B, R)` | 组件内边距 |
| | `External` | 组件在容器外 |
| | `Push` / `PushX` / `PushY` | 推开其他组件的权重 |
| | `HideMode(M)` | 隐藏模式 |

**TfpgMigAC — 轴级约束（行/列约束，流式 API）**：

`TfpgMigAC` 持有一组 `TfpgMigDimConstraint`，分别对应每一行或每一列。通过 `TfpgMigLayoutManager.RowConstraints` / `ColumnConstraints` 属性赋值。方法支持两种调用形式：无索引参数时操作当前行/列（`FCurIndex`），带索引参数时操作指定行/列。

| 方法 | 说明 | 示例 |
|------|------|------|
| `Count(N)` | 设置行/列总数为 N | `ac.Count(3)` |
| `Index(I)` | 设置当前操作索引为 I（后续无索引方法操作此行/列） | `ac.Index(2)` |
| `Size(S)` / `Size(S, I)` | 设置当前/指定行/列的尺寸（`min:pref:max` 格式） | `ac.Size('100:200:300')` |
| `Fill` / `Fill(I)` | 当前/指定行/列填充（组件默认增长） | `ac.Fill` |
| `Gap` | 默认间距，自动移到下一行/列 | `ac.Gap` |
| `Gap(S)` / `Gap(S, I)` | 设置当前/指定行/列的后间距并移到下一行/列 | `ac.Gap('10px')` |
| `Align(S)` / `Align(S, I)` | 设置行/列内组件对齐方式 | `ac.Align('center')` |
| `Grow` / `Grow(W)` / `Grow(W, I)` | 增长权重（无参=100） | `ac.Grow(200)` |
| `GrowPrio(P)` / `GrowPrio(P, I)` | 增长优先级 | `ac.GrowPrio(500)` |
| `Shrink` / `Shrink(W)` / `Shrink(W, I)` | 收缩权重（无参=100） | `ac.Shrink` |
| `ShrinkPrio(P)` / `ShrinkPrio(P, I)` | 收缩优先级 | `ac.ShrinkPrio(500)` |
| `SizeGroup(G)` / `SizeGroup(G, I)` | 同尺寸组名 | `ac.SizeGroup('col1')` |
| `NoGrid` / `NoGrid(I)` | 标记行/列为非网格（合并单元格） | `ac.NoGrid` |
| `GetCount` | 返回行/列数 | `n := ac.GetCount` |
| `GetConstraints` | 返回所有 `TfpgMigDimConstraint` 数组 | `arr := ac.GetConstraints` |
| `SetConstraints(Arr)` | 从数组设置约束 | `ac.SetConstraints(arr)` |

**AC 链式调用示例**：

```pascal
var
  mig: TfpgMigLayoutManager;
  colAC: TfpgMigAC;
begin
  mig := TfpgMigLayoutManager.Create;
  // 定义 3 列：第 0 列固定 80lp，第 1 列增长，第 2 列固定 100lp
  colAC := TfpgMigAC.Create;
  colAC.Size('80lp').Gap;       // 第 0 列：宽 80lp，默认间距
  colAC.Size('min:pref:max').Gap.Grow;  // 第 1 列：增长
  colAC.Size('100lp');          // 第 2 列：宽 100lp
  mig.ColumnConstraints := colAC;

  // 定义 3 行：第 0 行固定高度，第 1 行增长，第 2 行固定
  mig.RowConstraints := TfpgMigAC.Create
    .Size('30lp').Gap           // 第 0 行：高 30lp
    .Grow                       // 第 1 行：增长
    .Size('40lp');              // 第 2 行：高 40lp

  LayoutManager := mig;
end;
```

#### 2.11.1a Fluent API 链式调用模式

LC、AC、CC 三个约束类均采用**流式 API（Fluent API）**设计：每个配置方法返回 `Self`（当前对象），允许在同一语句中链式调用多个方法。这是从 Java MigLayout 移植的核心设计模式。

**链式调用原理**：

```pascal
// 每个方法返回 Self，等价于：
TfpgMigCC.Create.GrowX.AlignX('center').SpanX(3);
// 分解为：
var cc := TfpgMigCC.Create;
cc.GrowX;         // 返回 cc
cc.AlignX('center'); // 返回 cc
cc.SpanX(3);      // 返回 cc
```

**三约束协作模型**：

| 约束类 | 作用层级 | 赋值方式 | 链式入口 |
|--------|----------|----------|----------|
| `TfpgMigLC` | 容器级（整体布局行为） | `mig.LC.XXX` | `mig.LC.Fill.WrapAfter(2).GridGap('5', '5')` |
| `TfpgMigAC` | 轴级（每行/每列属性） | `mig.RowConstraints := TfpgMigAC.Create...` | `TfpgMigAC.Create.Size('30lp').Gap.Grow` |
| `TfpgMigCC` | 组件级（单个控件属性） | `mig.AddLayoutComponent(w, TfpgMigCC.Create...)` | `TfpgMigCC.Create.GrowX.SpanX(2).AlignX('right')` |

**典型链式调用对照**：

| 场景 | LC 链 | AC 链 | CC 链 |
|------|-------|-------|-------|
| 2 列表单 | `.WrapAfter(2).Fill` | — | `.GrowX` (输入框) |
| 3×3 对齐网格 | `.WrapAfter(3).Fill` | — | `.AlignX('left').AlignY('top')` |
| 固定列宽 | — | `.Size('80lp').Gap.Grow.Size('100lp')` | — |
| 按钮跨列右对齐 | — | — | `.SpanX(3).AlignX('right').Tag('btn')` |
| Memo 双向增长 | — | — | `.SpanX(4).GrowX.GrowY` |
| 带间距调试 | `.WrapAfter(2).GridGap('10','10').Debug` | — | `.GapX('5','0')` |

**完整示例 — 复杂注册表单**（取自 `examples/gui/lm-mig/frm_complex.pas`）：

```pascal
procedure TComplexMigForm.AfterCreate;
var
  mig: TfpgMigLayoutManager;
  lblTitle, lblName: TfpgLabel;
  edtName: TfpgEdit;
  chkNewsletter: TfpgCheckBox;
  memoComments: TfpgMemo;
  btnOK, btnCancel: TfpgButton;
begin
  mig := TfpgMigLayoutManager.Create;
  mig.LC.WrapAfter(4);   // 4 列
  mig.LC.Fill;            // 填充容器
  mig.LC.Debug;           // 调试可视化
  LayoutManager := mig;

  // 标题跨 4 列居中
  lblTitle := TfpgLabel.Create(Self);
  lblTitle.Text := 'User Registration Form';
  mig.AddLayoutComponent(lblTitle,
    TfpgMigCC.Create.SpanX(4).AlignX('center'));

  // 标签 + 输入框（输入框跨 3 列并水平增长）
  lblName := TfpgLabel.Create(Self);
  lblName.Text := 'Full Name:';
  mig.AddLayoutComponent(lblName,
    TfpgMigCC.Create.MinWidth('80lp'));

  edtName := TfpgEdit.Create(Self);
  mig.AddLayoutComponent(edtName,
    TfpgMigCC.Create.SpanX(3).GrowX);

  // 复选框跨 4 列
  chkNewsletter := TfpgCheckBox.Create(Self);
  chkNewsletter.Text := 'Subscribe to newsletter';
  mig.AddLayoutComponent(chkNewsletter,
    TfpgMigCC.Create.SpanX(4));

  // Memo 跨 4 列双向增长
  memoComments := TfpgMemo.Create(Self);
  mig.AddLayoutComponent(memoComments,
    TfpgMigCC.Create.SpanX(4).GrowX.GrowY);

  // 按钮行：OK 跨 3 列右对齐，Cancel 占 1 列
  btnOK := TfpgButton.Create(Self);
  btnOK.Text := 'Submit';
  mig.AddLayoutComponent(btnOK,
    TfpgMigCC.Create.SpanX(3).AlignX('right').Tag('buttons'));

  btnCancel := TfpgButton.Create(Self);
  btnCancel.Text := 'Cancel';
  mig.AddLayoutComponent(btnCancel,
    TfpgMigCC.Create.AlignX('right').Tag('buttons'));
end;
```

**完整示例 — 增长行为演示**（取自 `examples/gui/lm-mig/frm_growth.pas`）：

```pascal
procedure TGrowthMigForm.AfterCreate;
var
  mig: TfpgMigLayoutManager;
  lbl1, lbl2: TfpgLabel;
  edt1: TfpgEdit;
  btn1, btn2, btn3: TfpgButton;
  memo: TfpgMemo;
begin
  mig := TfpgMigLayoutManager.Create;
  mig.LC.WrapAfter(2);   // 2 列
  mig.LC.Fill;             // 填充（触发增长分配）
  LayoutManager := mig;

  // 标题跨 2 列居中
  lbl1 := TfpgLabel.Create(Self);
  lbl1.Text := 'Growth Demo';
  mig.AddLayoutComponent(lbl1,
    TfpgMigCC.Create.SpanX(2).AlignX('center'));

  // 固定宽度按钮（不增长）
  lbl2 := TfpgLabel.Create(Self);
  lbl2.Text := 'No Grow:';
  mig.AddLayoutComponent(lbl2, TfpgMigCC.Create.MinWidth('70lp'));

  btn1 := TfpgButton.Create(Self);
  btn1.Text := 'Fixed Width';
  mig.AddLayoutComponent(btn1, TfpgMigCC.Create);  // 无 Grow，固定大小

  // 增长的输入框
  edt1 := TfpgEdit.Create(Self);
  mig.AddLayoutComponent(edt1, TfpgMigCC.Create.GrowX);  // 水平增长

  // 双向增长的 Memo
  memo := TfpgMemo.Create(Self);
  mig.AddLayoutComponent(memo,
    TfpgMigCC.Create.SpanX(2).GrowX.GrowY);  // 水平+垂直增长

  // 底部居中按钮，限制最大宽度
  btn3 := TfpgButton.Create(Self);
  btn3.Text := 'Close (maxWidth=550)';
  btn3.MaxWidth := 550;
  mig.AddLayoutComponent(btn3,
    TfpgMigCC.Create.SpanX(2).AlignX('center'));
end;
```

> **避坑:**
> - 链式调用中方法顺序有时很重要：`SpanX(N)` 定义跨格范围，`Split(N)` 拆分单元格，`Split` 必须在 `SpanX` 之前。
> - `TfpgMigCC.Create` 每次创建一个新约束对象，不可复用给多个组件。
> - `TfpgMigAC.Gap` 无参数版本会自动递增 `FCurIndex`（移到下一行/列），相当于"配置完当前行/列并移动到下一个"。
> - `TfpgMigAC` 的 `Size('80lp')` 中 `lp` 是逻辑像素单位，会根据 DPI 自动缩放；也可用 `px`（物理像素）、`mm`、`cm`、`%`（百分比）等。
> - 尺寸字符串格式为 `min:pref:max`（如 `'10:100:200'`），单独数字表示首选值，`min:pref` 省略 max 时 max=首选值。

```pascal
uses
  fpg_miglayout, fpg_mig_lc, fpg_mig_cc;

procedure TForm.AfterCreate;
var
  mig: TfpgMigLayoutManager;
  lbl: TfpgLabel;
  edt: TfpgEdit;
  btn: TfpgButton;
begin
  mig := TfpgMigLayoutManager.Create;
  mig.LC.WrapAfter(2);    // 2 列网格
  mig.LC.Debug;           // 调试可视化
  LayoutManager := mig;

  // 第 1 行：标签 + 输入框
  lbl := TfpgLabel.Create(Self);
  lbl.Text := 'Name:';
  mig.AddLayoutComponent(lbl, TfpgMigCC.Create);

  edt := TfpgEdit.Create(Self);
  edt.PreferredSize := fpgSize(200, 24);
  mig.AddLayoutComponent(edt, TfpgMigCC.Create.GrowX);  // 水平增长

  // 第 2 行：按钮跨 2 列
  btn := TfpgButton.Create(Self);
  btn.Text := 'OK';
  btn.PreferredSize := fpgSize(80, 24);
  mig.AddLayoutComponent(btn, TfpgMigCC.Create.SpanX.Split(2).Tag('ok'));
end;
```

**完整示例 — 3×3 对齐网格**（取自 `examples/gui/lm-mig/frm_alignment.pas`）：

```pascal
procedure TForm.AfterCreate;
var
  mig: TfpgMigLayoutManager;
  btn: TfpgButton;
begin
  mig := TfpgMigLayoutManager.Create;
  mig.LC.WrapAfter(3);  // 3 列
  mig.LC.Fill;          // 单元格填充容器
  LayoutManager := mig;

  btn := TfpgButton.Create(Self);
  btn.Text := 'Top Left';
  mig.AddLayoutComponent(btn, TfpgMigCC.Create.AlignX('left').AlignY('top'));

  btn := TfpgButton.Create(Self);
  btn.Text := 'Center';
  mig.AddLayoutComponent(btn, TfpgMigCC.Create.AlignX('center').AlignY('center'));

  btn := TfpgButton.Create(Self);
  btn.Text := 'Bottom Right';
  mig.AddLayoutComponent(btn, TfpgMigCC.Create.AlignX('right').AlignY('bottom'));
end;
```

> **避坑:**
> - `TfpgMigCC.Create` 每次创建一个新约束对象，不可复用给多个组件。
> - 尺寸字符串格式为 `min:pref:max`（如 `'10:100:200'`），单独数字表示首选值。
> - `GrowX` 无参数版本等价于 `GrowX(100)`（权重 100）。
> - `SpanX` 无参数版本等价于 `SpanX(1)`，需传参才能跨格（如 `SpanX(3)` 跨 3 列）。
> - `Split(N)` 必须在 `SpanX` 之前调用，否则拆分的是子单元格而非父单元格。
> - MigLayout 的 DPI 缩放由 `TfpgMigPlatformDefaults` 管理，与 `Screen_dpi` 联动。

#### 2.11.2 FlowLayout

流式布局管理器，将组件按行排列，类似文本段落——超出容器宽度自动换行。适合工具栏、按钮组等简单场景。

**核心类**：`TfpgFlowLayoutManager`（继承 `TfpgBaseLayoutManager`）

**构造函数**：

```pascal
constructor Create; override; overload;                            // 默认间距 5px
constructor Create(const hgap: integer; const vgap: integer); overload;  // 自定义间距
```

**属性**：

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Alignment` | `TfpgFlowLayoutAlignment` | 读写 | `flaLeft` | 水平对齐方式 |
| `VAlignment` | `TfpgFlowLayoutVAlignment` | 读写 | `flvaTop` | 垂直对齐方式 |
| `HGap` | `TfpgCoord` | 读写 | `5` | 水平间距（组件间） |
| `VGap` | `TfpgCoord` | 读写 | `5` | 垂直间距（行间） |

**对齐枚举**：

| 枚举 | 值 | 说明 |
|------|------|------|
| `TfpgFlowLayoutAlignment` | `flaLeft` | 左对齐 |
| | `flaCenter` | 居中 |
| | `flaRight` | 右对齐 |
| `TfpgFlowLayoutVAlignment` | `flvaTop` | 顶部对齐 |
| | `flvaCenter` | 垂直居中 |
| | `flvaBottom` | 底部对齐 |

**完整示例**（取自 `examples/gui/lm-flow/frm_simple.pas`）：

```pascal
uses
  fpg_flowlayout, fpg_layouttypes;

procedure TSimpleFlowForm.AfterCreate;
var
  FlowLayout: ILayoutManager;
  i: integer;
  Btn: TfpgButton;
begin
  SetPosition(518, 365, 300, 250);
  WindowTitle := 'Simple Flow Form';

  FlowLayout := TfpgFlowLayoutManager.Create as ILayoutManager;
  LayoutManager := FlowLayout;

  for i := 1 to 10 do
  begin
    Btn := TfpgButton.Create(Self);
    Btn.Text := Format('Button %d', [i]);
    Btn.Width := 60 + (i * 5);   // 递增宽度，迫使换行
    Btn.Height := 30;
    FlowLayout.AddLayoutComponent(Btn, TfpgLayoutConstraint.Create());
  end;
end;
```

> **避坑:**
> - FlowLayout 的约束对象是空的 `TfpgLayoutConstraint`（无额外参数），不同于 MigLayout 的 `TfpgMigCC`。
> - 组件的 `PreferredSize` 决定其在流式布局中的大小；若未设置则使用 `Width`/`Height`。
> - 换行基于容器 `GetClientRect` 的宽度计算；容器尺寸未确定时使用默认 400px。
> - `HGap`/`VGap` 变更后不会自动触发重布局，需手动调用 `InvalidateLayout`。

#### 2.11.3 BorderLayout

五区域布局管理器，将容器分为北（North）、南（South）、东（East）、西（West）、中（Center）五个区域。Center 区域自动填充剩余空间。适合主窗口布局（工具栏在 North、状态栏在 South、侧边栏在 West、内容在 Center）。

**核心类**：`TfpgBorderLayoutManager`（继承 `TfpgBaseLayoutManager`）

**构造函数**：

```pascal
constructor Create; override; overload;                            // 默认间距 0
constructor Create(const hgap: integer; const vgap: integer); overload;  // 自定义间距
```

**属性**：

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `HGap` | `integer` | 读写 | `0` | 水平间距（区域间） |
| `VGap` | `integer` | 读写 | `0` | 垂直间距（区域间） |

**约束类**：`TfpgBorderLayoutConstraint`

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Region` | `TfpgBorderLayoutRegion` | 读写 | `blrCenter` | 组件放置的区域 |

**区域枚举**：

| 枚举值 | 说明 | 尺寸规则 |
|--------|------|----------|
| `blrNorth` | 北部（顶部） | 高度=PreferredHeight，宽度=容器宽度 |
| `blrSouth` | 南部（底部） | 高度=PreferredHeight，宽度=容器宽度 |
| `blrWest` | 西部（左侧） | 宽度=PreferredWidth，高度=剩余高度 |
| `blrEast` | 东部（右侧） | 宽度=PreferredWidth，高度=剩余高度 |
| `blrCenter` | 中部 | 宽高=剩余空间（自动填充） |

**布局规则**：
1. North/South 组件占满容器宽度，高度为 PreferredHeight
2. West/East 组件占满剩余高度，宽度为 PreferredWidth
3. Center 组件填充 North/South/West/East 之间的剩余空间
4. 每个区域最多一个组件；同区域多组件时后者覆盖前者

**完整示例**（取自 `examples/gui/lm-border/lm_border.pas`）：

```pascal
uses
  fpg_borderlayout, fpg_layoutmanager;

procedure TMainForm.AfterCreate;
var
  pnl: TfpgPanel;
  btn: TfpgButton;
  lm: TfpgBorderLayoutManager;
  constraint: TfpgBorderLayoutConstraint;
begin
  WindowTitle := 'BorderLayout Example';
  SetPosition(100, 100, 400, 300);

  lm := TfpgBorderLayoutManager.Create(10, 5);  // HGap=10, VGap=5
  Self.LayoutManager := lm;

  // North — 顶部工具栏
  btn := TfpgButton.Create(Self);
  btn.Text := 'North';
  constraint := TfpgBorderLayoutConstraint.Create;
  constraint.Region := blrNorth;
  lm.AddLayoutComponent(btn, constraint);

  // South — 底部状态栏
  btn := TfpgButton.Create(Self);
  btn.Text := 'South';
  constraint := TfpgBorderLayoutConstraint.Create;
  constraint.Region := blrSouth;
  lm.AddLayoutComponent(btn, constraint);

  // East — 右侧面板
  btn := TfpgButton.Create(Self);
  btn.Text := 'East';
  constraint := TfpgBorderLayoutConstraint.Create;
  constraint.Region := blrEast;
  lm.AddLayoutComponent(btn, constraint);

  // West — 左侧导航
  btn := TfpgButton.Create(Self);
  btn.Text := 'West';
  constraint := TfpgBorderLayoutConstraint.Create;
  constraint.Region := blrWest;
  lm.AddLayoutComponent(btn, constraint);

  // Center — 主内容区（自动填充）
  pnl := TfpgPanel.Create(Self);
  pnl.BackgroundColor := clLightBlue;
  constraint := TfpgBorderLayoutConstraint.Create;
  constraint.Region := blrCenter;
  lm.AddLayoutComponent(pnl, constraint);
end;
```

> **避坑:**
> - 每个区域只能放一个组件；同区域多次 `AddLayoutComponent` 后者覆盖前者。
> - Center 区域如果没有组件，该空间会留空（不自动分配给其他区域）。
> - North/South 的宽度始终等于容器宽度（减去 HGap），不受 East/West 影响。
> - East/West 的高度等于容器高度减去 North/South 高度及 VGap。
> - `HGap`/`VGap` 是区域之间的间距，不是组件内部 padding。

#### 2.11.4 三种布局管理器对比

| 维度 | MigLayout | FlowLayout | BorderLayout |
|------|-----------|------------|--------------|
| 复杂度 | 高（79 个约束方法） | 低（4 个属性） | 低（5 个区域） |
| 适用场景 | 表单、复杂网格、跨格合并 | 工具栏、按钮组、简单流 | 主窗口（工具栏+状态栏+侧栏+内容） |
| 约束类型 | `TfpgMigCC`（流式 API） | 空 `TfpgLayoutConstraint` | `TfpgBorderLayoutConstraint`（Region 属性） |
| 自动换行 | `LC.WrapAfter(N)` | 超宽自动换行 | 不适用 |
| 跨格/合并 | `SpanX`/`SpanY`/`Split` | 不支持 | 不支持 |
| 增长/收缩 | `GrowX`/`ShrinkX` 等 | 不支持 | Center 自动填充 |
| 绝对定位 | `Pos`/`X`/`Y` | 不支持 | 不支持 |
| 停靠 | `DockNorth` 等 | 不支持 | 本质就是停靠 |
| 调试可视化 | `LC.Debug` + `PaintDebug` | 无 | 无 |
| DPI 感知 | `TfpgMigPlatformDefaults` 联动 | 无特殊处理 | 无特殊处理 |

> **选型建议:** 主窗口框架用 BorderLayout；工具栏/按钮组用 FlowLayout；表单、对话框、复杂网格用 MigLayout。三者可嵌套使用——如 BorderLayout 的 Center 区域放一个 MigLayout 容器。

---

## 模块3：核心基础组件全解

> 本模块包含 fpGUI 全部组件，每个组件按固定内部格式：组件介绍 → 核心用途 → 全部属性 → 全部方法 → 全部事件 → 完整示例代码 → 避坑注意事项。

### 3.1 窗口 — TfpgWindowBase / TfpgWindow / TfpgBaseForm / TfpgForm

#### 3.1.1 窗口类体系 — TfpgWindowBase 与 TfpgForm 的关系

> 源码位置：
> - `corelib/fpg_base.pas`：`TfpgComponent`、`TfpgWidgetBase`、`TfpgWindowBase`
> - `corelib/fpg_widget.pas`：`TfpgWidget`
> - `gui/fpg_window.pas`：`TfpgWindow`
> - `gui/fpg_form.pas`：`TfpgBaseForm`、`TfpgForm`
> - 各后端 `corelib/{gdi,x11,cocoa,ohos}/fpg_gdi.pas` 等：`TfpgGDIWindow` 等原生窗口
> - `corelib/fpg_main.pas`：`TfpgNativeWindow`

fpGUI 的窗口模型由**两条平行的继承分支**组成——"逻辑控件"分支与"原生平台窗口"分支。理解这一点是理解 fpGUI 窗口机制的关键。

##### (1) 完整继承关系图

```
TComponent (FCL)
└── TfpgComponent          (fpg_base.pas)   帮助上下文、TagPointer
    │
    ├──【逻辑分支：界面树中的可视对象】
    │   TfpgWidgetBase     (fpg_base.pas)   位置/尺寸/约束/父控件/Canvas/字体
    │   └── TfpgWidget     (fpg_widget.pas) 事件/绘制/焦点/对齐/拖放
    │       ├── TfpgWindow (gui/fpg_window.pas) 顶层"窗口控件"
    │       │   └── TfpgBaseForm (fpg_form.pas) 窗口属性、模态、生命周期
    │       │       └── TfpgForm     (fpg_form.pas) 标准窗口（published 属性）
    │       │           └── TfpgMessageBox / TfpgBaseDialog / TfpgHintWindow …
    │       ├── TfpgPopupWindow                        弹出窗口（菜单/提示/下拉）
    │       └── TfpgButton / TfpgEdit / TfpgCheckBox … 所有普通控件
    │
    └──【原生分支：对操作系统窗口句柄的封装】
        TfpgWindowBase     (fpg_base.pas)   抽象平台窗口（句柄/消息派发/标题/状态）
        └── TfpgGDIWindow  (corelib/gdi)    Windows 平台（封装 HWND）
            TfpgX11Window  (corelib/x11)    Linux/X11 平台（封装 Window XID）
            TfpgCocoaWindow(corelib/cocoa)  macOS 平台（封装 NSWindow）
            TfpgOhosWindow (corelib/ohos)   OpenHarmony 平台
            └── TfpgWindowImpl = class(TfpgGDIWindow)  (fpg_interface.pas 跨平台别名)
                └── TfpgNativeWindow (fpg_main.pas)    暴露 WinHandle
```

> **要点**：`TfpgWindowBase` **不是** `TfpgForm` 的祖先。二者是平级关系（共同祖先为 `TfpgComponent`），通过**组合（Owner/Window 引用）**协作，而不是继承。

##### (2) 组合关系：一个窗体"拥有"一个原生窗口

- `TfpgWidgetBase` 内部持有字段 `FWindow: TfpgWindowBase`，并通过 `Window` 属性暴露（[fpg_base.pas](file:///d:/fpcupdeluxe34_new/fpGUI-2.1.0/framework/src/main/pascal/corelib/fpg_base.pas)）。
- 只有顶层窗口控件 `HasOwnWindow = True`：`TfpgWindow.Create` 中设置该标志（[fpg_window.pas](file:///d:/fpcupdeluxe34_new/fpGUI-2.1.0/framework/src/main/pascal/gui/fpg_window.pas) 构造函数），随后 `TfpgWidget.DoAllocateWindowHandle` 创建 `FWindow := TfpgNativeWindow.Create(Self)`——即以窗体自身为 Owner 创建原生窗口对象。
- 反方向上，`TfpgWindowBase.PrimaryWidget` 就是其 `Owner`（即顶层窗体控件），原生窗口通过它把事件送回控件树。
- 按钮、编辑框等子控件 `HasOwnWindow = False`，**没有操作系统窗口句柄**（轻量控件）。它们的 `Window` 属性沿父链向上查找，最终返回所属窗体的原生窗口：

```pascal
// TfpgWidgetBase.GetWindow（fpg_base.pas）
if HasOwnWindow then
  Result := FWindow           // 顶层窗口：返回自己创建的原生窗口
else if Assigned(FParent) then
  Result := FParent.Window;   // 子控件：沿父链向上借用窗体的原生窗口
```

```
┌───────────────────────────────────────────────┐
│ TfpgForm（逻辑层）                             │
│   Parent=nil, HasOwnWindow=True               │
│   ┌────────────┐  ┌────────────┐              │
│   │ TfpgButton │  │  TfpgEdit  │ ... 子控件    │
│   │ 无句柄      │  │  无句柄     │  HasOwnWindow│
│   └────────────┘  └────────────┘      =False   │
│         │ FWindow 引用                          │
│         ▼                                      │
│ TfpgNativeWindow（原生层，Owner = 该 Form）     │
│   = TfpgWindowImpl → TfpgGDIWindow             │
│   封装 HWND / XID / NSWindow                   │
└───────────────────────────────────────────────┘
```

这一设计的直接效果：**一个顶层窗体 = 一个操作系统窗口**；窗体上几十上百个子控件全部在该窗口的画布上由 fpGUI 自绘，创建/销毁成本极低，绘制风格统一（由 `fpgStyle` 驱动）。

##### (3) TfpgWindowBase 的职责

`TfpgWindowBase` 是与平台无关的抽象基类，所有后端相关操作声明为 `virtual; abstract;` 的 `Do*` 方法，由 `TfpgGDIWindow` 等子类实现。

| 分类 | 成员 | 说明 |
|------|------|------|
| 句柄生命周期 | `AllocateWindowHandle` / `ReleaseWindowHandle` / `HasHandle` | 创建/释放原生句柄 |
| 后端抽象方法 | `DoAllocateWindowHandle`、`DoReleaseWindowHandle`、`DoMoveWindow`、`DoSetWindowVisible`、`DoSetWindowTitle`、`DoSetWindowAttributes`、`DoSetMouseCursor`、`DoWindowToScreen`、`DoDNDEnabled` 等 | 各后端必须实现 |
| 窗口属性 | `WindowType`（`wtChild/wtWindow/wtModalForm/wtPopup`） | 窗口类型 |
|  | `WindowAttributes`（`waSizeable/waBorderless/waStayOnTop…`） | 窗口属性集 |
|  | `WindowTitle`、`WindowState`（`wsNormal/wsMinimized/wsMaximized`）、`WindowOpacity`、`WindowPosition`（间接） | 标题/状态/透明度 |
|  | `Left/Top/Width/Height`（只读） | 原生窗口实际几何位置 |
| 控件关联 | `PrimaryWidget` | = Owner，即所属顶层窗体控件 |
|  | `CurrentWidget` | 当前鼠标所在的子控件（用于 hover/光标切换） |
|  | `MouseCapture` / `PassiveMouseCapture` | 鼠标捕获目标（拖拽时持续接收事件） |
| 事件派发 | `DispatchMouseEvent`、`DispatchKeyEvent` | 将原生消息翻译后派发到控件 |
|  | `FindWidgetForMouseEvent`、`FindWidgetForKeyEvent`、`FindWidgetFromWindowPoint` | 命中测试 / 焦点控件查找 |
| 顶层操作 | `ActivateWindow`、`BringToFront`、`SetFullscreen`、`SetWindowVisible`、`MoveWindow`、`CaptureMouse/ReleaseMouse` | 激活/置顶/全屏/移动 |
| 拖放 | `AddDropableWidget` / `RemoveDropableWidget` | 注册可接收拖放的控件 |
| 坐标转换 | `WindowToScreen` / `DoWindowToScreen` | 窗口坐标 ↔ 屏幕坐标 |

##### (4) 消息/事件的实际流转路径

```
操作系统事件（Win32 WndProc / X11 event / Cocoa…）
        │
        ▼
TfpgGDIWindow 等后端窗口（TfpgWindowBase 子类）
   翻译为 fpGUI 消息记录 TfpgMessageRec
        │
        ▼
TfpgWindowBase.DispatchMouseEvent / DispatchKeyEvent
   通过 PrimaryWidget 进入控件树，递归命中测试
   FindWidgetForMouseEvent(PrimaryWidget, X, Y)
        │
        ▼
目标 TfpgWidget（按钮/编辑框…）
   MsgMouseDown / MsgKeyPress …（fpg_widget.pas 消息方法）
        │
        ▼
HandleLMouseDown / HandleKeyPress …（虚方法，可重写）
        │
        ▼
OnMouseDown / OnKeyPress …（用户事件回调）
```

##### (5) 各后端对应类

| 平台 | 后端窗口类 | 单元 | 句柄类型 |
|------|-----------|------|----------|
| Windows (GDI) | `TfpgGDIWindow` | `corelib/gdi/fpg_gdi.pas` | `HWND`（`WinHandle`） |
| Linux/X11 | `TfpgX11Window` | `corelib/x11/` | X11 `Window`（XID） |
| macOS | `TfpgCocoaWindow` | `corelib/cocoa/` | `NSWindow` |
| OpenHarmony | `TfpgOhosWindow` | `corelib/ohos/` | 平台原生窗口 |

`fpg_interface.pas` 用 `TfpgWindowImpl = class(TfpgGDIWindow)` 这类"再声明别名"把当前编译目标的后端类统一命名为 `TfpgWindowImpl`；`fpg_main.pas` 中的 `TfpgNativeWindow = class(TfpgWindowImpl)` 再做一层薄封装并公开 `WinHandle`。跨平台代码只引用 `TfpgNativeWindow`，无需关心实际后端。

##### (6) 避坑注意事项

> **避坑:**
> 1. **不要把 `TfpgWindowBase` 当窗体基类继承**。应用代码继承的是逻辑层的 `TfpgForm`（或 `TfpgPopupWindow`）。`TfpgWindowBase` 属于平台后端层，自定义窗口/对话框不应直接派生它。
> 2. **窗体创建前 `Window` 可能为 nil**。原生窗口在首次显示前才分配句柄（`AllocateWindowHandle`）。需要访问句柄或调用原生操作前，先判断 `WindowAllocated`。
> 3. **子控件无句柄**。对 `TfpgButton` 等调用 Win32 API 式操作是无效的；跨平台需求应通过 `TfpgWidget`/`TfpgWindow` 的公开 API 完成。
> 4. **设置标题要用逻辑层 API**：`TfpgForm.WindowTitle := 'x'`（`TfpgWindow` 内部转发给 `Window.WindowTitle`），不要绕过窗体直接操作 `PrimaryWidget`。
> 5. **一个 Form 与它的 NativeWindow 生命周期绑定**：窗体释放时其 Owner 的原生窗口随之释放；手动 `Free` 原生窗口会导致绘制/事件失效。

#### 3.1.2 TfpgForm — 窗口/表单

> 源码位置：`gui/fpg_form.pas`
> 继承链：`TfpgForm` → `TfpgBaseForm` → `TfpgWindow` → `TfpgWidget` → `TfpgWidgetBase` → `TfpgComponent`
> 组合关系：`TfpgForm`（`HasOwnWindow=True`）在首次显示时创建并拥有一个 `TfpgNativeWindow`（`TfpgWindowBase` 的后端子类），详见 3.1.1。

**组件介绍**：`TfpgForm` 是 fpGUI 中最常用的顶层窗口组件，作为应用程序主窗口或对话框使用。它提供窗口标题、位置策略、模态显示、缩放控制等功能。

**核心用途**：创建应用程序主窗口、创建模态/非模态对话框、作为承载其他控件的容器。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `BackgroundColor` | `TfpgColor` | RW | `clWindowBackground` | 背景色 |
| `FullScreen` | `boolean` | RW | `False` | 全屏模式 |
| `Height` | `TfpgCoord` | RW | — | 窗口高度 |
| `Hint` | `TfpgString` | RW | — | 提示文本 |
| `IconName` | `string` | RW | — | 图标名称 |
| `Left` | `TfpgCoord` | RW | — | X 坐标 |
| `MaxHeight` | `TfpgCoord` | RW | — | 最大高度 |
| `MaxWidth` | `TfpgCoord` | RW | — | 最大宽度 |
| `MinHeight` | `TfpgCoord` | RW | — | 最小高度 |
| `MinWidth` | `TfpgCoord` | RW | — | 最小宽度 |
| `ModalResult` | `TfpgModalResult` | RW | `mrNone` | 模态结果 |
| `Sizeable` | `boolean` | RW | — | 是否可缩放 |
| `TextColor` | `TfpgColor` | RW | `clText1` | 文本色 |
| `Top` | `TfpgCoord` | RW | — | Y 坐标 |
| `Width` | `TfpgCoord` | RW | — | 窗口宽度 |
| `WindowPosition` | `TWindowPosition` | RW | `wpAuto` | 窗口位置策略 |
| `WindowState` | `TfpgWindowState` | RW | `wsNormal` | 窗口状态 |
| `WindowTitle` | `string` | RW | — | 窗口标题 |
| `WindowOpacity` | `Single` | RW | `1.0` | 窗口透明度（0.0-1.0） |
| `WindowAttributes` | `TWindowAttributes` | RW | `[]` | 窗口属性集 |

`TWindowPosition` 枚举：

| 值 | 说明 |
|------|------|
| `wpUser` | 用户指定位置 |
| `wpAuto` | 自动定位 |
| `wpScreenCenter` | 屏幕居中 |
| `wpOneThirdDown` | 屏幕上方 1/3 处 |
| `wpVirtualScreenCenter` | 虚拟屏幕居中 |
| `wpMainFormCenter` | 主窗体居中 |

##### 方法

| 原型 | 功能 | 入参 | 返回值 | 说明 |
|------|------|------|--------|------|
| `procedure Show;` | 非模态显示 | — | — | 不阻塞调用者 |
| `procedure Hide;` | 隐藏窗口 | — | — | — |
| `function ShowModal: TfpgModalResult;` | 模态显示 | — | 模态结果 | 阻塞直到窗口关闭 |
| `procedure Close;` | 关闭窗口 | — | — | 触发 OnCloseQuery/OnClose |
| `function CloseQuery: boolean; virtual;` | 关闭查询 | — | 是否允许关闭 | 可重写以拦截关闭 |
| `procedure AfterCreate; virtual;` | 构造后初始化 | — | — | 重写以初始化子控件 |
| `procedure ScaleDPI(AFromDPI: integer = 0);` | DPI 缩放 | 源 DPI | — | 缩放所有子控件 |
| `procedure InvokeHelp; override;` | 调用帮助 | — | — | 触发 OnHelp |

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnActivate` | `TNotifyEvent` | 窗口激活 |
| `OnDeactivate` | `TNotifyEvent` | 窗口取消激活 |
| `OnClose` | `TFormCloseEvent` | 窗口关闭（可控制关闭行为） |
| `OnCloseQuery` | `TFormCloseQueryEvent` | 关闭查询（可阻止关闭） |
| `OnCreate` | `TNotifyEvent` | 窗口创建 |
| `OnDestroy` | `TNotifyEvent` | 窗口销毁 |
| `OnShow` | `TNotifyEvent` | 窗口显示 |
| `OnHide` | `TNotifyEvent` | 窗口隐藏 |
| `OnHelp` | `TfpgHelpEvent` | 帮助请求 |
| `OnPaint` | `TPaintEvent` | 绘制 |
| `OnResize` | `TNotifyEvent` | 尺寸改变 |
| `OnKeyPress` | `TKeyPressEvent` | 键盘按键 |
| `OnKeyChar` | `TfpgKeyCharEvent` | 字符输入 |
| `OnMouseDown/Up/Move` | 鼠标事件 | 鼠标交互 |
| `OnDoubleClick` | `TMouseButtonEvent` | 双击 |
| `OnShowHint` | `THintEvent` | 显示提示 |

##### 示例

主窗口：

```pascal
type
  TMainForm = class(TfpgForm)
  public
    procedure AfterCreate; override;
  end;

procedure TMainForm.AfterCreate;
begin
  inherited AfterCreate;
  Width := 400;
  Height := 300;
  WindowTitle := '我的应用';
  WindowPosition := wpScreenCenter;
end;
```

模态对话框 + 关闭查询：

```pascal
function ShowMyDialog: TfpgModalResult;
var
  frm: TMyDialogForm;
begin
  frm := TMyDialogForm.Create(nil);
  try
    Result := frm.ShowModal;  // 阻塞直到窗口关闭
  finally
    frm.Free;
  end;
end;

procedure TEditForm.FormCloseQuery(Sender: TObject; var CanClose: boolean);
begin
  if FModified then
    CanClose := (fpgMessageDlg('确认', '有未保存的修改，是否关闭？',
                  mtConfirmation, [mbYes, mbNo]) = mrYes)
  else
    CanClose := True;
end;

procedure TEditForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caFree;  // 关闭即释放
end;
```

##### 避坑注意事项

> **避坑:**
> 1. **AfterCreate vs OnCreate**：`AfterCreate` 是虚方法，适合在子类中重写以初始化控件；`OnCreate` 是事件属性，适合在设计期绑定。两者不要混用。
> 2. **ShowModal 内存管理**：`ShowModal` 返回后窗口仍存在，必须手动 `Free`。推荐使用 `try...finally`。
> 3. **CloseAction**：`OnClose` 事件中 `caHide` 仅隐藏窗口（不释放），`caFree` 释放窗口。模态窗口通常使用 `caFree`。
> 4. **WindowTitle vs Text**：窗口标题使用 `WindowTitle` 属性，不是 `Text`。

Show/ShowModal显示窗口时才创建**OHOS原生Window窗口，返回到 FWinHandle **。
Hide会**释放**原生 Window 窗口。要隐藏窗口使用 Visible。

#### 3.1.2 TfpgMainForm / TfpgBaseForm

- `TfpgBaseForm`：所有窗口的基类，定义 `WindowTitle`/`WindowPosition`/`ModalResult`/`Sizeable`/`FullScreen` 等 protected 属性。
- `TfpgForm`：标准窗口，将基类 protected 属性发布为 published。
- `TfpgMainForm`：当应用需要明确区分主窗口与普通窗口时可使用，行为与 `TfpgForm` 基本一致，主要用于设计器/应用框架识别主窗体角色。

> **避坑:** 自定义窗口优先继承 `TfpgForm`；只有需要区分主窗口语义时才使用 `TfpgMainForm`。

窗口类型继承树是两条独立分支：

TfpgComponent
├── TfpgWindowBase → TfpgOhosWindow → TfpgWindowImpl → TfpgNativeWindow
│   （有 SetFullscreen、FWinHandle）
│
└── TfpgWidgetBase → TfpgWidget → TfpgWindow → TfpgBaseForm → TfpgForm → TMainForm
    （有 Window 属性，返回 TfpgNativeWindow）
TMainForm 不继承 TfpgWindowBase，也不继承 TfpgOhosWindow。它们是兄弟分支！

TfpgWidget.Window 属性返回 TfpgNativeWindow（即 TfpgOhosWindow），这才是实际的窗口对象。

#### 3.1.3 TfpgBaseForm 与"主窗体"角色

- `TfpgBaseForm`（`gui/fpg_form.pas`，继承自 `TfpgWindow`）：所有窗体的基类，定义 `WindowTitle`/`WindowPosition`/`ModalResult`/`Sizeable`/`FullScreen` 等 protected 属性，以及模态栈（`ShowModal`）、关闭流程（`CloseQuery`/`OnCloseQuery`/`OnClose`）、DPI 缩放（`ScaleDPI`）等窗口生命周期逻辑。
- `TfpgForm`：标准窗口，将基类 protected 属性发布为 published，是应用开发实际使用的类。
- **关于"主窗体"**：当前 fpGUI 源码中**不存在 `TfpgMainForm` 类**。"主窗体"是运行期角色而非类型——由应用对象的 `fpgApplication.MainForm: TfpgWidgetBase` 属性标识。通常第一个创建/显示的 `TfpgForm` 即成为主窗体；也可显式赋值 `fpgApplication.MainForm := frm`。主窗体关闭后应用消息循环退出。

> **避坑:**
> 1. 自定义窗口/对话框一律继承 `TfpgForm`。
> 2. 需要"主窗口关闭即退出应用"的语义时，确保主窗体被赋给 `fpgApplication.MainForm`，而不是新建特殊窗体类型。

### 3.2 文本

#### 3.2.1 TfpgLabel

> 源码位置：`gui/fpg_label.pas`
> 继承链：`TfpgLabel` → `TfpgCustomLabel` → `TfpgWidget`

**组件介绍**：用于显示静态文本（不可编辑），支持自动尺寸、文本换行、对齐方式等。

**核心用途**：表单字段说明、状态文本、不可编辑的展示文本。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Alignment` | `TAlignment` | RW | `taLeftJustify` | 水平对齐 |
| `AutoSize` | `boolean` | RW | `False` | 自动尺寸 |
| `Layout` | `TLayout` | RW | `tlTop` | 垂直布局 |
| `Text` | `TfpgString` | RW | — | 标签文本 |
| `LineSpace` | `integer` | RW | 2 | 行间距 |
| `WrapText` | `boolean` | RW | `False` | 是否自动换行 |
| `BackgroundColor` | `TfpgColor` | RW | `clWindowBackground` | 背景色 |
| `FontDesc` | `string` | RW | — | 字体描述 |
| `TextColor` | `TfpgColor` | RW | `clText1` | 文本色 |

##### 方法

便捷工厂函数：

```pascal
function CreateLabel(AOwner: TComponent; x, y: TfpgCoord; AText: string;
  w: TfpgCoord = 0; h: TfpgCoord = 0;
  HAlign: TAlignment = taLeftJustify; VAlign: TLayout = tlTop;
  ALineSpace: integer = 2): TfpgLabel;
```

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnClick` | `TNotifyEvent` | 单击 |
| `OnDoubleClick` | `TMouseButtonEvent` | 双击 |
| `OnMultiClick` | `TMouseButtonMultiClickEvent` | 多次点击 |
| `OnMouseDown/Up/Move` | 鼠标事件 | 鼠标交互 |
| `OnMouseEnter/Exit` | `TNotifyEvent` | 鼠标进入/离开 |
| `OnShowHint` | `THintEvent` | 显示提示 |

##### 示例

```pascal
// 方式一：使用 CreateLabel 便捷函数
var lbl: TfpgLabel;
begin
  lbl := CreateLabel(Self, 10, 10, '用户名：');
end;

// 方式二：直接创建并启用换行
var lbl: TfpgLabel;
begin
  lbl := TfpgLabel.Create(Self);
  lbl.Left := 10;
  lbl.Top := 10;
  lbl.Width := 200;
  lbl.WrapText := True;
  lbl.Text := '这是一段很长的文本，宽度不够时自动换行。';
end;
```

##### 避坑注意事项

> **避坑:**
> 1. **AutoSize 与 Width 冲突**：`AutoSize = True` 时手动设置的 `Width` 会被文本宽度覆盖。
> 2. **WrapText 需要 Width**：`WrapText = True` 时必须设置 `Width`，否则换行不生效。

#### 3.2.2 TfpgEdit

> 源码位置：`gui/fpg_edit.pas`
> 继承链：`TfpgEdit` → `TfpgBaseTextEdit` → `TfpgBaseEdit` → `TfpgWidget`

**组件介绍**：单行文本输入控件，支持密码模式、最大长度、自动选择、只读等。派生出 `TfpgEditInteger` 和 `TfpgEditFloat`。

**核心用途**：表单输入（用户名、密码、搜索框等）。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Align` | `TAlign` | RW | `alNone` | 对齐 |
| `AutoSelect` | `Boolean` | RW | `True` | 获得焦点时自动全选 |
| `AutoSize` | `Boolean` | RW | `False` | 自动尺寸 |
| `BackgroundColor` | `TfpgColor` | RW | `clBoxColor` | 背景色 |
| `BorderStyle` | `TfpgEditBorderStyle` | RW | `ebsDefault` | 边框样式 |
| `ExtraHint` | `string` | RW | — | 额外提示（占位符） |
| `FontDesc` | `string` | RW | — | 字体描述 |
| `HeightMargin` | `integer` | RW | 2 | 垂直边距 |
| `HideSelection` | `Boolean` | RW | `True` | 失去焦点时隐藏选区 |
| `Hint` | `TfpgString` | RW | — | 提示 |
| `IgnoreMouseCursor` | `Boolean` | RW | `False` | 忽略鼠标光标定位 |
| `MaxLength` | `Integer` | RW | 0 | 最大字符数（0=无限） |
| `Options` | `TfpgTextEditOptions` | RW | `[]` | 选项集 |
| `ParentShowHint` | `boolean` | RW | `True` | 继承父控件 ShowHint |
| `PasswordMode` | `Boolean` | RW | `False` | 密码模式 |
| `ReadOnly` | `Boolean` | RW | `False` | 只读 |
| `SideMargin` | `integer` | RW | 3 | 水平边距 |
| `TabOrder` | `integer` | RW | — | Tab 顺序 |
| `Text` | `String` | RW | — | 文本内容 |
| `TextColor` | `TfpgColor` | RW | `clText1` | 文本色 |

`TfpgTextEditOption` 选项：`eo_ExtraHintIfFocus`（获得焦点时显示 ExtraHint）。

##### 方法

| 原型 | 功能 | 入参 | 返回值 | 说明 |
|------|------|------|--------|------|
| `procedure SelectAll;` | 全选文本 | — | — | — |
| `procedure Clear;` | 清空文本 | — | — | — |
| `procedure ClearSelection;` | 清除选中文本 | — | — | — |
| `procedure CopyToClipboard;` | 复制到剪贴板 | — | — | — |
| `procedure CutToClipboard;` | 剪切到剪贴板 | — | — | — |
| `procedure PasteFromClipboard;` | 从剪贴板粘贴 | — | — | — |
| `procedure InsertAtCursorPos(AText: string);` | 在光标处插入文本 | 待插入文本 | — | — |
| `function SelectionText: string;` | 获取选中文本 | — | 选中字符串 | — |
| `function GetClientRect: TfpgRect;` | 获取客户区矩形 | — | 矩形 | — |

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TNotifyEvent` | 文本改变 |
| `OnDragStartDetected` | `TNotifyEvent` | 拖放开始 |
| `OnEnter/OnExit` | `TNotifyEvent` | 焦点进出 |
| `OnKeyChar/OnKeyPress` | 键盘事件 | 键盘输入 |
| `OnMouseDown/Up/Move` | 鼠标事件 | 鼠标交互 |
| `OnMouseEnter/Exit` | `TNotifyEvent` | 鼠标进入/离开 |
| `OnPaint` | `TPaintEvent` | 绘制 |
| `OnShowHint` | `THintEvent` | 显示提示 |

##### 示例

```pascal
var ed: TfpgEdit;
begin
  ed := TfpgEdit.Create(Self);
  ed.Left := 10;
  ed.Top := 30;
  ed.Width := 200;
  ed.Text := '默认文本';
  ed.OnChange := @edTextChanged;
end;

// 密码输入框
ed := TfpgEdit.Create(Self);
ed.PasswordMode := True;
ed.MaxLength := 16;

// 占位符文本
ed := TfpgEdit.Create(Self);
ed.ExtraHint := '请输入用户名...';
ed.Options := [eo_ExtraHintIfFocus];
```

##### 避坑注意事项

> **避坑:** `ExtraHint` 占位符仅在 `Text` 为空时显示；`eo_ExtraHintIfFocus` 选项控制获得焦点时是否也显示。

#### 3.2.3 TfpgEditInteger — 整数编辑器

> 继承链：`TfpgEditInteger` → `TfpgBaseNumericEdit` → `TfpgBaseEdit`

**组件介绍**：仅允许输入整数的编辑器，自动校验范围、显示千位分隔符。

##### 属性（新增）

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `MaxValue` | `integer` | RW | 100 | 最大值 |
| `MinValue` | `integer` | RW | 0 | 最小值 |
| `Value` | `integer` | RW | 0 | 当前整数值 |
| `ShowThousand` | `boolean` | RW | `True` | 显示千位分隔符 |
| `CustomThousandSeparator` | `TfpgChar` | RW | — | 自定义千位分隔符 |
| `NegativeColor` | `TfpgColor` | RW | `clRed` | 负数颜色 |
| `Alignment` | `TAlignment` | RW | `taRightJustify` | 对齐方式 |

##### 示例

```pascal
var ed: TfpgEditInteger;
begin
  ed := TfpgEditInteger.Create(Self);
  ed.MinValue := 0;
  ed.MaxValue := 100;
  ed.Value := 50;
  ed.ShowThousand := True;
end;
```

#### 3.2.4 TfpgEditFloat — 浮点数编辑器

继承自 `TfpgBaseNumericEdit`，属性与 `TfpgEditInteger` 类似，但 `Value` 为 `extended` 类型，并增加 `Decimals: integer`（小数位数）属性。

#### 3.2.5 TfpgMemo

> 源码位置：`gui/fpg_memo.pas`
> 继承链：`TfpgMemo` → `TfpgWidget`

**组件介绍**：多行文本编辑控件，支持滚动条、行操作、拖放、右键菜单等。

**核心用途**：代码/日志/长文本编辑器、备注输入。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Align` | `TAlign` | RW | `alNone` | 对齐 |
| `BackgroundColor` | `TfpgColor` | RW | `clBoxColor` | 背景色 |
| `BorderStyle` | `TfpgEditBorderStyle` | RW | `ebsDefault` | 边框样式 |
| `FontDesc` | `string` | RW | — | 字体描述 |
| `Hint` | `TfpgString` | RW | — | 提示 |
| `Lines` | `TStringList` | RW | — | 行集合（直接操作行） |
| `ReadOnly` | `Boolean` | RW | `False` | 只读 |
| `TabOrder` | `integer` | RW | — | Tab 顺序 |
| `TextColor` | `TfpgColor` | RW | `clText1` | 文本色 |
| `Text` | `TfpgString` | RW | — | 全部文本 |
| `CursorPos` | `integer` | RW | — | 光标位置（行内字符索引） |
| `CursorLine` | `integer` | RW | — | 光标行号 |
| `MaxLength` | `integer` | RW | — | 最大字符数 |
| `TabWidth` | `integer` | RW | — | Tab 宽度 |
| `UseTabs` | `boolean` | RW | `False` | 是否使用 Tab 字符 |
| `PopupMenu` | `TfpgPopupMenu` | RW | — | 右键菜单 |
| `SelectionText` | `TfpgString` | R | — | 选中文本 |

##### 方法

| 原型 | 功能 | 说明 |
|------|------|------|
| `procedure CopyToClipboard;` | 复制到剪贴板 | — |
| `procedure CutToClipboard;` | 剪切到剪贴板 | — |
| `procedure PasteFromClipboard;` | 从剪贴板粘贴 | — |
| `procedure Clear;` | 清空所有文本 | — |
| `procedure BeginUpdate;` | 开始批量更新（暂停重绘） | — |
| `procedure EndUpdate;` | 结束批量更新（恢复重绘） | — |
| `procedure UpdateScrollBars;` | 更新滚动条 | — |

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TNotifyEvent` | 文本改变 |
| `OnDragStartDetected` | `TNotifyEvent` | 拖放开始 |
| `OnEnter/OnExit` | `TNotifyEvent` | 焦点进出 |
| `OnKeyChar/OnKeyPress` | 键盘事件 | 键盘输入 |
| `OnMouseDown/Up/Move` | 鼠标事件 | 鼠标交互 |
| `OnMouseEnter/Exit` | `TNotifyEvent` | 鼠标进入/离开 |
| `OnPaint` | `TPaintEvent` | 绘制 |
| `OnShowHint` | `THintEvent` | 显示提示 |

##### 示例

```pascal
var mem: TfpgMemo; i: integer;
begin
  mem := TfpgMemo.Create(Self);
  mem.Left := 10; mem.Top := 50;
  mem.Width := 300; mem.Height := 200;
  mem.Lines.Add('第一行');
  mem.Lines.Add('第二行');
  mem.FontDesc := 'Courier New-10';

  // 批量更新
  mem.BeginUpdate;
  try
    for i := 1 to 1000 do
      mem.Lines.Add('行 ' + IntToStr(i));
  finally
    mem.EndUpdate;
  end;
end;
```

##### 避坑注意事项

> **避坑:**
> 1. **Lines vs Text**：`Lines` 是 `TStringList` 按行操作；`Text` 是整体文本。修改 `Lines` 后 `Text` 自动同步。
> 2. **BeginUpdate/EndUpdate 必须配对**，否则控件不会刷新。

#### 3.2.6 TfpgSpinEdit

> 源码位置：`gui/fpg_spinedit.pas`
> 继承链：`TfpgSpinEditFloat` / `TfpgSpinEditInteger` → `TfpgAbstractSpinEdit` → `TfpgBevel`

**组件介绍**：带上下微调按钮的数值编辑器，分整数版与浮点版。

##### 属性（TfpgSpinEditFloat）

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Value` | `extended` | RW | 0 | 当前值 |
| `MaxValue` | `extended` | RW | — | 最大值 |
| `MinValue` | `extended` | RW | — | 最小值 |
| `Increment` | `extended` | RW | — | 步进值 |
| `LargeIncrement` | `extended` | RW | — | 大步进值 |
| `Decimals` | `integer` | RW | — | 小数位数 |
| `TextColor` | `TfpgColor` | RW | `clText1` | 文本色 |
| `NegativeColor` | `TfpgColor` | RW | `clRed` | 负数色 |
| `FontDesc` | `string` | RW | — | 字体描述 |

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TNotifyEvent` | 值改变 |

##### 示例

```pascal
var se: TfpgSpinEditFloat;
begin
  se := TfpgSpinEditFloat.Create(Self);
  se.MinValue := 0;
  se.MaxValue := 100;
  se.Value := 50;
  se.Increment := 0.5;
  se.Decimals := 1;
end;
```

#### 3.2.7 TfpgEditButton

> 源码位置：`gui/fpg_editbtn.pas`
> 继承链：`TfpgBaseEditButton` → `TfpgAbstractPanel`

**组件介绍**：带按钮的编辑控件基类，派生出 `TfpgFileNameEdit`、`TfpgDirectoryEdit` 等。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Text` / `ExtraHint` | `TfpgString` | RW | — | 文本/占位符 |
| `ReadOnly` | `Boolean` | RW | `False` | 只读 |
| `OnButtonClick` | `TNotifyEvent` | RW | — | 按钮点击事件 |

#### 3.2.8 TfpgEditCombo

> 源码位置：`gui/fpg_editcombo.pas`

**组件介绍**：可编辑的下拉组合框（输入框+下拉按钮），相比 `TfpgComboBox` 允许用户输入任意文本。

##### 属性：与 `TfpgComboBox` 类似，但允许自由输入。
##### 事件：`OnChange`、`OnDropDown`、`OnCloseUp` 等。

#### 3.2.9 TfpgHyperlink

> 源码位置：`gui/fpg_hyperlink.pas`
> 继承链：`TfpgHyperlink` → `TfpgCustomLabel` → `TfpgWidget`

**组件介绍**：超链接标签，点击后调用系统浏览器打开 URL。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `URL` | `TfpgString` | RW | — | 超链接 URL |
| `HotTrackColor` | `TfpgColor` | RW | `clHyperLink` | 热点颜色 |
| `HotTrackFont` | `TfpgString` | RW | — | 热点字体描述 |
| `Text` | `TfpgString` | RW | — | 显示文本 |
| `TextColor` | `TfpgColor` | RW | `clHyperLink` | 文本色 |

##### 方法

| 原型 | 功能 |
|------|------|
| `procedure GoHyperLink;` | 打开 URL（调用系统浏览器） |

##### 示例

```pascal
var link: TfpgHyperlink;
begin
  link := TfpgHyperlink.Create(Self);
  link.Text := '访问 fpGUI 官网';
  link.URL := 'https://fpgui.sourceforge.net';
end;
```

### 3.3 按钮

#### 3.3.1 TfpgButton

> 源码位置：`gui/fpg_button.pas`
> 继承链：`TfpgButton` → `TfpgBaseButton` → `TfpgWidget`

**组件介绍**：标准下压按钮，支持文本、图像、切换状态、模态结果等。可实现工具栏按钮、切换按钮等变体。

**核心用途**：确认/取消操作、命令触发、工具栏按钮、互斥切换按钮组。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Align` | `TAlign` | RW | `alNone` | 对齐方式 |
| `AllowAllUp` | `boolean` | RW | `False` | 切换组中是否允许全部弹起 |
| `AllowDown` | `Boolean` | RW | `False` | 是否为切换按钮（等价于 GroupIndex > 0） |
| `AllowMultiLineText` | `boolean` | RW | `False` | 是否允许多行文本 |
| `BackgroundColor` | `TfpgColor` | RW | `clButtonFace` | 背景色 |
| `Default` | `boolean` | RW | `False` | 是否为默认按钮（Enter 触发） |
| `Down` | `Boolean` | RW | `False` | 切换状态（按下/弹起） |
| `Embedded` | `Boolean` | RW | `False` | 嵌入模式（不显示焦点框） |
| `Enabled` | `boolean` | RW | `True` | 是否启用 |
| `Flat` | `Boolean` | RW | `False` | 扁平外观 |
| `FontDesc` | `string` | RW | — | 字体描述 |
| `GroupIndex` | `integer` | RW | 0 | 切换组索引（>0 启用切换行为） |
| `ImageLayout` | `TImageLayout` | RW | `ilImageLeft` | 图像布局位置 |
| `ImageMargin` | `integer` | RW | 3 | 图像边距 |
| `ImageName` | `string` | RW | — | 图像名称 |
| `ImageSize` | `integer` | RW | 16 | 图标尺寸（96 DPI 基准） |
| `ImageSpacing` | `integer` | RW | -1 | 图像与文本间距 |
| `ModalResult` | `TfpgModalResult` | RW | `mrNone` | 模态结果 |
| `ShowImage` | `Boolean` | RW | `True` | 是否显示图像 |
| `Text` | `string` | RW | — | 按钮文本 |
| `TextColor` | `TfpgColor` | RW | `clText1` | 文本色 |

`TImageLayout` 枚举：`ilImageLeft`/`ilImageTop`/`ilImageRight`/`ilImageBottom`。

##### 方法

| 原型 | 功能 |
|------|------|
| `procedure Click;` | 触发 OnClick 事件 |
| `function GetCommand: ICommand;` | 获取关联命令 |
| `procedure SetCommand(ACommand: ICommand);` | 设置命令对象（命令模式） |

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnClick` | `TNotifyEvent` | 单击 |
| `OnDragStartDetected` | `TNotifyEvent` | 拖放开始 |
| `OnEnter/OnExit` | `TNotifyEvent` | 焦点进出 |
| `OnKeyPress` | `TKeyPressEvent` | 键盘按键 |
| `OnMouseDown/Up/Move` | 鼠标事件 | 鼠标交互 |
| `OnMouseEnter/Exit` | `TNotifyEvent` | 鼠标进入/离开 |
| `OnShowHint` | `THintEvent` | 显示提示 |

##### 示例

```pascal
// 普通按钮
var btn: TfpgButton;
begin
  btn := TfpgButton.Create(Self);
  btn.Left := 10; btn.Top := 10;
  btn.Width := 80; btn.Height := 30;
  btn.Text := '确定';
  btn.OnClick := @btnOKClick;
end;

// 互斥切换按钮组
var btn1, btn2, btn3: TfpgButton;
begin
  btn1 := TfpgButton.Create(Self);
  btn1.Text := '左对齐';
  btn1.AllowDown := True;
  btn1.Down := True;

  btn2 := TfpgButton.Create(Self);
  btn2.Text := '居中';
  btn2.AllowDown := True;
  btn2.GroupIndex := 1;  // 与 btn1 同组

  btn3 := TfpgButton.Create(Self);
  btn3.Text := '右对齐';
  btn3.AllowDown := True;
  btn3.GroupIndex := 1;
end;

// 模态结果按钮
btnOK.ModalResult := mrOK;
btnCancel.ModalResult := mrCancel;
```

##### 避坑注意事项

> **避坑:**
> 1. **GroupIndex 唯一性**：不同切换组的按钮需使用不同的 `GroupIndex` 值。
> 2. **AllowDown 自动设置**：`AllowDown := True` 会自动将 `GroupIndex` 设为 1。如需多组切换按钮，需手动指定不同 `GroupIndex`。
> 3. **ImageName 解析**：`ImageName` 优先从 `fpgIcons` 查找（支持 HVIF 矢量图标），其次从 `fpgImages` 查找。
> 4. **ImageSize 含义**：`ImageSize` 是 96 DPI 基准的逻辑像素，实际渲染会根据屏幕 DPI 缩放。

#### 3.3.2 TfpgSpeedButton

> 源码位置：`gui/fpg_button.pas`

**组件介绍**：无文字、扁平的快速按钮，常用于工具栏。继承自 `TfpgBaseButton`，仅显示图像，不支持焦点框。属性与 `TfpgButton` 类似但默认 `Flat := True`、`ShowImage := True`，无 `Text` 属性。

#### 3.3.3 TfpgCheckBox

> 源码位置：`gui/fpg_checkbox.pas`
> 继承链：`TfpgCheckBox` → `TfpgBaseCheckBox` → `TfpgWidget`

**组件介绍**：复选框，支持勾选状态、只读、自定义方框位置。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `BoxLayout` | `TBoxLayout` | RW | `tbLeftBox` | 方框位置（左/右） |
| `Checked` | `boolean` | RW | `False` | 勾选状态 |
| `ReadOnly` | `Boolean` | RW | `False` | 只读 |
| `Text` | `string` | RW | — | 标签文本 |
| `BackgroundColor` | `TfpgColor` | RW | `clWindowBackground` | 背景色 |
| `FontDesc` | `string` | RW | — | 字体描述 |
| `TextColor` | `TfpgColor` | RW | `clText1` | 文本色 |

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TNotifyEvent` | 勾选状态改变 |
| `OnEnter/OnExit` | `TNotifyEvent` | 焦点进出 |
| `OnMouseDown/Up/Move` | 鼠标事件 | 鼠标交互 |
| `OnMouseEnter/Exit` | `TNotifyEvent` | 鼠标进入/离开 |
| `OnShowHint` | `THintEvent` | 显示提示 |

##### 示例

```pascal
var cb: TfpgCheckBox;
begin
  cb := CreateCheckBox(Self, 10, 10, '启用高级模式');
  cb.Checked := True;
  cb.OnChange := @cbStateChanged;

  // 右侧方框
  cb := TfpgCheckBox.Create(Self);
  cb.Text := '同意条款';
  cb.BoxLayout := tbRightBox;
end;
```

#### 3.3.4 TfpgRadioButton

> 源码位置：`gui/fpg_radiobutton.pas`
> 继承链：`TfpgRadioButton` → `TfpgWidget`

**组件介绍**：单选按钮，同一父容器内自动互斥。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `AutoSize` | `boolean` | RW | `False` | 自动尺寸 |
| `BoxLayout` | `TBoxLayout` | RW | `tbLeftBox` | 方框位置 |
| `Checked` | `boolean` | RW | `False` | 选中状态 |
| `GroupIndex` | `integer` | RW | 0 | 分组索引（同组互斥） |
| `Text` | `string` | RW | — | 标签文本 |
| `FontDesc` | `string` | RW | — | 字体描述 |

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TNotifyEvent` | 选中状态改变 |
| `OnDragStartDetected` | `TNotifyEvent` | 拖放开始 |
| `OnEnter/OnExit` | `TNotifyEvent` | 焦点进出 |
| `OnMouseDown/Up/Move` | 鼠标事件 | 鼠标交互 |
| `OnMouseEnter/Exit` | `TNotifyEvent` | 鼠标进入/离开 |
| `OnShowHint` | `THintEvent` | 显示提示 |

##### 示例

```pascal
var rb1, rb2: TfpgRadioButton;
begin
  rb1 := TfpgRadioButton.Create(Self);
  rb1.Text := '男'; rb1.Top := 10; rb1.Checked := True;
  rb2 := TfpgRadioButton.Create(Self);
  rb2.Text := '女'; rb2.Top := 30;
end;
```

##### 避坑注意事项

> **避坑:** 同一父容器中的 `TfpgRadioButton` 自动互斥，无需设置 `GroupIndex`；如需在同一容器中创建多组单选，使用 `GroupIndex` 区分。

#### 3.3.5 TfpgToggle

> 源码位置：`gui/fpg_toggle.pas`
> 继承链：`TfpgToggle` → `TfpgCheckBox`

**组件介绍**：开关切换控件（ON/OFF 风格），继承自复选框。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `UseAnimation` | `Boolean` | RW | — | 启用动画 |
| `ToggleWidth` | `TfpgCoord` | RW | 45 | 开关宽度 |
| `CheckedCaption` | `TfpgString` | RW | — | 勾选时文本 |
| `CheckedColor` | `TfpgColor` | RW | `clLime` | 勾选时颜色 |
| `CheckedTextColor` | `TfpgColor` | RW | `clHilite2` | 勾选时文本色 |
| `UnCheckedCaption` | `TfpgString` | RW | — | 未勾选时文本 |
| `UnCheckedColor` | `TfpgColor` | RW | `clWindowBackground` | 未勾选时颜色 |
| `UnCheckedTextColor` | `TfpgColor` | RW | `clText1` | 未勾选时文本色 |

##### 示例

```pascal
var tg: TfpgToggle;
begin
  tg := TfpgToggle.Create(Self);
  tg.ToggleWidth := 50;
  tg.CheckedCaption := 'ON';
  tg.UnCheckedCaption := 'OFF';
  tg.UseAnimation := True;
  tg.Checked := True;
end;
```

### 3.4 选择

#### 3.4.1 TfpgComboBox

> 源码位置：`gui/fpg_combobox.pas`
> 继承链：`TfpgComboBox` → `TfpgBaseStaticCombo` → `TfpgBaseComboBox` → `TfpgWidget`

**组件介绍**：下拉组合框，可选择或输入文本。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Align` | `TAlign` | RW | `alNone` | 对齐 |
| `AutoSize` | `Boolean` | RW | `False` | 自动尺寸 |
| `BackgroundColor` | `TfpgColor` | RW | `clBoxColor` | 背景色 |
| `DropDownCount` | `integer` | RW | 8 | 下拉项数 |
| `ExtraHint` | `string` | RW | — | 额外提示 |
| `FocusItem` | `integer` | RW | — | 当前选中项索引 |
| `FontDesc` | `string` | RW | — | 字体描述 |
| `Items` | `TStringList` | RW | — | 项集合 |
| `Margin` | `integer` | RW | 1 | 边距 |
| `Options` | `TfpgComboOptions` | RW | `[]` | 选项集 |
| `ReadOnly` | `Boolean` | RW | `False` | 只读 |
| `ScrollBarWidth` | `integer` | RW | — | 滚动条宽度 |
| `Text` | `string` | RW | — | 当前文本 |
| `TextColor` | `TfpgColor` | RW | `clText1` | 文本色 |

`TfpgComboOption` 选项：`wo_FocusItemTriggersOnChange` / `wo_AllowUserBlank` / `wo_NoControlFrame`。

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TNotifyEvent` | 选中项改变 |
| `OnCloseUp` | `TNotifyEvent` | 下拉关闭 |
| `OnDropDown` | `TNotifyEvent` | 下拉展开 |
| `OnDragStartDetected` | `TNotifyEvent` | 拖放开始 |
| `OnEnter/OnExit` | `TNotifyEvent` | 焦点进出 |
| `OnMouseDown/Up/Move` | 鼠标事件 | 鼠标交互 |
| `OnMouseEnter/Exit` | `TNotifyEvent` | 鼠标进入/离开 |
| `OnShowHint` | `THintEvent` | 显示提示 |

##### 示例

```pascal
var cb: TfpgComboBox;
begin
  cb := TfpgComboBox.Create(Self);
  cb.Left := 10; cb.Top := 10; cb.Width := 150;
  cb.Items.Add('选项一');
  cb.Items.Add('选项二');
  cb.Items.Add('选项三');
  cb.FocusItem := 0;
  cb.OnChange := @cbChanged;
end;
```

#### 3.4.2 TfpgListBox

> 源码位置：`gui/fpg_listbox.pas`
> 继承链：`TfpgListBox` → `TfpgTextListBox` → `TfpgBaseListBox` → `TfpgWidget`

**组件介绍**：纯列表框，仅显示文本项，支持单选/多选、热点追踪、拖拽排序。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Align` | `TAlign` | RW | `alNone` | 对齐 |
| `AutoHeight` | `boolean` | RW | `False` | 自动高度 |
| `BackgroundColor` | `TfpgColor` | RW | `clListBox` | 背景色 |
| `BorderStyle` | `TfpgEditBorderStyle` | RW | `ebsDefault` | 边框样式 |
| `DragToReorder` | `boolean` | RW | `False` | 拖拽排序 |
| `FocusItem` | `integer` | RW | — | 焦点项索引 |
| `FontDesc` | `string` | RW | — | 字体描述 |
| `HotTrack` | `boolean` | RW | `False` | 热点追踪 |
| `Items` | `TStringList` | RW | — | 项集合 |
| `PopupFrame` | `boolean` | RW | `False` | 弹出框架模式 |
| `ReadOnly` | `Boolean` | RW | `False` | 只读 |
| `ScrollBarPage` | `Integer` | RW | — | 滚动条页大小 |
| `ScrollBarWidth` | `Integer` | RW | — | 滚动条宽度 |
| `Text` | `string` | RW | — | 当前文本 |
| `TextColor` | `TfpgColor` | RW | `clText1` | 文本色 |
| `VisibleItems` | `Integer` | R | — | 可见行数 |

##### 方法

| 原型 | 功能 | 说明 |
|------|------|------|
| `procedure BeginUpdate;` | 开始批量更新 | — |
| `procedure EndUpdate;` | 结束批量更新 | — |
| `procedure Update;` | 刷新控件 | — |
| `function ItemCount: integer;` | 返回项数 | — |
| `function RowHeight: integer;` | 返回行高 | — |
| `procedure SetFirstItem(item: integer);` | 设置首个可见项 | — |
| `function GetClientRect: TfpgRect;` | 获取客户区 | — |

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TNotifyEvent` | 焦点项改变 |
| `OnDoubleClick` | `TMouseButtonEvent` | 双击 |
| `OnDragStartDetected` | `TNotifyEvent` | 拖放开始 |
| `OnEnter/OnExit` | `TNotifyEvent` | 焦点进出 |
| `OnKeyPress` | `TKeyPressEvent` | 键盘按键 |
| `OnMouseDown/Up/Move` | 鼠标事件 | 鼠标交互 |
| `OnMouseEnter/Exit` | `TNotifyEvent` | 鼠标进入/离开 |
| `OnScroll` | — | 滚动 |
| `OnSelect` | — | 选中项 |
| `OnShowHint` | `THintEvent` | 显示提示 |

##### 示例

```pascal
var lb: TfpgListBox; i: integer;
begin
  lb := TfpgListBox.Create(Self);
  lb.Left := 10; lb.Top := 10;
  lb.Width := 150; lb.Height := 200;
  for i := 1 to 10 do
    lb.Items.Add('项 ' + IntToStr(i));
  lb.FocusItem := 0;
  lb.OnSelect := @lbItemSelected;

  lb.DragToReorder := True;  // 允许拖拽排序
end;
```

#### 3.4.3 TfpgColorListBox

> 继承链：`TfpgColorListBox` → `TfpgBaseColorListBox` → `TfpgBaseListBox`

**组件介绍**：显示一组颜色供选择的列表框。

##### 属性（新增）

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Color` | `TfpgColor` | RW | — | 当前颜色 |
| `ColorPalette` | `TfpgColorPalette` | RW | `cpStandardColors` | 颜色调色板 |
| `ShowColorNames` | `Boolean` | RW | `True` | 显示颜色名称 |

`TfpgColorPalette` 枚举：`cpStandardColors` / `cpSystemColors` / `cpWebColors` / `cpUserDefined`。

#### 3.4.4 TfpgListView

> 源码位置：`gui/fpg_listview.pas`
> 继承链：`TfpgListView` → `TfpgWidget`

**组件介绍**：功能丰富的列表视图控件，支持报表/图标视图模式、多列、多选、图标等。

##### 属性

| 名称 | 类型 | 读写 | 说明 |
|------|------|------|------|
| `Columns` | `TfpgLVColumns` | RW | 列集合 |
| `Font` | `TfpgFontResourceBase` | RW | 字体对象 |
| `HScrollBar` / `VScrollBar` | `TfpgScrollBar` | R | 滚动条 |
| `Images` / `ImagesSelected` / `ImagesFocused` / `ImagesHotTrack` | `TfpgImageList` | RW | 各状态图像列表 |
| `SubItemImages` | `TfpgImageList` | RW | 子项图像列表 |
| `ItemHeight` | `Integer` | R | 行高 |
| `ItemIndex` | `Integer` | RW | 当前项索引 |
| `Items` | `TfpgLVItems` | RW | 项集合 |
| `MultiSelect` | `Boolean` | RW | 多选 |
| `ViewStyle` | `TfpgLVPainter` | RW | 视图样式 |
| `ScrollBarWidth` | `Integer` | RW | 滚动条宽度 |
| `ScrollBarStyle` | `TfpgScrollStyle` | RW | 滚动条样式 |
| `SelectionFollowsFocus` | `Boolean` | RW | 选中跟随焦点 |
| `ShowHeaders` | `Boolean` | RW | 显示列头 |
| `ShowFocusRect` | `Boolean` | RW | 显示焦点框 |

##### 方法

| 原型 | 功能 | 入参 | 返回值 |
|------|------|------|--------|
| `function AddItem: TfpgLVItem;` | 添加项 | — | 新项 |
| `function NewItem: TfpgLVItem;` | 创建新项 | — | 新项 |
| `function GetItemFromPoint(X, Y: Integer; out AIndex: Integer): TfpgLVItem;` | 按坐标获取项 | x,y | 项对象 |
| `procedure MakeItemVisible(AIndex: Integer; PartialOK: Boolean = False);` | 滚动到可见项 | 索引 | — |
| `procedure BeginUpdate;` | 开始批量更新 | — | — |
| `procedure EndUpdate;` | 结束批量更新 | — | — |

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnColumnClick` | `TfpgLVColumnClickEvent` | 列头点击 |
| `OnItemActivate` | `TfpgLVItemActivateEvent` | 项激活（双击） |
| `OnPaintColumn` | `TfpgLVPaintColumnEvent` | 自定义列绘制 |
| `OnPaintItem` | `TfpgLVPaintItemEvent` | 自定义项绘制 |
| `OnSelectionChanged` | `TfpgLVItemSelectEvent` | 选中改变 |

##### 子对象 TfpgLVColumn

| 属性 | 类型 | 说明 |
|------|------|------|
| `Caption` | `String` | 列标题 |
| `Alignment` / `CaptionAlignment` | `TAlignment` | 内容/标题对齐 |
| `AutoSize` / `AutoExpand` | `Boolean` | 自动宽度/扩展 |
| `Width` | `Integer` | 列宽 |
| `Visible` / `Clickable` / `Resizable` | `Boolean` | 可见/可点击/可缩放 |

##### 子对象 TfpgLVItem

| 属性 | 类型 | 说明 |
|------|------|------|
| `Caption` | `String` | 主文本 |
| `ImageIndex` | `Integer` | 图像索引 |
| `SubItems` | `TStrings` | 子项文本 |
| `UserData` | `Pointer` | 用户数据 |
| `Selected[ListView]` | `Boolean` | 选中状态 |

##### 示例

```pascal
var lv: TfpgListView; col: TfpgLVColumn; item: TfpgLVItem;
begin
  lv := TfpgListView.Create(Self);
  lv.Align := alClient;

  col := TfpgLVColumn.Create(lv.Columns);
  col.Caption := '名称'; col.Width := 150;
  col := TfpgLVColumn.Create(lv.Columns);
  col.Caption := '大小'; col.Width := 80;

  item := lv.AddItem;
  item.Caption := '文件1.txt';
  item.SubItems.Add('2 KB');
  item := lv.AddItem;
  item.Caption := '文件2.txt';
  item.SubItems.Add('5 KB');
end;

// 自定义绘制项
procedure TMyForm.lvPaintItem(ListView: TfpgListView; Canvas: TfpgCanvas;
  Item: TfpgLVItem; ItemIndex: Integer; Area: TfpgRect; var PaintPart: TfpgLVItemPaintPart);
begin
  Canvas.SetTextColor(clRed);
  Canvas.DrawString(Area.Left + 5, Area.Top + 2, Item.Caption);
  PaintPart := [];  // 禁止默认绘制
end;
```

#### 3.4.5 TfpgTreeView

> 源码位置：`gui/fpg_tree.pas`
> 继承链：`TfpgTreeView` → `TfpgWidget`

**组件介绍**：树视图控件，支持节点展开/折叠、图标、列头、状态图像。

##### 属性

| 名称 | 类型 | 读写 | 说明 |
|------|------|------|------|
| `BackgroundColor` | `TfpgColor` | RW | 背景色（默认 `clListBox`） |
| `DefaultColumnWidth` | `word` | RW | 默认列宽 |
| `FontDesc` | `string` | RW | 字体描述 |
| `ImageList` / `StateImageList` | `TfpgImageList` | RW | 图像/状态图像列表 |
| `IndentNodeWithNoImage` | `boolean` | RW | 无图像节点缩进 |
| `NoImageIndent` | `integer` | RW | 无图像缩进量 |
| `ScrollWheelDelta` | `integer` | RW | 滚轮步长 |
| `ShowColumns` | `boolean` | RW | 显示列头 |
| `ShowImages` | `boolean` | RW | 显示图像 |
| `TreeLineColor` | `TfpgColor` | RW | 连接线颜色 |
| `TreeLineStyle` | `TfpgLineStyle` | RW | 连接线样式 |
| `Selection` | `TfpgTreeNode` | RW | 当前选中节点 |
| `RootNode` | `TfpgTreeNode` | R | 根节点 |
| `PopupMenu` | `TfpgPopupMenu` | RW | 右键菜单 |

##### 方法

| 原型 | 功能 | 说明 |
|------|------|------|
| `procedure SetColumnWidth(AIndex, AWidth: word);` | 设置列宽 | — |
| `function GetColumnWidth(AIndex: word): word;` | 获取列宽 | — |
| `function GetNodeAt(const X, Y: integer): TfpgTreeNode;` | 按坐标获取节点 | — |
| `procedure FullCollapse;` / `procedure FullExpand;` | 全部折叠/展开 | — |
| `procedure GotoNextNodeUp;` / `procedure GotoNextNodeDown;` | 上/下移节点 | — |
| `function NextNode(ANode): TfpgTreeNode;` | 下一个节点 | — |
| `function PrevNode(ANode): TfpgTreeNode;` | 上一个节点 | — |
| `function NextVisualNode(ANode): TfpgTreeNode;` | 下一个可见节点 | — |
| `function PrevVisualNode(ANode): TfpgTreeNode;` | 上一个可见节点 | — |
| `procedure BeginUpdate;` / `procedure EndUpdate;` | 批量更新 | — |
| `function GetNodeRowHeight: Integer;` | 获取行高 | — |

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TNotifyEvent` | 选中节点改变 |
| `OnDoubleClick` | — | 双击 |
| `OnExpand` | `TfpgTreeExpandEvent` | 节点展开 |
| `OnKeyChar/OnKeyPress` | 键盘事件 | 键盘输入 |
| `OnStateImageClicked` | `TfpgStateImageClickedEvent` | 状态图标点击 |
| `OnShowHint` | `THintEvent` | 提示 |

##### 子对象 TfpgTreeNode

| 属性 | 类型 | 说明 |
|------|------|------|
| `Text` | `TfpgString` | 节点文本 |
| `Data` | `Pointer` | 用户数据 |
| `ImageIndex` / `StateImageIndex` | `integer` | 图像索引 |
| `Collapsed` | `boolean` | 是否折叠 |
| `HasChildren` | `Boolean` | 是否有子节点 |
| `Parent` / `FirstSubNode` / `LastSubNode` | `TfpgTreeNode` | 亲属节点 |
| `Next` / `Prev` | `TfpgTreeNode` | 兄弟节点 |
| `TextColor` / `SelColor` / `SelTextColor` | `TfpgColor` | 颜色 |

##### 示例

```pascal
var tv: TfpgTreeView; root, child, grandchild: TfpgTreeNode;
begin
  tv := TfpgTreeView.Create(Self);
  tv.Align := alClient;

  root := tv.RootNode.AppendText('根节点');
  child := root.AppendText('子节点1');
  grandchild := child.AppendText('孙节点1');
  root.AppendText('子节点2');

  root.Expand;
  tv.Selection := root.FirstSubNode;
end;
```

#### 3.4.6 TfpgStringGrid

> 源码位置：`gui/fpg_grid.pas`, `gui/fpg_customgrid.pas`, `gui/fpg_basegrid.pas`
> 继承链：`TfpgStringGrid` → `TfpgCustomStringGrid` → `TfpgCustomGrid` → `TfpgBaseGrid`

**组件介绍**：字符串网格（表格）控件，支持列定义、行高、滚动、列头点击等。

##### 属性

| 名称 | 类型 | 读写 | 说明 |
|------|------|------|------|
| `Align` | `TAlign` | RW | 对齐 |
| `AutoHeight` | `boolean` | RW | 自动行高 |
| `BorderStyle` | `TfpgEditBorderStyle` | RW | 边框 |
| `ColumnCount` | `integer` | RW | 列数 |
| `Columns[AIndex]` | `TfpgStringColumn` | R | 列对象 |
| `FocusRow` | `Integer` | RW | 焦点行 |
| `FontDesc` | `string` | RW | 字体描述 |
| `HeaderFontDesc` | `string` | RW | 列头字体 |
| `Options` | `TfpgGridOptions` | RW | 选项集 |
| `RowCount` | `integer` | RW | 行数 |
| `ScrollBarStyle` | `TfpgScrollStyle` | RW | 滚动条样式 |
| `ScrollBarPage` / `ScrollBarWidth` | `integer` | RW | 滚动条参数 |
| `TopRow` | `Integer` | RW | 首行 |
| `VisibleRows` | `Integer` | R | 可见行数 |
| `Cells[col, row]` | `string` | RW | 单元格内容 |

`TfpgGridOption` 选项：`go_HideFocusRect` / `go_AlternativeColor` / `go_SmoothScroll`。

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnClick` / `OnDoubleClick` | — | 单击/双击 |
| `OnEnter/OnExit` | `TNotifyEvent` | 焦点进出 |
| `OnHeaderClick` | `TfpgHeaderClick` | 列头点击 |
| `OnKeyPress` | `TKeyPressEvent` | 键盘按键 |
| `OnMouseDown/Up/Move` | 鼠标事件 | 鼠标交互 |
| `OnRowChange` | `TfpgRowChangeNotify` | 行改变 |
| `OnShowHint` | `THintEvent` | 提示 |

##### 示例

```pascal
var grid: TfpgStringGrid; i: integer;
begin
  grid := TfpgStringGrid.Create(Self);
  grid.Align := alClient;

  grid.ColumnCount := 3;
  grid.Columns[0].Title := '编号';  grid.Columns[0].Width := 60;
  grid.Columns[1].Title := '姓名'; grid.Columns[1].Width := 120;
  grid.Columns[2].Title := '分数'; grid.Columns[2].Width := 80;

  grid.RowCount := 5;
  for i := 0 to 4 do
  begin
    grid.Cells[0, i] := IntToStr(i + 1);
    grid.Cells[1, i] := '学生' + IntToStr(i + 1);
    grid.Cells[2, i] := IntToStr(Random(100));
  end;
end;
```

#### 3.4.7 TfpgFileGrid

> 继承链：`TfpgFileGrid` → `TfpgCustomGrid`

**组件介绍**：显示文件列表的网格控件，与文件对话框内部使用同一组件。

##### 属性

| 名称 | 类型 | 读写 | 说明 |
|------|------|------|------|
| `FileList` | `TfpgFileList` | RW | 文件列表对象 |
| `CurrentEntry` | `TFileEntry` | R | 当前文件条目 |

#### 3.4.8 TfpgHexView

> 源码位置：`gui/fpg_hexview.pas`

**组件介绍**：十六进制查看器，常用于二进制数据展示。提供地址列 + 十六进制列 + ASCII 列。属性包含 `Data`（字节数组）、`BytesPerLine`、`ShowAddress`、`ShowAscii` 等。

##### 示例

```pascal
var hv: TfpgHexView;
begin
  hv := TfpgHexView.Create(Self);
  hv.Align := alClient;
  hv.BytesPerLine := 16;
  // hv.Data := @MyBuffer; hv.DataSize := SizeOf(MyBuffer);
end;
```

### 3.5 容器

#### 3.5.1 TfpgPanel

> 源码位置：`gui/fpg_panel.pas`
> 继承链：`TfpgPanel` → `TfpgAbstractPanel` → `TfpgWidget`

**组件介绍**：面板容器，可显示标题、设置样式（凸起/下沉/平坦）、边框、文本对齐等。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Align` | `TAlign` | RW | `alNone` | 对齐 |
| `Alignment` | `TAlignment` | RW | `taCenter` | 文本水平对齐 |
| `BackgroundColor` | `TfpgColor` | RW | `clWindowBackground` | 背景色 |
| `BorderStyle` | `TPanelBorder` | RW | `bsSingle` | 边框 |
| `FontDesc` | `string` | RW | — | 字体描述 |
| `Layout` | `TLayout` | RW | `tlCenter` | 文本垂直布局 |
| `LineSpace` | `integer` | RW | 2 | 行间距 |
| `Margin` | `integer` | RW | 2 | 边距 |
| `ParentBackgroundColor` | `Boolean` | RW | `False` | 使用父背景色 |
| `Style` | `TPanelStyle` | RW | `bsRaised` | 面板样式 |
| `Text` | `string` | RW | — | 标题文本 |
| `TextColor` | `TfpgColor` | RW | `clText1` | 文本色 |
| `WrapText` | `boolean` | RW | `False` | 自动换行 |

`TPanelStyle`：`bsLowered` / `bsRaised` / `bsFlat`。
`TPanelBorder`：`bsSingle` / `bsDouble`。

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnClick/OnDoubleClick` | — | 点击/双击 |
| `OnDragStartDetected` | `TNotifyEvent` | 拖放 |
| `OnMouseDown/Up/Move` | 鼠标事件 | 鼠标交互 |
| `OnMouseScroll` | `TMouseWheelEvent` | 滚轮 |
| `OnPaint` | `TPaintEvent` | 绘制 |
| `OnResize` | `TNotifyEvent` | 尺寸改变 |
| `OnShowHint` | `THintEvent` | 提示 |

##### 示例

```pascal
var pnl: TfpgPanel;
begin
  pnl := TfpgPanel.Create(Self);
  pnl.Align := alTop;
  pnl.Height := 60;
  pnl.Text := '工具栏';
  pnl.Style := bsRaised;
  // 子控件放置在面板上
  btn.Parent := pnl;
  btn.Align := alLeft;
end;
```

#### 3.5.2 TfpgGroupBox

> 继承链：`TfpgGroupBox` → `TfpgAbstractPanel`

**组件介绍**：分组框，带有标题的容器，常用于将相关控件分组。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Alignment` | `TAlignment` | RW | — | 标题对齐 |
| `Margin` | `integer` | RW | — | 边距 |
| `Text` | `string` | RW | — | 分组标题 |
| `FontDesc` | `string` | RW | — | 字体描述 |
| `Style` | `TPanelStyle` | RW | — | 样式 |

##### 示例

```pascal
var gb: TfpgGroupBox;
begin
  gb := TfpgGroupBox.Create(Self);
  gb.Left := 10; gb.Top := 10;
  gb.Width := 300; gb.Height := 150;
  gb.Text := '用户信息';
  CreateLabel(gb, 10, 20, '姓名：');
end;
```

#### 3.5.3 TfpgBevel

> 继承链：`TfpgBevel` → `TfpgAbstractPanel`

**组件介绍**：斜面/分隔线，通过 `Shape` 控制形状（方框/边框/上下左右线/间隔/垂直分隔）。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Shape` | `TPanelShape` | RW | `bsBox` | 形状 |
| `Style` | `TPanelStyle` | RW | — | 样式 |
| `BorderStyle` | `TPanelBorder` | RW | `bsSingle` | 边框 |
| `ParentBackgroundColor` | `Boolean` | RW | `False` | 使用父背景色 |

`TPanelShape`：`bsBox` / `bsFrame` / `bsTopLine` / `bsBottomLine` / `bsLeftLine` / `bsRightLine` / `bsSpacer` / `bsVerDivider`。

##### 示例

```pascal
var bv: TfpgBevel;
begin
  bv := TfpgBevel.Create(Self);
  bv.Align := alTop;
  bv.Height := 2;
  bv.Shape := bsBottomLine;  // 水平分隔线
end;
```

#### 3.5.4 TfpgFrame

> 源码位置：`gui/fpg_panel.pas` / `gui/fpg_scrollframe.pas`

**组件介绍**：框架容器，可作为容器承载子控件，是 `TfpgScrollFrame` 的基类。可重用、可嵌套。

#### 3.5.5 TfpgPageControl（+ TfpgTabSheet）

> 源码位置：`gui/fpg_tab.pas`
> 继承链：`TfpgPageControl` → `TfpgWidget`

**组件介绍**：页面控件（Tab 控件），包含多个 `TfpgTabSheet` 页面，每次显示一个活动页面。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `ActivePage` | `TfpgTabSheet` | RW | — | 活动页面 |
| `ActivePageIndex` | `integer` | RW | 0 | 活动页索引 |
| `ActiveTabColor` | `TfpgColor` | RW | `clDefault` | 活动标签颜色 |
| `ActiveTabTextColor` | `TfpgColor` | RW | `clDefault` | 活动标签文本色 |
| `Align` | `TAlign` | RW | `alNone` | 对齐 |
| `BackgroundColor` | `TfpgColor` | RW | — | 背景色 |
| `FixedTabWidth` | `integer` | RW | 0 | 固定标签宽度（0=自适应） |
| `FixedTabHeight` | `integer` | RW | 0 | 固定标签高度 |
| `FontDesc` | `string` | RW | — | 字体描述 |
| `Options` | `TfpgTabOptions` | RW | `[]` | 选项集 |
| `SortPages` | `boolean` | RW | `False` | 自动排序标签页 |
| `Style` | `TfpgTabStyle` | RW | `tsTabs` | 标签样式 |
| `TabPosition` | `TfpgTabPosition` | RW | `tpTop` | 标签位置 |
| `TextColor` | `TfpgColor` | RW | `clText1` | 文本色 |
| `PageCount` | `Integer` | R | — | 标签页数量 |
| `Pages[AIndex]` | `TfpgTabSheet` | R | — | 按索引获取标签页 |

##### 方法

| 原型 | 功能 | 返回值 |
|------|------|--------|
| `function AppendTabSheet(ATitle: string): TfpgTabSheet;` | 追加标签页 | 新标签页 |
| `procedure RemoveTabSheet(ATabSheet: TfpgTabSheet);` | 移除标签页 | — |
| `function TabSheetAtPos(const x, y: integer): TfpgTabSheet;` | 按坐标获取标签页 | 标签页 |
| `procedure BeginUpdate;` / `procedure EndUpdate;` | 批量更新 | — |

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TTabSheetChange` | 活动页面改变 |
| `OnClosingTabSheet` | `TTabSheetClosing` | 标签页即将关闭 |

```pascal
TTabSheetChange  = procedure(Sender: TObject; NewActiveSheet: TfpgTabSheet) of object;
TTabSheetClosing = procedure(Sender: TObject; ATabSheet: TfpgTabSheet) of object;
```

##### 子对象 TfpgTabSheet

| 属性 | 类型 | 说明 |
|------|------|------|
| `PageIndex` | `Integer` | 页索引 |
| `PageControl` | `TfpgPageControl` | 所属页面控件 |
| `TabVisible` | `boolean` | 标签是否可见 |
| `TabColor` / `TabTextColor` | `TfpgColor` | 标签颜色/文本色 |
| `Text` | `string` | 标签文本 |

##### 示例

```pascal
var pc: TfpgPageControl; ts1, ts2: TfpgTabSheet;
begin
  pc := TfpgPageControl.Create(Self);
  pc.Align := alClient;
  ts1 := pc.AppendTabSheet('基本信息');
  ts2 := pc.AppendTabSheet('高级设置');
  CreateLabel(ts1, 10, 10, '基本设置内容');
  CreateLabel(ts2, 10, 10, '高级设置内容');
  pc.ActivePageIndex := 0;
end;
```

#### 3.5.6 TfpgScrollBar

> 源码位置：`gui/fpg_scrollbar.pas`
> 继承链：`TfpgScrollBar` → `TfpgWidget`

**组件介绍**：独立滚动条控件，可水平/垂直方向。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Align` | `TAlign` | RW | `alNone` | 对齐 |
| `Orientation` | `TOrientation` | RW | `orVertical` | 方向 |
| `Min` | `integer` | RW | 0 | 最小值 |
| `Max` | `integer` | RW | 100 | 最大值 |
| `Position` | `integer` | RW | 10 | 当前位置 |
| `PageSize` | `integer` | RW | 5 | 页大小 |
| `ScrollStep` | `integer` | RW | 1 | 步长 |

##### 方法

| 原型 | 功能 |
|------|------|
| `procedure LineUp;` | 上移一行 |
| `procedure LineDown;` | 下移一行 |
| `procedure PageUp;` | 上翻一页 |
| `procedure PageDown;` | 下翻一页 |
| `procedure RepaintSlider;` | 重绘滑块 |

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnScroll` | `TScrollNotifyEvent` | 滚动时触发 |

```pascal
TScrollNotifyEvent = procedure(Sender: TObject; position: integer) of object;
```

##### 示例

```pascal
var sb: TfpgScrollBar;
begin
  sb := TfpgScrollBar.Create(Self);
  sb.Orientation := orVertical;
  sb.Min := 0; sb.Max := 100; sb.Position := 50;
  sb.OnScroll := @sbScrolled;
end;
```

#### 3.5.7 TfpgScrollFrame

> 源码位置：`gui/fpg_scrollframe.pas`
> 继承链：`TfpgScrollFrame` → `TfpgFrame` → `TfpgWidget`

**组件介绍**：可滚动的框架容器，子控件可放置在 `ContentFrame` 上，超出可见区域通过滚动条访问。

##### 属性

| 名称 | 类型 | 读写 | 说明 |
|------|------|------|------|
| `ContentFrame` | `TfpgAutoSizingFrame` | R | 内容框架（放置子控件） |
| `ScrollBarWidth` | `Integer` | RW | 滚动条宽度 |
| `XOffset` | `integer` | RW | 水平偏移 |
| `YOffset` | `integer` | RW | 垂直偏移 |

##### 示例

```pascal
var sf: TfpgScrollFrame; btn: TfpgButton;
begin
  sf := TfpgScrollFrame.Create(Self);
  sf.Align := alClient;
  btn := TfpgButton.Create(sf.ContentFrame);
  btn.Top := 1000;  // 远超可见区域，通过滚动访问
  btn.Text := '远处的按钮';
end;
```

#### 3.5.8 TfpgSplitter

> 源码位置：`gui/fpg_splitter.pas`
> 继承链：`TfpgSplitter` → `TfpgWidget`

**组件介绍**：分隔条，可拖动调整相邻控件尺寸，支持双击折叠。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Align` | `TAlign` | RW | `alNone` | 对齐 |
| `AutoSnap` | `boolean` | RW | `True` | 自动吸附（双击折叠） |
| `ColorGrabBar` | `TfpgColor` | RW | `clSplitterGrabBar` | 抓取条颜色 |

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnSnap` | `TfpgSnapEvent` | 吸附时触发 |

```pascal
TfpgSnapEvent = procedure(Sender: TObject; const AClosed: boolean) of object;
```

##### 示例

```pascal
var pnl1, pnl2: TfpgPanel; spl: TfpgSplitter;
begin
  pnl1 := TfpgPanel.Create(Self);
  pnl1.Align := alLeft; pnl1.Width := 200;

  spl := TfpgSplitter.Create(Self);
  spl.Align := alLeft; spl.Width := 5;

  pnl2 := TfpgPanel.Create(Self);
  pnl2.Align := alClient;
end;
```

##### 子控件 TfpgMigSplitter

用于 MigLayout 网格中的分隔条，设置 `Control` 属性指向需要调整尺寸的控件。

| 属性 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `Control` | `TfpgWidget` | — | 关联的控件 |
| `Orientation` | `TfpgSplitterOrientation` | `soVertical` | 方向 |
| `MinSize` | `Integer` | 30 | 最小尺寸 |

### 3.6 弹窗

#### 3.6.1 TfpgMessageBox

> 源码位置：`gui/fpg_dialogs.pas`
> 继承链：`TfpgMessageBox` → `TfpgForm`

**组件介绍**：消息框组件，显示一段提示文本。通常使用 `ShowMessage` 过程或 `fpgMessageDlg` 函数，不需要手动创建。

##### 属性

| 名称 | 类型 | 读写 | 说明 |
|------|------|------|------|
| `CentreText` | `Boolean` | RW | 文本居中 |
| `FontDesc` | `string` | RW | 字体描述 |

##### 方法

| 原型 | 功能 |
|------|------|
| `procedure SetMessage(AMessage: string);` | 设置消息文本 |

#### 3.6.2 TfpgMessageDialog / fpgMessageDlg

> 源码位置：`gui/fpg_dialogs.pas`

**组件介绍**：标准消息对话框，显示图标、文本、多按钮。

```pascal
function fpgMessageDlg(const AMsg: TfpgString; AType: TfpgMsgDlgType;
  AButtons: TfpgMsgDlgButtons): TfpgModalResult; overload;

function fpgMessageDlg(const ACaption: TfpgString; const AMsg: TfpgString;
  AType: TfpgMsgDlgType; AButtons: TfpgMsgDlgButtons): TfpgModalResult; overload;
```

`TfpgMsgDlgType` 枚举：

| 值 | 说明 |
|------|------|
| `mtAbout` | 关于 |
| `mtWarning` | 警告 |
| `mtError` | 错误 |
| `mtInformation` | 信息 |
| `mtConfirmation` | 确认 |
| `mtCustom` | 自定义 |

`TfpgMsgDlgBtn` 枚举：`mbOK` / `mbCancel` / `mbYes` / `mbNo` / `mbAbort` / `mbRetry` / `mbIgnore` / `mbAll` / `mbNoToAll` / `mbYesToAll` / `mbHelp` / `mbClose`。

**预定义按钮组合**：

```pascal
const
  mbYesNoCancel      = [mbYes, mbNo, mbCancel];
  mbYesNo            = [mbYes, mbNo];
  mbOKCancel         = [mbOK, mbCancel];
  mbAbortRetryIgnore = [mbAbort, mbRetry, mbIgnore];
```

##### 示例

```pascal
// 简单信息提示
fpgMessageDlg('操作完成！', mtInformation, [mbOK]);

// 确认对话框
if fpgMessageDlg('确认', '是否删除选中项？', mtConfirmation, [mbYes, mbNo]) = mrYes then
  DeleteItem;
```

#### 3.6.3 TfpgOpenDialog / TfpgFileDialog

> 源码位置：`gui/fpg_dialogs.pas`
> 继承链：`TfpgFileDialog` → `TfpgForm`

**组件介绍**：文件打开/保存对话框。通过 `sfdOpen`/`sfdSave` 区分模式。

##### 属性

| 名称 | 类型 | 读写 | 说明 |
|------|------|------|------|
| `FileName` | `TfpgString` | RW | 选定的文件名 |
| `Filter` | `string` | RW | 文件过滤器 |
| `InitialDir` | `string` | RW | 初始目录 |
| `ShowHidden` | `boolean` | RW | 显示隐藏文件 |
| `FontDesc` | `string` | RW | 字体描述 |

##### 方法

| 原型 | 功能 |
|------|------|
| `function RunOpenFile: boolean;` | 打开模式 |
| `function RunSaveFile: boolean;` | 保存模式 |

**常量**：

```pascal
const
  sfdOpen = True;   // 打开模式
  sfdSave = False;  // 保存模式
```

**文件过滤器格式**：`描述 (*.ext)|*.ext|描述2 (*.ext2)|*.ext2`

##### 示例

```pascal
var dlg: TfpgFileDialog;
begin
  dlg := TfpgFileDialog.Create(nil);
  try
    dlg.Filter := '文本文件 (*.txt)|*.txt|所有文件 (*.*)|*.*';
    dlg.InitialDir := '/home/user';
    if dlg.ShowModal = mrOK then
      LoadFile(dlg.FileName);
  finally
    dlg.Free;
  end;
end;
```

#### 3.6.4 TfpgSaveDialog

`TfpgFileDialog` 设置 `sfdSave` 模式即作为保存对话框使用；通过全局函数 `SelectFileDialog(sfdSave, Filter, InitialDir)` 也可。

#### 3.6.5 TfpgSelectFolderDialog / SelectDirDialog

> 源码位置：`gui/fpg_dialogs.pas`

```pascal
function SelectDirDialog(const AStartDir: TfpgString = ''): TfpgString;
```

**示例**：

```pascal
var Dir: TfpgString;
begin
  Dir := SelectDirDialog('/home/user');
  if Dir <> '' then
    LoadFilesFrom(Dir);
end;
```

#### 3.6.6 TfpgColorDialog / fpgSelectColorDialog

> 源码位置：`gui/fpg_dialogs.pas`

```pascal
function fpgSelectColorDialog(APresetColor: TfpgColor = clBlack): TfpgColor;
```

**示例**：

```pascal
var c: TfpgColor;
begin
  c := fpgSelectColorDialog(clRed);
  if c <> clDefault then
    pnl.BackgroundColor := c;
end;
```

#### 3.6.7 TfpgFontDialog / TfpgFontSelectDialog / SelectFontDialog

> 继承链：`TfpgFontSelectDialog` → `TfpgBaseDialog` → `TfpgForm`

```pascal
function SelectFontDialog(var FontDesc: string): boolean;
```

**示例**：

```pascal
var desc: string;
begin
  desc := mem.FontDesc;
  if SelectFontDialog(desc) then
    mem.FontDesc := desc;
end;
```

#### 3.6.8 TfpgPromptDialog / fpgInputQuery / fpgIntegerQuery

> 源码位置：`gui/fpg_dialogs.pas`

```pascal
function fpgInputQuery(const ACaption, APrompt: TfpgString; var Value: TfpgString): Boolean;
function fpgIntegerQuery(const ACaption, APrompt: TfpgString; var Value: Integer;
  const MaxValue: Integer; const MinValue: Integer = 0): Boolean;
```

**示例**：

```pascal
var s: TfpgString;
begin
  s := '';
  if fpgInputQuery('输入', '请输入姓名：', s) then
    UserName := s;
end;

var age: Integer;
begin
  age := 18;
  if fpgIntegerQuery('年龄', '请输入年龄：', age, 120, 0) then
    SaveAge(age);
end;
```

### 3.7 进度状态

#### 3.7.1 TfpgProgressBar

> 源码位置：`gui/fpg_progressbar.pas`
> 继承链：`TfpgProgressBar` → `TfpgCustomProgressBar` → `TfpgWidget`

**组件介绍**：水平进度条。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Align` | `TAlign` | RW | `alNone` | 对齐 |
| `BackgroundColor` | `TfpgColor` | RW | `$c4c4c4` | 背景色 |
| `Max` | `longint` | RW | 100 | 最大值 |
| `Min` | `longint` | RW | 0 | 最小值 |
| `Position` | `longint` | RW | 0 | 当前位置 |
| `Step` | `longint` | RW | — | 步长 |
| `ShowCaption` | `boolean` | RW | `False` | 显示百分比文本 |
| `TextColor` | `TfpgColor` | RW | `clText1` | 文本色 |

##### 方法

| 原型 | 功能 |
|------|------|
| `procedure StepIt;` | 按步长前进 |
| `procedure StepBy(AStep: longint);` | 按指定步长前进 |

##### 示例

```pascal
var pb: TfpgProgressBar; i: integer;
begin
  pb := TfpgProgressBar.Create(Self);
  pb.Align := alBottom; pb.Height := 20;
  pb.Min := 0; pb.Max := 100; pb.ShowCaption := True;
  for i := 0 to 100 do
  begin
    pb.Position := i;
    fpgApplication.ProcessMessages;  // 处理消息以更新 UI
    fpgPause(50);
  end;
end;
```

#### 3.7.2 TfpgGauge

> 源码位置：`gui/fpg_gauge.pas`
> 继承链：`TfpgGauge` → `TfpgBaseGauge` → `TfpgWidget`

**组件介绍**：仪表盘，提供文本/水平条/垂直条/饼图/指针/表盘等多种样式。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Align` | `TAlign` | RW | `alNone` | 对齐 |
| `Anchors` | `TAnchors` | RW | — | 锚点 |
| `BorderStyle` | `TBorderStyle` | RW | `bsSingle` | 边框样式 |
| `Color` | `TfpgColor` | RW | `$FFc4c4c4` | 背景色 |
| `FirstColor` | `TfpgColor` | RW | `clBlack` | 文本/指针色 |
| `Kind` | `TGaugeKind` | RW | `gkHorizontalBar` | 仪表类型 |
| `MaxValue` | `Longint` | RW | 100 | 最大值 |
| `MinValue` | `Longint` | RW | 0 | 最小值 |
| `Progress` | `Longint` | RW | — | 当前进度 |
| `SecondColor` | `TfpgColor` | RW | `clWhite` | 条/扇形主色 |
| `ShowText` | `Boolean` | RW | `True` | 显示文本 |

`TGaugeKind`：`gkText` / `gkHorizontalBar` / `gkVerticalBar` / `gkPie` / `gkNeedle` / `gkDial`。

##### 方法

| 原型 | 功能 |
|------|------|
| `procedure AddProgress(AValue: Longint);` | 增加进度 |
| `function Percentage: integer;` | 获取百分比（只读） |

##### 示例

```pascal
var g: TfpgGauge;
begin
  g := TfpgGauge.Create(Self);
  g.Kind := gkPie;
  g.MinValue := 0; g.MaxValue := 100;
  g.Progress := 75; g.ShowText := True;
end;
```

#### 3.7.3 TfpgTrackBar

> 源码位置：`gui/fpg_trackbar.pas`
> 继承链：`TfpgTrackBarExtra` / `TfpgTrackBar` → `TfpgBaseTrackBar` → `TfpgWidget`

**组件介绍**：滑块控件，支持水平/垂直方向。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Align` | `TAlign` | RW | `alNone` | 对齐 |
| `BackgroundColor` | `TfpgColor` | RW | — | 背景色 |
| `Max` | `integer` | RW | 100 | 最大值 |
| `Min` | `integer` | RW | 0 | 最小值 |
| `Orientation` | `TOrientation` | RW | `orHorizontal` | 方向 |
| `Position` | `integer` | RW | 0 | 当前位置 |
| `SliderSize` | `integer` | RW | 11 | 滑块尺寸（仅 Extra） |

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TTrackBarChange` | 位置改变 |

```pascal
TTrackBarChange = procedure(Sender: TObject; APosition: integer) of object;
```

##### 示例

```pascal
var tb: TfpgTrackBarExtra;
begin
  tb := TfpgTrackBarExtra.Create(Self);
  tb.Min := 0; tb.Max := 100; tb.Position := 50;
  tb.OnChange := @tbChanged;
end;
```

#### 3.7.4 TfpgMenuBar

> 源码位置：`gui/fpg_menu.pas`
> 继承链：`TfpgMenuBar` → `TfpgWidget`

**组件介绍**：菜单栏，承载顶级菜单项。

##### 属性

| 名称 | 类型 | 读写 | 说明 |
|------|------|------|------|
| `MenuOptions` | `TfpgMenuOptions` | RW | 菜单选项 |
| `BeforeShow` | `TNotifyEvent` | RW | 显示前事件 |

##### 方法

| 原型 | 功能 | 入参 | 返回值 |
|------|------|------|--------|
| `function AddMenuItem(const AMenuTitle: string; OnClickProc: TNotifyEvent): TfpgMenuItem;` | 添加菜单项 | 标题/回调 | 新菜单项 |
| `function MenuItem(const AMenuPos: integer): TfpgMenuItem;` | 按位置获取菜单项 | 位置 | 菜单项 |

##### 示例

```pascal
var mb: TfpgMenuBar; miFile, miEdit: TfpgMenuItem;
begin
  mb := TfpgMenuBar.Create(Self);
  mb.Align := alTop;

  miFile := mb.AddMenuItem('文件', nil);
  miFile.SubMenu.AddMenuItem('新建', @miFileNewClick);
  miFile.SubMenu.AddMenuItem('打开...', @miFileOpenClick);
  miFile.SubMenu.AddMenuItem('退出', @miFileQuitClick);

  miEdit := mb.AddMenuItem('编辑', nil);
  miEdit.SubMenu.AddMenuItem('复制', @miEditCopyClick);
  miEdit.SubMenu.AddMenuItem('粘贴', @miEditPasteClick);
end;
```

#### 3.7.5 TfpgPopupMenu

> 继承链：`TfpgPopupMenu` → `TfpgPopupWindow`

**组件介绍**：弹出菜单，可绑定到控件的 `PopupMenu` 属性或手动 `ShowAt`。

##### 方法

| 原型 | 功能 | 入参 | 返回值 |
|------|------|------|--------|
| `function AddMenuItem(const AMenuName: TfpgString; const hotkeydef: string; OnClickProc: TNotifyEvent): TfpgMenuItem;` | 添加菜单项 | 名称/快捷键/回调 | 新菜单项 |
| `procedure AddSeparator;` | 添加分隔线 | — | — |
| `procedure AddHeader(AHeaderName: TfpgString);` | 添加标题 | 标题 | — |
| `function MenuItemByName(const AMenuName: TfpgString): TfpgMenuItem;` | 按名称查找 | 名称 | 菜单项 |
| `function MenuItem(const AMenuPos: integer): TfpgMenuItem;` | 按位置获取 | 位置 | 菜单项 |
| `procedure Close; override;` | 关闭菜单 | — | — |
| `procedure ShowAt(...);` | 在指定位置显示 | — | — |

##### 示例

```pascal
var pm: TfpgPopupMenu;
begin
  pm := TfpgPopupMenu.Create(Self);
  pm.AddMenuItem('复制', 'Ctrl+C', @pmCopyClick);
  pm.AddMenuItem('粘贴', 'Ctrl+V', @pmPasteClick);
  pm.AddSeparator;
  pm.AddMenuItem('删除', 'Del', @pmDeleteClick);

  mem.PopupMenu := pm;           // 绑定到控件
  pm.ShowAt(Self, 100, 100);    // 或在指定位置弹出
end;
```

#### 3.7.6 TfpgMenuItem

> 源码位置：`gui/fpg_menu.pas`

**组件介绍**：菜单项，可独立存在或属于某个菜单/子菜单。

##### 属性

| 名称 | 类型 | 读写 | 说明 |
|------|------|------|------|
| `Text` | `TfpgString` | RW | 菜单文本 |
| `Hint` | `TfpgString` | RW | 提示 |
| `HotKeyDef` | `TfpgHotKeyDef` | RW | 快捷键定义 |
| `Checked` | `boolean` | RW | 勾选状态 |
| `Enabled` | `boolean` | RW | 启用 |
| `Visible` | `boolean` | RW | 可见 |
| `Separator` | `boolean` | RW | 分隔线 |
| `Header` | `boolean` | RW | 标题 |
| `SubMenu` | `TfpgPopupMenu` | RW | 子菜单 |
| `OnClick` | `TNotifyEvent` | RW | 点击事件 |

##### 方法

| 原型 | 功能 |
|------|------|
| `procedure Click;` | 触发点击 |
| `function Selectable: boolean;` | 是否可选 |

#### 3.7.7 TfpgSystemTrayIcon

> 源码位置：`gui/fpg_trayicon.pas`
> 继承链：`TfpgSystemTrayIcon` → `TfpgWidget`

**组件介绍**：系统托盘图标，支持显示图标、提示、托盘消息、右键菜单。

##### 属性

| 名称 | 类型 | 读写 | 说明 |
|------|------|------|------|
| `ImageName` | `TfpgString` | RW | 图标图像名 |
| `PopupMenu` | `TfpgPopupMenu` | RW | 右键菜单 |
| `Hint` | `TfpgString` | RW | 提示文本 |

##### 方法

| 原型 | 功能 |
|------|------|
| `procedure Show;` | 显示托盘图标 |
| `procedure Hide;` | 隐藏托盘图标 |
| `procedure ShowMessage(ATitle, AMessage: string; AMessageIcon: TfpgMessageIconType; AMillisecondsTimeoutHint: integer);` | 显示托盘消息 |
| `function IsSystemTrayAvailable: boolean;` | 系统托盘是否可用 |
| `function SupportsMessages: boolean;` | 是否支持消息 |

`TfpgMessageIconType` 枚举：`mitNoIcon` / `mitInformation` / `mitWarning` / `mitCritical`。

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnClick` | `TNotifyEvent` | 点击 |
| `OnMessageClicked` | `TNotifyEvent` | 消息点击 |
| `OnPaint` | `TPaintEvent` | 绘制 |

##### 示例

```pascal
var tray: TfpgSystemTrayIcon;
begin
  tray := TfpgSystemTrayIcon.Create(Self);
  tray.ImageName := 'myapp_icon';
  tray.Hint := '我的应用';
  tray.PopupMenu := MyPopupMenu;
  tray.Show;
end;
```

### 3.8 图像绘图

#### 3.8.1 TfpgImage

> 源码位置：`corelib/fpg_main.pas`
> 继承链：`TfpgImage` → `TfpgImageImpl`

**组件介绍**：图像对象（非可视控件），承载位图数据，用于 `Canvas.DrawImage` 绘制或通过 `fpgImages` 全局管理。

##### 方法

| 原型 | 功能 | 说明 |
|------|------|------|
| `function CreateDisabledImage: TfpgImage;` | 创建禁用状态图像 | — |
| `function ImageFromSource: TfpgImage;` | 从源图像创建副本 | — |
| `function ImageFromRect(var ARect: TRect): TfpgImage; overload;` | 从矩形区域创建子图 | — |
| `function ImageFromRect(var ARect: TfpgRect): TfpgImage; overload;` | 从矩形区域创建子图 | — |
| `property ScanLine[Row: Integer]: Pointer;` | 直接访问像素行 | 用于像素级操作 |

> **说明:** `TfpgImage` 通常通过 `fpgImages.AddBMP`/`AddPNGFromResource` 或 `TfpgImageImpl.LoadFromFile` 加载。

##### 示例

```pascal
var img: TfpgImage;
begin
  img := fpgImages.GetImage('myimage');
  if Assigned(img) then
    Canvas.DrawImage(10, 10, img);
end;
```

#### 3.8.2 TfpgCanvas

> 源码位置：`corelib/fpg_main.pas`，基类 `TfpgCanvasBase` 在 `corelib/fpg_base.pas`
> 继承链：`TfpgCanvas` → `TfpgCanvasImpl`（如 `TfpgGDICanvas`/`TfpgCocoaCanvas`/`TfpgOHOSCanvas`）→ `TfpgCanvasBase`

**组件介绍**：画布对象（非控件），用于所有自绘操作。通过控件的 `Canvas` 属性获得，仅在 `HandlePaint` 或 `OnPaint` 中可用。

##### 属性

| 名称 | 类型 | 读写 | 说明 |
|------|------|------|------|
| `Color` | `TfpgColor` | RW | 当前画笔/填充色（等同 `SetColor`） |
| `TextColor` | `TfpgColor` | RW | 当前文本色（等同 `SetTextColor`） |
| `Font` | `TfpgFontResourceBase` | R | 当前字体对象 |
| `Pixels[X, Y]` | `TfpgColor` | RW | 像素读写 |
| `InterpolationFilter` | `TfpgCustomInterpolation` | RW | 图像缩放插值算法 |
| `LineStyle` | `TfpgLineStyle` | R | 当前线条样式 |
| `Widget` | `TfpgWidgetBase` | R | 所属控件 |

##### 方法（绘图核心）

| 原型 | 功能 | 入参 | 返回值 | 说明 |
|------|------|------|--------|------|
| `procedure SetColor(AColor: TfpgColor);` | 设置画笔/填充色 | 颜色 | — | — |
| `procedure SetTextColor(AColor: TfpgColor);` | 设置文本色 | 颜色 | — | — |
| `procedure SetLineStyle(AWidth: integer; AStyle: TfpgLineStyle);` | 设置线条样式 | 宽度/样式 | — | — |
| `procedure SetClipRect(const ARect: TfpgRect);` | 设置裁剪区域 | 矩形 | — | — |
| `function GetClipRect: TfpgRect;` | 获取裁剪区域 | — | 矩形 | — |
| `procedure AddClipRect(const ARect: TfpgRect);` | 增加裁剪区域 | 矩形 | — | 与现有区域求并 |
| `procedure ClearClipRect;` | 清除裁剪区域 | — | — | — |
| `procedure Clear(AColor: TfpgColor);` | 清空画布为指定色 | 颜色 | — | — |
| `procedure DrawRectangle(x, y, w, h: TfpgCoord); overload;` | 绘制矩形边框 | 坐标 | — | — |
| `procedure DrawRectangle(r: TfpgRect); overload;` | 绘制矩形边框 | 矩形 | — | — |
| `procedure FillRectangle(x, y, w, h: TfpgCoord); overload;` | 填充矩形 | 坐标 | — | — |
| `procedure FillRectangle(r: TfpgRect); overload;` | 填充矩形 | 矩形 | — | — |
| `procedure DrawLine(x1, y1, x2, y2: TfpgCoord);` | 绘制直线 | 起止点 | — | — |
| `procedure DrawLineClipped(var x1, y1, x2, y2: TfpgCoord; const AClipRect: TfpgRect);` | 裁剪绘制直线 | 起止点/裁剪 | — | — |
| `procedure DrawArc(x, y, w, h: TfpgCoord; a1, a2: double);` | 绘制弧线 | 外接矩形/起止角 | — | — |
| `procedure FillArc(x, y, w, h: TfpgCoord; a1, a2: double);` | 填充扇形 | 外接矩形/起止角 | — | — |
| `procedure FillTriangle(x1, y1, x2, y2, x3, y3: TfpgCoord);` | 填充三角形 | 三点坐标 | — | — |
| `procedure DrawPolygon(const Points: array of TPoint);` | 绘制多边形边框 | 点数组 | — | — |
| `procedure DrawPolyLine(const Points: array of TPoint);` | 绘制折线 | 点数组 | — | — |
| `procedure DrawImage(x, y: TfpgCoord; img: TfpgImageBase);` | 绘制图像 | 位置/图像 | — | — |
| `procedure DrawImagePart(x, y: TfpgCoord; img: TfpgImageBase; xi, yi, w, h: integer);` | 绘制图像部分 | 位置/源区域 | — | — |
| `procedure StretchDraw(x, y, w, h: TfpgCoord; ASource: TfpgImageBase);` | 拉伸绘制图像 | 目标矩形 | — | — |
| `procedure CopyRect(ADest_x, ADest_y: TfpgCoord; ASrcCanvas: TfpgCanvasBase; var ASrcRect: TfpgRect);` | 复制画布区域 | 目标/源 | — | — |
| `procedure DrawString(x, y: TfpgCoord; const txt: string);` | 绘制文本 | 位置/文本 | — | 不支持换行 |
| `function DrawText(x, y, w, h: TfpgCoord; const AText: TfpgString; AFlags: TfpgTextFlags = TextFlagsDflt; ALineSpace: integer = 2): integer; overload;` | 高级文本绘制 | 矩形/文本/标志 | 实际高度 | 支持换行/对齐 |
| `function DrawText(x, y: TfpgCoord; const AText: TfpgString; AFlags: TfpgTextFlags = TextFlagsDflt; ALineSpace: integer = 2): integer; overload;` | 高级文本绘制 | 位置/文本/标志 | 实际高度 | — |
| `function DrawText(r: TfpgRect; const AText: TfpgString; AFlags: TfpgTextFlags = TextFlagsDflt; ALineSpace: integer = 2): integer; overload;` | 高级文本绘制 | 矩形/文本/标志 | 实际高度 | — |
| `procedure GradientFill(ARect: TfpgRect; AStart, AStop: TfpgColor; ADirection: TGradientDirection);` | 渐变填充 | 矩形/起止色/方向 | — | — |
| `procedure XORFillRectangle(col: TfpgColor; x, y, w, h: TfpgCoord); overload;` | 异或填充矩形 | 颜色/坐标 | — | — |
| `procedure SetFont(AFont: TfpgFontResourceBase); overload;` | 设置当前字体 | 字体对象 | — | — |
| `procedure SetFontDefinition(AFontDef: TfpgFontDefinition);` | 按字体描述设置字体 | 字体描述 | — | 便捷方法 |
| `function GetLineWidth: integer;` | 获取线宽 | — | 线宽 | — |
| `function GetPixel(X, Y: integer): TfpgColor;` | 获取像素颜色 | 坐标 | 颜色 | — |
| `procedure SetPixel(X, Y: integer; const AValue: TfpgColor);` | 设置像素颜色 | 坐标/颜色 | — | — |
| `procedure BeginDraw; overload;` | 开始绘制 | — | — | 必须先调用 |
| `procedure BeginDraw(CanvasTarget: TfpgCanvasBase; XDelta, YDelta: Integer); overload;` | 开始绘制（带偏移） | 目标/偏移 | — | — |
| `procedure EndDraw; overload;` / `procedure EndDraw(x, y, w, h: TfpgCoord); overload;` / `procedure EndDraw(ARect: TfpgRect); overload;` | 结束绘制并刷新 | 可选区域 | — | — |
| `procedure FreeResources;` | 释放画布资源 | — | — | — |
| `function RestoreFromBuffer(const ARect: TfpgRect): Boolean;` | 从离屏缓冲恢复区域 | 矩形 | 是否成功 | — |
| `procedure GetWinRect(out r: TfpgRect);` | 获取窗口矩形 | — | — | — |

`TfpgTextFlags` 选项：`txtLeft` / `txtHCenter` / `txtRight` / `txtTop` / `txtVCenter` / `txtBottom` / `txtWrap` / `txtDisabled` / `txtAutoSize`。默认 `TextFlagsDflt = [txtLeft, txtTop]`。

##### 示例

```pascal
procedure TMyForm.FormPaint(Sender: TObject);
var r: TfpgRect;
begin
  // 绘制黑色矩形边框
  Canvas.SetColor(clBlack);
  r.SetRect(10, 10, 50, 50);
  Canvas.DrawRectangle(r);

  // 绘制蓝色填充矩形
  Canvas.SetColor(clBlue);
  r.Left := 70;
  Canvas.FillRectangle(r);

  // 绘制文本
  Canvas.SetTextColor(clBlack);
  Canvas.DrawString(10, 70, 'Hello fpGUI!');

  // 绘制对角线
  Canvas.SetColor(clRed);
  Canvas.DrawLine(10, 10, 60, 60);
end;

// 不同字体
var fnt: TfpgFontResourceBase; y: integer;
begin
  y := 60;
  Canvas.SetTextColor(clBlack);
  Canvas.DrawString(5, y, '默认字体文本');
  fnt := fpgApplication.FontManager.GetFont('Times-14:bold');
  Canvas.SetFont(fnt);
  y := y + Canvas.Font.GetHeight();
  Canvas.DrawString(5, y, 'Times 14号粗体文本');
end;
```

##### 避坑注意事项

> **避坑:**
> 1. **Canvas 仅在 HandlePaint/OnPaint 中有效**，在其他地方访问会得到空画布或异常。
> 2. **BeginDraw/EndDraw 配对**：`HandlePaint` 内部框架已自动调用 `BeginDraw`/`EndDraw`，自定义重写时若手动调用需注意嵌套。
> 3. **DrawString vs DrawText**：`DrawString` 简单、不换行；`DrawText` 支持换行、对齐、自动尺寸。

#### 3.8.3 TfpgPaintBox 替代方案

`TfpgPaintBox` 在 fpGUI 2.1.0 中**不存在**。需要自绘区域时，继承 `TfpgWidget` 并重写 `HandlePaint`：

```pascal
type
  TMyPaintBox = class(TfpgWidget)
  protected
    procedure HandlePaint; override;
  end;

procedure TMyPaintBox.HandlePaint;
begin
  inherited HandlePaint;
  Canvas.SetColor(clYellow);
  Canvas.FillRectangle(0, 0, Width, Height);
end;
```

或直接在窗体的 `OnPaint` 事件中绘制。

### 3.9 时间日期

#### 3.9.1 TfpgCalendar

> 源码位置：`gui/fpg_popupcalendar.pas`

**组件介绍**：月历控件，显示一个月份的日历网格，允许选择日期。属性包含 `Date`、`FirstDayOfWeek`、`ShowToday` 等。

##### 示例

```pascal
var cal: TfpgCalendar;
begin
  cal := TfpgCalendar.Create(Self);
  cal.Align := alClient;
  cal.Date := Now;
  // cal.OnDateSet := @calDateSet;
end;
```

#### 3.9.2 TfpgPopupCalendar

> 继承链：`TfpgPopupCalendar` → `TfpgPopupWindow`

**组件介绍**：弹出式日历选择器，通常与 `TfpgComboBox` 或 `TfpgFileNameEdit` 配合使用。

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnDateSet` | `TfpgOnDateSetEvent` | 日期选定 |

```pascal
TfpgOnDateSetEvent = procedure(Sender: TObject; const ADate: TDateTime) of object;
```

#### 3.9.3 TfpgDateTimePicker 替代方案

`TfpgDateTimePicker` 在 fpGUI 2.1.0 中**不存在**。使用 `TfpgPopupCalendar` 或 `TfpgEdit` + 弹出日历实现：

```pascal
var ed: TfpgEdit; cal: TfpgPopupCalendar;
begin
  ed := TfpgEdit.Create(Self);
  ed.Text := DateToStr(Now);
  // 在按钮点击事件中弹出 cal.ShowAt(...)
end;
```

### 3.10 拓展

#### 3.10.1 TfpgHintWindow

> 源码位置：`gui/fpg_hint.pas`
> 继承链：`TfpgHintWindow` → `TfpgForm`

**组件介绍**：提示窗口，鼠标悬停时显示提示文本。通常由 `fpgApplication` 自动创建并管理，无需手动实例化。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Text` | `TfpgString` | RW | — | 提示文本 |
| `Shadow` | `Integer` | RW | 0 | 阴影大小 |
| `Border` | `Integer` | RW | 1 | 边框大小 |
| `Margin` | `Integer` | RW | 3 | 内边距 |
| `ShadowColor` | `TfpgColor` | RW | `clGray` | 阴影颜色 |
| `Time` | `Integer` | RW | — | 显示时间 |
| `FontDesc` | `string` | RW | — | 字体描述 |

#### 3.10.2 TfpgAnimation / TfpgImgAnim

> 源码位置：`gui/fpg_animation.pas`
> 继承链：`TfpgImgAnim` → `TfpgBaseImgAnim` → `TfpgWidget`

**组件介绍**：帧动画控件，通过水平拼接的多帧图像实现循环播放。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `Align` | `TAlign` | RW | `alNone` | 对齐 |
| `Enabled` | `boolean` | RW | `True` | 启用 |
| `Interval` | `integer` | RW | 50 | 帧间隔（毫秒） |
| `ImageFileName` | `TfpgString` | RW | — | 图像文件名 |
| `IsTransparent` | `Boolean` | RW | `True` | 是否透明 |
| `FrameCount` | `integer` | RW | 4 | 总帧数 |
| `Position` | `integer` | RW | 0 | 当前帧（公开） |

##### 方法

| 原型 | 功能 |
|------|------|
| `procedure ImageFromByteArray(ABmp; ASize);` | 从字节数组加载图像 |
| `procedure SetImageFilename(AValue; AMaskSample);` | 带掩码设置图像 |

##### 示例

```pascal
var anim: TfpgImgAnim;
begin
  anim := TfpgImgAnim.Create(Self);
  anim.ImageFileName := 'myanimation.png';  // 多帧水平拼接图
  anim.FrameCount := 8;
  anim.Interval := 100;
end;
```

#### 3.10.3 TfpgLEDMatrix

> 源码位置：`gui/fpg_ledmatrix.pas`

**组件介绍**：LED 矩阵显示控件，可显示点阵文字/图形。属性包含 `LEDs`（点阵数据）、`LEDSize`、`LEDGap`、`OnColor`、`OffColor` 等。

##### 示例

```pascal
var led: TfpgLEDMatrix;
begin
  led := TfpgLEDMatrix.Create(Self);
  led.Align := alClient;
  // 配置 LED 矩阵列数后逐像素点亮
end;
```

#### 3.10.4 TfpgColorWheel

> 源码位置：`gui/fpg_colorwheel.pas`
> 继承链：`TfpgColorWheel` → `TfpgWidget`

**组件介绍**：色轮选择器，可拖动选择色相/饱和度，常与 `TfpgValueBar` 配合。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `BackgroundColor` | `TfpgColor` | RW | `clWindowBackground` | 背景色 |
| `ValueBar` | `TfpgValueBar` | RW | — | 关联的值条 |
| `MarginWidth` | `longint` | RW | 5 | 边距 |
| `CursorSize` | `longint` | RW | 5 | 光标尺寸 |
| `WhiteAreaPercent` | `longint` | RW | 10 | 白色区域百分比 |

##### 方法

| 原型 | 功能 |
|------|------|
| `procedure SetSelectedColor(NewColor: TfpgColor);` | 设置选中颜色 |

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TNotifyEvent` | 颜色改变 |

##### 子对象 TfpgValueBar

| 属性 | 类型 | 说明 |
|------|------|------|
| `Value` | `double` | 亮度值（0-1） |
| `SelectedColor` | `TfpgColor` | 选中颜色（只读） |
| `MarginWidth` | `longint` | 边距 |
| `CursorHeight` | `longint` | 光标高度 |

##### 示例

```pascal
var cw: TfpgColorWheel; vb: TfpgValueBar;
begin
  cw := TfpgColorWheel.Create(Self);
  cw.Align := alClient;
  vb := TfpgValueBar.Create(Self);
  vb.Align := alRight; vb.Width := 30;
  cw.ValueBar := vb;
  cw.OnChange := @cwColorChanged;
end;
```

#### 3.10.5 TfpgReadOnly

> 源码位置：`gui/fpg_readonly.pas`
> 继承链：`TfpgReadOnly` → `TComponent`

**组件介绍**：非可视组件，可批量设置表单上所有控件的只读状态。

##### 属性

| 名称 | 类型 | 读写 | 默认 | 说明 |
|------|------|------|------|------|
| `ReadOnly` | `boolean` | RW | `False` | 只读状态 |
| `Enabled` | `boolean` | RW | `False` | 是否激活批量控制 |
| `ProcessContainer` | `boolean` | RW | `False` | 是否处理容器控件 |

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnChange` | `TfpgOnChangeReadOnlyEvent` | 只读状态改变 |
| `OnProcess` | `TfpgOnProcessEvent` | 处理每个控件时触发 |
| `OnProcessFrm` | `TfpgOnProcessFrmEvent` | 处理每个表单时触发 |
| `OnGetParent` | `TfpgOnGetParentEvent` | 获取父表单 |

##### 示例

```pascal
var ro: TfpgReadOnly;
begin
  ro := TfpgReadOnly.Create(Self);
  ro.Enabled := True;
  ro.ReadOnly := True;  // 将表单上所有控件设为只读
end;
```

#### 3.10.6 TfpgFileNameEdit

> 源码位置：`gui/fpg_editbtn.pas`
> 继承链：`TfpgFileNameEdit` → `TfpgBaseEditButton` → `TfpgAbstractPanel`

**组件介绍**：文件名编辑器，输入框 + 按钮，点击按钮弹出文件对话框。

##### 属性

| 名称 | 类型 | 读写 | 说明 |
|------|------|------|------|
| `FileName` | `TfpgString` | RW | 文件路径 |
| `Filter` | `TfpgString` | RW | 文件过滤器 |
| `InitialDir` | `TfpgString` | RW | 初始目录 |
| `ReadOnly` | `Boolean` | RW | 只读 |
| `ExtraHint` | `TfpgString` | RW | 占位符提示 |

##### 事件

| 名称 | 类型 | 触发时机 |
|------|------|----------|
| `OnButtonClick` | `TNotifyEvent` | 按钮点击（默认打开文件对话框） |
| `OnChange` | `TNotifyEvent` | 文件名改变 |

##### 示例

```pascal
var fe: TfpgFileNameEdit;
begin
  fe := TfpgFileNameEdit.Create(Self);
  fe.Filter := '文本文件 (*.txt)|*.txt|所有文件 (*.*)|*.*';
  fe.InitialDir := '/home/user';
end;
```

#### 3.10.7 不存在的组件清单

| 组件名 | 状态 | 替代方案 |
|--------|------|---------|
| `TfpgPaintBox` | 不存在 | 继承 `TfpgWidget`，重写 `HandlePaint`，使用 `OnPaint` 事件 |
| `TfpgStatusBar` | 不存在 | 使用 `TfpgPanel` + `Align := alBottom` 实现 |
| `TfpgToolBar` | 不存在 | 使用 `TfpgPanel` + `TfpgButton`(设置 `Flat`, `AllowDown`, `GroupIndex`) 实现 |
| `TfpgDateTimePicker` | 不存在 | 使用 `TfpgPopupCalendar` 或 `TfpgEdit` + 弹出日历实现 |
| `TfpgSpeedButton`（独立类） | 不存在 | 用 `TfpgButton` 设 `Flat := True`、`ShowImage := True` |
| `TfpgMessageDialog`（独立类） | 不存在 | 用 `fpgMessageDlg` 函数或 `TfpgMessageBox` |
| `TfpgOpenDialog`/`TfpgSaveDialog`/`TfpgSelectFolderDialog`/`TfpgColorDialog`/`TfpgFontDialog`/`TfpgPromptDialog`（独立类） | 不存在 | 用统一 `TfpgFileDialog` + 模式标志，或对应的全局函数 `SelectFileDialog`/`SelectDirDialog`/`fpgSelectColorDialog`/`SelectFontDialog`/`fpgInputQuery`/`fpgIntegerQuery` |

---

## 模块4：组件属性详细说明（统一规范）

### 4.1 通用属性统一汇总

> 本节统一汇总所有控件共有的属性，避免在每节重复。源自 `TfpgWidget`（`corelib/fpg_widget.pas`）与 `TfpgWidgetBase`（`corelib/fpg_base.pas`）。

#### 4.1.1 位置与尺寸属性

| 属性 | 类型 | 读写 | 默认 | 适用控件 | 说明 |
|------|------|------|------|---------|------|
| `Left` | `TfpgCoord` | RW | 0 | 所有控件 | X 坐标（相对父客户区） |
| `Top` | `TfpgCoord` | RW | 0 | 所有控件 | Y 坐标 |
| `Width` | `TfpgCoord` | RW | 0 | 所有控件 | 宽度 |
| `Height` | `TfpgCoord` | RW | 0 | 所有控件 | 高度 |
| `MinWidth` | `TfpgCoord` | RW | 0 | `TfpgForm` 等顶层 | 最小宽度 |
| `MinHeight` | `TfpgCoord` | RW | 0 | `TfpgForm` 等顶层 | 最小高度 |
| `MaxWidth` | `TfpgCoord` | RW | 0 | `TfpgForm` 等顶层 | 最大宽度 |
| `MaxHeight` | `TfpgCoord` | RW | 0 | `TfpgForm` 等顶层 | 最大高度 |

**示例**：

```pascal
// 手动定位
btn.Left := 10;
btn.Top := 10;
btn.Width := 100;
btn.Height := 30;

// 最小/最大尺寸限制（窗口）
frm.MinWidth := 400;
frm.MaxHeight := 600;
```

#### 4.1.2 对齐与锚点属性

| 属性 | 类型 | 读写 | 默认 | 适用控件 | 说明 |
|------|------|------|------|---------|------|
| `Align` | `TAlign` | RW | `alNone` | 所有控件 | 对齐方式 |
| `Anchors` | `TAnchors` | RW | `[anLeft, anTop]` | 所有控件 | 缩放锚点 |

**Align 值**：`alNone` / `alTop` / `alBottom` / `alLeft` / `alRight` / `alClient`。

**Anchors 值**：`anLeft` / `anRight` / `anTop` / `anBottom` 集合。

**示例**：

```pascal
// 三栏布局
mnuBar.Align := alTop;     mnuBar.Height := 24;
stbArea.Align := alBottom; stbArea.Height := 20;
pnlLeft.Align := alLeft;   pnlLeft.Width := 150;
spl.Align := alLeft;       spl.Width := 4;
pnlMain.Align := alClient;

// 锚点：跟随窗口缩放
btn.Anchors := [anRight, anBottom];  // 固定右下角
ed.Anchors := [anLeft, anTop, anRight];  // 左右拉伸
```

#### 4.1.3 外观属性

| 属性 | 类型 | 读写 | 默认 | 适用控件 | 说明 |
|------|------|------|------|---------|------|
| `BackgroundColor` | `TfpgColor` | RW | `clWindowBackground` | 所有控件 | 背景色 |
| `TextColor` | `TfpgColor` | RW | `clText1` | 所有控件 | 文本色 |
| `FontDesc` | `string` | RW | — | 所有控件 | 字体描述字符串 |
| `Enabled` | `boolean` | RW | `True` | 所有控件 | 是否启用 |
| `Visible` | `boolean` | RW | `True` | 所有控件 | 是否可见 |

**字体描述格式**：`字体名-字号:属性1=true:属性2=true`

示例：`'Arial-8:antialias=true'`、`'Liberation Sans-10:bold:italic:antialias=true'`、`'Courier New-10'`。

#### 4.1.4 焦点与 Tab 顺序属性

| 属性 | 类型 | 读写 | 默认 | 适用控件 | 说明 |
|------|------|------|------|---------|------|
| `TabOrder` | `integer` | RW | 0 | 可聚焦控件 | Tab 键顺序 |
| `Focusable` | `boolean` | RW | `False` | 所有控件 | 是否可获焦点（子类可设为 True） |
| `Focused` | `boolean` | RW | `False` | 所有控件 | 是否拥有焦点 |

> **说明:** `Focusable` 默认 `False`；按钮/编辑框等交互控件在子类中默认 `True`。

#### 4.1.5 提示属性

| 属性 | 类型 | 读写 | 默认 | 适用控件 | 说明 |
|------|------|------|------|---------|------|
| `Hint` | `TfpgString` | RW | — | 所有控件 | 提示文本 |
| `ShowHint` | `boolean` | RW | — | 所有控件 | 是否显示提示 |
| `ParentShowHint` | `boolean` | RW | `True` | 所有控件 | 是否继承父控件 ShowHint |

**示例**：

```pascal
btn.Hint := '点击退出';
btn.ShowHint := True;
```

#### 4.1.6 容器与父子关系属性

| 属性 | 类型 | 读写 | 默认 | 适用控件 | 说明 |
|------|------|------|------|---------|------|
| `Parent` | `TfpgWidget` | RW | — | 所有控件 | 父控件 |
| `AcceptDrops` | `boolean` | RW | `False` | 所有控件 | 是否接受拖放 |
| `DropHandler` | `TfpgDropHandler` | RW | — | 所有控件 | 拖放处理器 |
| `PopupMenu` | `TfpgPopupMenu` | RW | — | 编辑框/Memo/树 等 | 右键菜单 |

#### 4.1.7 布局管理属性

| 属性 | 类型 | 读写 | 默认 | 适用控件 | 说明 |
|------|------|------|------|---------|------|
| `LayoutManager` | `ILayoutManager` | RW | nil | 容器控件 | 布局管理器（如 `TfpgMigLayoutManager`） |
| `IgnoreDblClicks` | `Boolean` | RW | `False` | 所有控件 | 是否忽略双击 |

#### 4.1.8 名称与标识属性

| 属性 | 类型 | 读写 | 默认 | 适用控件 | 说明 |
|------|------|------|------|---------|------|
| `Name` | `TComponentName` | RW | — | 所有 `TComponent` | 组件名称（设计期/引用） |
| `Tag` | `LongInt` | RW | 0 | 所有 `TComponent` | 用户标识值 |
| `TagPointer` | `Pointer` | RW | nil | `TfpgComponent` | 用户指针数据 |

> **说明:** `Name`/`Tag` 来自 FCL `TComponent`；`TagPointer` 来自 fpGUI `TfpgComponent`（基类），用于挂载任意指针数据。

#### 4.1.9 高级只读属性

| 属性 | 类型 | 读写 | 说明 |
|------|------|------|------|
| `Canvas` | `TfpgCanvas` | R | 绘图画布（仅绘制时有效） |
| `Window` | `TfpgNativeWindow` | R | 原生窗口对象 |
| `ActiveWidget` | `TfpgWidget` | RW | 活动子控件 |
| `IsContainer` | `Boolean` | R | 是否为容器 |
| `FormDesigner` | `TObject` | RW | 窗体设计器 |

### 4.2 属性数据类型系统

| Pascal 类型 | fpGUI 别名 | 用途 | 取值范围/示例 |
|------------|-----------|------|--------------|
| `integer` | `TfpgCoord` | 坐标/尺寸 | 任意整数 |
| `longword` | `TfpgColor` | 颜色（AARRGGBB） | `$FF000000`（黑） |
| `AnsiString` | `TfpgString` | 字符串 | UTF-8 文本 |
| `boolean` | — | 开关 | `True`/`False` |
| `Single` | — | 浮点（如透明度） | `0.0`~`1.0` |
| `TAlign` | — | 对齐方式 | `alNone`/`alTop`/... |
| `TAnchors` | — | 锚点集合 | `[anLeft, anTop]` |
| `TLayout` | — | 垂直布局 | `tlTop`/`tlCenter`/`tlBottom` |
| `TAlignment` | — | 水平对齐（来自 FCL） | `taLeftJustify`/... |
| `TfpgWindowState` | — | 窗口状态 | `wsNormal`/`wsMinimized`/`wsMaximized` |
| `TfpgModalResult` | — | 模态结果 | `mrNone`/`mrOK`/... |
| `TfpgImageList` | — | 图像列表 | — |
| `TfpgPopupMenu` | — | 弹出菜单 | — |
| `ILayoutManager` | — | 布局管理器接口 | `TfpgMigLayoutManager` |

### 4.3 通用属性命名与读写模式

**命名约定**：

- 布尔属性以 `Is`/`Can`/`Show`/`Allow`/`Ignore`/`Parent` 前缀：`IsContainer`、`ShowHint`、`AllowDown`、`IgnoreDblClicks`、`ParentShowHint`。
- 颜色属性以 `Color` 后缀：`BackgroundColor`、`TextColor`、`HotTrackColor`。
- 字体描述统一使用 `FontDesc: string`（不是 `Font` 对象），便于序列化。
- 集合属性使用复数：`Anchors`、`Options`、`WindowAttributes`。

**读写模式**：

| 模式 | 标识 | 说明 |
|------|------|------|
| 读写 | `read Fxxx write SetXxx` | 公开可读可写 |
| 只读 | `read Fxxx` | 仅可读（如 `Canvas`、`Window`、`PageCount`） |
| 存储控制 | `stored IsXxxStored` | 由存储函数决定是否写入流 |
| 默认值 | `default X` | 默认值，未改变时不写入流 |
| 虚拟写 | `write SetXxx; virtual;` | 子类可重写以拦截赋值 |

**典型 published 声明**：

```pascal
property Align: TAlign read FAlign write SetAlign default alNone;
property BackgroundColor: TfpgColor read FBackgroundColor write SetBackgroundColor default clWindowBackground;
property OnClick: TNotifyEvent read FOnClick write FOnClick;
property Canvas: TfpgCanvas read GetCanvas;  // 只读
```

### 4.4 通用属性跨组件参照表

> ✓ = 该组件支持此属性；— = 不支持或无意义。基于 `TfpgWidget` 基类与各组件 published 段汇总。

| 属性 | TfpgForm | TfpgButton | TfpgLabel | TfpgEdit | TfpgMemo | TfpgCheckBox | TfpgComboBox | TfpgListBox | TfpgPanel | TfpgPageControl | TfpgTreeView | TfpgStringGrid |
|------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Left/Top/Width/Height | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Align | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Anchors | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| BackgroundColor | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| TextColor | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — | — |
| FontDesc | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Enabled | ✓ | ✓ | — | ✓ | ✓ | — | ✓ | ✓ | — | ✓ | — | — |
| Visible | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Hint/ShowHint/ParentShowHint | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| TabOrder | ✓ | ✓ | — | ✓ | ✓ | — | ✓ | — | — | — | — | — |
| Focusable/Focused | ✓ | ✓ | — | ✓ | ✓ | — | ✓ | — | — | — | — | — |
| PopupMenu | — | — | — | — | ✓ | — | — | — | — | — | ✓ | — |
| AcceptDrops/DropHandler | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| LayoutManager | ✓ | — | — | — | — | — | — | — | ✓ | ✓ | — | — |
| IgnoreDblClicks | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| WindowTitle/WindowPosition/WindowState | ✓ | — | — | — | — | — | — | — | — | — | — | — |

> **说明:** 标记 — 的属性要么不存在于该组件 published 段，要么语义不适用。颜色属性 `—` 的位置通常继承基类默认值无需在子类重设。

---

## 模块5：方法与函数详细说明（核心重点）

> 本章为横切参考。统一列出全局函数、各组件通用方法、对话框方法、画布方法、工厂函数。每条按 原型 | 功能 | 入参明细 | 返回值 | 调用限制 | 代码示例 | 报错/禁忌/最佳实践 描述。

### 5.1 组件生命周期方法

| 原型 | 功能 | 入参明细 | 返回值 | 调用限制 | 说明 |
|------|------|---------|--------|---------|------|
| `constructor Create(AOwner: TComponent); override;` | 构造控件 | 所有者 | 新实例 | 不能在 `Initialize` 前调用 | `AOwner=nil` 时手动 `Free` |
| `destructor Destroy; override;` | 析构控件 | — | — | 不要直接调用，用 `Free` | — |
| `procedure AfterConstruction; override;` | 构造完成钩子 | — | — | 由 RTL 调用 | `TfpgForm` 在此触发 `AfterCreate` |
| `procedure AfterCreate; virtual;` | 表单构造后初始化 | — | — | 仅 `TfpgForm` 重写 | 在此初始化子控件 |
| `procedure Show;` | 非模态显示窗口 | — | — | 仅 `TfpgForm`/`TfpgWindow` | 不阻塞 |
| `procedure Hide;` | 隐藏窗口 | — | — | 仅窗口类 | — |
| `function ShowModal: TfpgModalResult;` | 模态显示窗口 | — | 模态结果 | 仅 `TfpgForm` | 阻塞直到关闭 |
| `procedure Close;` | 关闭窗口 | — | — | 仅 `TfpgForm` | 触发 OnCloseQuery/OnClose |
| `function CloseQuery: boolean; virtual;` | 关闭查询 | — | 是否允许关闭 | 可重写 | 返回 False 阻止关闭 |

**示例**：

```pascal
// 标准 5 步生命周期
fpgApplication.Initialize;
frm := TfpgForm.Create(nil);
try
  frm.Show;
  fpgApplication.Run;
finally
  frm.Free;
end;

// 模态对话框
dlg := TMyDialog.Create(nil);
try
  Result := dlg.ShowModal;
finally
  dlg.Free;
end;
```

> **禁忌:** 不要在 `Create` 构造函数里访问子控件（窗体尚未完成 `AfterCreate`）；不要在 `Destroy` 里访问其他控件（可能已释放）。

### 5.2 刷新重绘方法

| 原型 | 功能 | 入参明细 | 返回值 | 调用限制 | 说明 |
|------|------|---------|--------|---------|------|
| `procedure Invalidate;` | 失效化（请求重绘） | — | — | 不要在 `HandlePaint` 内调用 | 异步，投递到消息队列 |
| `procedure InvalidateRect(ARect: TfpgRect);` | 失效化指定区域 | 矩形 | — | 同上 | 性能优于全控件 `Invalidate` |
| `procedure RePaint; virtual;` | 立即重绘 | — | — | 谨慎使用 | 同步，立即重绘 |
| `procedure Realign;` | 重新对齐子控件 | — | — | 容器类 | 重新执行 Align 布局 |

**示例**：

```pascal
// 修改数据后请求重绘
mem.Lines.Add('新行');
mem.Invalidate;  // 异步重绘

// 仅刷新指定区域（高效）
r.SetRect(10, 10, 100, 50);
Self.InvalidateRect(r);

// 不要这样写（无限循环）
procedure TMyWidget.HandlePaint;
begin
  inherited HandlePaint;
  Invalidate;  // 错误！会无限重绘
end;
```

> **最佳实践:** 大数据批量修改用 `BeginUpdate`/`EndUpdate`；局部修改用 `InvalidateRect` 而非 `Invalidate`。

### 5.3 焦点方法

| 原型 | 功能 | 入参明细 | 返回值 | 调用限制 | 说明 |
|------|------|---------|--------|---------|------|
| `procedure SetFocus;` | 设置焦点 | — | — | 控件必须 `Focusable=True` 且可见 | — |
| `procedure KillFocus;` | 取消焦点 | — | — | — | — |
| `function FindKeyboardFocus: TfpgWidget;` | 查找当前焦点控件 | — | 焦点控件或 nil | 全局函数 | 从 `FocusRootWidget` 向下遍历 `ActiveWidget` |

**示例**：

```pascal
ed.SetFocus;  // 让编辑框获得焦点

var focused: TfpgWidget;
focused := FindKeyboardFocus;
if focused <> nil then
  DebugLn('当前焦点: ', focused.Name);
```

> **禁忌:** 在控件未显示或 `Focusable=False` 时调用 `SetFocus` 会被忽略或抛异常。

### 5.4 位置尺寸方法

| 原型 | 功能 | 入参明细 | 返回值 | 说明 |
|------|------|---------|--------|------|
| `procedure MoveAndResizeBy(const dx, dy, dw, dh: TfpgCoord);` | 偏移位置和尺寸 | dx/dy/dw/dh | — | 同时移动+缩放 |
| `procedure SetLayoutConstraint(AConstraint: TfpgLayoutConstraint);` | 设置布局约束 | 布局约束 | — | 用于 MigLayout |
| `procedure ScaleDPI(AFromDPI: integer = 0);` | DPI 缩放 | 源 DPI | — | 缩放所有子控件 |
| `function GetClientRect: TfpgRect;` | 获取客户区矩形 | — | 矩形 | 用于绘制 |
| `procedure DoPreferredSizeChanged; virtual;` | 首选尺寸改变 | — | — | 通知布局管理器 |

**示例**：

```pascal
// 偏移控件
btn.MoveAndResizeBy(10, 0, 0, 0);  // 右移 10 像素

// DPI 缩放
procedure TMyForm.AfterCreate;
begin
  inherited AfterCreate;
  ScaleDPI(96);  // 假设设计时 96 DPI，缩放到当前屏幕
end;
```

### 5.5 数据操作方法（剪贴板 / 列表 / 文本）

#### 5.5.1 剪贴板

| 原型 | 功能 | 入参明细 | 返回值 | 适用组件 |
|------|------|---------|--------|---------|
| `procedure CopyToClipboard;` | 复制到剪贴板 | — | — | `TfpgEdit`/`TfpgMemo` |
| `procedure CutToClipboard;` | 剪切到剪贴板 | — | — | `TfpgEdit`/`TfpgMemo` |
| `procedure PasteFromClipboard;` | 从剪贴板粘贴 | — | — | `TfpgEdit`/`TfpgMemo` |

**全局剪贴板对象**：

```pascal
function fpgClipboard: TfpgClipboard;
// 用法
fpgClipboard.Text := '要复制的文本';
S := fpgClipboard.Text;
```

#### 5.5.2 列表操作

> 适用 `TfpgComboBox.Items`、`TfpgListBox.Items`、`TfpgListView.Items` 等 `TStringList` 派生对象。

| 原型 | 功能 | 入参明细 | 返回值 | 说明 |
|------|------|---------|--------|------|
| `function Add(const S: string): Integer;` | 追加项 | 文本 | 新索引 | — |
| `function AddObject(const S: string; AObject: TObject): Integer;` | 追加项 + 对象 | 文本/对象 | 新索引 | — |
| `procedure Insert(Index: Integer; const S: string);` | 插入项 | 索引/文本 | — | — |
| `procedure Delete(Index: Integer);` | 删除项 | 索引 | — | — |
| `procedure Clear;` | 清空所有项 | — | — | — |
| `function Count: Integer;` | 项数 | — | 数量 | — |
| `property Items[Index: Integer]: string;` | 按索引访问 | 索引 | 文本 | 默认属性 |
| `property Objects[Index: Integer]: TObject;` | 按索引访问对象 | 索引 | 对象 | — |
| `function IndexOf(const S: string): Integer;` | 查找项 | 文本 | 索引（-1 未找到） | — |

**示例**：

```pascal
cb.Items.Add('选项一');
cb.Items.Add('选项二');
cb.FocusItem := 0;

for i := 0 to cb.Items.Count - 1 do
  DebugLn(cb.Items[i]);

idx := cb.Items.IndexOf('选项二');
if idx >= 0 then
  cb.Items.Delete(idx);
```

#### 5.5.3 文本操作

> 适用 `TfpgEdit`/`TfpgMemo`。

| 原型 | 功能 | 入参明细 | 返回值 | 说明 |
|------|------|---------|--------|------|
| `procedure SelectAll;` | 全选文本 | — | — | `TfpgEdit` |
| `procedure Clear;` | 清空文本 | — | — | `TfpgEdit`/`TfpgMemo` |
| `procedure ClearSelection;` | 清除选中文本 | — | — | `TfpgEdit` |
| `procedure InsertAtCursorPos(AText: string);` | 在光标处插入 | 文本 | — | `TfpgEdit` |
| `function SelectionText: string;` | 获取选中文本 | — | 选中字符串 | `TfpgEdit`/`TfpgMemo` |
| `procedure BeginUpdate;` | 开始批量更新 | — | — | `TfpgMemo`/`TfpgListBox` |
| `procedure EndUpdate;` | 结束批量更新 | — | — | 必须与 `BeginUpdate` 配对 |

**示例**：

```pascal
ed.SelectAll;
ed.InsertAtCursorPos('插入文本');
ShowMessage(ed.SelectionText);

mem.BeginUpdate;
try
  for i := 1 to 1000 do
    mem.Lines.Add('行 ' + IntToStr(i));
finally
  mem.EndUpdate;
end;
```

### 5.6 对话框方法与函数

> 源码位置：`gui/fpg_dialogs.pas`

#### 5.6.1 消息对话框

| 原型 | 功能 | 入参明细 | 返回值 | 说明 |
|------|------|---------|--------|------|
| `procedure ShowMessage(AMessage, ATitle: string; ACentreText: Boolean = False); overload;` | 显示消息框 | 文本/标题/居中 | — | — |
| `procedure ShowMessage(AMessage: string; ACentreText: Boolean = False); overload;` | 显示消息框 | 文本/居中 | — | 默认标题 |
| `function fpgMessageDlg(const AMsg: TfpgString; AType: TfpgMsgDlgType; AButtons: TfpgMsgDlgButtons): TfpgModalResult; overload;` | 消息对话框 | 文本/类型/按钮集 | 模态结果 | — |
| `function fpgMessageDlg(const ACaption, AMsg: TfpgString; AType: TfpgMsgDlgType; AButtons: TfpgMsgDlgButtons): TfpgModalResult; overload;` | 消息对话框（带标题） | 标题/文本/类型/按钮集 | 模态结果 | — |

> **说明:** 框架未提供 `ShowMessageFmt` 函数；使用 `ShowMessage(Format('处理 %d 条', [n]))` 实现格式化输出。`MessageDlg` 也不是单独函数，使用 `fpgMessageDlg` 替代。

**示例**：

```pascal
ShowMessage('操作完成！');
ShowMessage(Format('共处理 %d 条记录', [Count]));
if fpgMessageDlg('确认', '是否删除？', mtConfirmation, [mbYes, mbNo]) = mrYes then
  DeleteItem;
```

#### 5.6.2 输入对话框

| 原型 | 功能 | 入参明细 | 返回值 | 说明 |
|------|------|---------|--------|------|
| `function fpgInputQuery(const ACaption, APrompt: TfpgString; var Value: TfpgString): Boolean;` | 字符串输入框 | 标题/提示/初始值 | 是否确认 | Value 同时作为入参出参 |
| `function fpgIntegerQuery(const ACaption, APrompt: TfpgString; var Value: Integer; const MaxValue: Integer; const MinValue: Integer = 0): Boolean;` | 整数输入框 | 标题/提示/值/最大/最小 | 是否确认 | 自动范围校验 |

**示例**：

```pascal
var s: TfpgString;
begin
  s := '默认';
  if fpgInputQuery('输入', '请输入姓名：', s) then
    UserName := s;
end;

var age: Integer;
begin
  age := 18;
  if fpgIntegerQuery('年龄', '请输入年龄：', age, 120, 0) then
    SaveAge(age);
end;
```

#### 5.6.3 文件/字体/颜色对话框函数

| 原型 | 功能 | 入参明细 | 返回值 | 说明 |
|------|------|---------|--------|------|
| `function SelectFileDialog(const ADialogType: boolean = sfdOpen; const AFilter: TfpgString = ''; const AInitialDir: TfpgString = ''): TfpgString;` | 文件选择对话框 | 模式/过滤器/初始目录 | 文件名（空字符串=取消） | `sfdOpen`=打开，`sfdSave`=保存 |
| `function SelectDirDialog(const AStartDir: TfpgString = ''): TfpgString;` | 目录选择对话框 | 起始目录 | 目录（空字符串=取消） | — |
| `function SelectFontDialog(var FontDesc: string): boolean;` | 字体选择对话框 | 字体描述（入出） | 是否确认 | — |
| `function fpgSelectColorDialog(APresetColor: TfpgColor = clBlack): TfpgColor;` | 颜色选择对话框 | 预设颜色 | 选中颜色（`clDefault`=取消） | — |
| `function fpgShowCharMap: TfpgString;` | 字符映射表 | — | 选中字符 | — |

> **说明:** `ConfirmDlg` 不是 fpGUI 提供的独立函数；用 `fpgMessageDlg(..., mtConfirmation, [mbYes, mbNo])` 实现确认对话框。

**示例**：

```pascal
var fn: TfpgString;
begin
  fn := SelectFileDialog(sfdOpen, '文本文件 (*.txt)|*.txt|所有文件 (*.*)|*.*', '/home/user');
  if fn <> '' then
    LoadFile(fn);
end;

var dir: TfpgString;
begin
  dir := SelectDirDialog('/home/user');
  if dir <> '' then
    LoadFilesFrom(dir);
end;

var desc: string;
begin
  desc := mem.FontDesc;
  if SelectFontDialog(desc) then
    mem.FontDesc := desc;
end;

var c: TfpgColor;
begin
  c := fpgSelectColorDialog(clRed);
  if c <> clDefault then
    pnl.BackgroundColor := c;
end;
```

#### 5.6.4 `TfpgFileDialog` 组件方法

| 原型 | 功能 | 入参 | 返回值 | 说明 |
|------|------|------|--------|------|
| `function RunOpenFile: boolean;` | 执行打开模式 | — | 是否成功 | 内部调用 |
| `function RunSaveFile: boolean;` | 执行保存模式 | — | 是否成功 | 内部调用 |
| `function ShowModal: TfpgModalResult;` | 模态显示 | — | 模态结果 | 通常用 `mrOK` 判定 |

### 5.7 文件操作方法

| 原型 | 功能 | 入参 | 返回值 | 说明 |
|------|------|------|--------|------|
| `function Execute: boolean;` | 执行对话框 | — | 是否确认 | `TfpgFileDialog` 等对话框 |
| `TfpgImage.LoadFromFile` | 从文件加载图像 | 文件路径 | — | 通过 `TfpgImageImpl` 实现 |
| `TfpgImages.AddBMP(imgid, bmpdata, bmpsize)` | 从 BMP 数据添加 | ID/数据/大小 | `TfpgImage` | — |
| `TfpgImages.AddMaskedBMP(imgid, data, size, mcx, mcy)` | 添加带掩码 BMP | ID/数据/大小/掩码坐标 | `TfpgImage` | — |
| `TfpgImages.AddPNGFromResource(imgid, inst, resname)` | 从资源添加 PNG | ID/实例/资源名 | `TfpgImage` | — |
| `TfpgImages.AddBMPFromResource(imgid, inst, resname)` | 从资源添加 BMP | ID/实例/资源名 | `TfpgImage` | — |
| `TfpgImages.GetImage(imgid)` | 按 ID 获取图像 | ID | `TfpgImage` | nil=未找到 |
| `TfpgImages.DeleteImage(imgid, freeimg)` | 删除图像 | ID/是否释放 | 是否成功 | — |
| `TfpgImages.ListImages(sl)` | 列出所有图像 ID | 字符串列表 | — | — |

**示例**：

```pascal
var dlg: TfpgFileDialog;
begin
  dlg := TfpgFileDialog.Create(nil);
  try
    dlg.Filter := '文本文件 (*.txt)|*.txt|所有文件 (*.*)|*.*';
    dlg.InitialDir := '/home/user';
    if dlg.ShowModal = mrOK then
      LoadFile(dlg.FileName);
  finally
    dlg.Free;
  end;
end;

// 加载图像到全局管理器
fpgImages.AddPNGFromResource('myicon', HInstance, 'MYICON');
var img: TfpgImage := fpgImages.GetImage('myicon');
```

### 5.8 绘图方法（TfpgCanvas）

> 完整签名详见 [§3.8.2](#382-tfpgcanvas)。下表为常用方法速查：

| 原型 | 功能 | 入参 | 返回值 | 报错/禁忌 |
|------|------|------|--------|----------|
| `procedure SetColor(AColor: TfpgColor);` | 设置画笔/填充色 | 颜色 | — | — |
| `procedure SetTextColor(AColor: TfpgColor);` | 设置文本色 | 颜色 | — | — |
| `procedure SetLineStyle(AWidth: integer; AStyle: TfpgLineStyle);` | 设置线条样式 | 宽度/样式 | — | — |
| `procedure SetClipRect(const ARect: TfpgRect);` | 设置裁剪区域 | 矩形 | — | — |
| `procedure Clear(AColor: TfpgColor);` | 清空画布 | 颜色 | — | 在 `HandlePaint` 开头调用 |
| `procedure DrawRectangle(r: TfpgRect);` | 绘制矩形边框 | 矩形 | — | 仅边框 |
| `procedure FillRectangle(r: TfpgRect);` | 填充矩形 | 矩形 | — | 实心 |
| `procedure DrawLine(x1, y1, x2, y2: TfpgCoord);` | 绘制直线 | 起止点 | — | — |
| `procedure DrawArc(x, y, w, h; a1, a2: double);` | 绘制弧线 | 外接矩形/起止角 | — | 角度单位为度 |
| `procedure FillArc(x, y, w, h; a1, a2: double);` | 填充扇形 | 外接矩形/起止角 | — | — |
| `procedure FillTriangle(x1, y1, x2, y2, x3, y3);` | 填充三角形 | 三点 | — | — |
| `procedure DrawPolygon(const Points: array of TPoint);` | 绘制多边形 | 点数组 | — | — |
| `procedure DrawImage(x, y: TfpgCoord; img: TfpgImageBase);` | 绘制图像 | 位置/图像 | — | 图像必须已加载 |
| `procedure StretchDraw(x, y, w, h; ASource);` | 拉伸绘制图像 | 目标矩形/源 | — | — |
| `procedure DrawString(x, y: TfpgCoord; const txt: string);` | 绘制文本 | 位置/文本 | — | 不换行 |
| `function DrawText(r: TfpgRect; const AText; AFlags; ALineSpace): integer;` | 高级文本绘制 | 矩形/文本/标志 | 实际高度 | 支持换行对齐 |
| `procedure GradientFill(ARect; AStart, AStop; ADirection);` | 渐变填充 | 矩形/起止色/方向 | — | — |
| `function GetPixel(X, Y: integer): TfpgColor;` | 获取像素 | 坐标 | 颜色 | 性能低，慎用 |
| `procedure SetPixel(X, Y: integer; const AValue: TfpgColor);` | 设置像素 | 坐标/颜色 | — | 性能低，慎用 |
| `procedure BeginDraw;` | 开始绘制 | — | — | 必须先调用 |
| `procedure EndDraw;` | 结束绘制并刷新 | — | — | 必须配对 |
| `procedure SetFont(AFont: TfpgFontResourceBase);` | 设置字体 | 字体对象 | — | — |
| `procedure SetFontDefinition(AFontDef);` | 按描述设置字体 | 字体描述 | — | 便捷方法 |

**示例**：

```pascal
procedure TMyForm.FormPaint(Sender: TObject);
var r: TfpgRect;
begin
  Canvas.BeginDraw;
  try
    Canvas.Clear(clWindowBackground);

    Canvas.SetColor(clRed);
    r.SetRect(10, 10, 100, 50);
    Canvas.FillRectangle(r);

    Canvas.SetTextColor(clBlack);
    Canvas.DrawString(10, 70, 'Hello fpGUI!');

    Canvas.SetColor(clBlue);
    Canvas.DrawLine(10, 10, 60, 60);

    // 渐变
    Canvas.GradientFill(r, clRed, clBlue, gdHorizontal);
  finally
    Canvas.EndDraw;
  end;
end;
```

> **禁忌:** 不要在 `HandlePaint` 内调用 `Invalidate`；不要在 `OnPaint` 之外访问 `Canvas`。

### 5.9 全局工具函数

> 源码位置：`corelib/fpg_main.pas`

#### 5.9.1 全局对象访问

| 原型 | 功能 | 入参 | 返回值 | 说明 |
|------|------|------|--------|------|
| `function fpgApplication: TfpgApplication;` | 全局应用程序对象 | — | `TfpgApplication` | 单例 |
| `function fpgClipboard: TfpgClipboard;` | 全局剪贴板对象 | — | `TfpgClipboard` | 单例 |
| `var fpgStyle: TfpgStyle;` | 全局样式对象 | — | — | 当前样式 |
| `var fpgImages: TfpgImages;` | 全局图像管理器 | — | — | 单例 |
| `var FocusRootWidget: TfpgWidget;` | 焦点根控件 | — | — | — |

#### 5.9.2 颜色函数

| 原型 | 功能 | 入参 | 返回值 | 说明 |
|------|------|------|--------|------|
| `function fpgColorToRGB(col: TfpgColor): TfpgColor;` | 命名颜色解析为 RGB | 颜色 | RGB 颜色 | — |
| `function fpgGetNamedColor(col: TfpgColor): TfpgColor;` | 获取命名颜色 RGB | 颜色 | RGB | — |
| `procedure fpgSetNamedColor(colorid, rgbvalue: longword);` | 设置命名颜色 RGB | ID/RGB | — | — |
| `function fpgIsNamedColor(col: TfpgColor): boolean;` | 是否为命名颜色 | 颜色 | 布尔 | — |

> **说明:** 框架未提供 `RGBToFpgColor` 反向函数；用 `TfpgColor($FFRRGGBB)` 直接构造，如 `TfpgColor($FFFF8800)` 表示橙色。

#### 5.9.3 矩形/点辅助函数（已 deprecated，优先用对象方法）

| 原型 | 功能 | 替代方法 |
|------|------|---------|
| `function fpgPoint(AX, AY: integer): TfpgPoint;` | 构造点 | `P.SetPoint(AX, AY)` |
| `function fpgRect(ALeft, ATop, AWidth, AHeight: integer): TfpgRect;` | 构造矩形 | `R.SetRect(...)` |
| `function fpgSize(AWidth, AHeight: integer): TfpgSize;` | 构造尺寸 | `S.SetSize(...)` |
| `function CopyRect(out Dest; const Src): Boolean;` | 复制矩形 | `Src.CopyRect(out Dest)` |
| `function InflateRect(var Rect; dx, dy): Boolean;` | 膨胀矩形 | `Rect.InflateRect(dx, dy)` |
| `function IntersectRect(out; r1, r2): Boolean;` | 矩形相交 | `r1.IntersectRect(out, r2)` |
| `function IsRectEmpty(const ARect): Boolean;` | 矩形是否为空 | `Rect.IsRectEmpty` |
| `function OffsetRect(var Rect; dx, dy): Boolean;` | 偏移矩形 | `Rect.OffsetRect(dx, dy)` |
| `function PtInRect(const ARect; const APoint): Boolean;` | 点在矩形内 | `Rect.PointInRect(APoint)` |
| `function UnionRect(out; R1, R2): Boolean;` | 矩形并集 | `r1.UnionRect(out, r2)` |
| `function CenterPoint(const Rect): TPoint;` | 矩形中心点 | `Rect.CenterPoint` |
| `function fpgRectToRect(const ARect: TfpgRect): TRect;` | fpGUI 矩形转 FCL | 仍可用 |

#### 5.9.4 消息分发函数

| 原型 | 功能 | 入参 | 返回值 | 说明 |
|------|------|------|--------|------|
| `procedure fpgPostMessage(Sender, Dest; MsgCode: integer; var aparams); overload;` | 投递消息（异步） | 发送者/接收者/消息码/参数 | — | 不阻塞 |
| `procedure fpgPostMessage(Sender, Dest; MsgCode: integer); overload;` | 投递无参消息 | — | — | — |
| `procedure fpgSendMessage(Sender, Dest; MsgCode; var aparams); overload;` | 发送消息（同步） | — | — | 阻塞，立即处理 |
| `procedure fpgSendMessage(Sender, Dest; MsgCode: integer); overload;` | 发送无参消息 | — | — | — |
| `function fpgPeekMessage(Dest; MsgCode; Msg): Boolean;` | 查看消息 | 接收者/消息码/输出 | 是否存在 | 不移除 |
| `procedure fpgDeliverMessage(var msg);` | 派发消息 | 消息记录 | — | — |
| `procedure fpgDeliverMessages;` | 派发所有消息 | — | — | — |
| `procedure fpgCoalesceMessages;` | 合并消息 | — | — | — |
| `function fpgGetFirstMessage: PfpgMessageRec;` | 获取首条消息 | — | 消息指针 | — |
| `procedure fpgDeleteFirstMessage;` | 删除首条消息 | — | — | — |
| `procedure fpgDeleteMessagesForTarget(Dest; MsgCode = -1);` | 删除目标消息 | 接收者/消息码 | — | — |
| `procedure fpgWaitWindowMessage;` | 等待窗口消息 | — | — | — |

#### 5.9.5 时间/暂停函数

| 原型 | 功能 | 入参 | 返回值 | 说明 |
|------|------|------|--------|------|
| `function fpgGetTickCount: QWord;` | 系统时钟 | — | 毫秒 | 跨平台 |
| `procedure fpgPause(MilliSeconds: Cardinal);` | 暂停 | 毫秒 | — | — |
| `function fpgCheckTimers: Boolean;` | 检查定时器队列 | — | 是否有定时器触发 | — |
| `procedure fpgResetAllTimers;` | 重置所有定时器 | — | — | — |
| `function fpgClosestTimer(ctime; amaxtime): integer;` | 最近定时器 | 当前时间/最大间隔 | 定时器 ID | — |

### 5.10 便捷工厂函数

> 源码位置：`gui/fpg_label.pas`、`gui/fpg_button.pas`、`gui/fpg_edit.pas`、`gui/fpg_panel.pas` 等

| 原型 | 功能 | 返回值 | 单元 |
|------|------|--------|------|
| `function CreateLabel(AOwner; x, y; AText; w=0; h=0; HAlign=taLeftJustify; VAlign=tlTop; ALineSpace=2): TfpgLabel;` | 创建标签 | `TfpgLabel` | fpg_label |
| `function CreateCheckBox(AOwner; x, y; AText): TfpgCheckBox;` | 创建复选框 | `TfpgCheckBox` | fpg_checkbox |
| `function CreateRadioButton(AOwner; x, y; AText): TfpgRadioButton;` | 创建单选按钮 | `TfpgRadioButton` | fpg_radiobutton |
| `function CreateEdit(AOwner; x, y, w; h=23): TfpgEdit;` | 创建编辑框 | `TfpgEdit` | fpg_edit |
| `function CreateMemo(AOwner; x, y, w, h): TfpgMemo;` | 创建多行编辑 | `TfpgMemo` | fpg_memo |
| `function CreateButton(AOwner; x, y, w; AText; OnClick): TfpgButton;` | 创建按钮 | `TfpgButton` | fpg_button |
| `function CreateComboBox(AOwner; x, y, w; AList; h=24): TfpgComboBox;` | 创建组合框 | `TfpgComboBox` | fpg_combobox |
| `function CreateSplitter(AOwner; ALeft, ATop, AWidth, AHeight; AnAlign): TfpgSplitter;` | 创建分隔条 | `TfpgSplitter` | fpg_splitter |
| `function CreateMenuBar(AOwner: TfpgWidget): TfpgMenuBar; overload;` | 创建菜单栏 | `TfpgMenuBar` | fpg_menu |
| `function CreateMenuBar(AOwner: TfpgWidget; x, y, w, h): TfpgMenuBar; overload;` | 创建菜单栏（带位置） | `TfpgMenuBar` | fpg_menu |
| `function CreatePanel(AOwner; x, y, w, h; AText): TfpgPanel;` | 创建面板 | `TfpgPanel` | fpg_panel |
| `function CreateGroupBox(AOwner; x, y, w, h; AText): TfpgGroupBox;` | 创建分组框 | `TfpgGroupBox` | fpg_panel |
| `function CreateBevel(AOwner; x, y, w, h): TfpgBevel;` | 创建斜面 | `TfpgBevel` | fpg_panel |
| `function CreateGauge(AOwner; x, y, w, h): TfpgGauge;` | 创建仪表盘 | `TfpgGauge` | fpg_gauge |

**示例**：

```pascal
procedure TMyForm.AfterCreate;
begin
  inherited AfterCreate;
  Width := 300; Height := 200;
  WindowTitle := '快速构建';

  CreateLabel(Self, 10, 10, '姓名：');
  CreateEdit(Self, 60, 10, 150);

  CreateLabel(Self, 10, 40, '性别：');
  CreateRadioButton(Self, 60, 40, '男');
  CreateRadioButton(Self, 120, 40, '女');

  CreateCheckBox(Self, 10, 70, '同意条款');

  CreateButton(Self, 100, 150, 80, '确定', @btnOKClick);
end;
```

> **最佳实践:** 工厂函数会自动设置 `Left`/`Top`/`Width`/`Height`，适合快速原型；生产代码可改用直接 `Create` 以获得更细粒度控制（如设置 `Align`/`Anchors`）。

---

## 模块6：事件机制详解

### 6.1 事件运行原理（消息派发链）

fpGUI 的事件系统由四层构成：

```
┌─────────────────────────────────────────────────────────────────────┐
│ 1. 平台事件 → fpGUI 适配层                                          │
│    Win32 WndProc / X11 event / Cocoa NSEvent / OHOS OH_Ability      │
│                    │                                                │
│                    ▼                                                │
│ 2. fpgPostMessage / fpgSendMessage                                  │
│    将平台事件转换为 fpGUI 消息（FPGM_* 常量）入队                    │
│                    │                                                │
│                    ▼                                                │
│ 3. 控件消息处理方法（message 指令绑定）                              │
│    procedure MsgPaint(var msg: TfpgMessageRec); message FPGM_PAINT; │
│    procedure MsgMouseDown(var msg); message FPGM_MOUSEDOWN;        │
│    procedure MsgKeyPress(var msg); message FPGM_KEYPRESS;          │
│                    │                                                │
│                    ▼                                                │
│ 4. Handle* 虚方法（在控件类中可重写）                                │
│    procedure HandlePaint; virtual;                                  │
│    procedure HandleLMouseDown(x, y; shiftstate); virtual;           │
│    procedure HandleKeyPress(var keycode; var shiftstate; var consumed); │
│                    │                                                │
│                    ▼                                                │
│ 5. On* 事件属性（用户绑定的回调）                                   │
│    property OnClick: TNotifyEvent read FOnClick write FOnClick;     │
│    property OnMouseDown: TMouseButtonEvent;                         │
│    property OnKeyPress: TKeyPressEvent;                              │
└─────────────────────────────────────────────────────────────────────┘
```

**派发链详解**：

1. **平台事件 → fpGUI 消息**：平台原生事件（如 Win32 `WM_LBUTTONDOWN`）被适配层转换为 fpGUI 消息常量（如 `FPGM_MOUSEDOWN`），通过 `fpgPostMessage` 投递到目标控件的消息队列。
2. **消息队列派发**：`fpgApplication.Run` 循环调用 `fpgDeliverMessages` 取出消息，调用 `fpgDeliverMessage(msg)` 派发给目标控件的 `Dispatch` 方法。
3. **`message` 指令绑定**：控件中用 `message FPGM_XXX` 指令声明的方法（如 `MsgMouseDown`）接收对应消息，做内部状态处理。
4. **`Handle*` 虚方法**：消息处理方法调用对应的 `Handle*` 虚方法（如 `HandleLMouseDown`），子类可重写以扩展行为。
5. **`On*` 事件属性**：`Handle*` 方法最后触发用户绑定的 `On*` 事件属性（如 `OnClick`/`OnMouseDown`）。

**自定义事件流程**：

```pascal
// 用户代码只需绑定 On* 事件属性
btn.OnClick := @ButtonClick;

procedure TMyForm.ButtonClick(Sender: TObject);
begin
  Close;
end;
```

**消息层流程**（高级，参考 `examples/corelib/eventtest`）：

```pascal
type
  TMainForm = class(TfpgForm)
    procedure MsgPaint(var msg: TfpgMessageRec); message FPGM_PAINT;
    procedure MsgMouseDown(var msg: TfpgMessageRec); message FPGM_MOUSEDOWN;
    // ...
  end;

procedure TMainForm.MsgPaint(var msg: TfpgMessageRec);
begin
  // 直接处理绘制消息（比 OnPaint 更底层）
  Canvas.BeginDraw;
  Canvas.Clear(clWhite);
  Canvas.DrawString(0, 0, 'Event test');
  Canvas.EndDraw;
end;
```

### 6.2 所有组件事件统一参考

> 通用事件源自 `TfpgWidget`（`corelib/fpg_widget.pas`）。

#### 6.2.1 鼠标事件

| 事件名 | 类型签名 | 触发时机 |
|--------|---------|----------|
| `OnClick` | `procedure(Sender: TObject) of object;` | 单击 |
| `OnDoubleClick` | `procedure(Sender; AButton: TMouseButton; AShift: TShiftState; const AMousePos: TPoint) of object;` | 双击 |
| `OnMultiClick` | `procedure(Sender; AButton; AShift; const AMousePos; const AClickCount: Integer) of object;` | 多次点击（≥2） |
| `OnMouseDown` | `procedure(Sender; AButton: TMouseButton; AShift: TShiftState; const AMousePos: TPoint) of object;` | 鼠标按下 |
| `OnMouseUp` | `procedure(Sender; AButton; AShift; const AMousePos) of object;` | 鼠标释放 |
| `OnMouseMove` | `procedure(Sender; AShift: TShiftState; const AMousePos: TPoint) of object;` | 鼠标移动 |
| `OnMouseEnter` | `procedure(Sender: TObject) of object;` | 鼠标进入控件 |
| `OnMouseExit` | `procedure(Sender: TObject) of object;` | 鼠标离开控件 |
| `OnMouseScroll` | `procedure(Sender; AShift: TShiftState; AWheelDelta: Single; const AMousePos: TPoint) of object;` | 垂直滚轮 |
| `OnMouseHorizScroll` | `procedure(Sender; AShift; AWheelDelta; const AMousePos) of object;` | 水平滚轮 |

#### 6.2.2 键盘事件

| 事件名 | 类型签名 | 触发时机 |
|--------|---------|----------|
| `OnKeyPress` | `procedure(Sender; var KeyCode: word; var ShiftState: TShiftState; var Consumed: boolean) of object;` | 键盘按下 |
| `OnKeyRelease` | `procedure(Sender; var KeyCode; var ShiftState; var Consumed: boolean) of object;` | 键盘释放 |
| `OnKeyChar` | `procedure(Sender; AChar: TfpgChar; var Consumed: boolean) of object;` | 字符输入 |

> **说明:** `OnKeyPress` 与 `OnKeyRelease` 的 `KeyCode` 是扫描码（如 `keyF1`），不是 ASCII。`OnKeyChar` 用于实际字符输入。设 `Consumed := True` 表示已处理，阻止默认行为。

#### 6.2.3 焦点事件

| 事件名 | 类型签名 | 触发时机 |
|--------|---------|----------|
| `OnEnter` | `procedure(Sender: TObject) of object;` | 获得焦点 |
| `OnExit` | `procedure(Sender: TObject) of object;` | 失去焦点 |

#### 6.2.4 绘制事件

| 事件名 | 类型签名 | 触发时机 |
|--------|---------|----------|
| `OnPaint` | `procedure(Sender: TObject) of object;` | 绘制请求 |

#### 6.2.5 提示事件

| 事件名 | 类型签名 | 触发时机 |
|--------|---------|----------|
| `OnShowHint` | `procedure(Sender; var AHint: TfpgString) of object;` | 显示提示前，可动态修改提示文本 |

#### 6.2.6 尺寸/移动事件

| 事件名 | 类型签名 | 触发时机 |
|--------|---------|----------|
| `OnResize` | `procedure(Sender: TObject) of object;` | 尺寸改变 |
| `OnMove` | 通过消息 `FPGM_MOVE` 处理 | 位置移动 |

#### 6.2.7 窗口生命周期事件（仅 `TfpgForm`）

| 事件名 | 类型签名 | 触发时机 |
|--------|---------|----------|
| `OnCreate` | `TNotifyEvent` | 窗口创建 |
| `OnDestroy` | `TNotifyEvent` | 窗口销毁 |
| `OnShow` | `TNotifyEvent` | 窗口显示 |
| `OnHide` | `TNotifyEvent` | 窗口隐藏 |
| `OnActivate` | `TNotifyEvent` | 窗口激活 |
| `OnDeactivate` | `TNotifyEvent` | 窗口取消激活 |
| `OnClose` | `TFormCloseEvent` | 窗口关闭（可控制关闭行为） |
| `OnCloseQuery` | `TFormCloseQueryEvent` | 关闭查询（可阻止关闭） |
| `OnHelp` | `TfpgHelpEvent` | 帮助请求 |

#### 6.2.8 数据变更事件

| 事件名 | 适用组件 | 类型签名 | 触发时机 |
|--------|---------|---------|----------|
| `OnChange` | `TfpgEdit`/`TfpgMemo`/`TfpgCheckBox`/`TfpgRadioButton`/`TfpgComboBox`/`TfpgListBox`/`TfpgTreeView`/`TfpgTrackBar`/`TfpgSpinEdit`/`TfpgColorWheel` | `TNotifyEvent` | 内容/状态改变 |
| `OnSelect` | `TfpgListBox` | — | 选中项 |
| `OnSelectionChanged` | `TfpgListView` | `TfpgLVItemSelectEvent` | 选中改变 |
| `OnScroll` | `TfpgListBox`/`TfpgScrollBar` | `TScrollNotifyEvent` | 滚动 |

#### 6.2.9 下拉框特有事件

| 事件名 | 适用组件 | 类型签名 | 触发时机 |
|--------|---------|---------|----------|
| `OnDropDown` | `TfpgComboBox` | `TNotifyEvent` | 下拉展开 |
| `OnCloseUp` | `TfpgComboBox` | `TNotifyEvent` | 下拉关闭 |

#### 6.2.10 树/页特有事件

| 事件名 | 适用组件 | 类型签名 | 触发时机 |
|--------|---------|---------|----------|
| `OnExpand` | `TfpgTreeView` | `TfpgTreeExpandEvent` | 节点展开 |
| `OnStateImageClicked` | `TfpgTreeView` | `TfpgStateImageClickedEvent` | 状态图标点击 |
| `OnChange` | `TfpgPageControl` | `TTabSheetChange` | 活动页面改变 |
| `OnClosingTabSheet` | `TfpgPageControl` | `TTabSheetClosing` | 标签页即将关闭 |

#### 6.2.11 拖放事件

| 事件名 | 类型签名 | 触发时机 |
|--------|---------|----------|
| `OnDragStartDetected` | `TNotifyEvent` | 检测到拖放开始 |

拖放的具体处理通过 `DropHandler`（`TfpgDropHandler` 类）的虚方法实现：`DropEnter`/`DropMove`/`DropLeave`/`DropDrop`。

### 6.3 事件参数类型签名

```pascal
type
  // 通用通知
  TNotifyEvent = procedure(Sender: TObject) of object;

  // 键盘
  TfpgKeyCharEvent = procedure(Sender: TObject; AChar: TfpgChar; var Consumed: boolean) of object;
  TKeyPressEvent   = procedure(Sender: TObject; var KeyCode: word;
                       var ShiftState: TShiftState; var Consumed: boolean) of object;

  // 鼠标
  TMouseButtonEvent = procedure(Sender: TObject; AButton: TMouseButton;
                        AShift: TShiftState; const AMousePos: TPoint) of object;
  TMouseButtonMultiClickEvent = procedure(Sender: TObject; AButton: TMouseButton;
                        AShift: TShiftState; const AMousePos: TPoint;
                        const AClickCount: Integer) of object;
  TMouseMoveEvent = procedure(Sender: TObject; AShift: TShiftState;
                      const AMousePos: TPoint) of object;
  TMouseWheelEvent = procedure(Sender: TObject; AShift: TShiftState;
                      AWheelDelta: Single; const AMousePos: TPoint) of object;

  // 绘制
  TPaintEvent = procedure(Sender: TObject) of object;

  // 提示
  THintEvent = procedure(Sender: TObject; var AHint: TfpgString) of object;

  // 异常
  TExceptionEvent = procedure(Sender: TObject; E: Exception) of object;

  // 滚动条
  TScrollNotifyEvent = procedure(Sender: TObject; position: integer) of object;

  // 标签页
  TTabSheetChange  = procedure(Sender: TObject; NewActiveSheet: TfpgTabSheet) of object;
  TTabSheetClosing = procedure(Sender: TObject; ATabSheet: TfpgTabSheet) of object;

  // 滑块
  TTrackBarChange = procedure(Sender: TObject; APosition: integer) of object;

  // 日历
  TfpgOnDateSetEvent = procedure(Sender: TObject; const ADate: TDateTime) of object;

  // 分隔条
  TfpgSnapEvent = procedure(Sender: TObject; const AClosed: boolean) of object;

  // 枚举
  TMouseButton = (mbLeft, mbRight, mbMiddle);
```

### 6.4 事件触发时机

| 事件 | 触发条件 | 是否冒泡 |
|------|---------|---------|
| `OnClick` | 鼠标按下后释放（同一控件） | 不冒泡 |
| `OnDoubleClick` | 短时间内连续两次按下释放 | 不冒泡 |
| `OnMultiClick` | 连续点击次数 ≥ 2 | 不冒泡 |
| `OnMouseDown/Up` | 鼠标按下/释放 | 不冒泡 |
| `OnMouseMove` | 鼠标在控件内移动 | 不冒泡 |
| `OnMouseEnter/Exit` | 鼠标进入/离开控件边界 | 不冒泡 |
| `OnMouseScroll` | 鼠标滚轮垂直滚动 | 不冒泡 |
| `OnKeyPress` | 键按下时（扫描码） | `Consumed` 阻止默认 |
| `OnKeyChar` | 字符输入时 | `Consumed` 阻止默认 |
| `OnKeyRelease` | 键释放时 | `Consumed` 阻止默认 |
| `OnEnter/OnExit` | 焦点进入/离开 | 不冒泡 |
| `OnPaint` | 控件需要重绘（`Invalidate` 后） | 不冒泡 |
| `OnResize` | 控件尺寸改变 | 不冒泡 |
| `OnShowHint` | 显示提示前 | 可修改提示文本 |
| `OnChange` | 内容/状态改变 | 不冒泡 |
| `OnDropDown/OnCloseUp` | 下拉框展开/收起 | 不冒泡 |
| `OnClose` | 窗口关闭 | 通过 `CloseAction` 控制 |
| `OnCloseQuery` | 关闭前查询 | `CanClose` 阻止 |

### 6.5 事件绑定 / 解绑 / 自定义事件

#### 6.5.1 绑定事件

在 `{$mode objfpc}` 下使用 `@` 取方法地址：

```pascal
btn.OnClick := @ButtonClick;
ed.OnChange := @TextChanged;
mem.OnKeyPress := @KeyPressed;
```

#### 6.5.2 解绑事件

赋值为 `nil`：

```pascal
btn.OnClick := nil;
ed.OnChange := nil;
```

#### 6.5.3 自定义事件处理

```pascal
type
  TMyForm = class(TfpgForm)
    procedure FormKeyPress(Sender: TObject; var KeyCode: word;
      var ShiftState: TShiftState; var Consumed: boolean);
    procedure FormMouseDown(Sender: TObject; AButton: TMouseButton;
      AShift: TShiftState; const AMousePos: TPoint);
  end;

procedure TMyForm.FormKeyPress(Sender: TObject; var KeyCode: word;
  var ShiftState: TShiftState; var Consumed: boolean);
begin
  if (KeyCode = keyS) and (ssCtrl in ShiftState) then
  begin
    SaveFile;
    Consumed := True;  // 阻止默认行为
  end;
end;

procedure TMyForm.FormMouseDown(Sender: TObject; AButton: TMouseButton;
  AShift: TShiftState; const AMousePos: TPoint);
begin
  if AButton = mbRight then
    pmMain.ShowAt(Self, AMousePos.x, AMousePos.y);
end;
```

#### 6.5.4 重写 Handle* 虚方法

更底层的方式是重写 `Handle*` 虚方法：

```pascal
type
  TMyEdit = class(TfpgEdit)
  protected
    procedure HandleKeyPress(var keycode: word; var shiftstate: TShiftState; var consumed: boolean); override;
    procedure HandleLMouseDown(x, y: integer; shiftstate: TShiftState); override;
    procedure HandlePaint; override;
  end;

procedure TMyEdit.HandleKeyPress(var keycode: word; var shiftstate: TShiftState; var consumed: boolean);
begin
  if keycode = keyReturn then
  begin
    // 自定义回车行为
    DoSomething;
    consumed := True;
    Exit;
  end;
  inherited HandleKeyPress(keycode, shiftstate, consumed);  // 调用基类以触发 OnKeyPress
end;
```

#### 6.5.5 直接处理消息（最底层）

```pascal
type
  TMyForm = class(TfpgForm)
    procedure MsgPaint(var msg: TfpgMessageRec); message FPGM_PAINT;
    procedure MsgMouseDown(var msg: TfpgMessageRec); message FPGM_MOUSEDOWN;
  end;

procedure TMyForm.MsgPaint(var msg: TfpgMessageRec);
begin
  // 直接处理绘制消息
  Canvas.BeginDraw;
  Canvas.Clear(clWhite);
  Canvas.DrawString(0, 0, 'Custom paint');
  Canvas.EndDraw;
end;
```

### 6.6 实战代码示例（参考 examples/corelib/eventtest）

完整示例取自 `examples/corelib/eventtest/eventtest.lpr`，演示消息层级的所有事件：

```pascal
program eventtest;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils,
  fpg_base, fpg_main, fpg_widget, fpg_form;

type
  TMainForm = class(TfpgForm)
  private
    FMoveEventCount: integer;
    function ShiftStateToStr(Shift: TShiftState): string;
    function MouseState(AShift: TShiftState; const AMousePos: TPoint): string;
    procedure MsgActivate(var msg: TfpgMessageRec); message FPGM_ACTIVATE;
    procedure MsgDeActivate(var msg: TfpgMessageRec); message FPGM_DEACTIVATE;
    procedure MsgClose(var msg: TfpgMessageRec); message FPGM_CLOSE;
    procedure MsgPaint(var msg: TfpgMessageRec); message FPGM_PAINT;
    procedure MsgResize(var msg: TfpgMessageRec); message FPGM_RESIZE;
    procedure MsgMove(var msg: TfpgMessageRec); message FPGM_MOVE;
    procedure MsgKeyChar(var msg: TfpgMessageRec); message FPGM_KEYCHAR;
    procedure MsgKeyPress(var msg: TfpgMessageRec); message FPGM_KEYPRESS;
    procedure MsgKeyRelease(var msg: TfpgMessageRec); message FPGM_KEYRELEASE;
    procedure MsgMouseDown(var msg: TfpgMessageRec); message FPGM_MOUSEDOWN;
    procedure MsgMouseUp(var msg: TfpgMessageRec); message FPGM_MOUSEUP;
    procedure MsgMouseMove(var msg: TfpgMessageRec); message FPGM_MOUSEMOVE;
    procedure MsgDoubleClick(var msg: TfpgMessageRec); message FPGM_DOUBLECLICK;
    procedure MsgMouseEnter(var msg: TfpgMessageRec); message FPGM_MOUSEENTER;
    procedure MsgMouseExit(var msg: TfpgMessageRec); message FPGM_MOUSEEXIT;
    procedure MsgScroll(var msg: TfpgMessageRec); message FPGM_SCROLL;
    procedure MsgHorzScroll(var msg: TfpgMessageRec); message FPGM_HSCROLL;
  public
    constructor Create(AOwner: TComponent); override;
  end;

function TMainForm.ShiftStateToStr(Shift: TShiftState): string;
begin
  Result := '';
  if ssShift in Shift then Result := Result + 'Shift ';
  if ssAlt   in Shift then Result := Result + 'Alt ';
  if ssCtrl  in Shift then Result := Result + 'Ctrl ';
  if ssLeft  in Shift then Result := Result + 'Left ';
  if ssRight in Shift then Result := Result + 'Right ';
  if ssMiddle in Shift then Result := Result + 'Middle ';
  if ssDouble in Shift then Result := Result + 'Double ';
  if Length(Result) > 0 then SetLength(Result, Length(Result) - 1);
end;

procedure TMainForm.MsgPaint(var msg: TfpgMessageRec);
var h: integer;
begin
  WriteLn('Paint message');
  Canvas.BeginDraw;
  h := Canvas.Font.Height;
  Canvas.SetColor(clWhite);
  Canvas.FillRectangle(0, 0, Width, Height);
  Canvas.SetTextColor(clBlack);
  Canvas.DrawString(0, 0, 'Event test');
  Canvas.DrawString(0, h, 'Do something interactive (move mouse, press keys...)');
  Canvas.DrawString(0, h*2, 'and watch the output on the console.');
  Canvas.EndDraw;
end;

procedure TMainForm.MsgKeyPress(var msg: TfpgMessageRec);
begin
  WriteLn('[', ShiftStateToStr(msg.Params.keyboard.shiftstate),
    '] Key pressed: ', KeycodeToText(msg.Params.keyboard.keycode, []));
end;

procedure TMainForm.MsgMouseDown(var msg: TfpgMessageRec);
begin
  WriteLn('[X=', msg.Params.mouse.x, ' Y=', msg.Params.mouse.y, ']',
    ' Mouse button pressed: button=', msg.Params.mouse.Buttons);
end;

procedure TMainForm.MsgMouseMove(var msg: TfpgMessageRec);
begin
  Inc(FMoveEventCount);
  if (FMoveEventCount mod 10) = 0 then  // 限制输出频率
    WriteLn('[X=', msg.Params.mouse.x, ' Y=', msg.Params.mouse.y, '] Mouse moved');
end;

procedure TMainForm.MsgClose(var msg: TfpgMessageRec);
begin
  WriteLn('Window Close message');
  Close;
end;

constructor TMainForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMoveEventCount := 0;
  Width := 400;
  Height := 100;
end;

procedure MainProc;
var frm: TMainForm;
begin
  fpgApplication.Initialize;
  frm := TMainForm.Create(nil);
  frm.Show;
  fpgApplication.Run;
  frm.Free;
end;

begin
  MainProc;
end.
```

> **最佳实践:** 日常开发只需绑定 `On*` 事件属性；研究消息流或拦截默认行为时才使用 `Handle*` 重写或 `message` 指令。

---

## 模块7：实战案例与常见问题汇总

### 7.1 常用功能实战案例

#### 7.1.1 窗口创建（examples/gui/helloworld）

参见 [§1.4](#14-首个-fpgui-窗口程序helloworldlpr) 的 helloworld 完整示例。

#### 7.1.2 表单布局（examples/gui/alignment、lm-mig、lm-border、lm-flow）

**Align 对齐布局**（参考 `examples/gui/alignment/`）：

```pascal
procedure TMainForm.AfterCreate;
var mnuBar, stbArea, pnlLeft, spl, pnlMain: TfpgPanel;
begin
  inherited AfterCreate;
  Width := 800; Height := 600;
  WindowTitle := '经典三栏布局';

  mnuBar := TfpgPanel.Create(Self);
  mnuBar.Align := alTop;     mnuBar.Height := 24; mnuBar.Text := '菜单栏';

  stbArea := TfpgPanel.Create(Self);
  stbArea.Align := alBottom; stbArea.Height := 20; stbArea.Text := '状态栏';

  pnlLeft := TfpgPanel.Create(Self);
  pnlLeft.Align := alLeft;   pnlLeft.Width := 150; pnlLeft.Text := '侧边栏';

  spl := TfpgSplitter.Create(Self);
  spl.Align := alLeft;       spl.Width := 4;

  pnlMain := TfpgPanel.Create(Self);
  pnlMain.Align := alClient; pnlMain.Text := '主区域';
end;
```

**Anchors 缩放对齐**（参考 `examples/gui/alignment_resize/`）：

```pascal
// 按钮固定右下角
btn := TfpgButton.Create(Self);
btn.Left := Width - 90; btn.Top := Height - 40;
btn.Width := 80; btn.Height := 30;
btn.Anchors := [anRight, anBottom];
```

**MigLayout 网格布局**（参考 `examples/gui/lm-mig/`）：

```pascal
uses fpg_miglayout, fpg_mig_lc, fpg_mig_cc;

procedure TMainForm.AfterCreate;
var mig: TfpgMigLayoutManager; lbl, ed, btn: ...
begin
  inherited AfterCreate;
  Width := 300; Height := 150;
  WindowTitle := 'MigLayout 示例';

  mig := TfpgMigLayoutManager.Create;
  mig.LC.SetGridW(2); mig.LC.SetGridH(2);
  LayoutManager := mig;

  lbl := TfpgLabel.Create(Self); lbl.Text := '姓名:';
  mig.AddLayoutComponent(lbl, TfpgMigCC.Create);

  ed := TfpgEdit.Create(Self);
  mig.AddLayoutComponent(ed, TfpgMigCC.Create.GrowX);

  btn := TfpgButton.Create(Self); btn.Text := '确定';
  mig.AddLayoutComponent(btn, TfpgMigCC.Create.SpanX(2).AlignX('center'));
end;
```

**BorderLayout / FlowLayout**（参考 `examples/gui/lm-border/`、`examples/gui/lm-flow/`）：

```pascal
uses fpg_borderlayout, fpg_flowlayout;

// BorderLayout：四周+中心五区域
var bl: TfpgBorderLayoutManager;
bl := TfpgBorderLayoutManager.Create;
LayoutManager := bl;
bl.AddLayoutComponent(pnlNorth, lbpaNorth);
bl.AddLayoutComponent(pnlSouth, lbpaSouth);
bl.AddLayoutComponent(pnlEast,  lbpaEast);
bl.AddLayoutComponent(pnlWest,  lbpaWest);
bl.AddLayoutComponent(pnlCenter, lbpaCenter);

// FlowLayout：从左到右流水排布
var fl: TfpgFlowLayout;
fl := TfpgFlowLayout.Create;
LayoutManager := fl;
fl.AddLayoutComponent(btn1);
fl.AddLayoutComponent(btn2);
fl.AddLayoutComponent(btn3);
```

#### 7.1.3 数据展示（listviewtest、treeviewtest、gridtest）

参考 [§3.4.4](#344-tfpglistview)、[§3.4.5](#345-tfpgtreeview)、[§3.4.6](#346-tfpgstringgrid) 的示例代码。

#### 7.1.4 文件选择（examples/gui/filedialog）

```pascal
procedure TMainForm.miOpenClick(Sender: TObject);
var dlg: TfpgFileDialog;
begin
  dlg := TfpgFileDialog.Create(nil);
  try
    dlg.Filter := '文本文件 (*.txt)|*.txt|所有文件 (*.*)|*.*';
    dlg.InitialDir := '/home/user';
    if dlg.ShowModal = mrOK then
      LoadFile(dlg.FileName);
  finally
    dlg.Free;
  end;
end;
```

#### 7.1.5 弹窗提示（examples/gui/modalforms）

```pascal
// 信息提示
ShowMessage('保存成功');

// 确认对话框
if fpgMessageDlg('确认', '是否删除选中项？', mtConfirmation, [mbYes, mbNo]) = mrYes then
  DeleteItem;

// 输入对话框
var s: TfpgString;
s := '';
if fpgInputQuery('重命名', '请输入新名称：', s) then
  RenameItem(s);

// 模态子窗口
function ShowOptions: boolean;
var dlg: TOptionsDlg;
begin
  dlg := TOptionsDlg.Create(nil);
  try
    Result := (dlg.ShowModal = mrOK);
  finally
    dlg.Free;
  end;
end;
```

#### 7.1.6 自定义绘图（examples/corelib/canvastest）

```pascal
type
  TDrawForm = class(TfpgForm)
    procedure FormPaint(Sender: TObject);
  public
    procedure AfterCreate; override;
  end;

procedure TDrawForm.AfterCreate;
begin
  inherited AfterCreate;
  Width := 400; Height := 300;
  WindowTitle := '自绘演示';
  OnPaint := @FormPaint;
end;

procedure TDrawForm.FormPaint(Sender: TObject);
var r: TfpgRect;
begin
  Canvas.BeginDraw;
  try
    Canvas.Clear(clWindowBackground);

    Canvas.SetColor(clRed);
    r.SetRect(10, 10, 100, 50);
    Canvas.FillRectangle(r);

    Canvas.SetTextColor(clBlack);
    Canvas.DrawString(10, 70, '自绘文本');

    fpgStyle.DrawControlFrame(Canvas, 10, 100, 200, 25);
  finally
    Canvas.EndDraw;
  end;
end;
```

#### 7.1.7 日志输出（fpg_dbugintf）

```pascal
uses fpg_dbugintf;

procedure TMainForm.AfterCreate;
begin
  inherited AfterCreate;
  InitializeDebugOutput;       // 启动日志
  DebugLn('程序启动');
  DebugLnFmt('窗口尺寸: %dx%d', [Width, Height]);
end;

destructor TMainForm.Destroy;
begin
  DebugLn('程序退出');
  FinalizeDebugOutput;
  inherited Destroy;
end;
```

### 7.2 布局适配、窗口缩放、控件居中、自适应方案

#### 7.2.1 DPI 缩放（HiDPI）

> 源码位置：`gui/fpg_toolbox.pas`

```pascal
function ScaleX(const SizeX, FromDPI: Integer): Integer;
function ScaleY(const SizeY, FromDPI: Integer): Integer;
procedure ScaleDPI(Control: TComponent; FromDPI: Integer);
function fpgScaleFontToPixel(const ASize: Integer): Integer;
function MathRound(AValue: ValReal): Int64;
function MulDiv(nNumber, nNumerator, nDenominator: Integer): Integer;
```

```pascal
procedure TMyForm.AfterCreate;
begin
  inherited AfterCreate;
  // 设计期 96 DPI 缩放到当前屏幕
  ScaleDPI(Self, 96);
end;

// 手动缩放坐标
btn.Width := ScaleX(80, 96);
btn.Height := ScaleY(30, 96);
btn.Left := ScaleX(10, 96);
btn.Top := ScaleY(10, 96);
```

#### 7.2.2 窗口缩放时控件自适应

**Align 方式**：设置 `Align := alClient`/`alTop`/`alBottom`/`alLeft`/`alRight`，自动随父容器调整。

**Anchors 方式**：设置 `Anchors` 集合，控制四边是否随父容器缩放：

```pascal
// 编辑框左右拉伸
ed.Anchors := [anLeft, anTop, anRight];

// 按钮固定右下角
btn.Anchors := [anRight, anBottom];

// 控件四边都跟随（全拉伸）
pnl.Anchors := AllAnchors;  // = [anLeft, anRight, anTop, anBottom]
```

#### 7.2.3 控件居中

```pascal
// 窗口屏幕居中
frm.WindowPosition := wpScreenCenter;

// 控件在父容器居中（手动计算）
btn.Left := (ClientWidth  - btn.Width)  div 2;
btn.Top  := (ClientHeight - btn.Height) div 2;

// MigLayout 居中
mig.AddLayoutComponent(btn, TfpgMigCC.Create.AlignX('center').AlignY('center'));
```

#### 7.2.4 窗口最小/最大尺寸

```pascal
frm.MinWidth := 400;
frm.MinHeight := 300;
frm.MaxWidth := 1920;
frm.MaxHeight := 1080;
```

#### 7.2.5 窗口属性控制

```pascal
frm.Sizeable := False;          // 不可缩放
frm.FullScreen := True;         // 全屏
frm.WindowPosition := wpScreenCenter;  // 屏幕居中
frm.WindowOpacity := 0.8;       // 80% 不透明
frm.WindowState := wsMaximized; // 最大化
```

### 7.3 常见报错、编译错误、运行异常解决方案

#### 7.3.1 编译错误

| 报错 | 原因 | 解决方案 |
|------|------|---------|
| `Fatal: Cannot find unit fpg_base` | 单元搜索路径未配置 | 添加 `-Fuframework/src/main/pascal/corelib -Fuframework/src/main/pascal/gui` |
| `Error: Incompatible types: got "TfpgColor" expected "LongInt"` | 颜色直接传给 int 参数 | 用 `LongInt(color)` 或修改函数签名 |
| `Error: class type expected, but got "TObject"` | 类型转换缺失 | 用 `TfpgButton(Sender)` 强转 |
| `Error: Wrong number of parameters declared` | 事件签名不匹配 | 严格按事件类型签名实现 |
| `Hint/Note: Inherited method not found` | `override` 方法名拼错 | 检查基类方法名 |

#### 7.3.2 运行异常

| 异常 | 原因 | 解决方案 |
|------|------|---------|
| 控件不显示 | 未设置 `Parent` | 用 `Create(Self)` 或显式 `btn.Parent := pnl` |
| `Invalidate` 后界面不刷新 | 在 `HandlePaint` 内调用 `Invalidate` | 移除递归调用 |
| 事件不触发 | 未用 `@` 赋值（`objfpc` 模式） | 改为 `btn.OnClick := @Click` |
| 模态窗口泄漏 | `ShowModal` 后未 `Free` | 使用 `try...finally` |
| 字体不生效 | 字体描述格式错误 | 检查 `字体名-字号:属性=true` 格式 |
| 中文乱码 | 字符串编码不一致 | 用 `TfpgString`(UTF-8) 并确保源文件 UTF-8 |
| 颜色透明 | Alpha 通道为 0 | 用 `$FFRRGGBB` 格式（最高位 FF） |
| 双击触发两次 `OnClick` | 未设 `IgnoreDblClicks` | `btn.IgnoreDblClicks := True` |

#### 7.3.3 调试技巧

```pascal
// 全局异常处理
fpgApplication.OnException := @MyExceptionHandler;
fpgApplication.StopOnException := False;

procedure MyExceptionHandler(Sender: TObject; E: Exception);
begin
  DebugLn('异常: ', E.Message);
  fpgApplication.ShowBacktrace;  // 显示调用栈
end;

// 长时间操作保持响应
for i := 1 to 1000000 do
begin
  ProcessData(i);
  if i mod 1000 = 0 then
    fpgApplication.ProcessMessages;  // 处理消息
end;
```

### 7.4 性能优化、界面卡顿解决、内存优化

#### 7.4.1 性能优化原则

1. **批量更新**：操作大量项时使用 `BeginUpdate`/`EndUpdate` 暂停重绘：

```pascal
mem.BeginUpdate;
try
  for i := 1 to 1000 do
    mem.Lines.Add('行 ' + IntToStr(i));
finally
  mem.EndUpdate;
end;
```

2. **图像缓存**：使用 `fpgImages` 全局管理器注册图像，避免重复加载：

```pascal
fpgImages.AddPNGFromResource('myicon', HInstance, 'MYICON');
// 多次使用同一图像
img := fpgImages.GetImage('myicon');
```

3. **字体重用**：通过 `fpgApplication.FontManager.GetFont` 获取缓存的字体对象：

```pascal
var fnt: TfpgFontResourceBase;
fnt := fpgApplication.FontManager.GetFont('Arial-8:bold');
Canvas.SetFont(fnt);
```

4. **失效化区域**：使用 `InvalidateRect` 而非 `Invalidate` 仅刷新需要更新的区域：

```pascal
r.SetRect(10, 10, 100, 50);
Self.InvalidateRect(r);  // 仅刷新这一小块
```

5. **MigLayout 性能**：对于复杂界面，使用 MigLayout 比 Align 更高效且更灵活。

#### 7.4.2 界面卡顿解决

- 长时间循环中插入 `fpgApplication.ProcessMessages`。
- 耗时操作放到独立线程（参考 `examples/gui/threads1/`）。
- 减少 `RePaint` 调用，优先用 `Invalidate`（异步）。
- 大列表使用虚拟模式或分页加载。

#### 7.4.3 内存优化

- 模态窗口使用完立即 `Free`（`try...finally`）。
- 自定义控件的 `TfpgTimer` 在 `Destroy` 中释放。
- 图像不再使用时调用 `fpgImages.DeleteImage(imgid, True)` 释放。
- 大型字符串列表清空前先 `BeginUpdate`。

### 7.5 开发避坑总结

#### 7.5.1 窗体生命周期避坑

1. **AfterCreate vs OnCreate**：重写 `AfterCreate` 初始化子控件，不要在 `Create` 中做；设计期绑定用 `OnCreate`。
2. **模态窗口必须 Free**：`ShowModal` 返回后窗口仍存在，必须 `try...finally` 释放。
3. **CloseAction**：`OnClose` 中 `caHide` 仅隐藏，`caFree` 释放。模态窗口用 `caFree`。
4. **WindowTitle vs Text**：窗口标题用 `WindowTitle`，控件文本用 `Text`。

#### 7.5.2 事件避坑

1. **`@` 运算符**：`{$mode objfpc}` 下事件赋值必须用 `@`：`btn.OnClick := @Click`。
2. **`Invalidate` 不要递归**：`HandlePaint` 内不要调用 `Invalidate`，会无限循环。
3. **`Consumed` 标志**：键盘事件中 `Consumed := True` 阻止默认行为。
4. **事件签名**：必须严格匹配事件类型签名，否则编译错误。

#### 7.5.3 布局避坑

1. **Align 顺序**：按 Tab 顺序执行，`alTop/alBottom/alLeft/alRight` 按顺序切空间，`alClient` 填充剩余。
2. **AutoSize 与 Width 冲突**：`AutoSize = True` 时手动 Width 会被覆盖。
3. **WrapText 需要 Width**：`WrapText = True` 必须设置 Width。
4. **Anchors 默认 `[anLeft, anTop]`**：不设置时控件不会跟随缩放。

#### 7.5.4 颜色避坑

1. **Alpha 通道**：颜色最高字节是 Alpha，`$FFRRGGBB` 表示不透明，`$00RRGGBB` 全透明。
2. **命名颜色动态解析**：`clWindowBackground` 等由样式决定，`fpgColorToRGB` 解析为实际 RGB。

#### 7.5.5 资源管理避坑

1. **Owner vs Parent**：`Create(AOwner)` 设置所有者（自动释放），`Parent` 设置可视父控件。
2. **图像资源**：通过 `fpgImages` 注册的图像在程序退出时统一释放，不要手动 `Free`。
3. **字体对象**：通过 `FontManager.GetFont` 获取的字体由管理器管理，不要手动释放。
4. **TfpgTimer**：自定义控件中创建的定时器必须在 `Destroy` 中释放。

#### 7.5.6 编程模式总结

**模式一：主窗口 + 子控件**

```pascal
procedure MainProc;
var frm: TfpgForm;
begin
  fpgApplication.Initialize;
  frm := TfpgForm.Create(nil);
  try
    frm.Show;
    fpgApplication.Run;
  finally
    frm.Free;
  end;
end;
```

**模式二：模态对话框**

```pascal
function ShowOptions: boolean;
var dlg: TOptionsDlg;
begin
  dlg := TOptionsDlg.Create(nil);
  try
    Result := (dlg.ShowModal = mrOK);
  finally
    dlg.Free;
  end;
end;
```

**模式三：自绘控件**

```pascal
type
  TMyControl = class(TfpgWidget)
  protected
    procedure HandlePaint; override;
  end;
```

**模式四：事件驱动**

```pascal
btn.OnClick := @ButtonClick;
ed.OnChange := @TextChanged;
mem.OnKeyPress := @KeyPressed;
```

**模式五：布局管理**

```pascal
// 简单：Align
pnl.Align := alTop;
btn.Align := alClient;

// 高级：MigLayout
mig := TfpgMigLayoutManager.Create;
LayoutManager := mig;
mig.AddLayoutComponent(btn, TfpgMigCC.Create.GrowX);
```

#### 7.5.7 不存在的组件清单（再次提醒）

参见 [§3.10.7](#3107-不存在的组件清单)。

---

## 附录

### A. 完整组件清单

| 组件 | 单元 | 继承自 | 用途 |
|------|------|--------|------|
| `TfpgForm` | fpg_form | TfpgWindow | 主窗口/对话框 |
| `TfpgBaseForm` | fpg_form | TfpgWindow | 窗口基类 |
| `TfpgMainForm` | fpg_form | TfpgForm | 主窗体语义 |
| `TfpgButton` | fpg_button | TfpgBaseButton | 下压按钮 |
| `TfpgLabel` | fpg_label | TfpgCustomLabel | 静态文本标签 |
| `TfpgEdit` | fpg_edit | TfpgBaseTextEdit | 单行文本编辑 |
| `TfpgEditInteger` | fpg_edit | TfpgBaseNumericEdit | 整数编辑 |
| `TfpgEditFloat` | fpg_edit | TfpgBaseNumericEdit | 浮点数编辑 |
| `TfpgMemo` | fpg_memo | TfpgWidget | 多行文本编辑 |
| `TfpgCheckBox` | fpg_checkbox | TfpgBaseCheckBox | 复选框 |
| `TfpgRadioButton` | fpg_radiobutton | TfpgWidget | 单选按钮 |
| `TfpgToggle` | fpg_toggle | TfpgCheckBox | 开关切换 |
| `TfpgComboBox` | fpg_combobox | TfpgBaseStaticCombo | 下拉组合框 |
| `TfpgListBox` | fpg_listbox | TfpgTextListBox | 列表框 |
| `TfpgColorListBox` | fpg_listbox | TfpgBaseColorListBox | 颜色列表框 |
| `TfpgListView` | fpg_listview | TfpgWidget | 列表视图 |
| `TfpgTreeView` | fpg_tree | TfpgWidget | 树视图 |
| `TfpgStringGrid` | fpg_grid | TfpgCustomStringGrid | 字符串网格 |
| `TfpgFileGrid` | fpg_grid | TfpgCustomGrid | 文件网格 |
| `TfpgHexView` | fpg_hexview | TfpgWidget | 十六进制查看 |
| `TfpgPanel` | fpg_panel | TfpgAbstractPanel | 面板 |
| `TfpgGroupBox` | fpg_panel | TfpgAbstractPanel | 分组框 |
| `TfpgBevel` | fpg_panel | TfpgAbstractPanel | 斜面/分隔线 |
| `TfpgFrame` | fpg_panel | TfpgWidget | 框架容器 |
| `TfpgPageControl` | fpg_tab | TfpgWidget | 页面控件 |
| `TfpgTabSheet` | fpg_tab | TfpgWidget | 标签页 |
| `TfpgScrollBar` | fpg_scrollbar | TfpgWidget | 滚动条 |
| `TfpgScrollFrame` | fpg_scrollframe | TfpgFrame | 滚动框架 |
| `TfpgSplitter` | fpg_splitter | TfpgWidget | 分隔条 |
| `TfpgMigSplitter` | fpg_splitter | TfpgWidget | MigLayout 分隔条 |
| `TfpgMenuBar` | fpg_menu | TfpgWidget | 菜单栏 |
| `TfpgPopupMenu` | fpg_menu | TfpgPopupWindow | 弹出菜单 |
| `TfpgMenuItem` | fpg_menu | TfpgComponent | 菜单项 |
| `TfpgProgressBar` | fpg_progressbar | TfpgCustomProgressBar | 进度条 |
| `TfpgGauge` | fpg_gauge | TfpgBaseGauge | 仪表盘 |
| `TfpgTrackBar` | fpg_trackbar | TfpgBaseTrackBar | 滑块 |
| `TfpgTrackBarExtra` | fpg_trackbar | TfpgBaseTrackBar | 增强滑块 |
| `TfpgSpinEditFloat` | fpg_spinedit | TfpgAbstractSpinEdit | 浮点微调 |
| `TfpgSpinEditInteger` | fpg_spinedit | TfpgAbstractSpinEdit | 整数微调 |
| `TfpgHyperlink` | fpg_hyperlink | TfpgCustomLabel | 超链接标签 |
| `TfpgHintWindow` | fpg_hint | TfpgForm | 提示窗口 |
| `TfpgSystemTrayIcon` | fpg_trayicon | TfpgWidget | 系统托盘图标 |
| `TfpgColorWheel` | fpg_colorwheel | TfpgWidget | 色轮选择器 |
| `TfpgValueBar` | fpg_colorwheel | TfpgWidget | 值条 |
| `TfpgCalendar` | fpg_popupcalendar | TfpgWidget | 月历控件 |
| `TfpgPopupCalendar` | fpg_popupcalendar | TfpgPopupWindow | 弹出日历 |
| `TfpgImgAnim` | fpg_animation | TfpgBaseImgAnim | 帧动画 |
| `TfpgFileNameEdit` | fpg_editbtn | TfpgBaseEditButton | 文件名编辑 |
| `TfpgEditButton` | fpg_editbtn | TfpgAbstractPanel | 带按钮编辑基类 |
| `TfpgEditCombo` | fpg_editcombo | TfpgBaseComboBox | 可编辑组合框 |
| `TfpgReadOnly` | fpg_readonly | TComponent | 只读控制器（非可视） |
| `TfpgMessageBox` | fpg_dialogs | TfpgForm | 消息框 |
| `TfpgFileDialog` | fpg_dialogs | TfpgForm | 文件对话框 |
| `TfpgBaseDialog` | fpg_dialogs | TfpgForm | 对话框基类 |
| `TfpgFontSelectDialog` | fpg_dialogs | TfpgBaseDialog | 字体选择 |
| `TfpgImage` | fpg_main | TfpgImageImpl | 图像对象（非可视） |
| `TfpgCanvas` | fpg_main | TfpgCanvasImpl | 画布对象（非可视） |
| `TfpgApplication` | fpg_main | TfpgApplicationImpl | 全局应用对象 |
| `TfpgStyle` | fpg_main | TObject | 样式基类 |
| `TfpgTimer` | fpg_main | TfpgTimerImpl | 定时器 |
| `TfpgClipboard` | fpg_main | TfpgClipboardImpl | 剪贴板 |
| `TfpgImages` | fpg_main | TObject | 图像管理器 |
| `TfpgLEDMatrix` | fpg_ledmatrix | TfpgWidget | LED 矩阵 |

### B. 源码文件索引

| 路径 | 说明 |
|------|------|
| `corelib/fpg_base.pas` | 基础类型、消息常量、TfpgCanvasBase/TfpgWidgetBase |
| `corelib/fpg_main.pas` | 应用程序、Canvas、Style、Timer、全局函数 |
| `corelib/fpg_widget.pas` | 控件基类 TfpgWidget |
| `corelib/fpg_impl.pas` | 平台抽象接口（按平台子目录：gdi/cocoa/ohos/x11） |
| `corelib/fpg_interface.pas` | 各平台 TfpgXxxImpl 别名绑定 |
| `corelib/fpg_fontmanager.pas` | 字体管理 |
| `corelib/fpg_dbugintf.pas` | 调试日志输出 |
| `corelib/keys.inc` | 键盘常量 |
| `corelib/predefinedcolors.inc` | 颜色常量 |
| `corelib/fpg_miglayout.pas` | MigLayout 布局管理器 |
| `corelib/fpg_borderlayout.pas` | BorderLayout |
| `corelib/fpg_flowlayout.pas` | FlowLayout |
| `corelib/fpg_layoutmanager.pas` | ILayoutManager 接口 |
| `corelib/fpg_command_intf.pas` | ICommand 命令模式接口 |
| `corelib/fpg_extgraphics.pas` | 扩展图形 |
| `corelib/fpg_constants.pas` | 常量定义 |
| `corelib/fpg_stringutils.pas` | 字符串工具 |
| `corelib/fpg_utils.pas` | 通用工具 |
| `corelib/fpg_hvif.pas` | HVIF 矢量图标 |
| `corelib/fpg_iconstore.pas` | 图标存储 |
| `corelib/fpg_imagelist.pas` | 图像列表 |
| `corelib/fpg_imgfmt_bmp/jpg/png.pas` | 图像格式编解码 |
| `corelib/fpg_popupwindow.pas` | 弹出窗口基类 |
| `corelib/fpg_stdicons.pas` | 标准图标 |
| `corelib/fpg_stdimages.pas` | 标准图像 |
| `corelib/fpg_translations.pas` | i18n 翻译 |
| `corelib/fpg_pofiles.pas` | PO 文件解析 |
| `gui/fpg_form.pas` | 窗口/表单 |
| `gui/fpg_window.pas` | 顶层窗口基类 |
| `gui/fpg_button.pas` | 按钮 |
| `gui/fpg_label.pas` | 标签 |
| `gui/fpg_edit.pas` | 文本编辑 |
| `gui/fpg_memo.pas` | 多行编辑 |
| `gui/fpg_checkbox.pas` | 复选框 |
| `gui/fpg_radiobutton.pas` | 单选按钮 |
| `gui/fpg_toggle.pas` | 开关控件 |
| `gui/fpg_combobox.pas` | 组合框 |
| `gui/fpg_editcombo.pas` | 可编辑组合框 |
| `gui/fpg_listbox.pas` | 列表框 |
| `gui/fpg_listview.pas` | 列表视图 |
| `gui/fpg_tree.pas` | 树视图 |
| `gui/fpg_panel.pas` | 面板/分组框/斜面/框架 |
| `gui/fpg_tab.pas` | 页面控件 |
| `gui/fpg_scrollbar.pas` | 滚动条 |
| `gui/fpg_scrollframe.pas` | 滚动框架 |
| `gui/fpg_splitter.pas` | 分隔条 |
| `gui/fpg_menu.pas` | 菜单 |
| `gui/fpg_progressbar.pas` | 进度条 |
| `gui/fpg_gauge.pas` | 仪表盘 |
| `gui/fpg_trackbar.pas` | 滑块 |
| `gui/fpg_spinedit.pas` | 微调编辑 |
| `gui/fpg_hyperlink.pas` | 超链接 |
| `gui/fpg_hint.pas` | 提示窗口 |
| `gui/fpg_trayicon.pas` | 系统托盘 |
| `gui/fpg_colorwheel.pas` | 色轮 |
| `gui/fpg_popupcalendar.pas` | 弹出日历/月历 |
| `gui/fpg_animation.pas` | 帧动画 |
| `gui/fpg_dialogs.pas` | 标准对话框与全局函数 |
| `gui/fpg_editbtn.pas` | 复合编辑控件 |
| `gui/fpg_readonly.pas` | 只读控制器 |
| `gui/fpg_toolbox.pas` | DPI 缩放工具 |
| `gui/fpg_basegrid.pas` | 网格基类 |
| `gui/fpg_customgrid.pas` | 自定义网格 |
| `gui/fpg_grid.pas` | 文件网格/字符串网格 |
| `gui/fpg_hexview.pas` | 十六进制查看 |
| `gui/fpg_ledmatrix.pas` | LED 矩阵 |
| `gui/fpg_style.pas` | 样式基类 |
| `gui/fpg_style_fusion.pas` | Fusion 样式（默认现代） |
| `gui/fpg_style_carbon.pas` | Carbon 样式（macOS） |
| `gui/fpg_style_motif.pas` | Motif 样式 |
| `gui/fpg_style_plastic.pas` | Plastic 样式 |
| `gui/fpg_style_win2k.pas` | Windows 2000 样式 |
| `gui/fpg_style_win8.pas` | Windows 8 样式 |
| `gui/fpg_stylemanager.pas` | 样式管理器 |
| `gui/fpg_stringgridbuilder.pas` | 字符串网格构建器 |
| `gui/fpg_colormapping.pas` | 颜色映射 |
| `gui/fpg_dnd_window.pas` | 拖放窗口 |
| `gui/fpg_iniutils.pas` | INI 工具 |
| `gui/fpg_mru.pas` | 最近使用文件列表 |

### C. 示例项目索引

| 路径 | 说明 |
|------|------|
| `examples/corelib/helloworld/` | 核心库 Hello World |
| `examples/corelib/canvastest/` | Canvas 绘制测试 |
| `examples/corelib/eventtest/` | 事件测试（消息流） |
| `examples/corelib/aggcanvas/` | AGG 画布测试 |
| `examples/gui/helloworld/` | Hello World 入门 |
| `examples/gui/modalforms/` | 模态窗口 |
| `examples/gui/alignment/` | 基础对齐 |
| `examples/gui/alignment_resize/` | 缩放对齐 |
| `examples/gui/lm-border/` | BorderLayout 布局 |
| `examples/gui/lm-flow/` | FlowLayout 布局 |
| `examples/gui/lm-mig/` | MigLayout 布局 |
| `examples/gui/combobox/` | 组合框 |
| `examples/gui/listbox/` | 列表框 |
| `examples/gui/colorlistbox/` | 颜色列表框 |
| `examples/gui/listviewtest/` | 列表视图 |
| `examples/gui/treeviewtest/` | 树视图 |
| `examples/gui/gridtest/` | 网格 |
| `examples/gui/gridediting/` | 网格编辑 |
| `examples/gui/memo/` | 多行编辑 |
| `examples/gui/panel/` | 面板 |
| `examples/gui/bevel/` | 斜面 |
| `examples/gui/tabtest/` | 页面控件 |
| `examples/gui/menutest/` | 菜单 |
| `examples/gui/menu_headers/` | 菜单标题 |
| `examples/gui/splitter/` | 分隔条 |
| `examples/gui/scrollframe/` | 滚动框架 |
| `examples/gui/gauges/` | 仪表盘 |
| `examples/gui/calendar/` | 日历 |
| `examples/gui/colorwheel/` | 色轮 |
| `examples/gui/customwindow/` | 自定义窗口 |
| `examples/gui/filedialog/` | 文件对话框 |
| `examples/gui/filegrid/` | 文件网格 |
| `examples/gui/fontselect/` | 字体选择 |
| `examples/gui/hintwindow/` | 提示窗口 |
| `examples/gui/togglebox/` | 开关控件 |
| `examples/gui/splashscreen/` | 启动画面 |
| `examples/gui/drag_n_drop/` | 拖放 |
| `examples/gui/mousecursor/` | 鼠标光标 |
| `examples/gui/timertest/` | 定时器 |
| `examples/gui/animation/` | 动画 |
| `examples/gui/edits/` | 编辑框 |
| `examples/gui/edits_extrahint/` | 编辑框占位符 |
| `examples/gui/embedded_form/` | 嵌入式表单 |
| `examples/gui/aboutdialog/` | 关于对话框 |
| `examples/gui/command_interface/` | 命令模式 |
| `examples/gui/customstyles/` | 自定义样式 |
| `examples/gui/imgtest/` | 图像测试 |
| `examples/gui/imgtest_jpeg/` | JPEG 测试 |
| `examples/gui/led_matrix_display/` | LED 矩阵 |
| `examples/gui/sprites/` | 精灵动画 |
| `examples/gui/stdimages/` | 标准图像 |
| `examples/gui/threads1/` | 多线程 |
| `examples/gui/video_vlc/` | VLC 视频 |
| `examples/gui/wulinetest/` | 物理引擎 |
| `examples/gui/reporting/` | 报表 |
| `examples/gui/dbtest/` | 数据库测试 |
| `examples/gui/common/` | 公共示例代码 |
| `examples/apps/docedit/` | 文档编辑器 |
| `examples/apps/nanoedit/` | 简易编辑器 |
| `examples/apps/hexviewer/` | 十六进制查看器 |
| `examples/apps/globe/` | 地球仪 |
| `examples/apps/debugserver/` | 调试服务器 |

---

> **本手册基于 fpGUI 2.1.0 源码编写，所有 API 均来自实际源代码。**

> **最后更新: 2026-09-01**
