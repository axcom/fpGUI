{
    fpGUI  -  Free Pascal GUI Toolkit

    Copyright (c) 2026 See the file AUTHORS.txt, included in this
    distribution, for details of the copyright.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

    Description:
      This unit implements HarmonyOS native drawing support for fpGUI
      using the native_drawing and native_window NDK APIs.
}

unit fpg_ohos;

{$I fpg_defines.inc}
{$codepage utf8}

interface

uses
  Classes,
  SysUtils,
  CTypes,
  SyncObjs,
  fpg_base,
  fpg_impl,
  fpg_ohos_drawing,
  fpg_ohos_nativewindow,
  fpg_wakechannel,
  fpg_cmdlineparams;

function dlopen(__filename: PChar; __mode: Integer): Pointer; cdecl; external 'c' name 'dlopen';
function dlsym(__handle: Pointer; __name: PChar): Pointer; cdecl; external 'c';
{ libc free — releases memory allocated by C++ (strdup/malloc); FPC's
  FreeMem must NOT be used for buffers from the C heap. }
procedure cfree(p: Pointer); cdecl; external 'c' name 'free';

{ Resolve a symbol exported by LIB_fpgBridge (C++ bridge) via explicit handle. }
function LibBridgeSym(const AName: PChar): Pointer;

// ── OHOS hilog 日志支持 ─────────────────────────────────────────
const
  LOG_APP  = 0;
  LOG_INFO = 4;
  LOG_WARN = 5;
  LOG_ERROR = 6;
  FP_LOG_DOMAIN = $FF00;
  FP_LOG_TAG = 'fpc';

procedure OH_LOG_Print(logType: Integer; logLevel: Integer;
  domain: Cardinal; tag: PChar; fmt: PChar); cdecl; varargs;
  external 'libhilog_ndk.z.so';

// ── 日志辅助 ─────────────────────────────────────────────────────
procedure fpGUI_Hilog(level: Integer; const Msg: String);

const
  LIB_fpgBridge = 'libfp_bridge.so';
  
type
  POH_NativeWindow       = Pointer;
  POH_NativeWindowBuffer = Pointer;

const
  { Action constants matching OH_NativeXComponent_TouchEventType }
  OH_TOUCH_DOWN  = 0;
  OH_TOUCH_MOVE  = 1;
  OH_TOUCH_UP    = 2;

  { Keyboard action constants }
  OH_KEY_DOWN = 0;
  OH_KEY_UP   = 1;

type
{ TfpgOhosFontResource }

  TfpgOhosFontResource = class(TfpgFontResourceBase)
  protected
    FAscent: Integer;
    FDescent: Integer;
    FHeight: Integer;
    FTextWidth: Integer;
    FIsBold: Boolean;
    FIsItalic: Boolean;
    FIsUnderline: Boolean;
    FNativeFont: POH_Drawing_Font;
    FNativeTypeface: POH_Drawing_Typeface;
    FNativeTypefacePath: string;   { 主 typeface 来源（'FontMgr:xxx' 或文件路径）}
    FMetricsValid: Boolean;        // True if OH_Drawing_FontGetMetrics succeeded
    FNativeReady: Boolean;         { NativeFont 的 typeface/size 已配置完成，
                                     绘制时无需再重复 SetTypeface/SetTextSize }
    FMetrics: TOH_Drawing_FontMetrics;
    FFallbackTypefaces: array of POH_Drawing_Typeface;  { CJK 兜底 + emoji }
    FFallbackFonts: array of POH_Drawing_Font;          { 平行于 typefaces（同 FHeight）}
    procedure   BuildFallbackChain;       { 探测构建 fallback 字体链 }
    function    ResolveFallbackWidth(const ch: string; var AWidth: Single): Boolean;
    function    ResolveFallbackFont(const ch: string;
      var AUseFont: POH_Drawing_Font; var AWidth: Single): Boolean;
    procedure   RefreshMetrics;
  public
    constructor Create(const afontdesc: string); override;
    destructor Destroy; override;
    function  GetAscent: Integer; override;
    function  GetDescent: Integer; override;
    function  GetHeight: Integer; override;
    function  GetTextWidth(const txt: string): Integer; override;
    function  HandleIsValid: boolean; override;
    property  NativeFont: POH_Drawing_Font read FNativeFont;
    property  IsBold: Boolean read FIsBold;
    property  IsItalic: Boolean read FIsItalic;
    property  IsUnderline: Boolean read FIsUnderline;
  end;

{ TfpgOhosCmdLineParams — OHOS command-line params from C++ }
{ Parses space-separated args string: "-b debug key=value" }
type
  TfpgOhosCmdLineParams = class(TInterfacedObject, ICmdLineParams)
  private
    FItems: TStringList;
    FOptionChar: char;
    FCaseSensitiveOptions: Boolean;
    procedure   ParsePayload(const APayload: string);
    function    GetOptionAtIndex(AIndex: Integer; IsLong: Boolean): string;
    function    FindOptionIndex(const S: string; var LongOpt: Boolean; StartAt: Integer = -1): Integer;
    function    GetOptionValue(const S: string): string;
    function    GetOptionValue(const C: char; const S: string): string;
    function    GetOptionValues(const C: Char; const S: string): TStringArray;
    function    HasOption(const S: string): Boolean;
    function    HasOption(const C: char; const S: string): Boolean;
    function    CheckOptions(const ShortOptions: string; const Longopts: TStrings; Opts, NonOpts: TStrings; AllErrors: Boolean = False): string;
    function    CheckOptions(const ShortOptions: string; const Longopts: array of string; Opts, NonOpts: TStrings; AllErrors: Boolean = False): string;
    function    CheckOptions(const ShortOptions: string; const LongOpts: TStrings; AllErrors: Boolean = False): string;
    function    CheckOptions(const ShortOptions: string; const LongOpts: array of string; AllErrors: Boolean = False): string;
    function    CheckOptions(const ShortOptions: string; const LongOpts: string; AllErrors: Boolean = False): string;
    function    GetNonOptions(const ShortOptions: string; const LongOpts: Array of string): TStringArray;
    procedure   GetNonOptions(const ShortOptions: string; const LongOpts: Array of string; NonOptions: TStrings);
    function    GetCaseSensitiveOptions: Boolean;
    function    GetOptionChar: char;
    procedure   SetCaseSensitiveOptions(AValue: Boolean);
    procedure   SetOptionChar(AValue: char);
    function    ParamStr(AIndex: integer): string;
    function    GetParams(AIndex: integer): string;
    function    GetParamCount: integer;
  public
    constructor Create(const AAppArgs, APayload: string);
    destructor  Destroy; override;
    property    OptionChar: char read GetOptionChar write SetOptionChar;
    property    CaseSensitiveOptions: Boolean read GetCaseSensitiveOptions write SetCaseSensitiveOptions;
    property    Params[Index: integer]: string read GetParams;
    property    ParamCount: integer read GetParamCount;
  end;

{ TfpgOhosImage }

type
  TfpgOhosImage = class(TfpgImageBase)
  protected
    FNativeBitmap: POH_Drawing_Bitmap;
    procedure DoFreeImage; override;
    procedure DoInitImage(acolordepth, awidth, aheight: integer; aimgdata: Pointer); override;
    procedure DoInitImageMask(awidth, aheight: integer; aimgdata: Pointer); override;
  end;

{ TfpgOhosCanvas }

  TfpgOhosCanvas = class(TfpgCanvasBase)
  protected
    FCanvas: POH_Drawing_Canvas;
    FBitmap: POH_Drawing_Bitmap;
    FPen: POH_Drawing_Pen;
    FBrush: POH_Drawing_Brush;
    FRect: POH_Drawing_Rect;
    FPathEffect: POH_Drawing_PathEffect;   // dash 等线型效果（随 FLineStyle 重建，Destroy 时释放）
    FClipRect: TfpgRect;
    { FSaveCount: 0 = owns canvas/bitmap resources (must destroy them);
      >0 = sharing parent's canvas/bitmap (do NOT destroy) }
    FSaveCount: Int32;
    FColorValue: TfpgColor;
    FClipDepth: Int32;          // Number of active clip-rect saves on this canvas
    FChildSaveCount: UInt32;    // Save count captured in DoBeginDraw for child widgets
    { On the PARENT's canvas: base save count at the start of the first child.
      Captured in DoBeginDraw first-child branch; subsequent children call
      RestoreToCount to this level to discard the previous child's clip saves
      and matrix changes. Reset to 0 at the top of each frame. }
    FBaseChildSaveCount: UInt32;
    { Flag: true when at least one child widget has used this canvas in the
      current frame. Reset to false in top-level DoBeginDraw. }
    FHasChildPainted: Boolean;
    // 记录进入子分支时父 canvas 的 FBeginDrawCount
    FParentBeginDrawCount: Integer;
    // Canvas 创建后的 save count 基线（用于复用路径恢复）
    FSaveBaseline: Int32;
    { 首帧已上屏标志：第一次 DoPutBufferToScreen 成功 FlushBuffer 后置位，
      并向 ETS 发 NATIVE_CMD_FIRST_FRAME 打开 XComponent 显示门（防黑屏闪现）}
    FFirstFrameSent: Boolean;
    procedure   DoSetFontRes(fntres: TfpgFontResourceBase); override;
    procedure   DoSetTextColor(cl: TfpgColor); override;
    procedure   DoSetColor(cl: TfpgColor); override;
    procedure   DoSetLineStyle(awidth: integer; astyle: TfpgLineStyle); override;
    procedure   DoFillRectangle(x, y, w, h: TfpgCoord); override;
    procedure   DoXORFillRectangle(col: TfpgColor; x, y, w, h: TfpgCoord); override;
    procedure   DoFillTriangle(x1, y1, x2, y2, x3, y3: TfpgCoord); override;
    procedure   DoDrawRectangle(x, y, w, h: TfpgCoord); override;
    procedure   DoDrawLine(x1, y1, x2, y2: TfpgCoord); override;
    procedure   DoDrawImagePart(x, y: TfpgCoord; img: TfpgImageBase; xi, yi, w, h: integer); override;
    procedure   DoStretchDraw(x, y, w, h: TfpgCoord; ASource: TfpgImageBase); override;
    procedure   DoDrawString(x, y: TfpgCoord; const txt: string); override;
    procedure   DoSetClipRectInternal(const ARect: TfpgRect);
    procedure   DoSetClipRect(const ARect: TfpgRect); override;
    function    DoGetClipRect: TfpgRect; override;
    procedure   DoAddClipRect(const ARect: TfpgRect); override;
    procedure   DoClearClipRect; override;
    procedure   DoBeginDraw(awidget: TfpgWidgetBase; CanvasTarget: TfpgCanvasBase); override;
    procedure   DoPutBufferToScreen(x, y, w, h: TfpgCoord); override;
    procedure   DoEndDraw; override;
    function    GetPixel(X, Y: integer): TfpgColor; override;
    procedure   SetPixel(X, Y: integer; const AValue: TfpgColor); override;
    procedure   DoDrawArc(x, y, w, h: TfpgCoord; a1, a2: double); override;
    procedure   DoFillArc(x, y, w, h: TfpgCoord; a1, a2: double); override;
    procedure   DoDrawPolygon(const Points: array of TPoint); override;
    function    GetBufferAllocated: Boolean; override;
    procedure   DoAllocateBuffer; override;
  public
    function    GetBitmapWidth: Integer;
    function    GetBitmapHeight: Integer;
    function    GetBitmapPixels: Pointer;
    procedure   DrawString(x, y: TfpgCoord; const txt: string); override;
    procedure   CopyRect(ADest_x, ADest_y: TfpgCoord; ASrcCanvas: TfpgCanvasBase; var ASrcRect: TfpgRect); override;
    procedure   GradientFill(ARect: TfpgRect; AStart, AStop: TfpgColor; ADirection: TGradientDirection); override;
    constructor Create(awidget: TfpgWidgetBase); override;
    destructor  Destroy; override;
  end;

{ TfpgOhosWindow }

  TfpgOhosWindow = class(TfpgWindowBase)
  private
    FWinHandle: TfpgWinHandle;// OHNativeWindow* 指针（通过 OH_NativeWindow_CreateNativeWindowFromSurfaceId得到，不是 SurfaceID）
    FBuffer: POH_NativeWindowBuffer;
    FTitle: string;           // cached title (TfpgWindowBase.WindowTitle is write-only)
    FPhysicalWidth: Integer;  // physical pixel size at creation (for flush clamping)
    FPhysicalHeight: Integer;
    FDecTop: Integer;         // 本窗口装饰顶偏移（标题栏高，vp；-1=未查询懒加载）——弹窗定位补偿
    FDecLeft: Integer;        // 本窗口左边框宽（vp；-1=未查询懒加载）——弹窗定位 X 补偿
    FDNDEnabledQueued: Boolean;  { DoDNDEnabled 在句柄创建前调用时暂存，创建后补发（GDI QueueAcceptDrops 同式）}
  public
    { AGG 混合画布首帧重置请求：DoSetWindowVisible(True) 置位，下一次
      TOhosBufferManager.AttachWindow 消费并重置其 FFirstFrameSent，使重新
      显示后的首帧 FlushBuffer 再次通知 ETS 开门。AGG 画布在不同单元，且
      fpg_ohos 不可 uses fpg_ohos_hybrid_canvas（循环依赖），故经此公共字段
      跨单元传递重置信号。非 AGG 画布（TfpgOhosCanvas）同单元直接重置，不读此字段。 }
    FirstFrameResetPending: Boolean;
    property  PhysicalWidth: Integer read FPhysicalWidth;
    property  PhysicalHeight: Integer read FPhysicalHeight;
    { resize 反馈（windowSizeChange→onWindowResized）时更新物理尺寸：
      渲染目标（bitmap）按此重建，否则 bitmap 停在创建时尺寸，
      窗口拖大后超出部分无内容（黑色）。 }
    procedure SetPhysicalSize(AW, AH: Integer);
    { 标题栏拖动/最大化后同步屏幕位置（物理 px → FPosition 逻辑）。
      不触发窗口移动（位置已由系统改变，避免回发 ETS 循环）。 }
    procedure SetScreenPosition(AX, AY: Integer);
    { 系统已销毁窗口后调用：句柄置 nil（窗体对象保留）。
      关闭到托盘路径（onPrepareToTerminate 阻止终止后）依赖此清理：
      HasHandle=False → Show 时 AllocateWindowHandle 自动重建窗口。 }
    procedure InvalidateNativeHandle;
  protected
    function    HandleIsValid: boolean; override;
    procedure   DoUpdateWindowPosition; override;
    procedure   DoAllocateWindowHandle(AParent: TfpgWidgetBase); override;
    procedure   DoReleaseWindowHandle; override;
    procedure   DoRemoveWindowLookup; override;
    procedure   DoSetWindowAttributes(const AOldAtributes, ANewAttributes: TWindowAttributes; const AForceAll: Boolean); override;
    procedure   DoSetWindowVisible(const AValue: Boolean); override;
    procedure   DoMoveWindow(const x: TfpgCoord; const y: TfpgCoord); override;
    function    DoWindowToScreen(ASource: TfpgWindowBase; const AScreenPos: TPoint): TPoint; override;
    procedure   DoSetWindowTitle(const ATitle: string); override;
    procedure   DoSetMouseCursor; override;
    procedure   DoDNDEnabled(const AValue: boolean); override;
    { 窗口属性联动 OHOS（Pascal→C++→ETS；基类 fpg_base:722/723 虚方法 override）}
    procedure   SetWindowState(const AValue: TfpgWindowState); override;
    function    GetWindowState: TfpgWindowState; override;                   { v10 }
    procedure   SetFullscreen(AValue: Boolean); override;                   { v10 }
    procedure   SetWindowOpacity(AValue: Single); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;
    procedure   ActivateWindow; override;
    procedure   CaptureMouse(AForWidget: TfpgWidgetBase); override;
    procedure   ReleaseMouse; override;
    procedure   BringToFront; override;
    property    WinHandle: TfpgWinHandle read FWinHandle;
  end;

{ 仅用于从 ohos 后端读取 TfpgWindowBase 的 protected 键盘焦点（FindWidgetForKeyEvent）。
  借壳子类暴露，避免改动 framework 公共 API。 }
  THackWindow = class(TfpgWindowBase)
  public
    function HackGetFocusWidget: TfpgWidgetBase;
  end;

{ 窗口命令（native 线程 → loop 线程串行化）。
  Kind: 0=MOVED(x,y) 1=CLOSED 2=CAN_CLOSE(Result 回填+Awaiter) 3=REFRESH }
  PfpgOhosWinCmd = ^TfpgOhosWinCmd;
  TfpgOhosWinCmd = record
    Kind: Integer;
    Handle: TfpgWinHandle;
    A, B: Integer;
    Result: Integer;
    Awaiter: TEvent;
  end;

{ TfpgOhosApplication }

  TfpgOhosApplication = class(TfpgApplicationBase)
  private
    FScreenW: TfpgCoord;
    FScreenH: TfpgCoord;
    FScreenDpi: Integer;
    FEventQueue: TList;
    FEventQueueLock: TCriticalSection; // protects FEventQueue（NAPI 注入 vs loop 消费——TList 并发撕裂曾致 SIGSEGV）
    FKeyEventQueue: TList;
    FResizeQueue: TList;
    FResizeQueueLock: TCriticalSection; // protects FResizeQueue（同 EventQueue 竞态：注入 Add vs loop Delete）
    FTrayEventQueue: TList;       { 托盘事件队列（C++ 线程注入，UI 线程消费）}
    FConfigQueue: TList;          { 系统 Configuration 变更队列（同跨线程消费模式）}
    FKeyQueueLock: TCriticalSection;   // protects FKeyEventQueue (NAPI thread vs UI thread)
    FTrayQueueLock: TCriticalSection;  // protects FTrayEventQueue (NAPI thread vs UI thread)
    FConfigQueueLock: TCriticalSection; // protects FConfigQueue (NAPI thread vs UI thread)
    FWinCmdQueue: TList;              { native 线程窗口命令队列（跨线程串行化：桥入队→loop 消费）}
    FWinCmdLock: TCriticalSection;    // protects FWinCmdQueue (NAPI thread vs UI thread)
    FLastKeyboardType: Integer;        // last sent keyboard type (0=hidden) - avoid redundant bridge calls
    FLastKeyDown: Integer;             // last key code that delivered a KEYPRESS (Backspace/Delete UP re-fire guard)
    FCutKeyPending: Boolean;           // Ctrl+X KEYPRESS dispatched: drop the TextInput cut's duplicate delete
    FWinHandleMap: TList;       // maps TfpgWinHandle 鈫?TfpgWindowBase for touch routing
    FRepaintWin: TfpgWinHandle; // Qt QPA 式 RepaintHelper：目标窗口（buffer 池滞后重试）
    FRepaintTicks: Integer;     // 剩余重试次数
    FRepaintNext: Int64;        // 下次重试时刻（GetTickCount64）
    FRepaintArmLogged: Boolean; // 本轮只打一条 arm 日志（60ms/次重试不再刷屏）
    FDragQueue: TList;          { 拖拽事件队列（ETS 注入，loop/泵消费；同触摸队列模式）}
    FDragQueueLock: TCriticalSection; // protects FDragQueue
    function    HasPendingEvents: Boolean;
    function    HasPendingKeyEvents: Boolean;
    function    HasPendingResizeEvents: Boolean;
    function    HasPendingTrayEvents: Boolean;
    function    HasPendingConfigEvents: Boolean;
    function    HasPendingDragEvents: Boolean;
    function    HasPendingDispatchEvents: Boolean;
    procedure   EnqueueWinCmd(ACmd: PfpgOhosWinCmd);   { native 线程入队（取锁），loop 消费 }
    procedure   ProcessQueuedWindowCommands;           { loop 线程消费窗口命令队列 }
    procedure   UnsetCaretOnWindowInvalid;             { 窗口/buffer 失效时解除 caret（防悬空 blink）}
    procedure   ProcessQueuedEvents;
    procedure   ProcessQueuedKeyEvents;
    procedure   ProcessQueuedResizeEvents;
    procedure   ProcessQueuedTrayEvents;
    procedure   ProcessQueuedConfigEvents;
    procedure   EnqueueTextEvent(const AText: string);
    procedure   EnqueueDeleteEvent(AKind, ACount: Integer);
    procedure   EnqueueMoveCursorEvent(ADirection: Integer);
    procedure   UpdateKeyboardVisibility;
    procedure   ProcessDragEvents;          { enter/move/leave 消费：驱动 TfpgOhosDrop }
    procedure   EnsureDropSession(AWinHandle: TfpgWinHandle; const ASummaryJson: string);
    procedure   PumpEvents(ATimeoutMs: Integer);  { 拖拽泵循环入口（包装 DoWaitWindowMessage）}
    function    FindWindowByHandle(AHandle: TfpgWinHandle): TfpgWindowBase;
    function    FindHandleByWindow(AWindow: TfpgWindowBase): TfpgWinHandle;
    function    HitTestWindow(AGlobalX, AGlobalY: Integer): TfpgWindowBase;
  public
    procedure   EnqueueTouchEvent(AX, AY: Integer; AAction: Integer; AWinHandle: TfpgWinHandle);
    procedure   EnqueueKeyEvent(AKeyCode, AAction, AModifiers: Integer; AUnicodeChar: LongWord);
    procedure   EnqueueMouseEvent(AX, AY: Integer; AAction: Integer; AWinHandle: TfpgWinHandle; AButton: Integer);
    procedure   EnqueueWheelEvent(AX, AY: Integer; ADelta: Integer; AWinHandle: TfpgWinHandle);
    procedure   EnqueueHoverEvent(AX, AY: Integer; AWinHandle: TfpgWinHandle);
    procedure   EnqueueResizeEvent(AWinHandle: TfpgWinHandle; AWidth, AHeight: Integer);
    procedure   EnqueueTrayEvent(AEventType: Integer; const AMenuId: string);
    procedure   EnqueueConfigurationEvent(const AConfig: string);
    procedure   EnqueueLaunchParamsEvent(const APayload: string);
    procedure   EnqueueDragEvent(AWinHandle: TfpgWinHandle; AKind, AX, AY: Integer; const ASummary: string);
    procedure   RegisterWindowHandle(AHandle: TfpgWinHandle; AWindow: TfpgWindowBase);
    procedure   UnregisterWindowHandle(AHandle: TfpgWinHandle);
    procedure   ScheduleRepaintHelper(AWin: TfpgWinHandle);
    procedure   CancelRepaintHelper(AWin: TfpgWinHandle);
    procedure   CheckRepaintHelper;
  protected
    function    DoGetFontFaceList: TStringList; override;
    procedure   DoWaitWindowMessage(atimeoutms: integer); override;
    function    MessagesPending: boolean; override;
    procedure   DoFlush; override;
    function    GetMonitorCount: Integer; override;
    function    GetMonitorInfo(AIndex: Integer): TfpgScreenInfo; override;
    function    GetCmdLineParamsInterface: ICmdLineParams; override;
  public
    constructor Create(const AParams: string); override;
    destructor  Destroy; override;
    procedure   SetScreenSize(AWidth, AHeight: TfpgCoord; ADpi: Integer);
    function    GetScreenWidth: TfpgCoord; override;
    function    GetScreenHeight: TfpgCoord; override;
    function    GetScreenPixelColor(APos: TPoint): TfpgColor; override;
    function    Screen_dpi_x: integer; override;
    function    Screen_dpi_y: integer; override;
    function    Screen_dpi: integer; override;
  end;

{ TfpgOhosClipboard }

  TfpgOhosClipboard = class(TfpgClipboardBase)
  protected
    function    DoGetText: TfpgString; override;
    procedure   DoSetText(const AValue: TfpgString); override;
    procedure   InitClipboard; override;
  end;

{ TfpgOhosFileList }

  TfpgOhosFileList = class(TfpgFileListBase)
  protected
    procedure PopulateSpecialDirs(const aDirectory: TfpgString); override;
  public
    function  ReadDirectory(const aDirectory: TfpgString = ''): boolean; override;
  end;

{ TfpgOhosMimeData }

  TfpgOhosMimeData = class(TfpgMimeDataBase)
  end;

{ TfpgOhosDrag }

  TfpgOhosDrag = class(TfpgDragBase)
  public
    function    Execute(const ADropActions: TfpgDropActions; const ADefaultAction: TfpgDropAction = daCopy): TfpgDropAction; override;
    { drop 侧按 MimeChoice 读源数据（TfpgDragBase.FMimeData 为 protected）}
    function    GetMimeData: TfpgMimeDataBase;
  end;

{ TfpgOhosDrop }

  TfpgOhosDrop = class(TfpgDropBase)
  private
    FDropAction: TfpgDropAction;   { 当前协商动作（daCopy/daMove/...）}
  protected
    function    GetDropAction: TfpgDropAction; override;
    procedure   SetDropAction(AValue: TfpgDropAction); override;
    function    GetWindowForDrop: TfpgWindowBase; override;
    procedure   DataDropComplete; override;
  public
    constructor Create(AWindow: TfpgWindowBase);
    { ETS getSummary（enter）→ Mimetypes 列表（{"types":[{"utd":"...","mime":"text/plain"},...]}）}
    procedure LoadMimeTypesFromSummary(const ASummaryJson: string);
    { drop 兜底：从 records JSON 的 type 字段推导 mime（enter 的 summary 映射失败时）}
    procedure LoadMimeTypesFromRecords(const ARecordsJson: string);
    { 应用内拖拽兜底：从源 MimeData.Formats 填充 Mimetypes（summary 缺失时）}
    procedure LoadMimeTypesFromSource;
    { 跨应用 drop：records JSON → FDropData（应用内拖拽由 DataDropComplete 读源）}
    procedure SetDropDataFromRecords(const ARecordsJson: string);
    { 应用内拖拽源控件（TfpgDropBase.FSourceWidget 为 protected）}
    procedure SetSourceWidget(AWidget: TfpgWidgetBase);
    { 拖入位置更新（包装 protected SetPosition——引擎路由 Enter/Move/Accept）}
    procedure HandlePosition(AX, AY: Integer);
    { 拖入离开（包装 TargetWidget := nil——触发核心 Leave 通知）}
    procedure HandleLeave;
    { 最终落下：定位 + DataDropComplete + 回填应答（accept/action 到 gDragSession）}
    procedure HandleDrop(AX, AY: Integer);   { AX/AY = 窗口客户区逻辑坐标（调用方已换算）}
    { 应答状态（loop 线程 drop 命令读取）}
    function  DropAccepted: Boolean;
  end;

{ TfpgOhosTimer }

  TfpgOhosTimer = class(TfpgBaseTimer)
  protected
    { 感知活动计时计数：任何定时器 启用/停用 翻转 → NotifyTimerActiveChanged。
      Interval 后续修改走框架私有 SetInterval（无法 override），不通知——
      ETS tick 恒跑直至全部禁用（够用）。 }
    procedure SetEnabled(const AValue: boolean); override;
  end;

{ TfpgOhosSystemTrayIcon }

  TfpgOhosTrayEventProc = procedure(evType: Integer; const MenuId: string) of object;

  TfpgOhosSystemTrayIcon = class(TfpgSystemTrayHandlerBase)
  private
    FActive: Boolean;              { ETS 托盘 add 成功（evType=3 'ok'）}
    FMenuIndex: TList;             { TfpgMenuItem 列表，按菜单 JSON id 顺序（'m0'..'mN'）}
    procedure   SyncMenu;          { 序列化 Owner.PopupMenu → ohos_tray_set_menu }
    procedure   HandleTrayEvent(evType: Integer; const MenuId: string);
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;
    procedure   Show; override;
    procedure   Hide; override;
    function    IsSystemTrayAvailable: boolean; override;
    function    SupportsMessages: boolean; override;
  end;

  { 首帧通知：窗口第一次成功上屏（FlushBuffer）后告知 ETS 打开 XComponent 显示门，
    消除"窗口 show → 首帧 flush 之间 XComponent 黑屏闪现"（v12 经桥接表装载）}
  TNotifyFirstFrame = procedure(AHandle: Pointer); cdecl;
  
  { Pascal → C++：Pascal 导出函数表（C++ 填充输入，Pascal 填充输出）}
  TOHOSExportTable = record
    version: Integer;
    set_screen_size: Pointer;
    set_zoom_scale: Pointer;
    inject_touch_to_window: Pointer;
    inject_key_event: Pointer;
    inject_mouse_event: Pointer;
    inject_wheel_event: Pointer;
    inject_hover_event: Pointer;
    inject_text: Pointer;
    inject_delete_chars: Pointer;
    inject_delete_right_chars: Pointer;
    inject_move_cursor: Pointer;
    inject_window_resized: Pointer;
    inject_window_moved: Pointer;
    inject_window_closed: Pointer;
    can_close: Pointer;
    force_window_refresh: Pointer;
    inject_tray_event: Pointer;         { 托盘事件注入 }
    update_configuration: Pointer;      { 系统 Configuration 变更（紧凑 KV）}
    set_launch_params: Pointer;         { 启动载荷 JSON（want.uri/action/entities/parameters 全量）}
    inject_app_args: Pointer;
    timer_tick: Pointer;                { 定时器 ArkUI tick 注入 }
    timer_query: Pointer;               { 定时器活跃态查询 }
    inject_drag_event: Pointer;         { 系统拖拽 enter/move/leave }
    drag_process_drop: Pointer;         { drop 同步应答 (accept<<8)|action }
    inject_drag_end: Pointer;           { 拖拽会话结束 }
    { v6：动态分发入口（Pascal 实现，C++ 消费）}
    dispatch: Pointer;                  { fpgui_dispatch_entry(op,params): PChar }
    { v7：释放 dispatch 返回的 PChar }
    dispatch_free: Pointer;             { fpgui_dispatch_free(p: PChar) }
    file_picker_result: Pointer;        { 系统文件选择器结果回传 (reqId: Integer; resultJson: PChar) cdecl }
    file_io_result: Pointer;            { 文件IO回传 }
    arkts_invoke_result: Pointer;       { v13: procedure(callId,resultJson: PChar; failed: Integer); cdecl }
  end;

  { C++ → Pascal：LIBfp_Bridge 实现的所有回调 (供 pascall 调用，以后的添加可以不动此表，直接 LibBridgeSym 动态加载) }
  TOHOSBridgeCallbacks = record
    version: Integer;
    create_window: Pointer;
    destroy_window: Pointer;
    resize_window: Pointer;
    move_window: Pointer;
    set_window_visible: Pointer;
    set_modal_window: Pointer;
    set_pointer_style: Pointer;
    shake_window: Pointer;
    show_keyboard: Pointer;
    clipboard_set_text: Pointer;
    clipboard_get_text: Pointer;
    get_user_dir: Pointer;
    get_main_window_decoration: Pointer;
    get_window_decoration: Pointer;     { per-window dec（vp），弹窗定位补偿 }
    drag_start: Pointer;                { 系统拖拽：起拖，同步返回 sessionId }
    set_dnd_enabled: Pointer;           { 系统拖拽：窗口拖入开关 }
    set_window_state: Pointer;          { 0=normal 1=minimized 2=maximized }
    set_window_opacity: Pointer;        { 窗口透明度（×1000 整数透传）}
    set_window_title: Pointer;       { 窗口标题，运行时修改 }
    set_window_attributes: Pointer;     { 窗口属性位掩码 }
    tray_add: Pointer;                  { void(const char* title, int iconIndex) }
    tray_set_menu: Pointer;             { void(const char* json) }
    tray_remove: Pointer;               { void(void) }
    { v6：动态分发结果回传（C++ 实现，Pascal 消费）}
    dispatch_result: Pointer;           { void(jobId,resultJson,failed) }
    get_window_state: Pointer;          { int32_t(*)(void* handle)（v10 查询缓存的窗口状态）}
    open_url: Pointer;                  { void(*)(const char* url)（v11 打开 URL/文档）}
    { v12：首帧上屏通知（Pascal FlushBuffer 成功后调用；ETS 打开 XComponent 显示门）}
    notify_first_frame: Pointer;        { void(*)(void* handle) }
    show_file_picker: Pointer;			{ 文件选择器 }
    file_io: Pointer;
    arkts_invoke: Pointer;                { v13: function(callId,method,params: PChar): Integer; cdecl }
  end;

var
  pascalApi: TOHOSExportTable;
  cppApi: TOHOSBridgeCallbacks;

{ 反向桥接连接（LIB_fpgBridge）：向 fp_bridge_init 传入本方函数表、取回 C++ 函数表。
  必须在 fpgApplication.Initialize 完成之后由应用 MainProc 显式调用（幂等）。
  ⚠ 不可在 TfpgOhosApplication.Create 内调用：fpgApplication 惰性单例在 Create
  期间为 nil，connect 的回调链会触发 getter 递归 Create（栈溢出）。 }
procedure ohos_bridge_connect;

{ 首帧上屏通知（供 Agg2D 独立画布路径如 TAgg2D.DoPutBufferToScreen 调用）：
  同一窗口句柄仅通知一次；FlushBuffer 成功后经 C++ notify_first_frame 下发
  NATIVE_CMD_FIRST_FRAME，ETS 打开 XComponent 显示门（contentReady）。
  句柄变化（hide→show 重建 surface）自动重置，允许再次通知。 }
procedure OhosNotifyFirstFrame(AWinHandle: TfpgWinHandle);

{ Wraps fpgDeliverMessages with exception capture so a single failing
  message (e.g. fast typing) is logged instead of aborting the process. }
procedure SafeDeliverMessages;

function TryLoadSystemTypeface(var APath: string; AIsBold, AIsItalic: Boolean;
  const AFaceName: string = ''): POH_Drawing_Typeface;
{ FontMgr 家族枚举兜底：家族名含 'emoji'（大小写无关）→ 创建 typeface。
  系统字体只允许经 FontMgr 家族接口使用，禁止按路径读取系统字体文件。 }
function TryLoadEmojiTypeface(var APath: string): POH_Drawing_Typeface;

{ 惰性探测缓存：每个路径首次 FileExists 后记录结果（避免每字体资源创建重复 IO） }
function OhosFontExists(const APath: string): Boolean;
{ 字体名/相对路径 → 应用沙箱内首个存在的完整路径（''=未找到）。
  仅搜索应用自有目录：CWD(=resfile/resourceDir)、Context.resourceDir、
  Context.filesDir(+fonts/)、bundleCodeDir/libs/<abi>；系统目录不按路径读。 }
function OhosFindFontFile(const AName: string): string;
{ 按序解析候选（绝对路径直接探测；相对名走 OhosFindFontFile） }
function OhosResolveFontFile(const ACandidates: array of string): string;
{ fpGUI 默认家族（'Sans' 等）→ 鸿蒙中文默认家族（SC 存在优先，否则 Sans） }
function OhosMapDefaultFaceName(const AFaceName: string): string;

var
  OnOhosTouch: procedure(x, y: Integer) = nil;
  { 托盘事件全局回调（TfpgOhosSystemTrayIcon 构造时注册）：
    evType 0=click, 1=rightClick, 2=menuItem(menuId), 3=addResult('ok'/'fail') }
  OnOhosTray: TfpgOhosTrayEventProc = nil;
  { 启动载荷 JSON 应用层事件（冷启动 argv / 热启动 set_launch_params 均触发）：
    框架层只存 gLaunchParams 并回调本事件，JSON 解析由应用完成。 }
  OnOhosLaunchParams: procedure(const APayload: string) = nil;
  { ETS 托盘 add 成功标志（evType=3 'ok' 时置真）——IsSystemTrayAvailable 真实化 }
  gTrayActive: Boolean = False;
  gOhosScreenW: Integer = 1920;
  gOhosScreenH: Integer = 1080;
  gOhosScreenDpi: Integer = 160;

  { 系统 Configuration 全局（fpGUI 持全局：对比 → 处理 → 更新）。
    数值码对齐 ArkTS ConfigurationConstant：
    colorMode: -1=NOT_SET, 0=DARK, 1=LIGHT；
    direction: -1=NOT_SET, 0=VERTICAL, 1=HORIZONTAL；
    screenDensity 枚举: 120/160/240/320/480/640（0=NOT_SET）。 }
  gCfgLanguage: string = '';          { l   }
  gCfgColorMode: Integer = -1;        { c   }
  gCfgDirection: Integer = -1;        { d   }
  gCfgScreenDensity: Integer = 0;     { denKonf }
  gCfgDensityPixels: Single = 1.0;    { den }
  gCfgDisplayId: Integer = 0;         { i   }
  gCfgHasPointerDevice: Boolean = False; { p }
  gCfgFontId: string = '';            { f   }
  gCfgFontSizeScale: Single = 1.0;    { fs  }
  gCfgFontWeightScale: Single = 1.0;  { fw  }
  gCfgMcc: string = '';               { mcc }
  gCfgMnc: string = '';               { mnc }
  gCfgLocale: string = '';            { lc  }
  gCfgTimeFormat: string = '';        { tf  '12'/'24'，仅存储（启动读一次，无观察者） }
  gCfgDateFormat: string = '';        { df  'mm/dd/yyyy'|'dd/mm/yyyy'|'yyyy/mm/dd'，仅存储 }

  { 最近一次 FPGM_OHOS_CONFIG_CHANGED 消息的变更位集合（常量见 interface const 区）}
  gCfgChangedFlags: LongWord = 0;

  { 定时器 ArkUI 注入驱动：活动 Enabled 定时器计数与上抛去重。
    gTimerNotified 语义：ETS 侧当前感知的 tick 活跃态（初始 False=停）——
    仅"翻转"时上抛，避免无谓跨线程通知。 }
  gTimerActiveCount: Integer = 0;
  gTimerNotified: Boolean = False;

  // 用户缩放倍数
  gZoomScale: Single = 1.0;              

  gHiDPI: Integer = 96; 		 // Uniform scale (fallback) = physicalDpi/96.
  gScaleFactor: Single = 1.0;    // Window scale = densityPixels (physicalDpi/160). C++ API may override.
  gScaleFactorX: Single = 1.0;   // X scale = xDpi/96. Used for bitmap width, CanvasScale X.
  gScaleFactorY: Single = 1.0;   // Y scale = yDpi/96. Used for bitmap height, CanvasScale Y.

  gHiDPIScaleFactor: Double = 1.0;  // AggPas canvas (=gScaleFactorX)

{ Keyboard modifier state — tracked from key events since ETS passes 0 }
  gShiftPressed: Boolean = False;
  gCtrlPressed: Boolean = False;
  gAltPressed: Boolean = False;

{ Last pressed-and-not-yet-released mouse button (0=none). MOVE events use
  this state instead of the injected button value: a hover move (no button
  pressed) must NOT look like a left-button drag to widgets (which would
  start text selection without any click). }
  gLastDownButton: Integer = 0;

{ MOUSEDOWN dedup: the emulator fires BOTH onTouch Down and onMouse Press
  for a single click (<10ms apart). Two MOUSEDOWNs toggle MenuBar's
  FClicked twice -> popup opens and instantly closes ("flash"). A real
  double-click's two DOWNs are >150ms apart, so 50ms is safe. }
  gLastDownTick: QWord = 0;
  gLastDownWin: TfpgWinHandle = nil;
  { Delivery window for UP routing — stored as HANDLE + cached origin rect.
    NEVER store the window object pointer here: the popup submenu window can
    be destroyed (menu dismissed) between the DOWN and the UP, leaving a
    dangling pointer that would crash the dispatcher at msg.Dest.Dispatch. }
  gLastDownTargetWin: TfpgWinHandle = nil;
  gLastDownTargetLeft: Integer = 0;
  gLastDownTargetTop: Integer = 0;
  gLastDownGlobX: Integer = 0;   { resolved global point of last DOWN }
  gLastDownGlobY: Integer = 0;

{ Last resolved pointer position (global screen coords). Unified basis:
  ETS reports displayX/displayY (absolute screen) for every window, so the
  injected coordinate IS the global point. }
  gCursorX: Integer = 0;
  gCursorY: Integer = 0;
  gCursorValid: Boolean = False;

{ Modal window tracking — events for non-modal windows are dropped }
  gModalWinHandle: TfpgWinHandle = nil;

{ Last focused window handle — tracked for keyboard routing to popup windows }
  gFocusedWinHandle: TfpgWinHandle = nil;

{ In-process clipboard buffer — used when C++ bridge does not provide
  ohos_clipboard_set/get_text. Allocated/freed by Pascal's memory manager,
  so FreeMem matches GetMem. }
  OHOSClipboardBuf: string = '';

{ OHOS command-line args — injected by C++ PascalThread from ETS APP_ARGS + want.parameters['fpArgs'].
  Space-separated format: "-b debug key=value". Consumed by TfpgOhosCmdLineParams. }
  OhosArgs: string = '';
  { 最近一次启动载荷 JSON 原文 }
  gLaunchParams: string = '';

  { true = ohos_bridge_connect 已成功调用（此后 LibBridgeSym 兜底不再需要）}
  gBridgeInitialized: Boolean = False;
  
  gDispatchEntry: function(opType, params: PChar): PChar; cdecl = nil;
  gDispatchFree: procedure(p: PChar); cdecl = nil;
  gDispatchPump: procedure = nil;
  gDispatchHasPending: function: Boolean = nil;
  gDispatchUIThreadId: procedure(AId: TThreadID) = nil;
  
  { 首帧上屏通知（Pascal→C++→ETS；ohos_bridge_connect 经桥接表装载）}
  _notify_first_frame: TNotifyFirstFrame = nil;

//返回只读 resfile 目录（OHOS:`resourceDir/resfile/`） 
function GetResfileDir: string;
//返回安装包根目录（OHOS:`bundleCodeDir`，.so 同级 libs 的父目录）
function GetBundleCodeDir: string;
//返回可写 rawfile 目录（OHOS:`filesDir/rawfile/`） 
function GetRawfileDir: string;
//确保 rawfile 目录的子目录存在(创建），返回完整路径 
function EnsureRawfileDir(const ASubDir: string = ''): string;
//从 resfile 复制单个文件到 rawfile（覆盖） 
function ResFileToRaw(const AFileName: string; const ADestSubDir: string = ''): Boolean;
//递归复制 resfile/fonts → rawfile/fonts，返回文件数
function ResDirToRaw(const ASrcSubDir: string = ''; const ADestSubDir: string = ''): Integer;

{ IMPORTANT: FPC only exports global functions that are declared in the
  INTERFACE section. Implementation-only functions are NOT visible to
  dlsym from libentry.so — these must be declared here. }
procedure ohos_set_screen_size(w, h, dpi: Integer; density: Single); cdecl; export;
function ohos_inject_touch_event(x, y: Single; action: Integer): Integer; cdecl; export;
function ohos_inject_touch_to_window(winHandle: TfpgWinHandle; x, y: Single; action: Integer): Integer; cdecl; export;
function ohos_inject_key_event(keyCode, action, modifiers: Integer; unicodeChar: LongWord): Integer; cdecl; export;
function ohos_inject_mouse_event(winHandle: TfpgWinHandle; x, y: Single; action, button: Integer): Integer; cdecl; export;
function ohos_inject_wheel_event(winHandle: TfpgWinHandle; x, y: Single; delta: Integer): Integer; cdecl; export;
function ohos_inject_hover_event(winHandle: TfpgWinHandle; x, y: Single): Integer; cdecl; export;
procedure ohos_inject_text(text: PChar; len: Integer); cdecl; export;
procedure ohos_show_keyboard(show: Integer); cdecl; export;
{ ETS 主动显示/隐藏软键盘的入口（C++ ShowKeyboard 经 dlsym 调用）：
  仅同步状态/日志，不再 bridge 回 ETS（避免 showIme→showKeyboard→case6→showIme 回环）}
procedure ohos_show_keyboard_from_ets(show: Integer); cdecl; export;
function ohos_inject_delete_chars(ACount: Integer): Integer; cdecl; export;
function ohos_inject_delete_right_chars(ACount: Integer): Integer; cdecl; export;
function ohos_inject_move_cursor(ADirection: Integer): Integer; cdecl; export;
function ohos_inject_window_resized(winHandle: TfpgWinHandle; w, h: Integer): Integer; cdecl; export;
function ohos_inject_window_moved(winHandle: TfpgWinHandle; x, y: Integer): Integer; cdecl; export;
function ohos_inject_window_closed(winHandle: TfpgWinHandle): Integer; cdecl; export;
function ohos_can_close(winHandle: TfpgWinHandle): Integer; cdecl; export;
procedure ohos_force_window_refresh(winHandle: TfpgWinHandle); cdecl; export;
procedure ohos_set_zoom_scale(scale: Single); cdecl; export;
function ohos_clipboard_set_text(text: PChar): Integer; cdecl; export;
function ohos_clipboard_get_text: PChar; cdecl; export;
{ 系统 Configuration 变更（含首启初始化）下发：紧凑 KV 串（k=v;k2=v2;...）.
  fpGUI 持全局：逐字段对比 → 处理 → 更新。C++ 经 bridge update_configuration 调用。 }
procedure ohos_update_configuration(config: PChar); cdecl; export;
{ 启动载荷 JSON 注入（冷启动 argv[1] / 热启动 C++ set_launch_params 调用）。
    payload：{"uri","action","entities","parameters"}；框架层只存全局 + 事件回调，
    JSON 解析由应用挂接 OnOhosLaunchParams 完成。 }
procedure ohos_set_launch_params(payload: PChar); cdecl; export;
{ 命令行参数注入（C++ pro()/run() 前调用）：分离 payload 与 appArgs
  payload → gLaunchParams（want JSON）；appArgs → OhosArgs（已替换 %placeholder% 的命令行参数） }
procedure ohos_inject_app_args(payload, appArgs: PChar); cdecl; export;
{ 定时器 ArkUI 注入：
  ohos_timer_tick   —— ETS setInterval 到期经 NAPI 调用，唤醒 select（Signal）→ fpgCheckTimers。
  ohos_timer_query  —— ETS 注册期补查：返回当前是否有活动定时器（防早期通知丢失）。
  两者由 C++ 经 bridge timer_tick/timer_query 调用。 }
procedure ohos_timer_tick(); cdecl; export;
function  ohos_timer_query(): Integer; cdecl; export;
{ 托盘事件注入（C++ OnTrayEvent 经 bridge inject_tray_event 调用）：
  evType 0=click, 1=rightClick, 2=menuItem(menuId), 3=addResult('ok'/'fail') }
function ohos_inject_tray_event(eventType: Integer; menuId: PChar): Integer; cdecl; export;
{ 系统拖拽注入（C++ 经 bridge inject_drag_event/drag_process_drop/inject_drag_end 调用）：
  ohos_inject_drag_event —— enter/move/leave 入队（不阻塞，ETS UI 线程）；
  ohos_drag_process_drop —— drop 同步应答（阻塞 ≤5s，返回 (accept<<8)|action）；
  ohos_inject_drag_end   —— 会话结束（ETS executeDrag 回调，置 EndEvent+唤醒）。 }
function ohos_inject_drag_event(winHandle: TfpgWinHandle; kind: Integer; x, y: Single; summaryJson: PChar): Integer; cdecl; export;
function ohos_drag_process_drop(winHandle: TfpgWinHandle; x, y: Single; recordsJson: PChar): Integer; cdecl; export;
function ohos_inject_drag_end(sessionId: Int64; AResult: Integer): Integer; cdecl; export;

const
  { ── 系统配置变更消息（OHOS 适配内闭环，与框架消息机制一致）──────────
    链路：ETS onConfigurationUpdate → notifyConfiguration → Pascal
      HandleConfigurationEvent（UI 线程）→ 置 gCfgChangedFlags →
      fpgPostMessage(主窗体, FPGM_OHOS_CONFIG_CHANGED)。
    主窗体 override DefaultHandler 接收（与其他 OS 消息模型一致）：
      msg.Params.user.Param1 = CFG_CHANGED_* 位标志。 }
  FPGM_OHOS_CONFIG_CHANGED = FPGM_USER + 100;  { OHOS 系统配置变更消息 }
  CFG_CHANGED_COLORMODE  = 1 shl 0;   { 主题深浅色 }
  CFG_CHANGED_DIRECTION  = 1 shl 1;   { 横/竖屏 }
  CFG_CHANGED_LANGUAGE   = 1 shl 2;   { 语言 }
  CFG_CHANGED_LOCALE     = 1 shl 3;   { 地区（mcc/mnc/locale）}
  CFG_CHANGED_DENSITY    = 1 shl 4;   { 屏幕密度/缩放 }
  CFG_CHANGED_FONTSCALE  = 1 shl 5;   { 字体缩放 }
  CFG_CHANGED_DISPLAYSZ  = 1 shl 6;   { 屏幕尺寸（旋转重查后）}

  { OHOS 应用内置字体候选（相对名；解析根 = CWD 即 resfile(resourceDir)、
    Context.resourceDir/filesDir、bundleCodeDir/libs/<abi> —— 见
    OhosFindFontFile）。系统字体一律经 FontMgr 家族接口使用（family name），
    禁止按路径读取系统字体文件（/system/fonts 等）。
    注意：系统无独立 Bold 文件——粗体由 FontMgr style 或 fake bold 合成。 }
  OhosCJKFontFiles: array[0..2] of string = (
    'HarmonyOS_Sans_SC.ttf',       { 鸿蒙中文（简）优先（应用 resfile 随包）}
    'HarmonyOS_Sans.ttf',
    'NotoSansCJK-Regular.ttc'
  );
  OhosItalicFontFiles: array[0..1] of string = (
    'HarmonyOS_Sans_Italic.ttf',
    'HarmonyOS_Sans.ttf'
  );
  OhosEmojiFontFiles: array[0..1] of string = (
    'HMOSColorEmojiCompat.ttf',
    'HMOSColorEmojiFlags.ttf'
  );

implementation

uses
  baseunix,
  unix,
  fpg_utils,
  fpg_main,
  fpg_constants,
  fpg_dbugintf,
  fpg_widget,
  fpg_window,      { TfpgWindow.WindowTitle（窗题读取——应用 Create 阶段设置）}
  fpg_trayicon,    { TfpgSystemTrayIcon（托盘 Owner 强转，仅 implementation 层引用，避免循环）}
  fpg_menu,        { TfpgPopupMenu/TfpgMenuItem（托盘菜单序列化）}
//  fpg_ohos_dispatch,{ 动态分发（Registry-Dispatch）：注册表/Job/UI 队列 }
  fpg_form;        { TfpgBaseForm.CloseQuery（标题栏 X 关闭前 CanClose 查询，静态接管原 dlsym 桥）}

{ 前向声明（TfpgOhosApplication.Create 启动期调用，定义在文件后部）}
procedure DumpFontFamilies; forward;
procedure OhosLoadSystemFontConfig; forward;

{ 文本绘制诊断标志（首例 TextBlob 创建结果打印一次）}
var
  gDrawDiagDone: Boolean = False;

{ 系统字体配置（OH_Drawing_GetSystemFontConfigInfo，启动一次）：
  gSystemFontDirs —— 系统上报的字体目录清单（仅启动日志/诊断用途；
    系统字体禁止按路径读取，使用一律经 FontMgr 家族接口）；
  gSystemDefaultFamily —— 系统权威默认家族名（generic familyName）}
var
  gSystemFontDirs: TStringList = nil;
  gSystemDefaultFamily: string = '';
  { 非 OHOS 字体资源兜底 Typeface（TfpgOhosCanvas.DoDrawString 防御路径）：
    进程级单例，首次创建后复用，避免每帧 CreateFromFile/Destroy。 }
  gFallbackTypeface: POH_Drawing_Typeface = nil;
  gFallbackTypefacePath: string = '';

const
  RTLD_DEFAULT = Pointer(-1);
  RTLD_LAZY    = 1;

var
  { Cached handle of LIB_fpgBridge. RTLD_DEFAULT cannot see symbols of a
    shared library loaded with RTLD_LOCAL (the default), so every
    Pascal - C++ bridge lookup must use this explicit handle. }
  _libentry_handle: Pointer = nil;

{ ---------------------------------------------------------------------
   系统拖拽会话（Unified Drag & Drop）
   桥接契约（具名字段，版本号不变）：
     drag_start           (Pascal→C++：起拖，同步返回 sessionId)
     set_dnd_enabled      (Pascal→C++：窗口拖入开关)
     inject_drag_event    (C++→Pascal)
     drag_process_drop    (C++→Pascal)
     inject_drag_end      (C++→Pascal)
   --------------------------------------------------------------------- }
type
  TOHOSDragStart     = function(dataJson, extraJson: PChar): Int64; cdecl;
  TOHOSSetDNDEnabled = procedure(handle: Pointer; enabled: Integer); cdecl;

  { 窗口属性联动桥（Pascal→C++→ETS；set_window_state/opacity/title_to/attributes）}
  TOHOSSetWindowState      = procedure(handle: Pointer; state: Integer); cdecl;
  TOHOSSetWindowOpacity    = procedure(handle: Pointer; opacity: Single); cdecl;
  TOHOSSetWindowTitle      = procedure(handle: Pointer; title: PChar); cdecl;
  TOHOSSetWindowAttributes = procedure(handle: Pointer; attributes: Int32); cdecl;
  TOHOSGetWindowState      = function(handle: Pointer): Integer; cdecl;     { v10 查询缓存的窗口状态 }

  { Touch event injected from C++ native bridge (main thread only) }
  PfpgOhosTouchEvent = ^TfpgOhosTouchEvent;
  TfpgOhosTouchEvent = record
    X, Y: Integer;
    Action: Integer;  { 0=down, 1=move, 2=up }
    WindowHandle: TfpgWinHandle;  { target window for multi-window routing }
    MouseButton: Integer;  { 0=touch, 1=left, 2=right, 3=middle }
    Kind: Integer;         { 0=mouse/touch, 1=wheel, 2=hover }
    WheelDelta: Integer;   { wheel scroll delta (Kind=1) }
  end;

  { Keyboard/IME event injected from C++ native bridge }
  PfpgOhosKeyEvent = ^TfpgOhosKeyEvent;
  TfpgOhosKeyEvent = record
    Kind: Integer;       { 0=key, 1=text, 2=deleteLeft, 3=deleteRight, 4=moveCursor }
    KeyCode: Integer;    { OHOS key code }
    Action: Integer;     { 0=down, 1=up }
    Modifiers: Integer;  { modifier bitmask }
    UnicodeChar: LongWord;  { Unicode codepoint if applicable }
    Count: Integer;      { deleteLeft/deleteRight: number of chars; moveCursor: direction }
    Text: string;        { text event: insert text (UTF-8) }
  end;

  { 系统 Configuration/启动载荷 事件（C++ 线程注入，UI 线程消费）。
    Config 为紧凑 KV 串：k=v;k2=v2;...；值不含 ';' 与 '='。
    Kind: 0=Configuration KV，1=启动载荷 JSON（want.uri/action/entities/parameters） }
  PfpgOhosConfigEvent = ^TfpgOhosConfigEvent;
  TfpgOhosConfigEvent = record
    Kind: Integer;
    Config: string;
  end;

  { Resize event from C++ bridge }
  PfpgOhosResizeEvent = ^TfpgOhosResizeEvent;
  TfpgOhosResizeEvent = record
    WindowHandle: TfpgWinHandle;
    Width: Integer;
    Height: Integer;
  end;

  { Tray event injected from C++ bridge (ETS trayIcon callbacks) }
  PfpgOhosTrayEvent = ^TfpgOhosTrayEvent;
  TfpgOhosTrayEvent = record
    EventType: Integer;  { 0=click, 1=rightClick, 2=menuItem, 3=addResult }
    MenuId: string;      { evType=2: 菜单项 id；evType=3: 'ok'/'fail' }
  end;

  { 拖拽事件（ETS 注入，UI 线程消费；同触摸队列模式）}
  PfpgOhosDragEvent = ^TfpgOhosDragEvent;
  TfpgOhosDragEvent = record
    Kind: Integer;             { 0=enter, 1=move, 2=leave }
    WindowHandle: TfpgWinHandle;
    X, Y: Integer;             { 物理 px（C++ 已 ×g_density）}
    Summary: string;           { getSummary JSON（深拷贝）}
  end;

  { 拖拽会话：Execute 阻塞等待 + drop 应答共享（单会话全局；跨线程经 gDragSessionLock）}
  TfpgOhosDragSession = record
    Active: Boolean;          { 系统拖拽进行中（泵循环退出条件）}
    SessionId: Int64;
    EndEvent: TEvent;         { 拖拽结束事件（ETS dragEnd → SetEvent + WakeChannel）}
    Result: Integer;          { OHOS_DRAG_RESULT_* }
    DragRef: TfpgDragBase;    { 应用内拖拽源引用（drop 时按 MimeChoice 读源数据，X11:1100 同式）}
    { 拖入会话（目标侧）}
    Drop: TfpgOhosDrop;
    DropWinHandle: TfpgWinHandle;   { 当前悬停窗口句柄 }
    { drop 同步应答暂存（native 线程写入 → loop 线程消费）}
    DropX, DropY: Integer;
    DropRecords: string;
    DropAccept: Boolean;
    DropAction: TfpgDropAction;
  end;

const
  { IME event kinds (TfpgOhosKeyEvent.Kind) }
  OHOS_EV_KEY        = 0;
  OHOS_EV_TEXT       = 1;
  OHOS_EV_DELETE_LEFT  = 2;
  OHOS_EV_DELETE_RIGHT = 3;
  OHOS_EV_MOVE_CURSOR  = 4;

  { moveCursor directions (inputMethod.Direction) }
  OHOS_CURSOR_UP    = 1;
  OHOS_CURSOR_DOWN  = 2;
  OHOS_CURSOR_LEFT  = 3;
  OHOS_CURSOR_RIGHT = 4;

  OHOS_DRAG_ENTER = 0;
  OHOS_DRAG_MOVE  = 1;
  OHOS_DRAG_LEAVE = 2;

  OHOS_DRAG_RESULT_FAILED   = 0;
  OHOS_DRAG_RESULT_SUCCESS  = 1;
  OHOS_DRAG_RESULT_CANCELED = 2;

  { ohos_drag_process_drop 应答位打包 }
  OHOS_DROP_ACCEPT_SHIFT = 8;

var
  gDragSession: TfpgOhosDragSession;
  gDragSessionLock: TCriticalSection = nil;

{ ---------------------------------------------------------------------
   统一 Bridge 初始化（ohos_bridge_connect）
   C++ 端（libentry.so）在加载 libhelloworld.so 后、RunLazarus 前调用一次，双向装载全部桥接函数。
   记录布局与 C++ ohos_bridge.h 严格一致（4 字节对齐、全指针字段）。
   --------------------------------------------------------------------- }
const
  OHOS_BRIDGE_VERSION = 13;   { 与 C++ fp_bridge.h 同步；布局或成员变更时 +1
                               （v5：TOHOSExportTable 增 set_launch_params 启动载荷；
                                 v6：增 dispatch 动态分发入口 + dispatch_result 回调；
                                 v7：增 dispatch_free 释放入口返回的 PChar；
                                 v8：TOHOSBridgeCallbacks 增 tray_add/tray_set_menu/tray_remove；
                                 v9：清理废弃字段（inject_touch_event/show_keyboard/clipboard* 从 PascalApi 删除；
                                     get_actual_window_position 从 CppApi 删除）；
                                 v10：TOHOSBridgeCallbacks 增 get_window_state（查询缓存窗口状态）；
                                 v11：TOHOSBridgeCallbacks 增 open_url（打开 URL/文档）；
                                 v12：TOHOSBridgeCallbacks 增 notify_first_frame（首帧上屏通知，
                                     消除"窗口 show → 首帧 flush 之间 XComponent 黑屏闪现"）；
                                 v13：TOHOSExportTable 增 arkts_invoke_result（Pascal→ArkTS 结果回传）；
                                      TOHOSBridgeCallbacks 增 arkts_invoke（反向调用入口）） }

  { 动态分发异步作业超时（毫秒）。设为 0 表示禁用超时处理（不做超时回收）。 }
  OHOS_DISPATCH_TIMEOUT_MS = 30000;
  OHOS_DISPATCH_MAX_ASYNC  = 4;   { 异步并发上限 }

{ Resolve a symbol exported by LIB_fpgBridge (C++ bridge) via explicit handle. }
function LibBridgeSym(const AName: PChar): Pointer;
begin
  Result := nil;
  if _libentry_handle = nil then
    _libentry_handle := dlopen(LIB_fpgBridge, RTLD_LAZY);
  if _libentry_handle <> nil then
    Result := dlsym(_libentry_handle, AName);
end;

{ Forward declarations }
procedure _OhosWakeMainThread(Sender: TObject); forward;
function UnicodeCodepointToUTF8(cp: UInt32): string; forward;

// Multi-window bridge: function pointers set by C++ bootstrap via SetBridgeFunctions
type
  {$packrecords C}
  TOHOSWindowOptions = record
    windowType: Int32;
    windowAttributes: Int32;
    windowState: Int32;
    isMainform: Int32;
    mouseCursor: Int32;
    opacity: Single;
    left: Int32;
    top: Int32;
    width: Int32;
    height: Int32;
    title: array[0..255] of AnsiChar;
    SurfaceID: UInt64;
  end;
  {$packrecords default}
  POHOSWindowOptions = ^TOHOSWindowOptions;

  TOHOSCreateWindow = function(opts: POHOSWindowOptions): Pointer; cdecl;
  TOHOSDestroyWindow = procedure(handle: Pointer); cdecl;
  TOHOSResizeWindow = procedure(handle: Pointer; w, h: Integer); cdecl;
  TOHOSMoveWindow = procedure(handle: Pointer; x, y: Integer); cdecl;
  TOHOSSetWindowVisible = procedure(handle: Pointer; visible: Integer); cdecl;

{ Clipboard bridge — loaded dynamically from libhelloworld.so }
  TClipboardSetText = function(AText: PChar): Integer; cdecl;
  TClipboardGetText = function: PChar; cdecl;

{ 系统托盘 bridge — C++ ohos_tray_add/set_menu/remove（LibBridgeSym 懒加载）}
  TOHOSTrayAdd     = procedure(title: PChar; iconIndex: Integer); cdecl;
  TOHOSTraySetMenu = procedure(json: PChar); cdecl;
  TOHOSTrayRemove  = procedure; cdecl;

{ File system path bridge }
  TGetUserDir = function(dirType: Integer): PChar; cdecl;

{ Get main window decoration offset (title bar + frame) }
  TGetMainWindowDecoration = procedure(var decW, decH: Integer); cdecl;
  { 按窗口句柄返回装饰偏移（vp）——bridge get_window_decoration（per-window 弹窗定位补偿） }
  TGetWindowDecoration = procedure(handle: Pointer; var decW, decH: Integer); cdecl;

{ Cursor style bridge , per-window 光标（Pascal 传窗口句柄；nil=主窗回退）}
  TSetPointerStyle = function(AWinHandle: Pointer; AStyle: Integer): Integer; cdecl;

{ Modal window bridge }
  TSetModalWindow = procedure(AHandle: Pointer); cdecl;
  TShakeWindow = procedure(AHandle: Pointer); cdecl;

var
  _ohos_create_window: TOHOSCreateWindow = nil;
  _ohos_destroy_window: TOHOSDestroyWindow = nil;
  _ohos_resize_window: TOHOSResizeWindow = nil;
  _ohos_move_window: TOHOSMoveWindow = nil;
  _ohos_set_window_visible: TOHOSSetWindowVisible = nil;

  _clipboard_set_text: TClipboardSetText = nil;
  _clipboard_get_text: TClipboardGetText = nil;

  { 系统托盘 bridge 函数指针（LibBridgeSym 懒加载，桥接成功后直接装载）}
  _ohos_tray_add: TOHOSTrayAdd = nil;
  _ohos_tray_set_menu: TOHOSTraySetMenu = nil;
  _ohos_tray_remove: TOHOSTrayRemove = nil;

  _get_user_dir: TGetUserDir = nil;
  _set_pointer_style: TSetPointerStyle = nil;
  _set_modal_window: TSetModalWindow = nil;
  _shake_window: TShakeWindow = nil;
  
  _ohos_drag_start: TOHOSDragStart = nil;
  _ohos_set_dnd_enabled: TOHOSSetDNDEnabled = nil;
  _ohos_set_window_state: TOHOSSetWindowState = nil;
  _ohos_set_window_opacity: TOHOSSetWindowOpacity = nil;
  _ohos_set_window_title: TOHOSSetWindowTitle = nil;
  _ohos_set_window_attributes: TOHOSSetWindowAttributes = nil;
  _ohos_get_window_state: TOHOSGetWindowState = nil;                         { v10 }
//  _ohos_open_url: TOHOSOpenURL = nil;                                        { v11 }
//  _arkts_invoke: TArkTsInvokeFn = nil;                                       { v13 }

  _ohos_get_main_window_decoration: TGetMainWindowDecoration = nil;
  _ohos_get_window_decoration: TGetWindowDecoration = nil;   { bridge get_window_decoration }

  { C++ 侧软键盘显示回调（由 ohos_bridge_connect 装载；dlsym 兜底）}
  _ohos_show_keyboard_bridge: procedure(show: Integer); cdecl = nil;

  { 定时器活跃态通知（Pascal→C++→ETS）：LibBridgeSym 懒加载（ohos_send_timer_state）}
  _ohos_send_timer_state: procedure(active: Integer); cdecl = nil;

{ 反向桥接入口类型（与 C++ fp_bridge.h 严格一致）：
  ⚠ 必须用显式指针参数——FPC cdecl 下 `const` 记录参数按值传递（拷到栈上），
  会错位为 rsi=&cppApi，导致 C++ 端版本校验失败。旧桥用 constref 是对的。 }
type
  POHOSExportTable = ^TOHOSExportTable;
  POHOSBridgeCallbacks = ^TOHOSBridgeCallbacks;
  TFpBridgeInitFn = function(version: Integer; pascalApi: POHOSExportTable;
    cppApi: POHOSBridgeCallbacks): Integer; cdecl;

{ 向 LIB_fpgBridge 建立桥接（反向）：
  ① 传入本方函数表（与 ohos_bridge_connect 的 AExports 填充完全一致）
  ② 取回 C++ 函数表，装载到 _ohos_* 全局
  ③ fp_bridge_init 内部同步完成显示预初始化（set_screen_size/配置）
  幂等：gBridgeInitialized 为真时直接返回。
  由 单元初始化节 自动调用；也可显式调用（安全）。 }
procedure ohos_bridge_connect;
var
  h: Pointer;
  fn: TFpBridgeInitFn;
  //pascalApi: TOHOSExportTable;
  //cppApi: TOHOSBridgeCallbacks;
  p: PChar;
  fpgSearchPath: string;
begin
  //if gBridgeInitialized then Exit;

  h := dlopen(LIB_fpgBridge, RTLD_LAZY);
  if h = nil then
  begin
    fpGUI_Hilog(LOG_ERROR, 'fp_Bridge: dlopen libfp_bridge failed');
    Exit;
  end;
  fn := TFpBridgeInitFn(dlsym(h, 'fp_bridge_init'));
  if fn = nil then
  begin
    fpGUI_Hilog(LOG_ERROR, 'fp_bridge: fp_bridge_init not found');
    Exit;
  end;
  { Pascal → C++：本方函数表填充（与 ohos_bridge_connect 的 AExports 一致）}
  if not gBridgeInitialized then FillChar(pascalApi, SizeOf(pascalApi), 0);
  pascalApi.version                   := OHOS_BRIDGE_VERSION;
  pascalApi.set_screen_size           := @ohos_set_screen_size;
  pascalApi.set_zoom_scale            := @ohos_set_zoom_scale;
  pascalApi.inject_touch_to_window    := @ohos_inject_touch_to_window;
  pascalApi.inject_key_event          := @ohos_inject_key_event;
  pascalApi.inject_mouse_event        := @ohos_inject_mouse_event;
  pascalApi.inject_wheel_event        := @ohos_inject_wheel_event;
  pascalApi.inject_hover_event        := @ohos_inject_hover_event;
  pascalApi.inject_text               := @ohos_inject_text;
  pascalApi.inject_delete_chars       := @ohos_inject_delete_chars;
  pascalApi.inject_delete_right_chars := @ohos_inject_delete_right_chars;
  pascalApi.inject_move_cursor        := @ohos_inject_move_cursor;
  pascalApi.inject_window_resized     := @ohos_inject_window_resized;
  pascalApi.inject_window_moved       := @ohos_inject_window_moved;
  pascalApi.inject_window_closed      := @ohos_inject_window_closed;
  pascalApi.can_close                 := @ohos_can_close;
  pascalApi.force_window_refresh      := @ohos_force_window_refresh;
  pascalApi.inject_tray_event        := @ohos_inject_tray_event;
  pascalApi.update_configuration     := @ohos_update_configuration;
  pascalApi.set_launch_params        := @ohos_set_launch_params;
  pascalApi.inject_app_args          := @ohos_inject_app_args;
  pascalApi.timer_tick               := @ohos_timer_tick;
  pascalApi.timer_query              := @ohos_timer_query;
  pascalApi.inject_drag_event        := @ohos_inject_drag_event;
  pascalApi.drag_process_drop        := @ohos_drag_process_drop;
  pascalApi.inject_drag_end          := @ohos_inject_drag_end;
//  pascalApi.dispatch                 := @fpgui_dispatch_entry;    { v6 动态分发入口 }
//  pascalApi.dispatch_free            := @fpgui_dispatch_free;     { v7 释放入口返回的 PChar }
  { 系统文件选择器结果回传（扩展单元晚注册，通常为 nil）}
//  pascalApi.file_picker_result       := OhosFilePickerResultCallback;
  { 调用 C++ 端 fp_bridge_init：传入本方表，取回 C++ 表 }
  FillChar(cppApi, SizeOf(cppApi), 0);
  if fn(OHOS_BRIDGE_VERSION, @pascalApi, @cppApi) <> 0 then
  begin
    fpGUI_Hilog(LOG_ERROR, 'fp_bridge: fp_bridge_init failed (version mismatch)');
    Exit;
  end;
  { C++ → Pascal：回调装载（与 ohos_bridge_connect 的装载一致，16 命名 + 7 扩展）}
  Pointer(_ohos_create_window)              := cppApi.create_window;
  Pointer(_ohos_destroy_window)             := cppApi.destroy_window;
  Pointer(_ohos_resize_window)              := cppApi.resize_window;
  Pointer(_ohos_move_window)                := cppApi.move_window;
  Pointer(_ohos_set_window_visible)         := cppApi.set_window_visible;
  Pointer(_set_modal_window)                := cppApi.set_modal_window;
  Pointer(_set_pointer_style)               := cppApi.set_pointer_style;
  Pointer(_shake_window)                    := cppApi.shake_window;
  Pointer(_ohos_show_keyboard_bridge)       := cppApi.show_keyboard;
  Pointer(_clipboard_set_text)              := cppApi.clipboard_set_text;
  Pointer(_clipboard_get_text)              := cppApi.clipboard_get_text;
  Pointer(_get_user_dir)                    := cppApi.get_user_dir;
  Pointer(_ohos_get_main_window_decoration) := cppApi.get_main_window_decoration;
  Pointer(_ohos_get_window_decoration)      := cppApi.get_window_decoration;
  Pointer(_ohos_drag_start)                 := cppApi.drag_start;
  Pointer(_ohos_set_dnd_enabled)            := cppApi.set_dnd_enabled;
  Pointer(_ohos_set_window_state)           := cppApi.set_window_state;
  Pointer(_ohos_set_window_opacity)         := cppApi.set_window_opacity;
  Pointer(_ohos_set_window_title)           := cppApi.set_window_title;
  Pointer(_ohos_set_window_attributes)      := cppApi.set_window_attributes;
  { v10：查询缓存的窗口状态 }
  Pointer(_ohos_get_window_state)           := cppApi.get_window_state;
//  { v11：打开 URL/文档 }
//  Pointer(_ohos_open_url)                   := cppApi.open_url;
  { v12：首帧上屏通知（Pascal FlushBuffer 成功后 → C++ NATIVE_CMD_FIRST_FRAME → ETS）}
  Pointer(_notify_first_frame)              := cppApi.notify_first_frame;
  { 动态分发结果回传（v6）}
//  _fpgui_dispatch_result                    := TDispatchResultFn(cppApi.dispatch_result);
//  SetDispatchResultSink(@OhosDispatchResultSink);
  { 托盘命令（v8 经桥装载）}
  Pointer(_ohos_tray_add)                   := cppApi.tray_add;
  Pointer(_ohos_tray_set_menu)              := cppApi.tray_set_menu;
  Pointer(_ohos_tray_remove)                := cppApi.tray_remove;
//  { 文件选择器 }
//  pointer(_ohos_show_file_picker)			:= cppApi.show_file_picker;
//  { v13：Pascal → ArkTS 反向调用 }
//  Pointer(_arkts_invoke) := cppApi.arkts_invoke;
  
  gBridgeInitialized := True;
  fpGUI_Hilog(LOG_INFO, format('fp_bridge: connected OK (v%d)', [OHOS_BRIDGE_VERSION]));
end;

{ Agg2D 独立画布路径首帧上屏通知：模块级窗口句柄跟踪（句柄变化重置）。 }
var
  gAggFirstFrameWin: TfpgWinHandle = nil;
  gAggFirstFrameSent: Boolean = False;

procedure OhosNotifyFirstFrame(AWinHandle: TfpgWinHandle);
begin
  if AWinHandle = nil then Exit;
  if AWinHandle <> gAggFirstFrameWin then
  begin
    gAggFirstFrameWin := AWinHandle;
    gAggFirstFrameSent := False;
  end;
  if gAggFirstFrameSent then Exit;
  gAggFirstFrameSent := True;
  fpGUI_Hilog(LOG_INFO, format('PutBuf FIRST OK (AGG): win=%s',
    [IntToHex(PtrUInt(AWinHandle), 8)]));
  if Assigned(_notify_first_frame) then
    _notify_first_frame(AWinHandle);
end;

{ Convert TWindowAttributes set to bitmask for C struct }
function WindowAttributesToInt(attrs: TWindowAttributes): Int32;
var
  attr: TWindowAttribute;
begin
  Result := 0;
  for attr in attrs do
    Result := Result or (1 shl Ord(attr));
end;

// ── 日志辅助 ─────────────────────────────────────────────────────
procedure fpGUI_Hilog(level: Integer; const Msg: String);
var
  buf: array[0..1023] of Char;
begin
  StrPLCopy(buf, Msg, SizeOf(buf) - 1);
  OH_LOG_Print(LOG_APP, level, FP_LOG_DOMAIN, FP_LOG_TAG, '%{public}s', buf);
end;

{ ---------------------------------------------------------------------
  TfpgOhosWakeChannel - uses POSIX pipe to wake the event loop
  --------------------------------------------------------------------- }

type
  TfpgOhosWakeChannel = class(TInterfacedObject, IWakeChannel)
  private
    FPipeFds: array[0..1] of cint;
    FIsOpen: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Open;
    procedure Close;
    procedure Signal;
    procedure Drain;
    function GetPollFd: Integer;
  end;

constructor TfpgOhosWakeChannel.Create;
begin
  inherited Create;
  FPipeFds[0] := -1;
  FPipeFds[1] := -1;
  FIsOpen := False;
end;

destructor TfpgOhosWakeChannel.Destroy;
begin
  if FIsOpen then Close;
  inherited Destroy;
end;

procedure TfpgOhosWakeChannel.Open;
var
  flags: cint;
begin
  if FIsOpen then Exit;
  if fpPipe(FPipeFds) <> 0 then
  begin
    { OHOS sandbox blocks pipe(). Signal/Drain/GetPollFd check FIsOpen first }
    FPipeFds[0] := -1;
    FPipeFds[1] := -1;
    { FIsOpen stays False, so Signal/Drain/GetPollFd all skip }
    Exit;
  end;
  flags := FpFcntl(FPipeFds[0], F_GETFL);
  FpFcntl(FPipeFds[0], F_SETFL, flags or O_NONBLOCK);
  flags := FpFcntl(FPipeFds[1], F_GETFL);
  FpFcntl(FPipeFds[1], F_SETFL, flags or O_NONBLOCK);
  FIsOpen := True;
end;

procedure TfpgOhosWakeChannel.Close;
begin
  if not FIsOpen then Exit;
  FpClose(FPipeFds[0]);
  FpClose(FPipeFds[1]);
  FPipeFds[0] := -1;
  FPipeFds[1] := -1;
  FIsOpen := False;
end;

procedure TfpgOhosWakeChannel.Signal;
var
  buf: Byte;
begin
  if not FIsOpen then Exit;
  buf := 1;
  fpwrite(FPipeFds[1], buf, 1);
end;

procedure TfpgOhosWakeChannel.Drain;
var
  buf: array[0..63] of Byte;
begin
  if not FIsOpen then Exit;
  while FpRead(FPipeFds[0], buf, SizeOf(buf)) > 0 do ;
end;

function TfpgOhosWakeChannel.GetPollFd: Integer;
begin
  Result := FPipeFds[0];
end;

{ ---------------------------------------------------------------------
  Utility: convert fpGUI color (AARRGGBB) to native_drawing color (AARRGGBB)
  Both use the same format, so this is a direct pass-through.
  --------------------------------------------------------------------- }

function ColorToNative(cl: TfpgColor): UInt32;
begin
  // fpGUI AARRGGBB == OH_Drawing ARGB (both use same byte order)
  // fpGUI named colors have alpha=$00 (e.g. $999999), which makes them
  // fully transparent in native_drawing. Force alpha to $FF for opaque.
  if (((cl shr 24) and $FF) = 0) or (((cl shr 24) and $FF) = $80) then
    cl := cl or $FF000000;
  //Result := (cl and $FF00FF00) or ((cl shr 16) and $FF) or ((cl shl 16) and $FF0000);
  Result := cl;
end;

{ Byte length of one UTF-8 code point, given its first byte.
  Used for per-character text rendering/measuring so that caret math
  (which accumulates per-char widths) matches what we actually draw. }
function Utf8CharLen(b: Byte): Integer;
begin
  if b < $80 then
    Result := 1
  else if (b and $E0) = $C0 then
    Result := 2
  else if (b and $F0) = $E0 then
    Result := 3
  else if (b and $F8) = $F0 then
    Result := 4
  else
    Result := 1;
end;

{ ---------------------------------------------------------------------
  TfpgOhosFontResource
  --------------------------------------------------------------------- }
{ 验证 typeface 是否含中文字形（'中' U+4E2D，UTF-8 = E4 B8 AD） }
function TypefaceSupportsChinese(tf: POH_Drawing_Typeface): boolean;
var
  f: POH_Drawing_Font;
  w: Single;
begin
  Result := False;
  if tf = nil then Exit;
  f := OH_Drawing_FontCreate();
  if f = nil then Exit;
  try
    OH_Drawing_FontSetTypeface(f, tf);
    OH_Drawing_FontSetTextSize(f, 32);
    if OH_Drawing_FontMeasureText(f, PChar(#$E4#$B8#$AD), 3,
      TEXT_ENCODING_UTF8, nil, @w) = 0 then
      Result := w > 0;
  finally
    OH_Drawing_FontDestroy(f);
  end;
end;

function TryLoadSystemTypeface(var APath: string; AIsBold, AIsItalic: Boolean;
  const AFaceName: string = ''): POH_Drawing_Typeface;
const
  { 中文家族关键字（小写，包含匹配）：命中即视为含中文字形 }
  CJKKeys: array[0..3] of string = ('cjk', 'sc', 'fallback', 'sourcehan');
var
  mgr: POH_Drawing_FontMgr;
  ss: POH_Drawing_FontStyleSet;
  name: PChar;
  i, j, k, cnt, styleCnt: Int32;
  tf: POH_Drawing_Typeface;
  fam, faceName: string;
begin
  Result := nil;
  { 默认家族归一化：'Sans'/'sans-serif'/'default' → 'HarmonyOS Sans SC'（存在优先） }
  faceName := OhosMapDefaultFaceName(AFaceName);
  mgr := OH_Drawing_FontMgrCreate();
  if mgr = nil then Exit;
  try
    { 0) 按 FontDesc 字体名精确匹配（如 'HarmonyOS Sans SC'/'Arial'） }
    if faceName <> '' then
    begin
      { 精确匹配（含连字符变体：实测 FontMgr 家族名为 'HarmonyOS-Sans' 风格）}
      ss := OH_Drawing_FontMgrMatchFamily(mgr, PChar(faceName));
      if (ss = nil) and (Pos(' ', faceName) > 0) then
        ss := OH_Drawing_FontMgrMatchFamily(mgr,
          PChar(StringReplace(faceName, ' ', '-', [rfReplaceAll])));
      if ss <> nil then
      begin
        styleCnt := OH_Drawing_FontStyleSetCount(ss);
        { 粗体/斜体：Skia FontStyleSet 惯例 regular/bold/italic/bold-italic }
        k := 0;
        if AIsBold then k := 1;
        if AIsItalic then k := 2;
        if AIsBold and AIsItalic then k := 3;
        tf := nil;
        while k < styleCnt do
        begin
          tf := OH_Drawing_FontStyleSetCreateTypeface(ss, k);
          if tf <> nil then Break;
          Inc(k);
        end;
        if (tf = nil) and (k > 0) then
          tf := OH_Drawing_FontStyleSetCreateTypeface(ss, 0);
        OH_Drawing_FontMgrDestroyFontStyleSet(ss);
        if (tf <> nil) and TypefaceSupportsChinese(tf) then
        begin
          APath := 'FontMgr:' + LowerCase(faceName);
          fpGUI_Hilog(LOG_INFO, 'FONT LOADED: family="' + LowerCase(faceName) +
            '" bold=' + IntToStr(Integer(AIsBold)));
          Result := tf;
          Exit;
        end
        else if tf <> nil then
        begin
          { 家族不含中文：释放并继续 }
          OH_Drawing_TypefaceDestroy(tf);
          tf := nil;
        end;
      end;
    end;
    { 1) 枚举全部字体家族，命中中文关键字 → 从该家族创建 typeface }
    cnt := OH_Drawing_FontMgrGetFamilyCount(mgr);
    for i := 0 to cnt - 1 do
    begin
      name := OH_Drawing_FontMgrGetFamilyName(mgr, i);
      fam := LowerCase(StrPas(name));
      OH_Drawing_FontMgrDestroyFamilyName(name);
      for j := 0 to High(CJKKeys) do
      begin
        if Pos(CJKKeys[j], fam) > 0 then
        begin
          ss := OH_Drawing_FontMgrCreateFontStyleSet(mgr, i);
          if ss <> nil then
          begin
            styleCnt := OH_Drawing_FontStyleSetCount(ss);
            { 粗体/斜体：Skia FontStyleSet 惯例 regular/bold/italic/bold-italic }
            k := 0;
            if AIsBold then k := 1;
            if AIsItalic then k := 2;
            if AIsBold and AIsItalic then k := 3;
            tf := nil;
            while k < styleCnt do
            begin
              tf := OH_Drawing_FontStyleSetCreateTypeface(ss, k);
              if tf <> nil then Break;
              Inc(k);
            end;
            if (tf = nil) and (k > 0) then
              tf := OH_Drawing_FontStyleSetCreateTypeface(ss, 0);
            OH_Drawing_FontMgrDestroyFontStyleSet(ss);
            if (tf <> nil) and TypefaceSupportsChinese(tf) then
            begin
              APath := 'FontMgr:' + fam;
              fpGUI_Hilog(LOG_INFO, 'FONT LOADED: family="' + fam + '" bold=' + IntToStr(Integer(AIsBold)));
              Result := tf;
              Exit;
            end
            else if tf <> nil then
            begin
              { 家族不含中文：释放并继续枚举 }
              OH_Drawing_TypefaceDestroy(tf);
              tf := nil;
            end;
          end;
        end;
      end;
    end;
    { 2) 兜底：系统默认 sans-serif }
    ss := OH_Drawing_FontMgrMatchFamily(mgr, 'sans-serif');
    if ss <> nil then
    begin
      tf := OH_Drawing_FontStyleSetCreateTypeface(ss, 0);
      OH_Drawing_FontMgrDestroyFontStyleSet(ss);
      if (tf <> nil) and TypefaceSupportsChinese(tf) then
      begin
        APath := 'FontMgr:sans-serif';
        fpGUI_Hilog(LOG_INFO, 'FONT LOADED: family="sans-serif" bold=' + IntToStr(Integer(AIsBold)));
        Result := tf;
      end
      else if tf <> nil then
        OH_Drawing_TypefaceDestroy(tf);
    end;
  finally
    OH_Drawing_FontMgrDestroy(mgr);
  end;
end;

{ FontMgr 家族枚举：命中含 'emoji' 的家族 → 创建 typeface（官方家族接口，
  不读系统字体文件）。APath 置 'FontMgr:<family>' 供去重/日志。 }
function TryLoadEmojiTypeface(var APath: string): POH_Drawing_Typeface;
var
  mgr: POH_Drawing_FontMgr;
  ss: POH_Drawing_FontStyleSet;
  name: PChar;
  i, cnt: Int32;
  fam: string;
begin
  Result := nil;
  mgr := OH_Drawing_FontMgrCreate();
  if mgr = nil then Exit;
  try
    cnt := OH_Drawing_FontMgrGetFamilyCount(mgr);
    for i := 0 to cnt - 1 do
    begin
      name := OH_Drawing_FontMgrGetFamilyName(mgr, i);
      if name = nil then Continue;
      fam := LowerCase(StrPas(name));
      OH_Drawing_FontMgrDestroyFamilyName(name);
      if Pos('emoji', fam) = 0 then Continue;
      ss := OH_Drawing_FontMgrCreateFontStyleSet(mgr, i);
      if ss <> nil then
      begin
        if OH_Drawing_FontStyleSetCount(ss) > 0 then
          Result := OH_Drawing_FontStyleSetCreateTypeface(ss, 0);
        OH_Drawing_FontMgrDestroyFontStyleSet(ss);
      end;
      if Result <> nil then
      begin
        APath := 'FontMgr:' + fam;
        fpGUI_Hilog(LOG_INFO, 'FONT LOADED: emoji family="' + fam + '"');
        Exit;
      end;
    end;
  finally
    OH_Drawing_FontMgrDestroy(mgr);
  end;
end;

function TryLoadTypeface(var APath: string; AIsBold, AIsItalic: Boolean;
  const AFaceName: string = ''): POH_Drawing_Typeface;
var
  p: string;
  fname: string;
  ttcIdx: Integer;
  hpos: Integer;
  cands: array of string;
begin
  { 应用内置字体文件优先：FontDesc 直接以文件名指定（如 'simsun.ttc#1-12'）时，
    从 resfile/filesDir/libs 解析并按文件创建，优先于系统家族匹配——
    系统 MatchFamily 对未知家族会落到默认比例字体（不可用于等宽需求）。
    '#N' 后缀指定 TTC 集合内索引（如 simsun.ttc#1 = NSimSun 严格等宽）；
    已知名称（'Sans'/'Arial' 等）文件不存在时自然回退系统路径。 }
  if AFaceName <> '' then
  begin
    fname := AFaceName;
    ttcIdx := 0;
    hpos := Pos('#', fname);
    if hpos > 0 then
    begin
      ttcIdx := StrToIntDef(Copy(fname, hpos + 1, MaxInt), 0);
      fname := Copy(fname, 1, hpos - 1);
    end;
    { 候选名同时含小写变体：TfpgFontDefinition.NormalizeFaceName 会把
      'simsun.ttc' 规范为 'Simsun.ttc'，而 Linux 文件系统大小写敏感。 }
    SetLength(cands, 6);
    cands[0] := fname;
    cands[1] := LowerCase(fname);
    cands[2] := fname + '.ttf';
    cands[3] := LowerCase(fname) + '.ttf';
    cands[4] := fname + '.ttc';
    cands[5] := LowerCase(fname) + '.ttc';
    p := OhosResolveFontFile(cands);
    if p <> '' then
    begin
      Result := OH_Drawing_TypefaceCreateFromFile(PChar(p), ttcIdx);
      if Result <> nil then
      begin
        APath := p + '#' + IntToStr(ttcIdx);
        fpGUI_Hilog(LOG_INFO, 'FONT LOADED(app): path="' + p + '" idx=' +
          IntToStr(ttcIdx) + ' bold=' +
          IntToStr(Integer(AIsBold)) + ' italic=' + IntToStr(Integer(AIsItalic)));
        Exit;
      end
      else
        fpGUI_Hilog(LOG_ERROR, 'FONT CREATE FAIL(app): path="' + p + '" idx=' +
          IntToStr(ttcIdx) + ' name="' + AFaceName + '"');
    end;
  end;
  { FontMgr 系统字体优先（含中文，且支持粗体/斜体 style 选择） }
  Result := TryLoadSystemTypeface(APath, AIsBold, AIsItalic, AFaceName);
  if Result <> nil then
    Exit;
  Result := nil;
  { 应用内置字体文件兜底（resfile/filesDir/libs；系统字体不按路径读）}
  if AIsItalic then
    p := OhosResolveFontFile(OhosItalicFontFiles)
  else
    p := OhosResolveFontFile(OhosCJKFontFiles);
  if p <> '' then
  begin
    Result := OH_Drawing_TypefaceCreateFromFile(PChar(p), 0);
    if Result <> nil then
    begin
      APath := p;
      fpGUI_Hilog(LOG_INFO, 'FONT LOADED: path="' + p + '" bold=' +
        IntToStr(Integer(AIsBold)) + ' italic=' + IntToStr(Integer(AIsItalic)));
    end;
  end;
end;

constructor TfpgOhosFontResource.Create(const afontdesc: string);
var
  fd: TfpgFontDefinition;
  dummy: string;
begin
  inherited Create(afontdesc);
  fd := TfpgFontDefinition.Create(afontdesc);
  try
    { Font height in LOGICAL units. Canvas has CanvasScale(gScaleFactor)
      applied, so the font renders at fd.Size * gScaleFactor physical pixels. }
    FHeight := Round(fd.Size * 96 / 72 * gScaleFactor);
    //FHeight := fd.Size;
    FIsBold := fpgFontBold in fd.Attributes;
    FIsItalic := fpgFontItalic in fd.Attributes;
    FIsUnderline := fpgFontUnderline in fd.Attributes;
    FMetricsValid := False;
    FillChar(FMetrics, SizeOf(FMetrics), 0);

    FNativeTypeface := TryLoadTypeface(dummy, FIsBold, FIsItalic, fd.FaceName);
    FNativeTypefacePath := dummy;
    FNativeFont := OH_Drawing_FontCreate();
    if FNativeFont <> nil then
    begin
      if FNativeTypeface <> nil then
        OH_Drawing_FontSetTypeface(FNativeFont, FNativeTypeface);
      OH_Drawing_FontSetTextSize(FNativeFont, FHeight);
      { 合成粗体：系统无独立 Bold 文件；FontMgr 命中真实粗体 style 时
        APath 前缀 'FontMgr:' 不叠加（避免双重加粗）}
      if FIsBold and (Pos('FontMgr:', dummy) = 0) then
        OH_Drawing_FontSetFakeBoldText(FNativeFont, True);
    end;
    { 有 typeface 时构造已完成配置；无 typeface（字体加载失败，如模拟器
      无 CJK 字体族）时保持 False，首次绘制用兜底 typeface 配置一次后置位，
      避免逐次绘制重复 SetTypeface/SetTextSize（部分设备 ~24ms/次）。 }
    FNativeReady := (FNativeFont <> nil) and (FNativeTypeface <> nil);

    { 字符 fallback 字体链（CJK 兜底 + emoji）：缺字形字符防方框 }
    BuildFallbackChain;

    { Try to read real font metrics; fall back to heuristic on failure }
    RefreshMetrics;
    fpGUI_Hilog(LOG_INFO, format('FONT RES: desc=%s tf=%p font=%p h=%d bold=%d metrics=%s',
      [afontdesc, Pointer(FNativeTypeface), Pointer(FNativeFont), FHeight,
       Integer(FIsBold), BoolToStr(FMetricsValid, True)]));
  finally
    fd.Free;
  end;
end;

{ 构建 fallback 链：主字体缺字形（measure=0）时逐级兜底。
  系统字体优先经 FontMgr 家族接口（官方 API，不读系统字体文件），
  失败再试应用内置字体文件（resfile/filesDir，OhosFindFontFile 解析）。 }
procedure TfpgOhosFontResource.BuildFallbackChain;
var
  p: string;
  tf: POH_Drawing_Typeface;

  procedure AddTypefaceFont(ATypeface: POH_Drawing_Typeface; AIsBold: Boolean);
  var
    f: POH_Drawing_Font;
  begin
    if ATypeface = nil then Exit;
    f := OH_Drawing_FontCreate;
    if f = nil then
    begin
      OH_Drawing_TypefaceDestroy(ATypeface);
      Exit;
    end;
    OH_Drawing_FontSetTypeface(f, ATypeface);
    OH_Drawing_FontSetTextSize(f, FHeight);
    { 合成粗体：仅文件字体需要；FontMgr 命中真实 style 时不叠加 }
    if AIsBold then
      OH_Drawing_FontSetFakeBoldText(f, True);
    SetLength(FFallbackTypefaces, Length(FFallbackTypefaces) + 1);
    SetLength(FFallbackFonts, Length(FFallbackFonts) + 1);
    FFallbackTypefaces[High(FFallbackTypefaces)] := ATypeface;
    FFallbackFonts[High(FFallbackFonts)] := f;
  end;

begin
  { CJK 兜底：FontMgr 家族优先（与主字体同家族时去重跳过）}
  p := '';
  tf := TryLoadSystemTypeface(p, FIsBold, FIsItalic, '');
  if (tf <> nil) and (p <> FNativeTypefacePath) then
    AddTypefaceFont(tf, False)
  else
  begin
    if tf <> nil then
      OH_Drawing_TypefaceDestroy(tf);
    p := OhosResolveFontFile(OhosCJKFontFiles);
    if (p <> '') and (p <> FNativeTypefacePath) then
      AddTypefaceFont(OH_Drawing_TypefaceCreateFromFile(PChar(p), 0), FIsBold);
  end;
  { emoji：FontMgr 家族优先；失败再试应用内置 emoji 文件 }
  p := '';
  tf := TryLoadEmojiTypeface(p);
  if tf <> nil then
    AddTypefaceFont(tf, False)
  else
  begin
    p := OhosResolveFontFile(OhosEmojiFontFiles);
    if p <> '' then
      AddTypefaceFont(OH_Drawing_TypefaceCreateFromFile(PChar(p), 0), False);
  end;
end;

{ 在 fallback 链中测量字符宽（主字体缺字形时调用）。 }
function TfpgOhosFontResource.ResolveFallbackWidth(const ch: string;
  var AWidth: Single): Boolean;
var
  i: Integer;
  w: Single;
begin
  Result := False;
  for i := 0 to High(FFallbackFonts) do
  begin
    w := 0;
    if OH_Drawing_FontMeasureText(FFallbackFonts[i], PChar(ch), Length(ch),
      TEXT_ENCODING_UTF8, nil, @w) = 0 then
    begin
      if w > 0 then
      begin
        AWidth := w;
        Result := True;
        Exit;
      end;
    end;
  end;
end;

{ 在 fallback 链中定位可渲染该字符的字体（绘制用），并返回其宽度。 }
function TfpgOhosFontResource.ResolveFallbackFont(const ch: string;
  var AUseFont: POH_Drawing_Font; var AWidth: Single): Boolean;
var
  i: Integer;
  w: Single;
begin
  Result := False;
  for i := 0 to High(FFallbackFonts) do
  begin
    w := 0;
    if OH_Drawing_FontMeasureText(FFallbackFonts[i], PChar(ch), Length(ch),
      TEXT_ENCODING_UTF8, nil, @w) = 0 then
    begin
      if w > 0 then
      begin
        AUseFont := FFallbackFonts[i];
        AWidth := w;
        Result := True;
        Exit;
      end;
    end;
  end;
end;

procedure TfpgOhosFontResource.RefreshMetrics;
begin
  if (FNativeFont <> nil) and (FNativeTypeface <> nil) then
    FMetricsValid := (OH_Drawing_FontGetMetrics(FNativeFont, @FMetrics) <> 0)
  else
    FMetricsValid := False;
  if FMetricsValid then
  begin
    // OH_Drawing ascent is negative (distance from baseline to top)
    FAscent := Round(-FMetrics.fAscent);
    FDescent := Round(FMetrics.fDescent);
  end
  else begin
    FAscent := FHeight * 3 div 4;
    FDescent := FHeight div 4;
  end;
end;

destructor TfpgOhosFontResource.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FFallbackFonts) do
    if FFallbackFonts[i] <> nil then
      OH_Drawing_FontDestroy(FFallbackFonts[i]);
  SetLength(FFallbackFonts, 0);
  for i := 0 to High(FFallbackTypefaces) do
    if FFallbackTypefaces[i] <> nil then
      OH_Drawing_TypefaceDestroy(FFallbackTypefaces[i]);
  SetLength(FFallbackTypefaces, 0);
  if FNativeFont <> nil then
    OH_Drawing_FontDestroy(FNativeFont);
  if FNativeTypeface <> nil then
    OH_Drawing_TypefaceDestroy(FNativeTypeface);
  inherited Destroy;
end;

function TfpgOhosFontResource.GetAscent: Integer;
begin
  Result := FAscent;
end;

function TfpgOhosFontResource.GetDescent: Integer;
begin
  Result := FDescent;
end;

function TfpgOhosFontResource.GetHeight: Integer;
begin
  Result := FHeight;
end;

function TfpgOhosFontResource.GetTextWidth(const txt: string): Integer;
var
  i, clen, total: Integer;
  ch: string;
  textWidth: Single;
  ret: Int32;
  charW: Integer;
begin
  if txt = '' then Exit(0);
  { 逐字符 Round 累加：与渲染（DoDrawString 逐字符步进）及 fpg_edit
    光标/滚动定位口径一致。整串测量（含跨字符 kerning）会与逐字符
    定位产生累计偏差，导致超宽文本滚动后光标错位。 }
  total := 0;
  i := 1;
  while i <= Length(txt) do
  begin
    clen := Utf8CharLen(Byte(txt[i]));
    if clen < 1 then clen := 1;
    if i + clen - 1 > Length(txt) then clen := Length(txt) - i + 1;
    ch := Copy(txt, i, clen);

    textWidth := 0;
    if FNativeFont <> nil then
    begin
      ret := OH_Drawing_FontMeasureText(FNativeFont, PChar(ch), Length(ch),
        TEXT_ENCODING_UTF8, nil, @textWidth);
      if (ret <> 0) or (textWidth <= 0) then
      begin
        { 主字体缺字形 → fallback 链实测（防方框宽误差）}
        if not ResolveFallbackWidth(ch, textWidth) then
        begin
          if FMetricsValid and (FMetrics.fAvgCharWidth > 0) then
            textWidth := Round(FMetrics.fAvgCharWidth)
          else
            textWidth := FHeight * 3 div 5;
        end;
      end;
    end
    else
    begin
      if FMetricsValid and (FMetrics.fAvgCharWidth > 0) then
        textWidth := Round(FMetrics.fAvgCharWidth)
      else
        textWidth := FHeight * 3 div 5;
    end;

    total := total + Round(textWidth);
    Inc(i, clen);
  end;
  Result := total;
end;

function TfpgOhosFontResource.HandleIsValid: boolean;
begin
  Result := FNativeFont <> nil;
end;

{ ---------------------------------------------------------------------
  TfpgOhosImage
  --------------------------------------------------------------------- }

procedure TfpgOhosImage.DoFreeImage;
begin
  if FNativeBitmap <> nil then
  begin
    OH_Drawing_BitmapDestroy(FNativeBitmap);
    FNativeBitmap := nil;
  end;
end;

procedure TfpgOhosImage.DoInitImage(acolordepth, awidth, aheight: integer; aimgdata: Pointer);
var
  fmt: TOH_Drawing_BitmapFormat;
  pixels: PLongWord;
  i, count: Integer;
  v: UInt32;
begin
  // 守卫：尺寸无效时直接退出，避免 0 尺寸 bitmap 和整数溢出
  if (awidth <= 0) or (aheight <= 0) then Exit;
  
  FNativeBitmap := OH_Drawing_BitmapCreate();
  if FNativeBitmap = nil then Exit;
  fmt.colorFormat := COLOR_FORMAT_RGBA_8888;
  fmt.alphaFormat := ALPHA_FORMAT_UNPREMUL;//ALPHA_FORMAT_PREMUL;
  OH_Drawing_BitmapBuild(FNativeBitmap, awidth, aheight, @fmt);
  if aimgdata <> nil then
  begin
    Move(aimgdata^, OH_Drawing_BitmapGetPixels(FNativeBitmap)^, awidth * aheight * 4);
    // Swap R/B in each pixel: fpGUI ARGB (memory [B,G,R,A]) → RGBA_8888 ([R,G,B,A])
    pixels := OH_Drawing_BitmapGetPixels(FNativeBitmap);
    count := awidth * aheight;
    for i := 0 to count - 1 do
    begin
      v := pixels[i];
      pixels[i] := (v and $FF00FF00) or ((v shr 16) and $FF) or ((v shl 16) and $FF0000);
    end;
  end;
end;

procedure TfpgOhosImage.DoInitImageMask(awidth, aheight: integer; aimgdata: Pointer);
var
  pixels: PLongWord;
  mask: PByte;
  x, y, byteIndex, bitIndex, pixelIndex, rowBytes: Integer;
  v: UInt32;
begin
  if FNativeBitmap = nil then Exit;
  if aimgdata = nil then Exit;

  pixels := OH_Drawing_BitmapGetPixels(FNativeBitmap);
  mask := PByte(aimgdata);
  rowBytes := ((awidth + 31) div 32) * 4;  // DWORD aligned, match fpGUI msklinelen

  for y := 0 to aheight - 1 do
    for x := 0 to awidth - 1 do
    begin
      pixelIndex := y * awidth + x;
      byteIndex := y * rowBytes + (x div 8);
      bitIndex := 7 - (x mod 8);  // MSB first

      if (mask[byteIndex] and (1 shl bitIndex)) = 0 then
      begin
        // Transparent: clear alpha (OHOS RGBA = 0xAABBGGRR)
        v := pixels[pixelIndex];
        pixels[pixelIndex] := v and $00FFFFFF;
      end
      else
      begin
        // Opaque: ensure full alpha
        pixels[pixelIndex] := pixels[pixelIndex] or $FF000000;
      end;
    end;
end;

{ ---------------------------------------------------------------------
  TfpgOhosCanvas
  --------------------------------------------------------------------- }

constructor TfpgOhosCanvas.Create(awidget: TfpgWidgetBase);
begin
  inherited Create(awidget);
  FCanvas := nil;
  FBitmap := nil;
  FPen    := nil;
  FBrush  := nil;
  FRect   := nil;
  FPathEffect := nil;
  FClipRect.Clear;
  FSaveCount := 0;
  FClipDepth := 0;
  FColorValue := $FF000000;
  FBaseChildSaveCount := 0;
  FHasChildPainted := False;
end;


destructor TfpgOhosCanvas.Destroy;
begin
  if FSaveCount = 0 then
  begin
    if FCanvas <> nil then begin OH_Drawing_CanvasDestroy(FCanvas); FCanvas := nil; end;
    if FBitmap <> nil then begin OH_Drawing_BitmapDestroy(FBitmap); FBitmap := nil; end;
  end else begin
    FCanvas := nil;
    FBitmap := nil;
  end;
  if FPen <> nil then begin OH_Drawing_PenDestroy(FPen); FPen := nil; end;
  if FBrush <> nil then begin OH_Drawing_BrushDestroy(FBrush); FBrush := nil; end;
  if FRect <> nil then begin OH_Drawing_RectDestroy(FRect); FRect := nil; end;
  if FPathEffect <> nil then begin OH_Drawing_PathEffectDestroy(FPathEffect); FPathEffect := nil; end;
  inherited Destroy;
end;

procedure TfpgOhosCanvas.DoSetFontRes(fntres: TfpgFontResourceBase);
begin
  FFont := fntres;
end;

procedure TfpgOhosCanvas.DoSetTextColor(cl: TfpgColor);
begin
  //if FBrush = nil then FBrush := OH_Drawing_BrushCreate();
  //OH_Drawing_BrushSetColor(FBrush, ColorToNative(fpgColorToRGB(cl)));
  //DoSetTextColor 不应碰 FBrush。文字色由基类 FTextColor 存储，DoDrawString 已正确读取 FTextColor。
  
  // FTextColor is stored by base class SetTextColor.
  // DoDrawString reads FTextColor with save/restore on FBrush.
  // Do NOT touch FBrush here — it's for fill color, controlled by DoSetColor.  
end;

procedure TfpgOhosCanvas.DoSetColor(cl: TfpgColor);
var
  rgb: TfpgColor;
begin
  rgb := fpgColorToRGB(cl);
  FColorValue := cl;
  if FPen = nil then FPen := OH_Drawing_PenCreate();
  OH_Drawing_PenSetColor(FPen, ColorToNative(rgb));
  OH_Drawing_PenSetWidth(FPen, FLineWidth);
  if FBrush = nil then FBrush := OH_Drawing_BrushCreate();
  OH_Drawing_BrushSetColor(FBrush, ColorToNative(rgb));
end;

procedure TfpgOhosCanvas.DoSetLineStyle(awidth: integer; astyle: TfpgLineStyle);
var
  intervals: array[0..5] of Single;
  lw: Single;
  n: Integer;
begin
  FLineWidth := awidth;
  FLineStyle := astyle;
  if FPen = nil then FPen := OH_Drawing_PenCreate();
  OH_Drawing_PenSetWidth(FPen, awidth);

  if FPathEffect <> nil then
  begin
    OH_Drawing_PathEffectDestroy(FPathEffect);
    FPathEffect := nil;
  end;

  { Dash patterns match Agg2D.SetLineStyle (agg_2D.pas) so that AGG and
    non-AGG backends render identical line styles. }
  lw := awidth;
  if lw < 1 then lw := 1;
  n := 0;
  case astyle of
    lsDash:      begin intervals[0] := 3 * lw; intervals[1] := 4 * lw; n := 2; end;
    lsDot:       begin intervals[0] := 0.5 * lw; intervals[1] := 3 * lw; n := 2; end;
    lsDashDot:   begin intervals[0] := 4 * lw; intervals[1] := 3 * lw;
                       intervals[2] := 0.5 * lw; intervals[3] := 4 * lw; n := 4; end;
    lsDashDotDot:begin intervals[0] := 4 * lw; intervals[1] := 2 * lw;
                       intervals[2] := 0.5 * lw; intervals[3] := 2 * lw;
                       intervals[4] := 0.5 * lw; intervals[5] := 4 * lw; n := 6; end;
  end;

  if n > 0 then
  begin
    FPathEffect := OH_Drawing_CreateDashPathEffect(@intervals[0], n, 0.0);
    OH_Drawing_PenSetPathEffect(FPen, FPathEffect);
  end
  else
    OH_Drawing_PenSetPathEffect(FPen, nil);
end;

procedure TfpgOhosCanvas.DoFillRectangle(x, y, w, h: TfpgCoord);
begin
  if FCanvas = nil then
  begin
    fpGUI_Hilog(LOG_ERROR, 'DoFillRectangle SKIP: FCanvas=nil');
    Exit;
  end;
  if FCanvas = nil then Exit;
  if FRect <> nil then OH_Drawing_RectDestroy(FRect);
  FRect := OH_Drawing_RectCreate(x + FDeltaX, y + FDeltaY, x + FDeltaX + w, y + FDeltaY + h);
  if FBrush <> nil then
  begin
    OH_Drawing_CanvasAttachBrush(FCanvas, FBrush);
    OH_Drawing_CanvasDrawRect(FCanvas, FRect);
    OH_Drawing_CanvasDetachBrush(FCanvas);
  end;
end;

procedure TfpgOhosCanvas.DoXORFillRectangle(col: TfpgColor; x, y, w, h: TfpgCoord);
var
  px: Pointer;
  stride, bw, bh: UInt32;
  x0, y0, x1, y1, cx, cy: Integer;
  mask: UInt32;
  p: PLongWord;
begin
  if FBitmap = nil then Exit;
  px := OH_Drawing_BitmapGetPixels(FBitmap);
  if px = nil then Exit;
  bw := OH_Drawing_BitmapGetWidth(FBitmap);
  bh := OH_Drawing_BitmapGetHeight(FBitmap);
  { Defensive sanity check: a stale/destroyed bitmap handle can report
    garbage dimensions; refuse to write anything in that case (caret
    blink timer runs outside BeginDraw/EndDraw on this backend). }
  if (bw < 1) or (bh < 1) or (bw > 32768) or (bh > 32768) then Exit;
  stride := bw * 4;

  { Logical rect (incl. canvas offset) → physical bitmap pixels. }
  x0 := Round((x + FDeltaX) * gScaleFactorX);
  y0 := Round((y + FDeltaY) * gScaleFactorY);
  x1 := Round((x + FDeltaX + w) * gScaleFactorX) - 1;
  y1 := Round((y + FDeltaY + h) * gScaleFactorY) - 1;
  if x0 < 0 then x0 := 0;
  if y0 < 0 then y0 := 0;
  if x1 >= Integer(bw) then x1 := Integer(bw) - 1;
  if y1 >= Integer(bh) then y1 := Integer(bh) - 1;
  if (x1 < x0) or (y1 < y0) then Exit;

  { True per-pixel XOR (like the X11 GXxor / R2_XORPEN semantics):
    self-inverting, visible on any background. Native longword layout is
    AABBGGRR (bytes R,G,B,A), so the mask swaps R↔B; alpha is preserved. }
  mask := (col and $FF000000) or ((col shr 16) and $FF) or (col and $FF00)
       or ((col shl 16) and $FF0000);

  for cy := y0 to y1 do
  begin
    p := PLongWord(PByte(px) + cy * stride + x0 * 4);
    for cx := x0 to x1 do
    begin
      p^ := (p^ and $FF000000) or ((p^ xor mask) and $00FFFFFF);
      Inc(p);
    end;
  end;
end;

procedure TfpgOhosCanvas.DoFillTriangle(x1, y1, x2, y2, x3, y3: TfpgCoord);
var
  path: POH_Drawing_Path;
begin
  if FCanvas = nil then Exit;
  path := OH_Drawing_PathCreate();
  if path = nil then Exit;
  OH_Drawing_PathMoveTo(path, x1 + FDeltaX, y1 + FDeltaY);
  OH_Drawing_PathLineTo(path, x2 + FDeltaX, y2 + FDeltaY);
  OH_Drawing_PathLineTo(path, x3 + FDeltaX, y3 + FDeltaY);
  OH_Drawing_PathClose(path);
  if FBrush <> nil then
    OH_Drawing_CanvasAttachBrush(FCanvas, FBrush);
  OH_Drawing_CanvasDrawPath(FCanvas, path);
  if FBrush <> nil then
    OH_Drawing_CanvasDetachBrush(FCanvas);
  OH_Drawing_PathDestroy(path);
end;

procedure TfpgOhosCanvas.DoDrawRectangle(x, y, w, h: TfpgCoord);
begin
  if FCanvas = nil then Exit;
  if FRect <> nil then OH_Drawing_RectDestroy(FRect);
  FRect := OH_Drawing_RectCreate(x + FDeltaX, y + FDeltaY, x + FDeltaX + w, y + FDeltaY + h);
  if FPen <> nil then
  begin
    OH_Drawing_CanvasAttachPen(FCanvas, FPen);
    OH_Drawing_CanvasDrawRect(FCanvas, FRect);
    OH_Drawing_CanvasDetachPen(FCanvas);
  end;
end;

procedure TfpgOhosCanvas.DoDrawLine(x1, y1, x2, y2: TfpgCoord);
begin
  if FCanvas = nil then Exit;
  if FPen <> nil then
  begin
    OH_Drawing_CanvasAttachPen(FCanvas, FPen);
    OH_Drawing_CanvasDrawLine(FCanvas, x1 + FDeltaX, y1 + FDeltaY, x2 + FDeltaX, y2 + FDeltaY);
    OH_Drawing_CanvasDetachPen(FCanvas);
  end;
end;

procedure TfpgOhosCanvas.DoDrawImagePart(x, y: TfpgCoord; img: TfpgImageBase; xi, yi, w, h: integer);
var
  ohosImg: TfpgOhosImage;
  nativeBmp: POH_Drawing_Bitmap;
  srcRect, dstRect: POH_Drawing_Rect;
begin
  if (FCanvas = nil) or (img = nil) then Exit;
  if not (img is TfpgOhosImage) then Exit;
  ohosImg := TfpgOhosImage(img);
  nativeBmp := ohosImg.FNativeBitmap;
  if nativeBmp = nil then Exit;

  srcRect := OH_Drawing_RectCreate(xi, yi, xi + w, yi + h);
  dstRect := OH_Drawing_RectCreate(x + FDeltaX, y + FDeltaY, x + FDeltaX + w, y + FDeltaY + h);
  OH_Drawing_CanvasDrawBitmapRect(FCanvas, nativeBmp, srcRect, dstRect, nil);
  OH_Drawing_RectDestroy(dstRect);
  OH_Drawing_RectDestroy(srcRect);
end;

{ StretchDraw 快路径：与 DoDrawImagePart 同一原生缩放通道
  (OH_Drawing_CanvasDrawBitmapRect)，保证两者坐标语义完全一致——
  源整图 → 目标逻辑矩形 (x,y,w,h)，Canvas 的 scale 矩阵负责 HiDPI 物理映射，
  目标物理矩形被完整采样填充（无逐像素 SetPixel 的空洞/发虚问题）。
  非 TfpgOhosImage 或原生位图不可用时回退基类插值实现。 }
procedure TfpgOhosCanvas.DoStretchDraw(x, y, w, h: TfpgCoord; ASource: TfpgImageBase);
var
  ohosImg: TfpgOhosImage;
  nativeBmp: POH_Drawing_Bitmap;
  srcRect, dstRect: POH_Drawing_Rect;
  imgW, imgH: Integer;
begin
  if (FCanvas = nil) or (ASource = nil) then Exit;
  if (w <= 0) or (h <= 0) then Exit;
  if ASource is TfpgOhosImage then
  begin
    ohosImg := TfpgOhosImage(ASource);
    nativeBmp := ohosImg.FNativeBitmap;
    if nativeBmp <> nil then
    begin
      imgW := OH_Drawing_BitmapGetWidth(nativeBmp);
      imgH := OH_Drawing_BitmapGetHeight(nativeBmp);
      if (imgW > 0) and (imgH > 0) then
      begin
        srcRect := OH_Drawing_RectCreate(0, 0, imgW, imgH);
        dstRect := OH_Drawing_RectCreate(x + FDeltaX, y + FDeltaY,
                                         x + FDeltaX + w, y + FDeltaY + h);
        OH_Drawing_CanvasDrawBitmapRect(FCanvas, nativeBmp, srcRect, dstRect, nil);
        OH_Drawing_RectDestroy(dstRect);
        OH_Drawing_RectDestroy(srcRect);
        Exit;
      end;
    end;
  end;
  { 兜底：基类 Mitchel 插值（经 SetPixel，已含 FDelta 与 alpha 修正） }
  inherited DoStretchDraw(x, y, w, h, ASource);
end;

procedure TfpgOhosCanvas.DoDrawString(x, y: TfpgCoord; const txt: string);
var
  lFont: POH_Drawing_Font;
  useFont: POH_Drawing_Font;
  lTypeface: POH_Drawing_Typeface;
  lTextBlob: POH_Drawing_TextBlob;
  fontSize, baseY, curX, chW: Single;
  ownFont: Boolean;
  ohosFntRes: TfpgOhosFontResource;
  savedBrushColor: UInt32;
  i, clen: Integer;
  ch: string;
  fallbackUsed: Boolean;
  needFontSetup: Boolean;
begin
  if (FCanvas = nil) or (txt = '') then Exit;

  ownFont := False;
  ohosFntRes := nil;
  if (FFont <> nil) and (FFont is TfpgOhosFontResource) then
  begin
    ohosFntRes := TfpgOhosFontResource(FFont);
    lFont := ohosFntRes.NativeFont;
    lTypeface := ohosFntRes.FNativeTypeface;
    fontSize := ohosFntRes.GetHeight;
    baseY := y + FDeltaY + ohosFntRes.GetAscent;
  end
  else
  begin
    lFont := OH_Drawing_FontCreate();
    if lFont = nil then Exit;
    lTypeface := nil;
    if FFont <> nil then
      fontSize := FFont.GetHeight
    else
      fontSize := 14.0;
    baseY := y + FDeltaY + fontSize;
    ownFont := True;
  end;

  { 字体配置只在必要时做一次（每个资源/临时字体一次）：
    OH_Drawing_FontSetTypeface/SetTextSize 在部分设备上 ~24ms/次，
    逐次绘制重复设置会拖垮渲染（实测 17 次/帧 ≈ 全部 paint 耗时）。
    资源构造时若 typeface 加载失败（如模拟器无 CJK 字体族），
    首次绘制用兜底 typeface 配置一次并置 FNativeReady，之后不再重复。 }
  needFontSetup := ownFont or (ohosFntRes = nil) or (not ohosFntRes.FNativeReady);
  if needFontSetup then
  begin
    if lTypeface = nil then
    begin
      { FFont 非 OHOS 资源/资源缺 typeface 时的兜底：进程级单例，
        仅首次创建，后续绘制直接复用。 }
      if gFallbackTypeface = nil then
      begin
        gFallbackTypefacePath := OhosResolveFontFile(OhosCJKFontFiles);
        if gFallbackTypefacePath <> '' then
          gFallbackTypeface := OH_Drawing_TypefaceCreateFromFile(
            PChar(gFallbackTypefacePath), 0);
      end;
      lTypeface := gFallbackTypeface;   { ownTypeface 恒 False：进程级单例不销毁 }
    end;
    if lTypeface <> nil then
      OH_Drawing_FontSetTypeface(lFont, lTypeface);
    OH_Drawing_FontSetTextSize(lFont, fontSize);
    if ohosFntRes <> nil then
      ohosFntRes.FNativeReady := True;
  end;

  // TextBlob fills via brush — temporarily set brush to FTextColor
  if FBrush = nil then
    FBrush := OH_Drawing_BrushCreate();
  savedBrushColor := OH_Drawing_BrushGetColor(FBrush);
  OH_Drawing_BrushSetColor(FBrush, ColorToNative(fpgColorToRGB(FTextColor)));
  OH_Drawing_BrushSetAntiAlias(FBrush, True);
  OH_Drawing_CanvasAttachBrush(FCanvas, FBrush);

  { Draw per character and advance by the per-character measured width.
    This matches fpGUI's positioning model (TfpgBaseEdit accumulates
    Font.GetTextWidth of each char for caret/scroll math); a single
    full-string TextBlob applies cross-character kerning and drifts
    from that model, causing caret misplacement on long/scrollable text.
    主字体缺字形（measure=0）→ fallback 链（CJK/emoji）渲染该字符，防方框。 }
  curX := x + FDeltaX;
  i := 1;
  while i <= Length(txt) do
  begin
    clen := Utf8CharLen(Byte(txt[i]));
    if clen < 1 then clen := 1;
    if i + clen - 1 > Length(txt) then clen := Length(txt) - i + 1;
    ch := Copy(txt, i, clen);

    useFont := lFont;
    chW := 0;
    OH_Drawing_FontMeasureText(lFont, PChar(ch), Length(ch), TEXT_ENCODING_UTF8, nil, @chW);
    fallbackUsed := False;
    if (chW <= 0) and (ohosFntRes <> nil) then
      fallbackUsed := ohosFntRes.ResolveFallbackFont(ch, useFont, chW);

    lTextBlob := OH_Drawing_TextBlobCreateFromText(PChar(ch), Length(ch), useFont,
      TEXT_ENCODING_UTF8);
    if lTextBlob <> nil then
    begin
      OH_Drawing_CanvasDrawTextBlob(FCanvas, lTextBlob, curX, baseY);
      OH_Drawing_TextBlobDestroy(lTextBlob);
    end
    else if not gDrawDiagDone then
    begin
      gDrawDiagDone := True;
      fpGUI_Hilog(LOG_ERROR, format('DRAW: TextBlob nil ch=%s useFont=%p chW=%.2f fb=%d',
        [ch, Pointer(useFont), chW, Integer(fallbackUsed)]));
    end;

    if chW <= 0 then
    begin
      { 无任何字体命中：宽度兜底（不步进 0 导致叠字）}
      if ohosFntRes <> nil then
        chW := ohosFntRes.GetHeight * 3 / 5
      else
        chW := fontSize * 3 / 5;
    end;
    { Integer stepping matches TfpgBaseEdit's caret math:
      it accumulates Round(GetTextWidth(ch)) per char. }
    curX := curX + Round(chW);
    Inc(i, clen);
  end;

  OH_Drawing_CanvasDetachBrush(FCanvas);
  OH_Drawing_BrushSetColor(FBrush, savedBrushColor);

  if ownFont then
    OH_Drawing_FontDestroy(lFont);
end;

procedure TfpgOhosCanvas.DoSetClipRectInternal(const ARect: TfpgRect);
var
  n: Int32;
  wRect: TfpgRect;
  native: TfpgRect;
begin
  FClipRect := ARect;
  if FCanvas = nil then Exit;
  { Convert to native window coordinates and intersect with widget bounds.
    Matches X11's DoSetClipRectInternal: prevents drawing outside the
    widget's visible area (critical for child widgets that extend beyond
    their parent, and for tab labels that exceed the control width). }
  native := ARect;
  native.OffsetRect(FDeltaX, FDeltaY);
  wRect := GetWidgetWindowRect;
  native.IntersectRect(native, wRect);
  { SetClipRect = REPLACE semantics: drop any active clip saves first }
  if FClipDepth > 0 then
  begin
    n := OH_Drawing_CanvasGetSaveCount(FCanvas);
    if n > FClipDepth then
      OH_Drawing_CanvasRestoreToCount(FCanvas, n - FClipDepth);
    FClipDepth := 0;
  end;
  OH_Drawing_CanvasSave(FCanvas);
  Inc(FClipDepth);
  if FRect <> nil then OH_Drawing_RectDestroy(FRect);
  FRect := OH_Drawing_RectCreate(native.Left, native.Top,
                                 native.Right + 1, native.Bottom + 1);
  OH_Drawing_CanvasClipRect(FCanvas, FRect, TOH_Drawing_CanvasClipOp.INTERSECT, False);
end;

procedure TfpgOhosCanvas.DoSetClipRect(const ARect: TfpgRect);
begin
  DoSetClipRectInternal(ARect);
end;

function TfpgOhosCanvas.DoGetClipRect: TfpgRect;
begin
  Result := FClipRect;
end;

procedure TfpgOhosCanvas.DoAddClipRect(const ARect: TfpgRect);
begin
  if FCanvas = nil then Exit;
  OH_Drawing_CanvasSave(FCanvas);
  Inc(FClipDepth);
  if FRect <> nil then OH_Drawing_RectDestroy(FRect);
  FRect := OH_Drawing_RectCreate(ARect.Left + FDeltaX, ARect.Top + FDeltaY, ARect.Right + FDeltaX + 1, ARect.Bottom + FDeltaY +1);
  OH_Drawing_CanvasClipRect(FCanvas, FRect, TOH_Drawing_CanvasClipOp.INTERSECT, False);
end;

procedure TfpgOhosCanvas.DoClearClipRect;
var
  r: TfpgRect;
begin
  { Match X11 behavior: ClearClipRect resets clip to widget bounds
    instead of removing all clipping. This prevents tab labels and
    other child drawings from overflowing beyond the control area. }
  r.SetRect(0, 0, FWidget.ActualWidth, FWidget.ActualHeight);
  DoSetClipRectInternal(r);
end;

procedure TfpgOhosCanvas.DoBeginDraw(awidget: TfpgWidgetBase; CanvasTarget: TfpgCanvasBase);
const
  BufferResizeThreshold = 50;
var
  winRect: TfpgRect;
  fmt: TOH_Drawing_BitmapFormat;
  ohosTarget: TfpgOhosCanvas;
  curW,curH,needW,needH: integer;
begin
  { Child widget: share parent canvas/bitmap with offset }
  if (CanvasTarget <> nil) and (CanvasTarget <> Self) then
  begin
    ohosTarget := TfpgOhosCanvas(CanvasTarget);
    { Diagnostic: a child widget whose geometry extends beyond the window
      gets clipped by OH_Drawing (draws nothing) — the "part of the window
      stays white" symptom in non-AGG mode. Log only the out-of-bounds
      widgets to keep the noise low. }
    if (awidget <> nil) and (awidget.Window <> nil) and (ohosTarget.FBitmap <> nil) then
    begin
      winRect := awidget.Window.GetClientRect;
      if (FDeltaX + awidget.ActualWidth  > winRect.Width) or
         (FDeltaY + awidget.ActualHeight > winRect.Height) then
        fpGUI_Hilog(LOG_INFO, 'DoBeginDraw CHILD OOB wdg=' + awidget.ClassName +
          ' name=' + awidget.Name +
          ' delta=(' + IntToStr(FDeltaX) + ',' + IntToStr(FDeltaY) + ') log' +
          ' size=(' + IntToStr(awidget.ActualWidth) + 'x' + IntToStr(awidget.ActualHeight) + ') log' +
          ' win=(' + IntToStr(winRect.Width) + 'x' + IntToStr(winRect.Height) + ') log' +
          ' parentBmp=' + IntToHex(PtrUInt(ohosTarget.FBitmap), 8) +
          ' w=' + IntToStr(OH_Drawing_BitmapGetWidth(ohosTarget.FBitmap)) +
          ' h=' + IntToStr(OH_Drawing_BitmapGetHeight(ohosTarget.FBitmap)));
    end;
    { If the target canvas has no native resources yet, allocate them.
      This handles the case where fpGUI's BeginDraw redirects drawing to
      PrimaryWidget.Canvas, which for popup windows is a separate canvas
      object from the window's canvas (Self). }
    if ohosTarget.FCanvas = nil then
    begin
      if awidget <> nil then
        winRect := awidget.Window.GetClientRect
      else
        winRect.SetRect(0, 0, 400, 300);
      if winRect.Width < 1 then winRect.Width := 400;
      if winRect.Height < 1 then winRect.Height := 300;
      winRect.Width  := Round(winRect.Width  * gScaleFactorX);
      winRect.Height := Round(winRect.Height * gScaleFactorY);
      ohosTarget.FCanvas := OH_Drawing_CanvasCreate();
      ohosTarget.FBitmap := OH_Drawing_BitmapCreate();
      if (ohosTarget.FCanvas = nil) or (ohosTarget.FBitmap = nil) then
      begin
        if ohosTarget.FCanvas <> nil then begin OH_Drawing_CanvasDestroy(ohosTarget.FCanvas); ohosTarget.FCanvas := nil; end;
        if ohosTarget.FBitmap <> nil then begin OH_Drawing_BitmapDestroy(ohosTarget.FBitmap); ohosTarget.FBitmap := nil; end;
        Exit;
      end;
      fmt.colorFormat := COLOR_FORMAT_RGBA_8888;
      fmt.alphaFormat := ALPHA_FORMAT_PREMUL;
      OH_Drawing_BitmapBuild(ohosTarget.FBitmap, winRect.Width, winRect.Height, @fmt);
      OH_Drawing_CanvasBind(ohosTarget.FCanvas, ohosTarget.FBitmap);
      OH_Drawing_CanvasClear(ohosTarget.FCanvas, $FFFFFFFF);
      OH_Drawing_CanvasScale(ohosTarget.FCanvas, gScaleFactorX, gScaleFactorY);
      OH_Drawing_CanvasSave(ohosTarget.FCanvas);
    end;
    FCanvas := ohosTarget.FCanvas;
    FBitmap := ohosTarget.FBitmap;
    FSaveCount := 1;
    FWidget := awidget;
    if ohosTarget.FHasChildPainted then
      OH_Drawing_CanvasRestoreToCount(FCanvas, ohosTarget.FBaseChildSaveCount);
    ohosTarget.FBaseChildSaveCount := OH_Drawing_CanvasGetSaveCount(FCanvas);
    FChildSaveCount := OH_Drawing_CanvasGetSaveCount(FCanvas);
    OH_Drawing_CanvasSave(FCanvas);
    ohosTarget.FHasChildPainted := True;
    FParentBeginDrawCount := ohosTarget.FBeginDrawCount;
    Exit;
  end;

  { Top-level widget: own resources }
  if FSaveCount = 0 then
  begin
    { Reuse canvas/bitmap when sizes match, using FSaveBaseline to restore
      the save stack to a known state (avoids hardcoded save count).
      Hysteresis: keep the buffer until it is either too small for the
      requested size or larger than needed by BufferResizeThreshold —
      avoids full reallocation (and flicker) on small resizes. }
    if (FCanvas <> nil) and (FBitmap <> nil) then
    begin
      if awidget <> nil then
        winRect := awidget.Window.GetClientRect
      else
        winRect.SetRect(0, 0, 400, 300);
      if winRect.Width < 1 then winRect.Width := 400;
      if winRect.Height < 1 then winRect.Height := 300;
      { 用窗口实际物理尺寸（resize 反馈更新）作重建依据——GetClientRect 在
        反馈处理后可能滞后，导致 bitmap 停在旧尺寸（拖大后黑色区域）。 }
      if (awidget <> nil) and (awidget.Window is TfpgOhosWindow) then
      begin
        needW := TfpgOhosWindow(awidget.Window).PhysicalWidth;
        needH := TfpgOhosWindow(awidget.Window).PhysicalHeight;
        if needW < 1 then needW := Round(winRect.Width * gScaleFactorX);
        if needH < 1 then needH := Round(winRect.Height * gScaleFactorY);
      end
      else
      begin
        needW := Round(winRect.Width  * gScaleFactorX);
        needH := Round(winRect.Height * gScaleFactorY);
      end;
      curW := OH_Drawing_BitmapGetWidth(FBitmap);
      curH := OH_Drawing_BitmapGetHeight(FBitmap);
      if (curW >= needW) and (curH >= needH) and
         (curW <= needW + BufferResizeThreshold) and
         (curH <= needH + BufferResizeThreshold) then
      begin
        OH_Drawing_CanvasRestoreToCount(FCanvas, FSaveBaseline);
        FWidget := awidget;
        FHasChildPainted := False;
        FBaseChildSaveCount := 0;
        FClipDepth := 0;
        Exit;   // reuse: preserve content for XOR toggle
      end;
      OH_Drawing_CanvasDestroy(FCanvas); FCanvas := nil;
      OH_Drawing_BitmapDestroy(FBitmap); FBitmap := nil;
    end;
    if FCanvas <> nil then begin OH_Drawing_CanvasDestroy(FCanvas); FCanvas := nil; end;
    if FBitmap <> nil then begin OH_Drawing_BitmapDestroy(FBitmap); FBitmap := nil; end;
  end;
  FSaveCount := 0;
  FCanvas := nil;
  FBitmap := nil;
  { Reset child tracking — no children have painted yet this frame }
  FHasChildPainted := False;
  FBaseChildSaveCount := 0;
  FClipDepth := 0;

  FCanvas := OH_Drawing_CanvasCreate();
  if FCanvas = nil then Exit;

  FBitmap := OH_Drawing_BitmapCreate();
  if FBitmap = nil then begin OH_Drawing_CanvasDestroy(FCanvas); FCanvas := nil; Exit; end;

  if awidget <> nil then
    winRect := awidget.Window.GetClientRect
  else
    winRect.SetRect(0, 0, 400, 300);
  if winRect.Width < 1 then winRect.Width := 400;
  if winRect.Height < 1 then winRect.Height := 300;
  { Scale bitmap to physical resolution for crisp rendering.
    用窗口实际物理尺寸（resize 反馈更新），见上方 reuse 判断注释。 }
  if (awidget <> nil) and (awidget.Window is TfpgOhosWindow) then
  begin
    if TfpgOhosWindow(awidget.Window).PhysicalWidth > 0 then
      winRect.Width := TfpgOhosWindow(awidget.Window).PhysicalWidth
    else
      winRect.Width := Round(winRect.Width * gScaleFactorX);
    if TfpgOhosWindow(awidget.Window).PhysicalHeight > 0 then
      winRect.Height := TfpgOhosWindow(awidget.Window).PhysicalHeight
    else
      winRect.Height := Round(winRect.Height * gScaleFactorY);
  end
  else
  begin
    winRect.Width  := Round(winRect.Width  * gScaleFactorX);
    winRect.Height := Round(winRect.Height * gScaleFactorY);
  end;
  fmt.colorFormat := COLOR_FORMAT_RGBA_8888; //画布目标用 PREMUL 对齐原生绘制/Skia 约定；内容不透明时与 OPAQUE 等价
  fmt.alphaFormat := ALPHA_FORMAT_PREMUL;
  OH_Drawing_BitmapBuild(FBitmap, winRect.Width, winRect.Height, @fmt);

  OH_Drawing_CanvasBind(FCanvas, FBitmap);
  OH_Drawing_CanvasClear(FCanvas, $FFFFFFFF);
  { Apply DPI scale so fpGUI logical coordinates map to physical pixels. }
  OH_Drawing_CanvasScale(FCanvas, gScaleFactorX, gScaleFactorY);
  OH_Drawing_CanvasSave(FCanvas);
  FSaveBaseline := OH_Drawing_CanvasGetSaveCount(FCanvas);
  FWidget := awidget;

end;

procedure TfpgOhosCanvas.DoPutBufferToScreen(x, y, w, h: TfpgCoord);
var
  nativeWin: TfpgWinHandle;
  buf: Pointer;
  fence: Int32;
  hdl: PBufferHandle;
  addr: Pointer;
  region: TOH_Region;
  regRect: TOH_Region_Rect;
  px: Pointer;
  bmpW, bmpH, srcStride, dstStride: Integer;
  copyW, copyH, i: Integer;
  ohosWin: TfpgOhosWindow;
  sx, sy, sw, sh: Integer;
  reqResult: Integer;
  bg: LongWord;
  sizeMismatch: Boolean;
{  caretWidget: TfpgWidgetBase;
  caretRect: TfpgRect;
  dx, dy: TfpgCoord;
  widgetX, widgetY, widgetW, widgetH: Integer; }
begin
  if (FWidget = nil) or (FBitmap = nil) then Exit;
  ohosWin := TfpgOhosWindow(FWidget.Window);
  if ohosWin = nil then Exit;
  nativeWin := ohosWin.WinHandle;
  if nativeWin = nil then Exit;
(*
  { ── 检查是否有光标，如果有，判断当前绘制区域是否小于控件区域 ── }
  if Assigned(fpgCaret) and (fpgCaret.Canvas <> nil) then
  begin
    // 获取光标所在的控件
    caretWidget := fpgCaret.Canvas.Widget;
    if Assigned(caretWidget) then
    begin
      // 获取控件的区域
      caretRect := caretWidget.GetClientRect;
      dx := 0;
      dy := 0;
      // 将控件区域转换为窗口坐标
      caretWidget.WidgetToWindow(dx, dy);
      
      // 计算控件区域
      widgetX := dx;
      widgetY := dy;
      widgetW := caretRect.Width;
      widgetH := caretRect.Height;
      
      // 如果当前绘制区域小于控件区域，则扩大为控件区域
      // 否则使用原始的x, y, w, h参数
      if (w < widgetW) or (h < widgetH) then
      begin
        x := widgetX;
        y := widgetY;
        w := widgetW;
        h := widgetH;
      end;
    end;
  end;
*)
  // 局部刷新区域，只更新该区域
  sx := Round(x * gHiDPIScaleFactor);
  sy := Round(y * gHiDPIScaleFactor);
  sw := Round(w * gHiDPIScaleFactor);
  sh := Round(h * gHiDPIScaleFactor);

  { 位图尺寸基准：所有区域计算以位图为上限（原代码用 GetWidth/Height 各处重复取） }
  bmpW := Integer(OH_Drawing_BitmapGetWidth(FBitmap));
  bmpH := Integer(OH_Drawing_BitmapGetHeight(FBitmap));
  if (bmpW <= 0) or (bmpH <= 0) then Exit;
  if sw <= 0 then sw := bmpW;
  if sh <= 0 then sh := bmpH;

  { 扩展为全窗刷新：保证缓冲池每个缓冲内容完整一致，
    避免光标闪烁时显示旧缓冲导致字符消失/吃字符（与 AGG 版一致） }
  if Assigned(fpgCaret) and (fpgCaret.Canvas <> nil) then
  begin  
    sx := 0; sy := 0; sw := bmpW; sh := bmpH;
  end; 
  
  { ★ 区域一律夹到 bitmap 之内 }
  if sx >= bmpW then Exit;
  if sy >= bmpH then Exit;
  if sx + sw > bmpW then sw := bmpW - sx;
  if sy + sh > bmpH then sh := bmpH - sy;
  if (sw <= 0) or (sh <= 0) then Exit;

  // 申请 buffer（RequestBuffer 替代 LockBuffer——API 20+ 已移除 LockBuffer）
  buf := nil;
  fence := -1;
  reqResult := OH_NativeWindow_NativeWindowRequestBuffer(nativeWin, @buf, @fence);
  if reqResult <> 0 then begin
    Exit;
  end;

  // 从 buffer 获取句柄
  hdl := OH_NativeWindow_GetBufferHandleFromNative(buf);
  if (hdl = nil) or (hdl^.fd < 0) then begin
    OH_NativeWindow_NativeWindowAbortBuffer(nativeWin, buf);
    Exit;
  end;
  { RequestBuffer 返回的是 release fence（消费者已释放该 buffer 的信号）：
    写入前必须等待；超时按既定策略继续写（记日志）。随后自行关闭并置 -1——
    FlushBuffer 的 acquire fence 对 CPU 渲染传 -1，且文档禁止与 release
    fence 复用同一 fd。 }
  {if (fence >= 0) then
  begin
    if not OH_NativeFence_Wait(fence, 500) then
      fpGUI_Hilog(LOG_WARN, format('PutBuf fence wait timeout: win=%s fd=%d',
        [IntToHex(PtrUInt(nativeWin), 8), fence]));
    OH_NativeFence_Close(fence);
    fence := -1;
  end;}
  
  // 确保不超出 buffer 实际尺寸
  { ≤1px 视为匹配：bitmap 由逻辑尺寸×scale 往返可能有 1px 取整差
    （实测 phys=1840 → FSize=Round(1840/2.375)=775 → 775×2.375=1841），
    拷贝按 hdl 夹紧，1px 差异无影响，不应触发失配丢帧。 }
  sizeMismatch := (Abs(Integer(hdl^.width)  - bmpW) > 1) or
                  (Abs(Integer(hdl^.height) - bmpH) > 1);
  if sizeMismatch then begin
    fpGUI_Hilog(LOG_WARN, format('PutBuf MISMATCH: win=%s bmp=%dx%d hdl=%dx%d first=%d',
      [IntToHex(PtrUInt(nativeWin), 8), bmpW, bmpH,
       Integer(hdl^.width), Integer(hdl^.height), Ord(FFirstFrameSent)]));
    if fpgApplication is TfpgOhosApplication then
      TfpgOhosApplication(fpgApplication).ScheduleRepaintHelper(nativeWin);
    if FFirstFrameSent then
    begin
      { 已上过首帧 → 失配期间不上屏。半帧（背景填充+被裁剪拷贝）
        正是"新页只显一部份"的来源；交给 RepaintHelper 促收敛。 }
      OH_NativeWindow_NativeWindowAbortBuffer(nativeWin, buf);
      Exit;
    end;
  end
  else if fpgApplication is TfpgOhosApplication then
    // ★几何已追上 → 停掉重试（原实现永远停不下来）
    TfpgOhosApplication(fpgApplication).CancelRepaintHelper(nativeWin);
    
  { 诊断：bitmap（渲染目标）vs hdl（OHOS buffer）尺寸——
    创建阶段 surface 压缩态（drawable=客户区-dec）时 hdl 偏小 → 复制被裁剪
    （底部被裁+显示拉伸"拉高"）。确认裁剪是否发生、何时恢复。 }
{  fpGUI_Hilog(LOG_INFO,format('PutBuf: win=%s bmp=%dx%d hdl=%dx%d copy=%dx%d',
    [IntToHex(PtrUInt(nativeWin), 8),
     OH_Drawing_BitmapGetWidth(FBitmap), OH_Drawing_BitmapGetHeight(FBitmap),
     hdl^.width, hdl^.height, sw, sh])); }

  // 5. 数据拷贝（buffer 句柄 -> mmap 获取 CPU 可写地址）
  px := OH_Drawing_BitmapGetPixels(FBitmap);
  if px = nil then begin
    OH_NativeWindow_NativeWindowAbortBuffer(nativeWin, buf);
    Exit;
  end;

  addr := fpmmap(nil, hdl^.size, PROT_READ or PROT_WRITE, MAP_SHARED, hdl^.fd, 0);
  if addr = Pointer(-1) then begin
    OH_NativeWindow_NativeWindowAbortBuffer(nativeWin, buf);
    Exit;
  end;

  { 缓冲池固定（hdl 不随窗口 resize 更新）：窗口拖大后 bitmap 新尺寸 > hdl，
    复制被裁剪 → 扩大区域无数据（黑色）。先把整个 buffer 填为窗口背景色
    （取 bitmap 左上角像素，fpGUI 窗体背景通常在此），再复制 →
    拖大区域显示背景而非黑色。仅 bitmap 超出 hdl 时填充（平时 1:1 不开销）。 }
  if sizeMismatch{(bmpW > Integer(hdl^.width)) or (bmpH > Integer(hdl^.height))} then
  begin
    bg := PLongWord(px)^;
    FillDWord(addr^, hdl^.size div 4, bg);
{    fpGUI_Hilog(LOG_INFO,format('PutBuf: buffer %dx%d < bitmap %dx%d, bg-fill',
      [hdl^.width, hdl^.height,
       OH_Drawing_BitmapGetWidth(FBitmap), OH_Drawing_BitmapGetHeight(FBitmap)])); }
    { Qt QPA 式 RepaintHelper：surface/buffer 池滞后（hdl < bitmap）——
      安排定时重绘重试，buffer 几何更新后恢复 1:1 }
    if fpgApplication is TfpgOhosApplication then
      TfpgOhosApplication(fpgApplication).ScheduleRepaintHelper(nativeWin);
  end;

  srcStride := OH_Drawing_BitmapGetWidth(FBitmap) * 4;
  dstStride := hdl^.stride;
  copyW := sw * 4;
  
  if copyW > dstStride then copyW := dstStride;
  if (sx * 4 + copyW) > srcStride then copyW := srcStride - sx * 4;
  
  copyH := sh;
  if copyH > hdl^.height - sy then copyH := hdl^.height - sy;

  { 整帧且步幅一致 → 单次 Move 快路径（替代逐行约 2400 次 Move） }
  if (copyW = srcStride) and (srcStride = dstStride) then
    Move(PByte(px)^, PByte(addr)^, copyH * srcStride)
  else
  for i := 0 to copyH - 1 do
    Move(PByte(px)[(sy + i) * srcStride + sx * 4], 
         PByte(addr)[(sy + i) * dstStride + sx * 4], 
         copyW);

  fpmunmap(addr, hdl^.size);

  regRect.x := sx;
  regRect.y := sy;
  regRect.w := copyW div 4;
  regRect.h := copyH;
  region.rects      := @regRect;
  region.rectNumber := 1;
  
  // 6. 提交 buffer（RequestBuffer 配套 FlushBuffer）
  OH_NativeWindow_NativeWindowFlushBuffer(nativeWin, buf, fence, region);

  // 7. 首帧通知：本窗口第一次成功上屏 → 告知 ETS 打开 XComponent 显示门
  //    （contentReady）。ETS 门在此之前保持 opacity=0（显示窗口页面背景），
  //    避免"未初始化的黑色 surface"闪现。
  if not FFirstFrameSent then
  begin
    FFirstFrameSent := True;
    fpGUI_Hilog(LOG_INFO, format('PutBuf FIRST OK: win=%s bmp=%dx%d hdl=%dx%d',
      [IntToHex(PtrUInt(nativeWin), 8), bmpW, bmpH,
       Integer(hdl^.width), Integer(hdl^.height)]));
    if Assigned(_notify_first_frame) then
      _notify_first_frame(nativeWin);
  end;
end;

procedure TfpgOhosCanvas.DoEndDraw;
var n: Integer;
begin
  if FSaveCount <> 0 then
  begin
   // 恢复原生画布状态
   //OH_Drawing_CanvasRestoreToCount(FCanvas, OH_Drawing_CanvasGetSaveCount(FCanvas) - 1);
   n := OH_Drawing_CanvasGetSaveCount(FCanvas);
   if n > FChildSaveCount then
     OH_Drawing_CanvasRestoreToCount(FCanvas, FChildSaveCount);
    { Child canvas: release references to parent's shared resources.
      Canvas state management (child offset translate) is handled in
      DoBeginDraw via the translate-reverse pattern — no RestoreToCount
      needed here since we never call CanvasSave in the child path. }
    FChildSaveCount := 0;
    FCanvas := nil;
    FBitmap := nil;
    FSaveCount := 0;
    { Balance parent FBeginDrawCount that was incremented in BeginDraw
      when the parent's BeginDraw was triggered from the child's BeginDraw. }
    while (FCanvasTarget <> nil) and (FCanvasTarget <> Self) and
          (TfpgOhosCanvas(FCanvasTarget).FBeginDrawCount > FParentBeginDrawCount) do
      FCanvasTarget.EndDraw;
  end;
end;

procedure TfpgOhosCanvas.DrawString(x, y: TfpgCoord; const txt: string);
var
  underline: integer;
  fontdesc: string;
  ulW, chW: Single;
  i, clen: Integer;
  ch: string;
  nativeFont: POH_Drawing_Font;
begin
  DoDrawString(x, y, txt);

  if Assigned(FFont) then
    fontdesc := FFont.FontDesc
  else
    fontdesc := '';

  if Pos('UNDERLINE', UpperCase(fontdesc)) > 0 then
  begin
    // Use real ascent + descent for accurate underline position
    underline := (FFont.GetDescent div 2) + 1;
    if underline = 0 then underline := 1;
    if underline >= FFont.GetDescent then underline := FFont.GetDescent - 1;
    DoSetLineStyle(1, lsSolid);
    DoSetColor(FTextColor);
    { Underline width must use the same per-character accumulation as
      DoDrawString, otherwise it drifts on long/scrollable text. }
    ulW := 0;
    nativeFont := nil;
    if (FFont <> nil) and (FFont is TfpgOhosFontResource) then
      nativeFont := TfpgOhosFontResource(FFont).NativeFont;
    if nativeFont <> nil then
    begin
      i := 1;
      while i <= Length(txt) do
      begin
        clen := Utf8CharLen(Byte(txt[i]));
        if clen < 1 then clen := 1;
        if i + clen - 1 > Length(txt) then clen := Length(txt) - i + 1;
        ch := Copy(txt, i, clen);
        chW := 0;
        OH_Drawing_FontMeasureText(nativeFont, PChar(ch), Length(ch), TEXT_ENCODING_UTF8, nil, @chW);
        ulW := ulW + Round(chW);
        Inc(i, clen);
      end;
    end;
    // OHOS +1 显示看起来稍好
    DoDrawLine(x, y + FFont.GetAscent + FFont.GetDescent - underline +1,
      x + Round(ulW), y + FFont.GetAscent + FFont.GetDescent - underline +1);
  end;
end;

function TfpgOhosCanvas.GetPixel(X, Y: integer): TfpgColor;
var
  px: Pointer;
  stride: UInt32;
  v: UInt32;
  sx, sy: Integer;
begin
  Result := 0;
  if FBitmap = nil then Exit;
  px := OH_Drawing_BitmapGetPixels(FBitmap);
  if px = nil then Exit;
  sx := Round((X + FDeltaX) * gScaleFactorX);
  sy := Round((Y + FDeltaY) * gScaleFactorY);
  stride := OH_Drawing_BitmapGetWidth(FBitmap) * 4;
  v := PLongWord(PByte(px) + sy * stride + sx * 4)^;
  // RGBA_8888 → fpGUI AARRGGBB: swap R↔B
  Result := (v and $FF00FF00) or ((v shr 16) and $FF) or ((v shl 16) and $FF0000);
end;

procedure TfpgOhosCanvas.SetPixel(X, Y: integer; const AValue: TfpgColor);
var
  px: Pointer;
  stride: UInt32;
  v: UInt32;
  sx, sy: Integer;
  bw, bh: Integer;
begin
  if FBitmap = nil then Exit;
  px := OH_Drawing_BitmapGetPixels(FBitmap);
  if px = nil then Exit;
  bw := OH_Drawing_BitmapGetWidth(FBitmap);
  bh := OH_Drawing_BitmapGetHeight(FBitmap);
  sx := Round((X + FDeltaX) * gScaleFactorX);
  sy := Round((Y + FDeltaY) * gScaleFactorY);
  { Bounds check: negative or oversized coordinates must not write outside
    the bitmap (unlike the hybrid canvas this one had no guard). }
  if (sx < 0) or (sy < 0) or (sx >= bw) or (sy >= bh) then Exit;
  stride := bw * 4;
//v := (AValue and $FF00FF00) or ((AValue shr 16) and $FF) or ((AValue shl 16) and $FF0000);
  { fpGUI $AARRGGBB → RGBA_8888 (swap R↔B); force alpha=0xFF: SetPixel is opaque
    by convention across backends, and the interpolation engine emits alpha=0. }
  v := (AValue and $0000FF00) or ((AValue shr 16) and $FF) or ((AValue shl 16) and $FF0000) or $FF000000;
  PLongWord(PByte(px) + sy * stride + sx * 4)^ := v;
end;

procedure TfpgOhosCanvas.CopyRect(ADest_x, ADest_y: TfpgCoord; ASrcCanvas: TfpgCanvasBase;
  var ASrcRect: TfpgRect);
var
  src: TfpgOhosCanvas;
  srcBmp: POH_Drawing_Bitmap;
  w, h: Integer;
  sRect, dRect: POH_Drawing_Rect;
begin
  if (ASrcCanvas = nil) or (FCanvas = nil) then Exit;
  SortRect(ASrcRect);
  w := ASrcRect.Right - ASrcRect.Left + 1;
  h := ASrcRect.Bottom - ASrcRect.Top + 1;
  if (w < 1) or (h < 1) then Exit;

  { Same-canvas copy or foreign canvas type: fall back to the base class
    per-pixel implementation (native in-place blit is undefined). }
  if (ASrcCanvas = Self) or not (ASrcCanvas is TfpgOhosCanvas) then
  begin
    inherited CopyRect(ADest_x, ADest_y, ASrcCanvas, ASrcRect);
    Exit;
  end;

  src := TfpgOhosCanvas(ASrcCanvas);
  srcBmp := src.FBitmap;
  if srcBmp = nil then Exit;

  { Source rect is in source bitmap pixel space (physical, ×gScaleFactor).
    Dest rect is logical: the target canvas carries the gScaleFactor transform. }
  sRect := OH_Drawing_RectCreate(ASrcRect.Left * gScaleFactorX, ASrcRect.Top * gScaleFactorY,
    (ASrcRect.Right + 1) * gScaleFactorX, (ASrcRect.Bottom + 1) * gScaleFactorY);
  dRect := OH_Drawing_RectCreate(ADest_x, ADest_y, ADest_x + w, ADest_y + h);
  OH_Drawing_CanvasDrawBitmapRect(FCanvas, srcBmp, sRect, dRect, nil);
  OH_Drawing_RectDestroy(dRect);
  OH_Drawing_RectDestroy(sRect);
end;

procedure TfpgOhosCanvas.GradientFill(ARect: TfpgRect; AStart, AStop: TfpgColor;
  ADirection: TGradientDirection);
var
  px: Pointer;
  stride, bw, bh: UInt32;
  x0, y0, x1, y1, runLen, i,m: Integer;
  r0, g0, b0, r1, g1, b1, rd, gd, bd: Integer;
  r, g, b: Integer;
  v: UInt32;
  row: PLongWord;
begin
  if FBitmap = nil then Exit;
  px := OH_Drawing_BitmapGetPixels(FBitmap);
  if px = nil then Exit;
  bw := OH_Drawing_BitmapGetWidth(FBitmap);
  bh := OH_Drawing_BitmapGetHeight(FBitmap);
  stride := bw * 4;

  { Logical rect (incl. canvas offset) → physical bitmap pixels. }
  x0 := Round((ARect.Left   + FDeltaX) * gScaleFactorX);
  y0 := Round((ARect.Top    + FDeltaY) * gScaleFactorY);
  x1 := Round((ARect.Right  + 1 + FDeltaX) * gScaleFactorX) - 1;
  y1 := Round((ARect.Bottom + 1 + FDeltaY) * gScaleFactorY) - 1;
  if x0 < 0 then x0 := 0;
  if y0 < 0 then y0 := 0;
  if x1 >= Integer(bw) then x1 := Integer(bw) - 1;
  if y1 >= Integer(bh) then y1 := Integer(bh) - 1;
  if (x1 < x0) or (y1 < y0) then Exit;

  r0 := (AStart shr 16) and $FF; g0 := (AStart shr 8) and $FF; b0 := AStart and $FF;
  r1 := (AStop  shr 16) and $FF; g1 := (AStop  shr 8) and $FF; b1 := AStop  and $FF;
  rd := r1 - r0; gd := g1 - g0; bd := b1 - b0;

  if ADirection = gdVertical then
  begin
    { Per-row gradient: each row is a single-colour run of contiguous
      memory → FillDWord (fast fill, ~4-8× faster than the pixel loop). }
    runLen := x1 - x0 + 1;
    for i := 0 to y1 - y0 do
    begin
      r := r0 + (i * rd) div (y1 - y0);
      g := g0 + (i * gd) div (y1 - y0);
      b := b0 + (i * bd) div (y1 - y0);
      { RGBA_8888 longword = AABBGGRR → R/B swapped }
      v := $FF000000 or (b shl 16) or (g shl 8) or r;
      row := PLongWord(PByte(px) + (y0 + i) * stride + x0 * 4);
      FillDWord(row^, runLen, v);
    end;
  end
  else
  begin
    { Per-column gradient (gdHorizontal): column pixels are non-contiguous
      (stride jumps between rows), keep per-pixel writes with pointer
      stepping instead of index arithmetic. }
    runLen := y1 - y0;   { rows to step }
    for i := 0 to x1 - x0 do
    begin
      r := r0 + (i * rd) div (x1 - x0);
      g := g0 + (i * gd) div (x1 - x0);
      b := b0 + (i * bd) div (x1 - x0);
      v := $FF000000 or (b shl 16) or (g shl 8) or r;
      row := PLongWord(PByte(px) + y0 * stride + (x0 + i) * 4);
      for m := 0 to runLen do
      begin
        row^ := v;
        Inc(PByte(row), stride);
      end;
    end;
  end;
end;

procedure TfpgOhosCanvas.DoDrawArc(x, y, w, h: TfpgCoord; a1, a2: double);
begin
  if FCanvas = nil then Exit;
  if FRect <> nil then OH_Drawing_RectDestroy(FRect);
  FRect := OH_Drawing_RectCreate(x + FDeltaX, y + FDeltaY, x + FDeltaX + w, y + FDeltaY + h);
  if FPen <> nil then OH_Drawing_CanvasAttachPen(FCanvas, FPen);
  OH_Drawing_CanvasDrawArc(FCanvas, FRect, a1, a2);
  if FPen <> nil then OH_Drawing_CanvasDetachPen(FCanvas);
end;

procedure TfpgOhosCanvas.DoFillArc(x, y, w, h: TfpgCoord; a1, a2: double);
begin
  if FCanvas = nil then Exit;
  if FRect <> nil then OH_Drawing_RectDestroy(FRect);
  FRect := OH_Drawing_RectCreate(x + FDeltaX, y + FDeltaY, x + FDeltaX + w, y + FDeltaY + h);
  if FBrush <> nil then OH_Drawing_CanvasAttachBrush(FCanvas, FBrush);
  OH_Drawing_CanvasDrawArc(FCanvas, FRect, a1, a2);
  if FBrush <> nil then OH_Drawing_CanvasDetachBrush(FCanvas);
end;

procedure TfpgOhosCanvas.DoDrawPolygon(const Points: array of TPoint);
var
  i: Integer;
  path: POH_Drawing_Path;
begin
  if (FCanvas = nil) or (Length(Points) < 2) then Exit;
  path := OH_Drawing_PathCreate();
  if path = nil then Exit;
  OH_Drawing_PathMoveTo(path, Points[0].X + FDeltaX, Points[0].Y + FDeltaY);
  for i := 1 to High(Points) do
    OH_Drawing_PathLineTo(path, Points[i].X + FDeltaX, Points[i].Y + FDeltaY);
  OH_Drawing_PathClose(path);
  if FPen <> nil then OH_Drawing_CanvasAttachPen(FCanvas, FPen);
  OH_Drawing_CanvasDrawPath(FCanvas, path);
  if FPen <> nil then OH_Drawing_CanvasDetachPen(FCanvas);
  OH_Drawing_PathDestroy(path);
end;

function TfpgOhosCanvas.GetBufferAllocated: Boolean;
begin
  Result := FBitmap <> nil;
end;

procedure TfpgOhosCanvas.DoAllocateBuffer;
var
  winRect: TfpgRect;
  fmt: TOH_Drawing_BitmapFormat;
begin
  if FCanvas <> nil then begin OH_Drawing_CanvasDestroy(FCanvas); FCanvas := nil; end;
  if FBitmap <> nil then begin OH_Drawing_BitmapDestroy(FBitmap); FBitmap := nil; end;
  FCanvas := OH_Drawing_CanvasCreate();
  FBitmap := OH_Drawing_BitmapCreate();
  if FWidget <> nil then
  begin
    winRect := FWidget.Window.GetClientRect;
    if winRect.Width < 1 then winRect.Width := 1;
    if winRect.Height < 1 then winRect.Height := 1;
  end
  else
  begin
    winRect.SetRect(0, 0, 100, 100);
  end;
  winRect.Width  := Round(winRect.Width  * gScaleFactorX);
  winRect.Height := Round(winRect.Height * gScaleFactorY);
  fmt.colorFormat := COLOR_FORMAT_RGBA_8888;
  fmt.alphaFormat := ALPHA_FORMAT_PREMUL;
  OH_Drawing_BitmapBuild(FBitmap, winRect.Width, winRect.Height, @fmt);
  OH_Drawing_CanvasBind(FCanvas, FBitmap);
  OH_Drawing_CanvasScale(FCanvas, gScaleFactorX, gScaleFactorY);
end;

function TfpgOhosCanvas.GetBitmapWidth: Integer;
begin
  if FBitmap <> nil then
    Result := OH_Drawing_BitmapGetWidth(FBitmap)
  else
    Result := 0;
end;

function TfpgOhosCanvas.GetBitmapHeight: Integer;
begin
  if FBitmap <> nil then
    Result := OH_Drawing_BitmapGetHeight(FBitmap)
  else
    Result := 0;
end;

function TfpgOhosCanvas.GetBitmapPixels: Pointer;
begin
  if FBitmap <> nil then
    Result := OH_Drawing_BitmapGetPixels(FBitmap)
  else
    Result := nil;
end;

{ ---------------------------------------------------------------------
  TfpgOhosWindow
  --------------------------------------------------------------------- }

constructor TfpgOhosWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FWinHandle := nil;
  FBuffer    := nil;
  FDecTop    := -1;   // 装饰偏移未查询（懒加载）
  FDecLeft   := -1;
end;

destructor TfpgOhosWindow.Destroy;
begin
  DoReleaseWindowHandle;
  inherited Destroy;
end;

function TfpgOhosWindow.HandleIsValid: boolean;
begin
  Result := FWinHandle <> nil;
end;

procedure TfpgOhosWindow.DoUpdateWindowPosition;
var
  scaledW, scaledH: Integer;
begin
  if FWinHandle <> nil then
  begin
    // Scale position from logical to physical pixels
    if Assigned(_ohos_move_window) then
      _ohos_move_window(FWinHandle, Round(FPosition.X * gScaleFactorX), Round(FPosition.Y * gScaleFactorY));
    // Resize buffer to physical pixel dimensions
    if (Owner is TfpgWidget) and (TfpgWidget(Owner).ActualWidth > 0) then
    begin
      scaledW := Round(TfpgWidget(Owner).ActualWidth  * gScaleFactorX);
      scaledH := Round(TfpgWidget(Owner).ActualHeight * gScaleFactorY);
    end
    else
    begin
      scaledW := Round(FSize.W * gScaleFactorX);
      scaledH := Round(FSize.H * gScaleFactorY);
    end;
    { ★ ETS windowSizeChange 反馈的 FPhysicalWidth/Height 是缓冲几何权威值。
      逻辑尺寸 × scale 的往返有损（Round 二次舍入），实测 ±1px：
        phys 829 → FSize 436 → Round(436×1.9)=828
        phys 995 → FSize 524 → Round(524×1.9)=996
      用这种值 SET_BUFFER_GEOMETRY 会把 ETS 刚推的正确几何覆写掉，
      致 hdl ≠ bitmap==phys 永久失配 → RepaintHelper 无限重试。
      差 ≤1px 视为同一尺寸，改推权威 phys；差 >1px 才是真实布局变化
      （应用改客户区/系统钳制），照推重算值，等 ETS 反馈回来再对齐。 }
    if (FPhysicalWidth > 0) and (Abs(scaledW - FPhysicalWidth) <= 1) then
      scaledW := FPhysicalWidth;
    if (FPhysicalHeight > 0) and (Abs(scaledH - FPhysicalHeight) <= 1) then
      scaledH := FPhysicalHeight;
    { +同步窗口逻辑尺寸：缓冲(GetClientRect=FSize)必须与 widget/窗口一致 (fpGUI-bug) }
    FSize.W := Round(scaledW / gScaleFactorX);
    FSize.H := Round(scaledH / gScaleFactorY);
    { 不去重：目标几何可能已被 ETS 以权威值推过，而缓冲池或因压缩态滞后，
      每次都推（等值重推是幂等的）才能让 RepaintHelper 的重试真正生效。 }
    if Assigned(_ohos_resize_window) then
      _ohos_resize_window(FWinHandle, scaledW, scaledH)
    else
      OH_NativeWindow_NativeWindowHandleOpt(FWinHandle, 1{SET_SIZE}, scaledW, scaledH);
  end;
end;

procedure TfpgOhosWindow.DoAllocateWindowHandle(AParent: TfpgWidgetBase);
var
  opts: TOHOSWindowOptions;
  s: single;
  pm: TfpgRect; 
  DesignW, DesignH, ScaledW, ScaledH, dX, dY: Integer;
  physX, physY: Integer; 
  expX, expY2, expY3: Integer;
  cw, ch: Integer;
  decTop, decW, decH: Integer;
begin
  // Fill WindowOptions struct and pass to C++ in one call.
  FillChar(opts, SizeOf(opts), 0);
  opts.windowType := Ord(FWindowType);
  opts.windowAttributes := WindowAttributesToInt(FWindowAttributes);
  opts.windowState := Ord(FWindowState);
  if (TfpgWidgetBase(Owner) = fpgApplication.MainForm) or (fpgApplication.MainForm = nil) then
    opts.isMainform := 1 
  else
    opts.isMainform := 0;
  opts.mouseCursor := Ord(FMouseCursor);
  opts.opacity := WindowOpacity;
  opts.left := Round(FPosition.X * gScaleFactorX);	
  opts.top := Round(FPosition.Y * gScaleFactorY);
  opts.width := Round(FSize.W * gScaleFactorX);   	
  opts.height := Round(FSize.H * gScaleFactorY);  	
  // Copy title (ensure null-terminated, capped at buffer size)
  { 标题来源（Qt QPA 式系统标题栏）：
    1. FTitle（DoSetWindowTitle 已同步——窗口创建后动态设置）
    2. Owner（PrimaryWidget = TfpgWindow 子类）的 WindowTitle——fpGUI 应用
       通常在 Create 阶段设置 WindowTitle := '...'（此时 FWindow 未创建，
       SetWindowTitle 只存 FWindowTitle；DoAllocateWindowHandle 时读取）
    3. fpgApplication.AppTitle（应用级默认） }
  if FTitle <> '' then
    StrPLCopy(opts.title, FTitle, SizeOf(opts.title) - 1)
  else if (Owner is TfpgWindow) and (TfpgWindow(Owner).WindowTitle <> '') then
    StrPLCopy(opts.title, TfpgWindow(Owner).WindowTitle, SizeOf(opts.title) - 1)
  else if fpgApplication <> nil then
    StrPLCopy(opts.title, fpgApplication.AppTitle, SizeOf(opts.title) - 1);

{ fpGUI源框架修复 / 或TfpgBaseForm.HandleShow里ScaleDPI;提到inherited前 }
//  opts.left 	:= Round(FPosition.X * gScaleFactor * gScaleFactorX); 	//主窗口适用
//  opts.top 	:= Round(FPosition.Y * gScaleFactor * gScaleFactorY);
//  opts.width 	:= Round(FSize.W * gScaleFactor * gScaleFactorX);    	
//  opts.height := Round(FSize.H * gScaleFactor * gScaleFactorY);   	
//  opts.left 	:= Round(FPosition.X {* gScaleFactor} * gScaleFactorX);	//弹窗适用
//  opts.top 	:= Round(FPosition.Y {* gScaleFactor} * gScaleFactorY);
//  opts.width 	:= Round(FSize.W {* gScaleFactor} * gScaleFactorX);   	
//  opts.height := Round(FSize.H {* gScaleFactor} * gScaleFactorY);  	
{ TWindowType = (wtChild, wtWindow, wtModalForm, wtPopup)（fpg_base.pas:54）—— 主窗体=wtWindow、模态=wtModalForm、弹窗=wtPopup
fpGUI原框架：主窗口创建时 ScaleDPI 尚未跑（而弹窗及子窗体无此问题）}
  if (FWindowType in [wtWindow, wtModalForm]) then
    s := gScaleFactor      // 主窗体创建时 ScaleDPI 未跑，补核心因子：480×1.8958=910
  else
    s := 1.0;              // 弹窗尺寸已含内容计算：不重复缩放
  if (Owner is TfpgWidget) and (TfpgWidget(Owner).ActualWidth > 0) and (FWindowType in [wtWindow, wtModalForm]){popup用自己的FSize，不用Owner覆盖} then
  begin
    opts.width  := Round(TfpgWidget(Owner).ActualWidth  * gScaleFactorX * s);
    opts.height := Round(TfpgWidget(Owner).ActualHeight * gScaleFactorY * s);
  end
  else
  begin
    opts.width  := Round(FSize.W * gScaleFactorX * s);
    opts.height := Round(FSize.H * gScaleFactorY * s);
  end;
{ 居中位置修正（纯启发式，无 RTTI/框架依赖）：
  fpGUI 居中公式（fpg_form.pas:529-555）在 ScaleDPI 前用设计宽度计算 → 混合空间偏右下。
  弹窗居中位置计算在 TfpgBaseForm.DoAllocateWindowHandle（fpg_form.pas:523-559），发生在 ScaleDPI 之前 —— 这是混合空间计算的 bug。
  特征检测：FPosition 若符合 (pm.W-DesignW)/2 与 /2 或 /3 → 居中类模式。
  修正后写两个空间：
    widget.Left/FPosition  ← 物理值（DoUpdateWindowPosition 直接用；ScaleDPI 后被 widget.Left 覆盖为同值）
    widget.Left  ← 设计值 physX/gScaleFactor（ScaleDPI 放大后 = physX，闭环一致）}
if (FWindowType in [wtWindow, wtModalForm]) and (gScaleFactor <> 1.0) and
   (Owner is TfpgWidget) then
begin
  pm := fpgApplication.Desktop.AvailableGeometry(fpgApplication.Desktop.PrimaryScreen);
  DesignW := TfpgWidget(Owner).ActualWidth;
  DesignH := TfpgWidget(Owner).ActualHeight;
  ScaledW := Round(DesignW * gScaleFactor);
  ScaledH := Round(DesignH * gScaleFactor);
  expX := pm.Left + (pm.Width  - DesignW) div 2;   // 居中公式 X（/2，两种模式同）
  expY2 := pm.Top + (pm.Height - DesignH) div 2;   // wpScreenCenter Y
  expY3 := pm.Top + (pm.Height - DesignH) div 3;   // wpOneThirdDown Y
  if (abs(FPosition.X - expX) <= 2) and
     ((abs(FPosition.Y - expY2) <= 2) or (abs(FPosition.Y - expY3) <= 2)) then
  begin
    dX := (ScaledW - DesignW) div 2;               // 物理空间偏差
    if abs(FPosition.Y - expY2) <= 2 then
      dY := (ScaledH - DesignH) div 2
    else
      dY := (ScaledH - DesignH) div 3;
    physX := FPosition.X - dX;                     // 期望物理位置（居中）
    physY := FPosition.Y - dY;
    opts.left := Round(physX * gScaleFactorX);     // 创建即正确（无首帧跳动）
    opts.top  := Round(physY * gScaleFactorY);
    TfpgWidget(Owner).Left := Round(physX / gScaleFactor);  // 设计空间（ScaleDPI 放大后=physX）
    TfpgWidget(Owner).Top  := Round(physY / gScaleFactor);
    FPosition.X := physX;                          // 物理值：创建后 DoUpdateWindowPosition 直接用
    FPosition.Y := physY;
  end;
end;
{ 位置 clamp（逻辑空间）：对话框居中计算混合空间可能产生偏右下的 FPosition，
  加标题栏后总高超出屏幕 → 底部 OK/Cancel 不可见。收进逻辑屏幕内。
  Y 预留标题栏逻辑高度：优先精确查询主窗口装饰 decH（vp，ETS setMainWindowDec
  上报 → C++ 缓存）。
  尺寸用 widget 实际值（创建时 FSize 可能未同步为 0）。 }
if (FWindowType in [wtWindow, wtModalForm]) and (gOhosScreenW > 0) then
begin
  if (Owner is TfpgWidget) then
  begin
    cw := TfpgWidget(Owner).ActualWidth;
    ch := TfpgWidget(Owner).ActualHeight;
  end
  else
  begin
    cw := FSize.W;
    ch := FSize.H;
  end;
  if Assigned(_ohos_get_main_window_decoration) then
  begin
    decW := 0; decH := 0;
    _ohos_get_main_window_decoration(decW, decH);
    if decH > 0 then
    begin 
      decTop := decH;
	  fpGUI_Hilog(LOG_INFO, format('clamp-before type=%d pos=(%d,%d) cw=%d ch=%d screen=(%d,%d) decTop=%d',
	    [Ord(FWindowType), FPosition.X, FPosition.Y, cw, ch, gOhosScreenW, gOhosScreenH, decTop]));
	  if FPosition.X + cw > gOhosScreenW then FPosition.X := gOhosScreenW - cw;
	  if FPosition.Y + ch + decTop > gOhosScreenH then FPosition.Y := gOhosScreenH - ch - decTop;
	  if FPosition.X < 0 then FPosition.X := 0;
	  if FPosition.Y < 0 then FPosition.Y := 0;
	  fpGUI_Hilog(LOG_INFO, format('clamp-after pos=(%d,%d)', [FPosition.X, FPosition.Y]));
    end;
  end;
end;
opts.left := Round(FPosition.X * gScaleFactorX);   // 原式不变，FPosition 已修正
opts.top  := Round(FPosition.Y * gScaleFactorY);  
// 嵌入模式：
if (Owner is TfpgWidgetBase) and (TfpgWidgetBase(Owner).EmbeddedSurfaceId <> 0) then
  opts.SurfaceId := TfpgWidgetBase(Owner).EmbeddedSurfaceId;

if (Owner is TfpgWidget) then
  fpGUI_Hilog(LOG_INFO, format('ohos_create_window- type=%d wdg=(%d,%d) s=%.4f gfx=%.4f gfy=%.4f gsf=%.4f pos=(%d,%d) opts=(%d,%d,%d,%d)',
    [Ord(FWindowType),
     TfpgWidget(Owner).ActualWidth, TfpgWidget(Owner).ActualHeight,
     s, gScaleFactorX, gScaleFactorY, gScaleFactor,
     FPosition.X, FPosition.Y,
     opts.left, opts.top, opts.width, opts.height]))
else
  fpGUI_Hilog(LOG_INFO, format('ohos_create_window- type=%d wdg=nonwidget s=%.4f gfx=%.4f gfy=%.4f gsf=%.4f pos=(%d,%d) opts=(%d,%d,%d,%d)',
    [Ord(FWindowType),
     s, gScaleFactorX, gScaleFactorY, gScaleFactor,
     FPosition.X, FPosition.Y,
     opts.left, opts.top, opts.width, opts.height]));

  // Create sub-window at physical pixel size.
  if Assigned(_ohos_create_window) then
  begin
    FWinHandle := _ohos_create_window(@opts);
    FPhysicalWidth := opts.width;
    FPhysicalHeight := opts.height;
  end;

  { Apply position that was set via FPosition/UpdateWindowPosition before the
    native handle existed (e.g., from TfpgWidget.DoAllocateWindowHandle line 452
    which calls UpdatePosition before Window.AllocateWindowHandle line 461). }
  if (FWinHandle <> nil) then
  begin
    if opts.SurfaceId=0 then
      DoUpdateWindowPosition;
    if Owner is TfpgWidget then
      TfpgWidget(Owner).Invalidate;
  end;

  { Register this window handle with the application for touch event routing }
  if (FWinHandle <> nil) and (fpgApplication is TfpgOhosApplication) then
    TfpgOhosApplication(fpgApplication).RegisterWindowHandle(FWinHandle, Self);

  { 补发拖入开关（DoDNDEnabled 在句柄创建前被调用时——DropHandler 常于窗体创建期设置）}
  if (FWinHandle <> nil) and FDNDEnabledQueued then
  begin
    if Assigned(_ohos_set_dnd_enabled) then
      _ohos_set_dnd_enabled(FWinHandle, 1);
  end;

  { The newly created window takes keyboard focus until the user touches
    somewhere else. Dropdowns/popups never reach DoSetWindowVisible(True)
    (TfpgPopupWindow.ShowAt does not set Visible), so track focus here too. }
  if FWinHandle <> nil then
    gFocusedWinHandle := FWinHandle;
end;

procedure TfpgOhosWindow.SetPhysicalSize(AW, AH: Integer);
begin
  FPhysicalWidth := AW;
  FPhysicalHeight := AH;
  { 同步逻辑总尺寸：ETS windowSizeChange 为客户区 px → 逻辑=÷gfx。
    fpGUI FPGM_RESIZE→HandleResize 只更新 PrimaryWidget 布局，窗口基类
    FSize 未跟随 → 最大化/还原后触摸命中。与渲染物理尺寸一并同步。 }
  FSize.W := Round(AW / gScaleFactorX);
  FSize.H := Round(AH / gScaleFactorY);
  fpGUI_Hilog(LOG_INFO, format('SetPhysicalSize h=%s phys=%dx%d FSize=%dx%d',
    [IntToHex(PtrUInt(FWinHandle), 8), AW, AH, FSize.W, FSize.H]));
end;

procedure TfpgOhosWindow.SetScreenPosition(AX, AY: Integer);
begin
  FPosition.X := Round(AX / gScaleFactorX);
  FPosition.Y := Round(AY / gScaleFactorY);
  fpGUI_Hilog(LOG_INFO, format('SetScreenPosition handle=%s px=%d,%d log=(%d,%d)',
    [IntToHex(PtrUInt(FWinHandle), 8), AX, AY, FPosition.X, FPosition.Y]));
end;

procedure TfpgOhosWindow.InvalidateNativeHandle;
begin
  fpGUI_Hilog(LOG_INFO, format('InvalidateNativeHandle: %s -> nil',
    [IntToHex(PtrUInt(FWinHandle), 8)]));
  FWinHandle := nil;
  { 窗口句柄已失效（系统销毁/buffer 释放）：解除 caret 防悬空 blink（编辑框重绘会恢复）}
  if fpgApplication is TfpgOhosApplication then
    TfpgOhosApplication(fpgApplication).UnsetCaretOnWindowInvalid;
end;

procedure TfpgOhosWindow.DoReleaseWindowHandle;
begin
  if FWinHandle <> nil then
  begin
    { Clear modal tracking when modal window is destroyed }
    if FWinHandle = gModalWinHandle then
      gModalWinHandle := nil;
    { Clear keyboard focus if this window held it (avoid routing to a
      destroyed handle after the dropdown closes) }
    if FWinHandle = gFocusedWinHandle then
      gFocusedWinHandle := nil;
    if Assigned(_set_modal_window) then
      _set_modal_window(nil);
    { Unregister before destroying the native window }
    if fpgApplication is TfpgOhosApplication then
      TfpgOhosApplication(fpgApplication).UnregisterWindowHandle(FWinHandle);
    if Assigned(_ohos_destroy_window) then
      _ohos_destroy_window(FWinHandle)
    else
      OH_NativeWindow_DestroyNativeWindow(FWinHandle);
    FWinHandle := nil;
  end;
  { Defense-in-depth: drop any fpGUI messages still queued for this window.
    A popup submenu can be destroyed while a MOUSEUP/MOVEMOVE posted to it
    is still in the queue; dispatching it afterwards would dereference a
    freed object at msg.Dest.Dispatch (SIGSEGV @ 0xa0). fpgDeliverMessage
    runs without the queue lock, so this is safe during message dispatch. }
  fpgDeleteMessagesForTarget(Self, -1);
  { 窗口资源已释放：解除 caret 防悬空 blink（编辑框重绘会恢复闪烁）}
  if fpgApplication is TfpgOhosApplication then
    TfpgOhosApplication(fpgApplication).UnsetCaretOnWindowInvalid;
end;

procedure TfpgOhosWindow.DoRemoveWindowLookup;
begin
  { Cleanup already performed in DoReleaseWindowHandle:
    - UnregisterWindowHandle removed the entry from FWinHandleMap
    - _ohos_destroy_window destroyed the native window.
    At this point FWinHandle = nil — nothing left to do. 
    DoRemoveWindowLookup 在窗口析构时由基类调用：
	Destroy → DoReleaseWindowHandle → DoRemoveWindowLookup(line 2493)
										 ↑ 此时窗口句柄已销毁
    OHOS 的 DoReleaseWindowHandle 已经完成了所有清理：1. 从应用句柄映射表移除 2. 销毁 OHOS 原生窗口
    到 DoRemoveWindowLookup 被调用时，FWinHandle = nil 且 UnregisterWindowHandle 已完成。
    OHOS 上无需额外操作。
  }
end;

procedure TfpgOhosWindow.DoSetWindowAttributes(const AOldAtributes, ANewAttributes: TWindowAttributes; const AForceAll: Boolean);
begin
  { Re-apply window title when attributes are forced (window just created)
    or when title was set before the window handle existed.
    The C++ bridge g_nextWindowTitle is consumed during ohos_create_window,
    so we push it again for already-created windows. }
  if AForceAll and (FWinHandle <> nil) and (FTitle <> '') then
    DoSetWindowTitle(FTitle);
  { 窗口属性位掩码 → ETS（waFullScreen/waBorderless/waStayOnTop/
    waSystemStayOnTop 等；基类 SetWindowAttributes 仅在 HasHandle 时调本方法，
    创建前属性由 opts.windowAttributes 生效）}
  if FWinHandle = nil then Exit;
  if Assigned(_ohos_set_window_attributes) then
    _ohos_set_window_attributes(FWinHandle, WindowAttributesToInt(ANewAttributes));
end;

procedure TfpgOhosWindow.DoSetWindowVisible(const AValue: Boolean);
begin
  if AValue then
  begin
    { Track focused window for keyboard routing }
    if FWinHandle <> nil then
      gFocusedWinHandle := FWinHandle;
    { Track modal windows so ProcessQueuedEvents can block parent input }
    if FWindowType = wtModalForm then
    begin
      gModalWinHandle := FWinHandle;
      { Notify C++ bridge about the modal window handle (for ETS auto-raise) }
      if Assigned(_set_modal_window) then
        _set_modal_window(FWinHandle);
    end;
  end
  else
  begin
    { Clear modal tracking when modal window is hidden }
    if (FWinHandle <> nil) and (FWinHandle = gModalWinHandle) then
    begin
      gModalWinHandle := nil;
      if Assigned(_set_modal_window) then
        _set_modal_window(nil);
    end;
  end;
  if (Owner <> nil) and (Owner is TfpgWidget) and
     (TfpgWidgetBase(Owner).Canvas is TfpgOhosCanvas) then
    TfpgOhosCanvas(TfpgWidgetBase(Owner).Canvas).FFirstFrameSent := False;
  { AGG 混合画布路径：首帧标志在 TOhosBufferManager.FFirstFrameSent（不同单元），
      经 FirstFrameResetPending 公共字段传递重置请求——下一次 AttachWindow 消费。
      无条件置位对非 AGG 无害（不读此字段）。覆盖 hide→show 句柄未变但 contentReady
      回 false 的场景（与非 AGG 上方重置同效）。 }
  FirstFrameResetPending := True;
  if Assigned(_ohos_set_window_visible) and (FWinHandle <> nil) then
    _ohos_set_window_visible(FWinHandle, Integer(AValue));
  if AValue and (Owner is TfpgWidget) then
    TfpgWidget(Owner).Invalidate;
end;

procedure TfpgOhosWindow.DoMoveWindow(const x: TfpgCoord; const y: TfpgCoord);
begin
  if Assigned(_ohos_move_window) then
  begin
    if FWinHandle <> nil then
      _ohos_move_window(FWinHandle, Round(x * gScaleFactorX), Round(y * gScaleFactorY));
    // If handle is nil, position will be applied in DoUpdateWindowPosition
    // after AllocateWindowHandle creates the native window.
  end;
end;

function TfpgOhosWindow.DoWindowToScreen(ASource: TfpgWindowBase; const AScreenPos: TPoint): TPoint;
var
  w: TfpgOhosWindow;
  decW, decH: Integer;
begin
  // Add the source window's screen position to the widget-relative coordinates.
  // ASource is the window containing the widget; its FPosition holds the screen
  // position set by UpdateWindowPosition. This is needed for ShowAt to position
  // popup menus at the correct screen location relative to the source widget.
  Result.X := AScreenPos.X + ASource.Left;
  Result.Y := AScreenPos.Y + ASource.Top;
  { 窗口带系统装饰（标题栏）时：FPosition = 窗口顶（标题栏顶），而 widget 坐标为
    客户区坐标 → 屏幕位置需补本窗口标题栏高（per-window FDecTop，px，懒加载查询）。
    ETS 在 setupMainWindow/createSubWin 经 setWindowDec 上报 →
    C++ ohos_get_window_decoration（bridge get_window_decoration）。 }
  if ASource is TfpgOhosWindow then
  begin
    w := TfpgOhosWindow(ASource);
    if w.FDecTop < 0 then
    begin
      w.FDecTop := 0; w.FDecLeft := 0;
      if Assigned(_ohos_get_window_decoration) and (w.FWinHandle <> nil) then
      begin
        decW := 0; decH := 0;
        _ohos_get_window_decoration(w.FWinHandle, decW, decH);
        { decH = 标题栏 + 下边框（下边框≈边框宽）→ 标题栏真高 = decH - 下边框；
          下边框 ≈ decW/2（左右对称）。FDecLeft = 左边框（X 补偿）。 }
        w.FDecLeft := decW div 2;
        w.FDecTop := decH - decW div 2;
        if w.FDecTop < 0 then w.FDecTop := 0;
      end;
    end;
    if (w.FDecTop > 0) and (w.FWindowType in [wtWindow, wtModalForm]) then
    begin
      // 自绘标题栏：borderless 回退窗系统装饰=0，但 ETS titleBar=1 窗口
      // setWindowDec(reqId,0,titleBarVp) 上报自绘标题栏高（vp）→ FDecTop>0。
      // 若仍按 waBorderless 拦掉，菜单/弹窗锚点漏补偿 → 弹出位置偏上=标题栏高。
      // borderless 且未上报时 FDecTop=0，无副作用。
      Result.X := Result.X + round(w.FDecLeft/gZoomScale);
      Result.Y := Result.Y + round(w.FDecTop/gZoomScale);
    end;
    fpGUI_Hilog(LOG_INFO, format('DoWindowToScreen wtype=%d in=(%d,%d) winL=(%d,%d) decTop=%d decLeft=%d out=(%d,%d)',
      [Ord(w.FWindowType), AScreenPos.X, AScreenPos.Y, ASource.Left, ASource.Top,
       w.FDecTop, w.FDecLeft, Result.X, Result.Y]));
  end
  else
    fpGUI_Hilog(LOG_INFO, format('DoWindowToScreen NON-OHOS in=(%d,%d) out=(%d,%d)',
      [AScreenPos.X, AScreenPos.Y, Result.X, Result.Y]));
end;

procedure TfpgOhosWindow.DoSetWindowTitle(const ATitle: string);
begin
  FTitle := ATitle;
  if Assigned(_ohos_set_window_title) then
    _ohos_set_window_title(FWinHandle, PChar(ATitle));
end;

{ 窗口状态 → OHOS（minimize/maximize/restore）。
  基类 SetWindowState 为空实现且不更新 FWindowState——此处自维护
  （GetWindowState 依赖它）。创建前设置由 opts.windowState 生效。 }
procedure TfpgOhosWindow.SetWindowState(const AValue: TfpgWindowState);
begin
  if FWindowState = AValue then Exit;
  FWindowState := AValue;
  if FWinHandle = nil then Exit;
  if Assigned(_ohos_set_window_state) then
    _ohos_set_window_state(FWinHandle, Ord(AValue));
end;

{ 查询真实系统窗口状态（v10）。
  OHOS OHNativeWindow* 不含状态信息，必须经 C++ 缓存桥查询。
  C++ 缓存由 ETS windowStatusChange 事件实时更新。
  状态映射：OHOS WindowStatusType → TfpgWindowState }
function TfpgOhosWindow.GetWindowState: TfpgWindowState;
var
  ohosState: Integer;
begin
  Result := inherited GetWindowState;  // fallback: 内存变量
  if FWinHandle = nil then Exit;
  if not Assigned(_ohos_get_window_state) then Exit;
  ohosState := _ohos_get_window_state(FWinHandle);
  case ohosState of
    3: Result := wsMinimized;   // MINIMIZE
    1, 2: Result := wsMaximized; // FULL_SCREEN, MAXIMIZE
  else
    Result := wsNormal;          // UNDEFINED, FLOATING, SPLIT_SCREEN
  end;
end;

{ 全屏切换 → OHOS（沉浸式全屏）。
  基类 SetFullscreen 仅修改 waFullScreen 标志位，不触发 DoSetWindowAttributes。
  此处 override 后发送属性位掩码到 ETS，由 applyWindowAttributes 执行实际全屏操作。 }
procedure TfpgOhosWindow.SetFullscreen(AValue: Boolean);
begin
  inherited SetFullscreen(AValue);
  if FWinHandle = nil then Exit;
  if Assigned(_ohos_set_window_attributes) then
    _ohos_set_window_attributes(FWinHandle, WindowAttributesToInt(FWindowAttributes));
end;

{ 窗口透明度 → OHOS（OpenHarmony SDK 无 setWindowOpacity：
  桥通道建立，ETS 暂存预留；基类正常存 FWindowOpacity）。
  创建前设置由 opts.opacity 生效。 }
procedure TfpgOhosWindow.SetWindowOpacity(AValue: Single);
begin
  inherited SetWindowOpacity(AValue);
  if FWinHandle = nil then Exit;
  if Assigned(_ohos_set_window_opacity) then
    _ohos_set_window_opacity(FWinHandle, AValue);
end;

procedure TfpgOhosWindow.DoSetMouseCursor;
const
  { Map fpGUI TMouseCursor to OHOS Input_PointerStyle
    (核对 oh_pointer_style.h；mcSizeSWNE→NESW=11、mcSizeSENW→NWSE=12 ) }
  CursorMap: array[TMouseCursor] of Integer = (
    0,  0, 13, 26, 22, 23, 12, 11, 11, 12,
    21, 42, 19, 17, 15, 0
  );
var
  ohosStyle: Integer;
begin
  { per-window 光标优先（ETS 已上报各窗口 windowId；C++ 按句柄查表）}
(*
  if not Assigned(_set_pointer_style_to) then
  begin
    Pointer(_set_pointer_style_to) := LibBridgeSym('ohos_set_pointer_style_to');
    if not Assigned(_set_pointer_style_to) then
    begin
      if not Assigned(_set_pointer_style) then
      begin
        Pointer(_set_pointer_style) := LibBridgeSym('ohos_set_pointer_style');
        if not Assigned(_set_pointer_style) then Exit;
      end;
      if FMouseCursor <= High(CursorMap) then
        ohosStyle := CursorMap[FMouseCursor]
      else
        ohosStyle := 0;
      _set_pointer_style(ohosStyle);   { 旧主窗版兜底 }
      Exit;
    end;
  end;
*)  
  if FMouseCursor <= High(CursorMap) then
    ohosStyle := CursorMap[FMouseCursor]
  else
    ohosStyle := 0;
  _set_pointer_style(Self.WinHandle, ohosStyle);
end;

procedure TfpgOhosWindow.DoDNDEnabled(const AValue: boolean);
begin
  { 句柄未建时暂存，创建后补发（GDI QueueAcceptDrops 同式；见 DoAllocateWindowHandle 末尾）}
  FDNDEnabledQueued := AValue;
  if FWinHandle = nil then Exit;
  if Assigned(_ohos_set_dnd_enabled) then
    _ohos_set_dnd_enabled(FWinHandle, Integer(AValue));
end;

procedure TfpgOhosWindow.ActivateWindow;
begin
  if Assigned(_ohos_set_window_visible) and (FWinHandle <> nil) then
    _ohos_set_window_visible(FWinHandle, 1);
end;

procedure TfpgOhosWindow.CaptureMouse(AForWidget: TfpgWidgetBase);
begin
  { Active capture: DispatchMouseEvent routes all mouse messages to the
    captured widget while it is set (fpg_base.pas:2537). }
  MouseCapture := AForWidget;
end;

procedure TfpgOhosWindow.ReleaseMouse;
begin
  MouseCapture := nil;
end;

procedure TfpgOhosWindow.BringToFront;
begin
  ActivateWindow;
end;

{ ---------------------------------------------------------------------
  TfpgOhosApplication
  --------------------------------------------------------------------- }

function setenv(const name, value: PChar; overwrite: LongInt): LongInt; cdecl; external 'c';

constructor TfpgOhosApplication.Create(const AParams: string);
var
  i: Integer;
  p: PChar;
  fpgSearchPath: string;
begin
  inherited Create(AParams);
  FScreenW := 1920;
  FScreenH := 1080;
  FScreenDpi := 160;
  FEventQueue := TList.Create;
  FEventQueueLock := TCriticalSection.Create;
  FKeyEventQueue := TList.Create;
  FResizeQueue := TList.Create;
  FResizeQueueLock := TCriticalSection.Create;
  FTrayEventQueue := TList.Create;
  FConfigQueue := TList.Create;
  FKeyQueueLock := TCriticalSection.Create;
  FTrayQueueLock := TCriticalSection.Create;
  FConfigQueueLock := TCriticalSection.Create;
  FWinCmdLock := TCriticalSection.Create;
  FWinCmdQueue := TList.Create;
  FDragQueue := TList.Create;
  FDragQueueLock := TCriticalSection.Create;
  { 拖拽会话（单会话全局；锁与事件在此初始化，避免注入线程竞态懒建）}
  if gDragSessionLock = nil then
    gDragSessionLock := TCriticalSection.Create;
  if gDragSession.EndEvent = nil then
    gDragSession.EndEvent := TEvent.Create(nil, True, False, '');   { 手动复位 }
  gDragSession.Active := False;
  gDragSession.SessionId := 0;
  gDragSession.Result := OHOS_DRAG_RESULT_CANCELED;
  gDragSession.DragRef := nil;
  gDragSession.Drop := nil;
  gDragSession.DropWinHandle := nil;
  gDragSession.DropRecords := '';
  gDragSession.DropAccept := False;
  gDragSession.DropAction := daIgnore;
  FLastKeyboardType := -1;   { force first UpdateKeyboardVisibility to send }
  FLastKeyDown := 0;
  FCutKeyPending := False;
  FWinHandleMap := TList.Create;
  FRepaintWin := nil;
  FRepaintTicks := 0;
  FRepaintNext := 0;
  WakeChannel := TfpgOhosWakeChannel.Create;
  WakeChannel.Open;
  { 动态分发：注入主循环唤醒 + 结果回传（WakeChannel 就绪后）}
  if assigned(gDispatchUIThreadId) then gDispatchUIThreadId(GetCurrentThreadId); { 当前即 fpGUI 主线程 }
  FIsInitialized := True;
  { 启动调试：打印 FontMgr 家族清单（前 25 个），用于校准 CJK 匹配/默认映射 }
  DumpFontFamilies;
  { 系统字体配置：权威字体目录 + 默认家族（版本/厂商无关）}
  OhosLoadSystemFontConfig;
  { WakeMainThread disabled for OHOS: FPC target does not support
    class method as procedure-of-object, and TMethod(Code, nil) hack
    causes instability. The event loop uses fpSelect on wake pipe
    instead — this is sufficient for single-threaded fpGUI apps. }
  Classes.WakeMainThread := nil;
  FSelection := TfpgOhosClipboard.Create;

	if Assigned(_get_user_dir) then
	begin
	  // rawfile Dir
	  p := _get_user_dir(0);  
	  if (p <> nil) and (p[0] <> #0) then
	  begin
        if setenv('HOME', p, 1) = 0 then
          fpGUI_Hilog(LOG_INFO, format('HOME redirected?: %s' , [strpas(p)]))
        else
          fpGUI_Hilog(LOG_INFO, format('HOME redirect failed: %s' , [strpas(p)]));
	    cfree(p);
	  end else if p <> nil then
        cfree(p);
      // resfile Dir
	  p := _get_user_dir(3);  
	  if (p <> nil) and (p[0] <> #0) then
	  begin
        fpgSearchPath := fpgAppendPathDelim(fpgFromOSEncoding(p));
        if fpgSetCurrentDir(fpgSearchPath) then
          fpGUI_Hilog(LOG_INFO, 'CWD redirected to resfile: ' + fpgSearchPath)
        else
          fpGUI_Hilog(LOG_INFO, 'CWD redirect failed: ' + fpgSearchPath);
	    cfree(p);
	  end else if p <> nil then
        cfree(p);
	end;
  
end;

destructor TfpgOhosApplication.Destroy;
var
  i: Integer;
begin
  Classes.WakeMainThread := nil;
  if WakeChannel <> nil then
  begin
    WakeChannel.Close;
    WakeChannel := nil;
  end;
  { Clean up touch event queue }
  if FEventQueue <> nil then
  begin
    for i := 0 to FEventQueue.Count - 1 do
      Dispose(PfpgOhosTouchEvent(FEventQueue[i]));
    FEventQueue.Free;
  end;
  { Clean up key event queue }
  if FKeyEventQueue <> nil then
  begin
    FKeyQueueLock.Enter;
    try
      for i := 0 to FKeyEventQueue.Count - 1 do
        Dispose(PfpgOhosKeyEvent(FKeyEventQueue[i]));
      FKeyEventQueue.Free;
    finally
      FKeyQueueLock.Leave;
    end;
  end;
  if FKeyQueueLock <> nil then
    FKeyQueueLock.Free;
  { Clean up event queue (mouse/hover touch) }
  if FEventQueue <> nil then
  begin
    FEventQueueLock.Enter;
    try
      for i := 0 to FEventQueue.Count - 1 do
        Dispose(PfpgOhosTouchEvent(FEventQueue[i]));
      FEventQueue.Free;
    finally
      FEventQueueLock.Leave;
    end;
  end;
  if FEventQueueLock <> nil then
    FEventQueueLock.Free;
  { Clean up resize event queue }
  if FResizeQueue <> nil then
  begin
    FResizeQueueLock.Enter;
    try
      for i := 0 to FResizeQueue.Count - 1 do
        Dispose(PfpgOhosResizeEvent(FResizeQueue[i]));
      FResizeQueue.Free;
    finally
      FResizeQueueLock.Leave;
    end;
  end;
  if FResizeQueueLock <> nil then
    FResizeQueueLock.Free;
  { Clean up tray event queue }
  if FTrayEventQueue <> nil then
  begin
    FTrayQueueLock.Enter;
    try
      for i := 0 to FTrayEventQueue.Count - 1 do
        Dispose(PfpgOhosTrayEvent(FTrayEventQueue[i]));
      FTrayEventQueue.Free;
    finally
      FTrayQueueLock.Leave;
    end;
  end;
  if FTrayQueueLock <> nil then
    FTrayQueueLock.Free;
  { Clean up config event queue }
  if FConfigQueue <> nil then
  begin
    FConfigQueueLock.Enter;
    try
      for i := 0 to FConfigQueue.Count - 1 do
        Dispose(PfpgOhosConfigEvent(FConfigQueue[i]));
      FConfigQueue.Free;
    finally
      FConfigQueueLock.Leave;
    end;
  end;
  if FConfigQueueLock <> nil then
    FConfigQueueLock.Free;
  { Clean up window command queue }
  if FWinCmdQueue <> nil then
  begin
    if FWinCmdLock <> nil then
      FWinCmdLock.Enter;
    try
      for i := 0 to FWinCmdQueue.Count - 1 do
        Dispose(PfpgOhosWinCmd(FWinCmdQueue[i]));
      FWinCmdQueue.Free;
    finally
      if FWinCmdLock <> nil then
        FWinCmdLock.Leave;
    end;
  end;
  if FWinCmdLock <> nil then
    FWinCmdLock.Free;
  { Clean up drag event queue }
  if FDragQueue <> nil then
  begin
    FDragQueueLock.Enter;
    try
      for i := 0 to FDragQueue.Count - 1 do
        Dispose(PfpgOhosDragEvent(FDragQueue[i]));
      FDragQueue.Free;
    finally
      FDragQueueLock.Leave;
    end;
  end;
  if FDragQueueLock <> nil then
    FDragQueueLock.Free;
  { Clean up window handle map (don't free the windows, just the list entries) }
  if FWinHandleMap <> nil then
  begin
    { List stores plain TfpgWinHandle pointers; just free the list }
    FWinHandleMap.Free;
  end;
  inherited Destroy;
end;

procedure TfpgOhosApplication.RegisterWindowHandle(AHandle: TfpgWinHandle; AWindow: TfpgWindowBase);
begin
  if (AHandle = nil) or (AWindow = nil) then Exit;
  if FWinHandleMap = nil then Exit;
  { Store handle+window pair as two consecutive pointers in the list
    （窗口表仅由 loop 线程访问——窗口桥已串行化入队，无需锁；
     FPC 临界区在 Linux 不可重入，加锁曾导致嵌套重入死锁）}
  FWinHandleMap.Add(AHandle);
  FWinHandleMap.Add(AWindow);
end;

procedure TfpgOhosApplication.UnregisterWindowHandle(AHandle: TfpgWinHandle);
var
  i: Integer;
begin
  if (AHandle = nil) or (FWinHandleMap = nil) then Exit;
  for i := 0 to (FWinHandleMap.Count div 2) - 1 do
  begin
    if FWinHandleMap[i * 2] = AHandle then
    begin
      FWinHandleMap.Delete(i * 2);      // delete handle
      FWinHandleMap.Delete(i * 2);      // delete window (now at same index)
      Exit;
    end;
  end;
end;

{ Standalone procedure for WakeMainThread callback (workaround for FPC OHOS
  limitation on class method as procedure-of-object) }
procedure _OhosWakeMainThread(Sender: TObject);
begin
  if fpgApplication <> nil then
    fpgApplication.WakeMainThread;
end;

procedure TfpgOhosApplication.EnqueueTouchEvent(AX, AY: Integer; AAction: Integer; AWinHandle: TfpgWinHandle);
var
  ev: PfpgOhosTouchEvent;
begin
  New(ev);
  ev^.X := AX;
  ev^.Y := AY;
  ev^.Action := AAction;
  ev^.WindowHandle := AWinHandle;
  ev^.MouseButton := 0;  // touch, not a mouse button
  FEventQueueLock.Enter;
  try
    FEventQueue.Add(ev);
  finally
    FEventQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgOhosApplication.EnqueueMouseEvent(AX, AY: Integer; AAction: Integer; AWinHandle: TfpgWinHandle; AButton: Integer);
var
  ev: PfpgOhosTouchEvent;
begin
  New(ev);
  ev^.X := AX;
  ev^.Y := AY;
  ev^.Action := AAction;
  ev^.WindowHandle := AWinHandle;
  ev^.MouseButton := AButton;
  ev^.Kind := 0;
  ev^.WheelDelta := 0;
  FEventQueueLock.Enter;
  try
    FEventQueue.Add(ev);
  finally
    FEventQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgOhosApplication.EnqueueWheelEvent(AX, AY: Integer; ADelta: Integer; AWinHandle: TfpgWinHandle);
var
  ev: PfpgOhosTouchEvent;
begin
  New(ev);
  ev^.X := AX;
  ev^.Y := AY;
  ev^.Action := 0;
  ev^.WindowHandle := AWinHandle;
  ev^.MouseButton := 0;
  ev^.Kind := 1;
  ev^.WheelDelta := ADelta;
  FEventQueueLock.Enter;
  try
    FEventQueue.Add(ev);
  finally
    FEventQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgOhosApplication.EnqueueHoverEvent(AX, AY: Integer; AWinHandle: TfpgWinHandle);
var
  ev: PfpgOhosTouchEvent;
begin
  New(ev);
  ev^.X := AX;
  ev^.Y := AY;
  ev^.Action := 1;
  ev^.WindowHandle := AWinHandle;
  ev^.MouseButton := 0;
  ev^.Kind := 2;
  ev^.WheelDelta := 0;
  FEventQueueLock.Enter;
  try
    FEventQueue.Add(ev);
  finally
    FEventQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgOhosApplication.EnqueueKeyEvent(AKeyCode, AAction, AModifiers: Integer; AUnicodeChar: LongWord);
var
  ev: PfpgOhosKeyEvent;
begin
  New(ev);
  ev^.Kind := OHOS_EV_KEY;
  ev^.KeyCode := AKeyCode;
  ev^.Action := AAction;
  ev^.Modifiers := AModifiers;
  ev^.UnicodeChar := AUnicodeChar;
  ev^.Count := 0;
  ev^.Text := '';
  FKeyQueueLock.Enter;
  try
    FKeyEventQueue.Add(ev);
  finally
    FKeyQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

{ IME text insertion (Kind=1) — enqueued so the UI thread processes it in
  order with key events; never call fpGUI message system cross-thread. }
procedure TfpgOhosApplication.EnqueueTextEvent(const AText: string);
var
  ev: PfpgOhosKeyEvent;
begin
  if AText = '' then Exit;
  New(ev);
  ev^.Kind := OHOS_EV_TEXT;
  ev^.KeyCode := 0;
  ev^.Action := 0;
  ev^.Modifiers := 0;
  ev^.UnicodeChar := 0;
  ev^.Count := 0;
  { Deep copy: AText is owned by the injecting (ETS) thread. Sharing the
    reference would let both threads race on the string's refcount/refcount
    release under fast typing -> heap corruption (0xFEFE fill) -> SIGSEGV. }
  ev^.Text := Copy(AText, 1, Length(AText));
  FKeyQueueLock.Enter;
  try
    FKeyEventQueue.Add(ev);
  finally
    FKeyQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

{ IME deleteLeft (Kind=2) / deleteRight (Kind=3) }
procedure TfpgOhosApplication.EnqueueDeleteEvent(AKind, ACount: Integer);
var
  ev: PfpgOhosKeyEvent;
begin
  if ACount < 1 then Exit;
  { DoCut writes the clipboard (DoSetText) right before the focused
    TextInput component also performs its own cut, whose onChange delete
    would delete the surrounding text from fpGUI's buffer. Drop delete
    injections arriving within 200ms of a clipboard write. }
{  if (FSelection is TfpgOhosClipboard) and
     (GetTickCount64 - TfpgOhosClipboard(FSelection).FLastSetTime < 200) then
    Exit; }
  New(ev);
  ev^.Kind := AKind;
  ev^.KeyCode := 0;
  ev^.Action := 0;
  ev^.Modifiers := 0;
  ev^.UnicodeChar := 0;
  ev^.Count := ACount;
  ev^.Text := '';
  FKeyQueueLock.Enter;
  try
    FKeyEventQueue.Add(ev);
  finally
    FKeyQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

{ IME moveCursor (Kind=4); ADirection: OHOS_CURSOR_* }
procedure TfpgOhosApplication.EnqueueMoveCursorEvent(ADirection: Integer);
var
  ev: PfpgOhosKeyEvent;
begin
  New(ev);
  ev^.Kind := OHOS_EV_MOVE_CURSOR;
  ev^.KeyCode := 0;
  ev^.Action := 0;
  ev^.Modifiers := 0;
  ev^.UnicodeChar := 0;
  ev^.Count := ADirection;
  ev^.Text := '';
  FKeyQueueLock.Enter;
  try
    FKeyEventQueue.Add(ev);
  finally
    FKeyQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgOhosApplication.EnqueueResizeEvent(AWinHandle: TfpgWinHandle; AWidth, AHeight: Integer);
var
  ev: PfpgOhosResizeEvent;
begin
  New(ev);
  ev^.WindowHandle := AWinHandle;
  ev^.Width := AWidth;
  ev^.Height := AHeight;
  FResizeQueueLock.Enter;
  try
    FResizeQueue.Add(ev);
  finally
    FResizeQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgOhosApplication.EnqueueTrayEvent(AEventType: Integer; const AMenuId: string);
var
  ev: PfpgOhosTrayEvent;
begin
  New(ev);
  ev^.EventType := AEventType;
  ev^.MenuId := AMenuId;
  FTrayQueueLock.Enter;
  try
    FTrayEventQueue.Add(ev);
  finally
    FTrayQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgOhosApplication.EnqueueConfigurationEvent(const AConfig: string);
var
  ev: PfpgOhosConfigEvent;
begin
  New(ev);
  ev^.Kind := 0;
  ev^.Config := AConfig;
  FConfigQueueLock.Enter;
  try
    FConfigQueue.Add(ev);
  finally
    FConfigQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

{ 启动载荷 JSON 入队（C++ set_launch_params 线程注入 → UI 线程消费；
   与 EnqueueConfigurationEvent 同队列复用，Kind=1 区分分发）。 }
procedure TfpgOhosApplication.EnqueueLaunchParamsEvent(const APayload: string);
var
  ev: PfpgOhosConfigEvent;
begin
  New(ev);
  ev^.Kind := 1;
  ev^.Config := APayload;
  FConfigQueueLock.Enter;
  try
    FConfigQueue.Add(ev);
  finally
    FConfigQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

function TfpgOhosApplication.HasPendingEvents: Boolean;
begin
  FEventQueueLock.Enter;
  try
    Result := FEventQueue.Count > 0;
  finally
    FEventQueueLock.Leave;
  end;
end;

function TfpgOhosApplication.HasPendingKeyEvents: Boolean;
begin
  Result := False;
  if FKeyEventQueue = nil then Exit;
  FKeyQueueLock.Enter;
  try
    Result := FKeyEventQueue.Count > 0;
  finally
    FKeyQueueLock.Leave;
  end;
end;

function TfpgOhosApplication.HasPendingResizeEvents: Boolean;
begin
  if FResizeQueueLock = nil then
  begin
    Result := (FResizeQueue <> nil) and (FResizeQueue.Count > 0);
    Exit;
  end;
  FResizeQueueLock.Enter;
  try
    Result := (FResizeQueue <> nil) and (FResizeQueue.Count > 0);
  finally
    FResizeQueueLock.Leave;
  end;
end;

function TfpgOhosApplication.HasPendingTrayEvents: Boolean;
begin
  Result := False;
  if FTrayEventQueue = nil then Exit;
  FTrayQueueLock.Enter;
  try
    Result := FTrayEventQueue.Count > 0;
  finally
    FTrayQueueLock.Leave;
  end;
end;

function TfpgOhosApplication.HasPendingConfigEvents: Boolean;
begin
  Result := False;
  if FConfigQueue = nil then Exit;
  FConfigQueueLock.Enter;
  try
    Result := FConfigQueue.Count > 0;
  finally
    FConfigQueueLock.Leave;
  end;
end;

function TfpgOhosApplication.HasPendingDragEvents: Boolean;
begin
  Result := False;
  if FDragQueue = nil then Exit;
  FDragQueueLock.Enter;
  try
    Result := FDragQueue.Count > 0;
  finally
    FDragQueueLock.Leave;
  end;
end;

function TfpgOhosApplication.HasPendingDispatchEvents: Boolean;
begin
  Result := False;
  if not assigned(gDispatchHasPending) then Exit;
  
  Result := gDispatchHasPending();
end;

procedure TfpgOhosApplication.EnqueueDragEvent(AWinHandle: TfpgWinHandle;
  AKind, AX, AY: Integer; const ASummary: string);
var
  ev: PfpgOhosDragEvent;
begin
  New(ev);
  ev^.Kind := AKind;
  ev^.WindowHandle := AWinHandle;
  ev^.X := AX;
  ev^.Y := AY;
  { 深拷贝：ASummary 属注入（ETS）线程（同 EnqueueTextEvent 教训，防引用计数竞争）}
  ev^.Summary := Copy(ASummary, 1, Length(ASummary));
  FDragQueueLock.Enter;
  try
    FDragQueue.Add(ev);
  finally
    FDragQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

{ 目标窗口（悬停窗口）→ 拖入会话（首次 enter 创建；GDI 每窗口独立 DropTarget 语义）}
procedure TfpgOhosApplication.EnsureDropSession(AWinHandle: TfpgWinHandle;
  const ASummaryJson: string);
var
  wnd: TfpgWindowBase;
begin
  { 跨窗口切换：旧会话释放（触发旧控件 Leave 通知），按新窗口重建 }
  if (gDragSession.Drop <> nil) and (gDragSession.DropWinHandle <> AWinHandle) then
  begin
    gDragSession.Drop.HandleLeave;
    FreeAndNil(gDragSession.Drop);
    gDragSession.DropWinHandle := nil;
  end;
  if gDragSession.Drop <> nil then Exit;
  wnd := FindWindowByHandle(AWinHandle);
  if wnd = nil then Exit;
  gDragSession.Drop := TfpgOhosDrop.Create(wnd);
  gDragSession.DropWinHandle := AWinHandle;
  { 应用内拖拽：补源控件（跨应用为 nil）；Source 为 TfpgDrag（fpg_main）public 属性 }
  if gDragSession.Active and (gDragSession.DragRef <> nil) then
    gDragSession.Drop.SetSourceWidget(TfpgDrag(gDragSession.DragRef).Source);
  { 装载 mimetypes（widget 的 DropHandler.Enter 依据它 accept/reject）}
  gDragSession.Drop.LoadMimeTypesFromSummary(ASummaryJson);
  { 内部拖拽：move 阶段即从源 MimeData 填充（getSummary 的 key 是数字索引，
    无法映射类型）→ DropHandler 的 Enter 判定立即真实（方案 C：
    内部拖拽的 CanDrop/角标与实际接受一致）。外部拖入无源 → 保持乐观，
    drop 时由 records type 推导兜底。}
  if (gDragSession.Drop.Mimetypes.Count = 0) and gDragSession.Active and
     (gDragSession.DragRef <> nil) then
    gDragSession.Drop.LoadMimeTypesFromSource;
  fpGUI_Hilog(LOG_INFO, format('drag-session created h=%s class=%s mimes=%d summary=%s',
    [IntToHex(PtrUInt(AWinHandle), 8), wnd.ClassName,
     gDragSession.Drop.Mimetypes.Count, Copy(ASummaryJson, 1, 200)]));
end;

{ enter/move/leave 消费：坐标换算与触摸同式（÷gScaleFactorX，触摸 3867 行同式）
  → 减窗口位置 → 窗口客户区 → TfpgOhosDrop（核心引擎路由 Enter/Leave/Move）}
procedure TfpgOhosApplication.ProcessDragEvents;
var
  ev: PfpgOhosDragEvent;
  wnd: TfpgWindowBase;
  lx, ly: Integer;
begin
  while True do
  begin
    FDragQueueLock.Enter;
    try
      if (FDragQueue = nil) or (FDragQueue.Count = 0) then
        ev := nil
      else
      begin
        ev := PfpgOhosDragEvent(FDragQueue[0]);
        FDragQueue.Delete(0);
      end;
    finally
      FDragQueueLock.Leave;
    end;
    if ev = nil then Break;

    try
      wnd := FindWindowByHandle(ev^.WindowHandle);
      if wnd = nil then Continue;             { 窗口已销毁：丢弃（同触摸 DROP 逻辑）}
      { 坐标：物理 px → 逻辑（ETS 已用组件相对 getX/getY = 客户区 vp，
        C++ ×density 后即客户区 px——不再减窗口位置，见 drag-evt 日志校准）}
      if gScaleFactorX <> 1.0 then
      begin
        lx := Round(ev^.X / gScaleFactorX);
        ly := Round(ev^.Y / gScaleFactorY);
      end
      else
      begin
        lx := ev^.X;
        ly := ev^.Y;
      end;

      case ev^.Kind of
        OHOS_DRAG_ENTER, OHOS_DRAG_MOVE:
          begin
            EnsureDropSession(ev^.WindowHandle, ev^.Summary);
            if gDragSession.Drop <> nil then
            begin
              gDragSession.Drop.HandlePosition(lx, ly);   { ← 核心路由 }
              fpGUI_Hilog(LOG_INFO, format(
                'drag-evt kind=%d h=%s client=(%d,%d) mimes=%d',
                [ev^.Kind, IntToHex(PtrUInt(ev^.WindowHandle), 8),
                 lx, ly, gDragSession.Drop.Mimetypes.Count]));
            end
            else
              fpGUI_Hilog(LOG_INFO, format(
                'drag-evt kind=%d h=%s NO-SESSION (wnd=%d)',
                [ev^.Kind, IntToHex(PtrUInt(ev^.WindowHandle), 8),
                 Integer(wnd <> nil)]));
          end;
        OHOS_DRAG_LEAVE:
          begin
            fpGUI_Hilog(LOG_INFO, format('drag-evt kind=2 h=%s',
              [IntToHex(PtrUInt(ev^.WindowHandle), 8)]));
            if gDragSession.Drop <> nil then
            begin
              gDragSession.Drop.HandleLeave;
              FreeAndNil(gDragSession.Drop);
              gDragSession.DropWinHandle := nil;
            end;
          end;
      end;
    finally
      Dispose(ev);
    end;
  end;
end;

{ 拖拽泵循环入口（包装 protected DoWaitWindowMessage；X11 TApplicationHelper 同式）}
procedure TfpgOhosApplication.PumpEvents(ATimeoutMs: Integer);
begin
  DoWaitWindowMessage(ATimeoutMs);
end;

function TfpgOhosApplication.FindWindowByHandle(AHandle: TfpgWinHandle): TfpgWindowBase;
var
  i: Integer;
begin
  Result := nil;
  if (AHandle = nil) or (FWinHandleMap = nil) then Exit;
  for i := 0 to (FWinHandleMap.Count div 2) - 1 do
  begin
    if FWinHandleMap[i * 2] = AHandle then
    begin
      Result := TfpgWindowBase(FWinHandleMap[i * 2 + 1]);
      Exit;
    end;
  end;
end;

{ Reverse lookup: native handle registered for a window object. Used so UP
  routing can be stored as a handle and resolved through the (always valid)
  handle map — never as a raw object pointer that can dangle once the popup
  window is destroyed. }
function TfpgOhosApplication.FindHandleByWindow(AWindow: TfpgWindowBase): TfpgWinHandle;
var
  i: Integer;
begin
  Result := nil;
  if (AWindow = nil) or (FWinHandleMap = nil) then Exit;
  for i := 0 to (FWinHandleMap.Count div 2) - 1 do
  begin
    if TfpgWindowBase(FWinHandleMap[i * 2 + 1]) = AWindow then
    begin
      Result := TfpgWinHandle(FWinHandleMap[i * 2]);
      Exit;
    end;
  end;
end;

{ Find the top-most fpGUI window whose logical rect contains the global
  logical point. FWinHandleMap stores (handle, window) pairs; the window
  registered later is on top (e.g. a popup submenu above the main form). }
function TfpgOhosApplication.HitTestWindow(AGlobalX, AGlobalY: Integer): TfpgWindowBase;
var
  i: Integer;
  w: TfpgWindowBase;
begin
  Result := nil;
  if FWinHandleMap = nil then Exit;
  for i := 0 to (FWinHandleMap.Count div 2) - 1 do
  begin
    w := TfpgWindowBase(FWinHandleMap[i * 2 + 1]);
    if (w <> nil) and w.HasHandle and
       (AGlobalX >= w.Left) and (AGlobalX < w.Left + w.Width) and
       (AGlobalY >= w.Top)  and (AGlobalY < w.Top + w.Height) then
      Result := w;   { last match = top-most }
  end;
end;

procedure TfpgOhosApplication.ProcessQueuedEvents;
var
  ev: PfpgOhosTouchEvent;
  wnd: TfpgWindowBase;
  rw: TfpgWindowBase;
  msg: TfpgMessageParams;
  diag: string;
  gx, gy: Integer;
  wPrev: TfpgWindowBase;
begin
  { Qt QPA 式 RepaintHelper：每轮检查 buffer 池滞后重绘（到期 Invalidate）}
  CheckRepaintHelper;
  while True do
  begin
    ev := nil;
    FEventQueueLock.Enter;
    try
      if FEventQueue.Count > 0 then
      begin
        ev := PfpgOhosTouchEvent(FEventQueue[0]);
        FEventQueue.Delete(0);
      end;
    finally
      FEventQueueLock.Leave;
    end;
    if ev = nil then
      Break;

    { Route to native window — Dispatch forwards to PrimaryWidget. }
    if ev^.WindowHandle <> nil then
      wnd := FindWindowByHandle(ev^.WindowHandle)
    else if MainForm <> nil then
      wnd := MainForm.Window
    else if FormCount > 0 then
      wnd := Forms[0].Window
    else
      wnd := nil;

    if wnd = nil then
    begin
      Dispose(ev);
      Continue;
    end;

if (gModalWinHandle <> nil) and (FindWindowByHandle(gModalWinHandle) = nil) then
begin
  fpGUI_Hilog(LOG_INFO, 'modal handle stale, clearing');
  gModalWinHandle := nil;
  if Assigned(_set_modal_window) then _set_modal_window(nil);
end;

    { Track focused window for keyboard routing. Only DOWN updates it:
      MOVE (hover) must not steal keyboard focus from a just-opened popup
      (combo dropdown) — otherwise a mouse move over the parent window
      reroutes subsequent key events (arrows/Enter/Esc) back to the parent
      and the dropdown never sees them. Clicks still switch focus via DOWN. }
// 主窗口触摸（ohos_inject_touch_event 无句柄）也要刷新聚焦窗口，否则 UpdateKeyboardVisibility 判定失败 → 软键盘不弹出 → 主窗无法录入。
//    if (ev^.WindowHandle <> nil) and (ev^.Kind = 0) and (ev^.Action = OH_TOUCH_DOWN) then
//      gFocusedWinHandle := ev^.WindowHandle;
if (ev^.Kind = 0) and (ev^.Action = OH_TOUCH_DOWN) then
begin
  if ev^.WindowHandle <> nil then
    gFocusedWinHandle := ev^.WindowHandle
  else if (wnd <> nil) and (wnd is TfpgOhosWindow) then
    gFocusedWinHandle := TfpgOhosWindow(wnd).WinHandle;
end;

    { Modal blocking: re-raise modal + shake feedback, drop events for others.
      Popup windows (wtPopup: ComboBox dropdown, context menus, etc.) are
      part of the modal window's OWN interaction — they open on top of the
      modal form (e.g. FileDialog) and MUST NOT be blocked, otherwise the
      dropdown cannot be operated with mouse or keyboard. }
    if (gModalWinHandle <> nil) and (ev^.WindowHandle <> gModalWinHandle) then
    begin
      if (wnd <> nil) and (wnd.WindowType = wtPopup) then
         { let popups through }
      else
      begin
        fpGUI_Hilog(LOG_INFO, 'touch DROPPED by modal: win=' +
          IntToHex(PtrUInt(ev^.WindowHandle), 8) + ' modal=' +
          IntToHex(PtrUInt(gModalWinHandle), 8) + ' act=' + IntToStr(ev^.Action));
        { 仅点击（DOWN）时 re-raise + shake 抖动：MOVE/UP（悬停/抬起）只丢弃不抖，
          否则鼠标悬停在模态窗口外（含模态打开瞬间鼠标在主窗上）会持续抖动 }
        if ev^.Action = OH_TOUCH_DOWN then
        begin
          { Re-raise modal window so it stays on top }
          if Assigned(_ohos_set_window_visible) then
            _ohos_set_window_visible(gModalWinHandle, 1);
          { Shake animation via C++ bridge }
          if Assigned(_shake_window) then
            _shake_window(gModalWinHandle);
        end;
        Dispose(ev);
        Continue;
      end;
    end;

    FillChar(msg, SizeOf(msg), 0);
    { Convert OHOS physical touch coordinates to logical pixels.
      Gate on gScaleFactorX (the factor actually used for the conversion):
      on devices with density < 1 (gScaleFactor clamped to 1) the old
      gScaleFactor <> 1.0 check would skip the division and misroute
      every touch point. }
    if gScaleFactorX <> 1.0 then
    begin
      msg.mouse.x := Round(ev^.X / gScaleFactorX);
      msg.mouse.y := Round(ev^.Y / gScaleFactorY);
    end
    else
    begin
      msg.mouse.x := ev^.X;
      msg.mouse.y := ev^.Y;
    end;
    { Carry keyboard modifier state so mouse handlers see Shift/Ctrl/Alt. }
    msg.mouse.shiftstate := [];
    if gShiftPressed then Include(msg.mouse.shiftstate, ssShift);
    if gCtrlPressed  then Include(msg.mouse.shiftstate, ssCtrl);
    if gAltPressed   then Include(msg.mouse.shiftstate, ssAlt);
    msg.mouse.timestamp := Now;

    { Re-route pointer events by SCREEN coordinates. UNIFIED basis: the ETS
      side now reports displayX/displayY (absolute screen, vp) for EVERY
      window (main or sub), the C++ bridge converts vp -> px, and Pascal
      scales to logical pixels. msg IS therefore the global screen point —
      no window-origin guessing, no drag compensation needed:
      WidgetToScreen(msg - wnd.Left + wnd.Left) = screen point, so dragging
      is naturally 1:1. Reroute ONLY when the point lands in the main
      form's menu-bar band (top 20 logical px) or inside a different
      window. }
    if ((ev^.Kind = 0) and ((ev^.Action = OH_TOUCH_DOWN) or
                            (ev^.Action = OH_TOUCH_MOVE))) or
       (ev^.Kind = 2) then
    begin
      rw := nil;
      if MainForm <> nil then
      begin
        gx := msg.mouse.x;   { global screen point (logical) }
        gy := msg.mouse.y;
        { Pointer state machine: if the previous frame's resolved position
          sat on a subwindow, keep routing there — a click always follows a
          hover on the submenu, so a stray main-window interpretation must
          never pop the menu bar while the pointer is on a subwindow. }
        if gCursorValid then
          wPrev := HitTestWindow(gCursorX, gCursorY)
        else
          wPrev := nil;
        gCursorX := gx;
        gCursorY := gy;
        gCursorValid := True;
        rw := HitTestWindow(gx, gy);
        if (wPrev <> nil) and (wPrev <> MainForm.Window) then
          rw := wPrev                 { pointer was on a subwindow }
        else if (rw <> nil) and (rw <> MainForm.Window) then
          rw := rw                    { hit a subwindow }
        else if (rw = MainForm.Window) and
                (gy >= MainForm.Window.Top) and
                (gy <= MainForm.Window.Top + 20) then
          rw := MainForm.Window       { menu-bar band }
        else
          rw := nil;
        diag := 'TOUCH: diag kind=' + IntToStr(ev^.Kind) +
          ' act=' + IntToStr(ev^.Action) +
          ' msg=(' + IntToStr(msg.mouse.x) + ',' + IntToStr(msg.mouse.y) + ')' +
          ' glob=(' + IntToStr(gx) + ',' + IntToStr(gy) + ')' +
          ' wnd=' + wnd.ClassName + '(' + IntToStr(wnd.Left) + ',' +
          IntToStr(wnd.Top) + ' ' + IntToStr(wnd.Width) + 'x' +
          IntToStr(wnd.Height) + ')' +
          ' mf=(' + IntToStr(MainForm.Window.Left) + ',' +
          IntToStr(MainForm.Window.Top) + ')';
        if rw = nil then
          diag := diag + ' rw=nil'
        else
          diag := diag + ' rw=' + rw.ClassName + '(' + IntToStr(rw.Left) +
            ',' + IntToStr(rw.Top) + ' ' + IntToStr(rw.Width) + 'x' +
            IntToStr(rw.Height) + ')';
        fpGUI_Hilog(LOG_INFO, diag);
        if rw = wnd then
          rw := nil;   { already in the target window }
      end;
      if (rw <> nil) and (rw <> wnd) then
      begin
        fpGUI_Hilog(LOG_INFO, 'TOUCH: reroute act=' + IntToStr(ev^.Action) +
          ' xy=(' + IntToStr(msg.mouse.x) + ',' + IntToStr(msg.mouse.y) +
          ') from=' + wnd.ClassName + ' to=' + rw.ClassName);
        msg.mouse.x := gx - rw.Left;
        msg.mouse.y := gy - rw.Top;
        wnd := rw;
      end;
    end;

    if ev^.Kind = 1 then
    begin
      { Wheel scroll: FPGM_SCROLL with delta (±1 per notch). }
      msg.mouse.delta := ev^.WheelDelta;
      { Unified screen basis: normalise to the delivery window's space. }
      msg.mouse.x := msg.mouse.x - wnd.Left;
      msg.mouse.y := msg.mouse.y - wnd.Top;
      fpgPostMessage(nil, wnd, FPGM_SCROLL, msg);
      Dispose(ev);
      Continue;
    end;

    if ev^.Kind = 2 then
    begin
      { Hover: move with no buttons pressed — framework synthesises
        MOUSEENTER/EXIT and cursor changes from DispatchMouseEvent. }
      msg.mouse.Buttons := 0;
      { Normalise to window space via the global screen point (gx/gy). }
      msg.mouse.x := gx - wnd.Left;
      msg.mouse.y := gy - wnd.Top;
      fpgPostMessage(nil, wnd, FPGM_MOUSEMOVE, msg);
      Dispose(ev);
      Continue;
    end;

    { Map MouseButton to fpGUI button constant.
      Emulator reports button as bitmask/X11 style:
      0=no button (hover/move), 1=left, 2=right, 3=middle.
      (NOT the ArkUI MouseButton enum Left=0/Right=1/Middle=2 —
      hdc logs show left clicks arrive with button=1, right with 2.) }
    case ev^.MouseButton of
      0: msg.mouse.Buttons := MOUSE_LEFT;
      1: msg.mouse.Buttons := MOUSE_LEFT;
      2: msg.mouse.Buttons := MOUSE_RIGHT;
      3: msg.mouse.Buttons := MOUSE_MIDDLE;
    else
      msg.mouse.Buttons := MOUSE_LEFT;  // touch (other values) → left
    end;
    case ev^.Action of
      OH_TOUCH_DOWN:
        begin
          { Dedup double-fired DOWNs (emulator sends touch DOWN then mouse
            DOWN for one click, 20-105ms apart) — otherwise MenuBar FClicked
            toggles twice and the popup "flashes" open/closed. 150ms window:
            covers the measured dual-fire gap (<=105ms) while real double-
            click 2nd DOWNs (>150ms) pass through; double-click detection
            itself happens on UP (DOUBLECLICK_MS=320) and is unaffected.
            The 2nd DOWN often arrives through a DIFFERENT window with
            subwindow-space coords (e.g. clicking a submenu item fires a
            DOWN on the subwindow with main-window coords, then a second
            DOWN on the main window with the SAME physical point expressed
            in subwindow space) — match it against the previous DOWN's
            resolved global point via both window spaces. }
          if (gLastDownTick <> 0) and
             (GetTickCount64 - gLastDownTick < 150) then
          begin
            if ev^.WindowHandle = gLastDownWin then
            begin
              gLastDownTick := GetTickCount64;   { keep the window armed }
              Dispose(ev);
              Continue;
            end;
            if gLastDownTargetWin <> nil then
            begin
              { Compare the global screen points (gx/gy IS the screen point). }
              if (Abs(gx - gLastDownGlobX) + Abs(gy - gLastDownGlobY)) < 20 then
              begin
                fpGUI_Hilog(LOG_INFO, 'TOUCH: DOWN dedup cross-window xy=(' +
                  IntToStr(msg.mouse.x) + ',' + IntToStr(msg.mouse.y) + ')');
                gLastDownTick := GetTickCount64;
                Dispose(ev);
                Continue;
              end;
            end;
          end;
          gLastDownTick := GetTickCount64;
          gLastDownTargetWin := FindHandleByWindow(wnd);   { delivery window (re-routed) }
          gLastDownTargetLeft := wnd.Left;
          gLastDownTargetTop := wnd.Top;
          gLastDownWin := ev^.WindowHandle;   { source handle, kept for dedup }
          gLastDownButton := msg.mouse.Buttons;
          gLastDownGlobX := gx;
          gLastDownGlobY := gy;
          { Normalise delivery coords to the delivery window's space: gx/gy
            is the global screen point; subtract the delivery window origin. }
          msg.mouse.x := gx - wnd.Left;
          msg.mouse.y := gy - wnd.Top;
          fpGUI_Hilog(LOG_INFO, 'TOUCH: DOWN x=' + IntToStr(msg.mouse.x) + ' y=' + IntToStr(msg.mouse.y));
          fpgPostMessage(nil, wnd, FPGM_MOUSEDOWN, msg);
        end;
      OH_TOUCH_MOVE:
        begin
          { Use the pressed-button state, NOT the injected button value:
            a hover move (no button pressed) must deliver Buttons=0 so
            widgets do not start a drag/selection without a click. }
          msg.mouse.Buttons := gLastDownButton;
          { Throttle: coalesce consecutive MOVE events — only the last one
            before a non-MOVE (or queue drain) is delivered. }
          if (FEventQueue.Count > 0) and
             (PfpgOhosTouchEvent(FEventQueue[0])^.Kind = 0) and
             (PfpgOhosTouchEvent(FEventQueue[0])^.Action = OH_TOUCH_MOVE) then
          begin
            { Keep the most recent MOVE position by skipping this one. }
            Dispose(ev);
            Continue;
          end;
          { Normalise to the delivery window's space: gx/gy is the global
            screen point; subtracting the window origin yields window-space
            coords for any window. Idempotent after rerouting (msg was
            already set to gx-rw.Left). }
          msg.mouse.x := gx - wnd.Left;
          msg.mouse.y := gy - wnd.Top;
          fpgPostMessage(nil, wnd, FPGM_MOUSEMOVE, msg);
        end;
      OH_TOUCH_UP:
        begin
          { Use the DOWN-recorded button (state machine), NOT the injected
            UP button value: the emulator can report a wrong button on UP
            (e.g. left click delivered as button=1 -> would open the right-
            click popup menu of edits). }
          msg.mouse.Buttons := gLastDownButton;
          gLastDownButton := 0;
          { Deliver UP to the window that got the DOWN (re-routed target if
            any), NOT the event's window: when a click on the MenuBar pops a
            submenu (new XComponent window is created on top), the emulator
            routes the UP to the new window (same coords = submenu item 1)
            which then executes/closes the submenu immediately ("popup
            appears and vanishes"). fpGUI semantics: the UP belongs to the
            window that got the DOWN.
            Resolve through the handle map at post time — the DOWN window may
            have been destroyed in the meantime (e.g. the click dismissed the
            menu); posting to a freed object would crash the dispatcher at
            msg.Dest.Dispatch. }
          wnd := FindWindowByHandle(gLastDownTargetWin);
          if wnd <> nil then
          begin
            { The emulator's UP coords are unreliable (reported in yet
              another space); reuse the DOWN position, normalised to the
              delivery window. }
            msg.mouse.x := gLastDownGlobX - wnd.Left;
            msg.mouse.y := gLastDownGlobY - wnd.Top;
            fpGUI_Hilog(LOG_INFO, 'TOUCH: UP x=' + IntToStr(msg.mouse.x) + ' y=' + IntToStr(msg.mouse.y) +
              ' toDownWin=' + IntToStr(PtrUInt(wnd)));
            fpgPostMessage(nil, wnd, FPGM_MOUSEUP, msg);
          end
          else
            fpGUI_Hilog(LOG_INFO, 'TOUCH: UP dropped (no DOWN window) x=' + IntToStr(msg.mouse.x));
          gLastDownWin := nil;
          gLastDownTargetWin := nil;
        end;
    end;
    Dispose(ev);
  end;
end;

procedure TfpgOhosApplication.UpdateKeyboardVisibility;
var
  wnd: TfpgWindowBase;
  fw: TfpgWidget;
  cn: string;
  kbType: Integer;
begin
  { Called after touch/mouse messages have been delivered, when the
    keyboard focus has settled. Show the soft keyboard only while a
    text-entry widget holds the focus, and hint the keyboard type:
    0=hide, 1=text, 2=number, 3=decimal.

    Focus lookup walks the focused window's PrimaryWidget.ActiveWidget
    chain (gFocusedWinHandle is refreshed by every touch event) instead
    of the global FocusRootWidget, which can be nil in multi-window apps.
    fpg_ohos (corelib) cannot reference GUI-layer edit classes, so match
    by class name (substring 鈥?covers TfpgEdit*, TfpgMemo, TfpgSpinedit,
    TfpgFileNameEdit, TfpgComboBox, etc.). }
  fw := nil;
  if gFocusedWinHandle <> nil then
  begin
    wnd := FindWindowByHandle(gFocusedWinHandle);
    if (wnd <> nil) and (wnd.PrimaryWidget is TfpgWidget) then
    begin
      fw := TfpgWidget(wnd.PrimaryWidget);
      while (fw <> nil) and (fw.ActiveWidget <> nil) do
        fw := fw.ActiveWidget;
    end;
  end;

  kbType := 0;
  if fw <> nil then
  begin
    cn := fw.ClassName;
    if (Pos('EditInteger', cn) > 0) then
      kbType := 2
    else if (Pos('EditFloat', cn) > 0) or (Pos('EditCurrency', cn) > 0) then
      kbType := 3
    else if (Pos('Edit', cn) > 0) or (Pos('Memo', cn) > 0)
         or (Pos('Spin', cn) > 0) or (cn = 'TfpgComboBox')
         or (Pos('Terminal', cn) > 0) { terminal emulator views need keyboard }
         or (Assigned(fpgCaret) and (fpgCaret.Canvas <> nil)) then
      kbType := 1;
  end;
  if kbType <> FLastKeyboardType then
  begin
    FLastKeyboardType := kbType;
    fpGUI_Hilog(LOG_INFO, 'KBD: type ' + IntToStr(kbType) + ' focus=' + cn);
    ohos_show_keyboard(kbType);
    fpGUI_Hilog(LOG_INFO, 'KBD: type ' + IntToStr(kbType) + ' DONE');
  end;
end;

procedure TfpgOhosApplication.ProcessQueuedResizeEvents;
var
  ev: PfpgOhosResizeEvent;
  wnd: TfpgWindowBase;
  msg: TfpgMessageParams;
begin
  while (FResizeQueue <> nil) and (FResizeQueue.Count > 0) do
  begin
    ev := nil;
    FResizeQueueLock.Enter;
    try
      if (FResizeQueue <> nil) and (FResizeQueue.Count > 0) then
      begin
        ev := PfpgOhosResizeEvent(FResizeQueue[0]);
        FResizeQueue.Delete(0);
      end;
    finally
      FResizeQueueLock.Leave;
    end;
    if ev = nil then
      Break;

    fpGUI_Hilog(LOG_INFO, format('ResizeEvent: win=%s ev=%dx%d',
      [IntToHex(PtrUInt(ev^.WindowHandle), 8), ev^.Width, ev^.Height]));

    if ev^.WindowHandle <> nil then
      wnd := FindWindowByHandle(ev^.WindowHandle)
    else
      wnd := nil;

    if wnd <> nil then
    begin
      { 方案 C（去重防御）：ev 尺寸与窗口当前物理尺寸完全相同（纯移动误报/
        系统重发/多层过滤后的漏网重复）→ 跳过 SetPhysicalSize+FPGM_RESIZE+
        Invalidate，避免移动中多余的 bitmap 重建判定与重绘提交（拖动花屏）。 }
      if (wnd is TfpgOhosWindow) and
         (TfpgOhosWindow(wnd).PhysicalWidth = ev^.Width) and
         (TfpgOhosWindow(wnd).PhysicalHeight = ev^.Height) then
      begin
        fpGUI_Hilog(LOG_INFO, format('ResizeEvent SKIP (same size): win=%s %dx%d',
          [wnd.ClassName, ev^.Width, ev^.Height]));
        Dispose(ev);
        Continue;
      end;

      { 更新窗口物理尺寸（渲染目标重建依据）：BeginDraw 的 bitmap 重建判断
        用 PhysicalWidth/Height（=反馈的实际 drawable px），否则 GetClientRect
        滞后时 bitmap 停在创建尺寸 → 窗口拖大后超出部分无内容（黑色）。 }
      if wnd is TfpgOhosWindow then
      begin
        TfpgOhosWindow(wnd).SetPhysicalSize(ev^.Width, ev^.Height);
        { 尺寸变化（最大化/平铺/拖边）可能改变系统装饰（标题栏隐藏/恢复）→
          FDecTop/FDecLeft 懒加载缓存失效，重置后 DoWindowToScreen 重新查询。 }
        TfpgOhosWindow(wnd).FDecTop := -1;
      end;

      { 创建阶段过滤由 ETS 侧 "creation-compressed feedback skip" 承担，bitmap 尺寸由
        PhysicalWidth/Height 决定，此处信任反馈直接处理。 }
      FillChar(msg, SizeOf(msg), 0);
      //msg.rect.SetRect(0, 0, ev^.Width, ev^.Height);
      msg.rect.SetRect(0, 0,
		Round(ev^.Width  / (gScaleFactorX)),
		Round(ev^.Height / (gScaleFactorY)));
      fpgSendMessage(nil, wnd, FPGM_RESIZE, msg);
      { 强制重绘：TfpgWidget.DoResize 只触发 OnResize 不 Invalidate。
        创建阶段 XComponent 显示区先于校正 resize 生效，首帧在压缩区绘制被拉伸
        （字体变长、底部按钮不可见），校正反馈（正确客户区）到达后必须重绘
        才能按新 FSize 重建缓冲。 }
      if (wnd.PrimaryWidget is TfpgWidget) then
      begin
        TfpgWidget(wnd.PrimaryWidget).Invalidate;
        fpGUI_Hilog(LOG_INFO, format('resize->invalidate wnd=%s client=%dx%d',
          [wnd.ClassName, msg.rect.Width, msg.rect.Height]));
      end;
    end;
    Dispose(ev);
  end;
end;

{ 托盘事件分发（UI 线程消费）：转发到全局回调 OnOhosTray
  （TfpgOhosSystemTrayIcon.HandleTrayEvent，由托盘 handler 构造时注册）。 }
{ 窗口命令队列：native/ETS 线程只入队（EnqueueWinCmd），loop 线程统一消费——
  消除跨线程直调窗口表/堆的数据竞争（扫菜单/弹菜单 cppcrash 根治）。 }
procedure TfpgOhosApplication.EnqueueWinCmd(ACmd: PfpgOhosWinCmd);
begin
  if ACmd = nil then Exit;
  FWinCmdLock.Enter;
  try
    FWinCmdQueue.Add(ACmd);
  finally
    FWinCmdLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgOhosApplication.ProcessQueuedWindowCommands;
var
  cmd: PfpgOhosWinCmd;
  wnd: TfpgWindowBase;
  frm: TfpgBaseForm;
  obj: TObject;
  lx, ly: Integer;
  records: string;
  mimes: string;
  k: Integer;
begin
  while True do
  begin
    FWinCmdLock.Enter;
    try
      if (FWinCmdQueue = nil) or (FWinCmdQueue.Count = 0) then
        cmd := nil
      else
      begin
        cmd := PfpgOhosWinCmd(FWinCmdQueue[0]);
        FWinCmdQueue.Delete(0);
      end;
    finally
      FWinCmdLock.Leave;
    end;
    if cmd = nil then Break;

    case cmd^.Kind of
      0: { MOVED（拖标题栏/最大化后同步屏幕位置）}
        begin
          wnd := FindWindowByHandle(cmd^.Handle);
          if (wnd <> nil) and (wnd is TfpgOhosWindow) then
            TfpgOhosWindow(wnd).SetScreenPosition(cmd^.A, cmd^.B);
        end;
      1: { CLOSED（系统已销毁窗口 → 框架侧标准关闭流程）}
        begin
          wnd := FindWindowByHandle(cmd^.Handle);
          if wnd <> nil then
          begin
            fpGUI_Hilog(LOG_INFO, format('window-cmd CLOSED handle=%s class=%s',
              [IntToHex(PtrUInt(cmd^.Handle), 8), wnd.ClassName]));
            if wnd is TfpgOhosWindow then
              TfpgOhosWindow(wnd).InvalidateNativeHandle;
            UnregisterWindowHandle(cmd^.Handle);
            fpgPostMessage(nil, wnd, FPGM_CLOSE);
          end;
        end;
      2: { CAN_CLOSE（同步查询，loop 执行后回填 Awaiter）}
        begin
          cmd^.Result := 1;   // 默认允许（找不到窗口/非窗体）
          wnd := FindWindowByHandle(cmd^.Handle);
          frm := nil;
          if wnd <> nil then
          begin
            obj := wnd;
            if obj is TfpgBaseForm then
              frm := TfpgBaseForm(obj)
            else if wnd.Owner <> nil then
            begin
              obj := wnd.Owner;
              if obj is TfpgBaseForm then
                frm := TfpgBaseForm(obj);
            end;
          end;
          if frm <> nil then
          begin
            try
              if frm.CloseQuery then
                cmd^.Result := 1
              else
                cmd^.Result := 0;
            except
              cmd^.Result := 1;
            end;
          end;
          if cmd^.Awaiter <> nil then
            cmd^.Awaiter.SetEvent;
        end;
      3: { REFRESH（ETS 尺寸确认后强制重绘/重发几何）}
        begin
          wnd := FindWindowByHandle(cmd^.Handle);
          if wnd <> nil then
          begin
            fpGUI_Hilog(LOG_INFO, format('window-cmd REFRESH handle=%s class=%s',
              [IntToHex(PtrUInt(cmd^.Handle), 8), wnd.ClassName]));
            if wnd is TfpgOhosWindow then
            begin
              TfpgOhosWindow(wnd).DoUpdateWindowPosition;
              if wnd.Owner is TfpgWidget then
                TfpgWidget(wnd.Owner).Invalidate;
            end;
          end;
        end;
      4: { DROP（系统拖拽落下同步应答：accept<<8 | action；照抄 CAN_CLOSE Awaiter 模式）}
        begin
          cmd^.Result := 0;   { 默认拒绝 }
          wnd := FindWindowByHandle(cmd^.Handle);
          { 会话兜底：enter 链路异常（未到达/窗口切换）时就地创建 }
          if (wnd <> nil) and (gDragSession.Drop <> nil) and
             (gDragSession.DropWinHandle <> cmd^.Handle) then
          begin
            gDragSession.Drop.HandleLeave;
            FreeAndNil(gDragSession.Drop);
            gDragSession.DropWinHandle := nil;
          end;
          if (wnd <> nil) and (gDragSession.Drop = nil) then
          begin
            gDragSession.Drop := TfpgOhosDrop.Create(wnd);
            gDragSession.DropWinHandle := cmd^.Handle;
            if gDragSession.Active and (gDragSession.DragRef <> nil) then
              gDragSession.Drop.SetSourceWidget(TfpgDrag(gDragSession.DragRef).Source);
          end;
          if (wnd <> nil) and (gDragSession.Drop <> nil) then
          begin
            try
              { 丢弃该窗口积压的 enter/move（旧坐标，drop 后无意义；
                防 drop 处理完后的旧事件重建会话干扰下一次拖拽）}
              FDragQueueLock.Enter;
              try
                if FDragQueue <> nil then
                  for k := FDragQueue.Count - 1 downto 0 do
                    if PfpgOhosDragEvent(FDragQueue[k])^.WindowHandle = cmd^.Handle then
                    begin
                      Dispose(PfpgOhosDragEvent(FDragQueue[k]));
                      FDragQueue.Delete(k);
                    end;
              finally
                FDragQueueLock.Leave;
              end;
              { 取 native 线程暂存的 drop 参数 }
              gDragSessionLock.Enter;
              try
                lx := gDragSession.DropX;
                ly := gDragSession.DropY;
                records := gDragSession.DropRecords;
              finally
                gDragSessionLock.Leave;
              end;
              { 坐标：物理 px → 逻辑（客户区基准，同 ProcessDragEvents；不再减窗口位置）}
              if gScaleFactorX <> 1.0 then
              begin
                lx := Round(lx / gScaleFactorX);
                ly := Round(ly / gScaleFactorY);
              end;
              { 跨应用数据 → FDropData；应用内数据在 DataDropComplete 读源 }
              if records <> '' then
                gDragSession.Drop.SetDropDataFromRecords(records);
              { Mimetypes 兜底：应用内拖拽优先从源 MimeData 填充（权威精确——records 的
                UTD type 推导可能失真）；跨应用用 records type 推导 }
              if gDragSession.Drop.Mimetypes.Count = 0 then
              begin
                gDragSession.Drop.LoadMimeTypesFromSource;
                if gDragSession.Drop.Mimetypes.Count = 0 then
                  gDragSession.Drop.LoadMimeTypesFromRecords(records);
              end;
              { 最终定位（drop 点与最后 move 可能不同）+ 落下 }
              gDragSession.Drop.HandleDrop(lx, ly);
              { 应答（HandleDrop 内部已回填 gDragSession.DropAccept/DropAction）}
              if gDragSession.DropAccept then
                cmd^.Result := (1 shl OHOS_DROP_ACCEPT_SHIFT) or Ord(gDragSession.DropAction);
              { 日志：Mimetypes 明细（验证 drop 判定依据）}
              mimes := '';
              for k := 0 to gDragSession.Drop.Mimetypes.Count - 1 do
              begin
                if k > 0 then mimes := mimes + ',';
                mimes := mimes + gDragSession.Drop.Mimetypes[k].format;
              end;
              fpGUI_Hilog(LOG_INFO, format(
                'drop-done h=%s client=(%d,%d) mimes=[%s] accept=%d action=%d',
                [IntToHex(PtrUInt(cmd^.Handle), 8), lx, ly, mimes,
                 Integer(gDragSession.DropAccept), Ord(gDragSession.DropAction)]));
              FreeAndNil(gDragSession.Drop);
              gDragSession.DropWinHandle := nil;
            except
              cmd^.Result := 0;
            end;
          end
          else
            fpGUI_Hilog(LOG_INFO, format('drop-DROPPED wnd=%d drop=%d',
              [Integer(wnd <> nil), Integer(gDragSession.Drop <> nil)]));
          if cmd^.Awaiter <> nil then
            cmd^.Awaiter.SetEvent;
        end;
    end;
    Dispose(cmd);
  end;
end;

{ OHOS caret 解除入口（替代已删除的每波 GuardCaretLiveness——每波扫描会误杀活 caret）：
  窗口句柄/buffer 失效时一次性解除 caret（FCanvas 置 nil + 停 blink），
  杜绝 500ms InvertCaret 用已释放 canvas → SIGSEGV；编辑框重绘会重新 SetCaret 恢复闪烁。 }
procedure TfpgOhosApplication.UnsetCaretOnWindowInvalid;
begin
  if Assigned(fpgCaret) then
    fpgCaret.UnSetCaret(nil);
end;

procedure TfpgOhosApplication.ProcessQueuedTrayEvents;
var
  ev: PfpgOhosTrayEvent;
begin
  if FTrayEventQueue = nil then Exit;
  while True do
  begin
    FTrayQueueLock.Enter;
    try
      if FTrayEventQueue.Count = 0 then
      begin
        ev := nil;
      end
      else
      begin
        ev := PfpgOhosTrayEvent(FTrayEventQueue[0]);
        FTrayEventQueue.Delete(0);
      end;
    finally
      FTrayQueueLock.Leave;
    end;
    if ev = nil then Break;

    fpGUI_Hilog(LOG_INFO, format('TrayEvent: type=%d menu=%s cb=%s',
      [ev^.EventType, ev^.MenuId,
       BoolToStr(Assigned(OnOhosTray), True)]));

    { evType=3：add 结果回传（'ok'/'fail'）→ 更新全局托盘可用标志 }
    if ev^.EventType = 3 then
      gTrayActive := (ev^.MenuId = 'ok');

    if Assigned(OnOhosTray) then
      OnOhosTray(ev^.EventType, ev^.MenuId);

    Dispose(ev);
  end;
end;

{ 应用屏幕缩放（den 变化 / ohos_set_screen_size 共用）。
  fpGUI 后端自算缩放：fpGUI 框架 1:1，全部像素换算由 gScaleFactorX/Y 承担
  （画布 CanvasScale / 窗口 / 位图）。控件逻辑坐标不随密度变化（不自动改窗口尺寸）。 }
procedure ApplyScreenScaling(den: Single; w, h, dpi: Integer);
var
  sf, baseBackend: Single;
begin
  sf := den;
  if sf < 1.0 then sf := 1.0;

{
| 参数                                      	| （非框架缩放方案:96）          	| （框架缩放方案:96*density）	|
| ----------------------------------------- | ----------------------------- | --------------------------|
| `gScaleCore`（核心缩放 = Screen_dpi_x/96） 	| 1.0                          	| 182/96 ≈ 1.8958          	|
| `gScaleBackend`（逻辑→物理）               	| dp = 1.9（`ADensity`）       	| 1.0                      	|
| `Screen_dpi_x/y/Screen_dpi`               | 96                           	| 182                      	|
| 窗口创建/移动/位图/CanvasScale             	| ×1.9                         	| ×1                       	|
| 输入坐标 / resize 反馈 / 屏幕逻辑尺寸      	| ÷1.9                         	| ÷1                       	|
| 非 AGG 字体 FHeight                        | 13.3（canvas ×1.9 → 25.3px） 	| 25.3（1:1 → 25.3px）      	|
| AGG 字体 FHeight（物理）                   	| 25.3，GetHeight=13.3         	| 25.3，GetHeight=25.3      	|
| 弹窗一致性                                 	| 全部一致                     	| 文本类一致；固定像素类受限	|
由fpGUI原框架提供缩放存在的问题：
1. **固定像素控件弹窗偏小**：日历（TfpgPopupCalendar）等弹窗内控件为硬编码设计值，不参与
   ScaleDPI、不随字体放大，显示偏小 1.8958 倍。GDI/X11 在 HiDPI 下存在相同官方局限
   （`TfpgPopupWindow.HandleShow` 不调用 ScaleDPI，fpg_popupwindow.pas:247）。另案评估。
2. **弹窗创建时序**（⑤ 依赖）：窗口创建时 widget=设计值，ScaleDPI 后 `UpdatePosition` 再同步
   到放大值——观察首帧是否出现一次尺寸跳动，必要时在 `DoSetWindowVisible` 显式同步。
AggPas 是软件渲染，失去 OH_Drawing 硬件加速。对于嵌入式设备性能可能不够。
}
  // 采用fpGUI框架的缩放方案
  //gHiDPI := Round(96 * sf);       // 精度低
  //gScaleFactor := gHiDPI / 96;    // ≈1.8958
  //baseBackend  := 1.0;           	// 后端 1:1

  // 由本OHOS支持自行计算缩放(置fpGUI框架缩放为1:1)
  gHiDPI := 96;
  gScaleFactor := 1.0;
  baseBackend  := sf;               { dp = VirtualPixelRatio }

  gScaleFactorX := baseBackend * gZoomScale;
  gScaleFactorY := baseBackend * gZoomScale;
  gHiDPIScaleFactor := gScaleFactorX;

  if (w > 0) and (sf > 0) then
    gOhosScreenW := Round(w / gScaleFactorX)
  else if w > 0 then
    gOhosScreenW := w;
  if (h > 0) and (sf > 0) then
    gOhosScreenH := Round(h / gScaleFactorY)
  else if h > 0 then
    gOhosScreenH := h;
  if dpi > 0 then
    gOhosScreenDpi := dpi;

  if (fpgApplication <> nil) and (fpgApplication is TfpgOhosApplication) then
    TfpgOhosApplication(fpgApplication).SetScreenSize(gOhosScreenW, gOhosScreenH, gOhosScreenDpi);
end;

{ 全部窗体全量重绘：屏幕密度变化后画布按新 gScaleFactorX/Y 重画（逻辑坐标不变）。 }
procedure RefreshAllWindows;
var
  i: Integer;
  f: TfpgWidgetBase;
begin
  if fpgApplication = nil then Exit;
  for i := 0 to fpgApplication.FormCount - 1 do
  begin
    f := fpgApplication.Forms[i];
    if f = nil then Continue;
    if f is TfpgWidget then
      TfpgWidget(f).Invalidate;
  end;
end;

{ 执行 Configuration 变更（UI 线程）：解析紧凑 KV → 逐字段对比 gCfg* 全局 → 变化才处理。
   对比防重复：onConfigurationUpdate 每次可能全量下发，未变字段零动作。 }
{ 运行期 display 重查（旋转/分辨率变化）：更新 gOhosScreenW/H/Dpi 与缩放全局。
  由 'd'（方向）配置变化分支调用；Pascal 直调 native_display_manager。 }
procedure OhosRefreshDisplayScaling; forward;

procedure HandleConfigurationEvent(const kv: string);
var
  i, p, eq: Integer;
  key, val: string;
  ival: Integer;
  fval: Single;
  s, cur: string;
  changed: Boolean;
  flags: LongWord;
  params: TfpgMessageParams;
begin
  if kv = '' then Exit;
  flags := 0;
  i := 1;
  while i <= Length(kv) do
  begin
    p := Pos(';', kv, i);
    if p = 0 then p := Length(kv) + 1;
    s := Copy(kv, i, p - i);
    i := p + 1;
    if s = '' then Continue;
    eq := Pos('=', s);
    if eq = 0 then Continue;
    key := LowerCase(Copy(s, 1, eq - 1));
    val := Copy(s, eq + 1, Length(s) - eq);
    changed := False;
    ival := 0;
    fval := 0;
    if key = 'l' then
    begin
      if val <> gCfgLanguage then
      begin
        gCfgLanguage := val;
        flags := flags or CFG_CHANGED_LANGUAGE;
        changed := True;
      end;
    end
    else if key = 'c' then
    begin
      if TryStrToInt(val, ival) and (ival <> gCfgColorMode) then
      begin
        gCfgColorMode := ival;
        flags := flags or CFG_CHANGED_COLORMODE;
        changed := True;
      end;
    end
    else if key = 'd' then
    begin
      if TryStrToInt(val, ival) and (ival <> gCfgDirection) then
      begin
        gCfgDirection := ival;
        flags := flags or CFG_CHANGED_DIRECTION;
        changed := True;
        { 横/竖屏：屏幕逻辑尺寸/密度随旋转变化 → 重查 display 并刷新全局缩放 }
        OhosRefreshDisplayScaling;
        flags := flags or CFG_CHANGED_DISPLAYSZ;
      end;
    end
    else if key = 'den' then
    begin
      if TryStrToFloat(val, fval) and (Abs(fval - gCfgDensityPixels) > 0.001) then
      begin
        gCfgDensityPixels := fval;
        { 屏幕密度变化 → 重算缩放 + 全量重绘（逻辑坐标不变，不自动改窗口尺寸） }
        ApplyScreenScaling(fval, 0, 0, gOhosScreenDpi);
        RefreshAllWindows;
        flags := flags or CFG_CHANGED_DENSITY;
        changed := True;
      end;
    end
    else if key = 'denkonf' then
    begin
      if TryStrToInt(val, ival) and (ival <> gCfgScreenDensity) then
      begin
        gCfgScreenDensity := ival;
        changed := True;
      end;
    end
    else if key = 'i' then
    begin
      if TryStrToInt(val, ival) and (ival <> gCfgDisplayId) then
      begin
        gCfgDisplayId := ival;
        changed := True;
      end;
    end
    else if key = 'p' then
    begin
      cur := BoolToStr(gCfgHasPointerDevice, True);
      if val <> cur then
      begin
        gCfgHasPointerDevice := (val = 'true') or (val = '1') or (val = 'TRUE');
        changed := True;
      end;
    end
    else if key = 'f' then
    begin
      if val <> gCfgFontId then
      begin
        gCfgFontId := val;
        changed := True;
      end;
    end
    else if key = 'fs' then
    begin
      if TryStrToFloat(val, fval) and (Abs(fval - gCfgFontSizeScale) > 0.001) then
      begin
        gCfgFontSizeScale := fval;
        flags := flags or CFG_CHANGED_FONTSCALE;
        changed := True;
      end;
    end
    else if key = 'fw' then
    begin
      if TryStrToFloat(val, fval) and (Abs(fval - gCfgFontWeightScale) > 0.001) then
      begin
        gCfgFontWeightScale := fval;
        changed := True;
      end;
    end
    else if key = 'mcc' then
    begin
      if val <> gCfgMcc then
      begin
        gCfgMcc := val;
        flags := flags or CFG_CHANGED_LOCALE;
        changed := True;
      end;
    end
    else if key = 'mnc' then
    begin
      if val <> gCfgMnc then
      begin
        gCfgMnc := val;
        flags := flags or CFG_CHANGED_LOCALE;
        changed := True;
      end;
    end
    else if key = 'lc' then
    begin
      if val <> gCfgLocale then
      begin
        gCfgLocale := val;
        flags := flags or CFG_CHANGED_LOCALE;
        changed := True;
      end;
    end
    else if key = 'tf' then
    begin
      if val <> gCfgTimeFormat then
      begin
        gCfgTimeFormat := val;
        changed := True;
      end;
    end
    else if key = 'df' then
    begin
      if val <> gCfgDateFormat then
      begin
        gCfgDateFormat := val;
        changed := True;
      end;
    end;
    if changed then
      fpGUI_Hilog(LOG_INFO, format('Config %s=%s', [key, val]));
  end;

  { 一次 KV 全部处理后统一投递（聚合所有变化位）：
    主窗体 override DefaultHandler 消费 FPGM_OHOS_CONFIG_CHANGED，
    msg.Params.user.Param1 = flags（CFG_CHANGED_* 位）。 }
  if flags <> 0 then
  begin
    gCfgChangedFlags := flags;
    if (fpgApplication <> nil) and (fpgApplication.MainForm <> nil) then
    begin
      params.user.Param1 := flags;
      fpgPostMessage(fpgApplication, fpgApplication.MainForm,
                     FPGM_OHOS_CONFIG_CHANGED, params);
    end;
    fpGUI_Hilog(LOG_INFO, format('Config msg to MainForm flags=%x', [flags]));
  end;
end;

{ ═══════════════════════════════════════════════════════════════
  TfpgOhosCmdLineParams — ICmdLineParams 实现
  解析 OhosArgs 空格分隔参数："-b debug key=value"
  ═══════════════════════════════════════════════════════════════ }

constructor TfpgOhosCmdLineParams.Create(const AAppArgs, APayload: string);
var tmp: TStringList;
    i: Integer;
begin
  inherited Create;
  FItems := TStringList.Create;
  FOptionChar := '-';
  FCaseSensitiveOptions := False;
  // 1. 解析 OhosArgs → 按空格分割追加到 FItems
  if Trim(AAppArgs) <> '' then
  begin
    tmp := TStringList.Create;
    try
      tmp.Delimiter := ' ';
      tmp.StrictDelimiter := True;
      tmp.DelimitedText := Trim(AAppArgs);
      for i := 0 to tmp.Count - 1 do
        if Trim(tmp[i]) <> '' then
          FItems.Add(Trim(tmp[i]));
    finally
      tmp.Free;
    end;
  end;
  // 2. 解析 gLaunchParams → JSON 字段追加为 key=value
  ParsePayload(APayload);
end;

destructor TfpgOhosCmdLineParams.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TfpgOhosCmdLineParams.ParsePayload(const APayload: string);
var
  p, pEnd, pField: PChar;
  key, value, subKey: string;
begin
  if APayload = '' then Exit;
  p := PChar(APayload);
  while (p^ <> #0) and (p^ <> '{') do Inc(p);
  if p^ = '{' then Inc(p);

  while p^ <> #0 do
  begin
    while (p^ <> #0) and (p^ in [' ', ',', #10, #13, #9]) do Inc(p);
    if (p^ = #0) or (p^ = '}') then Break;

    if p^ = '"' then Inc(p);
    pField := p;
    while (p^ <> #0) and (p^ <> '"') do Inc(p);
    SetString(key, pField, p - pField);
    if p^ = '"' then Inc(p);

    while (p^ <> #0) and (p^ in [' ', #9]) do Inc(p);
    if p^ = ':' then Inc(p);
    while (p^ <> #0) and (p^ in [' ', #9]) do Inc(p);

    if p^ = '"' then
    begin
      Inc(p);
      pField := p;
      while (p^ <> #0) and (p^ <> '"') do
      begin
        if (p^ = '\') and (p[1] <> #0) then Inc(p);
        Inc(p);
      end;
      SetString(value, pField, p - pField);
      if p^ = '"' then Inc(p);
      value := StringReplace(value, '\"', '"', [rfReplaceAll]);
      value := StringReplace(value, '\\', '\', [rfReplaceAll]);
      value := StringReplace(value, '\n', #10, [rfReplaceAll]);
      value := StringReplace(value, '\r', #13, [rfReplaceAll]);
      value := StringReplace(value, '\t', #9, [rfReplaceAll]);
      FItems.Add(key + '=' + value);
    end
    else if p^ = '{' then
    begin
      Inc(p);
      while (p^ <> #0) and (p^ <> '}') do
      begin
        while (p^ <> #0) and (p^ in [' ', ',', #10, #13, #9]) do Inc(p);
        if (p^ = #0) or (p^ = '}') then Break;
        if p^ = '"' then Inc(p);
        pField := p;
        while (p^ <> #0) and (p^ <> '"') do Inc(p);
        SetString(subKey, pField, p - pField);
        if p^ = '"' then Inc(p);
        while (p^ <> #0) and (p^ in [' ', #9]) do Inc(p);
        if p^ = ':' then Inc(p);
        while (p^ <> #0) and (p^ in [' ', #9]) do Inc(p);
        if p^ = '"' then
        begin
          Inc(p);
          pField := p;
          while (p^ <> #0) and (p^ <> '"') do
          begin
            if (p^ = '\') and (p[1] <> #0) then Inc(p);
            Inc(p);
          end;
          SetString(value, pField, p - pField);
          if p^ = '"' then Inc(p);
          value := StringReplace(value, '\"', '"', [rfReplaceAll]);
          value := StringReplace(value, '\\', '\', [rfReplaceAll]);
          FItems.Add(key + '.' + subKey + '=' + value);
        end
        else
          Inc(p);
        while (p^ <> #0) and (p^ in [' ', ',', #9]) do Inc(p);
      end;
      if p^ = '}' then Inc(p);
    end
    else
      Inc(p);
    while (p^ <> #0) and (p^ in [' ', #9]) do Inc(p);
  end;
end;

function TfpgOhosCmdLineParams.GetOptionAtIndex(AIndex: Integer; IsLong: Boolean): string;
var
  P: Integer;
  O: String;
begin
  Result := '';
  If (AIndex < 0) then
    Exit;
  If IsLong then
  begin // Long options have form --option=value
    O := FItems[AIndex];
    P := Pos('=', O);
    if (P = 0) then
      P := Length(O);
    Delete(O, 1, P);
    Result := O;
  end
  else
  begin // short options have form '-o value'
    if (AIndex<ParamCount-1) then
      if (Copy(FItems[AIndex+1], 1, 1) <> '-') then
        Result := FItems[AIndex+1];
  end;
end;

function TfpgOhosCmdLineParams.FindOptionIndex(const S: string; var LongOpt: Boolean; StartAt: Integer): Integer;
var
  SO, O: string;
  I, P: integer;
begin
  if not CaseSensitiveOptions then
    SO := UpperCase(S)
  else
    SO := S;
  Result := -1;
  I := StartAt;
  if (I = -1) then
    I := ParamCount-1;
  while (Result = -1) and (I >= 0) do
  begin
    O := FItems[i];
    // - must be seen as an option value
    if (Length(O) > 1) and (O[1] = FOptionChar) then
    begin
      Delete(O, 1, 1);
      LongOpt := (Length(O) > 0) and (O[1] = FOptionChar);
      if LongOpt then
        Delete(O, 1, 1);
      P := Pos('=', O);
      if (P <> 0) then
        O := Copy(O, 1, P - 1);
      if not CaseSensitiveOptions then
        O      := UpperCase(O);
      if (O = SO) then
        Result := i;
    end;
    Dec(i);
  end;
end;

function TfpgOhosCmdLineParams.GetOptionValue(const S: string): string;
begin
  Result := GetoptionValue(#255, S);
end;

function TfpgOhosCmdLineParams.GetOptionValue(const C: char; const S: string): string;
var
  B: Boolean;
  I, P: integer;
  O: string;
begin
  Result := '';
  B := False;
  I      := FindOptionIndex(C, B);
  if (I = -1) then
    I := FindoptionIndex(S, B);
  if (I <> -1) then
    if B then
    begin
      // Long options have form --option=value
      O := FItems[I];
      P := Pos('=', O);
      if (P = 0) then
        P := Length(O);
      Delete(O, 1, P);
      Result := O;
    end
    else if (I < ParamCount-1) then
    begin
      if (Copy(FItems[I+1], 1, 1) <> '-') then
        Result := FItems[I+1]; // short options have form '-o value'
    end;
end;

function TfpgOhosCmdLineParams.GetOptionValues(const C: Char; const S: string): TStringArray;
var
  I, Cnt: Integer;
  B: Boolean;
begin
  SetLength(Result, ParamCount);
  Cnt := 0;
  Repeat
    I := FindOptionIndex(C, B, I);
    If I<>-1 then
    begin
      Inc(Cnt);
      Dec(I);
    end;
  Until I = -1;
  Repeat
    I := FindOptionIndex(S, B,I );
    If I <> -1 then
    begin
      Inc(Cnt);
      Dec(I);
    end;
  Until I = -1;
  SetLength(Result, Cnt);
  Cnt := 0;
  I := -1;
  Repeat
    I := FindOptionIndex(C, B, I);
    If (I <> -1) then
    begin
      Result[Cnt] := GetOptionAtIndex(I, False);
      Inc(Cnt);
      Dec(i);
    end;
  Until (I = -1);
  I := -1;
  Repeat
    I := FindOptionIndex(S, B, I);
    If I <> -1 then
    begin
      Result[Cnt] := GetOptionAtIndex(I, True);
      Inc(Cnt);
      Dec(i);
    end;
  Until (I = -1);
end;

function TfpgOhosCmdLineParams.HasOption(const S: string): Boolean;
var
  B: Boolean;
begin
  B := False;
  Result := FindOptionIndex(S, B) <> -1;
end;  

function TfpgOhosCmdLineParams.HasOption(const C: char; const S: string): Boolean;
var
  B: Boolean;
begin
  B := False;
  Result := (FindOptionIndex(C, B) <> -1) or (FindOptionIndex(S, B) <> -1);
end;

function TfpgOhosCmdLineParams.CheckOptions(const ShortOptions: string; const Longopts: TStrings; AllErrors: Boolean): string;
begin
  Result := CheckOptions(ShortOptions, LongOpts, nil, nil, AllErrors);
end;

function TfpgOhosCmdLineParams.CheckOptions(const ShortOptions: string; const Longopts: TStrings; Opts, NonOpts: TStrings; AllErrors: Boolean): string;
var
  I, J, L, P: integer;
  O, OV, SO: string;
  UsedArg, HaveArg: Boolean;

  function FindLongOpt(S: string): Boolean;
  var
    I: integer;
  begin
    Result := Assigned(LongOpts);
    if not Result then
      Exit;
    if CaseSensitiveOptions then
    begin
      I := LongOpts.Count - 1;
      while (I >= 0) and (LongOpts[i] <> S) do
        Dec(i);
    end
    else
    begin
      S := UpperCase(S);
      I := LongOpts.Count - 1;
      while (I >= 0) and (UpperCase(LongOpts[i]) <> S) do
        Dec(i);
    end;
    Result := (I <> -1);
  end;

  procedure AddToResult(const Msg: string);
  begin
    if (Result <> '') then
      Result := Result + LineEnding;
    Result := Result + Msg;
  end;

begin
  if CaseSensitiveOptions then
    SO := ShortOptions
  else
    SO := LowerCase(ShortOptions);
  Result := '';
  I := 1;
  while (I < ParamCount) and ((Result = '') or AllErrors) do
  begin
    O := FItems[I];
    if (Length(O) = 0) or (O[1] <> FOptionChar) then
    begin
      if Assigned(NonOpts) then
        NonOpts.Add(O);
    end
    else
	  begin
      if (Length(O) < 2) then
        AddToResult(Format(SErrInvalidOption, [i, O]))
      else
      begin
        HaveArg := False;
        OV      := '';
        // Long option ?
        if (O[2] = FOptionChar) then
        begin
          Delete(O, 1, 2);
          J := Pos('=', O);
          if J <> 0 then
          begin
            HaveArg := True;
            OV      := O;
            Delete(OV, 1, J);
            O       := Copy(O, 1, J - 1);
          end;
          // Switch Option
          if FindLongopt(O) then
          begin
            if HaveArg then
              AddToResult(Format(SErrNoOptionAllowed, [I, O]));
          end
          else
          begin // Required argument
            if FindLongOpt(O + ':') then
            begin
              if not HaveArg then
                AddToResult(Format(SErrOptionNeeded, [I, O]));
            end
            else
            begin // Optional Argument.
              if not FindLongOpt(O + '::') then
                AddToResult(Format(SErrInvalidOption, [I, O]));
            end;
          end;
        end
        else // Short Option.
        begin
          HaveArg := (I < ParamCount-1) and (Length(FItems[I + 1]) > 0) and (FItems[I + 1][1] <> FOptionChar);
          UsedArg := False;
          if HaveArg then
            OV := FItems[I + 1];
          if not CaseSensitiveOptions then
            O := LowerCase(O);
          L := Length(O);
          J := 2;
          while ((Result = '') or AllErrors) and (J <= L) do
          begin
            P := Pos(O[J], ShortOptions);
            if (P = 0) or (O[j] = ':') then
              AddToResult(Format(SErrInvalidOption, [I, O[J]]))
            else
            begin
		          if (P < Length(ShortOptions)) and (Shortoptions[P + 1] = ':') then
			        begin
                // Required argument
                if ((P + 1) = Length(ShortOptions)) or (Shortoptions[P + 2] <> ':') then
                  if (J < L) or not haveArg then // Must be last in multi-opt !!
                    AddToResult(Format(SErrOptionNeeded, [I, O[J]]));
                O := O[j]; // O is added to arguments.
                UsedArg := True;
              end;
            end;
            Inc(J);
          end;
          if HaveArg and UsedArg then
          begin
            Inc(I); // Skip argument.
            O := O[Length(O)]; // O is added to arguments !
          end;
        end;
        if HaveArg and ((Result = '') or AllErrors) then
          if Assigned(Opts) then
            Opts.Add(O + '=' + OV);
      end;
    end;
    Inc(I);
  end;
end;

function TfpgOhosCmdLineParams.CheckOptions(const ShortOptions: string; const Longopts: array of string; Opts, NonOpts: TStrings; AllErrors: Boolean): string;
var
  L: TStringList;
  I: integer;
begin
  L := TStringList.Create;
  try
    for I := 0 to High(LongOpts) do
      L.Add(LongOpts[i]);
    Result := CheckOptions(ShortOptions, L, Opts, NonOpts, AllErrors);
  finally
    L.Free;
  end;
end;

function TfpgOhosCmdLineParams.CheckOptions(const ShortOptions: string; const LongOpts: array of string; AllErrors: Boolean): string;
var
  L: TStringList;
  I: integer;
begin
  L := TStringList.Create;
  try
    for I := 0 to High(LongOpts) do
      L.Add(LongOpts[i]);
    Result := CheckOptions(ShortOptions, L, AllErrors);
  finally
    L.Free;
  end;
end;

function TfpgOhosCmdLineParams.CheckOptions(const ShortOptions: string; const LongOpts: string; AllErrors: Boolean): string;
const
  cSepChars = ' '#10#13#9;
var
  L: TStringList;
  Len, I, J: integer;
begin
  L := TStringList.Create;
  try
    I := 1;
    Len := Length(LongOpts);
    while I <= Len do
    begin
      while Isdelimiter(cSepChars, LongOpts, I) do
        Inc(I);
      J := I;
      while (J <= Len) and not IsDelimiter(cSepChars, LongOpts, J) do
        Inc(J);
      if (I <= J) then
        L.Add(Copy(LongOpts, I, (J - I)));
      I := J + 1;
    end;
    Result := CheckOptions(Shortoptions, L, AllErrors);
  finally
    L.Free;
  end;
end;

function TfpgOhosCmdLineParams.GetNonOptions(const ShortOptions: string; const LongOpts: array of string): TStringArray;
var
  NO : TStrings;
  I : Integer;
begin
  NO := TStringList.Create;
  try
    GetNonOptions(ShortOptions, LongOpts, No);
    SetLength(Result, NO.Count);
    For I := 0 to NO.Count-1 do
      Result[I] := NO[i];
  finally
    NO.Free;
  end;
end;

procedure TfpgOhosCmdLineParams.GetNonOptions(const ShortOptions: string; const LongOpts: array of string; NonOptions: TStrings);
var
  S: String;
begin
  S := CheckOptions(ShortOptions, LongOpts, Nil, NonOptions, true);
  if (S <> '') then
    Raise EListError.Create(S);
end;

function TfpgOhosCmdLineParams.GetCaseSensitiveOptions: Boolean;
begin
  Result := FCaseSensitiveOptions;
end;

function TfpgOhosCmdLineParams.GetOptionChar: char;
begin
  Result := FOptionChar;
end;

procedure TfpgOhosCmdLineParams.SetCaseSensitiveOptions(AValue: Boolean);
begin
  FCaseSensitiveOptions := AValue;
end;

procedure TfpgOhosCmdLineParams.SetOptionChar(AValue: char);
begin
  FOptionChar := AValue;
end;

function TfpgOhosCmdLineParams.ParamStr(AIndex: integer): string;
begin
  if AIndex < FItems.Count then 
    Result := FItems[AIndex]
  else
    Result := '';
end;

function TfpgOhosCmdLineParams.GetParams(AIndex: integer): string;
begin
  Result := GetOptionAtIndex(AIndex, False);
end;

function TfpgOhosCmdLineParams.GetParamCount: integer;
begin
  Result := FItems.Count;
end;

{ ═══════════════════════════════════════════════════════════════
  HandleLaunchParamsEvent — 启动载荷 JSON 消费（UI 线程）
  热启动由 C++ set_launch_params 调用；仅更新 gLaunchParams + 事件回调
  appArgs 已由 ohos_inject_app_args 独立处理，此处不再提取
  ═══════════════════════════════════════════════════════════════ }
procedure HandleLaunchParamsEvent(const APayload: string);
begin
  if APayload = '' then Exit;
  gLaunchParams := APayload;
  fpGUI_Hilog(LOG_INFO, format('HandleLaunchParamsEvent: gLaunchParams=%s', [gLaunchParams]));
  if Assigned(OnOhosLaunchParams) then
    OnOhosLaunchParams(APayload);
end;

{ 运行期 display 重查（旋转/分辨率变化）：更新 gOhosScreenW/H/Dpi 与缩放全局。
  由 'd'（方向）配置变化分支调用；Pascal 直调 native_display_manager，
  无需 C++ 桥参与。失败时保留原值（ApplyScreenScaling 跳过）。 }
procedure OhosRefreshDisplayScaling;
var
  w, h, dpi: Int32;
  ratio: Single;
begin
  w := 0; h := 0; dpi := 0; ratio := 0;
  if OH_NativeDisplayManager_GetDefaultDisplayWidth(w) <> 0 then Exit;
  if OH_NativeDisplayManager_GetDefaultDisplayHeight(h) <> 0 then Exit;
  OH_NativeDisplayManager_GetDefaultDisplayDensityDpi(dpi);
  if OH_NativeDisplayManager_GetDefaultDisplayVirtualPixelRatio(ratio) = 0 then
    if ratio > 0 then
      gCfgDensityPixels := ratio;
  ApplyScreenScaling(gCfgDensityPixels, w, h, dpi);
  fpGUI_Hilog(LOG_INFO, format('Display refreshed (rotation): %dx%d dpi=%d den=%.4f',
    [w, h, dpi, gCfgDensityPixels]));
end;

{ 系统 Configuration 变更消费（UI 线程）：转发至全局对比处理。
   fontSizeScale/fontWeightScale 仅存储不消费（fontScale 暂不处理——
   字放大需控件重排策略，避免界面显示不全）。 }
procedure TfpgOhosApplication.ProcessQueuedConfigEvents;
var
  ev: PfpgOhosConfigEvent;
begin
  if FConfigQueue = nil then Exit;
  while True do
  begin
    FConfigQueueLock.Enter;
    try
      if FConfigQueue.Count = 0 then
        ev := nil
      else
      begin
        ev := PfpgOhosConfigEvent(FConfigQueue[0]);
        FConfigQueue.Delete(0);
      end;
    finally
      FConfigQueueLock.Leave;
    end;
    if ev = nil then Break;

    case ev^.Kind of
      0: HandleConfigurationEvent(ev^.Config);
      1: HandleLaunchParamsEvent(ev^.Config);
    end;
    Dispose(ev);
  end;
end;

{ Qt QPA 式 RepaintHelper：窗口 resize 后 NativeWindow buffer 池可能滞后
  （hdl 几何未随窗口更新），安排定时重试重绘直到 buffer 尺寸跟上（或达上限）。
  触发方：DoPutBufferToScreen 检测 hdl < bitmap 时；执行方：CheckRepaintHelper
  （ProcessQueuedEvents 每轮检查到期——Invalidate 目标窗口触发重绘）。 }
procedure TfpgOhosApplication.ScheduleRepaintHelper(AWin: TfpgWinHandle);
begin
  if AWin = nil then Exit;
  if FRepaintWin = AWin then
  begin
    if FRepaintTicks > 0 then Exit;      { 已在重试中 }
    Exit;                                { ★ 本窗口预算已耗尽，不再自动重启 }
  end;
  FRepaintWin   := AWin;
  FRepaintTicks := 200;                  { ~12s 上限（60ms/次）；几何追上即 Cancel 提前停止 }
  FRepaintNext  := GetTickCount64 + 60;
  FRepaintArmLogged := False;            { 新一轮只打一条 arm 日志 }
end;

{ 几何失配解除 → 停止重试。由 DoPutBufferToScreen 在 hdl = bitmap 时调用。 }
procedure TfpgOhosApplication.CancelRepaintHelper(AWin: TfpgWinHandle);
begin
  if FRepaintWin <> AWin then Exit;
  FRepaintWin   := nil;
  FRepaintTicks := 0;
  FRepaintNext  := 0;
end;

procedure TfpgOhosApplication.CheckRepaintHelper;
var
  wnd: TfpgWindowBase;
begin
  if FRepaintTicks <= 0 then Exit;
  if FRepaintWin = nil then
  begin
    FRepaintTicks := 0;
    Exit;
  end;
  if GetTickCount64 < FRepaintNext then Exit;
  FRepaintNext := GetTickCount64 + 60;
  Dec(FRepaintTicks);
  wnd := FindWindowByHandle(FRepaintWin);
  if (wnd <> nil) and (wnd.PrimaryWidget is TfpgWidget) then
  begin
    TfpgWidget(wnd.PrimaryWidget).Invalidate;
    { 降噪：只在本轮首次 tick 打一条；60ms/次的重试不再刷屏。 }
    if not FRepaintArmLogged then
    begin
      FRepaintArmLogged := True;
      fpGUI_Hilog(LOG_INFO, format('RepaintHelper: arm ticks=%d wnd=%s',
        [FRepaintTicks, wnd.ClassName]));
    end;
  end;

  if FRepaintTicks > 0 then Exit;          { 预算未尽，下一轮继续 }

  { 预算耗尽：保留 FRepaintWin（Schedule 见同窗口已耗尽即不再重启），
    只打一条放弃日志；下次进入时首行 FRepaintTicks<=0 直接 Exit，不再打印。
    几何追上时由 CancelRepaintHelper 清除，之后新尺寸才允许重新上膛 ——
    由此彻底杜绝 retry=3→0 无限自持。 }
  fpGUI_Hilog(LOG_INFO, 'RepaintHelper: budget exhausted, stop');
  FRepaintTicks := 0;
end;

{ OHOS key code → fpGUI key_* mapping.
  ArkUI onKeyEvent delivers KeyCode enum values matching
  native_key_event.h ARKUI_KEYCODE_* constants. }
const
  OHOS_KEYCODE_A            = 2017;
  OHOS_KEYCODE_B            = 2018;
  OHOS_KEYCODE_C            = 2019;
  OHOS_KEYCODE_D            = 2020;
  OHOS_KEYCODE_E            = 2021;
  OHOS_KEYCODE_F            = 2022;
  OHOS_KEYCODE_G            = 2023;
  OHOS_KEYCODE_H            = 2024;
  OHOS_KEYCODE_I            = 2025;
  OHOS_KEYCODE_J            = 2026;
  OHOS_KEYCODE_K            = 2027;
  OHOS_KEYCODE_L            = 2028;
  OHOS_KEYCODE_M            = 2029;
  OHOS_KEYCODE_N            = 2030;
  OHOS_KEYCODE_O            = 2031;
  OHOS_KEYCODE_P            = 2032;
  OHOS_KEYCODE_Q            = 2033;
  OHOS_KEYCODE_R            = 2034;
  OHOS_KEYCODE_S            = 2035;
  OHOS_KEYCODE_T            = 2036;
  OHOS_KEYCODE_U            = 2037;
  OHOS_KEYCODE_V            = 2038;
  OHOS_KEYCODE_W            = 2039;
  OHOS_KEYCODE_X            = 2040;
  OHOS_KEYCODE_Y            = 2041;
  OHOS_KEYCODE_Z            = 2042;
  OHOS_KEYCODE_0            = 2000;
  OHOS_KEYCODE_1            = 2001;
  OHOS_KEYCODE_2            = 2002;
  OHOS_KEYCODE_3            = 2003;
  OHOS_KEYCODE_4            = 2004;
  OHOS_KEYCODE_5            = 2005;
  OHOS_KEYCODE_6            = 2006;
  OHOS_KEYCODE_7            = 2007;
  OHOS_KEYCODE_8            = 2008;
  OHOS_KEYCODE_9            = 2009;
  OHOS_KEYCODE_STAR         = 2010;
  OHOS_KEYCODE_POUND        = 2011;
  OHOS_KEYCODE_DPAD_UP      = 2012;
  OHOS_KEYCODE_DPAD_DOWN    = 2013;
  OHOS_KEYCODE_DPAD_LEFT    = 2014;
  OHOS_KEYCODE_DPAD_RIGHT   = 2015;
  OHOS_KEYCODE_DPAD_CENTER  = 2016;
  OHOS_KEYCODE_COMMA        = 2043;
  OHOS_KEYCODE_PERIOD       = 2044;
  OHOS_KEYCODE_ALT_LEFT     = 2045;
  OHOS_KEYCODE_ALT_RIGHT    = 2046;
  OHOS_KEYCODE_SHIFT_LEFT   = 2047;
  OHOS_KEYCODE_SHIFT_RIGHT  = 2048;
  OHOS_KEYCODE_TAB          = 2049;
  OHOS_KEYCODE_SPACE        = 2050;
  OHOS_KEYCODE_ENTER        = 2054;
  OHOS_KEYCODE_DEL          = 2055;
  OHOS_KEYCODE_GRAVE        = 2056;
  OHOS_KEYCODE_MINUS        = 2057;
  OHOS_KEYCODE_EQUALS       = 2058;
  OHOS_KEYCODE_LEFT_BRACKET = 2059;
  OHOS_KEYCODE_RIGHT_BRACKET= 2060;
  OHOS_KEYCODE_BACKSLASH    = 2061;
  OHOS_KEYCODE_SEMICOLON    = 2062;
  OHOS_KEYCODE_APOSTROPHE   = 2063;
  OHOS_KEYCODE_SLASH        = 2064;
  OHOS_KEYCODE_AT           = 2065;
  OHOS_KEYCODE_PLUS         = 2066;
  OHOS_KEYCODE_MENU         = 2067;
  OHOS_KEYCODE_PAGE_UP      = 2068;
  OHOS_KEYCODE_PAGE_DOWN    = 2069;
  OHOS_KEYCODE_ESCAPE       = 2070;
  OHOS_KEYCODE_FORWARD_DEL  = 2071;
  OHOS_KEYCODE_CTRL_LEFT    = 2072;
  OHOS_KEYCODE_CTRL_RIGHT   = 2073;
  OHOS_KEYCODE_CAPS_LOCK    = 2074;
  OHOS_KEYCODE_SCROLL_LOCK  = 2075;
  OHOS_KEYCODE_META_LEFT    = 2076;
  OHOS_KEYCODE_META_RIGHT   = 2077;
  OHOS_KEYCODE_FUNCTION     = 2078;
  OHOS_KEYCODE_SYSRQ        = 2079;
  OHOS_KEYCODE_BREAK        = 2080;
  OHOS_KEYCODE_MOVE_HOME    = 2081;
  OHOS_KEYCODE_MOVE_END     = 2082;
  OHOS_KEYCODE_INSERT       = 2083;
  OHOS_KEYCODE_FORWARD      = 2084;
  OHOS_KEYCODE_F1           = 2090;
  OHOS_KEYCODE_F2           = 2091;
  OHOS_KEYCODE_F3           = 2092;
  OHOS_KEYCODE_F4           = 2093;
  OHOS_KEYCODE_F5           = 2094;
  OHOS_KEYCODE_F6           = 2095;
  OHOS_KEYCODE_F7           = 2096;
  OHOS_KEYCODE_F8           = 2097;
  OHOS_KEYCODE_F9           = 2098;
  OHOS_KEYCODE_F10          = 2099;
  OHOS_KEYCODE_F11          = 2100;
  OHOS_KEYCODE_F12          = 2101;
  OHOS_KEYCODE_VOLUME_UP    = 16;
  OHOS_KEYCODE_VOLUME_DOWN  = 17;
  OHOS_KEYCODE_BACK         = 2;
  { Modifier key bitmask (ui_input_event.h) }
  OHOS_MODIFIER_CTRL  = 1 shl 0;
  OHOS_MODIFIER_SHIFT = 1 shl 1;
  OHOS_MODIFIER_ALT   = 1 shl 2;
  OHOS_MODIFIER_META  = 1 shl 3;

{ Convert OHOS modifier bitmask to fpGUI TShiftState }
function OhosModifiersToShiftState(AModifiers: Integer): TShiftState;
begin
  Result := [];
  if (AModifiers and OHOS_MODIFIER_SHIFT) <> 0 then
    Include(Result, ssShift);
  if (AModifiers and OHOS_MODIFIER_ALT) <> 0 then
    Include(Result, ssAlt);
  if (AModifiers and OHOS_MODIFIER_CTRL) <> 0 then
    Include(Result, ssCtrl);
  if (AModifiers and OHOS_MODIFIER_META) <> 0 then
    Include(Result, ssMeta);
end;

{ Map OHOS key code (ARKUI_KEYCODE_*) to fpGUI key_* constant. }
function MapOhosKeyToFpgKey(AOhosKeyCode: Integer; out AFpgKey: word): Boolean;
begin
  Result := True;
  case AOhosKeyCode of
    OHOS_KEYCODE_A..OHOS_KEYCODE_Z:
      AFpgKey := AOhosKeyCode - OHOS_KEYCODE_A + keyA;
    OHOS_KEYCODE_0..OHOS_KEYCODE_9:
      AFpgKey := AOhosKeyCode - OHOS_KEYCODE_0 + ord('0');
    OHOS_KEYCODE_ENTER:        AFpgKey := keyEnter;
    OHOS_KEYCODE_TAB:          AFpgKey := keyTab;
    OHOS_KEYCODE_SPACE:        AFpgKey := keySpace;
    OHOS_KEYCODE_ESCAPE:       AFpgKey := keyEscape;
    OHOS_KEYCODE_DEL:          AFpgKey := keyBackSpace;
    OHOS_KEYCODE_FORWARD_DEL:  AFpgKey := keyDelete;
    OHOS_KEYCODE_BACKSLASH:    AFpgKey := ord('\');
    OHOS_KEYCODE_SLASH:        AFpgKey := ord('/');
    OHOS_KEYCODE_SEMICOLON:    AFpgKey := ord(';');
    OHOS_KEYCODE_APOSTROPHE:   AFpgKey := ord('''');
    OHOS_KEYCODE_COMMA:        AFpgKey := ord(',');
    OHOS_KEYCODE_PERIOD:       AFpgKey := ord('.');
    OHOS_KEYCODE_MINUS:        AFpgKey := ord('-');
    OHOS_KEYCODE_EQUALS:       AFpgKey := ord('=');
    OHOS_KEYCODE_GRAVE:        AFpgKey := ord('`');
    OHOS_KEYCODE_LEFT_BRACKET: AFpgKey := ord('[');
    OHOS_KEYCODE_RIGHT_BRACKET:AFpgKey := ord(']');
    OHOS_KEYCODE_STAR:         AFpgKey := ord('*');
    OHOS_KEYCODE_POUND:        AFpgKey := ord('#');
    OHOS_KEYCODE_AT:           AFpgKey := ord('@');
    OHOS_KEYCODE_PLUS:         AFpgKey := ord('+');
    OHOS_KEYCODE_DPAD_UP:      AFpgKey := keyUp;
    OHOS_KEYCODE_DPAD_DOWN:    AFpgKey := keyDown;
    OHOS_KEYCODE_DPAD_LEFT:    AFpgKey := keyLeft;
    OHOS_KEYCODE_DPAD_RIGHT:   AFpgKey := keyRight;
    OHOS_KEYCODE_DPAD_CENTER:  AFpgKey := keyEnter;
    OHOS_KEYCODE_PAGE_UP:      AFpgKey := keyPageUp;
    OHOS_KEYCODE_PAGE_DOWN:    AFpgKey := keyPageDown;
    OHOS_KEYCODE_MOVE_HOME:    AFpgKey := keyHome;
    OHOS_KEYCODE_MOVE_END:     AFpgKey := keyEnd;
    OHOS_KEYCODE_INSERT:       AFpgKey := keyInsert;
    OHOS_KEYCODE_MENU:         AFpgKey := keyMenu;
    OHOS_KEYCODE_CAPS_LOCK:    AFpgKey := keyVoid;
    OHOS_KEYCODE_SCROLL_LOCK:  AFpgKey := keyVoid;
    OHOS_KEYCODE_F1..OHOS_KEYCODE_F12:
      AFpgKey := AOhosKeyCode - OHOS_KEYCODE_F1 + keyF1;
    OHOS_KEYCODE_BREAK:        AFpgKey := keyBreak;
    OHOS_KEYCODE_SYSRQ:        AFpgKey := keySysRq;
    OHOS_KEYCODE_VOLUME_UP,
    OHOS_KEYCODE_VOLUME_DOWN,
    OHOS_KEYCODE_BACK:         Result := False;
    else                       Result := False;
  end;
end;

function THackWindow.HackGetFocusWidget: TfpgWidgetBase;
begin
  Result := FindWidgetForKeyEvent;
end;

procedure TfpgOhosApplication.ProcessQueuedKeyEvents;
var
  ev: PfpgOhosKeyEvent;
  dest: TfpgWindowBase;
  fw: TfpgWidget;
  msg: TfpgMessageParams;
  fpgKey: word;
  ss: TShiftState;
  i, clen: Integer;
  text: string;
  cwname: string;  { DIAG: dest 窗口的鼠标当前控件（点击落点参考）}
  fwname: string;  { DIAG: dest 窗口的键盘焦点控件（FindWidgetForKeyEvent）}
begin
  while True do
  begin
    FKeyQueueLock.Enter;
    try
      if (FKeyEventQueue = nil) or (FKeyEventQueue.Count = 0) then
        Break;
      ev := PfpgOhosKeyEvent(FKeyEventQueue[0]);
      FKeyEventQueue.Delete(0);
    finally
      FKeyQueueLock.Leave;
    end;

    { Route to keyboard focus root first (dropdown/popup windows set
      FocusRootWidget on ShowAt, so the keyboard follows the dropdown the
      moment it opens and stays there until the user touches elsewhere),
      then to last touched window, then fall back to main form }
    dest := nil;
    if FocusRootWidget <> nil then
    begin
      fw := FocusRootWidget;
      while (fw <> nil) and (not fw.HasOwnWindow) and (fw.Parent <> nil) do
        fw := fw.Parent;
      if fw <> nil then
        dest := fw.Window;
    end;
    if dest = nil then
      if gFocusedWinHandle <> nil then
        dest := FindWindowByHandle(gFocusedWinHandle);
    if (dest = nil) and (MainForm <> nil) then
      dest := MainForm.Window
    else if (dest = nil) and (FormCount > 0) then
      dest := Forms[0].Window;
    if dest = nil then
    begin
      Dispose(ev);
      Continue;
    end;

    { DIAG: keyboard routing (dropdown keyboard debug) }
    if (dest <> nil) and (dest.CurrentWidget <> nil) then
      cwname := dest.CurrentWidget.ClassName
    else
      cwname := 'nil';
    if (dest is TfpgWindowBase) then
      try
        if THackWindow(dest).HackGetFocusWidget <> nil then
          fwname := THackWindow(dest).HackGetFocusWidget.ClassName
        else
          fwname := 'nil';
      except
        fwname := 'err';
      end
    else
      fwname := 'n/a';
    fpGUI_Hilog(LOG_INFO, 'KEYEV kind=' + IntToStr(ev^.Kind) +
      ' code=' + IntToStr(ev^.KeyCode) + ' act=' + IntToStr(ev^.Action) +
      ' uni=' + IntToStr(ev^.UnicodeChar) +
      ' dest=' + dest.ClassName + '(' + IntToStr(dest.Left) + ',' +
      IntToStr(dest.Top) + ') cw=' + cwname + ' fw=' + fwname);

    case ev^.Kind of
      OHOS_EV_TEXT:
        begin
          { IME insertText: forward each UTF-8 code point as KEYCHAR }
          text := ev^.Text;
          i := 1;
          while i <= Length(text) do
          begin
            clen := Utf8CharLen(Byte(text[i]));
            if clen < 1 then clen := 1;
            if i + clen - 1 > Length(text) then clen := Length(text) - i + 1;
            FillChar(msg, SizeOf(msg), 0);
            msg.keyboard.keychar := Copy(text, i, clen);
            try
              fpgSendMessage(nil, dest, FPGM_KEYCHAR, msg);
            except
              { Widget handling may raise (e.g. message queue full from
                nested RePaint under fast/auto-repeat input). Drop the
                char and keep the event loop alive. }
              fpGUI_Hilog(LOG_INFO, 'ProcessQueuedKeyEvents KEYCHAR dropped');
            end;
            Inc(i, clen);
          end;
        end;
      OHOS_EV_DELETE_LEFT:
        begin
          { IME deleteLeft: N 脳 Backspace (edit widget handles selection too) }
          { Ctrl+X: the focused TextInput component also cuts by itself; its
            onChange delete arrives right after the X KEYPRESS (DoCut) in the
            same queue — drop it so surrounding text is not deleted. }
          if FCutKeyPending then
          begin
            FCutKeyPending := False;
            Dispose(ev);
            Continue;
          end;
          FillChar(msg, SizeOf(msg), 0);
          msg.keyboard.keycode := keyBackSpace;
          msg.keyboard.shiftstate := [];
          for i := 1 to ev^.Count do
          begin
            try
              fpgSendMessage(nil, dest, FPGM_KEYPRESS, msg);
            except
              fpGUI_Hilog(LOG_INFO, 'ProcessQueuedKeyEvents BACKSPACE dropped');
            end;
          end;
        end;
      OHOS_EV_DELETE_RIGHT:
        begin
          FillChar(msg, SizeOf(msg), 0);
          msg.keyboard.keycode := keyDelete;
          msg.keyboard.shiftstate := [];
          for i := 1 to ev^.Count do
          begin
            try
              fpgSendMessage(nil, dest, FPGM_KEYPRESS, msg);
            except
              fpGUI_Hilog(LOG_INFO, 'ProcessQueuedKeyEvents DELETE dropped');
            end;
          end;
        end;
      OHOS_EV_MOVE_CURSOR:
        begin
          case ev^.Count of
            OHOS_CURSOR_LEFT:  fpgKey := keyLeft;
            OHOS_CURSOR_RIGHT: fpgKey := keyRight;
            OHOS_CURSOR_UP:    fpgKey := keyUp;
            OHOS_CURSOR_DOWN:  fpgKey := keyDown;
          else
            fpgKey := 0;
          end;
          if fpgKey <> 0 then
          begin
            FillChar(msg, SizeOf(msg), 0);
            msg.keyboard.keycode := fpgKey;
            msg.keyboard.shiftstate := [];
            fpgSendMessage(nil, dest, FPGM_KEYPRESS, msg);
          end;
        end;
    else { OHOS_EV_KEY }
      begin
		// IME 文本中的换行符同时生成 FPGM_KEYPRESS  
		if (ev^.UnicodeChar in [10,13]) then 
		begin
		    FillChar(msg, SizeOf(msg), 0);
			msg.keyboard.keycode := keyReturn;
			try
			  fpgSendMessage(nil, dest, FPGM_KEYPRESS, msg);
			except
			  fpGUI_Hilog(LOG_INFO, 'ProcessQueuedKeyEvents ENTER dropped');
			end;
		end;

        FillChar(msg, SizeOf(msg), 0);

        { Handle Unicode character input (from soft/hardware keyboard).
          Ctrl/Alt/Meta 组合是命令键，不产生字符输入（KEYCHAR）——否则
          Ctrl+X/C/V 的字母被当普通字符插入（替换选中/污染粘贴）。 }
        if (ev^.UnicodeChar > 0) and (ev^.Action = OH_KEY_DOWN) and
           ((ev^.Modifiers and (OHOS_MODIFIER_CTRL or OHOS_MODIFIER_ALT or OHOS_MODIFIER_META)) = 0) then
        begin
          msg.keyboard.keychar := UnicodeCodepointToUTF8(ev^.UnicodeChar);
          fpgPostMessage(nil, dest, FPGM_KEYCHAR, msg);
        end;

        { Modifier state: per-event snapshot from the injected modifiers.
          Self-healing — a lost SHIFT-UP can no longer stick the state,
          because every key event re-snapshots it from its own mods field. }
        gShiftPressed := (ev^.Modifiers and OHOS_MODIFIER_SHIFT) <> 0;
        gCtrlPressed  := (ev^.Modifiers and OHOS_MODIFIER_CTRL)  <> 0;
        gAltPressed   := (ev^.Modifiers and OHOS_MODIFIER_ALT)   <> 0;
        case ev^.KeyCode of
          OHOS_KEYCODE_SHIFT_LEFT..OHOS_KEYCODE_SHIFT_RIGHT,
          OHOS_KEYCODE_CTRL_LEFT..OHOS_KEYCODE_CTRL_RIGHT,
          OHOS_KEYCODE_ALT_LEFT..OHOS_KEYCODE_ALT_RIGHT,
          OHOS_KEYCODE_META_LEFT..OHOS_KEYCODE_META_RIGHT,
          OHOS_KEYCODE_FUNCTION:
            begin Dispose(ev); Continue; end;
        end;

        { Build shiftstate directly from the per-event modifiers snapshot }
        ss := OhosModifiersToShiftState(ev^.Modifiers);
        msg.keyboard.shiftstate := ss;

        { Handle raw key events }
        if MapOhosKeyToFpgKey(ev^.KeyCode, fpgKey) then
        begin
          msg.keyboard.keycode := fpgKey;
          { DIAG: mapped keycode (dropdown keyboard debug) }
          fpGUI_Hilog(LOG_INFO, 'KEYEV mapped code=' + IntToStr(ev^.KeyCode) +
            ' -> fpgKey=' + IntToStr(fpgKey) + ' act=' + IntToStr(ev^.Action) +
            ' dest=' + dest.ClassName);
          if ev^.Action = OH_KEY_DOWN then
          begin
            FLastKeyDown := ev^.KeyCode;
            { Ctrl+X (keyX + ssCtrl): DoCut will delete the selection and
              write the clipboard; the TextInput component's own cut follows
              as a deleteLeft injection — mark so it gets dropped. }
            if (fpgKey = ord('X')) and (ssCtrl in ss) then
              FCutKeyPending := True
            else
              FCutKeyPending := False;
            if (fpgKey = ord('V')) and (ssCtrl in ss) then
              fpGUI_Hilog(LOG_INFO, 'KEY Ctrl+V DOWN -> KEYPRESS');
            fpgSendMessage(nil, dest, FPGM_KEYPRESS, msg);
          end
          else if (ev^.Action = OH_KEY_UP) and
                  ((fpgKey = keyBackSpace) or (fpgKey = keyDelete)) then
          begin
            { The focused TextInput component consumes the DOWN of
              Backspace/Delete (it never bubbles to onKeyEvent), so only the
              UP reaches us. Re-fire it as KEYPRESS — unless the DOWN was
              already delivered (FLastKeyDown matches), which would double-delete. }
            if FLastKeyDown <> ev^.KeyCode then
              fpgSendMessage(nil, dest, FPGM_KEYPRESS, msg);
            FLastKeyDown := 0;
          end
          else
          begin
            FLastKeyDown := 0;
            FCutKeyPending := False;   { X UP / other keys clear pending cut flag }
            if (fpgKey = ord('V')) and (ssCtrl in ss) then
              fpGUI_Hilog(LOG_INFO, 'KEY Ctrl+V UP -> KEYRELEASE');
            fpgSendMessage(nil, dest, FPGM_KEYRELEASE, msg);
          end;
        end;
      end;
    end;

    Dispose(ev);
  end;
end;

function TfpgOhosApplication.DoGetFontFaceList: TStringList;
var
  mgr: POH_Drawing_FontMgr;
  cnt, i: Int32;
  fname: PChar;
begin
  Result := TStringList.Create;
  mgr := OH_Drawing_FontMgrCreate;
  if mgr <> nil then
  begin
    cnt := OH_Drawing_FontMgrGetFamilyCount(mgr);
    for i := 0 to cnt - 1 do
    begin
      fname := OH_Drawing_FontMgrGetFamilyName(mgr, i);
      if fname <> nil then
      begin
        Result.Add(StrPas(fname));
        OH_Drawing_FontMgrDestroyFamilyName(fname);
      end;
    end;
    OH_Drawing_FontMgrDestroy(mgr);
  end;
  if Result.Count = 0 then
  begin
    Result.Add('HarmonyOS Sans');
    Result.Add('HarmonyOS Sans Mono');
    Result.Add('HarmonyOS Sans SC');
    Result.Add('HarmonyOS Sans TC');
  end;
  { 中文/鸿蒙家族置顶（UI 字体选择器易用性）：
    逆序遍历命中项 Move 到头部，保持各自相对顺序 }
  for i := Result.Count - 1 downto 0 do
  begin
    if (Pos('SC', Result[i]) > 0) or (Pos('CJK', Result[i]) > 0) or
       (Pos('HarmonyOS', Result[i]) > 0) or (Pos('Noto Sans', Result[i]) > 0) then
      Result.Move(i, 0);
  end;
end;

procedure TfpgOhosApplication.DoWaitWindowMessage(atimeoutms: integer);
var
  rfds: baseunix.TFDSet;
  wakefd: integer;
  maxfd: integer;
  r: integer;
begin
  try
    DoFlush;
    ProcessQueuedWindowCommands;
    ProcessQueuedEvents;
    ProcessQueuedKeyEvents;
    ProcessQueuedResizeEvents;
    ProcessQueuedTrayEvents;
    ProcessQueuedConfigEvents;
    ProcessDragEvents;
    if assigned(gDispatchPump) then gDispatchPump(); //fpgui_dispatch_pump;   { 动态分发：UI 线程执行同步 Handler / 启动异步 Worker }
    SafeDeliverMessages;
  except
    on E: Exception do
      fpGUI_Hilog(LOG_ERROR, 'loop-wave exception: ' + E.ClassName + ': ' + E.Message);
  end;
  UpdateKeyboardVisibility;

  if HasPendingEvents or HasPendingKeyEvents or HasPendingResizeEvents or HasPendingTrayEvents or HasPendingConfigEvents or HasPendingDragEvents or HasPendingDispatchEvents then Exit;

  fpFD_ZERO(rfds);
  maxfd := 0;
  wakefd := -1;
  if WakeChannel <> nil then
  begin
    wakefd := WakeChannel.GetPollFd;
    if wakefd >= 0 then
    begin
      fpFD_SET(wakefd, rfds);
      maxfd := wakefd;
    end;
  end;

  { Cap polling interval. 定时器由 ArkUI tick 驱动兜底后：
    select 超时仅防"无任何唤醒源"的无限 sleep；短定时器仍由
    fpgClosestTimer 传精确 timeout（<2500 不被截断）。
    不再以 500ms 空转轮询检查定时器（避免功耗/精度缺陷）。 }
  if atimeoutms < 0 then
    atimeoutms := 50;   { short poll when requested }
  if atimeoutms > 2500 then
    atimeoutms := 2500;  { upper cap for idle wake（tick 兜底） }

  if maxfd >= 0 then
  begin
    r := fpSelect(maxfd + 1, @rfds, nil, nil, atimeoutms);
    if (wakefd >= 0) and (r > 0) and (fpFD_ISSET(wakefd, rfds) <> 0) then
    begin
      if WakeChannel <> nil then
        WakeChannel.Drain;
    end;
  end
  else
  begin
    { No valid fd — just sleep briefly to avoid busy-looping }
    Sleep(50);
  end;

  try
    ProcessQueuedEvents;
    ProcessQueuedKeyEvents;
    ProcessQueuedWindowCommands;
    ProcessQueuedTrayEvents;
    ProcessQueuedConfigEvents;
    ProcessDragEvents;
    //fpgui_dispatch_pump;   { 唤醒后补泵一次（select 期间到达的 dispatch） }
    if assigned(gDispatchPump) then gDispatchPump();
    SafeDeliverMessages;
  except
    on E: Exception do
      fpGUI_Hilog(LOG_ERROR, 'loop-wave2 exception: ' + E.ClassName + ': ' + E.Message);
  end;

  if Assigned(FOnIdle) then
    try
      { 零未捕获异常：OnIdle 回调一并跨护栏——事件循环内任何
        异常（含与系统 IPC 交错期间）都不再冒泡到 FPC halt(255)，记录并继续 }
      FOnIdle(Self);
    except
      on E: Exception do
        fpGUI_Hilog(LOG_ERROR, 'OnIdle exception: ' + E.ClassName + ': ' + E.Message);
    end;
end;

function TfpgOhosApplication.MessagesPending: boolean;
begin
  Result := HasPendingEvents or HasPendingKeyEvents or HasPendingResizeEvents or HasPendingTrayEvents or HasPendingConfigEvents or HasPendingDragEvents or HasPendingDispatchEvents or (fpgGetFirstMessage <> nil);
end;

procedure TfpgOhosApplication.DoFlush;
begin
  { OHOS 渲染提交在 DoPutBufferToScreen/EndDraw 中完成，
    此函数用于即时处理已入队的系统消息，防止事件积压。 }
  ProcessQueuedResizeEvents;
  SafeDeliverMessages;
end;

function TfpgOhosApplication.GetMonitorCount: Integer;
begin
  Result := 1;
end;

function TfpgOhosApplication.GetMonitorInfo(AIndex: Integer): TfpgScreenInfo;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Bounds.SetRect(0, 0, GetScreenWidth, GetScreenHeight);
  Result.WorkArea := Result.Bounds;
  Result.Primary := AIndex = 0;
  Result.DpiX := Screen_dpi_x;
  Result.DpiY := Screen_dpi_y;
end;

function TfpgOhosApplication.GetCmdLineParamsInterface: ICmdLineParams;
begin
  if not Assigned(FCmdLineParams) then
    FCmdLineParams := TfpgOhosCmdLineParams.Create(OhosArgs, gLaunchParams);
  Result := FCmdLineParams;
end;

function TfpgOhosApplication.GetScreenWidth: TfpgCoord;
begin
  { gOhosScreenW is set by ohos_set_screen_size from the C++ API
    before fpgApplication is created. }
  Result := gOhosScreenW;
end;

function TfpgOhosApplication.GetScreenHeight: TfpgCoord;
begin
  Result := gOhosScreenH;
end;

procedure TfpgOhosApplication.SetScreenSize(AWidth, AHeight: TfpgCoord; ADpi: Integer);
begin
  if AWidth > 0 then FScreenW := AWidth;
  if AHeight > 0 then FScreenH := AHeight;
  if ADpi > 0 then FScreenDpi := ADpi;
end;

function TfpgOhosApplication.GetScreenPixelColor(APos: TPoint): TfpgColor;
begin
  { TODO: Implement screen pixel color capture via OHOS screenshot API
    or native_drawing pixel readback. Requires platform-specific API access. 
	需要用 libohscreenshot.so 截图后读取像素：
	OH_Screenshot_CreateScreenshotCollector(&collector);
	OH_Screenshot_GetScreenshotTrack(collector, &track, timedOut);
	OH_Screenshot_GetMainImage(track, &image);
	从 image.buffer 读取像素
	需要权限 ohos.permission.CAPTURE_SCREEN 和 API 调用，在应用沙箱中可能受限。  
  }
  Result := 0;
end;

function TfpgOhosApplication.Screen_dpi_x: integer;
begin
  Result := gHiDPI;
end;

function TfpgOhosApplication.Screen_dpi_y: integer;
begin
  Result := gHiDPI;
end;

function TfpgOhosApplication.Screen_dpi: integer;
begin
{
布局            		: Screen_dpi = Round(96 × gScaleCore)
窗口/位图/画布   		: × gScaleBackend
输入/resize/屏幕逻辑 	: ÷ gScaleBackend
非 AGG 字体     		: FHeight = fd.Size×96/72 × gScaleCore    （GetHeight 直接返回）
AGG 字体        		: FHeight = fd.Size×96/72 × gScaleCore × gScaleBackend
						GetHeight = FHeight ÷ gHiDPIScaleFactor(=gScaleBackend)
}
  Result := gHiDPI;
end;

{ ---------------------------------------------------------------------
   TfpgOhosClipboard
   --------------------------------------------------------------------- }

function TfpgOhosClipboard.DoGetText: TfpgString;
var
  p: PChar;
begin
  { System clipboard first: covers both external copies and in-app
    copy/cut (DoSetText writes to the system pasteboard via C++). }
  if Assigned(_clipboard_get_text) then
  begin
    p := _clipboard_get_text();
    if p <> nil then
    begin
      Result := StrPas(p);
      fpGUI_Hilog(LOG_INFO, 'clipboard_get: len=' + IntToStr(Length(Result)) +
        ' head=' + Copy(Result, 1, 40));
      { The buffer was allocated by C++ (strdup → libc malloc). FPC's heap
        manager is NOT libc malloc, so FreeMem would corrupt the heap —
        release it with libc free instead. }
      cfree(p);
      Exit;
    end;
    { The system bridge exists but returned nothing (e.g. pasteboard read
      failed/empty). Do NOT fall back to OHOSClipboardBuf here: that buffer
      holds OUR last in-app copy, which is stale once another app replaced
      the system clipboard — pasting it would show old content. }
    Result := '';
    Exit;
  end;
  { Fallback: in-process buffer (only when the system bridge is absent —
    keeps copy/cut/paste working even if the bridge is unavailable). }
  Result := OHOSClipboardBuf;
end;

procedure TfpgOhosClipboard.DoSetText(const AValue: TfpgString);
begin
  OHOSClipboardBuf := AValue;
  if Assigned(_clipboard_set_text) then
    _clipboard_set_text(PChar(AValue));
end;

procedure TfpgOhosClipboard.InitClipboard;
begin
  { Load clipboard bridge functions from the C++ library (in-process).
    bridge_init 已装载时跳过 dlsym（优先使用统一桥）。 }
  if _clipboard_set_text = nil then
    fpGUI_Hilog(LOG_INFO, 'Clipboard: ohos_clipboard_set_text not found');
  if _clipboard_get_text = nil then
    fpGUI_Hilog(LOG_INFO, 'Clipboard: ohos_clipboard_get_text not found');
end;

{ ---------------------------------------------------------------------
   TfpgOhosFileList
   --------------------------------------------------------------------- }

procedure TfpgOhosFileList.PopulateSpecialDirs(const aDirectory: TfpgString);
var
  p: PChar;
begin
  FSpecialDirs.Clear;
  { 基类 PopulateSpecialDirs 的多级绝对路径从 i=1 开始 Insert，
    空列表时 Insert(1) 越界（Windows/Linux 单级路径恰好避坑）。
    Unix 语义：根 '/' 作为第 0 项特殊目录，保证后续 Insert(i>=1) 合法。}
  FSpecialDirs.Add(DirectorySeparator);
  inherited PopulateSpecialDirs(aDirectory);
  if Assigned(_get_user_dir) then
  begin
    p := _get_user_dir(0);  // rawfile
    if (p <> nil) and (p[0] <> #0) then
    begin
      if FSpecialDirs.IndexOf(p) < 0 then
        FSpecialDirs.Add(p);
      cfree(p);
    end;
  end;
  fpGUI_Hilog(LOG_INFO, 'PopulateSpecialDirs: count=' +
    IntToStr(FSpecialDirs.Count) + ' cur=' + IntToStr(CurrentSpecialDir));
end;

function TfpgOhosFileList.ReadDirectory(const aDirectory: TfpgString = ''): boolean;
var
  dir: string;
  p: PChar;
begin
  dir := aDirectory;
  if (dir = '') or (dir = '.') then
  begin
    fpGUI_Hilog(LOG_INFO, 'ReadDirectory fallback: aDirectory="' + aDirectory + '"');
    dir := '';
    if Assigned(_get_user_dir) then
    begin
      p := _get_user_dir(0);          // rawfile
      if (p <> nil) and (p[0] <> #0) then
      begin
        dir := StrPas(p);
        cfree(p);
      end
      else if p <> nil then
        cfree(p);
    end
    else
      fpGUI_Hilog(LOG_INFO, 'ReadDirectory: _get_user_dir not available');
    if dir = '' then
      dir := GetCurrentDir;        // 兜底：CWD
    fpGUI_Hilog(LOG_INFO, 'ReadDirectory resolve: "' + dir + '"');
  end;
  Result := inherited ReadDirectory(dir);
end;

{ ---------------------------------------------------------------------
   TfpgOhosDrag - 系统拖拽（dragController.executeDrag）
   X11 同式模态泵：While not 结束 do PumpEvents(50)
   - 起拖：MimeData → dataJson → _ohos_drag_start（C++/ETS 异步执行，同步返回 sessionId）
   - 泵循环：DoWaitWindowMessage（拖入 enter/move/leave → TfpgOhosDrop、
             drop 同步应答 win-cmd）照常运转
   - 结束：ETS executeDrag 回调 → onDragEnd → ohos_inject_drag_end → EndEvent
   - 结果：SUCCESS → drop 侧协商动作（daMove 精确支持）；否则 daIgnore
   --------------------------------------------------------------------- }

{ 访问 TfpgDrag（fpg_main.pas）的 protected FPreviewWin：隐藏 fpGUI 预览窗，
  避免与系统跟手预览"双图"（零框架改动）}
type
  TDragHack = class(TfpgDrag)
  end;

{ JSON/序列化工具（实现见后）——forward 声明以满足先于 TfpgOhosDrag.Execute 使用 }
function OhosJsonEscape(const S: string): string; forward;
function OhosJsonUnescape(const S: string): string; forward;
function OhosJsonGetString(const AJson, AKey: string; var AValue: string): Boolean; forward;
function DropActionsToInt(const AActions: TfpgDropActions): Int32; forward;
function OhosMimeDataToJson(const AMimeData: TfpgMimeDataBase): string; forward;

function TfpgOhosDrag.Execute(const ADropActions: TfpgDropActions; const ADefaultAction: TfpgDropAction): TfpgDropAction;
var
  app: TfpgOhosApplication;
  dataJson, extraJson: string;
begin
  if FDragging then
    Exit(daIgnore);                       { 重入保护（GDI/X11 同式）}

  FDragging := True;
  Result := ADefaultAction;
  try
    if not Assigned(_ohos_drag_start) then
    begin
      fpGUI_Hilog(LOG_INFO, 'TfpgOhosDrag.Execute: bridge ohos_drag_start unavailable, stub fallback');
      Exit;                               { 返回 ADefaultAction（原 stub 行为）}
    end;

    app := TfpgOhosApplication(fpgApplication);

    { 隐藏 fpGUI 预览窗（TfpgDrag.Execute 已 Show 的 40% 透明 popup 与系统跟手预览
      冲突；FPreviewWin 为 protected，经 TDragHack 访问——零框架改动）}
    if TDragHack(Self).FPreviewWin <> nil then
      TDragHack(Self).FPreviewWin.Visible := False;

    { 序列化 MimeData → dataJson；动作集 → extraJson（ETS 协商 DragBehavior 用）}
    dataJson := OhosMimeDataToJson(FMimeData);
    extraJson := Format('{"actions":%d,"default":%d}',
      [DropActionsToInt(ADropActions), Ord(ADefaultAction)]);

    { 建立会话 }
    gDragSessionLock.Enter;
    try
      gDragSession.Active := True;
      gDragSession.Result := OHOS_DRAG_RESULT_CANCELED;
      gDragSession.DragRef := Self;
      gDragSession.Drop := nil;
      gDragSession.DropWinHandle := nil;
      gDragSession.EndEvent.ResetEvent;
    finally
      gDragSessionLock.Leave;
    end;
    gDragSession.SessionId := _ohos_drag_start(PChar(dataJson), PChar(extraJson));

    { 模态泵循环（X11:4742 同式：While not FFinished do WaitWindowMessage）}
    while gDragSession.Active and (gDragSession.SessionId <> 0) do
    begin
      if gDragSession.EndEvent.WaitFor(50) = wrSignaled then
        Break;
      app.PumpEvents(50);
    end;

    { 结果映射：SUCCESS → drop 侧协商动作（daMove 精确支持）；否则 daIgnore }
    case gDragSession.Result of
      OHOS_DRAG_RESULT_SUCCESS:
        Result := gDragSession.DropAction;
    else
      Result := daIgnore;
    end;
  finally
    gDragSessionLock.Enter;
    try
      gDragSession.Active := False;
      gDragSession.DragRef := nil;
      if gDragSession.Drop <> nil then
        FreeAndNil(gDragSession.Drop);
      gDragSession.DropWinHandle := nil;
    finally
      gDragSessionLock.Leave;
    end;
    FDragging := False;
  end;
end;

function TfpgOhosDrag.GetMimeData: TfpgMimeDataBase;
begin
  Result := FMimeData;
end;

{ ---------------------------------------------------------------------
   TfpgOhosDrop - 系统拖拽拖入目标
   - GetWindowForDrop：会话目标窗口（GDI:1543 / X11:1149 同式）
   - DataDropComplete：应用内拖拽直接读源 MimeData（X11:1100 同式）；
     跨应用数据由 SetDropDataFromRecords 先行写入
   --------------------------------------------------------------------- }

constructor TfpgOhosDrop.Create(AWindow: TfpgWindowBase);
begin
  inherited Create;
  FDropAction := daCopy;
  TargetWindow := AWindow;                 { GDI:1551 同式 }
  if gDragSession.DragRef <> nil then
    FSourceWidget := TfpgDrag(gDragSession.DragRef).Source;   { X11:1160 同式 }
end;

procedure TfpgOhosDrop.SetSourceWidget(AWidget: TfpgWidgetBase);
begin
  FSourceWidget := AWidget;
end;

function TfpgOhosDrop.GetDropAction: TfpgDropAction;
begin
  Result := FDropAction;
end;

procedure TfpgOhosDrop.SetDropAction(AValue: TfpgDropAction);
begin
  FDropAction := AValue;
end;

function TfpgOhosDrop.GetWindowForDrop: TfpgWindowBase;
begin
  Result := TargetWindow;
end;

{ 应用内拖拽：按 MimeChoice 从源 MimeData 取数据；跨应用：records 已写入 FDropData }
procedure TfpgOhosDrop.DataDropComplete;
var
  m: TfpgMimeDataBase;
  accepted: Boolean;
begin
  if gDragSession.Active and (gDragSession.DragRef <> nil) and (MimeChoice <> '') then
  begin
    m := TfpgOhosDrag(gDragSession.DragRef).GetMimeData;
    if (m <> nil) and m.HasFormat(MimeChoice) then
      SetDropData(m.GetData(MimeChoice));
  end;
  { 应答捕获须在 inherited 之前：基类 DataDropComplete 成功后会把
    FDropStatus 改为 dsDropped，之后判定会误报"未接受" }
  accepted := FDropStatus = dsAccepted;
  inherited DataDropComplete;
  { 回填应答（ProcessQueuedWindowCommands case 4 读取）}
  gDragSession.DropAccept := accepted;
  gDragSession.DropAction := FDropAction;
end;

procedure TfpgOhosDrop.HandlePosition(AX, AY: Integer);
begin
  SetPosition(AX, AY);                     { 核心引擎：路由 Enter/Leave/Move/Accept }
end;

procedure TfpgOhosDrop.HandleLeave;
begin
  TargetWidget := nil;                     { GDI HandleDNDLeave 同式 }
end;

procedure TfpgOhosDrop.HandleDrop(AX, AY: Integer);
begin
  { 强制重路由：move 阶段 Mimetypes 未知（getSummary key 是数字索引）时控件已
    RejectDrop，且 SetTargetWidget 检测"目标未变化"不会重入 Enter——清空目标
    使 SetPosition 重新走 Enter → DropHandler 用兜底填充的 Mimetypes 重新判定。
    FWinMousePos 重置：drop 坐标常与最后 move 相同，SetPosition 的坐标去重
    会提前 Exit 导致 TargetWidget 保持 nil（DataDropComplete 空转 → 偶发拒绝）。}
  if (Mimetypes.Count > 0) and (TargetWidget <> nil) then
    TargetWidget := nil;
  FWinMousePos := fpgPoint(-1, -1);
  SetPosition(AX, AY);                     { 最终定位（drop 点与最后 move 可能不同）}
  DataDropComplete;
end;

function TfpgOhosDrop.DropAccepted: Boolean;
begin
  Result := gDragSession.DropAccept;
end;

{ ETS getSummary → Mimetypes（{"types":[{"utd":"...","mime":"text/plain"},...]}）}
procedure TfpgOhosDrop.LoadMimeTypesFromSummary(const ASummaryJson: string);
var
  work: string;
  mime: string;
  p: Integer;
  itm: TfpgMimeDataItem;
begin
  if ASummaryJson = '' then Exit;
  work := ASummaryJson;
  while True do
  begin
    if not OhosJsonGetString(work, 'mime', mime) then Break;
    if mime <> '' then
    begin
      itm := TfpgMimeDataItem.Create(mime, 0);
      Mimetypes.Add(itm);
    end;
    p := Pos('"mime"', work);
    if p = 0 then Break;
    Inc(p, 8);
    if p >= Length(work) then Break;
    Delete(work, 1, p);
  end;
end;

{ drop 兜底：从 records JSON 的 type 字段推导 mime（enter 的 summary 映射失败时）。
  UTD → fpGUI mime 前缀匹配（实测 UTD 带数字后缀，如 'general.image-65'）。}
procedure TfpgOhosDrop.LoadMimeTypesFromRecords(const ARecordsJson: string);
var
  work: string;
  t, mime: string;
  p: Integer;
  itm: TfpgMimeDataItem;
begin
  if ARecordsJson = '' then Exit;
  work := ARecordsJson;
  while True do
  begin
    if not OhosJsonGetString(work, 'type', t) then Break;
    { 前缀匹配覆盖 UTD 后缀（-65 等）：注意 general.plain-text 不以 general.text 开头，
      必须单独匹配（此前漏配导致外部文本拖入 mimes 空 → 拒绝）}
    if (Pos('general.plain-text', t) = 1) or (Pos('general.text', t) = 1) or
       (Pos('general.hyperlink', t) = 1) then
      mime := 'text/plain'
    else if Pos('general.html', t) = 1 then
      mime := 'text/html'
    else if (Pos('general.file', t) = 1) or (Pos('general.image', t) = 1) or
            (Pos('general.video', t) = 1) or (Pos('general.audio', t) = 1) or
            (Pos('general.folder', t) = 1) then
      mime := 'text/uri-list'
    else
      mime := '';
    if mime <> '' then
    begin
      itm := TfpgMimeDataItem.Create(mime, 0);
      Mimetypes.Add(itm);
    end;
    p := Pos('"type"', work);
    if p = 0 then Break;
    Inc(p, 7);
    if p >= Length(work) then Break;
    Delete(work, 1, p);
  end;
end;

{ 应用内拖拽兜底：从源 MimeData.Formats 填充 Mimetypes（summary 缺失/映射失败时）}
procedure TfpgOhosDrop.LoadMimeTypesFromSource;
var
  m: TfpgMimeDataBase;
  sl: TStrings;
  i: Integer;
  itm: TfpgMimeDataItem;
begin
  if not (gDragSession.Active and (gDragSession.DragRef <> nil)) then Exit;
  m := TfpgOhosDrag(gDragSession.DragRef).GetMimeData;
  if m = nil then Exit;
  sl := m.Formats;
  try
    for i := 0 to sl.Count - 1 do
    begin
      itm := TfpgMimeDataItem.Create(sl[i], 0);
      Mimetypes.Add(itm);
    end;
  finally
    sl.Free;
  end;
end;

{ 跨应用 drop：records JSON → FDropData（text/html/uris 提取）}
procedure TfpgOhosDrop.SetDropDataFromRecords(const ARecordsJson: string);
var
  text, html, s: string;
  uris: TStringList;
  p: Integer;
  work: string;
begin
  if ARecordsJson = '' then Exit;
  text := ''; html := '';
  uris := TStringList.Create;
  try
    if OhosJsonGetString(ARecordsJson, 'textContent', s) then text := s;
    if OhosJsonGetString(ARecordsJson, 'htmlContent', s) then html := s;
    work := ARecordsJson;
    while True do
    begin
      if not OhosJsonGetString(work, 'uri', s) then Break;
      uris.Add(s);
      p := Pos('"uri"', work);
      if p = 0 then Break;
      Inc(p, 6);
      if p >= Length(work) then Break;
      Delete(work, 1, p);
    end;
    if text <> '' then
      SetDropData(text)
    else if uris.Count > 0 then
      SetDropData(uris[0])              { FDropData 为 Variant：单 URI 字符串（v1）}
    else if html <> '' then
      SetDropData(html);
  finally
    uris.Free;
  end;
end;

{ ---------------------------------------------------------------------
   JSON 工具（固定 schema 的轻量提取；ETS 侧 JSON.stringify 输出：
   非 ASCII 原样 UTF-8，转义仅 " \ \n \r \t 及 \uXXXX 控制符）
   --------------------------------------------------------------------- }

function OhosJsonEscape(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    case S[i] of
      '"':  Result := Result + '\"';
      '\':  Result := Result + '\\';
      #10:  Result := Result + '\n';
      #13:  Result := Result + '\r';
      #9:   Result := Result + '\t';
      #0..#8, #11, #12, #14..#31:
        Result := Result + '\u' + IntToHex(Ord(S[i]), 4);
    else
      Result := Result + S[i];
    end;
  end;
end;

function OhosJsonUnescape(const S: string): string;
var
  i: Integer;
  cp: LongWord;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if S[i] = '\' then
    begin
      Inc(i);
      if i > Length(S) then Break;
      case S[i] of
        '"':  Result := Result + '"';
        '\':  Result := Result + '\';
        '/':  Result := Result + '/';
        'n':  Result := Result + #10;
        'r':  Result := Result + #13;
        't':  Result := Result + #9;
        'u':
          begin
            cp := StrToInt64('$' + Copy(S, i + 1, 4));
            Result := Result + UnicodeCodepointToUTF8(cp);   { 单元内已有 }
            Inc(i, 4);
          end;
      end;
      Inc(i);
    end
    else
    begin
      Result := Result + S[i];
      Inc(i);
    end;
  end;
end;

{ 提取 JSON 对象中指定键的字符串值（首个匹配；供固定 schema 使用）}
function OhosJsonGetString(const AJson, AKey: string; var AValue: string): Boolean;
var
  i, p, e: Integer;
begin
  Result := False;
  i := 1;
  while i <= Length(AJson) do
  begin
    if AJson[i] = '"' then
    begin
      p := i + 1;
      e := p;
      while (e <= Length(AJson)) and (AJson[e] <> '"') do Inc(e);
      if (e - p = Length(AKey)) and (Copy(AJson, p, e - p) = AKey) then
      begin
        i := e + 1;
        while (i <= Length(AJson)) and (AJson[i] in [' ', #9, #10, #13]) do Inc(i);
        if (i <= Length(AJson)) and (AJson[i] = ':') then
        begin
          Inc(i);
          while (i <= Length(AJson)) and (AJson[i] in [' ', #9, #10, #13]) do Inc(i);
          if (i <= Length(AJson)) and (AJson[i] = '"') then
          begin
            Inc(i);
            p := i;
            while (i <= Length(AJson)) and (AJson[i] <> '"') do
            begin
              if AJson[i] = '\' then Inc(i, 2) else Inc(i);
            end;
            AValue := OhosJsonUnescape(Copy(AJson, p, i - p));
            Result := True;
            Exit;
          end;
        end;
      end;
      i := e + 1;
    end
    else
      Inc(i);
  end;
end;

{ TfpgDropActions 位掩码 → int（extraJson 协商用）}
function DropActionsToInt(const AActions: TfpgDropActions): Int32;
var
  a: TfpgDropAction;
begin
  Result := 0;
  for a in AActions do
    Result := Result or (1 shl Ord(a));
end;

{ 拖出：MimeData → dataJson（{"text","html","uris","types"}）}
function OhosMimeDataToJson(const AMimeData: TfpgMimeDataBase): string;
var
  sl: TStrings;
  i: Integer;
begin
  if AMimeData = nil then Exit('{}');
  Result := '{';
  if AMimeData.Text <> '' then
    Result := Result + '"text":"' + OhosJsonEscape(AMimeData.Text) + '",';
  if AMimeData.HTML <> '' then
    Result := Result + '"html":"' + OhosJsonEscape(AMimeData.HTML) + '",';
  if (AMimeData.urls <> nil) and (AMimeData.urls.Count > 0) then
  begin
    Result := Result + '"uris":[';
    for i := 0 to AMimeData.urls.Count - 1 do
    begin
      if i > 0 then Result := Result + ',';
      Result := Result + '"' + OhosJsonEscape(StrPas(PChar(AMimeData.urls[i]))) + '"';
    end;
    Result := Result + '],';
  end;
  sl := AMimeData.Formats;
  try
    Result := Result + '"types":[';
    for i := 0 to sl.Count - 1 do
    begin
      if i > 0 then Result := Result + ',';
      Result := Result + '"' + OhosJsonEscape(sl[i]) + '"';
    end;
    Result := Result + ']';
  finally
    sl.Free;
  end;
  Result := Result + '}';
end;

{ ---------------------------------------------------------------------
   TfpgOhosSystemTrayIcon - HarmonyOS trayIcon (@kit.CoreKit, 2in1/PC)
   通过 C++ 桥接命令通道（ohos_tray_add/set_menu/remove）控制 ETS 托盘，
   事件通道（onTrayEvent → ohos_inject_tray_event）回传点击/菜单选择。
   --------------------------------------------------------------------- }

{ JSON 字符串转义（菜单 label 安全序列化）}
function OhosTrayEscapeJson(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    case S[i] of
      '"':  Result := Result + '\"';
      '\':  Result := Result + '\\';
      #10:  Result := Result + '\n';
      #13:  Result := Result + '\r';
      #9:   Result := Result + '\t';
      else  Result := Result + S[i];
    end;
  end;
end;

constructor TfpgOhosSystemTrayIcon.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FActive := False;
  FMenuIndex := TList.Create;
  { 注册全局托盘事件回调（应用单托盘实例；多实例时后注册者生效）}
  OnOhosTray := @HandleTrayEvent;
end;

destructor TfpgOhosSystemTrayIcon.Destroy;
begin
  Hide;
  { 仅当本实例仍是全局回调注册者时清空 }
  if TMethod(OnOhosTray).Code = TMethod(TfpgOhosTrayEventProc(@HandleTrayEvent)).Code then
    OnOhosTray := nil;
  FMenuIndex.Free;
  inherited Destroy;
end;

{ 序列化 Owner.PopupMenu（fpGUI 原生菜单）为系统托盘菜单 JSON。
  规则：Separator/Header → {"type":"sep"}；其余 → {"id":"mN","label":...}；
  id 与 FMenuIndex 下标一一对应（事件回传按 id 反查 TfpgMenuItem）。
  子菜单（item.SubMenu）与勾选态（Checked）预留：SDK 支持后扩展 JSON。 }
procedure TfpgOhosSystemTrayIcon.SyncMenu;
var
  w: TfpgSystemTrayIcon;
  menu: TfpgPopupMenu;
  i, n, itemIdx: Integer;
  item: TfpgMenuItem;
  json: string;
begin
  if not Assigned(_ohos_tray_set_menu) then Exit;
  w := TfpgSystemTrayIcon(Self.Owner);
  if (w = nil) or (w.PopupMenu = nil) then Exit;
  menu := w.PopupMenu;
  FMenuIndex.Clear;
  json := '[';
  n := 0;
  itemIdx := 0;
  for i := 0 to menu.ComponentCount - 1 do
  begin
    if not (menu.Components[i] is TfpgMenuItem) then Continue;
    item := TfpgMenuItem(menu.Components[i]);
    if not item.Visible then Continue;
    if n > 0 then json := json + ',';
    if item.Separator or item.Header then
      json := json + '{"id":"sep' + IntToStr(n) + '","type":"sep"}'
    else
    begin
      json := json + '{"id":"m' + IntToStr(itemIdx) + '","label":"'
        + OhosTrayEscapeJson(item.Text) + '"}';
      FMenuIndex.Add(item);
      Inc(itemIdx);
    end;
    Inc(n);
  end;
  json := json + ']';
  fpGUI_Hilog(LOG_INFO, format('Tray SyncMenu: %s', [json]));
  _ohos_tray_set_menu(PChar(json));
end;

procedure TfpgOhosSystemTrayIcon.HandleTrayEvent(evType: Integer; const MenuId: string);
var
  w: TfpgSystemTrayIcon;
  i: Integer;
  item: TfpgMenuItem;
begin
  case evType of
    0: begin  { 左键点击 → widget OnClick（应用恢复主窗等）}
         w := TfpgSystemTrayIcon(Self.Owner);
         if Assigned(w) and Assigned(w.OnClick) then
           w.OnClick(w);
       end;
    1: begin  { 右键点击：系统自动显示菜单，仅记录 }
         fpGUI_Hilog(LOG_INFO, 'Tray rightClick');
       end;
    2: begin  { 菜单项选中 → 按 id 反查 TfpgMenuItem 触发 OnClick }
         for i := 0 to FMenuIndex.Count - 1 do
         begin
           if MenuId = 'm' + IntToStr(i) then
           begin
             item := TfpgMenuItem(FMenuIndex[i]);
             if Assigned(item.OnClick) then
               item.OnClick(item);
             Break;
           end;
         end;
       end;
    3: begin  { add 结果回传 }
         FActive := (MenuId = 'ok');
         fpGUI_Hilog(LOG_INFO, format('Tray add result: %s', [MenuId]));
       end;
  end;
end;

procedure TfpgOhosSystemTrayIcon.Show;
var
  w: TfpgSystemTrayIcon;
  title: string;
begin
  if FActive then Exit;
  w := TfpgSystemTrayIcon(Self.Owner);
  if (w = nil) or (not Assigned(_ohos_tray_add)) then Exit;
  SyncMenu;
  title := w.Hint;
  if title = '' then title := 'fpGUI';
  fpGUI_Hilog(LOG_INFO, format('Tray Show: title=%s', [title]));
  _ohos_tray_add(PChar(title), 0);
  { 乐观置真（ETS 结果回传前即可用）；add 失败由 evType=3 'fail' 复位 }
  FActive := True;
end;

procedure TfpgOhosSystemTrayIcon.Hide;
begin
  FActive := False;
  gTrayActive := False;
  if Assigned(_ohos_tray_remove) then
    _ohos_tray_remove();
end;

function TfpgOhosSystemTrayIcon.IsSystemTrayAvailable: boolean;
begin
  Result := FActive;
end;

function TfpgOhosSystemTrayIcon.SupportsMessages: boolean;
begin
  { HarmonyOS 通知体系可用（ShowMessage 通知模块为后续增强）}
  Result := True;
end;

procedure ohos_set_screen_size(w, h, dpi: Integer; density: Single); cdecl;
begin
  { fpGUI HiDPI scale factor = dp = VirtualPixelRatio (OHOS system scale).
    All coordinates and AggPas canvas use this uniform factor.
    缩放计算与 den 变化共用 ApplyScreenScaling（fpg_ohos 配置处理）。 }
  ApplyScreenScaling(density, w, h, dpi);

  fpGUI_Hilog(LOG_INFO,'gScaleFactor='+floattostr(gScaleFactor)+' W='+inttostr(gOhosScreenW)+' H='+inttostr(gOhosScreenH)+' gOhosScreenDpi='+inttostr(gOhosScreenDpi));
end;

procedure ohos_set_zoom_scale(scale: Single); cdecl;
begin
  gZoomScale := scale;
end;

{ 系统 Configuration 变更/首启初始化入口（C++ 经 bridge update_configuration 调用）。
   启动阶段（fpgApplication 未建）直接在调用线程写全局（无并发）；
   运行阶段投递消息队列，由 UI 线程消费（防跨线程直接改全局）。 }
procedure ohos_update_configuration(config: PChar); cdecl;
begin
  if config = nil then Exit;
  if (fpgApplication <> nil) and (fpgApplication is TfpgOhosApplication) then
    TfpgOhosApplication(fpgApplication).EnqueueConfigurationEvent(StrPas(config))
  else
    HandleConfigurationEvent(StrPas(config));
end;

{ 启动载荷 JSON 注入入口（C++ 经 bridge set_launch_params 调用）。
   冷启动：Pascal RunLazarus 直接收 argv[1]（不经本函数）；
   热启动：ETS onNewWant → setLaunchParams NAPI → 本函数。
   连接期直接就地处理；运行期投递 UI 线程队列（防跨线程直接改全局）。 }
procedure ohos_set_launch_params(payload: PChar); cdecl; export;
begin
  if payload = nil then Exit;
  if (fpgApplication <> nil) and (fpgApplication is TfpgOhosApplication) then
    TfpgOhosApplication(fpgApplication).EnqueueLaunchParamsEvent(StrPas(payload))
  else
    HandleLaunchParamsEvent(StrPas(payload));
end;

{ 命令行参数注入（C++ pro()/run() 前调用）：
  payload → gLaunchParams（want JSON）；appArgs → OhosArgs（已替换 %placeholder%） }
procedure ohos_inject_app_args(payload, appArgs: PChar); cdecl; export;
begin
  if payload <> nil then
  begin
    gLaunchParams := StrPas(payload);
    fpGUI_Hilog(LOG_INFO, format('ohos_inject_app_args: gLaunchParams=%s', [gLaunchParams]));
  end;
  if appArgs <> nil then
  begin
    OhosArgs := StrPas(appArgs);
    fpGUI_Hilog(LOG_INFO, format('ohos_inject_app_args: OhosArgs=%s', [OhosArgs]));
  end;
end;

{ ── 定时器 ArkUI 注入驱动 ──────────────────────────────
   fpGUI 框架定时器由 fpgCheckTimers 检查（CheckAlarm），其驱动源本为
   select 超时轮询（cap 500ms：功耗/精度/后台饿死风险）。
   改为：ETS setInterval(T,12ms) tick → ohos_timer_tick → WakeChannel.Signal
   唤醒 select → 事件循环照常 fpgCheckTimers。短定时器仍由 fpgClosestTimer
   精确 timeout（doWait cap 2500）双保险。
   自适应：TfpgOhosTimer.SetEnabled 感知活动计数翻转 → ohos_send_timer_state
   通知 ETS 启停 setInterval（无定时器时零轮询）。 }

procedure NotifyTimerActiveChanged;
var
  active: Integer;
begin
  if gTimerActiveCount < 0 then gTimerActiveCount := 0;
  active := Ord(gTimerActiveCount > 0);
  if gTimerNotified = (active = 1) then Exit;   { 翻转才上抛 }
  gTimerNotified := not gTimerNotified;
  if Assigned(_ohos_send_timer_state) then
  begin
    _ohos_send_timer_state(active);
    fpGUI_Hilog(LOG_INFO, format('Timer state=%d (activeCount=%d)', [active, gTimerActiveCount]));
  end
  else
    fpGUI_Hilog(LOG_INFO, 'Timer state notify unavailable (ohos_send_timer_state not found)');
end;

procedure TfpgOhosTimer.SetEnabled(const AValue: boolean);
var
  oldActive: Integer;
begin
  oldActive := gTimerActiveCount;
  if oldActive < 0 then oldActive := 0;
  inherited SetEnabled(AValue);
  if FEnabled and (oldActive = 0) then
  begin
    gTimerActiveCount := oldActive + 1;
    NotifyTimerActiveChanged;
  end
  else if (not FEnabled) and (oldActive > 0) then
  begin
    gTimerActiveCount := oldActive - 1;
    NotifyTimerActiveChanged;
  end;
end;

procedure ohos_timer_tick(); cdecl;
begin
  if (fpgApplication <> nil) and (fpgApplication is TfpgOhosApplication) then
    TfpgOhosApplication(fpgApplication).WakeChannel.Signal;
end;

function ohos_timer_query(): Integer; cdecl;
begin
  if gTimerActiveCount > 0 then
    Result := 1
  else
    Result := 0;
end;

function ohos_inject_touch_event(x, y: Single; action: Integer): Integer; cdecl;
begin
  { Backward-compatible entry point: routes to main form only.
    For multi-window routing, use ohos_inject_touch_to_window. }
  Result := -1;
  if fpgApplication = nil then Exit;
  if not (fpgApplication is TfpgOhosApplication) then Exit;
  TfpgOhosApplication(fpgApplication).EnqueueTouchEvent(Round(x), Round(y), action, nil);
  if Assigned(OnOhosTouch) then
    OnOhosTouch(Round(x), Round(y));
  Result := 0;
end;

function ohos_inject_touch_to_window(winHandle: TfpgWinHandle; x, y: Single; action: Integer): Integer; cdecl;
begin
  Result := -1;
  if fpgApplication = nil then Exit;
  if not (fpgApplication is TfpgOhosApplication) then Exit;
  TfpgOhosApplication(fpgApplication).EnqueueTouchEvent(Round(x), Round(y), action, winHandle);
  if Assigned(OnOhosTouch) then
    OnOhosTouch(Round(x), Round(y));
  Result := 0;
end;

function ohos_inject_wheel_event(winHandle: TfpgWinHandle; x, y: Single; delta: Integer): Integer; cdecl;
begin
  Result := -1;
  if fpgApplication = nil then Exit;
  if not (fpgApplication is TfpgOhosApplication) then Exit;
  TfpgOhosApplication(fpgApplication).EnqueueWheelEvent(Round(x), Round(y), delta, winHandle);
  Result := 0;
end;

function ohos_inject_hover_event(winHandle: TfpgWinHandle; x, y: Single): Integer; cdecl;
begin
  Result := -1;
  if fpgApplication = nil then Exit;
  if not (fpgApplication is TfpgOhosApplication) then Exit;
  TfpgOhosApplication(fpgApplication).EnqueueHoverEvent(Round(x), Round(y), winHandle);
  Result := 0;
end;

function ohos_inject_tray_event(eventType: Integer; menuId: PChar): Integer; cdecl;
begin
  Result := -1;
  if fpgApplication = nil then Exit;
  if not (fpgApplication is TfpgOhosApplication) then Exit;
  TfpgOhosApplication(fpgApplication).EnqueueTrayEvent(eventType, StrPas(menuId));
  Result := 0;
end;

{ Helper: convert a single Unicode codepoint to UTF-8 string }
function UnicodeCodepointToUTF8(cp: UInt32): string;
begin
  Result := '';
  if cp = 0 then Exit;
  if cp < $80 then
    Result := Chr(cp)
  else if cp < $800 then
    Result := Chr($C0 or (cp shr 6)) + Chr($80 or (cp and $3F))
  else if cp < $10000 then
    Result := Chr($E0 or (cp shr 12)) + Chr($80 or ((cp shr 6) and $3F))
           + Chr($80 or (cp and $3F))
  else if cp < $110000 then
    Result := Chr($F0 or (cp shr 18)) + Chr($80 or ((cp shr 12) and $3F))
           + Chr($80 or ((cp shr 6) and $3F)) + Chr($80 or (cp and $3F));
end;

function ohos_inject_key_event(keyCode, action, modifiers: Integer; unicodeChar: LongWord): Integer; cdecl;
begin
  { Injects keyboard events from the C++ bridge.
    Called from napi_init.cpp when hardware/software keyboard events occur. }
  Result := -1;
  if fpgApplication = nil then Exit;
  if not (fpgApplication is TfpgOhosApplication) then Exit;
  TfpgOhosApplication(fpgApplication).EnqueueKeyEvent(keyCode, action, modifiers, unicodeChar);
  Result := 0;
end;

function ohos_inject_mouse_event(winHandle: TfpgWinHandle; x, y: Single; action, button: Integer): Integer; cdecl;
begin
  Result := -1;
  if fpgApplication = nil then Exit;
  if not (fpgApplication is TfpgOhosApplication) then Exit;
  TfpgOhosApplication(fpgApplication).EnqueueMouseEvent(Round(x), Round(y), action, winHandle, button);
  Result := 0;
end;

{ Inject UTF-8 text from IME into focused widget.
  Enqueued (thread-safe) so the UI thread processes it in order with key
  events - never touch the fpGUI message system from the NAPI thread. }
procedure ohos_inject_text(text: PChar; len: Integer); cdecl;
var
  s: string;
  realLen: Integer;
begin
  if (text = nil) or (len <= 0) or (fpgApplication = nil) then Exit;
  if not (fpgApplication is TfpgOhosApplication) then Exit;
  { Guard against an over-reported length: napi_get_value_string_utf8 may
    return a truncated buffer size (4096 cap) that exceeds the actual
    string, causing SetString to read past the buffer. }
  realLen := StrLen(text);
  if len > realLen then len := realLen;
  if len < 1 then Exit;
  SetString(s, text, len);
  TfpgOhosApplication(fpgApplication).EnqueueTextEvent(s);
end;

{ IME deleteLeft (backspace) 鈥?delete ACount chars before the cursor }
function ohos_inject_delete_chars(ACount: Integer): Integer; cdecl;
begin
  Result := -1;
  if (ACount < 1) or (fpgApplication = nil) then Exit;
  if not (fpgApplication is TfpgOhosApplication) then Exit;
  TfpgOhosApplication(fpgApplication).EnqueueDeleteEvent(OHOS_EV_DELETE_LEFT, ACount);
  Result := 0;
end;

{ IME deleteRight (forward delete) 鈥?delete ACount chars after the cursor }
function ohos_inject_delete_right_chars(ACount: Integer): Integer; cdecl;
begin
  Result := -1;
  if (ACount < 1) or (fpgApplication = nil) then Exit;
  if not (fpgApplication is TfpgOhosApplication) then Exit;
  TfpgOhosApplication(fpgApplication).EnqueueDeleteEvent(OHOS_EV_DELETE_RIGHT, ACount);
  Result := 0;
end;

{ IME moveCursor → ADirection: OHOS_CURSOR_* (inputMethod.Direction) }
function ohos_inject_move_cursor(ADirection: Integer): Integer; cdecl;
begin
  Result := -1;
  if (fpgApplication = nil) then Exit;
  if not (fpgApplication is TfpgOhosApplication) then Exit;
  TfpgOhosApplication(fpgApplication).EnqueueMoveCursorEvent(ADirection);
  Result := 0;
end;

{ Called by the app to show/hide the soft keyboard when an edit gets/loses
  focus. Bridges to ETS via the C++ export ohos_bridge_show_keyboard.
  优先用 ohos_bridge_connect 装载的全局回调；未初始化时 dlsym 兜底。 }
procedure ohos_show_keyboard(show: Integer); cdecl;
begin
  fpGUI_Hilog(LOG_INFO, 'show_keyboard: type=' + IntToStr(show));
  if Assigned(_ohos_show_keyboard_bridge) then
    _ohos_show_keyboard_bridge(show)
  else
    fpGUI_Hilog(LOG_INFO, 'show_keyboard: ohos_bridge_show_keyboard NOT FOUND');
end;

{ ETS 发起版：只记录状态，不 bridge 回 ETS。
  调用方（ETS FpgSurface.showIme/hideIme）随后自行聚焦/取消聚焦 TextInput。
  避免 showIme → testNapi.showKeyboard → 本函数 → bridge → case 6 → showIme 无限回环。 }
procedure ohos_show_keyboard_from_ets(show: Integer); cdecl;
begin
  fpGUI_Hilog(LOG_INFO, 'show_keyboard_from_ets: show=' + IntToStr(show));
end;

function ohos_inject_window_resized(winHandle: TfpgWinHandle; w, h: Integer): Integer; cdecl;
begin
  Result := -1;
  { DIAG [主窗拉长]: ETS onWindowResized 反馈是否真正到达 Pascal 入口
    （origin C++ bridge → 本函数），用于区分"ETS 未调用/调用被吞"与
    "到达但入队/消费滞后"。 }
  fpGUI_Hilog(LOG_INFO, format('OhosWindowResize Feedback 到达: h=%s %dx%d appOK=%d',
    [IntToHex(PtrUInt(winHandle), 8), w, h,
     Integer((fpgApplication <> nil) and (fpgApplication is TfpgOhosApplication))]));
  if fpgApplication = nil then Exit;
  if not (fpgApplication is TfpgOhosApplication) then Exit;
  TfpgOhosApplication(fpgApplication).EnqueueResizeEvent(winHandle, w, h);
  Result := 0;
end;

{ ── 标题栏事件注入（ETS windowEvent/windowRectChange 经 C++ bridge 调用）── }

{ 拖动标题栏/最大化后同步窗口屏幕位置（物理 px）→ FPosition 逻辑。
   触摸映射（屏幕坐标-窗口位置）与弹窗定位随之修正。
   跨线程串行化：入队 → loop 线程 SetScreenPosition（不再 native 直调窗口对象）。 }
function ohos_inject_window_moved(winHandle: TfpgWinHandle; x, y: Integer): Integer; cdecl;
var
  cmd: PfpgOhosWinCmd;
begin
  Result := -1;
  if fpgApplication = nil then Exit;
  if not (fpgApplication is TfpgOhosApplication) then Exit;
  New(cmd);
  cmd^.Kind := 0; cmd^.Handle := winHandle; cmd^.A := x; cmd^.B := y;
  cmd^.Result := 0; cmd^.Awaiter := nil;
  TfpgOhosApplication(fpgApplication).EnqueueWinCmd(cmd);
  Result := 0;
end;

{ 窗口已被系统销毁（标题栏 X 关闭，CanClose 已允许）→ 框架侧标准关闭流程：
   FPGM_CLOSE 消息（TfpgBaseForm.MsgClose → CloseQuery/OnClose/释放）。
   原生句柄已由 C++ 清理。跨线程串行化：入队 → loop 线程执行 Invalidate/Unregister/Close。 }
function ohos_inject_window_closed(winHandle: TfpgWinHandle): Integer; cdecl;
var
  cmd: PfpgOhosWinCmd;
begin
  Result := -1;
  if fpgApplication = nil then Exit;
  if not (fpgApplication is TfpgOhosApplication) then Exit;
  New(cmd);
  cmd^.Kind := 1; cmd^.Handle := winHandle; cmd^.A := 0; cmd^.B := 0;
  cmd^.Result := 0; cmd^.Awaiter := nil;
  TfpgOhosApplication(fpgApplication).EnqueueWinCmd(cmd);
  Result := 0;
end;

{ 标题栏 X 关闭前 CanClose 查询（同步语义，跨线程串行化）：
   入队 CAN_CLOSE → loop 线程执行 CloseQuery（fpg_form.TfpgBaseForm）→ TEvent 唤醒。
   兼容性：FindWindowByHandle 返回 TfpgWindowBase（窗口对象），窗体为其 Owner；
   TfpgWindowBase 与 TfpgBaseForm 无继承关系，判断经 TObject 中转（消费侧实现）。
   1=可关闭 0=不可。 }
function ohos_can_close(winHandle: TfpgWinHandle): Integer; cdecl;
var
  cmd: PfpgOhosWinCmd;
  ev: TEvent;
begin
  Result := 1;   // 默认允许（找不到窗口/非窗体/超时）
  if fpgApplication = nil then Exit;
  if not (fpgApplication is TfpgOhosApplication) then Exit;
  New(cmd);
  cmd^.Kind := 2; cmd^.Handle := winHandle; cmd^.A := 0; cmd^.B := 0;
  cmd^.Result := 1; cmd^.Awaiter := nil;
  ev := TEvent.Create(nil, True, False, '');
  cmd^.Awaiter := ev;
  TfpgOhosApplication(fpgApplication).EnqueueWinCmd(cmd);
  if ev.WaitFor(500) = wrSignaled then
    Result := cmd^.Result
  else
    Result := 1;   // 超时兜底；ev 不 Free（防 loop 后续 SetEvent 悬空，频率低可忽略）
end;

{ 主动刷新窗口（ETS 在 setupMainWindow 尺寸确认后调用）：
   1) Invalidate → 重绘； 2) DoUpdateWindowPosition → 重发 move/resize。
   跨线程串行化：入队 → loop 线程执行（不再 native 直调窗口对象）。 }
procedure ohos_force_window_refresh(winHandle: TfpgWinHandle); cdecl;
var
  cmd: PfpgOhosWinCmd;
begin
  if fpgApplication = nil then Exit;
  if not (fpgApplication is TfpgOhosApplication) then Exit;
  New(cmd);
  cmd^.Kind := 3; cmd^.Handle := winHandle; cmd^.A := 0; cmd^.B := 0;
  cmd^.Result := 0; cmd^.Awaiter := nil;
  TfpgOhosApplication(fpgApplication).EnqueueWinCmd(cmd);
end;

{ ---------------------------------------------------------------------
   系统拖拽注入（C++ 经 bridge inject_drag_event/drag_process_drop/inject_drag_end 调用）
   --------------------------------------------------------------------- }

{ 拖拽事件注入（enter/move/leave）：入队，不阻塞（ETS UI 线程）。
  kind: 0=enter 1=move 2=leave；x/y 物理 px（C++ 已 ×density）}
function ohos_inject_drag_event(winHandle: TfpgWinHandle; kind: Integer;
  x, y: Single; summaryJson: PChar): Integer; cdecl;
var
  s: string;
begin
  Result := -1;
  if fpgApplication = nil then Exit;
  if not (fpgApplication is TfpgOhosApplication) then Exit;
  if summaryJson <> nil then
    s := StrPas(summaryJson)
  else
    s := '';
  TfpgOhosApplication(fpgApplication).EnqueueDragEvent(winHandle, kind,
    Round(x), Round(y), s);
  Result := 0;
end;

{ drop 同步应答：ETS onDrop 阻塞等待（≤5s改:2.5s）。经 win-cmd 队列串行化到 loop 线程
  （照抄 ohos_can_close 的 Awaiter 模式）。返回 (accept<<8)|action：
  accept=1 接受 / 0 拒绝；action ∈ TfpgDropAction（0=ignore..4=ask）}
function ohos_drag_process_drop(winHandle: TfpgWinHandle; x, y: Single;
  recordsJson: PChar): Integer; cdecl;
var
  cmd: PfpgOhosWinCmd;
  ev: TEvent;
begin
  Result := 0;
  if fpgApplication = nil then Exit;
  if not (fpgApplication is TfpgOhosApplication) then Exit;

  { 暂存 drop 参数（loop 线程读取；单会话串行）}
  gDragSessionLock.Enter;
  try
    gDragSession.DropX := Round(x);
    gDragSession.DropY := Round(y);
    if recordsJson <> nil then
      gDragSession.DropRecords := StrPas(recordsJson)
    else
      gDragSession.DropRecords := '';
  finally
    gDragSessionLock.Leave;
  end;

  New(cmd);
  cmd^.Kind := 4; cmd^.Handle := winHandle; cmd^.A := 0; cmd^.B := 0;
  cmd^.Result := 0; cmd^.Awaiter := nil;
  ev := TEvent.Create(nil, True, False, '');
  cmd^.Awaiter := ev;
  TfpgOhosApplication(fpgApplication).EnqueueWinCmd(cmd);
  if ev.WaitFor(2500) = wrSignaled then
    Result := cmd^.Result
  else
    Result := 0;   { 超时兜底：拒绝（ev 不 Free，防 loop 后续 SetEvent 悬空——同 can_close）}
end;

{ 拖拽会话结束（ETS executeDrag 回调）：置 Result + EndEvent + 唤醒事件循环
  （泵循环可能在 fpSelect 阻塞）。取消/失败路径必须回调，否则 Execute 卡 60s。 }
function ohos_inject_drag_end(sessionId: Int64; AResult: Integer): Integer; cdecl;
begin
  Result := -1;
  gDragSessionLock.Enter;
  try
    if gDragSession.Active and (gDragSession.SessionId = sessionId) then
    begin
      gDragSession.Result := AResult;
      if gDragSession.EndEvent <> nil then
        gDragSession.EndEvent.SetEvent;
      Result := 0;
    end;
  finally
    gDragSessionLock.Leave;
  end;
  if fpgApplication is TfpgOhosApplication then
    TfpgOhosApplication(fpgApplication).WakeChannel.Signal;
end;

{ In-process clipboard: stores text in a Pascal string, so FreeMem matches GetMem. }

function ohos_clipboard_set_text(text: PChar): Integer; cdecl;
begin
  if text <> nil then
    OHOSClipboardBuf := StrPas(text)
  else
    OHOSClipboardBuf := '';
  Result := 0;
end;

function ohos_clipboard_get_text: PChar; cdecl;
begin
  if OHOSClipboardBuf <> '' then
  begin
    Result := GetMem(Length(OHOSClipboardBuf) + 1);
    StrCopy(Result, PChar(OHOSClipboardBuf));
  end
  else
    Result := nil;
end;

{ ---------------------------------------------------------------------
   Crash diagnostics: safe message delivery + FPC error hooks + error
   log hook. stderr is invalid under appspawn (any write raises a second
   exception and crashes in the unwind path, fpc_popaddrstack), so all
   diagnostics go through fpGUI_Hilog instead. }
(*procedure SafeDeliverMessages;
begin
  try
    { message pool (fpgPostMessage raises when full). }
    fpgCoalesceMessages;
    fpgDeliverMessages;
  except
    on E: Exception do
    begin
      fpGUI_Hilog(LOG_ERROR, 'SafeDeliverMessages exception: ' + E.ClassName +
        ': ' + E.Message);
      raise;
    end;
  end;
end;*)
{ 消息目标有效性守卫 + 逐条异常隔离（OHOS 专用，不动框架）：
  队列逐条取出 → 若目标窗口/控件已失效则丢弃（防投递到已释放对象 →
  绘制到失效 canvas/控件的 SIGSEGV 根因防线）；有效目标投递异常仅记录。
  修复：FPGM_PAINT 一律放行——框架 TfpgWidget.MsgPaint 在窗口未分配
  （WindowAllocated=False）时自复位 FInvalidated 并安全返回（fpg_widget.pas:
  "The window will generate a paint message later when it exists"）。
  此前软守卫在此场景 drop 了残留 paint，导致 popup 复用打开时 FInvalidated
  残留 True 吞掉首绘 FPGM_PAINT → 弹窗黑屏。残留对象必存活（Destructor 已
  fpgDeleteMessagesForTarget(Self, FPGM_PAINT) 清队），放行无悬垂风险。 }
procedure SafeDeliverMessages;
var
  mp: PfpgMessageRec;
  m: TfpgMessageRec;
  destOk: Boolean;
begin
  try
    fpgCoalesceMessages;
    repeat
      mp := fpgGetFirstMessage;
      if mp <> nil then
      begin
        m := mp^;
        fpgDeleteFirstMessage;
        { 软守卫：窗口类 → HasHandle（失效=False）；widget → WindowAllocated
          FPGM_PAINT 例外：放行给 MsgPaint 自复位（见上注），避免 popup 首绘丢失 }
        destOk := True;
        if m.MsgCode <> FPGM_PAINT then
        begin
          if m.Dest is TfpgWindowBase then
            destOk := TfpgWindowBase(m.Dest).HasHandle
          else if m.Dest is TfpgWidgetBase then
            destOk := TfpgWidgetBase(m.Dest).WindowAllocated;
        end;
        if destOk then
        begin
          fpgDeliverMessage(m);
        end
        else
          fpGUI_Hilog(LOG_INFO, 'drop stale msg code='+inttostr(m.MsgCode)+' dest=%p'+inttostr(QWord(m.Dest)));
      end;
    until mp = nil;
  except
    on E: Exception do
    begin
      fpGUI_Hilog(LOG_ERROR, 'SafeDeliverMessages exception: ' + E.ClassName +	': ' + E.Message);
	  raise;
	end;
  end;
end;

{ ── 字体路径探测与家族映射 ────────────────────────────── }

var
  gFontProbeCache: TStringList = nil;   { path → '1'/'0'；惰性填充 }

function OhosFontExists(const APath: string): Boolean;
var
  idx: Integer;
begin
  if gFontProbeCache = nil then
    gFontProbeCache := TStringList.Create;
  idx := gFontProbeCache.IndexOf(APath);
  if idx >= 0 then
  begin
    Result := (gFontProbeCache.ValueFromIndex[idx] = '1');
    Exit;
  end;
  Result := FileExists(APath);
  if Result then
    gFontProbeCache.Add(APath + '=1')
  else
    gFontProbeCache.Add(APath + '=0');
end;

{ 应用沙箱字体搜索目录（惰性缓存；全部来自官方 Context/桥接，禁止硬编码
  /data/storage 等绝对路径；系统字体目录绝不纳入——系统字体仅经 FontMgr）：
    ''                          → CWD（启动已重定向到 Context.resourceDir=resfile）
    Context.resourceDir         → resfile 解压目录
    Context.filesDir (+fonts/)  → 应用可写目录
    bundleCodeDir/libs/<abi>(+fonts/) → 与 .so 同层 }
var
  gAppFontDirs: TStringList = nil;

function OhosAbiLibDirName: string;
begin
  {$IFDEF CPUX86_64}
  Result := 'x86_64';
  {$ELSE}
    {$IFDEF CPUAARCH64}
    Result := 'arm64-v8a';
    {$ELSE}
      {$IFDEF CPUARM}
      Result := 'armeabi-v7a';
      {$ELSE}
      Result := '';
      {$ENDIF}
    {$ENDIF}
  {$ENDIF}
end;

function OhosAppFontDirs: TStringList;
var
  d: string;
  abi: string;
begin
  if gAppFontDirs = nil then
  begin
    gAppFontDirs := TStringList.Create;
    gAppFontDirs.Add('');                       { CWD = resfile(resourceDir) }
    d := GetResfileDir;
    if d <> '' then
      gAppFontDirs.Add(IncludeTrailingPathDelimiter(d));
    d := GetRawfileDir;                         { Context.filesDir（可写）}
    if d <> '' then
    begin
      gAppFontDirs.Add(IncludeTrailingPathDelimiter(d));
      gAppFontDirs.Add(IncludeTrailingPathDelimiter(d) + 'fonts' + PathDelim);
    end;
    d := GetBundleCodeDir;                      { Context.bundleCodeDir }
    abi := OhosAbiLibDirName;
    if (d <> '') and (abi <> '') then
    begin
      gAppFontDirs.Add(IncludeTrailingPathDelimiter(d) + 'libs' + PathDelim +
        abi + PathDelim);
      gAppFontDirs.Add(IncludeTrailingPathDelimiter(d) + 'libs' + PathDelim +
        abi + PathDelim + 'fonts' + PathDelim);
    end;
  end;
  Result := gAppFontDirs;
end;

function OhosFindFontFile(const AName: string): string;
var
  dirs: TStringList;
  i: Integer;
  cand: string;
begin
  Result := '';
  if AName = '' then Exit;
  { 绝对路径：直接探测（仅应用沙箱路径）}
  if AName[1] = PathDelim then
  begin
    if OhosFontExists(AName) then
      Result := AName;
    Exit;
  end;
  dirs := OhosAppFontDirs;
  for i := 0 to dirs.Count - 1 do
  begin
    cand := dirs[i] + AName;
    if OhosFontExists(cand) then
      Exit(cand);
    { 纯文件名再试 fonts/ 子目录（带子目录的名字跳过，避免 fonts/fonts/）}
    if Pos(PathDelim, AName) = 0 then
    begin
      cand := dirs[i] + 'fonts' + PathDelim + AName;
      if OhosFontExists(cand) then
        Exit(cand);
    end;
  end;
end;

function OhosResolveFontFile(const ACandidates: array of string): string;
var
  i: Integer;
  p: string;
begin
  Result := '';
  for i := Low(ACandidates) to High(ACandidates) do
  begin
    p := OhosFindFontFile(ACandidates[i]);
    if p <> '' then
    begin
      Result := p;
      Exit;
    end;
  end;
end;

{ 启动调试：打印 FontMgr 家族清单（前 25 个）——校准 CJK 匹配与默认映射 }
procedure DumpFontFamilies;
var
  mgr: POH_Drawing_FontMgr;
  cnt, i: Int32;
  fname: PChar;
begin
  mgr := OH_Drawing_FontMgrCreate;
  if mgr = nil then Exit;
  try
    cnt := OH_Drawing_FontMgrGetFamilyCount(mgr);
    for i := 0 to cnt - 1 do
    begin
      fname := OH_Drawing_FontMgrGetFamilyName(mgr, i);
      if fname <> nil then
      begin
        fpGUI_Hilog(LOG_INFO, format('FONT FAMILY[%d]: %s', [i, StrPas(fname)]));
        OH_Drawing_FontMgrDestroyFamilyName(fname);
      end;
      if i >= 24 then Break;
    end;
    fpGUI_Hilog(LOG_INFO, format('FONT FAMILY total=%d', [cnt]));
  finally
    OH_Drawing_FontMgrDestroy(mgr);
  end;
end;

{ 读取系统字体配置（OH_Drawing_GetSystemFontConfigInfo，API 12+）：
  fontDirSet → gSystemFontDirs（权威字体目录，版本/厂商无关）；
  fontGenericInfoSet → gSystemDefaultFamily（系统权威默认家族）。
  失败（nil）时静默降级现有探测。 }
procedure OhosLoadSystemFontConfig;
var
  cfg: POH_Drawing_FontConfigInfo;
  err: Integer;
  i: Integer;
  fam: string;
begin
  err := 0;
  cfg := OH_Drawing_GetSystemFontConfigInfo(@err);
  if cfg = nil then
  begin
    fpGUI_Hilog(LOG_INFO, format('SystemFontConfig unavailable (err=%d)', [err]));
    Exit;
  end;
  try
    if gSystemFontDirs = nil then
      gSystemFontDirs := TStringList.Create;
    gSystemFontDirs.Clear;
    for i := 0 to cfg^.fontDirSize - 1 do
      if cfg^.fontDirSet[i] <> nil then
        gSystemFontDirs.Add(IncludeTrailingPathDelimiter(StrPas(cfg^.fontDirSet[i])));
    fpGUI_Hilog(LOG_INFO, format('SystemFontConfig: dirs=%d generic=%d fallback=%d',
      [cfg^.fontDirSize, cfg^.fontGenericInfoSize, cfg^.fallbackGroupSize]));
    for i := 0 to cfg^.fontGenericInfoSize - 1 do
      if cfg^.fontGenericInfoSet[i].familyName <> nil then
      begin
        fam := StrPas(cfg^.fontGenericInfoSet[i].familyName);
        fpGUI_Hilog(LOG_INFO, format('FONT GENERIC[%d]: %s', [i, fam]));
        if (gSystemDefaultFamily = '') and
           (Pos('harmonyos', LowerCase(fam)) > 0) then
          gSystemDefaultFamily := fam;
      end;
    if gSystemDefaultFamily = '' then
      for i := 0 to cfg^.fontGenericInfoSize - 1 do
        if cfg^.fontGenericInfoSet[i].familyName <> nil then
        begin
          fam := StrPas(cfg^.fontGenericInfoSet[i].familyName);
          if Pos('sans', LowerCase(fam)) > 0 then
          begin
            gSystemDefaultFamily := fam;
            Break;
          end;
        end;
  finally
    OH_Drawing_DestroySystemFontConfigInfo(cfg);
  end;
end;

function OhosMapDefaultFaceName(const AFaceName: string): string;
var
  lc: string;
  mgr: POH_Drawing_FontMgr;
  ss: POH_Drawing_FontStyleSet;
begin
  Result := AFaceName;
  lc := LowerCase(AFaceName);
  if (lc = '') or (lc = 'sans') or (lc = 'sans-serif') or (lc = 'default') then
  begin
    mgr := OH_Drawing_FontMgrCreate;
    if mgr = nil then Exit;
    try
      { 0) 系统权威默认家族（OH_Drawing_GetSystemFontConfigInfo generic；
         FontMgr 家族名为连字符风格，空格版失败时试连字符变体）}
      if gSystemDefaultFamily <> '' then
      begin
        ss := OH_Drawing_FontMgrMatchFamily(mgr, PChar(gSystemDefaultFamily));
        if (ss = nil) and (Pos(' ', gSystemDefaultFamily) > 0) then
          ss := OH_Drawing_FontMgrMatchFamily(mgr,
            PChar(StringReplace(gSystemDefaultFamily, ' ', '-', [rfReplaceAll])));
        if ss <> nil then
        begin
          Result := gSystemDefaultFamily;
          OH_Drawing_FontMgrDestroyFontStyleSet(ss);
          Exit;
        end;
      end;
      { 1) FontMgr 实测家族名为连字符风格（'HarmonyOS-Sans'，无 SC/CJK 家族名）——
        按序探测：SC 空格版 → 连字符版 → 空格版 }
      ss := OH_Drawing_FontMgrMatchFamily(mgr, 'HarmonyOS Sans SC');
      if ss <> nil then
      begin
        Result := 'HarmonyOS Sans SC';
        OH_Drawing_FontMgrDestroyFontStyleSet(ss);
      end
      else
      begin
        ss := OH_Drawing_FontMgrMatchFamily(mgr, 'HarmonyOS-Sans');
        if ss <> nil then
        begin
          Result := 'HarmonyOS-Sans';
          OH_Drawing_FontMgrDestroyFontStyleSet(ss);
        end
        else
        begin
          ss := OH_Drawing_FontMgrMatchFamily(mgr, 'HarmonyOS Sans');
          if ss <> nil then
          begin
            Result := 'HarmonyOS Sans';
            OH_Drawing_FontMgrDestroyFontStyleSet(ss);
          end;
        end;
      end;
    finally
      OH_Drawing_FontMgrDestroy(mgr);
    end;
  end;
end;

{ ---- internal helpers ---- }

function JoinPath(const ABase, ASub: string): string;
begin
  Result := IncludeTrailingPathDelimiter(ABase);
  if ASub <> '' then
    Result := Result + ASub;
end;

function GetResfileDir: string;
var
  p: PChar;
  resDir: string;
begin
  Result := '';
  if not Assigned(_get_user_dir) then
    Exit;
  p := _get_user_dir(3);   // resourceDir (read-only HAP)
  if (p = nil) or (p[0] = #0) then
  begin
    if p <> nil then cfree(p);
    Exit;
  end;
  resDir := p;
  cfree(p);
  Result := resDir;
end;

function GetBundleCodeDir: string;
var
  p: PChar;
  d: string;
begin
  Result := '';
  if not Assigned(_get_user_dir) then
    Exit;
  p := _get_user_dir(6);   // bundleCodeDir (HAP install root)
  if (p = nil) or (p[0] = #0) then
  begin
    if p <> nil then cfree(p);
    Exit;
  end;
  d := p;
  cfree(p);
  Result := d;
end;

function GetRawfileDir: string;
var
  p: PChar;
  filesDir: string;
begin
  Result := '';
  if not Assigned(_get_user_dir) then
    Exit;
  p := _get_user_dir(0);   // filesDir (writable, persistent)
  if (p = nil) or (p[0] = #0) then
  begin
    if p <> nil then cfree(p);
    Exit;
  end;
  filesDir := p;
  cfree(p);
  Result := filesDir;
end;

function EnsureRawfileDir(const ASubDir: string): string;
var
  rawDir: string;
begin
  Result := '';
  rawDir := GetRawfileDir;
  if rawDir = '' then
    Exit;
  rawDir := JoinPath(rawDir, ASubDir);
  if not DirectoryExists(rawDir) then
  begin
    if not ForceDirectories(rawDir) then
      Exit;
  end;
  Result := IncludeTrailingPathDelimiter(rawDir);
end;

{ ---- file copy ---- }

function DoCopyFile(const ASrc, ADst: string): Boolean;
var
  srcStream, dstStream: TFileStream;
begin
  Result := False;
  srcStream := nil;
  dstStream := nil;
  try
    srcStream := TFileStream.Create(ASrc, fmOpenRead or fmShareDenyWrite);
    dstStream := TFileStream.Create(ADst, fmCreate);
    dstStream.CopyFrom(srcStream, 0);
    Result := True;
  except
    on E: Exception do
      fpGUI_Hilog(LOG_ERROR, 'CopyFile error: ' + ASrc + ' -> ' + ADst + ' : ' + E.Message);
  end;
  srcStream.Free;
  dstStream.Free;
end;

function ResFileToRaw(const AFileName: string; const ADestSubDir: string): Boolean;
var
  resDir, rawDir, srcPath, dstPath, destDir: string;
begin
  Result := False;
  resDir := GetResfileDir;
  rawDir := EnsureRawfileDir('');
  if (resDir = '') or (rawDir = '') then
    Exit;
  srcPath := JoinPath(resDir, AFileName);
  destDir := JoinPath(rawDir, ADestSubDir);
  dstPath := JoinPath(destDir, ExtractFileName(AFileName));
  { Make sure the destination subdirectory exists }
  ForceDirectories(destDir);
  if not FileExists(srcPath) then
  begin
    fpGUI_Hilog(LOG_INFO, 'CopyResToRaw: source not found: ' + srcPath);
    Exit;
  end;
  Result := DoCopyFile(srcPath, dstPath);
  if Result then
    fpGUI_Hilog(LOG_INFO, 'CopyResToRaw: ' + AFileName + ' OK');
end;

function ResDirToRaw(const ASrcSubDir: string;
  const ADestSubDir: string): Integer;
var
  resDir, rawDir, srcBase, dstBase: string;
  dstSub: string;

  procedure ProcessDir(const curRel: string);
  var
    sr: TSearchRec;
    curSrc, curDst, entry: string;
  begin
    curSrc := JoinPath(srcBase, curRel);
    curDst := JoinPath(dstBase, curRel);
    if not DirectoryExists(curDst) then
      ForceDirectories(curDst);
    if FindFirst(JoinPath(curSrc, '*'), faAnyFile, sr) = 0 then
    begin
      try
        repeat
          entry := sr.Name;
          if (entry = '.') or (entry = '..') then Continue;
          if (sr.Attr and faDirectory) <> 0 then
            ProcessDir(JoinPath(curRel, entry))
          else
          begin
            if DoCopyFile(JoinPath(curSrc, entry), JoinPath(curDst, entry)) then
              Inc(Result);
          end;
        until FindNext(sr) <> 0;
      finally
        FindClose(sr);
      end;
    end;
  end;

begin
  Result := 0;
  resDir := GetResfileDir;
  rawDir := EnsureRawfileDir('');
  if (resDir = '') or (rawDir = '') then
    Exit;
  srcBase := JoinPath(resDir, ASrcSubDir);
  { ADestSubDir defaults to ASrcSubDir (mirror structure) }
  if ADestSubDir <> '' then
    dstSub := ADestSubDir
  else
    dstSub := ASrcSubDir;
  dstBase := JoinPath(rawDir, dstSub);
  if not DirectoryExists(srcBase) then
  begin
    fpGUI_Hilog(LOG_INFO, 'CopyResDirToRaw: source dir not found: ' + srcBase);
    Exit;
  end;
  ProcessDir('');
  fpGUI_Hilog(LOG_INFO, Format('CopyResDirToRaw: %s -> %s  (%d files)', [srcBase, dstBase, Result]));
end;

var
  SavedErrorProc: TErrorProc;

procedure OhosErrorProc(ErrNo: Longint; Address: Pointer; Frame: Pointer);
begin
  fpGUI_Hilog(LOG_ERROR, 'FPC RTE ' + IntToStr(ErrNo) + ' at ' +
    IntToHex(PtrUInt(Address), 8) + ' frame=' + IntToHex(PtrUInt(Frame), 8));
  if Assigned(SavedErrorProc) then
    SavedErrorProc(ErrNo, Address, Frame);
end;

{ Routes fpGUI core diagnostics (timer/caret exceptions) to hilog. }
procedure OhosErrorLogProc(const AMsg: string);
begin
  fpGUI_Hilog(LOG_ERROR, AMsg);
end;

initialization
  ohos_bridge_connect;
  SavedErrorProc := System.ErrorProc;
  System.ErrorProc := @OhosErrorProc;
end.

