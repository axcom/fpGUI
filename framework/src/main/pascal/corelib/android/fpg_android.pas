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
      Android backend for fpGUI.

      Architecture (see DESIGN.zh-CN.md for the full write-up):
        * The Pascal application runs its own blocking message loop on a
          worker thread; the Java UI thread only injects events through
          the native entry points in fpg_android_bridge.pas and wakes the
          loop through a pipe-based IWakeChannel.
        * The main form owns the activity Surface: its window handle is
          the ANativeWindow* and its canvas buffer IS the screen buffer.
        * Secondary windows (dialogs, popups) have no system window; their
          buffer manager composites their pixels into the screen buffer at
          the window origin and presents.
        * Rendering uses the AGG hybrid canvas (fpg_android_hybrid_canvas)
          with FreeType glyphs and density-based HiDPI scaling.
}

unit fpg_android;

{$I fpg_defines.inc}

interface

uses
  Classes,
  SysUtils,
  CTypes,
  SyncObjs,
  fpg_base,
  fpg_impl,
  fpg_android_ndk,
  fpg_wakechannel;

const
  { Key/text event kinds (mirrors the OHOS queue model). }
  ANDROID_EV_KEY          = 0;
  ANDROID_EV_TEXT         = 1;
  ANDROID_EV_DELETE_LEFT  = 2;
  ANDROID_EV_DELETE_RIGHT = 3;
  ANDROID_EV_MOVE_CURSOR  = 4;

  { moveCursor directions }
  ANDROID_CURSOR_UP    = 1;
  ANDROID_CURSOR_DOWN  = 2;
  ANDROID_CURSOR_LEFT  = 3;
  ANDROID_CURSOR_RIGHT = 4;

  { Android KeyEvent modifiers (mirror of the Java constants) }
  ANDROID_META_SHIFT_ON = $00000001;
  ANDROID_META_ALT_ON   = $00000002;
  ANDROID_META_SYM_ON   = $00000004;
  ANDROID_META_CTRL_ON  = $00001000;
  ANDROID_META_META_ON  = $00010000;

type
  { TfpgAndroidWakeChannel - POSIX pipe based event loop wake-up.

    Android's app sandbox allows pipe()/fcntl()/select() (verified on
    Android 5..15); if pipe creation fails the loop falls back to a 50ms
    poll (see TfpgAndroidApplication.DoWaitWindowMessage). }
  TfpgAndroidWakeChannel = class(TInterfacedObject, IWakeChannel)
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

  { TfpgAndroidImage - memory only image; the hybrid canvas reads
    TfpgImage.ImageData directly, no native resource needed. }
  TfpgAndroidImage = class(TfpgImageBase)
  protected
    procedure DoFreeImage; override;
    procedure DoInitImage(acolordepth, awidth, aheight: integer; aimgdata: Pointer); override;
    procedure DoInitImageMask(awidth, aheight: integer; aimgdata: Pointer); override;
  end;

  TfpgAndroidApplication = class;
  TfpgAndroidWindow = class;

  { TfpgAndroidWindow - one fpGUI window.

    Main window (Owner is fpgApplication.MainForm):
      * handle = ANativeWindow* of the activity surface
      * size   = logical screen size (the form fills the screen)
    Secondary window (form/dialog/popup):
      * handle = Pointer(Self) - a virtual handle used for event routing
      * a real floating window (Java PopupWindow + SurfaceView) is created
        for it when the Java hooks are available (SubWindowId > 0); its own
        ANativeWindow is stored in SubSurface and the window's buffer is
        presented straight to it. Without the hooks the buffer manager
        falls back to compositing into the main screen buffer. }
  TfpgAndroidWindow = class(TfpgWindowBase)
  private
    FWinHandle: TfpgWinHandle;
    FTitle: string;
    FIsMain: Boolean;
    FPhysicalWidth: Integer;
    FPhysicalHeight: Integer;
    FSubWindowId: Integer;
    FSubSurface: PANativeWindow;
    { True while applying geometry that came from Java (B2 bounds sync):
      backend callbacks must not be sent back to Java (feedback loop). }
    FSyncingFromJava: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property WinHandle: TfpgWinHandle read FWinHandle;
    property IsMain: Boolean read FIsMain;
    { Physical pixel size of the backing surface (main window). }
    property PhysicalWidth: Integer read FPhysicalWidth;
    property PhysicalHeight: Integer read FPhysicalHeight;
    { Floating-window id (0 = none: main window or compositing fallback). }
    property SubWindowId: Integer read FSubWindowId;
    { B2 bounds sync in progress (Java -> Pascal); see ApplyWindowBounds. }
    property SyncingFromJava: Boolean read FSyncingFromJava write FSyncingFromJava;
    { The window's own ANativeWindow (floating windows only). }
    property SubSurface: PANativeWindow read FSubSurface;
    function  HasSubSurface: Boolean;
    { Called by the bridge when the floating window's surface appears/goes. }
    procedure SetSubSurface(aSurface: PANativeWindow);
    { Adopt a (new) surface on the main window, or detach with nil. }
    procedure AttachSurface(aWindow: PANativeWindow);
    { Update the physical size after a surface resize. }
    procedure SetPhysicalSize(AW, AH: Integer);
    { Surface went away: drop the native handle (window object survives). }
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
  public
    procedure   ActivateWindow; override;
    procedure   CaptureMouse(AForWidget: TfpgWidgetBase); override;
    procedure   ReleaseMouse; override;
    procedure   BringToFront; override;
  end;

  { TfpgAndroidApplication - event queues, message loop, screen metrics.

    The queues are filled from the Java UI thread (bridge entry points)
    and drained by the Pascal loop thread. All queue access is protected
    by critical sections. }
  TfpgAndroidApplication = class(TfpgApplicationBase)
  private
    FEventQueue: TList;            { PfpgAndroidTouchEvent }
    FEventQueueLock: TCriticalSection;
    FKeyEventQueue: TList;         { PfpgAndroidKeyEvent }
    FKeyQueueLock: TCriticalSection;
    FResizeQueue: TList;           { PfpgAndroidResizeEvent }
    FResizeQueueLock: TCriticalSection;
    FWindowList: TList;            { TfpgAndroidWindow, z-order (main first) }
    FWindowListLock: TCriticalSection;
    FNextSubWindowId: Integer;     { floating-window id allocator (starts at 0) }
    FLastKeyboardType: Integer;    { -1 = unknown, 0 = hidden, >0 = type }
    FLastKeyboardWindowId: Integer; { window the last IME state was applied to }
    FPhysicalW: Integer;           { last reported surface metrics }
    FPhysicalH: Integer;
    FSurfacePending: Boolean;      { gMainSurface changed, apply on loop }
    FLastModalId: Integer;         { last modal window id pushed to Java }
    function    HasPendingEvents: Boolean;
    function    HasPendingKeyEvents: Boolean;
    function    HasPendingResizeEvents: Boolean;
    procedure   ProcessPendingSurface;
    procedure   ProcessPendingSubWindowState;
    procedure   ProcessQueuedEvents;
    procedure   ProcessQueuedKeyEvents;
    procedure   ProcessQueuedResizeEvents;
    procedure   SyncModalState;
    procedure   UpdateKeyboardVisibility;
    { Freeform window state (see FREEFORM-DESIGN.zh-CN.md). }
    procedure   ApplyWindowBounds(AId, APx, APy, APw, APh: Integer);
    procedure   HandleWindowClosed(AId: Integer);
    procedure   HandleWindowFocused(AId: Integer);
    function    FindWindowByHandle(AHandle: TfpgWinHandle): TfpgWindowBase;
    function    HitTestWindow(AGlobalX, AGlobalY: Integer): TfpgWindowBase;
  public
    constructor Create(const AParams: string); override;
    destructor  Destroy; override;
    { Window registry (z-order: main first, last = top). }
    procedure   RegisterWindow(AWindow: TfpgAndroidWindow);
    procedure   UnregisterWindow(AWindow: TfpgAndroidWindow);
    procedure   BringToFront(AWindow: TfpgAndroidWindow);
    procedure   InvalidateLowerWindows(AWindow: TfpgAndroidWindow);
    function    MainWindow: TfpgAndroidWindow;
    { Z-order position of a window (0 = bottom/main). MaxInt when the
      window is not registered. Used by the screen compositor. }
    function    WindowZIndex(AWindow: TfpgWindowBase): Integer;
    { Floating-window helpers. }
    function    NextSubWindowId: Integer;
    function    FindWindowBySubId(AId: Integer): TfpgAndroidWindow;
    { Event injection (thread-safe; called from the Java UI thread). }
    procedure   EnqueueTouchEvent(AAction, AX, AY, AButton: Integer);
    procedure   EnqueueHoverEvent(AX, AY: Integer);
    procedure   EnqueueWheelEvent(AX, AY, ADelta: Integer);
    { Pointer events from a floating window (local pixel coordinates). }
    procedure   EnqueueSubTouchEvent(AId, AAction, AX, AY, AButton: Integer);
    procedure   EnqueueSubHoverEvent(AId, AX, AY: Integer);
    procedure   EnqueueSubWheelEvent(AId, ADelta: Integer);
    procedure   EnqueueKeyEvent(AKeyCode, AAction, AModifiers: Integer; AUnicodeChar: LongWord);
    procedure   EnqueueTextEvent(const AText: string);
    procedure   EnqueueDeleteEvent(AKind, ACount: Integer);
    procedure   EnqueueResizeEvent(AWidth, AHeight: Integer; ADensity: Double);
    { Freeform window events (thread-safe; Java UI thread). }
    procedure   EnqueueWindowBoundsEvent(AId, AX, AY, AW, AH: Integer);
    procedure   EnqueueWindowStateEvent(AId, AKind: Integer);
    procedure   EnqueueSubKeyEvent(AId, AKeyCode, AAction, AModifiers: Integer; AUnicodeChar: LongWord);
    procedure   EnqueueSubTextEvent(AId: Integer; const AText: string);
    procedure   EnqueueSubDeleteEvent(AId, AKind, ACount: Integer);
    { Apply pending surface changes (main window binding). }
    procedure   ApplyPendingSurface;
    { Soft keyboard / clipboard / activity bridge hooks - installed by
      fpg_android_bridge.pas. }
    procedure   SetMainSurface(aSurface: PANativeWindow);
    procedure   StopApplication;
  protected
    function    DoGetFontFaceList: TStringList; override;
    procedure   DoWaitWindowMessage(atimeoutms: integer); override;
    function    MessagesPending: boolean; override;
    procedure   DoFlush; override;
    function    GetMonitorCount: Integer; override;
    function    GetMonitorInfo(AIndex: Integer): TfpgScreenInfo; override;
  public
    function    GetScreenWidth: TfpgCoord; override;
    function    GetScreenHeight: TfpgCoord; override;
    function    GetScreenPixelColor(APos: TPoint): TfpgColor; override;
    function    Screen_dpi_x: integer; override;
    function    Screen_dpi_y: integer; override;
    function    Screen_dpi: integer; override;
  end;

  { TfpgAndroidClipboard - Java ClipboardManager through the bridge with an
    in-process fallback buffer. }
  TfpgAndroidClipboard = class(TfpgClipboardBase)
  private
    FBuffer: TfpgString;
  protected
    function    DoGetText: TfpgString; override;
    procedure   DoSetText(const AValue: TfpgString); override;
    procedure   InitClipboard; override;
  end;

  { TfpgAndroidFileList - adds the app sandbox directories. }
  TfpgAndroidFileList = class(TfpgFileListBase)
  protected
    procedure   PopulateSpecialDirs(const aDirectory: TfpgString); override;
  public
    function    ReadDirectory(const aDirectory: TfpgString = ''): boolean; override;
  end;

  { TfpgAndroidTimer - the loop's select timeout drives fpgCheckTimers;
    nothing platform specific is needed. }
  TfpgAndroidTimer = class(TfpgBaseTimer)
  end;

  { Drag & drop: not supported in v1 (no system drag events); the classes
    exist so the widget set contract is satisfiable. }
  TfpgAndroidMimeData = class(TfpgMimeDataBase)
  end;

  TfpgAndroidDrag = class(TfpgDragBase)
  public
    function Execute(const ADropActions: TfpgDropActions;
      const ADefaultAction: TfpgDropAction = daCopy): TfpgDropAction; override;
  end;

  TfpgAndroidDrop = class(TfpgDropBase)
  private
    FDropAction: TfpgDropAction;
  protected
    function  GetDropAction: TfpgDropAction; override;
    procedure SetDropAction(AValue: TfpgDropAction); override;
    function  GetWindowForDrop: TfpgWindowBase; override;
  end;

  { No system tray on Android. }
  TfpgAndroidSystemTrayIcon = class(TfpgSystemTrayHandlerBase)
  public
    procedure Show; override;
    procedure Hide; override;
    function  IsSystemTrayAvailable: boolean; override;
    function  SupportsMessages: boolean; override;
  end;

  { Java (Canvas) presentation fallback, installed by fpg_android_bridge.pas.
    Used when the ANativeWindow buffers are not CPU-mappable (seen on
    emulators with host-side GL translation, e.g. LDPlayer "speed" mode):
    the frame's pixels are handed to Java, which draws them with
    SurfaceHolder.lockCanvas/drawBitmap. aPixels is tightly packed
    (stride = aWidth * 4) ARGB/8888 with the same byte order as the
    screen buffer. }
  TAndroidPresentFrameProc = procedure(aPixels: Pointer; aWidth, aHeight: Integer);

  { Floating secondary windows, installed by fpg_android_bridge.pas. All
    coordinates/sizes are DEVICE pixels relative to the main window's content
    origin. ADismissOnOutside: wtPopup (menus/dropdowns) - Java renders these
    as in-app floating windows. ABorderless: wtPopup / waBorderless windows
    must not show the system freeform caption bar. AOwnerId: the secondary
    window (subId) the popup belongs to; 0 = main window. Java creates an
    in-app popup inside the owning window's activity so it stacks above it. }
  TAndroidCreateSubWindowProc = procedure(AId, AX, AY, AW, AH: Integer;
    ADismissOnOutside: Boolean; ABorderless: Boolean; AOwnerId: Integer);
  TAndroidMoveSubWindowProc = procedure(AId, AX, AY, AW, AH: Integer);
  TAndroidShowSubWindowProc = procedure(AId: Integer; AVisible: Boolean);
  TAndroidDestroySubWindowProc = procedure(AId: Integer);
  { Present a tightly packed frame into one floating window's own surface. }
  TAndroidPresentSubFrameProc = procedure(AId: Integer; APixels: Pointer;
    AWidth, AHeight: Integer);

  { Fired just before a native window object is freed / released. Installed
    by fpg_android_buffer_manager.pas so buffer managers stop referencing a
    window that is about to become invalid (a dangling FWindow in
    gSubManagers crashes the next RecompositeSubWindows pass). }
  TAndroidWindowDestroyingProc = procedure(AWindow: TfpgWindowBase);

  { Main-window decoration (waBorderless / waFullScreen) + window title;
    installed by the bridge. Java removes the system title bar for
    waBorderless / waFullScreen, hides the status bar for waFullScreen and
    keeps the title bar otherwise (re-opening the window once with the
    normal theme). }
  TAndroidSetMainDecorationProc = procedure(ABorderless, AFullScreen: Boolean;
    const ATitle: string);

var
  { Java-facing callbacks, installed by fpg_android_bridge.pas. }
  AndroidShowKeyboardProc: procedure(AWindowId: Integer; AVisible: Boolean;
    AKbType: Integer) = nil;
  AndroidClipboardGetProc: function: string = nil;
  AndroidClipboardSetProc: procedure(const AText: string) = nil;
  AndroidFinishProc: procedure = nil;

  { Screen surface hooks, installed by fpg_android_buffer_manager.pas
    (keeps the dependency direction: buffer manager -> application). }
  AndroidScreenAttachHook: procedure(aSurface: PANativeWindow) = nil;
  AndroidScreenDetachHook: procedure = nil;

  AndroidPresentFrameProc: TAndroidPresentFrameProc = nil;
  AndroidCreateSubWindowProc: TAndroidCreateSubWindowProc = nil;
  AndroidMoveSubWindowProc: TAndroidMoveSubWindowProc = nil;
  AndroidShowSubWindowProc: TAndroidShowSubWindowProc = nil;
  AndroidDestroySubWindowProc: TAndroidDestroySubWindowProc = nil;
  AndroidPresentSubFrameProc: TAndroidPresentSubFrameProc = nil;
  AndroidWindowDestroyingProc: TAndroidWindowDestroyingProc = nil;
  AndroidSetMainDecorationProc: TAndroidSetMainDecorationProc = nil;
  { Current modal secondary window id (0 = no modal). Java disables input on
    every other window while a modal is active, so system caption buttons
    cannot be used either. Installed by the bridge. }
  AndroidSetModalWindowProc: procedure(AId: Integer) = nil;

  { Screen metrics (logical size, physical size, density). Written on the
    Pascal loop thread by ApplyPendingSurface / resize processing. }
  gAndroidScreenW: Integer = 1280;
  gAndroidScreenH: Integer = 720;
  { Last surface metrics reported by Java (device pixels). Kept globally so
    the application object can queue an initial resize even when the metrics
    arrived before the Pascal application existed. }
  gAndroidPhysW: Integer = 0;
  gAndroidPhysH: Integer = 0;
  gAndroidDensity: Double = 1.0;
  { Device pixels per logical pixel for the hybrid canvas/fonts. }
  gHiDPIScaleFactor: Double = 1.0;
  { Logical DPI used by fpGUI layout (constant; scaling is explicit). }
  gHiDPI: Integer = 96;
  gAndroidScreenValid: Boolean = False;

  { Application sandbox paths reported by nativeInit. }
  gAndroidFilesDir: string = '';
  gAndroidCacheDir: string = '';
  gAndroidExternalFilesDir: string = '';

  { True once the Pascal application object exists (loop thread). }
  gAndroidAppReady: Boolean = False;

  { Device reports the freeform window-management feature (diagnostics). }
  gSupportsFreeform: Boolean = False;

  { Presentation mode. Default: hand every frame to Java and draw it with
    SurfaceHolder.lockCanvas/drawBitmap - the only path that is safe on
    every device AND on emulators whose surface buffers are not reachable
    by the CPU (host-side GL translation, e.g. LDPlayer speed mode).
    The native ANativeWindow_lock path (faster, one less copy) is selected
    with the manifest meta-data com.fpgui.presenter="native". }
  gAndroidUseJavaPresenter: Boolean = True;

type
  TAndroidMainProc = procedure;

var
  { Assigned by the application's .lpr before the surface is created. }
  AndroidAppMain: TAndroidMainProc = nil;

function  AndroidApplication: TfpgAndroidApplication;
procedure AndroidLogStr(const AMsg: string);

{ ---- Entry points used by fpg_android_bridge.pas (Java UI thread) ---- }
procedure AndroidSetAppMain(AProc: TAndroidMainProc);
function  AndroidStartApp: Boolean;
procedure AndroidSetMainSurface(aToken: Integer; aSurface: PANativeWindow);
procedure AndroidDetachMainSurface(aToken: Integer);
function  AndroidIsCurrentMainToken(aToken: Integer): Boolean;
procedure AndroidBeginMainReattach;
procedure AndroidSetScreenMetrics(aToken: Integer; AWidthPx, AHeightPx: Integer; ADensity: Double);
procedure AndroidSetSandboxPaths(const AFiles, ACache, AExternal: string);
procedure AndroidEnqueueTouch(AAction: Integer; AX, AY: Single; AButton: Integer);
procedure AndroidEnqueueHover(AX, AY: Single);
procedure AndroidEnqueueWheel(ADelta: Integer);
procedure AndroidEnqueueKey(AKeyCode, AAction, AModifiers: Integer; AUnicodeChar: LongWord);
{ Floating-window events (Java thread). Surface changes are queued for the
  loop thread; aSurface ownership is taken by the queue. }
procedure AndroidAttachSubSurface(AId: Integer; aSurface: PANativeWindow);
procedure AndroidSubWindowDismissed(AId: Integer);
procedure AndroidEnqueueSubTouch(AId, AAction: Integer; AX, AY: Single; AButton: Integer);
procedure AndroidEnqueueSubHover(AId: Integer; AX, AY: Single);
procedure AndroidEnqueueSubWheel(AId, ADelta: Integer);
procedure AndroidEnqueueText(const AText: string);
procedure AndroidEnqueueDelete(ABefore, AAfter: Integer);
{ Freeform secondary-window events (see FREEFORM-DESIGN.zh-CN.md). }
procedure AndroidEnqueueWindowBounds(AId, AX, AY, AW, AH: Integer);
procedure AndroidEnqueueWindowClosed(AId: Integer);
procedure AndroidEnqueueWindowFocused(AId: Integer);
procedure AndroidEnqueueWindowRepaint(AId: Integer);
procedure AndroidEnqueueSubKey(AId, AKeyCode, AAction, AModifiers: Integer; AUnicodeChar: LongWord);
procedure AndroidEnqueueSubText(AId: Integer; const AText: string);
procedure AndroidEnqueueSubDelete(AId, ABefore, AAfter: Integer);
function  AndroidHandleBack: Boolean;
procedure AndroidRequestStop;

function  AndroidKeyToFpgKey(AKeyCode: Integer): Word;
function  AndroidIsStarted: Boolean;

implementation

uses
  baseunix,
  unix,
  fpg_main,
  fpg_utils,
  fpg_widget,
  fpg_form,
  fpg_popupwindow,
  fpg_fontcache;

type
  { Touch/mouse/wheel/hover event injected from Java. X/Y are PHYSICAL
    pixels; the loop converts to logical with gHiDPIScaleFactor.
    MouseButton: 0 = plain touch (mapped to the left button), 1 = left,
    2 = right, 3 = middle. }
  PfpgAndroidTouchEvent = ^TfpgAndroidTouchEvent;
  TfpgAndroidTouchEvent = record
    X, Y: Integer;
    Action: Integer;        { AMOTION_EVENT_ACTION_* }
    MouseButton: Integer;   { 0 touch, 1 left, 2 right, 3 middle }
    Kind: Integer;          { 0 touch/mouse, 1 wheel, 2 hover,
                              3 bounds, 4 closed, 5 focused }
    WheelDelta: Integer;
    SubWindowId: Integer;   { 0 = main window; >0 = floating window id }
    W, H: Integer;          { Kind=3: physical content width/height }
  end;

  { Pending floating-window surface attach/detach (Java thread -> loop). }
  PSubSurfaceChange = ^TSubSurfaceChange;
  TSubSurfaceChange = record
    Id: Integer;
    Surface: PANativeWindow;   { nil = detached }
  end;

  PfpgAndroidKeyEvent = ^TfpgAndroidKeyEvent;
  TfpgAndroidKeyEvent = record
    Kind: Integer;          { ANDROID_EV_* }
    KeyCode: Integer;
    Action: Integer;        { 0 down, 1 up }
    Modifiers: Integer;
    UnicodeChar: LongWord;
    Count: Integer;
    Text: string;
    WindowId: Integer;      { 0 = main window; >0 = freeform window id }
  end;

  PfpgAndroidResizeEvent = ^TfpgAndroidResizeEvent;
  TfpgAndroidResizeEvent = record
    Width: Integer;         { physical px }
    Height: Integer;
    Density: Double;        { 0 = unchanged }
  end;

var
  { Pointer state machine across queued events (loop thread only). }
  gLastDownButton: Integer = 0;
  gLastDownTargetWin: TfpgWinHandle = nil;
  gLastDownGlobX: Integer = 0;
  gLastDownGlobY: Integer = 0;
  gFocusedWinHandle: TfpgWinHandle = nil;

  { Main surface hand-off (Java thread writes, loop thread consumes).
    gMainSurface holds a reference owned by the backend. Replaced/detached
    surfaces go to the retired list and are released on the LOOP thread
    (ProcessPendingSurface) so the rendering code can never touch a surface
    the Java thread just released. }
  gMainSurfaceLock: TCriticalSection = nil;
  gMainSurface: PANativeWindow = nil;
  gMainSurfaceChanged: Boolean = False;
  { Instance token of the main-window Activity that owns gMainSurface.
    Superseded instances (borderless re-attach) must not detach the surface
    or stop the application. While a re-attach is pending, detach/stop events
    of the OLD instance are ignored until the new surface arrives. }
  gMainSurfaceToken: Integer = 0;
  gMainReattachPending: Boolean = False;
  gMainSurfaceHooked: Boolean = False;   { hook state actually applied (loop thread) }
  gRetiredSurfaces: TList = nil;         { PANativeWindow, owned by backend }
  { Floating windows: pending surface attach/detach and outside-dismiss
    notifications (Java thread -> loop thread). }
  gSubStateLock: TCriticalSection = nil;
  gSubSurfQueue: TList = nil;            { PSubSurfaceChange }
  gDismissedSubWindows: TList = nil;     { Integer ids }

  { App startup hand-off. gAppThreadFinished lets a re-created activity
    (onDestroy -> new onCreate in the same process) restart the app. }
  gAppStartLock: TCriticalSection = nil;
  gAppStarted: Boolean = False;
  gAppThreadFinished: Boolean = True;
  gAppThread: TThread = nil;

const
  RTLD_LAZY = 1;

function setenv(const name, value: PChar; overwrite: LongInt): LongInt; cdecl;
  external 'c';

{ Forward declarations (used by the event processing code below). }
function Utf8CharLen(b: Byte): Integer; forward;
function UnicodeCodepointToUTF8(cp: UInt32): string; forward;

function AndroidApplication: TfpgAndroidApplication;
begin
  { IMPORTANT: never touch the fpgApplication getter before the Pascal
    worker thread created the application object — the getter lazily
    creates it on the CALLING thread, and Java-thread calls must not
    create the app object. }
  Result := nil;
  if not gAndroidAppReady then
    Exit;
  if fpgApplication is TfpgAndroidApplication then
    Result := TfpgAndroidApplication(fpgApplication);
end;

procedure AndroidLogStr(const AMsg: string);
begin
  AndroidLog(ANDROID_LOG_INFO, AMsg);
end;

{ ---------------------------------------------------------------------
  TfpgAndroidWakeChannel
  --------------------------------------------------------------------- }

constructor TfpgAndroidWakeChannel.Create;
begin
  inherited Create;
  FPipeFds[0] := -1;
  FPipeFds[1] := -1;
  FIsOpen := False;
end;

destructor TfpgAndroidWakeChannel.Destroy;
begin
  if FIsOpen then
    Close;
  inherited Destroy;
end;

procedure TfpgAndroidWakeChannel.Open;
var
  flags: cint;
begin
  if FIsOpen then
    Exit;
  if fpPipe(FPipeFds) <> 0 then
  begin
    FPipeFds[0] := -1;
    FPipeFds[1] := -1;
    Exit;   { Signal/Drain/GetPollFd all check FIsOpen }
  end;
  flags := FpFcntl(FPipeFds[0], F_GETFL);
  FpFcntl(FPipeFds[0], F_SETFL, flags or O_NONBLOCK);
  flags := FpFcntl(FPipeFds[1], F_GETFL);
  FpFcntl(FPipeFds[1], F_SETFL, flags or O_NONBLOCK);
  FIsOpen := True;
end;

procedure TfpgAndroidWakeChannel.Close;
begin
  if not FIsOpen then
    Exit;
  FpClose(FPipeFds[0]);
  FpClose(FPipeFds[1]);
  FPipeFds[0] := -1;
  FPipeFds[1] := -1;
  FIsOpen := False;
end;

procedure TfpgAndroidWakeChannel.Signal;
var
  buf: Byte;
begin
  if not FIsOpen then
    Exit;
  buf := 1;
  fpwrite(FPipeFds[1], buf, 1);
end;

procedure TfpgAndroidWakeChannel.Drain;
var
  buf: array[0..63] of Byte;
begin
  if not FIsOpen then
    Exit;
  while FpRead(FPipeFds[0], buf, SizeOf(buf)) > 0 do ;
end;

function TfpgAndroidWakeChannel.GetPollFd: Integer;
begin
  Result := FPipeFds[0];
end;

{ ---------------------------------------------------------------------
  TfpgAndroidImage
  --------------------------------------------------------------------- }

procedure TfpgAndroidImage.DoFreeImage;
begin
  { memory only - nothing to release }
end;

procedure TfpgAndroidImage.DoInitImage(acolordepth, awidth, aheight: integer;
  aimgdata: Pointer);
begin
  { memory only - the base class already allocated FImageData }
  if (acolordepth = 0) or (awidth = 0) or (aheight = 0) or (aimgdata = nil) then ;
end;

procedure TfpgAndroidImage.DoInitImageMask(awidth, aheight: integer;
  aimgdata: Pointer);
begin
  if (awidth = 0) or (aheight = 0) or (aimgdata = nil) then ;
end;

{ ---------------------------------------------------------------------
  TfpgAndroidWindow
  --------------------------------------------------------------------- }

constructor TfpgAndroidWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FWinHandle := nil;
  FTitle := '';
  FIsMain := False;
  FPhysicalWidth := 0;
  FPhysicalHeight := 0;
  FSyncingFromJava := False;
end;

destructor TfpgAndroidWindow.Destroy;
var
  app: TfpgAndroidApplication;
begin
  { fpGUI's TfpgWidget.HandleHide frees the window object directly (it does
    not go through ReleaseWindowHandle), so the window must unregister
    itself here - otherwise the application's window list keeps a dangling
    pointer (seen as duplicate "main" entries after a hide/show cycle). }
  app := AndroidApplication;
  if app <> nil then
  begin
    if FSubWindowId = 0 then
      app.InvalidateLowerWindows(Self);
    app.UnregisterWindow(Self);
  end;
  if Assigned(AndroidWindowDestroyingProc) then
    AndroidWindowDestroyingProc(Self);
  if (FSubWindowId > 0) and Assigned(AndroidDestroySubWindowProc) then
    AndroidDestroySubWindowProc(FSubWindowId);
  FSubWindowId := 0;
  if FSubSurface <> nil then
  begin
    ANativeWindow_release(FSubSurface);
    FSubSurface := nil;
  end;
  inherited Destroy;
end;

function TfpgAndroidWindow.HandleIsValid: boolean;
begin
  Result := FWinHandle <> nil;
end;

procedure TfpgAndroidWindow.AttachSurface(aWindow: PANativeWindow);
begin
  if FWinHandle = TfpgWinHandle(aWindow) then
    Exit;
  FWinHandle := TfpgWinHandle(aWindow);
  if aWindow <> nil then
  begin
    FPhysicalWidth := ANativeWindow_getWidth(aWindow);
    FPhysicalHeight := ANativeWindow_getHeight(aWindow);
  end
  else
  begin
    FPhysicalWidth := 0;
    FPhysicalHeight := 0;
  end;
  AndroidLog(ANDROID_LOG_INFO, Format('Window.AttachSurface: %s phys=%dx%d',
    [ClassName, FPhysicalWidth, FPhysicalHeight]));
  if Owner is TfpgWidget then
    TfpgWidget(Owner).Invalidate;
end;

function TfpgAndroidWindow.HasSubSurface: Boolean;
begin
  Result := FSubSurface <> nil;
end;

procedure TfpgAndroidWindow.SetSubSurface(aSurface: PANativeWindow);
var
  old: PANativeWindow;
begin
  if FSubSurface = aSurface then
    Exit;
  { Called on the loop thread (ProcessPendingSubWindowState). }
  if aSurface <> nil then
    ANativeWindow_acquire(aSurface);
  old := FSubSurface;
  FSubSurface := aSurface;
  if old <> nil then
    ANativeWindow_release(old);
  if Owner is TfpgWidget then
    TfpgWidget(Owner).Invalidate;
end;

procedure TfpgAndroidWindow.SetPhysicalSize(AW, AH: Integer);
begin
  FPhysicalWidth := AW;
  FPhysicalHeight := AH;
  if gHiDPIScaleFactor >= 1.0 then
  begin
    FSize.W := Round(AW / gHiDPIScaleFactor);
    FSize.H := Round(AH / gHiDPIScaleFactor);
  end
  else
  begin
    FSize.W := AW;
    FSize.H := AH;
  end;
end;

procedure TfpgAndroidWindow.InvalidateNativeHandle;
begin
  FWinHandle := nil;
  FPhysicalWidth := 0;
  FPhysicalHeight := 0;
end;

procedure TfpgAndroidWindow.DoAllocateWindowHandle(AParent: TfpgWidgetBase);
var
  app: TfpgAndroidApplication;
  physW, physH: Integer;
  ownerId: Integer;
  ow: TfpgWindowBase;
begin
  app := AndroidApplication;
  FIsMain := (Owner = fpgApplication.MainForm) or (fpgApplication.MainForm = nil);

  if FIsMain then
  begin
    { Main window owns the activity surface. }
    gMainSurfaceLock.Enter;
    try
      FWinHandle := TfpgWinHandle(gMainSurface);
    finally
      gMainSurfaceLock.Leave;
    end;
    if FWinHandle <> nil then
    begin
      FPhysicalWidth := ANativeWindow_getWidth(PANativeWindow(FWinHandle));
      FPhysicalHeight := ANativeWindow_getHeight(PANativeWindow(FWinHandle));
    end;
    FPosition.X := 0;
    FPosition.Y := 0;
    if (FPhysicalWidth > 0) and (FPhysicalHeight > 0) then
      SetPhysicalSize(FPhysicalWidth, FPhysicalHeight)
    else
    begin
      FSize.W := gAndroidScreenW;
      FSize.H := gAndroidScreenH;
    end;
    AndroidLog(ANDROID_LOG_INFO, Format('AllocateWindowHandle MAIN: handle=%p size=%dx%d logical',
      [Pointer(FWinHandle), FSize.W, FSize.H]));
    { Main-window decoration: waBorderless -> no title bar; waFullScreen ->
      no title bar + no status bar; otherwise keep the system title bar.
      SetWindowParameters pushes the form's WindowTitle into FTitle first. }
    if Assigned(AndroidSetMainDecorationProc) then
    begin
      SetWindowParameters;
      AndroidSetMainDecorationProc(waBorderless in FWindowAttributes,
        waFullScreen in FWindowAttributes, FTitle);
    end;
  end
  else
  begin
    { Secondary window: virtual handle for routing, clamped to the logical
      screen. When the Java hooks are installed, also create a real floating
      window (PopupWindow + SurfaceView) for it. }
    FWinHandle := TfpgWinHandle(Self);
    if FPosition.X + FSize.W > gAndroidScreenW then
      FPosition.X := gAndroidScreenW - FSize.W;
    if FPosition.Y + FSize.H > gAndroidScreenH then
      FPosition.Y := gAndroidScreenH - FSize.H;
    if FPosition.X < 0 then
      FPosition.X := 0;
    if FPosition.Y < 0 then
      FPosition.Y := 0;
    if (app <> nil) and Assigned(AndroidCreateSubWindowProc) then
    begin
      FSubWindowId := app.NextSubWindowId;
      { Owner window of a popup: the reference widget set by ShowAt. Java
        creates the in-app popup inside that window's activity so it stacks
        above it (0 = main window). }
      ownerId := 0;
      if (FWindowType = wtPopup) and (Owner is TfpgPopupWindow) and
         (TfpgPopupWindow(Owner).PopupWidget <> nil) then
      begin
        ow := TfpgPopupWindow(Owner).PopupWidget.Window;
        if (ow <> nil) and (ow is TfpgAndroidWindow) then
          ownerId := TfpgAndroidWindow(ow).SubWindowId;
      end;
      { wtPopup (menus/dropdowns/hints) and waBorderless windows must not
        show the system freeform caption bar. }
      AndroidCreateSubWindowProc(FSubWindowId,
        Round(FPosition.X * gHiDPIScaleFactor),
        Round(FPosition.Y * gHiDPIScaleFactor),
        Round(FSize.W * gHiDPIScaleFactor),
        Round(FSize.H * gHiDPIScaleFactor),
        FWindowType = wtPopup,   { menus: in-app floating window }
        (FWindowType = wtPopup) or (waBorderless in FWindowAttributes),
        ownerId);
    end;
    AndroidLog(ANDROID_LOG_INFO, Format('AllocateWindowHandle sub: type=%d owner=%s pos=%d,%d size=%dx%d subId=%d',
      [Ord(FWindowType), Owner.ClassName, FPosition.X, FPosition.Y, FSize.W, FSize.H,
       FSubWindowId]));
  end;

  if (FWinHandle <> nil) and (app <> nil) then
    app.RegisterWindow(Self);

  if Owner is TfpgWidget then
    TfpgWidget(Owner).Invalidate;
end;

procedure TfpgAndroidWindow.DoReleaseWindowHandle;
var
  app: TfpgAndroidApplication;
begin
  app := AndroidApplication;
  if app <> nil then
  begin
    { Compositing fallback: repaint whatever was below this window before
      it disappears. Floating windows own their surface. }
    if FSubWindowId = 0 then
      app.InvalidateLowerWindows(Self);
    app.UnregisterWindow(Self);
  end;
  if Assigned(AndroidWindowDestroyingProc) then
    AndroidWindowDestroyingProc(Self);
  if (FSubWindowId > 0) and Assigned(AndroidDestroySubWindowProc) then
    AndroidDestroySubWindowProc(FSubWindowId);
  FSubWindowId := 0;
  FWinHandle := nil;
end;

procedure TfpgAndroidWindow.DoRemoveWindowLookup;
var
  app: TfpgAndroidApplication;
begin
  app := AndroidApplication;
  if app <> nil then
    app.UnregisterWindow(Self);
end;

procedure TfpgAndroidWindow.DoUpdateWindowPosition;
var
  app: TfpgAndroidApplication;
begin
  { No native window to move; positions are virtual. For secondary windows
    the pixels live in the shared screen buffer, so a position/size change
    must repaint: the window at its new rect and everything below it (to
    erase the old pixels). The main window's repaint covers the screen. }
  FNotifiedPosition := FPosition;
  if FSyncingFromJava then
    Exit;
  if not FIsMain then
  begin
    { Floating window: move/resize the real window. }
    if (FSubWindowId > 0) and Assigned(AndroidMoveSubWindowProc) then
      AndroidMoveSubWindowProc(FSubWindowId,
        Round(FPosition.X * gHiDPIScaleFactor),
        Round(FPosition.Y * gHiDPIScaleFactor),
        Round(FSize.W * gHiDPIScaleFactor),
        Round(FSize.H * gHiDPIScaleFactor));
    if (FSubWindowId = 0) and (AndroidApplication <> nil) then
    begin
      { Compositing fallback: the pixels live in the shared screen buffer,
        so a position change must repaint this window and everything below. }
      app := AndroidApplication;
      app.InvalidateLowerWindows(Self);
    end;
    if Owner is TfpgWidget then
      TfpgWidget(Owner).Invalidate;
  end;
end;

procedure TfpgAndroidWindow.DoSetWindowAttributes(const AOldAtributes, ANewAttributes: TWindowAttributes; const AForceAll: Boolean);
begin
  if AForceAll then ;
  if AOldAtributes = ANewAttributes then ;
  { No native attributes on Android; decoration is self-drawn by fpGUI. }
end;

procedure TfpgAndroidWindow.DoSetWindowVisible(const AValue: Boolean);
var
  app: TfpgAndroidApplication;
begin
  app := AndroidApplication;
  if FSyncingFromJava then
    Exit;
  { Floating window: show/hide the real PopupWindow (hiding destroys its
    surface; showing re-creates it and the surface callback re-attaches). }
  if (FSubWindowId > 0) and Assigned(AndroidShowSubWindowProc) then
    AndroidShowSubWindowProc(FSubWindowId, AValue);
  if AValue then
  begin
    if (app <> nil) and not FIsMain then
      app.BringToFront(Self);
    if Owner is TfpgWidget then
      TfpgWidget(Owner).Invalidate;
  end
  else
  begin
    { Compositing fallback: erase this window's pixels by repainting the
      windows below it. Floating windows just disappear with their surface. }
    if (FSubWindowId = 0) and (app <> nil) then
      app.InvalidateLowerWindows(Self);
  end;
end;

procedure TfpgAndroidWindow.DoMoveWindow(const x: TfpgCoord; const y: TfpgCoord);
var
  app: TfpgAndroidApplication;
begin
  FPosition.X := x;
  FPosition.Y := y;
  if FSyncingFromJava then
    Exit;
  if not FIsMain then
  begin
    if (FSubWindowId > 0) and Assigned(AndroidMoveSubWindowProc) then
      AndroidMoveSubWindowProc(FSubWindowId,
        Round(FPosition.X * gHiDPIScaleFactor),
        Round(FPosition.Y * gHiDPIScaleFactor),
        Round(FSize.W * gHiDPIScaleFactor),
        Round(FSize.H * gHiDPIScaleFactor));
    if (FSubWindowId = 0) and (AndroidApplication <> nil) then
    begin
      app := AndroidApplication;
      app.InvalidateLowerWindows(Self);
    end;
    if Owner is TfpgWidget then
      TfpgWidget(Owner).Invalidate;
  end;
end;

function TfpgAndroidWindow.DoWindowToScreen(ASource: TfpgWindowBase; const AScreenPos: TPoint): TPoint;
begin
  { Virtual screen: window positions ARE screen positions. }
  Result.X := AScreenPos.X + ASource.Left;
  Result.Y := AScreenPos.Y + ASource.Top;
end;

procedure TfpgAndroidWindow.DoSetWindowTitle(const ATitle: string);
begin
  FTitle := ATitle;
end;

procedure TfpgAndroidWindow.DoSetMouseCursor;
begin
  { Touch devices have no pointer cursor. }
end;

procedure TfpgAndroidWindow.DoDNDEnabled(const AValue: boolean);
begin
  if AValue then ;
  { v1: no system drag & drop. }
end;

procedure TfpgAndroidWindow.ActivateWindow;
begin
  if FIsMain then
    gFocusedWinHandle := FWinHandle
  else
    gFocusedWinHandle := FWinHandle;
end;

procedure TfpgAndroidWindow.CaptureMouse(AForWidget: TfpgWidgetBase);
begin
  MouseCapture := AForWidget;
end;

procedure TfpgAndroidWindow.ReleaseMouse;
begin
  MouseCapture := nil;
end;

procedure TfpgAndroidWindow.BringToFront;
var
  app: TfpgAndroidApplication;
begin
  app := AndroidApplication;
  if (app <> nil) and not FIsMain then
    app.BringToFront(Self);
end;

{ ---------------------------------------------------------------------
  TfpgAndroidApplication
  --------------------------------------------------------------------- }

constructor TfpgAndroidApplication.Create(const AParams: string);
var
  p: PChar;
begin
  inherited Create(AParams);
  FEventQueue := TList.Create;
  FEventQueueLock := TCriticalSection.Create;
  FKeyEventQueue := TList.Create;
  FKeyQueueLock := TCriticalSection.Create;
  FResizeQueue := TList.Create;
  FResizeQueueLock := TCriticalSection.Create;
  FWindowList := TList.Create;
  FWindowListLock := TCriticalSection.Create;
  FNextSubWindowId := 0;
  FLastKeyboardType := -1;
  FLastKeyboardWindowId := 0;
  FPhysicalW := 0;
  FPhysicalH := 0;
  FSurfacePending := False;
  FLastModalId := 0;

  WakeChannel := TfpgAndroidWakeChannel.Create;
  WakeChannel.Open;
  Classes.WakeMainThread := nil;

  FSelection := TfpgAndroidClipboard.Create;

  { HOME is redirected to the app files dir so FPC path helpers and
    relative file access work inside the sandbox. }
  if gAndroidFilesDir <> '' then
  begin
    p := PChar(gAndroidFilesDir);
    setenv('HOME', p, 1);
    fpgSetCurrentDir(gAndroidFilesDir);
  end;

  { fpgApplication.Initialize checks this flag; the backend owns the
    platform initialisation so it reports the app as initialized. }
  FIsInitialized := True;
  gAndroidAppReady := True;
  AndroidLog(ANDROID_LOG_INFO, 'TfpgAndroidApplication created; screen=' +
    IntToStr(gAndroidScreenW) + 'x' + IntToStr(gAndroidScreenH) +
    ' density=' + FloatToStr(gAndroidDensity));

  { The Java shell usually reports the surface metrics before this object
    exists (those resize events were dropped). Queue one now so the main form
    is resized to the window as soon as the loop runs - otherwise the form
    keeps its design-time size (and its anchored widgets stay put). }
  if gAndroidScreenValid and (gAndroidPhysW > 0) and (gAndroidPhysH > 0) then
    EnqueueResizeEvent(gAndroidPhysW, gAndroidPhysH, gAndroidDensity);
end;

destructor TfpgAndroidApplication.Destroy;
var
  i: Integer;
begin
  gAndroidAppReady := False;
  if WakeChannel <> nil then
  begin
    WakeChannel.Close;
    WakeChannel := nil;
  end;

  if FEventQueue <> nil then
  begin
    for i := 0 to FEventQueue.Count - 1 do
      Dispose(PfpgAndroidTouchEvent(FEventQueue[i]));
    FEventQueue.Free;
  end;
  if FKeyEventQueue <> nil then
  begin
    for i := 0 to FKeyEventQueue.Count - 1 do
      Dispose(PfpgAndroidKeyEvent(FKeyEventQueue[i]));
    FKeyEventQueue.Free;
  end;
  if FResizeQueue <> nil then
  begin
    for i := 0 to FResizeQueue.Count - 1 do
      Dispose(PfpgAndroidResizeEvent(FResizeQueue[i]));
    FResizeQueue.Free;
  end;
  FWindowList.Free;
  FEventQueueLock.Free;
  FKeyQueueLock.Free;
  FResizeQueueLock.Free;
  FWindowListLock.Free;
  inherited Destroy;
end;

procedure TfpgAndroidApplication.RegisterWindow(AWindow: TfpgAndroidWindow);
var
  i: Integer;
begin
  FWindowListLock.Enter;
  try
    { The framework can recreate a form's native window object (a hide/show
      cycle overwrites the form's FWindow without freeing the old object).
      Drop any earlier window of the same owner so stale objects never stay
      in the hit-test/routing list. }
    for i := FWindowList.Count - 1 downto 0 do
      if (TfpgAndroidWindow(FWindowList[i]) <> AWindow) and
         (TfpgAndroidWindow(FWindowList[i]).Owner = AWindow.Owner) then
        FWindowList.Delete(i);
    if FWindowList.IndexOf(AWindow) < 0 then
    begin
      if AWindow.IsMain then
        FWindowList.Insert(0, AWindow)   { main window always at the bottom }
      else
        FWindowList.Add(AWindow);
    end;
  finally
    FWindowListLock.Leave;
  end;
end;

procedure TfpgAndroidApplication.UnregisterWindow(AWindow: TfpgAndroidWindow);
begin
  FWindowListLock.Enter;
  try
    FWindowList.Remove(AWindow);
  finally
    FWindowListLock.Leave;
  end;
end;

procedure TfpgAndroidApplication.BringToFront(AWindow: TfpgAndroidWindow);
begin
  if AWindow.IsMain then
    Exit;
  FWindowListLock.Enter;
  try
    FWindowList.Remove(AWindow);
    FWindowList.Add(AWindow);
  finally
    FWindowListLock.Leave;
  end;
end;

procedure TfpgAndroidApplication.InvalidateLowerWindows(AWindow: TfpgAndroidWindow);
var
  i, idx: Integer;
  w: TfpgAndroidWindow;
begin
  FWindowListLock.Enter;
  try
    idx := FWindowList.IndexOf(AWindow);
    if idx < 0 then
      Exit;
    { Everything below the disappearing window must repaint. }
    for i := idx - 1 downto 0 do
    begin
      w := TfpgAndroidWindow(FWindowList[i]);
      if (w <> nil) and (w.PrimaryWidget is TfpgWidget) and
         TfpgWidget(w.PrimaryWidget).Visible then
        TfpgWidget(w.PrimaryWidget).Invalidate;
    end;
  finally
    FWindowListLock.Leave;
  end;
end;

function TfpgAndroidApplication.MainWindow: TfpgAndroidWindow;
begin
  Result := nil;
  FWindowListLock.Enter;
  try
    if (FWindowList.Count > 0) and TfpgAndroidWindow(FWindowList[0]).IsMain then
      Result := TfpgAndroidWindow(FWindowList[0]);
  finally
    FWindowListLock.Leave;
  end;
end;

function TfpgAndroidApplication.NextSubWindowId: Integer;
begin
  Inc(FNextSubWindowId);
  if FNextSubWindowId < 1 then
    FNextSubWindowId := 1;
  Result := FNextSubWindowId;
end;

function TfpgAndroidApplication.FindWindowBySubId(AId: Integer): TfpgAndroidWindow;
var
  i: Integer;
  w: TfpgAndroidWindow;
begin
  Result := nil;
  if AId <= 0 then
    Exit;
  FWindowListLock.Enter;
  try
    for i := 0 to FWindowList.Count - 1 do
    begin
      w := TfpgAndroidWindow(FWindowList[i]);
      if (w <> nil) and (w.SubWindowId = AId) then
        Exit(w);
    end;
  finally
    FWindowListLock.Leave;
  end;
end;

function TfpgAndroidApplication.WindowZIndex(AWindow: TfpgWindowBase): Integer;
begin
  Result := MaxInt;
  if AWindow = nil then
    Exit;
  FWindowListLock.Enter;
  try
    Result := FWindowList.IndexOf(AWindow);
  finally
    FWindowListLock.Leave;
  end;
  if Result < 0 then
    Result := MaxInt;
end;

function TfpgAndroidApplication.FindWindowByHandle(AHandle: TfpgWinHandle): TfpgWindowBase;
var
  i: Integer;
  w: TfpgAndroidWindow;
begin
  Result := nil;
  if AHandle = nil then
    Exit;
  FWindowListLock.Enter;
  try
    for i := 0 to FWindowList.Count - 1 do
    begin
      w := TfpgAndroidWindow(FWindowList[i]);
      if (w <> nil) and (w.WinHandle = AHandle) then
        Exit(w);
    end;
  finally
    FWindowListLock.Leave;
  end;
end;

function TfpgAndroidApplication.HitTestWindow(AGlobalX, AGlobalY: Integer): TfpgWindowBase;
var
  i: Integer;
  w: TfpgAndroidWindow;
begin
  Result := nil;
  FWindowListLock.Enter;
  try
    { Top-most first. }
    for i := FWindowList.Count - 1 downto 0 do
    begin
      w := TfpgAndroidWindow(FWindowList[i]);
      if (w = nil) or not (w.PrimaryWidget is TfpgWidget) or
         not TfpgWidget(w.PrimaryWidget).Visible then
        Continue;
      if (AGlobalX >= w.Left) and (AGlobalX < w.Left + w.Width) and
         (AGlobalY >= w.Top) and (AGlobalY < w.Top + w.Height) then
        Exit(w);
    end;
  finally
    FWindowListLock.Leave;
  end;
end;

procedure TfpgAndroidApplication.SetMainSurface(aSurface: PANativeWindow);
begin
  gMainSurfaceLock.Enter;
  try
    gMainSurface := aSurface;
    gMainSurfaceChanged := True;
  finally
    gMainSurfaceLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgAndroidApplication.ProcessPendingSurface;
var
  surf: PANativeWindow;
  changed: Boolean;
  w: TfpgAndroidWindow;
begin
  changed := False;
  surf := nil;
  gMainSurfaceLock.Enter;
  try
    if gMainSurfaceChanged then
    begin
      changed := True;
      surf := gMainSurface;
      gMainSurfaceChanged := False;
    end;
  finally
    gMainSurfaceLock.Leave;
  end;
  if not changed then
    Exit;

  { Notify the buffer manager (screen buffer + present target). }
  if surf <> nil then
  begin
    if Assigned(AndroidScreenAttachHook) then
      AndroidScreenAttachHook(surf);
    gMainSurfaceHooked := True;
  end
  else
  begin
    if gMainSurfaceHooked and Assigned(AndroidScreenDetachHook) then
      AndroidScreenDetachHook();
    gMainSurfaceHooked := False;
  end;

  w := MainWindow;
  if w <> nil then
  begin
    w.AttachSurface(surf);
    if surf <> nil then
    begin
      { New surface: adopt its geometry and ask the form to lay out again. }
      w.SetPhysicalSize(ANativeWindow_getWidth(surf), ANativeWindow_getHeight(surf));
      EnqueueResizeEvent(w.PhysicalWidth, w.PhysicalHeight, 0);
    end;
  end;

  { Now that no window or buffer manager references the old surfaces,
    release them. }
  gMainSurfaceLock.Enter;
  try
    while gRetiredSurfaces.Count > 0 do
    begin
      ANativeWindow_release(PANativeWindow(gRetiredSurfaces[0]));
      gRetiredSurfaces.Delete(0);
    end;
  finally
    gMainSurfaceLock.Leave;
  end;
end;

procedure TfpgAndroidApplication.ProcessPendingSubWindowState;
var
  ch: PSubSurfaceChange;
  w: TfpgAndroidWindow;
  id: Integer;
begin
  { Floating-window surface attach/detach (owned by the queue; the window
    acquires its own reference). }
  while True do
  begin
    ch := nil;
    gSubStateLock.Enter;
    try
      if (gSubSurfQueue <> nil) and (gSubSurfQueue.Count > 0) then
      begin
        ch := PSubSurfaceChange(gSubSurfQueue[0]);
        gSubSurfQueue.Delete(0);
      end;
    finally
      gSubStateLock.Leave;
    end;
    if ch = nil then
      Break;
    w := FindWindowBySubId(ch^.Id);
    if w <> nil then
      w.SetSubSurface(ch^.Surface);
    if ch^.Surface <> nil then
      ANativeWindow_release(ch^.Surface);
    Dispose(ch);
  end;

  { Outside-touch dismissals of menus/popups. }
  while True do
  begin
    id := 0;
    gSubStateLock.Enter;
    try
      if (gDismissedSubWindows <> nil) and (gDismissedSubWindows.Count > 0) then
      begin
        id := Integer(gDismissedSubWindows[0]);
        gDismissedSubWindows.Delete(0);
      end;
    finally
      gSubStateLock.Leave;
    end;
    if id = 0 then
      Break;
    w := FindWindowBySubId(id);
    if (w <> nil) and (w.WindowType = wtPopup) and
       (w.PrimaryWidget is TfpgWidget) and TfpgWidget(w.PrimaryWidget).Visible then
      TfpgWidget(w.PrimaryWidget).Visible := False;
  end;
end;

procedure TfpgAndroidApplication.EnqueueTouchEvent(AAction, AX, AY, AButton: Integer);
var
  ev: PfpgAndroidTouchEvent;
begin
  New(ev);
  ev^.X := AX;
  ev^.Y := AY;
  ev^.Action := AAction;
  ev^.MouseButton := AButton;
  ev^.Kind := 0;
  ev^.WheelDelta := 0;
  ev^.SubWindowId := 0;
  ev^.W := 0;
  ev^.H := 0;
  FEventQueueLock.Enter;
  try
    FEventQueue.Add(ev);
  finally
    FEventQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgAndroidApplication.EnqueueHoverEvent(AX, AY: Integer);
var
  ev: PfpgAndroidTouchEvent;
begin
  New(ev);
  ev^.X := AX;
  ev^.Y := AY;
  ev^.Action := AMOTION_EVENT_ACTION_MOVE;
  ev^.MouseButton := 0;
  ev^.Kind := 2;   { hover: move with no button pressed }
  ev^.WheelDelta := 0;
  ev^.SubWindowId := 0;
  ev^.W := 0;
  ev^.H := 0;
  FEventQueueLock.Enter;
  try
    FEventQueue.Add(ev);
  finally
    FEventQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgAndroidApplication.EnqueueWheelEvent(AX, AY, ADelta: Integer);
var
  ev: PfpgAndroidTouchEvent;
begin
  New(ev);
  ev^.X := AX;
  ev^.Y := AY;
  ev^.Action := 0;
  ev^.MouseButton := 0;
  ev^.Kind := 1;   { wheel }
  ev^.WheelDelta := ADelta;
  ev^.SubWindowId := 0;
  ev^.W := 0;
  ev^.H := 0;
  FEventQueueLock.Enter;
  try
    FEventQueue.Add(ev);
  finally
    FEventQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgAndroidApplication.EnqueueSubTouchEvent(AId, AAction, AX, AY, AButton: Integer);
var
  ev: PfpgAndroidTouchEvent;
begin
  New(ev);
  ev^.X := AX;
  ev^.Y := AY;
  ev^.Action := AAction;
  ev^.MouseButton := AButton;
  ev^.Kind := 0;
  ev^.WheelDelta := 0;
  ev^.SubWindowId := AId;
  ev^.W := 0;
  ev^.H := 0;
  FEventQueueLock.Enter;
  try
    FEventQueue.Add(ev);
  finally
    FEventQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgAndroidApplication.EnqueueSubHoverEvent(AId, AX, AY: Integer);
var
  ev: PfpgAndroidTouchEvent;
begin
  New(ev);
  ev^.X := AX;
  ev^.Y := AY;
  ev^.Action := AMOTION_EVENT_ACTION_MOVE;
  ev^.MouseButton := 0;
  ev^.Kind := 2;
  ev^.WheelDelta := 0;
  ev^.SubWindowId := AId;
  ev^.W := 0;
  ev^.H := 0;
  FEventQueueLock.Enter;
  try
    FEventQueue.Add(ev);
  finally
    FEventQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgAndroidApplication.EnqueueSubWheelEvent(AId, ADelta: Integer);
var
  ev: PfpgAndroidTouchEvent;
begin
  New(ev);
  ev^.X := 0;
  ev^.Y := 0;
  ev^.Action := 0;
  ev^.MouseButton := 0;
  ev^.Kind := 1;
  ev^.WheelDelta := ADelta;
  ev^.SubWindowId := AId;
  ev^.W := 0;
  ev^.H := 0;
  FEventQueueLock.Enter;
  try
    FEventQueue.Add(ev);
  finally
    FEventQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgAndroidApplication.EnqueueKeyEvent(AKeyCode, AAction, AModifiers: Integer; AUnicodeChar: LongWord);
var
  ev: PfpgAndroidKeyEvent;
begin
  New(ev);
  ev^.Kind := ANDROID_EV_KEY;
  ev^.KeyCode := AKeyCode;
  ev^.Action := AAction;
  ev^.Modifiers := AModifiers;
  ev^.UnicodeChar := AUnicodeChar;
  ev^.Count := 0;
  ev^.Text := '';
  ev^.WindowId := 0;
  FKeyQueueLock.Enter;
  try
    FKeyEventQueue.Add(ev);
  finally
    FKeyQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgAndroidApplication.EnqueueTextEvent(const AText: string);
var
  ev: PfpgAndroidKeyEvent;
begin
  if AText = '' then
    Exit;
  New(ev);
  ev^.Kind := ANDROID_EV_TEXT;
  ev^.KeyCode := 0;
  ev^.Action := 0;
  ev^.Modifiers := 0;
  ev^.UnicodeChar := 0;
  ev^.Count := 0;
  { Deep copy: the string belongs to the injecting (Java) thread. }
  ev^.Text := Copy(AText, 1, Length(AText));
  ev^.WindowId := 0;
  FKeyQueueLock.Enter;
  try
    FKeyEventQueue.Add(ev);
  finally
    FKeyQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgAndroidApplication.EnqueueDeleteEvent(AKind, ACount: Integer);
var
  ev: PfpgAndroidKeyEvent;
begin
  if ACount < 1 then
    Exit;
  New(ev);
  ev^.Kind := AKind;
  ev^.KeyCode := 0;
  ev^.Action := 0;
  ev^.Modifiers := 0;
  ev^.UnicodeChar := 0;
  ev^.Count := ACount;
  ev^.Text := '';
  ev^.WindowId := 0;
  FKeyQueueLock.Enter;
  try
    FKeyEventQueue.Add(ev);
  finally
    FKeyQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgAndroidApplication.EnqueueResizeEvent(AWidth, AHeight: Integer; ADensity: Double);
var
  ev: PfpgAndroidResizeEvent;
begin
  New(ev);
  ev^.Width := AWidth;
  ev^.Height := AHeight;
  ev^.Density := ADensity;
  FResizeQueueLock.Enter;
  try
    FResizeQueue.Add(ev);
  finally
    FResizeQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

{ ---- Freeform window events -------------------------------------------- }

procedure TfpgAndroidApplication.EnqueueWindowBoundsEvent(AId, AX, AY, AW, AH: Integer);
var
  ev: PfpgAndroidTouchEvent;
begin
  New(ev);
  ev^.X := AX;
  ev^.Y := AY;
  ev^.Action := 0;
  ev^.MouseButton := 0;
  ev^.Kind := 3;
  ev^.WheelDelta := 0;
  ev^.SubWindowId := AId;
  ev^.W := AW;
  ev^.H := AH;
  FEventQueueLock.Enter;
  try
    FEventQueue.Add(ev);
  finally
    FEventQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgAndroidApplication.EnqueueWindowStateEvent(AId, AKind: Integer);
var
  ev: PfpgAndroidTouchEvent;
begin
  New(ev);
  FillChar(ev^, SizeOf(ev^), 0);
  ev^.Kind := AKind;   { 4 = closed, 5 = focused }
  ev^.SubWindowId := AId;
  FEventQueueLock.Enter;
  try
    FEventQueue.Add(ev);
  finally
    FEventQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgAndroidApplication.EnqueueSubKeyEvent(AId, AKeyCode, AAction, AModifiers: Integer; AUnicodeChar: LongWord);
var
  ev: PfpgAndroidKeyEvent;
begin
  New(ev);
  ev^.Kind := ANDROID_EV_KEY;
  ev^.KeyCode := AKeyCode;
  ev^.Action := AAction;
  ev^.Modifiers := AModifiers;
  ev^.UnicodeChar := AUnicodeChar;
  ev^.Count := 0;
  ev^.Text := '';
  ev^.WindowId := AId;
  FKeyQueueLock.Enter;
  try
    FKeyEventQueue.Add(ev);
  finally
    FKeyQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgAndroidApplication.EnqueueSubTextEvent(AId: Integer; const AText: string);
var
  ev: PfpgAndroidKeyEvent;
begin
  if AText = '' then
    Exit;
  New(ev);
  ev^.Kind := ANDROID_EV_TEXT;
  ev^.KeyCode := 0;
  ev^.Action := 0;
  ev^.Modifiers := 0;
  ev^.UnicodeChar := 0;
  ev^.Count := 0;
  ev^.Text := Copy(AText, 1, Length(AText));
  ev^.WindowId := AId;
  FKeyQueueLock.Enter;
  try
    FKeyEventQueue.Add(ev);
  finally
    FKeyQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

procedure TfpgAndroidApplication.EnqueueSubDeleteEvent(AId, AKind, ACount: Integer);
var
  ev: PfpgAndroidKeyEvent;
begin
  if ACount < 1 then
    Exit;
  New(ev);
  ev^.Kind := AKind;
  ev^.KeyCode := 0;
  ev^.Action := 0;
  ev^.Modifiers := 0;
  ev^.UnicodeChar := 0;
  ev^.Count := ACount;
  ev^.Text := '';
  ev^.WindowId := AId;
  FKeyQueueLock.Enter;
  try
    FKeyEventQueue.Add(ev);
  finally
    FKeyQueueLock.Leave;
  end;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

function TfpgAndroidApplication.HasPendingEvents: Boolean;
begin
  FEventQueueLock.Enter;
  try
    Result := FEventQueue.Count > 0;
  finally
    FEventQueueLock.Leave;
  end;
end;

function TfpgAndroidApplication.HasPendingKeyEvents: Boolean;
begin
  FKeyQueueLock.Enter;
  try
    Result := FKeyEventQueue.Count > 0;
  finally
    FKeyQueueLock.Leave;
  end;
end;

function TfpgAndroidApplication.HasPendingResizeEvents: Boolean;
begin
  FResizeQueueLock.Enter;
  try
    Result := FResizeQueue.Count > 0;
  finally
    FResizeQueueLock.Leave;
  end;
end;

procedure TfpgAndroidApplication.ProcessQueuedResizeEvents;
var
  ev: PfpgAndroidResizeEvent;
  w: TfpgAndroidWindow;
  msg: TfpgMessageParams;
  physW, physH: Integer;
  density: Double;
begin
  while True do
  begin
    ev := nil;
    FResizeQueueLock.Enter;
    try
      if FResizeQueue.Count > 0 then
      begin
        ev := PfpgAndroidResizeEvent(FResizeQueue[0]);
        FResizeQueue.Delete(0);
      end;
    finally
      FResizeQueueLock.Leave;
    end;
    if ev = nil then
      Break;

    density := ev^.Density;
    if (density > 0) and (gAndroidDensity <> density) then
    begin
      gAndroidDensity := density;
      gHiDPIScaleFactor := density;
    end;

    { Keep the logical screen in sync with the physical surface. }
    if (ev^.Width > 0) and (ev^.Height > 0) then
    begin
      FPhysicalW := ev^.Width;
      FPhysicalH := ev^.Height;
      if gHiDPIScaleFactor >= 1.0 then
      begin
        gAndroidScreenW := Round(ev^.Width / gHiDPIScaleFactor);
        gAndroidScreenH := Round(ev^.Height / gHiDPIScaleFactor);
      end
      else
      begin
        gAndroidScreenW := ev^.Width;
        gAndroidScreenH := ev^.Height;
      end;
      gAndroidScreenValid := True;
    end;

    w := MainWindow;
    if w = nil then
    begin
      Dispose(ev);
      Continue;
    end;

    if (ev^.Width > 0) and (ev^.Height > 0) and
       (w.PhysicalWidth = ev^.Width) and (w.PhysicalHeight = ev^.Height) and
       (w.PrimaryWidget is TfpgWidget) and
       (TfpgWidget(w.PrimaryWidget).ActualWidth = w.Width) and
       (TfpgWidget(w.PrimaryWidget).ActualHeight = w.Height) then
    begin
      { Same geometry AND the primary widget already matches the window
        (e.g. metrics-only update). The widget check matters on startup: the
        surface metrics are often known before the main form exists, so the
        form still carries its design-time size and must be resized. }
      Dispose(ev);
      Continue;
    end;

    if (ev^.Width > 0) and (ev^.Height > 0) then
    begin
      w.SetPhysicalSize(ev^.Width, ev^.Height);
      physW := w.Width;
      physH := w.Height;
    end
    else
    begin
      physW := gAndroidScreenW;
      physH := gAndroidScreenH;
    end;

    AndroidLog(ANDROID_LOG_INFO, Format('Resize: phys=%dx%d logical=%dx%d density=%.4f',
      [ev^.Width, ev^.Height, physW, physH, gHiDPIScaleFactor]));

    FillChar(msg, SizeOf(msg), 0);
    msg.rect.SetRect(0, 0, physW, physH);
    fpgSendMessage(nil, w, FPGM_RESIZE, msg);
    if w.PrimaryWidget is TfpgWidget then
      TfpgWidget(w.PrimaryWidget).Invalidate;
    Dispose(ev);
  end;
end;

procedure TfpgAndroidApplication.ProcessQueuedEvents;
var
  ev: PfpgAndroidTouchEvent;
  wnd: TfpgWindowBase;
  msg: TfpgMessageParams;
  gx, gy: Integer;
  mw: TfpgWindowBase;
begin
  while True do
  begin
    ev := nil;
    FEventQueueLock.Enter;
    try
      if FEventQueue.Count > 0 then
      begin
        ev := PfpgAndroidTouchEvent(FEventQueue[0]);
        FEventQueue.Delete(0);
      end;
    finally
      FEventQueueLock.Leave;
    end;
    if ev = nil then
      Break;

    { Freeform window state events (not pointer input). }
    if ev^.Kind = 3 then   { bounds changed: X,Y,W,H = physical content rect }
    begin
      ApplyWindowBounds(ev^.SubWindowId, ev^.X, ev^.Y, ev^.W, ev^.H);
      Dispose(ev);
      Continue;
    end;
    if ev^.Kind = 4 then   { window closed by the system (X button / back) }
    begin
      HandleWindowClosed(ev^.SubWindowId);
      Dispose(ev);
      Continue;
    end;
    if ev^.Kind = 5 then   { window gained focus }
    begin
      HandleWindowFocused(ev^.SubWindowId);
      Dispose(ev);
      Continue;
    end;
    if ev^.Kind = 6 then   { window is ready: repaint (first frame may have
                             been dropped before the Java window existed) }
    begin
      mw := FindWindowBySubId(ev^.SubWindowId);
      if (mw <> nil) and (mw.PrimaryWidget is TfpgWidget) then
        TfpgWidget(mw.PrimaryWidget).Invalidate;
      Dispose(ev);
      Continue;
    end;

    { Physical -> logical. }
    if gHiDPIScaleFactor >= 1.0 then
    begin
      gx := Round(ev^.X / gHiDPIScaleFactor);
      gy := Round(ev^.Y / gHiDPIScaleFactor);
    end
    else
    begin
      gx := ev^.X;
      gy := ev^.Y;
    end;

    if ev^.SubWindowId > 0 then
    begin
      { Pointer event from a floating window: coordinates are already local
        to that window; no hit-testing needed. }
      wnd := FindWindowBySubId(ev^.SubWindowId);
      if wnd = nil then
      begin
        Dispose(ev);
        Continue;
      end;
    end
    else
    begin
      wnd := HitTestWindow(gx, gy);
      if wnd = nil then
      begin
        if MainForm <> nil then
          wnd := MainForm.Window
        else if FormCount > 0 then
          wnd := Forms[0].Window;
      end;
      if wnd = nil then
      begin
        Dispose(ev);
        Continue;
      end;
    end;

    { Modal blocking: while a modal form (ShowModal) is active, only that
      form's window - and popups it owns, e.g. combo dropdowns - accepts
      pointer events. TopModalForm is maintained by fpGUI itself. }
    if (fpgApplication <> nil) and (fpgApplication.TopModalForm <> nil) then
    begin
      mw := fpgApplication.TopModalForm.Window;
      if (mw <> nil) and (wnd <> mw) and (wnd.WindowType <> wtPopup) then
      begin
        Dispose(ev);
        Continue;
      end;
    end;

    FillChar(msg, SizeOf(msg), 0);
    if ev^.SubWindowId > 0 then
    begin
      { Floating-window event: gx/gy are already window-local. }
      msg.mouse.x := gx;
      msg.mouse.y := gy;
    end
    else
    begin
      msg.mouse.x := gx - wnd.Left;
      msg.mouse.y := gy - wnd.Top;
    end;
    msg.mouse.shiftstate := [];
    msg.mouse.timestamp := Now;

    { Wheel scroll (mouse). }
    if ev^.Kind = 1 then
    begin
      msg.mouse.delta := ev^.WheelDelta;
      fpgPostMessage(nil, wnd, FPGM_SCROLL, msg);
      Dispose(ev);
      Continue;
    end;

    { Hover (mouse move with no button): framework synthesises
      MOUSEENTER/EXIT and cursor changes from DispatchMouseEvent. }
    if ev^.Kind = 2 then
    begin
      msg.mouse.buttons := 0;
      fpgPostMessage(nil, wnd, FPGM_MOUSEMOVE, msg);
      Dispose(ev);
      Continue;
    end;

    { Keyboard focus follows the clicked window. }
    if (ev^.Action = AMOTION_EVENT_ACTION_DOWN) and (wnd is TfpgAndroidWindow) then
      gFocusedWinHandle := TfpgAndroidWindow(wnd).WinHandle;

    { A1 (desktop style): a click on a non-popup window closes the whole
      popup/menu chain, and the click still reaches its target. }
    if (ev^.Action = AMOTION_EVENT_ACTION_DOWN) and
       (wnd.WindowType <> wtPopup) and (PopupListFirst <> nil) then
      ClosePopups;

    { MOVE/UP are delivered to the window that received DOWN (if alive);
      this keeps drags working when the pointer crosses windows. }
    if (ev^.Action in [AMOTION_EVENT_ACTION_MOVE, AMOTION_EVENT_ACTION_UP,
                       AMOTION_EVENT_ACTION_CANCEL]) and
       (gLastDownTargetWin <> nil) then
    begin
      mw := FindWindowByHandle(gLastDownTargetWin);
      if mw <> nil then
        wnd := mw;
    end;

    case ev^.Action of
      AMOTION_EVENT_ACTION_DOWN:
        begin
          { 0 = touch -> left button; 1/2/3 = mouse left/right/middle. }
          case ev^.MouseButton of
            2: gLastDownButton := MOUSE_RIGHT;
            3: gLastDownButton := MOUSE_MIDDLE;
          else
            gLastDownButton := MOUSE_LEFT;
          end;
          gLastDownTargetWin := (wnd as TfpgAndroidWindow).WinHandle;
          gLastDownGlobX := gx;
          gLastDownGlobY := gy;
          msg.mouse.buttons := gLastDownButton;
          fpgPostMessage(nil, wnd, FPGM_MOUSEDOWN, msg);
        end;
      AMOTION_EVENT_ACTION_MOVE:
        begin
          msg.mouse.buttons := gLastDownButton;
          fpgPostMessage(nil, wnd, FPGM_MOUSEMOVE, msg);
        end;
      AMOTION_EVENT_ACTION_UP, AMOTION_EVENT_ACTION_CANCEL:
        begin
          msg.mouse.buttons := gLastDownButton;
          gLastDownButton := 0;
          { Deliver to the DOWN position so widgets match press/release. }
          if ev^.SubWindowId > 0 then
          begin
            msg.mouse.x := gLastDownGlobX;   { already window-local }
            msg.mouse.y := gLastDownGlobY;
          end
          else
          begin
            msg.mouse.x := gLastDownGlobX - wnd.Left;
            msg.mouse.y := gLastDownGlobY - wnd.Top;
          end;
          fpgPostMessage(nil, wnd, FPGM_MOUSEUP, msg);
          gLastDownTargetWin := nil;
        end;
    end;
    Dispose(ev);
  end;
end;

{ B2: freeform window moved/resized by the user. x/y/w/h are PHYSICAL
  content pixels. Only secondary windows (id>0) are handled here; the main
  window's size comes from its surface. }
procedure TfpgAndroidApplication.ApplyWindowBounds(AId, APx, APy, APw, APh: Integer);
var
  w: TfpgAndroidWindow;
  lx, ly, lw, lh: Integer;
  msg: TfpgMessageParams;
begin
  if AId <= 0 then
    Exit;
  w := FindWindowBySubId(AId);
  if w = nil then
    Exit;
  if (APw < 1) or (APh < 1) then
    Exit;
  if gHiDPIScaleFactor >= 1.0 then
  begin
    lx := Round(APx / gHiDPIScaleFactor);
    ly := Round(APy / gHiDPIScaleFactor);
    lw := Round(APw / gHiDPIScaleFactor);
    lh := Round(APh / gHiDPIScaleFactor);
  end
  else
  begin
    lx := APx; ly := APy; lw := APw; lh := APh;
  end;

  { Popups (menus/dropdowns) own their size: the layout is fixed by their
    content. Only the position is synced back - a size report (the window may
    be padded for the freeform drag band / min task size) would otherwise
    resize the fpGUI popup and leave blank margins. }
  if w.FWindowType = wtPopup then
  begin
    if (w.FPosition.X = lx) and (w.FPosition.Y = ly) then
      Exit;
    w.FSyncingFromJava := True;
    try
      w.FPosition.X := lx;
      w.FPosition.Y := ly;
    finally
      w.FSyncingFromJava := False;
    end;
    Exit;
  end;

  if (w.FPosition.X = lx) and (w.FPosition.Y = ly) and
     (w.FSize.W = lw) and (w.FSize.H = lh) then
    Exit;

  w.FSyncingFromJava := True;
  try
    w.FPosition.X := lx;
    w.FPosition.Y := ly;
    w.FSize.W := lw;
    w.FSize.H := lh;
    w.FPhysicalWidth := APw;
    w.FPhysicalHeight := APh;
    FillChar(msg, SizeOf(msg), 0);
    msg.rect.SetRect(0, 0, lw, lh);
    fpgSendMessage(nil, w, FPGM_RESIZE, msg);
    if w.PrimaryWidget is TfpgWidget then
      TfpgWidget(w.PrimaryWidget).Invalidate;
  finally
    w.FSyncingFromJava := False;
  end;
end;

{ The system closed a freeform window (X button / back key). }
procedure TfpgAndroidApplication.HandleWindowClosed(AId: Integer);
var
  w: TfpgAndroidWindow;
begin
  w := FindWindowBySubId(AId);
  if w = nil then
    Exit;
  if w.FWindowType = wtPopup then
  begin
    if w.PrimaryWidget is TfpgPopupWindow then
      TfpgPopupWindow(w.PrimaryWidget).Close;
  end
  else
  begin
    if w.PrimaryWidget is TfpgBaseForm then
      TfpgBaseForm(w.PrimaryWidget).Close
    else if w.PrimaryWidget is TfpgWidget then
      TfpgWidget(w.PrimaryWidget).Visible := False;
  end;
end;

procedure TfpgAndroidApplication.HandleWindowFocused(AId: Integer);
var
  w: TfpgAndroidWindow;
begin
  w := FindWindowBySubId(AId);
  if w <> nil then
    gFocusedWinHandle := w.WinHandle;
end;

procedure TfpgAndroidApplication.ProcessQueuedKeyEvents;
var
  ev: PfpgAndroidKeyEvent;
  dest: TfpgWindowBase;
  fw: TfpgWidget;
  msg: TfpgMessageParams;
  fpgKey: word;
  ss: TShiftState;
  i, clen: Integer;
  text: string;
begin
  while True do
  begin
    ev := nil;
    FKeyQueueLock.Enter;
    try
      if FKeyEventQueue.Count > 0 then
      begin
        ev := PfpgAndroidKeyEvent(FKeyEventQueue[0]);
        FKeyEventQueue.Delete(0);
      end;
    finally
      FKeyQueueLock.Leave;
    end;
    if ev = nil then
      Break;

    { Route to the popup that owns the focus root first, then to the
      window the event came from (freeform), then to the last touched
      window, then to the main form. A modal form always wins. }
    dest := nil;
    if (fpgApplication <> nil) and (fpgApplication.TopModalForm <> nil) then
      dest := fpgApplication.TopModalForm.Window;
    if (dest = nil) and (ev^.WindowId > 0) then
      dest := FindWindowBySubId(ev^.WindowId);
    if (dest = nil) and (FocusRootWidget <> nil) then
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

    { A1: typing into a non-popup window closes the popup/menu chain. }
    if (dest.WindowType <> wtPopup) and (PopupListFirst <> nil) then
      ClosePopups;

    case ev^.Kind of
      ANDROID_EV_TEXT:
        begin
          text := ev^.Text;
          i := 1;
          while i <= Length(text) do
          begin
            clen := Utf8CharLen(Byte(text[i]));
            if clen < 1 then
              clen := 1;
            if i + clen - 1 > Length(text) then
              clen := Length(text) - i + 1;
            FillChar(msg, SizeOf(msg), 0);
            msg.keyboard.keychar := Copy(text, i, clen);
            try
              fpgSendMessage(nil, dest, FPGM_KEYCHAR, msg);
            except
              on E: Exception do
                AndroidLog(ANDROID_LOG_ERROR, 'KEYCHAR dropped: ' + E.Message);
            end;
            Inc(i, clen);
          end;
        end;
      ANDROID_EV_DELETE_LEFT:
        begin
          FillChar(msg, SizeOf(msg), 0);
          msg.keyboard.keycode := keyBackSpace;
          msg.keyboard.shiftstate := [];
          for i := 1 to ev^.Count do
            try
              fpgSendMessage(nil, dest, FPGM_KEYPRESS, msg);
            except
              on E: Exception do
                AndroidLog(ANDROID_LOG_ERROR, 'BACKSPACE dropped: ' + E.Message);
            end;
        end;
      ANDROID_EV_DELETE_RIGHT:
        begin
          FillChar(msg, SizeOf(msg), 0);
          msg.keyboard.keycode := keyDelete;
          msg.keyboard.shiftstate := [];
          for i := 1 to ev^.Count do
            try
              fpgSendMessage(nil, dest, FPGM_KEYPRESS, msg);
            except
              on E: Exception do
                AndroidLog(ANDROID_LOG_ERROR, 'DELETE dropped: ' + E.Message);
            end;
        end;
      ANDROID_EV_MOVE_CURSOR:
        begin
          case ev^.Count of
            ANDROID_CURSOR_LEFT:  fpgKey := keyLeft;
            ANDROID_CURSOR_RIGHT: fpgKey := keyRight;
            ANDROID_CURSOR_UP:    fpgKey := keyUp;
            ANDROID_CURSOR_DOWN:  fpgKey := keyDown;
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
    else { ANDROID_EV_KEY }
      begin
        FillChar(msg, SizeOf(msg), 0);

        { Unicode input (hardware/soft keyboard typing without IME commit). }
        if (ev^.UnicodeChar > 0) and (ev^.Action = 0) and
           ((ev^.Modifiers and (ANDROID_META_CTRL_ON or ANDROID_META_ALT_ON or
                                ANDROID_META_META_ON)) = 0) then
        begin
          msg.keyboard.keychar := UnicodeCodepointToUTF8(ev^.UnicodeChar);
          fpgPostMessage(nil, dest, FPGM_KEYCHAR, msg);
        end;

        ss := [];
        if (ev^.Modifiers and ANDROID_META_SHIFT_ON) <> 0 then
          Include(ss, ssShift);
        if (ev^.Modifiers and ANDROID_META_CTRL_ON) <> 0 then
          Include(ss, ssCtrl);
        if (ev^.Modifiers and ANDROID_META_ALT_ON) <> 0 then
          Include(ss, ssAlt);
        msg.keyboard.shiftstate := ss;

        if AndroidKeyToFpgKey(ev^.KeyCode) <> 0 then
        begin
          fpgKey := AndroidKeyToFpgKey(ev^.KeyCode);
          msg.keyboard.keycode := fpgKey;
          if ev^.Action = 0 then
            fpgSendMessage(nil, dest, FPGM_KEYPRESS, msg)
          else
            fpgSendMessage(nil, dest, FPGM_KEYRELEASE, msg);
        end;
      end;
    end;
    Dispose(ev);
  end;
end;

procedure TfpgAndroidApplication.UpdateKeyboardVisibility;
var
  wnd: TfpgWindowBase;
  fw: TfpgWidget;
  cn: string;
  kbType: Integer;
  winId: Integer;
begin
  fw := nil;
  winId := 0;
  if gFocusedWinHandle <> nil then
  begin
    wnd := FindWindowByHandle(gFocusedWinHandle);
    if (wnd <> nil) and (wnd.PrimaryWidget is TfpgWidget) then
    begin
      if wnd is TfpgAndroidWindow then
        winId := TfpgAndroidWindow(wnd).SubWindowId;
      fw := TfpgWidget(wnd.PrimaryWidget);
      while (fw <> nil) and (fw.ActiveWidget <> nil) do
        fw := fw.ActiveWidget;
    end;
  end;

  cn := '';
  kbType := 0;
  if fw <> nil then
  begin
    cn := fw.ClassName;
    if Pos('EditInteger', cn) > 0 then
      kbType := 2
    else if (Pos('EditFloat', cn) > 0) or (Pos('EditCurrency', cn) > 0) then
      kbType := 3
    else if (Pos('Edit', cn) > 0) or (Pos('Memo', cn) > 0)
         or (Pos('Spin', cn) > 0) or (cn = 'TfpgComboBox')
         or (Assigned(fpgCaret) and (fpgCaret.Canvas <> nil)) then
      kbType := 1;
  end;
  if (kbType <> FLastKeyboardType) or (winId <> FLastKeyboardWindowId) then
  begin
    FLastKeyboardType := kbType;
    FLastKeyboardWindowId := winId;
    AndroidLog(ANDROID_LOG_INFO, 'KBD: type ' + IntToStr(kbType) + ' focus=' + cn +
      ' win=' + IntToStr(winId));
    if Assigned(AndroidShowKeyboardProc) then
      AndroidShowKeyboardProc(winId, kbType > 0, kbType);
  end;
end;

procedure TfpgAndroidApplication.ApplyPendingSurface;
begin
  ProcessPendingSurface;
end;

procedure TfpgAndroidApplication.StopApplication;
begin
  Terminated := True;
  if WakeChannel <> nil then
    WakeChannel.Signal;
end;

function TfpgAndroidApplication.DoGetFontFaceList: TStringList;
var
  i: Integer;
  fam: string;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  for i := 0 to gFontCache.Count - 1 do
  begin
    if gFontCache[i] = nil then
      Continue;
    fam := gFontCache[i].FamilyName;
    if (fam <> '') and (Result.IndexOf(fam) < 0) then
      Result.Add(fam);
  end;
  if Result.Count = 0 then
  begin
    Result.Add('Roboto');
    Result.Add('Droid Sans');
    Result.Add('Noto Sans CJK SC');
  end;
end;

{ Push the current modal window (TopModalForm's secondary window id, 0 = none)
  to Java. Java disables input on every other window while a modal is active,
  including the system caption buttons, and raises the modal task. Pascal's
  own event filtering (ProcessQueuedEvents) stays as a cross-ROM safety net. }
procedure TfpgAndroidApplication.SyncModalState;
var
  mw: TfpgWindowBase;
  id: Integer;
begin
  id := 0;
  if (fpgApplication <> nil) and (fpgApplication.TopModalForm <> nil) then
  begin
    mw := fpgApplication.TopModalForm.Window;
    if (mw <> nil) and (mw is TfpgAndroidWindow) then
      id := TfpgAndroidWindow(mw).SubWindowId;
  end;
  if id = FLastModalId then
    Exit;
  FLastModalId := id;
  if Assigned(AndroidSetModalWindowProc) then
    AndroidSetModalWindowProc(id);
  AndroidLog(ANDROID_LOG_INFO, Format('modal window changed: id=%d', [id]));
end;

procedure TfpgAndroidApplication.DoWaitWindowMessage(atimeoutms: integer);
var
  rfds: baseunix.TFDSet;
  wakefd: integer;
  maxfd: integer;
  r: integer;
begin
  try
    ProcessPendingSurface;
    ProcessPendingSubWindowState;
    ProcessQueuedResizeEvents;
    ProcessQueuedEvents;
    ProcessQueuedKeyEvents;
    SyncModalState;
    fpgDeliverMessages;
  except
    on E: Exception do
      AndroidLog(ANDROID_LOG_ERROR, 'loop-wave exception: ' + E.ClassName + ': ' + E.Message);
  end;

  { The main form may have been closed while the events above were handled
    (fpgApplication.Terminate): finish the Java activity before the loop
    exits, otherwise the window would stay behind. }
  if Terminated and Assigned(AndroidFinishProc) then
  begin
    AndroidFinishProc;
    Exit;
  end;

  UpdateKeyboardVisibility;

  if HasPendingEvents or HasPendingKeyEvents or HasPendingResizeEvents then
    Exit;

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

  if atimeoutms < 0 then
    atimeoutms := 50;
  if atimeoutms > 2500 then
    atimeoutms := 2500;

  if maxfd >= 0 then
  begin
    r := fpSelect(maxfd + 1, @rfds, nil, nil, atimeoutms);
    if (wakefd >= 0) and (r > 0) and (fpFD_ISSET(wakefd, rfds) <> 0) then
      WakeChannel.Drain;
  end
  else
    Sleep(50);

  try
    ProcessPendingSurface;
    ProcessPendingSubWindowState;
    ProcessQueuedResizeEvents;
    ProcessQueuedEvents;
    ProcessQueuedKeyEvents;
    SyncModalState;
    fpgDeliverMessages;
  except
    on E: Exception do
      AndroidLog(ANDROID_LOG_ERROR, 'loop-wave2 exception: ' + E.ClassName + ': ' + E.Message);
  end;

  if Assigned(FOnIdle) then
    try
      FOnIdle(Self);
    except
      on E: Exception do
        AndroidLog(ANDROID_LOG_ERROR, 'OnIdle exception: ' + E.ClassName + ': ' + E.Message);
    end;

  { The main form was closed (TfpgBaseForm.Close -> fpgApplication.Terminate)
    or the activity is being torn down: finish the Java activity so the
    application really exits instead of leaving a dead window behind. }
  if Terminated and Assigned(AndroidFinishProc) then
    AndroidFinishProc;
end;

function TfpgAndroidApplication.MessagesPending: boolean;
begin
  Result := HasPendingEvents or HasPendingKeyEvents or HasPendingResizeEvents or
    (fpgGetFirstMessage <> nil);
end;

procedure TfpgAndroidApplication.DoFlush;
begin
  ProcessPendingSurface;
  ProcessPendingSubWindowState;
  ProcessQueuedResizeEvents;
  fpgDeliverMessages;
end;

function TfpgAndroidApplication.GetMonitorCount: Integer;
begin
  Result := 1;
end;

function TfpgAndroidApplication.GetMonitorInfo(AIndex: Integer): TfpgScreenInfo;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Bounds.SetRect(0, 0, GetScreenWidth, GetScreenHeight);
  Result.WorkArea := Result.Bounds;
  Result.Primary := AIndex = 0;
  Result.DpiX := Screen_dpi_x;
  Result.DpiY := Screen_dpi_y;
end;

function TfpgAndroidApplication.GetScreenWidth: TfpgCoord;
begin
  Result := gAndroidScreenW;
end;

function TfpgAndroidApplication.GetScreenHeight: TfpgCoord;
begin
  Result := gAndroidScreenH;
end;

function TfpgAndroidApplication.GetScreenPixelColor(APos: TPoint): TfpgColor;
begin
  { TODO: read back from the screen buffer (fpg_android_buffer_manager). }
  if APos.X = APos.Y then ;
  Result := 0;
end;

function TfpgAndroidApplication.Screen_dpi_x: integer;
begin
  Result := gHiDPI;
end;

function TfpgAndroidApplication.Screen_dpi_y: integer;
begin
  Result := gHiDPI;
end;

function TfpgAndroidApplication.Screen_dpi: integer;
begin
  Result := gHiDPI;
end;

{ ---------------------------------------------------------------------
  TfpgAndroidClipboard
  --------------------------------------------------------------------- }

function TfpgAndroidClipboard.DoGetText: TfpgString;
begin
  Result := '';
  if Assigned(AndroidClipboardGetProc) then
    Result := AndroidClipboardGetProc();
  if Result = '' then
    Result := FBuffer;   { fallback: last in-app copy }
end;

procedure TfpgAndroidClipboard.DoSetText(const AValue: TfpgString);
begin
  FBuffer := AValue;
  if Assigned(AndroidClipboardSetProc) then
    AndroidClipboardSetProc(AValue);
end;

procedure TfpgAndroidClipboard.InitClipboard;
begin
  { Nothing to do; the bridge hooks are optional. }
end;

{ ---------------------------------------------------------------------
  TfpgAndroidFileList
  --------------------------------------------------------------------- }

procedure TfpgAndroidFileList.PopulateSpecialDirs(const aDirectory: TfpgString);
begin
  FSpecialDirs.Clear;
  FSpecialDirs.Add(DirectorySeparator);
  inherited PopulateSpecialDirs(aDirectory);
  if (gAndroidFilesDir <> '') and (FSpecialDirs.IndexOf(gAndroidFilesDir) < 0) then
    FSpecialDirs.Add(gAndroidFilesDir);
  if (gAndroidExternalFilesDir <> '') and (FSpecialDirs.IndexOf(gAndroidExternalFilesDir) < 0) then
    FSpecialDirs.Add(gAndroidExternalFilesDir);
end;

function TfpgAndroidFileList.ReadDirectory(const aDirectory: TfpgString = ''): boolean;
var
  dir: string;
begin
  dir := aDirectory;
  if (dir = '') or (dir = '.') then
  begin
    dir := gAndroidFilesDir;
    if dir = '' then
      dir := GetCurrentDir;
  end;
  Result := inherited ReadDirectory(dir);
end;

{ ---------------------------------------------------------------------
  Utility functions
  --------------------------------------------------------------------- }

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
  Drag & drop / tray stubs
  --------------------------------------------------------------------- }

function TfpgAndroidDrag.Execute(const ADropActions: TfpgDropActions;
  const ADefaultAction: TfpgDropAction): TfpgDropAction;
begin
  if ADropActions = [] then ;
  if ADefaultAction = daCopy then ;
  Result := daIgnore;
end;

function TfpgAndroidDrop.GetDropAction: TfpgDropAction;
begin
  Result := FDropAction;
end;

procedure TfpgAndroidDrop.SetDropAction(AValue: TfpgDropAction);
begin
  FDropAction := AValue;
end;

function TfpgAndroidDrop.GetWindowForDrop: TfpgWindowBase;
begin
  Result := nil;
end;

procedure TfpgAndroidSystemTrayIcon.Show;
begin
  { not supported }
end;

procedure TfpgAndroidSystemTrayIcon.Hide;
begin
  { not supported }
end;

function TfpgAndroidSystemTrayIcon.IsSystemTrayAvailable: boolean;
begin
  Result := False;
end;

function TfpgAndroidSystemTrayIcon.SupportsMessages: boolean;
begin
  Result := False;
end;

function UnicodeCodepointToUTF8(cp: UInt32): string;
begin
  if cp < $80 then
    Result := AnsiChar(cp)
  else if cp < $800 then
    Result := AnsiChar($C0 or (cp shr 6)) + AnsiChar($80 or (cp and $3F))
  else if cp < $10000 then
    Result := AnsiChar($E0 or (cp shr 12)) +
              AnsiChar($80 or ((cp shr 6) and $3F)) +
              AnsiChar($80 or (cp and $3F))
  else
    Result := AnsiChar($F0 or (cp shr 18)) +
              AnsiChar($80 or ((cp shr 12) and $3F)) +
              AnsiChar($80 or ((cp shr 6) and $3F)) +
              AnsiChar($80 or (cp and $3F));
end;

function AndroidKeyToFpgKey(AKeyCode: Integer): Word;
begin
  case AKeyCode of
    AKEYCODE_ESCAPE, AKEYCODE_BACK: Result := keyEscape;
    AKEYCODE_DPAD_UP:    Result := keyUp;
    AKEYCODE_DPAD_DOWN:  Result := keyDown;
    AKEYCODE_DPAD_LEFT:  Result := keyLeft;
    AKEYCODE_DPAD_RIGHT: Result := keyRight;
    AKEYCODE_DPAD_CENTER: Result := keyReturn;
    AKEYCODE_TAB:        Result := keyTab;
    AKEYCODE_SPACE:      Result := Ord(' ');
    AKEYCODE_ENTER,
    AKEYCODE_NUMPAD_ENTER: Result := keyReturn;
    AKEYCODE_DEL:        Result := keyBackSpace;
    AKEYCODE_FORWARD_DEL: Result := keyDelete;
    AKEYCODE_PAGE_UP:    Result := keyPageUp;
    AKEYCODE_PAGE_DOWN:  Result := keyPageDown;
    AKEYCODE_MOVE_HOME:  Result := keyHome;
    AKEYCODE_MOVE_END:   Result := keyEnd;
    AKEYCODE_INSERT:     Result := keyInsert;
    AKEYCODE_MENU:       Result := keyMenu;
  else
    Result := 0;
  end;
end;

{ ---------------------------------------------------------------------
  Java-facing entry points
  --------------------------------------------------------------------- }

procedure AndroidSetAppMain(AProc: TAndroidMainProc);
begin
  AndroidAppMain := AProc;
end;

function AndroidIsStarted: Boolean;
begin
  gAppStartLock.Enter;
  try
    Result := gAppStarted;
  finally
    gAppStartLock.Leave;
  end;
end;

type
  TAndroidAppThread = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TAndroidAppThread.Execute;
begin
  AndroidLog(ANDROID_LOG_INFO, 'Pascal app thread started');
  { The RTL's "main thread" is whichever thread loaded the library - here
    the Java UI thread (System.loadLibrary -> JNI_OnLoad). The fpGUI message
    loop runs on THIS worker thread, so it must own the main-thread role:
    otherwise TfpgApplication.WaitWindowMessage's CheckSynchronize raises
    EThread ("CheckSynchronize called from non-main thread") on every loop
    iteration and TThread.Synchronize() from worker threads would target
    the wrong thread. Must happen before any TThread/application object
    is created. }
  MainThreadID := GetCurrentThreadID;
  try
    { Clear a previous termination so a re-created activity can run the
      loop again. The getter creates the application object on THIS thread
      (never on the Java UI thread) on first use. }
    if fpgApplication <> nil then
    begin
      fpgApplication.Terminated := False;
      { A previous run's main form has been freed: drop the stale pointer so
        the newly created form becomes the main window again (otherwise its
        window would be allocated as a secondary one). }
      fpgApplication.MainForm := nil;
    end;
    gFocusedWinHandle := nil;
    if Assigned(AndroidAppMain) then
      AndroidAppMain();
  except
    on E: Exception do
      AndroidLog(ANDROID_LOG_ERROR, 'App thread exception: ' + E.ClassName + ': ' + E.Message);
  end;
  gAppStartLock.Enter;
  try
    gAppThreadFinished := True;
  finally
    gAppStartLock.Leave;
  end;
  AndroidLog(ANDROID_LOG_INFO, 'Pascal app thread finished');
end;

function AndroidStartApp: Boolean;
begin
  Result := False;
  gAppStartLock.Enter;
  try
    if gAppStarted and not gAppThreadFinished then
      Exit;
    gAppStarted := True;
    gAppThreadFinished := False;
  finally
    gAppStartLock.Leave;
  end;
  AndroidLog(ANDROID_LOG_INFO, 'AndroidStartApp: starting Pascal app thread');
  gAppThread := TAndroidAppThread.Create(False);
  gAppThread.FreeOnTerminate := True;
  Result := True;
end;

procedure AndroidSetMainSurface(aToken: Integer; aSurface: PANativeWindow);
var
  app: TfpgAndroidApplication;
  old: PANativeWindow;
begin
  old := nil;
  if aSurface <> nil then
    AndroidLog(ANDROID_LOG_INFO, Format('AndroidSetMainSurface: token=%d %p %dx%d',
      [aToken, Pointer(aSurface), ANativeWindow_getWidth(aSurface),
       ANativeWindow_getHeight(aSurface)]))
  else
    AndroidLog(ANDROID_LOG_INFO, Format('AndroidSetMainSurface: token=%d detached',
      [aToken]));

  { Take ownership of the incoming surface (the caller keeps its own
    reference from ANativeWindow_fromSurface). The previous surface is
    queued for the loop thread to release - see gRetiredSurfaces. }
  if aSurface <> nil then
    ANativeWindow_acquire(aSurface);
  gMainSurfaceLock.Enter;
  try
    if aToken > gMainSurfaceToken then
    begin
      gMainSurfaceToken := aToken;
      gMainReattachPending := False;   { the new instance took over }
    end;
    old := gMainSurface;
    gMainSurface := aSurface;
    gMainSurfaceChanged := True;
    if (old <> nil) and (old <> aSurface) then
      gRetiredSurfaces.Add(old);
  finally
    gMainSurfaceLock.Leave;
  end;

  app := AndroidApplication;
  if app <> nil then
    app.SetMainSurface(aSurface);
  { When the app is not running yet the parked surface is picked up by
    DoAllocateWindowHandle; the pending-changed flag wakes nothing because
    no loop exists yet. }
end;

procedure AndroidDetachMainSurface(aToken: Integer);
var
  current: Boolean;
begin
  gMainSurfaceLock.Enter;
  try
    current := (aToken >= gMainSurfaceToken) and (not gMainReattachPending);
  finally
    gMainSurfaceLock.Leave;
  end;
  if not current then
  begin
    { A superseded instance's surface went away (borderless re-attach):
      keep the current surface. }
    AndroidLog(ANDROID_LOG_INFO, Format('AndroidDetachMainSurface: stale token=%d ignored',
      [aToken]));
    Exit;
  end;
  AndroidSetMainSurface(aToken, nil);
end;

function AndroidIsCurrentMainToken(aToken: Integer): Boolean;
begin
  gMainSurfaceLock.Enter;
  try
    Result := (aToken >= gMainSurfaceToken) and (not gMainReattachPending);
  finally
    gMainSurfaceLock.Leave;
  end;
end;

{ Called on the loop thread before asking Java to re-open the main window
  without decoration: suppresses detach/stop events of the old instance
  until the new instance's surface arrives. }
procedure AndroidBeginMainReattach;
begin
  gMainSurfaceLock.Enter;
  try
    gMainReattachPending := True;
  finally
    gMainSurfaceLock.Leave;
  end;
end;

procedure AndroidSetScreenMetrics(aToken: Integer; AWidthPx, AHeightPx: Integer; ADensity: Double);
var
  app: TfpgAndroidApplication;
  current: Boolean;
begin
  gMainSurfaceLock.Enter;
  try
    current := aToken >= gMainSurfaceToken;
  finally
    gMainSurfaceLock.Leave;
  end;
  if not current then
    Exit;   { stale metrics from a superseded main-window instance }

  if ADensity > 0 then
  begin
    gAndroidDensity := ADensity;
    gHiDPIScaleFactor := ADensity;
  end;
  if (AWidthPx > 0) and (AHeightPx > 0) then
  begin
    gAndroidPhysW := AWidthPx;
    gAndroidPhysH := AHeightPx;
    if gHiDPIScaleFactor >= 1.0 then
    begin
      gAndroidScreenW := Round(AWidthPx / gHiDPIScaleFactor);
      gAndroidScreenH := Round(AHeightPx / gHiDPIScaleFactor);
    end
    else
    begin
      gAndroidScreenW := AWidthPx;
      gAndroidScreenH := AHeightPx;
    end;
    gAndroidScreenValid := True;
  end;
  app := AndroidApplication;
  if app <> nil then
    app.EnqueueResizeEvent(AWidthPx, AHeightPx, ADensity);
end;

procedure AndroidSetSandboxPaths(const AFiles, ACache, AExternal: string);
begin
  gAndroidFilesDir := AFiles;
  gAndroidCacheDir := ACache;
  gAndroidExternalFilesDir := AExternal;
  AndroidLog(ANDROID_LOG_INFO, 'sandbox files=' + AFiles);
end;

procedure AndroidEnqueueTouch(AAction: Integer; AX, AY: Single; AButton: Integer);
var
  app: TfpgAndroidApplication;
begin
  if not gAndroidAppReady then
    Exit;
  app := AndroidApplication;
  if app = nil then
    Exit;
  app.EnqueueTouchEvent(AAction, Round(AX), Round(AY), AButton);
end;

procedure AndroidEnqueueHover(AX, AY: Single);
var
  app: TfpgAndroidApplication;
begin
  if not gAndroidAppReady then
    Exit;
  app := AndroidApplication;
  if app = nil then
    Exit;
  app.EnqueueHoverEvent(Round(AX), Round(AY));
end;

procedure AndroidEnqueueWheel(ADelta: Integer);
var
  app: TfpgAndroidApplication;
begin
  if not gAndroidAppReady then
    Exit;
  app := AndroidApplication;
  if app = nil then
    Exit;
  app.EnqueueWheelEvent(0, 0, ADelta);
end;

procedure AndroidEnqueueKey(AKeyCode, AAction, AModifiers: Integer; AUnicodeChar: LongWord);
var
  app: TfpgAndroidApplication;
begin
  if not gAndroidAppReady then
    Exit;
  app := AndroidApplication;
  if app = nil then
    Exit;
  app.EnqueueKeyEvent(AKeyCode, AAction, AModifiers, AUnicodeChar);
end;

procedure AndroidEnqueueText(const AText: string);
var
  app: TfpgAndroidApplication;
begin
  if not gAndroidAppReady then
    Exit;
  app := AndroidApplication;
  if app = nil then
    Exit;
  app.EnqueueTextEvent(AText);
end;

procedure AndroidEnqueueDelete(ABefore, AAfter: Integer);
var
  app: TfpgAndroidApplication;
begin
  if not gAndroidAppReady then
    Exit;
  app := AndroidApplication;
  if app = nil then
    Exit;
  if ABefore > 0 then
    app.EnqueueDeleteEvent(ANDROID_EV_DELETE_LEFT, ABefore);
  if AAfter > 0 then
    app.EnqueueDeleteEvent(ANDROID_EV_DELETE_RIGHT, AAfter);
end;

function AndroidHandleBack: Boolean;
var
  app: TfpgAndroidApplication;
  mw: TfpgWindowBase;
  top: TfpgWindowBase;
  mainWnd: TfpgWindowBase;
begin
  Result := False;
  app := AndroidApplication;
  if app = nil then
    Exit;
  { A modal dialog or a non-main focused window is open: consume Back by
    delivering Escape (fpGUI closes popups/dialogs on Escape). }
  mw := nil;
  if (fpgApplication <> nil) and (fpgApplication.TopModalForm <> nil) then
    mw := fpgApplication.TopModalForm.Window;
  top := nil;
  if gFocusedWinHandle <> nil then
    top := app.FindWindowByHandle(gFocusedWinHandle);
  mainWnd := nil;
  if (fpgApplication <> nil) and (fpgApplication.MainForm <> nil) then
    mainWnd := fpgApplication.MainForm.Window;
  if (mw <> nil) or ((top <> nil) and (top <> mainWnd)) then
  begin
    AndroidEnqueueKey(AKEYCODE_ESCAPE, 0, 0, 0);
    AndroidEnqueueKey(AKEYCODE_ESCAPE, 1, 0, 0);
    Result := True;
  end;
end;

procedure AndroidRequestStop;
var
  app: TfpgAndroidApplication;
begin
  app := AndroidApplication;
  if app <> nil then
    app.StopApplication;
end;

procedure AndroidAttachSubSurface(AId: Integer; aSurface: PANativeWindow);
var
  ch: PSubSurfaceChange;
begin
  if AId <= 0 then
  begin
    if aSurface <> nil then
      ANativeWindow_release(aSurface);
    Exit;
  end;
  New(ch);
  ch^.Id := AId;
  ch^.Surface := aSurface;
  gSubStateLock.Enter;
  try
    gSubSurfQueue.Add(ch);
  finally
    gSubStateLock.Leave;
  end;
  if AndroidApplication <> nil then
    AndroidApplication.WakeMainThread;
end;

procedure AndroidSubWindowDismissed(AId: Integer);
begin
  if AId <= 0 then
    Exit;
  gSubStateLock.Enter;
  try
    gDismissedSubWindows.Add(Pointer(PtrInt(AId)));
  finally
    gSubStateLock.Leave;
  end;
  if AndroidApplication <> nil then
    AndroidApplication.WakeMainThread;
end;

procedure AndroidEnqueueSubTouch(AId, AAction: Integer; AX, AY: Single; AButton: Integer);
var
  app: TfpgAndroidApplication;
begin
  if not gAndroidAppReady then
    Exit;
  app := AndroidApplication;
  if app = nil then
    Exit;
  app.EnqueueSubTouchEvent(AId, AAction, Round(AX), Round(AY), AButton);
end;

procedure AndroidEnqueueSubHover(AId: Integer; AX, AY: Single);
var
  app: TfpgAndroidApplication;
begin
  if not gAndroidAppReady then
    Exit;
  app := AndroidApplication;
  if app = nil then
    Exit;
  app.EnqueueSubHoverEvent(AId, Round(AX), Round(AY));
end;

procedure AndroidEnqueueSubWheel(AId, ADelta: Integer);
var
  app: TfpgAndroidApplication;
begin
  if not gAndroidAppReady then
    Exit;
  app := AndroidApplication;
  if app = nil then
    Exit;
  app.EnqueueSubWheelEvent(AId, ADelta);
end;

{ ---- Freeform secondary-window events (Java UI thread -> loop) --------- }

procedure AndroidEnqueueWindowBounds(AId, AX, AY, AW, AH: Integer);
var
  app: TfpgAndroidApplication;
begin
  if not gAndroidAppReady then
    Exit;
  app := AndroidApplication;
  if app = nil then
    Exit;
  app.EnqueueWindowBoundsEvent(AId, AX, AY, AW, AH);
end;

procedure AndroidEnqueueWindowClosed(AId: Integer);
var
  app: TfpgAndroidApplication;
begin
  if not gAndroidAppReady then
    Exit;
  app := AndroidApplication;
  if app = nil then
    Exit;
  app.EnqueueWindowStateEvent(AId, 4);
end;

procedure AndroidEnqueueWindowFocused(AId: Integer);
var
  app: TfpgAndroidApplication;
begin
  if not gAndroidAppReady then
    Exit;
  app := AndroidApplication;
  if app = nil then
    Exit;
  app.EnqueueWindowStateEvent(AId, 5);
end;

procedure AndroidEnqueueWindowRepaint(AId: Integer);
var
  app: TfpgAndroidApplication;
begin
  if not gAndroidAppReady then
    Exit;
  app := AndroidApplication;
  if app = nil then
    Exit;
  app.EnqueueWindowStateEvent(AId, 6);
end;

procedure AndroidEnqueueSubKey(AId, AKeyCode, AAction, AModifiers: Integer; AUnicodeChar: LongWord);
var
  app: TfpgAndroidApplication;
begin
  if not gAndroidAppReady then
    Exit;
  app := AndroidApplication;
  if app = nil then
    Exit;
  app.EnqueueSubKeyEvent(AId, AKeyCode, AAction, AModifiers, AUnicodeChar);
end;

procedure AndroidEnqueueSubText(AId: Integer; const AText: string);
var
  app: TfpgAndroidApplication;
begin
  if not gAndroidAppReady then
    Exit;
  app := AndroidApplication;
  if app = nil then
    Exit;
  app.EnqueueSubTextEvent(AId, AText);
end;

procedure AndroidEnqueueSubDelete(AId, ABefore, AAfter: Integer);
var
  app: TfpgAndroidApplication;
begin
  if not gAndroidAppReady then
    Exit;
  app := AndroidApplication;
  if app = nil then
    Exit;
  if ABefore > 0 then
    app.EnqueueSubDeleteEvent(AId, ANDROID_EV_DELETE_LEFT, ABefore);
  if AAfter > 0 then
    app.EnqueueSubDeleteEvent(AId, ANDROID_EV_DELETE_RIGHT, AAfter);
end;

initialization
  gMainSurfaceLock := TCriticalSection.Create;
  gAppStartLock := TCriticalSection.Create;
  gRetiredSurfaces := TList.Create;
  gSubStateLock := TCriticalSection.Create;
  gSubSurfQueue := TList.Create;
  gDismissedSubWindows := TList.Create;

finalization
  FreeAndNil(gSubSurfQueue);
  FreeAndNil(gDismissedSubWindows);
  FreeAndNil(gSubStateLock);
  FreeAndNil(gRetiredSurfaces);
  FreeAndNil(gMainSurfaceLock);
  FreeAndNil(gAppStartLock);

end.
