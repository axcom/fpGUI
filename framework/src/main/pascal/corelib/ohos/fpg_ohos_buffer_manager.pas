{
    This unit is part of the fpGUI Toolkit project.

    Copyright (c) 2026 by Graeme Geldenhuys.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      HarmonyOS platform implementation of IBufferManager for the hybrid
      canvas. Manages a pixel buffer and writes it to the native window
      surface via the native_window API.
}

unit fpg_ohos_buffer_manager;

{$mode objfpc}{$H+}

interface

uses
  CTypes,
  fpg_impl,
  fpg_base;

type

  { TOhosBufferManager - Manages a pixel buffer and flushes it
    to a HarmonyOS native window surface }

  TOhosBufferManager = class(TInterfacedObject, IBufferManager)
  private
    FWinHandle: TfpgWinHandle;  { OHNativeWindow* }
    FBuffer: Pointer;
    FBufWidth: Integer;
    FBufHeight: Integer;
    FStride: Integer;
    FWindowW: Integer;          { physical window size at creation, for flush clamping }
    FWindowH: Integer;
    { Cached mmap — avoids mmap/munmap on every frame }
    FMappedAddr: Pointer;       { cached mmap address, nil = not mapped }
    FMappedSize: LongWord;      { size of the current mapping }
    FMappedFd: Integer;         { buffer fd, -1 = invalid }
    { 首帧已上屏标志：第一次成功 FlushBuffer 后置位，并调用
      OhosNotifyFirstFrame 通知 ETS 打开 XComponent 显示门（contentReady）。
      AttachWindow 检测到 native 窗口句柄变化（hide→show 时 ETS 重建
      XComponent→新 surface→新 OHNativeWindow 句柄）时重置为 False，
      使重新显示后的首帧再次通知开门（与非 AGG TfpgOhosCanvas.FFirstFrameSent
      在 DoSetWindowVisible(True) 重置同效）。 }
    FFirstFrameSent: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    { IBufferManager }
    procedure AttachWindow(AWindow: TfpgWindowBase);
    procedure DetachWindow;
    procedure AllocateBuffer(AWidth, AHeight: Integer;
      out AData: Pointer; out AStride: Integer);
    function  BufferAllocated: Boolean;
    procedure FreeBuffer;
    procedure   PutBufferToScreen(x, y, w, h: TfpgCoord);
    procedure   UnmapCachedAddr;
    procedure   RestoreFromBuffer(const ARect: TfpgRect);
  end;


function CreateOhosBufferManager: IBufferManager;


implementation

uses
  baseunix, sysutils,
  unix,
  fpg_main,
  fpg_ohos_nativewindow,
  fpg_ohos;

{ NOTE: fpmmap, fpmunmap, OH_NativeWindow_* functions, and PBufferHandle/TOH_Region
  types are declared in fpg_ohos_nativewindow.pas (moved out of fpg_ohos.pas). }

const
  NATIVE_WINDOW_PROT_READ  = 1;
  NATIVE_WINDOW_PROT_WRITE = 2;
  NATIVE_WINDOW_MAP_SHARED = 1;


{ TOhosBufferManager }

constructor TOhosBufferManager.Create;
begin
  inherited Create;
  FWinHandle   := nil;
  FBuffer      := nil;
  FBufWidth    := 0;
  FBufHeight   := 0;
  FStride      := 0;
  FMappedAddr  := nil;
  FMappedSize  := 0;
  FMappedFd    := -1;
end;

destructor TOhosBufferManager.Destroy;
begin
  FreeBuffer;
  inherited Destroy;
end;

procedure TOhosBufferManager.AttachWindow(AWindow: TfpgWindowBase);
var
  win: TfpgOhosWindow;
begin
  win := TfpgOhosWindow(AWindow);
  
  { 检测 native 窗口句柄变化：hide→show 时 ETS 重建 XComponent→新 surface
    →新 OHNativeWindow 句柄。句柄变化意味着新的显示门（contentReady 回 false），
    重置 FFirstFrameSent 使重新显示后的首帧 FlushBuffer 再次通知 ETS 开门。
    句柄未变（同窗口逐帧 Attach）则不重置，避免每帧重复通知。 }
  if FWinHandle <> win.WinHandle then
    FFirstFrameSent := False;
  { 消费 DoSetWindowVisible(True) 置位的重置请求：覆盖 hide→show 句柄未变但
    contentReady 回 false 的场景（与非 AGG TfpgOhosCanvas 同效）。 }
  if win.FirstFrameResetPending then
  begin
    FFirstFrameSent := False;
    win.FirstFrameResetPending := False;
  end;
  
  FWinHandle := win.WinHandle;
  FWindowW := win.PhysicalWidth;
  FWindowH := win.PhysicalHeight;
end;

procedure TOhosBufferManager.DetachWindow;
begin
  UnmapCachedAddr;
  FWinHandle := nil;
end;

procedure TOhosBufferManager.AllocateBuffer(AWidth, AHeight: Integer;
  out AData: Pointer; out AStride: Integer);
var
  newStride: Integer;
begin
  newStride := AWidth * 4;

  { Use GetMem for AggPas software rendering.
    OH_Drawing_BitmapBuild allocates GPU memory, but AggPas writes via
    CPU and the GPU memory may not be CPU-cache-coherent, causing the
    flushed content to be invisible (stale GPU data). }
  if not BufferAllocated then
  begin
    FBufWidth  := AWidth;
    FBufHeight := AHeight;
    FStride    := newStride;
    FBuffer    := GetMem(FBufHeight * FStride);
  end;
  { else: keep existing buffer }

  AData   := FBuffer;
  AStride := FStride;
end;

function TOhosBufferManager.BufferAllocated: Boolean;
begin
  Result := FBuffer <> nil;
end;

procedure TOhosBufferManager.FreeBuffer;
begin
  UnmapCachedAddr;
  if FBuffer <> nil then
  begin
    FreeMem(FBuffer);
    FBuffer := nil;
  end;
  FBufWidth  := 0;
  FBufHeight := 0;
  FStride    := 0;
end;

{ Unmap the cached native window buffer mapping, if any. }
procedure TOhosBufferManager.UnmapCachedAddr;
begin
  if FMappedAddr <> nil then
  begin
    fpmunmap(FMappedAddr, FMappedSize);
    FMappedAddr := nil;
  end;
  FMappedSize := 0;
  FMappedFd   := -1;
end;

procedure TOhosBufferManager.PutBufferToScreen(x, y, w, h: TfpgCoord);
var
  nativeBuf: Pointer;
  fence: Int32;
  hdl: PBufferHandle;
  region: TOH_Region;
  dstStride, copyW, copyH, i: Int32;
  srcOfs: Int32;
  scale: Double;
  physX, physY, physW, physH: Integer;
  sizeMismatch: Boolean;
  bg: LongWord;
  addr: Pointer;
  regRect: TOH_Region_Rect;
{  caretWidget: TfpgWidgetBase;
  caretRect: TfpgRect;
  dx, dy: TfpgCoord;
  widgetX, widgetY, widgetW, widgetH: Integer; }
begin
  if (FWinHandle = nil) or (FBuffer = nil) then
    Exit;
  if (w <= 0) or (h <= 0) then
    Exit;
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
  scale := gHiDPIScaleFactor;
  if scale < 1.0 then scale := 1.0;
  physX := Round(x * scale);
  physY := Round(y * scale);
  physW := Round(w * scale);
  physH := Round(h * scale);

  FillChar(region, SizeOf(region), 0);
  
  { ── 申请 buffer（RequestBuffer 替代 LockBuffer——API 20+ 已移除 LockBuffer） ── }
  nativeBuf := nil;
  fence := -1;
  if OH_NativeWindow_NativeWindowRequestBuffer(FWinHandle, @nativeBuf, @fence) <> 0 then
    Exit;

  hdl := OH_NativeWindow_GetBufferHandleFromNative(nativeBuf);
  if hdl = nil then
  begin
    OH_NativeWindow_NativeWindowAbortBuffer(FWinHandle, nativeBuf);
    Exit;
  end;

  { ★ buffer 池几何滞后判定。
    判据必须是 FWindowW/H vs hdl，不能是 FBufW vs hdl —— AllocPhysicalBuffer
    故意分配 PhysicalWidth + ResizeThreshold(50) 且只增不减
    （fpg_ohos_hybrid_canvas.pas:254 / :283），FBufW 恒 > hdl^.width，
    用它判会永远失配 → AGG 每帧 skip → 永远黑屏。
    FWindowW/H 由 AttachWindow 每帧从 win.PhysicalWidth 刷新。 }
  { ≤1px 视为匹配（与非 AGG 路径一致）：bitmap 由逻辑尺寸×scale 往返可能有
    1px 取整差，拷贝按 hdl 夹紧，不应触发失配丢帧/RepaintHelper 重试。 }
  sizeMismatch := (FWindowW > 0) and (FWindowH > 0) and
                  ((Abs(FWindowW - Integer(hdl^.width)) > 1) or
                   (Abs(FWindowH - Integer(hdl^.height)) > 1));
  if sizeMismatch then
  begin
    if fpgApplication is TfpgOhosApplication then
      TfpgOhosApplication(fpgApplication).ScheduleRepaintHelper(FWinHandle);
    if FFirstFrameSent then
    begin
      OH_NativeWindow_NativeWindowAbortBuffer(FWinHandle, nativeBuf);
      if fence >= 0 then
        fpclose(fence);   { ★ RequestBuffer 输出的 fence fd，不关则每 60ms 重试泄一个 }
      Exit;
    end;
  end
  else if fpgApplication is TfpgOhosApplication then
    { ★ 几何已追上 → 停掉重试 }
    TfpgOhosApplication(fpgApplication).CancelRepaintHelper(FWinHandle);

  { ★ caret 存在时扩为全窗刷新。只 FillChar(region) 却未扩拷贝区 → 空操作。
    对齐非 AGG TfpgOhosCanvas.DoPutBufferToScreen（fpg_ohos.pas:2702-2705）。 }
  if Assigned(fpgCaret) and (fpgCaret.Canvas <> nil) then
  begin
    physX := 0;
    physY := 0;
    physW := Integer(hdl^.width);
    physH := Integer(hdl^.height);
  end;
  
  addr := fpmmap(nil, hdl^.size, NATIVE_WINDOW_PROT_READ or NATIVE_WINDOW_PROT_WRITE,
    NATIVE_WINDOW_MAP_SHARED, hdl^.fd, 0);
  if addr = Pointer(-1) then
  begin
    OH_NativeWindow_NativeWindowAbortBuffer(FWinHandle, nativeBuf);
    Exit;
  end;

  { 首帧失配兜底：先按窗口背景色填满目标 buffer，避免露出未初始化内容。
    对照非 AGG 版 fpg_ohos.pas:2777-2789。仅首帧失配会走到此处。 }
  if sizeMismatch then
  begin
    bg := PLongWord(FBuffer)^;
    FillDWord(addr^, hdl^.size div 4, bg);
  end;

  dstStride := hdl^.stride;

  { ★ 提交区域先夹到目标 buffer，再算拷贝量 }
  if physX < 0 then physX := 0;
  if physY < 0 then physY := 0;
  if physX + physW > Integer(hdl^.width)  then physW := Integer(hdl^.width)  - physX;
  if physY + physH > Integer(hdl^.height) then physH := Integer(hdl^.height) - physY;
  // 边界检查
  copyW := physW * 4;
  if copyW > dstStride - physX * 4 then copyW := dstStride - physX * 4;
  if (physX * 4 + copyW) > FStride then copyW := FStride - physX * 4;
  copyH := physH;
  if copyH > hdl^.height - physY then copyH := hdl^.height - physY;
  { Clamp source rows to our software buffer: if the window grew between
    BeginDraw and EndDraw, physH can exceed FBufHeight and the Move below
    would read past the end of FBuffer. }
  if (physY + copyH) > FBufHeight then copyH := FBufHeight - physY;
  if (copyW <= 0) or (copyH <= 0) then
  begin
    fpmunmap(addr, hdl^.size);
    OH_NativeWindow_NativeWindowAbortBuffer(FWinHandle, nativeBuf);
    Exit;
  end;

  // 执行拷贝
  srcOfs := physY * FStride + physX * 4;
  for i := 0 to copyH - 1 do
    Move(PByte(FBuffer)[srcOfs + i * FStride],
         PByte(addr)[(physY + i) * dstStride + physX * 4], copyW);

  fpmunmap(addr, hdl^.size);

  { ★ region 必须等于实际拷贝矩形（置于 copyW/copyH 夹紧之后）。
    缺陷：caret 分支 FillChar 使 region.rects=nil，其后无条件
    region.rectNumber := 1 → 合成器解引用空指针（点过编辑框后每次 flush 必中）。 }
  regRect.x := physX;
  regRect.y := physY;
  regRect.w := copyW div 4;   { copyW 是字节数 → region 要像素数 }
  regRect.h := copyH;
  region.rects     := @regRect;
  region.rectNumber := 1;
{  fpGUI_Hilog(LOG_INFO, format('AGG PutBuf: win=%dx%d hdl=%dx%d phys=%d,%d %dx%d copy=%dx%d ff=%d',
    [FWindowW, FWindowH, hdl^.width, hdl^.height, physX, physY, physW, physH,
     copyW div 4, copyH, Ord(FFirstFrameSent)]));}
     
  OH_NativeWindow_NativeWindowFlushBuffer(FWinHandle, nativeBuf, fence, region);

  { 首帧上屏通知：AGG 混合画布路径首次成功 FlushBuffer 后告知 ETS 打开
    XComponent 显示门（contentReady）。缺失此通知时 ETS firstFrameArrived 恒
    false → XComponent opacity=0 → 窗口只显示页面背景（内容不可见）。
    FFirstFrameSent 由 AttachWindow 在 native 句柄变化时重置（hide→show 再通知）。
    多发无害：ETS onFirstFrame 命中 contentReady=true 时自检直接 return。 }
  if not FFirstFrameSent then
  begin
    FFirstFrameSent := True;
    if Assigned(_notify_first_frame) then
      _notify_first_frame(FWinHandle);
  end;  
end;

procedure TOhosBufferManager.RestoreFromBuffer(const ARect: TfpgRect);
begin
  { Blit ARect from the off-screen buffer directly to the OS window.
    Calls PutBufferToScreen for the given rectangle. }
  //OHOS 无 Expose 事件，本方法休眠；语义与 GDI/X11 一致——从完整 backbuffer blit 区域  
  if BufferAllocated then
    PutBufferToScreen(ARect.Left, ARect.Top, ARect.Width, ARect.Height);
end;

function CreateOhosBufferManager: IBufferManager;
begin
  Result := TOhosBufferManager.Create;
end;

end.
