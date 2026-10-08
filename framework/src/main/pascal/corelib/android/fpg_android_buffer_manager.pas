{
    fpGUI  -  Free Pascal GUI Toolkit

    Copyright (c) 2026 See the file AUTHORS.txt, included in this
    distribution, for details of the copyright.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      Android implementation of IBufferManager for the AGG hybrid canvas.

      Single-surface model (see DESIGN.zh-CN.md):
        * One global "screen buffer" holds the pixels of the activity
          SurfaceView at physical resolution.
        * The MAIN window's buffer manager hands that buffer to its canvas,
          so the main form paints directly into the screen buffer; its
          PutBufferToScreen simply presents (lock -> full copy -> post).
        * Secondary windows (dialogs, popups) have their own off-screen
          buffer; their PutBufferToScreen composites the window pixels into
          the screen buffer at the window origin and then presents.

      All of this runs on the Pascal loop thread; the Java UI thread only
      touches the ANativeWindow hand-off in fpg_android.pas.
}

unit fpg_android_buffer_manager;

{$I fpg_defines.inc}

interface

uses
  CTypes,
  fpg_impl,
  fpg_base,
  fpg_android_ndk;

type
  TAndroidBufferManager = class(TInterfacedObject, IBufferManager)
  private
    FWindow: TfpgWindowBase;
    FIsMain: Boolean;
    FBuffer: Pointer;
    FBufWidth: Integer;     { physical }
    FBufHeight: Integer;
    FStride: Integer;       { bytes }
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
    procedure PutBufferToScreen(x, y, w, h: TfpgCoord);
    procedure RestoreFromBuffer(const ARect: TfpgRect);
  end;

{ Global screen state. The surface pointer is set by the application
  (AndroidSetMainSurface); the screen buffer is (re)allocated lazily. }
procedure AndroidScreenAttach(aSurface: PANativeWindow);
procedure AndroidScreenDetach;
function  AndroidScreenSurface: PANativeWindow;
function  AndroidScreenPixel(AX, AY: Integer): TfpgColor;

function CreateAndroidBufferManager: IBufferManager;

implementation

uses
  Classes,
  SysUtils,
  fpg_main,
  fpg_widget,
  fpg_android;

var
  gScreenSurface: PANativeWindow = nil;
  gScreenBuffer: Pointer = nil;
  gScreenW: Integer = 0;         { physical pixels }
  gScreenH: Integer = 0;
  gScreenStride: Integer = 0;    { bytes per row }
  { Registry of secondary-window buffer managers (creation order). The
    screen compositor re-blends every visible one over the screen buffer on
    EVERY present: the main window repaints clear the whole surface (fpGUI
    forms clear their full canvas on any child invalidation), which would
    otherwise erase overlaid dialogs/popups. }
  gSubManagers: TList = nil;
  { True when the surface buffers turned out not to be CPU-mappable and the
    frame is handed to the Java Canvas presenter instead. Re-detected for
    every new surface. }
  gScreenUseJavaPresenter: Boolean = False;
  { Tightly packed staging copy for the Java presenter (only used when the
    screen buffer stride differs from the surface width). }
  gStaging: Pointer = nil;
  gStagingSize: Integer = 0;

const
  ANDROID_PAGE_SIZE = 4096;

{ mincore: reports whether the pages at ADDR are mapped in this process.
  Used to validate ANativeWindow_lock's buffer pointer BEFORE touching it -
  some emulators (host-side GL translation) return success with a buffer
  whose CPU mapping lives in another address space, and writing it faults. }
function fpm_mincore(addr: Pointer; length: PtrUInt; vec: PByte): cint;
  cdecl; external 'c' name 'mincore';

function LockedBitsMapped(bits: Pointer): Boolean;
var
  vec: array[0..0] of Byte;
begin
  Result := False;
  if bits = nil then
    Exit;
  Result := fpm_mincore(bits, ANDROID_PAGE_SIZE, @vec[0]) = 0;
end;

procedure AndroidScreenAttach(aSurface: PANativeWindow);
begin
  gScreenSurface := aSurface;
  { A new surface may be mappable again (e.g. activity re-created in another
    rendering mode): re-run detection on the first present. }
  gScreenUseJavaPresenter := False;
end;

procedure AndroidScreenDetach;
begin
  gScreenSurface := nil;
end;

function AndroidScreenSurface: PANativeWindow;
begin
  Result := gScreenSurface;
end;

function EnsureScreenBuffer(AW, AH: Integer): Pointer;
begin
  if AW < 1 then
    AW := 1;
  if AH < 1 then
    AH := 1;
  if (gScreenBuffer <> nil) and (gScreenW >= AW) and (gScreenH >= AH) then
    Exit(gScreenBuffer);
  if gScreenBuffer <> nil then
    FreeMem(gScreenBuffer);
  gScreenW := AW;
  gScreenH := AH;
  gScreenStride := AW * 4;
  gScreenBuffer := GetMem(gScreenStride * gScreenH);
  FillChar(gScreenBuffer^, gScreenStride * gScreenH, $FF);
  AndroidLog(ANDROID_LOG_INFO, Format('ScreenBuffer allocated: %dx%d stride=%d',
    [gScreenW, gScreenH, gScreenStride]));
  Result := gScreenBuffer;
end;

function ScreenBufferWidth: Integer;
begin
  Result := gScreenW;
end;

function ScreenBufferHeight: Integer;
begin
  Result := gScreenH;
end;

function AndroidScreenPixel(AX, AY: Integer): TfpgColor;
var
  px: PByte;
begin
  Result := 0;
  if (gScreenBuffer = nil) or (AX < 0) or (AY < 0) or
     (AX >= gScreenW) or (AY >= gScreenH) then
    Exit;
  px := PByte(gScreenBuffer) + AY * gScreenStride + AX * 4;
  Result := (TfpgColor($FF) shl 24) or (TfpgColor(px[2]) shl 16) or
            (TfpgColor(px[1]) shl 8) or TfpgColor(px[0]);
end;

{ Present the screen buffer via the Java Canvas path: compact the rows
  into a tightly packed staging buffer (the screen buffer may be wider
  than the surface) and hand it to the bridge hook. }
procedure PresentScreenViaJava;
var
  surfW, surfH, rowBytes, y: Integer;
  src, dst: PByte;
begin
  if (gScreenSurface = nil) or (gScreenBuffer = nil) then
    Exit;
  if not Assigned(AndroidPresentFrameProc) then
    Exit;
  surfW := ANativeWindow_getWidth(gScreenSurface);
  surfH := ANativeWindow_getHeight(gScreenSurface);
  if surfW < 1 then
    surfW := gScreenW;
  if surfH < 1 then
    surfH := gScreenH;
  if (surfW > gScreenW) then
    surfW := gScreenW;
  if (surfH > gScreenH) then
    surfH := gScreenH;
  if (surfW < 1) or (surfH < 1) then
    Exit;

  if gScreenStride = surfW * 4 then
  begin
    { Already tightly packed. }
    AndroidPresentFrameProc(gScreenBuffer, surfW, surfH);
    Exit;
  end;

  if (gStaging = nil) or (gStagingSize < surfW * surfH * 4) then
  begin
    if gStaging <> nil then
      FreeMem(gStaging);
    gStagingSize := surfW * surfH * 4;
    gStaging := GetMem(gStagingSize);
  end;
  src := PByte(gScreenBuffer);
  dst := PByte(gStaging);
  rowBytes := surfW * 4;
  for y := 0 to surfH - 1 do
  begin
    Move(src^, dst^, rowBytes);
    Inc(src, gScreenStride);
    Inc(dst, rowBytes);
  end;
  AndroidPresentFrameProc(gStaging, surfW, surfH);
end;

{ Present the whole screen buffer to the surface. Must run on the loop
  thread. The locked BufferQueue buffer can differ in size from our
  assumed geometry; uncovered pixels are filled with the screen
  background so no stale/undefined content is ever posted.

  If the locked buffer is not CPU-mappable (detected with mincore before
  writing - some emulators use host-side GL buffers), the native path is
  abandoned and every later frame goes through the Java Canvas presenter. }
procedure PresentScreen;
var
  nativeBuf: TANativeWindowBuffer;
  dst: PByte;
  src: PByte;
  dstStride: Integer;
  rowBytes: Integer;
  y: Integer;
  copyH: Integer;
  fill: LongWord;
begin
  if (gScreenSurface = nil) or (gScreenBuffer = nil) or (gScreenW < 1) or (gScreenH < 1) then
    Exit;

  { Configured Java presenter, or auto-switched earlier (see below). }
  if gAndroidUseJavaPresenter or gScreenUseJavaPresenter then
  begin
    PresentScreenViaJava;
    Exit;
  end;

  if not gScreenUseJavaPresenter then
  begin
    if ANativeWindow_lock(gScreenSurface, @nativeBuf, nil) = 0 then
    begin
      if LockedBitsMapped(nativeBuf.Bits) and
         (nativeBuf.Width >= 1) and (nativeBuf.Height >= 1) then
      begin
        try
          dstStride := nativeBuf.Stride * 4;
          dst := PByte(nativeBuf.Bits);

          { Fill first: covers any area the screen buffer does not reach. }
          fill := PLongWord(gScreenBuffer)^;
          FillDWord(dst^, nativeBuf.Stride * nativeBuf.Height, fill);

          rowBytes := nativeBuf.Width * 4;
          if rowBytes > gScreenStride then
            rowBytes := gScreenStride;
          if nativeBuf.Height < gScreenH then
            copyH := nativeBuf.Height
          else
            copyH := gScreenH;
          src := PByte(gScreenBuffer);
          for y := 0 to copyH - 1 do
          begin
            Move(src^, dst^, rowBytes);
            Inc(src, gScreenStride);
            Inc(dst, dstStride);
          end;
        finally
          ANativeWindow_unlockAndPost(gScreenSurface);
        end;
        Exit;   { native presentation succeeded }
      end;

      { Lock succeeded but the buffer cannot be reached by the CPU
        (host-side GL emulators). Release it and switch to Java. }
      ANativeWindow_unlockAndPost(gScreenSurface);
      gScreenUseJavaPresenter := True;
      AndroidLog(ANDROID_LOG_WARN,
        'surface buffer is not CPU-mappable; using the Java Canvas presenter');
    end
    else
      Exit;   { transient lock failure - retry next frame }
  end;

  PresentScreenViaJava;
end;

{ Copy a physical rectangle from a source buffer into the screen buffer. }
procedure CompositeRect(ASrc: Pointer; ASrcStride, ASrcW, ASrcH,
  ADstX, ADstY: Integer);
var
  copyW, copyH, sx, sy, y: Integer;
  src, dst: PByte;
begin
  if (ASrc = nil) or (gScreenBuffer = nil) then
    Exit;
  sx := 0;
  sy := 0;
  copyW := ASrcW;
  copyH := ASrcH;
  if ADstX < 0 then
  begin
    Inc(sx, -ADstX);
    Dec(copyW, -ADstX);
    ADstX := 0;
  end;
  if ADstY < 0 then
  begin
    Inc(sy, -ADstY);
    Dec(copyH, -ADstY);
    ADstY := 0;
  end;
  if ADstX + copyW > gScreenW then
    copyW := gScreenW - ADstX;
  if ADstY + copyH > gScreenH then
    copyH := gScreenH - ADstY;
  if (copyW < 1) or (copyH < 1) then
    Exit;
  if sx + copyW > ASrcW then
    copyW := ASrcW - sx;
  if (copyW < 1) or (copyH < 1) then
    Exit;
  src := PByte(ASrc) + sy * ASrcStride + sx * 4;
  dst := PByte(gScreenBuffer) + ADstY * gScreenStride + ADstX * 4;
  for y := 0 to copyH - 1 do
  begin
    Move(src^, dst^, copyW * 4);
    Inc(src, ASrcStride);
    Inc(dst, gScreenStride);
  end;
end;

{ Z-order position of a manager's window (for the compositor). }
function SubManagerZIndex(AMgr: TAndroidBufferManager): Integer;
var
  app: TfpgAndroidApplication;
begin
  Result := MaxInt;
  app := AndroidApplication;
  if (app <> nil) and (AMgr.FWindow <> nil) then
    Result := app.WindowZIndex(AMgr.FWindow);
end;

{ Blend one secondary window's buffer over the screen buffer.
  Only the window's own rectangle is composited: the canvas buffer carries
  a paint-slack threshold (window size + 50 logical px) which is filled
  white and must not appear on screen. }
procedure CompositeSubWindow(AMgr: TAndroidBufferManager);
var
  sf: Double;
  dstX, dstY, copyW, copyH: Integer;
begin
  if (AMgr.FBuffer = nil) or (AMgr.FWindow = nil) then
    Exit;
  { Floating windows own their surface - never composite them. }
  if (AMgr.FWindow is TfpgAndroidWindow) and
     TfpgAndroidWindow(AMgr.FWindow).HasSubSurface then
    Exit;
  if not (AMgr.FWindow.PrimaryWidget is TfpgWidget) then
    Exit;
  if not TfpgWidget(AMgr.FWindow.PrimaryWidget).Visible then
    Exit;
  sf := gHiDPIScaleFactor;
  if sf < 1.0 then
    sf := 1.0;
  dstX := Round(AMgr.FWindow.Left * sf);
  dstY := Round(AMgr.FWindow.Top * sf);
  copyW := Round(AMgr.FWindow.Width * sf);
  copyH := Round(AMgr.FWindow.Height * sf);
  if copyW > AMgr.FBufWidth then
    copyW := AMgr.FBufWidth;
  if copyH > AMgr.FBufHeight then
    copyH := AMgr.FBufHeight;
  if (copyW < 1) or (copyH < 1) then
    Exit;
  CompositeRect(AMgr.FBuffer, AMgr.FStride, copyW, copyH, dstX, dstY);
end;

{ Present a floating window's buffer into its own popup view (Java canvas
  presenter). The buffer may carry a paint-slack threshold (+50 logical px)
  and its row stride may be wider than the window: only the window's
  rectangle is presented, compacted to stride = width*4. }
procedure PresentSubWindowSurface(AMgr: TAndroidBufferManager);
var
  aw: TfpgAndroidWindow;
  sf: Double;
  w, h, rowBytes, y: Integer;
  src, dst: PByte;
begin
  if not Assigned(AndroidPresentSubFrameProc) then
    Exit;
  if not (AMgr.FWindow is TfpgAndroidWindow) then
    Exit;
  aw := TfpgAndroidWindow(AMgr.FWindow);
  if (aw.SubWindowId <= 0) or (AMgr.FBuffer = nil) then
    Exit;
  sf := gHiDPIScaleFactor;
  if sf < 1.0 then
    sf := 1.0;
  w := Round(aw.Width * sf);
  h := Round(aw.Height * sf);
  if w > AMgr.FBufWidth then
    w := AMgr.FBufWidth;
  if h > AMgr.FBufHeight then
    h := AMgr.FBufHeight;
  if (w < 1) or (h < 1) then
    Exit;

  if AMgr.FStride = w * 4 then
  begin
    AndroidPresentSubFrameProc(aw.SubWindowId, AMgr.FBuffer, w, h);
    Exit;
  end;

  if (gStaging = nil) or (gStagingSize < w * h * 4) then
  begin
    if gStaging <> nil then
      FreeMem(gStaging);
    gStagingSize := w * h * 4;
    gStaging := GetMem(gStagingSize);
  end;
  rowBytes := w * 4;
  src := PByte(AMgr.FBuffer);
  dst := PByte(gStaging);
  for y := 0 to h - 1 do
  begin
    Move(src^, dst^, rowBytes);
    Inc(src, AMgr.FStride);
    Inc(dst, rowBytes);
  end;
  AndroidPresentSubFrameProc(aw.SubWindowId, gStaging, w, h);
end;

{ Re-blend all visible secondary windows, bottom to top (z-order). }
procedure RecompositeSubWindows;
var
  i, j, best: Integer;
  m, bm: TAndroidBufferManager;
  used: array of Boolean;
begin
  if (gSubManagers = nil) or (gSubManagers.Count = 0) then
    Exit;
  SetLength(used, gSubManagers.Count);
  for i := 0 to gSubManagers.Count - 1 do
  begin
    best := -1;
    bm := nil;
    for j := 0 to gSubManagers.Count - 1 do
    begin
      if used[j] then
        Continue;
      m := TAndroidBufferManager(gSubManagers[j]);
      if bm = nil then
      begin
        best := j;
        bm := m;
        Continue;
      end;
      if SubManagerZIndex(m) < SubManagerZIndex(bm) then
      begin
        best := j;
        bm := m;
      end;
    end;
    if (best < 0) or (bm = nil) then
      Break;
    used[best] := True;
    CompositeSubWindow(bm);
  end;
end;

{ TAndroidBufferManager }

constructor TAndroidBufferManager.Create;
begin
  inherited Create;
  FWindow := nil;
  FIsMain := False;
  FBuffer := nil;
  FBufWidth := 0;
  FBufHeight := 0;
  FStride := 0;
end;

destructor TAndroidBufferManager.Destroy;
begin
  if gSubManagers <> nil then
    gSubManagers.Remove(Self);
  FreeBuffer;
  inherited Destroy;
end;

procedure TAndroidBufferManager.AttachWindow(AWindow: TfpgWindowBase);
var
  aw: TfpgAndroidWindow;
begin
  FWindow := AWindow;
  if AWindow is TfpgAndroidWindow then
  begin
    aw := TfpgAndroidWindow(AWindow);
    FIsMain := aw.IsMain;
  end
  else
    FIsMain := False;
  { Secondary windows join the screen compositor registry. }
  if (not FIsMain) and (gSubManagers <> nil) and
     (gSubManagers.IndexOf(Self) < 0) then
    gSubManagers.Add(Self);
end;

procedure TAndroidBufferManager.DetachWindow;
begin
  FWindow := nil;
  if gSubManagers <> nil then
    gSubManagers.Remove(Self);
end;

procedure TAndroidBufferManager.AllocateBuffer(AWidth, AHeight: Integer;
  out AData: Pointer; out AStride: Integer);
var
  surfW, surfH: Integer;
  wantW, wantH: Integer;
begin
  if FIsMain then
  begin
    { The main window paints straight into the screen buffer.
      IMPORTANT: honour the caller's requested size (canvas asks for the
      window size + a paint-slack threshold and later FillChar()s the whole
      requested geometry): the screen buffer must be at least as large as
      BOTH the request and the surface, otherwise the canvas writes past
      the end of the buffer (SIGSEGV_ACCERR, seen on the first frame). }
    wantW := AWidth;
    wantH := AHeight;
    if gScreenSurface <> nil then
    begin
      surfW := ANativeWindow_getWidth(gScreenSurface);
      surfH := ANativeWindow_getHeight(gScreenSurface);
      if surfW > wantW then
        wantW := surfW;
      if surfH > wantH then
        wantH := surfH;
    end;
    FBuffer := EnsureScreenBuffer(wantW, wantH);
    FBufWidth := gScreenW;
    FBufHeight := gScreenH;
    FStride := gScreenStride;
  end
  else
  begin
    if AWidth < 1 then
      AWidth := 1;
    if AHeight < 1 then
      AHeight := 1;
    if (FBuffer = nil) or (FBufWidth < AWidth) or (FBufHeight < AHeight) then
    begin
      if FBuffer <> nil then
        FreeMem(FBuffer);
      FBufWidth := AWidth;
      FBufHeight := AHeight;
      FStride := AWidth * 4;
      FBuffer := GetMem(FStride * FBufHeight);
      FillChar(FBuffer^, FStride * FBufHeight, 0);
    end;
  end;
  AData := FBuffer;
  AStride := FStride;
end;

function TAndroidBufferManager.BufferAllocated: Boolean;
begin
  Result := FBuffer <> nil;
end;

procedure TAndroidBufferManager.FreeBuffer;
begin
  { The screen buffer is shared and owned by the global screen state; it
    is never freed per-canvas. Only secondary buffers are released. }
  if not FIsMain and (FBuffer <> nil) then
    FreeMem(FBuffer);
  FBuffer := nil;
  FBufWidth := 0;
  FBufHeight := 0;
  FStride := 0;
end;

procedure TAndroidBufferManager.PutBufferToScreen(x, y, w, h: TfpgCoord);
begin
  if not FIsMain then
  begin
    if (FBuffer = nil) or (FWindow = nil) then
    begin
      AndroidLog(ANDROID_LOG_WARN, Format('sub PutBufferToScreen skipped: buf=%p win=%p req=%d,%d %dx%d',
        [FBuffer, Pointer(FWindow), x, y, w, h]));
      Exit;
    end;
    { Floating window with its own popup view: present straight into it
      (the Java view draws the bitmap; no surface involved). }
    if (FWindow is TfpgAndroidWindow) and
       (TfpgAndroidWindow(FWindow).SubWindowId > 0) and
       Assigned(AndroidPresentSubFrameProc) then
    begin
      PresentSubWindowSurface(Self);
      Exit;
    end;
  end
  else
  begin
    if (x = y) and (w = h) then ;   { keep the parameters meaningful }
  end;
  { Compositing fallback (no floating windows available): re-blend all
    visible secondary windows over the screen buffer and post the frame. }
  RecompositeSubWindows;
  PresentScreen;
end;

procedure TAndroidBufferManager.RestoreFromBuffer(const ARect: TfpgRect);
begin
  PutBufferToScreen(ARect.Left, ARect.Top, ARect.Width, ARect.Height);
end;

function CreateAndroidBufferManager: IBufferManager;
begin
  Result := TAndroidBufferManager.Create;
end;

{ A native window object is about to be freed (e.g. a popup window closing
  through TfpgWidget.HandleHide). Detach every buffer manager that still
  references it, otherwise the stale FWindow pointer crashes the next
  RecompositeSubWindows pass on the main window's present. }
procedure AndroidWindowDestroying(AWindow: TfpgWindowBase);
var
  i: Integer;
  m: TAndroidBufferManager;
begin
  if (gSubManagers = nil) or (AWindow = nil) then
    Exit;
  for i := gSubManagers.Count - 1 downto 0 do
  begin
    m := TAndroidBufferManager(gSubManagers[i]);
    if m.FWindow = AWindow then
      m.DetachWindow;   { clears FWindow and removes from gSubManagers }
  end;
end;

initialization
  AndroidScreenAttachHook := @AndroidScreenAttach;
  AndroidScreenDetachHook := @AndroidScreenDetach;
  AndroidWindowDestroyingProc := @AndroidWindowDestroying;
  gSubManagers := TList.Create;

finalization
  FreeAndNil(gSubManagers);

end.
