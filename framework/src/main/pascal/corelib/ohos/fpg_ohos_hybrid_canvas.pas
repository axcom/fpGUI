{
    This unit is part of the fpGUI Toolkit project.

    Copyright (c) 2026 by Graeme Geldenhuys.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      Hybrid canvas that uses AggPas for all 2D rendering (anti-aliased
      lines, alpha blending, gradients) and renders text directly into
      the AggPas buffer via cached FreeType bitmap glyphs (TGlyphCache).
      Buffer management (allocation, screen flushing) is handled via
      IBufferManager.

      Text is rendered into the same pixel buffer as 2D content, giving
      correct z-ordering automatically. No deferred text queues, no
      two-surface compositing, no flickering.

      No platform-specific code, no include files.
}

unit fpg_ohos_hybrid_canvas;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  fpg_base,
  agg_2D;

type

  { TOhosHybridCanvas — composes a clean Agg2D object for 2D rendering and
    IBufferManager for platform-specific pixel buffer operations.

    Inherits from TfpgCanvasBase to satisfy the fpGUI canvas contract.
    All 2D operations are forwarded to the internal Agg2D object.
    Text is rendered via TfpgFontResourceBase.DrawTextToBuffer, which is
    implemented by the platform's registered AggFontResourceClass (e.g.
    TfpgFreeTypeFontResource on Unix/macOS, TfpgGDIAggFontResource on
    Windows). The canvas itself has no font-engine dependency.

    No platform-specific code, no include files. }

  TOhosHybridCanvas = class(TfpgCanvasBase)
  protected
    FAgg: agg_2D.Agg2D;
    FBufferManager: IBufferManager;
    FCurrentTextColor: TfpgColor;
    FWindowAttached: Boolean;
    FAttachedWindow: TfpgWindowBase;
    FBufData: Pointer;
    FBufStride: Integer;
    FBufWidth: Integer;
    FBufHeight: Integer;
    {$ifdef OHOS}
    FPhysicalBufW: Integer;
    FPhysicalBufH: Integer;
    procedure   AllocPhysicalBuffer;
    {$endif}
    procedure EnsureWindowAttached;
    { Text rendering — into buffer via glyph cache }
    procedure DoDrawString(x, y: TfpgCoord; const txt: string); override;
    procedure DoSetFontRes(fntres: TfpgFontResourceBase); override;
    procedure DoSetTextColor(cl: TfpgColor); override;
    { 2D rendering — delegated to FAgg }
    procedure DoSetColor(cl: TfpgColor); override;
    procedure DoSetLineStyle(awidth: integer; astyle: TfpgLineStyle); override;
    procedure DoFillRectangle(x, y, w, h: TfpgCoord); override;
    procedure DoXORFillRectangle(col: TfpgColor; x, y, w, h: TfpgCoord); override;
    procedure DoFillTriangle(x1, y1, x2, y2, x3, y3: TfpgCoord); override;
    procedure DoDrawRectangle(x, y, w, h: TfpgCoord); override;
    procedure DoDrawLine(x1, y1, x2, y2: TfpgCoord); override;
    procedure DoDrawImagePart(x, y: TfpgCoord; img: TfpgImageBase; xi, yi, w, h: integer); override;
    procedure DoStretchDraw(x, y, w, h: TfpgCoord; ASource: TfpgImageBase); override;
    { Shared image blit: source rect (sx0,sy0,sx1,sy1) in image pixels,
      dest rect (dx0,dy0,dx1,dy1) in logical canvas coords. Caller guarantees
      img is TfpgImage with ColorDepth=32. }
    procedure TransformImageRect(img: TfpgImageBase;
      sx0, sy0, sx1, sy1: Integer; dx0, dy0, dx1, dy1: Double);
    procedure DoDrawArc(x, y, w, h: TfpgCoord; a1, a2: double); override;
    procedure DoFillArc(x, y, w, h: TfpgCoord; a1, a2: double); override;
    procedure DoDrawPolygon(const Points: array of TPoint); override;
    function  GetPixel(X, Y: integer): TfpgColor; override;
    procedure SetPixel(X, Y: integer; const AValue: TfpgColor); override;
    { Clip rect — applied to FAgg }
    procedure DoSetClipRectInternal(const ARect: TfpgRect);
    procedure DoSetClipRect(const ARect: TfpgRect); override;
    function  DoGetClipRect: TfpgRect; override;
    procedure DoAddClipRect(const ARect: TfpgRect); override;
    procedure DoClearClipRect; override;
    { Lifecycle — coordinate FAgg and IBufferManager }
    procedure DoBeginDraw(awidget: TfpgWidgetBase; CanvasTarget: TfpgCanvasBase); override;
    procedure DoPutBufferToScreen(x, y, w, h: TfpgCoord); override;
    procedure DoEndDraw; override;
    function  GetBufferAllocated: Boolean; override;
    procedure DoAllocateBuffer; override;
    procedure DoRestoreFromBuffer(const ARect: TfpgRect); override;
  public
    constructor Create(awidget: TfpgWidgetBase); override;
    destructor  Destroy; override;
    procedure   GradientFill(ARect: TfpgRect; AStart, AStop: TfpgColor; ADirection: TGradientDirection); override;
    procedure   CopyRect(ADest_x, ADest_y: TfpgCoord; ASrcCanvas: TfpgCanvasBase; var ASrcRect: TfpgRect); override;
  end;


{ Factory function type for creating platform-specific buffer manager }
type
  TBufferManagerFactory = function: IBufferManager;

var
  { Set by platform-specific initialisation code (e.g. fpg_interface.pas) }
  CreateBufferManager: TBufferManagerFactory = nil;


implementation

uses
  agg_color,
  agg_basics,
  fpg_main,
  fpg_widget,
  fpg_ohos;

procedure OH_LOG_Print(logType: Integer; logLevel: Integer;
  domain: Cardinal; tag: PChar; fmt: PChar); cdecl; varargs;
  external 'libhilog_ndk.z.so';
const
  LOG_APP  = 0;
  LOG_INFO = 3+1;
  LOG_WARN = 4+1;
  LOG_ERROR = 5+1;
  FP_LOG_DOMAIN = $FF00;
  FP_LOG_TAG = 'fpGUI';
procedure fpGUI_Hilog(level: Integer; const Msg: String);
var
  buf: array[0..1023] of Char;
begin
  StrPCopy(buf, Msg);
  OH_LOG_Print(LOG_APP, level, FP_LOG_DOMAIN, FP_LOG_TAG, '%{public}s', buf);
end;  


{ Helper: convert TfpgColor to AggPas Color (rgba8).
  AggPas uses pixfmt_bgra32 which places B at byte 0, G at 1, R at 2, A at 3.
  This matches the native display format on X11, GDI, and Cocoa. }
function fpgColorToAgg(c: TfpgColor): agg_2D.Color;
var
  rgb: TfpgColor;
begin
  rgb := fpgColorToRGB(c);
  {$ifdef OHOS}
  { OHOS NativeWindow expects RGBA_8888, but AggPas writes BGRA32.
    Swap R and B so the displayed colour matches the intended value.
    E.g. clSelection ($FF08246A=intended blue) → swap → AggPas writes
    B=$08, G=$24, R=$6A, A=$FF → OHOS reads RGBA: R=$08, G=$24, B=$6A=blue. }
  Result.r := rgb and $FF;             // intended B → Agg R (ends up at OHOS R)
  Result.g := (rgb shr 8) and $FF;     // G stays G
  Result.b := (rgb shr 16) and $FF;    // intended R → Agg B (ends up at OHOS B)
  {$else}
  Result.r := (rgb shr 16) and $FF;
  Result.g := (rgb shr 8) and $FF;
  Result.b := rgb and $FF;
  {$endif}
  Result.a := (rgb shr 24) and $FF;
  if Result.a = 0 then
    Result.a := 255;
end;


{ TOhosHybridCanvas }

constructor TOhosHybridCanvas.Create(awidget: TfpgWidgetBase);
begin
  inherited Create(awidget);
  FAgg.Construct;
  FCurrentTextColor := 0;
  FWindowAttached := False;
  FAttachedWindow := nil;
  FBufData := nil;
  FBufStride := 0;
  FBufWidth := 0;
  FBufHeight := 0;
  if Assigned(CreateBufferManager) then
    FBufferManager := CreateBufferManager();
end;

destructor TOhosHybridCanvas.Destroy;
begin
  if Assigned(FBufferManager) then
  begin
    FBufferManager.FreeBuffer;
    FBufferManager := nil;
  end;
  FAgg.Destruct;
  inherited Destroy;
end;

procedure TOhosHybridCanvas.EnsureWindowAttached;
begin
  if not Assigned(FWidget) then
    Exit;
  if not Assigned(FWidget.Window) then
    Exit;
  { Always re-attach the buffer manager to the current window.
    Popup windows are destroyed and recreated between show/hide
    cycles, so the X11 handle changes even though the canvas
    persists. Object-pointer comparison is unreliable because FPC's
    memory allocator may reuse the same address for the new window,
    making a stale FAttachedWindow appear current while the buffer
    manager still holds a zeroed-out (invalid) X11 handle.
    AttachWindow is cheap (copies a few fields), so always calling
    it is safer than trying to detect staleness. }
  FAttachedWindow := FWidget.Window;
  if Assigned(FBufferManager) then
    FBufferManager.AttachWindow(FAttachedWindow);
  FWindowAttached := True;
end;

{$ifdef OHOS}
procedure TOhosHybridCanvas.AllocPhysicalBuffer;
const
  ResizeThreshold = 50;
var
  AllocW, AllocH: Integer;
  scale: Double;
  winRect: TfpgRect;
begin
  if not Assigned(FBufferManager) then Exit;
  if not Assigned(FWidget) then Exit;

  { Use the widget's client rect to match what fpGUI actually paints.
    The non-AGG TfpgOhosCanvas also uses awidget.Window.GetClientRect. }
  if Assigned(FWidget.Window) then
    winRect := FWidget.Window.GetClientRect
  else
    winRect.SetRect(0, 0, 400, 300);
  if winRect.Width < 1 then winRect.Width := 400;
  if winRect.Height < 1 then winRect.Height := 300;

  scale := gHiDPIScaleFactor;
  if scale < 1.0 then scale := 1.0;

  { 用窗口实际物理尺寸（resize 反馈更新）作分配依据：GetClientRect 在反馈
    处理后可能滞后 → AllocW/H 偏小 → buffer 停在旧尺寸 → 窗口拖大后扩大部分
    无内容（黑色）。与 TfpgOhosCanvas.BeginDraw 修复一致。 }
  if Assigned(FWidget.Window) and (FWidget.Window is TfpgOhosWindow) then
  begin
    if TfpgOhosWindow(FWidget.Window).PhysicalWidth > 0 then
      AllocW := TfpgOhosWindow(FWidget.Window).PhysicalWidth + ResizeThreshold
    else
      AllocW := Round(winRect.Width * scale) + ResizeThreshold;
    if TfpgOhosWindow(FWidget.Window).PhysicalHeight > 0 then
      AllocH := TfpgOhosWindow(FWidget.Window).PhysicalHeight + ResizeThreshold
    else
      AllocH := Round(winRect.Height * scale) + ResizeThreshold;
  end
  else
  begin
    AllocW := Round(winRect.Width * scale) + ResizeThreshold;
    AllocH := Round(winRect.Height * scale) + ResizeThreshold;
  end;

  { Stale-pointer guard: FBufData may still point at memory that was already
    released by FBufferManager.FreeBuffer (window destroyed/recreated between
    show/hide cycles). BufferAllocated (= FBuffer <> nil) detects that case;
    otherwise the fast-path check below would skip reallocation and every
    draw call would write into freed memory (SEGV_ACCERR). }
  if (FBufData <> nil) and Assigned(FBufferManager) and (not FBufferManager.BufferAllocated) then
  begin
    fpGUI_Hilog(LOG_WARN, 'AllocPhysicalBuffer: stale buffer reset (was ' +
      IntToHex(PtrUInt(FBufData), 8) + ')');
    FBufData := nil;
    FPhysicalBufW := 0;
    FPhysicalBufH := 0;
    FBufStride := 0;
  end;

  if (FPhysicalBufW >= AllocW) and (FPhysicalBufH >= AllocH) and (FBufData <> nil) then
    Exit;

  EnsureWindowAttached;

  if FBufData <> nil then
    FBufferManager.FreeBuffer;

  { Clear canvas-side fields too: FreeBuffer only clears the manager's FBuffer,
    leaving FBufData/FPhysicalBufW/H stale which would fool the fast-path check. }
  FBufData := nil;
  FPhysicalBufW := 0;
  FPhysicalBufH := 0;
  FBufStride := 0;

  FBufferManager.AllocateBuffer(AllocW, AllocH, FBufData, FBufStride);

  if FBufData = nil then
    Exit;

  { Clear the entire buffer to white, so un-painted areas are not garbage. }
  //FillChar(FBufData^, AllocH * FBufStride, $FF);
  //if FPhysicalBufW = 0 then // 只在新分配时清空一次 AggPas 缓冲区，重入时不清
  if (FPhysicalBufW = 0) or (FPhysicalBufW <> AllocW) or (FPhysicalBufH <> AllocH) then
    FillChar(FBufData^, AllocH * FBufStride, $FF);
  
  FPhysicalBufW := AllocW;
  FPhysicalBufH := AllocH;
  FBufWidth  := AllocW;
  FBufHeight := AllocH;

  {fpGUI_Hilog(LOG_INFO, 'AllocPhysicalBuffer: win(logical)=' + IntToStr(winRect.Width) +
    'x' + IntToStr(winRect.Height) + ' scale=' + FormatFloat('0.###', scale) +
    ' alloc(phys)=' + IntToStr(AllocW) + 'x' + IntToStr(AllocH) +
    ' buf=' + IntToHex(PtrUInt(FBufData), 8) + ' stride=' + IntToStr(FBufStride));}

  FAgg.attach(int8u_ptr(FBufData), FBufWidth, FBufHeight, FBufStride);
  FAgg.resetTransformations;
end;
{$endif}


{ --- Text rendering (into buffer via glyph cache) --- }

procedure TOhosHybridCanvas.DoDrawString(x, y: TfpgCoord; const txt: string);
var
  cb: agg_2D.RectD;
begin
  if (Length(txt) < 1) or (FBufData = nil) or not Assigned(FFont) then
    Exit;
  { AY passed to DrawTextToBuffer is the baseline (top + ascent).
    The clip box from Agg2D is forwarded so text clips to the same region
    as 2D operations — required for selection-highlight redraws in TfpgEdit. }
  cb := FAgg.clipBox;
  FFont.DrawTextToBuffer(PByte(FBufData), FBufStride, FBufWidth, FBufHeight,
    x + FDeltaX, y + FDeltaY + FFont.GetAscent, txt, FCurrentTextColor,
    Trunc(cb.x1 / gHiDPIScaleFactor), Trunc(cb.y1 / gHiDPIScaleFactor), 
    Trunc(cb.x2 / gHiDPIScaleFactor), Trunc(cb.y2 / gHiDPIScaleFactor)); //传 clip 前 ÷sf（恢复逻辑语义）
end;

procedure TOhosHybridCanvas.DoSetFontRes(fntres: TfpgFontResourceBase);
begin
  { Font resource is stored in FFont by the base class SetFont call.
    Each AggCanvas font resource (TfpgFreeTypeFontResource,
    TfpgGDIAggFontResource) is self-contained — no extra canvas-side
    glyph-cache state to synchronise here. }
end;

procedure TOhosHybridCanvas.DoSetTextColor(cl: TfpgColor);
begin
  FCurrentTextColor := cl;
end;


{ --- 2D rendering (delegated to FAgg) --- }

procedure TOhosHybridCanvas.DoSetColor(cl: TfpgColor);
var
  c: agg_2D.Color;
begin
  c := fpgColorToAgg(cl);
  FAgg.lineColor(c);
  FAgg.fillColor(c);
end;

procedure TOhosHybridCanvas.DoSetLineStyle(awidth: integer; astyle: TfpgLineStyle);
const
  StyleMap: array[TfpgLineStyle] of agg_2D.LineStyle = (
    stySolid,       // lsSolid
    styDash,        // lsDash
    styDot,         // lsDot
    styDashDot,     // lsDashDot
    styDashDotDot   // lsDashDotDot
  );
var
  w: integer;
begin
  { X11 treats lineWidth=0 as "1px hardware-accelerated line".
    AggPas treats 0 as "don't stroke at all", so clamp to 1. }
  {$ifdef OHOS}
  { On HiDPI screens, set minimum physical line width so borders
    are visible. awidth=1 at scale 3.167 gives ~3px which should
    be visible, but clGridLines color may be too close to background.
    We keep awidth as-is — Agg2D's scale transform handles the
    logical→physical conversion for line width automatically. }
  w := awidth;
  if w < 1 then w := 1;
  {$else}
  w := awidth;
  if w < 1 then
    w := 1;
  {$endif}
  FAgg.SetLineStyle(w, StyleMap[astyle]);
end;

procedure TOhosHybridCanvas.DoFillRectangle(x, y, w, h: TfpgCoord);
var
  fc: agg_2D.Color;
  rx, ry, rw, rh: TfpgCoord;
  cx1, cy1, cx2, cy2: TfpgCoord;
  cb: agg_2D.RectD;
  bgra: LongWord;
  py: TfpgCoord;
  rowPtr: PLongWord;
begin
  if (w < 1) or (h < 1) then
    Exit;

  fc := FAgg.fillColor;

  { Fast path: for fully opaque fills we write directly into the pixel buffer,
    bypassing AggPas's per-pixel alpha-blend rasteriser. Profiling showed that
    BGRA32_BLEND_SOLID_HSPAN consumed 84% of CPU time — most of which was
    opaque solid rectangle fills that need no blending at all.
    
    Note: the coordinates here are in LOGICAL (user) space, but the buffer
    is at PHYSICAL pixel resolution with an Agg2D scale transform applied.
    We must multiply by the scale factor to write to the correct pixel range. }
  if (fc.a = 255) and (FBufData <> nil) then
  begin
    { Build BGRA32 LongWord: on little-endian [B, G, R, A] in memory }
    bgra := LongWord(fc.b)
          or (LongWord(fc.g) shl 8)
          or (LongWord(fc.r) shl 16)
          or LongWord($FF000000);

    { Get clip rect from AggPas — clipBox is in PHYSICAL pixels
      (DoSetClipRect multiplies by gHiDPIScaleFactor) }
    cb := FAgg.clipBox;
    cx1 := Round(cb.x1);
    cy1 := Round(cb.y1);
    cx2 := Round(cb.x2);
    cy2 := Round(cb.y2);

    { Logical coords → physical pixels FIRST, then clip in physical space.
      Comparing logical y against the physical clip rect used to clamp the
      fill to the wrong position (selection highlight appeared too low). }
    rx := Round((x + FDeltaX) * gHiDPIScaleFactor);
    ry := Round((y + FDeltaY) * gHiDPIScaleFactor);
    rw := Round(w * gHiDPIScaleFactor);
    rh := Round(h * gHiDPIScaleFactor);

    { Clip to AggPas clip rect (physical) }
    if rx < cx1 then begin Dec(rw, cx1 - rx); rx := cx1; end;
    if ry < cy1 then begin Dec(rh, cy1 - ry); ry := cy1; end;
    if rx + rw > cx2 then rw := cx2 - rx;
    if ry + rh > cy2 then rh := cy2 - ry;

    { Clip to buffer bounds }
    if rx < 0 then begin Dec(rw, -rx); rx := 0; end;
    if ry < 0 then begin Dec(rh, -ry); ry := 0; end;
    if rx + rw > FBufWidth then rw := FBufWidth - rx;
    if ry + rh > FBufHeight then rh := FBufHeight - ry;

    if (rw < 1) or (rh < 1) then
      Exit;

    { Direct memory fill — no alpha blending needed }
    for py := ry to ry + rh - 1 do
    begin
      rowPtr := PLongWord(PByte(FBufData) + py * FBufStride + rx * 4);
      { Sentinel: guard against writes past the end of the physical buffer
        (SEGV_ACCERR in FillDWord). Child sub-regions can exceed the buffer
        when widget sizes are inconsistent with the window; this keeps the
        app alive and logs the offending context. }
      if (PtrUInt(rowPtr) + PtrUInt(rw) * 4) >
         (PtrUInt(FBufData) + PtrUInt(FBufHeight) * PtrUInt(FBufStride)) then
      begin
        fpGUI_Hilog(LOG_WARN, 'DoFillRectangle OOB guard: rx=' + IntToStr(rx) +
          ' ry=' + IntToStr(ry) + ' rw=' + IntToStr(rw) + ' py=' + IntToStr(py) +
          ' bufW=' + IntToStr(FBufWidth) + ' bufH=' + IntToStr(FBufHeight) +
          ' stride=' + IntToStr(FBufStride) + ' buf=' + IntToHex(PtrUInt(FBufData), 8));
        Continue;
      end;
      FillDWord(rowPtr^, rw, bgra);
    end;
  end
  else
  begin
    { Transparent or no buffer — fall through to AggPas for proper blending }
    FAgg.noLine;
    FAgg.rectangle(x + FDeltaX, y + FDeltaY,
                   x + FDeltaX + w - 1, y + FDeltaY + h - 1, True);
  end;
end;

procedure TOhosHybridCanvas.DoXORFillRectangle(col: TfpgColor; x, y, w, h: TfpgCoord);
var
  px, py: TfpgCoord;
  rx, ry, rw, rh: TfpgCoord;
  xorMask: LongWord;
  rgb: TfpgColor;
  rowPtr: PLongWord;
  cb: agg_2D.RectD;
  cx1, cy1, cx2, cy2: TfpgCoord;
begin
  if (w < 1) or (h < 1) then
    Exit;
  if FBufData = nil then
    Exit;

  { Perform true bitwise XOR on pixel data, matching X11's GXxor behaviour.
    This ensures the caret is always visible regardless of background colour. }
  rgb := fpgColorToRGB(col);
  { Build BGRA XOR mask: TfpgColor is $AARRGGBB, buffer is BGRA byte order.
    On little-endian, a LongWord in memory is [B, G, R, A].
    Force alpha to $FF so XOR flips the colour channels but keeps pixels opaque. }
  xorMask := (rgb and $FF) shl 16          { R → byte 2 }
           or (rgb and $FF00)               { G → byte 1 }
           or ((rgb shr 16) and $FF)        { B → byte 0 }
           or $FF000000;                    { A = $FF }
  
  rx := x + FDeltaX;
  ry := y + FDeltaY;
  rw := w;
  rh := h;

  if gHiDPIScaleFactor <> 1.0 then
  begin
    rx := Round(rx * gHiDPIScaleFactor);
    ry := Round(ry * gHiDPIScaleFactor);
    rw := Round(rw * gHiDPIScaleFactor);
    rh := Round(rh * gHiDPIScaleFactor);
  end;

  { 唯一 clip 段（物理空间）：早期逻辑坐标 clip 与物理缓冲尺寸比较是
    空间错配（HiDPI 下不生效，且逻辑矩形 > 物理缓冲时提前 Exit 而非
    裁剪）——已删除，此处自足。 }
  if rx < 0 then begin Inc(rw, rx); rx := 0; end;
  if ry < 0 then begin Inc(rh, ry); ry := 0; end;
  if rx + rw > FBufWidth then rw := FBufWidth - rx;
  if ry + rh > FBufHeight then rh := FBufHeight - ry;
  if (rw < 1) or (rh < 1) then
    Exit;

  for py := ry to ry + rh - 1 do
  begin
    rowPtr := PLongWord(PByte(FBufData) + py * FBufStride + rx * 4);
    { OOB guard: skip rows that would write past the physical buffer. }
    if (PtrUInt(rowPtr) + PtrUInt(rw) * 4) >
       (PtrUInt(FBufData) + PtrUInt(FBufHeight) * PtrUInt(FBufStride)) then
      Continue;
    for px := 0 to rw - 1 do
    begin
      rowPtr^ := rowPtr^ xor xorMask;
      Inc(rowPtr);
    end;
  end;
end;

procedure TOhosHybridCanvas.DoFillTriangle(x1, y1, x2, y2, x3, y3: TfpgCoord);
var
  c: agg_2D.Color;
begin
  { Ensure both fill and line use the current color, matching
    TAgg2D.DoFillTriangle behaviour. Add 0.5 for pixel alignment. }
  c := FAgg.lineColor;
  FAgg.fillColor(c);
  FAgg.lineWidth(1);
  FAgg.triangle(x1 + FDeltaX + 0.5, y1 + FDeltaY + 0.5,
                x2 + FDeltaX + 0.5, y2 + FDeltaY + 0.5,
                x3 + FDeltaX + 0.5, y3 + FDeltaY + 0.5);
end;

procedure TOhosHybridCanvas.DoDrawRectangle(x, y, w, h: TfpgCoord);
var
  lw: TfpgCoord;
  lc: agg_2D.Color;
begin
  FAgg.noFill;
  FAgg.rectangle(x + FDeltaX + 0.5, y + FDeltaY + 0.5,
                 x + FDeltaX + w - 1.5, y + FDeltaY + h - 1.5, False);
end;

procedure TOhosHybridCanvas.DoDrawLine(x1, y1, x2, y2: TfpgCoord);
var
  lw: TfpgCoord;
  t: TfpgCoord;
  lc: agg_2D.Color;
begin
  FAgg.line(x1 + FDeltaX, y1 + FDeltaY, x2 + FDeltaX, y2 + FDeltaY, True);
end;

procedure TOhosHybridCanvas.TransformImageRect(img: TfpgImageBase;
  sx0, sy0, sx1, sy1: Integer; dx0, dy0, dx1, dy1: Double);
var
  aggImg: agg_2D.Image;
  stride: Integer;
  buffer: Pointer;
  tempBuf: PLongWord;
  srcBuf: PLongWord;
  maskPtr: PByte;
  imgW, imgH: Integer;
  row, col: Integer;
  mskLineLen: Integer;
  byteIdx, bitIdx: Integer;
  needFree: Boolean;
{$ifdef OHOS}
  p2: PByte;
  pDst: PByte;
  i2, r2: Integer;
  v2: LongWord;
  tempSwap: Pointer;
{$endif}
begin
  { 调用方保证 img 为 32 位 TfpgImage }
  imgW := TfpgImage(img).Width;
  imgH := TfpgImage(img).Height;
  needFree := False;

  if img.Masked and (img.MaskData <> nil) then
  begin
    { Image has a 1-bit mask. Create a temporary copy with alpha applied.
      Mask format: 1 bit per pixel, MSB first, rows padded to 32-bit.
      Bit = 1 means opaque, bit = 0 means transparent.
      BMP palette images may have alpha=0 for all pixels (the native X11
      canvas ignores alpha), so we must set alpha=0xFF for opaque pixels. }
    tempBuf := GetMem(imgW * imgH * 4);
    srcBuf := PLongWord(img.ImageData);
    Move(srcBuf^, tempBuf^, imgW * imgH * 4);

    mskLineLen := ((imgW + 31) div 32) * 4;  { bytes per mask row }
    maskPtr := PByte(img.MaskData);

    for row := 0 to imgH - 1 do
    begin
      for col := 0 to imgW - 1 do
      begin
        byteIdx := col div 8;
        bitIdx := 7 - (col mod 8);  { MSB first }
        if ((maskPtr + row * mskLineLen + byteIdx)^ shr bitIdx) and 1 = 0 then
          { Mask bit = 0: transparent — clear alpha }
          tempBuf[row * imgW + col] := tempBuf[row * imgW + col] and $00FFFFFF
        else
          { Mask bit = 1: opaque — ensure alpha is 0xFF }
          tempBuf[row * imgW + col] := tempBuf[row * imgW + col] or $FF000000;
      end;
    end;

    buffer := tempBuf;
    stride := imgW * 4;
    needFree := True;
  end
  else
  begin
    stride := Integer(PByte(TfpgImage(img).ScanLine[1]) - PByte(TfpgImage(img).ScanLine[0]));
    if stride < 0 then
      buffer := TfpgImage(img).ScanLine[imgH - 1]
    else
      buffer := TfpgImage(img).ScanLine[0];
  end;

{$ifdef OHOS}
{ Display expects RGBA_8888; AggPas's bgra_order reads [B,G,R,A] and blends
  raw values into the BGRA32 target without colour swapping (vector/text
  paths swap via fpgColorToAgg/nativeColor). Swap source pixels to RGBA
  order so the blended result matches the intended colour. }
if needFree then
begin
  { masked 分支：tempBuf 原地交换（释放留在末尾） }
  p2 := PByte(buffer);
  for i2 := 0 to imgW * imgH - 1 do
  begin
    v2 := PLongWord(p2)^;
    PLongWord(p2)^ := (v2 and $FF00FF00) or ((v2 shr 16) and $FF) or ((v2 shl 16) and $FF0000);
    Inc(p2, 4);
  end;
end
else
begin
  { 非 masked：逐行复制（处理负 stride）+ 交换 }
  tempSwap := GetMem(imgW * imgH * 4);
  p2 := PByte(buffer);
  pDst := PByte(tempSwap);
  for r2 := 0 to imgH - 1 do
  begin
    Move(p2^, pDst^, imgW * 4);
    Inc(p2, stride);
    Inc(pDst, imgW * 4);
  end;
  p2 := PByte(tempSwap);
  for i2 := 0 to imgW * imgH - 1 do
  begin
    v2 := PLongWord(p2)^;
    PLongWord(p2)^ := (v2 and $FF00FF00) or ((v2 shr 16) and $FF) or ((v2 shl 16) and $FF0000);
    Inc(p2, 4);
  end;
  buffer := tempSwap;
  stride := imgW * 4;
  needFree := True;
end;
{$endif}

  aggImg.Construct(int8u_ptr(buffer), imgW, imgH, stride);
  FAgg.transformImage(@aggImg, sx0, sy0, sx1, sy1, dx0, dy0, dx1, dy1);
  aggImg.Destruct;

  if needFree then
  {$ifdef OHOS}
    FreeMem(buffer);      // tempBuf (masked) 或 tempSwap (交换副本)
  {$else}
    FreeMem(tempBuf);
  {$endif}
end;

procedure TOhosHybridCanvas.DoDrawImagePart(x, y: TfpgCoord; img: TfpgImageBase; xi, yi, w, h: integer);
begin
  if not (img is TfpgImage) then
    Exit;
  if TfpgImage(img).ColorDepth <> 32 then
    Exit;
  TransformImageRect(img, xi, yi, xi + w, yi + h,
    x + FDeltaX, y + FDeltaY, x + FDeltaX + w, y + FDeltaY + h);
end;

{ StretchDraw 快路径：与 DoDrawImagePart 同一 AggPas transformImage 通道，
  源整图 → 目标逻辑矩形；FAgg 的 scale 变换负责 HiDPI 物理映射，目标物理
  矩形被完整采样填充（避免基类插值逐像素 SetPixel 的空洞/发虚/错位）。
  非 32 位 TfpgImage 回退基类 Mitchel 插值。 }
procedure TOhosHybridCanvas.DoStretchDraw(x, y, w, h: TfpgCoord; ASource: TfpgImageBase);
var
  imgW, imgH: Integer;
begin
  if not (ASource is TfpgImage) then
  begin
    fpGUI_Hilog(LOG_INFO, 'DoStretchDraw: not TfpgImage -> inherited');
    inherited DoStretchDraw(x, y, w, h, ASource);
    Exit;
  end;
  if TfpgImage(ASource).ColorDepth <> 32 then
  begin
    fpGUI_Hilog(LOG_INFO, 'DoStretchDraw: ColorDepth=' + IntToStr(TfpgImage(ASource).ColorDepth) + ' -> inherited');
    inherited DoStretchDraw(x, y, w, h, ASource);
    Exit;
  end;
  imgW := TfpgImage(ASource).Width;
  imgH := TfpgImage(ASource).Height;
  if (imgW <= 0) or (imgH <= 0) or (w <= 0) or (h <= 0) then
    Exit;
  TransformImageRect(ASource, 0, 0, imgW, imgH,
    x + FDeltaX, y + FDeltaY, x + FDeltaX + w, y + FDeltaY + h);
end;

procedure TOhosHybridCanvas.DoDrawArc(x, y, w, h: TfpgCoord; a1, a2: double);
var
  cx, cy, rx, ry: double;
begin
  cx := x + FDeltaX + w / 2.0;
  cy := y + FDeltaY + h / 2.0;
  rx := w / 2.0;
  ry := h / 2.0;
  FAgg.noFill;
  FAgg.arc(cx, cy, rx, ry, a1, a1 + a2);
end;

procedure TOhosHybridCanvas.DoFillArc(x, y, w, h: TfpgCoord; a1, a2: double);
var
  cx, cy, rx, ry: double;
begin
  cx := x + FDeltaX + w / 2.0;
  cy := y + FDeltaY + h / 2.0;
  rx := w / 2.0;
  ry := h / 2.0;
  FAgg.noLine;
  FAgg.arc(cx, cy, rx, ry, a1, a1 + a2);
end;

procedure TOhosHybridCanvas.DoDrawPolygon(const Points: array of TPoint);
var
  i, j: Integer;
  poly: array of double;
  c: agg_2D.Color;
begin
  poly := nil;
  if Length(Points) < 2 then
    Exit;
  SetLength(poly, (Length(Points) * 2) + 1);
  j := 1;
  for i := Low(Points) to High(Points) do
  begin
    poly[j * 2 - 1] := Points[i].X + FDeltaX + 0.5;
    poly[j * 2] := Points[i].Y + FDeltaY + 0.5;
    Inc(j);
  end;
  { X11 uses XFillPolygon, GDI uses Windows.Polygon — both fill.
    Ensure fill and line color match so polygon renders filled. }
  c := FAgg.lineColor;
  FAgg.fillColor(c);
  FAgg.lineWidth(1);
  FAgg.polygon(@poly[1], Length(Points));
end;

function TOhosHybridCanvas.GetPixel(X, Y: integer): TfpgColor;
var
  px: PByte;
  drawX, drawY: Integer;
begin
  Result := 0;
  drawX := X + FDeltaX;
  drawY := Y + FDeltaY;
  if gHiDPIScaleFactor <> 1.0 then
  begin
    drawX := Round(drawX * gHiDPIScaleFactor);
    drawY := Round(drawY * gHiDPIScaleFactor);
  end;
  if (FBufData = nil) or (drawX < 0) or (drawY < 0) or
     (drawX >= FBufWidth) or (drawY >= FBufHeight) then
    Exit;
  px := PByte(FBufData) + drawY * FBufStride + drawX * 4;
  {$ifdef OHOS}
  { OHOS：fpgColorToAgg 已把 AggPas bgra32 缓冲写成 RGBA 字节序
    [R,G,B,A]（:149-156 swap）→ 直接按 R,G,B 读回。 }
  Result := (TfpgColor(px[0]) shl 16) or (TfpgColor(px[1]) shl 8) or TfpgColor(px[2]);
  {$else}
  { BGRA to TfpgColor ($AARRGGBB) }
  Result := (TfpgColor(px[2]) shl 16) or (TfpgColor(px[1]) shl 8) or TfpgColor(px[0]);
  {$endif}
end;

procedure TOhosHybridCanvas.SetPixel(X, Y: integer; const AValue: TfpgColor);
var
  px: PByte;
  rgb: TfpgColor;
  drawX, drawY: Integer;
begin
  drawX := X + FDeltaX;
  drawY := Y + FDeltaY;
  if gHiDPIScaleFactor <> 1.0 then
  begin
    drawX := Round(drawX * gHiDPIScaleFactor);
    drawY := Round(drawY * gHiDPIScaleFactor);
  end;
  if (FBufData = nil) or (drawX < 0) or (drawY < 0) or
     (drawX >= FBufWidth) or (drawY >= FBufHeight) then
    Exit;
  rgb := fpgColorToRGB(AValue);
  px := PByte(FBufData) + drawY * FBufStride + drawX * 4;
  {$ifdef OHOS}
  { OHOS：缓冲实为 RGBA 字节序 [R,G,B,A]（fpgColorToAgg swap 所致，
    见 :149-156）→ 按 R,G,B 写入，与绘制路径/显示一致。 }
  px[0] := (rgb shr 16) and $FF;  { R }
  px[1] := (rgb shr 8) and $FF;   { G }
  px[2] := rgb and $FF;           { B }
  {$else}
  { TfpgColor ($AARRGGBB) to BGRA }
  px[0] := rgb and $FF;           { B }
  px[1] := (rgb shr 8) and $FF;   { G }
  px[2] := (rgb shr 16) and $FF;  { R }
  {$endif}
  px[3] := 255;                   { A = fully opaque }
end;

procedure TOhosHybridCanvas.GradientFill(ARect: TfpgRect; AStart, AStop: TfpgColor; ADirection: TGradientDirection);
var
  c1, c2: agg_2D.Color;
begin
  c1 := fpgColorToAgg(AStart);
  c2 := fpgColorToAgg(AStop);
  if ADirection = gdVertical then
    FAgg.fillLinearGradient(
      ARect.Left + FDeltaX, ARect.Top + FDeltaY,
      ARect.Left + FDeltaX, ARect.Bottom + FDeltaY, c1, c2)
  else
    FAgg.fillLinearGradient(
      ARect.Left + FDeltaX, ARect.Top + FDeltaY,
      ARect.Right + FDeltaX, ARect.Top + FDeltaY, c1, c2);
  FAgg.noLine;
  FAgg.rectangle(
    ARect.Left + FDeltaX, ARect.Top + FDeltaY,
    ARect.Right + FDeltaX, ARect.Bottom + FDeltaY, True);
end;


{ --- Clip rect --- }

procedure TOhosHybridCanvas.DoSetClipRectInternal(const ARect: TfpgRect);
var
  wRect: TfpgRect;
  native: TfpgRect;
begin
  { Convert to native window coordinates and intersect with widget bounds.
    Matches X11's DoSetClipRectInternal behavior. }
  native := ARect;
  native.OffsetRect(FDeltaX, FDeltaY);
  wRect := GetWidgetWindowRect;
  native.IntersectRect(native, wRect);
  { Apply to Agg2D in physical pixels }
  FAgg.clipBox(native.Left * gHiDPIScaleFactor, native.Top * gHiDPIScaleFactor,
               native.Right * gHiDPIScaleFactor, native.Bottom * gHiDPIScaleFactor);
end;

procedure TOhosHybridCanvas.DoSetClipRect(const ARect: TfpgRect);
begin
  DoSetClipRectInternal(ARect);
end;

function TOhosHybridCanvas.DoGetClipRect: TfpgRect;
var
  cb: agg_2D.RectD;
begin
  cb := FAgg.clipBox;
  Result.SetRect(Round(cb.x1/gHiDPIScaleFactor), Round(cb.y1/gHiDPIScaleFactor),
                 Round((cb.x2 - cb.x1)/gHiDPIScaleFactor), Round((cb.y2 - cb.y1)/gHiDPIScaleFactor));
end;

procedure TOhosHybridCanvas.DoAddClipRect(const ARect: TfpgRect);
var
  NewRect: TfpgRect;
begin
  DoGetClipRect.IntersectRect(NewRect, ARect);
  DoSetClipRect(NewRect);
end;

procedure TOhosHybridCanvas.DoClearClipRect;
var
  r: TfpgRect;
begin
  { Match X11 behavior: ClearClipRect resets clip to widget bounds
    instead of clearing to full buffer size. }
  r.SetRect(0, 0, FWidget.ActualWidth, FWidget.ActualHeight);
  DoSetClipRectInternal(r);
end;


{ --- Lifecycle --- }

procedure TOhosHybridCanvas.DoBeginDraw(awidget: TfpgWidgetBase; CanvasTarget: TfpgCanvasBase);
var
  pCanvas: TOhosHybridCanvas;
  pStart: PtrUInt;
  availBytes: PtrUInt;
begin
  if CanvasTarget = Self then
  begin
    { Top-level canvas: we draw to our own buffer.
      Buffer is already attached via DoAllocateBuffer. }
    EnsureWindowAttached;
    {$ifdef OHOS}
    AllocPhysicalBuffer;
    if FBufData <> nil then
    begin
      FAgg.attach(int8u_ptr(FBufData), FBufWidth, FBufHeight, FBufStride);
      FAgg.resetTransformations;
      {$ifdef OHOS}
      { Hybrid canvas keeps Agg2D.HiDPIScaleFactor at 1.0 and applies the
        display scale explicitly here (resetTransformations is identity). }
      if gHiDPIScaleFactor <> 1.0 then
        FAgg.scale(gHiDPIScaleFactor, gHiDPIScaleFactor);
      {$endif}
    end;
    {$endif}
  end
  else if CanvasTarget is TOhosHybridCanvas then
  begin
    { Alien widget: attach our Agg2D to a sub-region of the parent's buffer.
      We calculate a byte offset so that AggPas position (0,0) maps to the
      widget's top-left pixel. This way we do NOT need FDeltaX/FDeltaY offsets
      in draw calls — AggPas draws in widget-local coordinates.
      This mirrors the original TAgg2D.AttachPartialImage approach. }
    if TOhosHybridCanvas(CanvasTarget).FBufData <> nil then
    begin
      pCanvas := TOhosHybridCanvas(CanvasTarget);
      FBufStride := pCanvas.FBufStride;
      {$ifdef OHOS}
      { Scale child widget sub-region to physical pixels. FDeltaX/FDeltaY
        and ActualWidth/ActualHeight are in logical coordinates, but the
        parent buffer uses physical pixel dimensions. Without scaling, the
        child renders at logical size/offset in a physical buffer, causing
        widgets to appear at 1/scale size in the top-left corner. }
      FBufWidth := Round(awidget.ActualWidth * gHiDPIScaleFactor);
      FBufHeight := Round(awidget.ActualHeight * gHiDPIScaleFactor);
      FBufData := PByte(pCanvas.FBufData)
                  + Round(FDeltaX * gHiDPIScaleFactor) * 4
                  + Round(FDeltaY * gHiDPIScaleFactor) * FBufStride;
      { Clamp the sub-region to the parent buffer extent. Child widgets can
        report logical sizes far beyond the window (e.g. scroll content),
        and attach()ting such a size lets AggPas draw far past the end of
        the physical buffer -> wild writes (SEGV_ACCERR in FillDWord). }
      pStart := PtrUInt(pCanvas.FBufData);
      if PtrUInt(FBufData) < pStart then
        FBufData := pCanvas.FBufData;
      if PtrUInt(FBufData) >= pStart + PtrUInt(pCanvas.FBufHeight) * PtrUInt(FBufStride) then
      begin
        if (pCanvas.FWidget <> nil) then
          fpGUI_Hilog(LOG_WARN, 'DoBeginDraw CHILD clamp: start beyond parent buffer, skip (off=' +
            IntToHex(PtrUInt(FBufData) - pStart, 8) + ')' +
            ' wdg=' + awidget.ClassName + ' name=' + awidget.Name +
            ' delta=(' + IntToStr(FDeltaX) + ',' + IntToStr(FDeltaY) + ') log' +
            ' size=(' + IntToStr(awidget.ActualWidth) + 'x' + IntToStr(awidget.ActualHeight) + ') log' +
            ' parentBuf=' + IntToHex(PtrUInt(pCanvas.FBufData), 8) +
            ' ' + IntToStr(pCanvas.FBufWidth) + 'x' + IntToStr(pCanvas.FBufHeight) + ' phys' +
            ' parentWnd=' + pCanvas.FWidget.ClassName)
        else
          fpGUI_Hilog(LOG_WARN, 'DoBeginDraw CHILD clamp: start beyond parent buffer, skip (off=' +
            IntToHex(PtrUInt(FBufData) - pStart, 8) + ')' +
            ' wdg=' + awidget.ClassName + ' name=' + awidget.Name +
            ' delta=(' + IntToStr(FDeltaX) + ',' + IntToStr(FDeltaY) + ') log' +
            ' size=(' + IntToStr(awidget.ActualWidth) + 'x' + IntToStr(awidget.ActualHeight) + ') log' +
            ' parentBuf=' + IntToHex(PtrUInt(pCanvas.FBufData), 8) +
            ' ' + IntToStr(pCanvas.FBufWidth) + 'x' + IntToStr(pCanvas.FBufHeight) + ' phys' +
            ' parentWnd=nil');
        Exit;
      end;
      availBytes := pStart + PtrUInt(pCanvas.FBufHeight) * PtrUInt(FBufStride)
                    - PtrUInt(FBufData);
      if PtrUInt(FBufWidth) * 4 > availBytes then
        FBufWidth := availBytes div 4;
      if PtrUInt(FBufHeight) * PtrUInt(FBufStride) > availBytes then
        FBufHeight := availBytes div FBufStride;
      { AggPas addresses rows as y*FBufStride + x*4, so the last row of the
        sub-region must not write past the row end: FBufWidth*4 must be
        <= FBufStride, otherwise a child wider than the parent row (e.g.
        scroll content during layout) writes past the sub-region/parent
        buffer end on every full-window repaint -> heap corruption. }
      if FBufWidth * 4 > FBufStride then
        FBufWidth := FBufStride div 4;
      if (FBufWidth < 1) or (FBufHeight < 1) then
      begin
        if (pCanvas.FWidget <> nil) then
          fpGUI_Hilog(LOG_WARN, 'DoBeginDraw CHILD clamp: sub-region outside parent buffer, skip (off=' +
            IntToHex(PtrUInt(FBufData) - pStart, 8) + ' avail=' + IntToStr(Int64(availBytes)) + ')' +
            ' wdg=' + awidget.ClassName + ' name=' + awidget.Name +
            ' delta=(' + IntToStr(FDeltaX) + ',' + IntToStr(FDeltaY) + ') log' +
            ' size=(' + IntToStr(awidget.ActualWidth) + 'x' + IntToStr(awidget.ActualHeight) + ') log' +
            ' parentBuf=' + IntToHex(PtrUInt(pCanvas.FBufData), 8) +
            ' ' + IntToStr(pCanvas.FBufWidth) + 'x' + IntToStr(pCanvas.FBufHeight) + ' phys' +
            ' parentWnd=' + pCanvas.FWidget.ClassName)
        else
          fpGUI_Hilog(LOG_WARN, 'DoBeginDraw CHILD clamp: sub-region outside parent buffer, skip (off=' +
            IntToHex(PtrUInt(FBufData) - pStart, 8) + ' avail=' + IntToStr(Int64(availBytes)) + ')' +
            ' wdg=' + awidget.ClassName + ' name=' + awidget.Name +
            ' delta=(' + IntToStr(FDeltaX) + ',' + IntToStr(FDeltaY) + ') log' +
            ' size=(' + IntToStr(awidget.ActualWidth) + 'x' + IntToStr(awidget.ActualHeight) + ') log' +
            ' parentBuf=' + IntToHex(PtrUInt(pCanvas.FBufData), 8) +
            ' ' + IntToStr(pCanvas.FBufWidth) + 'x' + IntToStr(pCanvas.FBufHeight) + ' phys' +
            ' parentWnd=nil');
        Exit;
      end;
      {$else}
      FBufWidth := awidget.ActualWidth;
      FBufHeight := awidget.ActualHeight;
      { Calculate byte offset into parent's buffer so position (0,0) maps
        to the widget's top-left pixel. Both FAgg and FBufData must use
        this same offset pointer so the glyph cache renders into the
        correct sub-region. }
      FBufData := PByte(TOhosHybridCanvas(CanvasTarget).FBufData)
                  + FDeltaX * 4 + FDeltaY * FBufStride;
      {$endif}
      FAgg.attach(int8u_ptr(FBufData), FBufWidth, FBufHeight, FBufStride);
      {$ifdef OHOS}
      { Apply HiDPI scale for child widget. Both the sub-region offset/size
        and the Agg2D transform must use the same scale factor for child
        widgets to render at the correct position and size.
        (Agg2D.HiDPIScaleFactor stays 1.0 for the hybrid canvas, so
        resetTransformations/attach do not install the scale.) }
      if gHiDPIScaleFactor <> 1.0 then
        FAgg.scale(gHiDPIScaleFactor, gHiDPIScaleFactor);
      {$endif}
      {fpGUI_Hilog(LOG_INFO, 'DoBeginDraw CHILD share OK buf=' + IntToHex(PtrUInt(FBufData), 8) +
        ' w=' + IntToStr(FBufWidth) + ' h=' + IntToStr(FBufHeight) +
        ' wdg=' + awidget.ClassName + ' name=' + awidget.Name +
        ' delta=(' + IntToStr(FDeltaX) + ',' + IntToStr(FDeltaY) + ') log' +
        ' size=(' + IntToStr(awidget.ActualWidth) + 'x' + IntToStr(awidget.ActualHeight) + ') log' +
        ' parentBuf=' + IntToHex(PtrUInt(pCanvas.FBufData), 8) +
        ' ' + IntToStr(pCanvas.FBufWidth) + 'x' + IntToStr(pCanvas.FBufHeight) + ' phys');}
      { Zero out deltas: partial-attach already positioned the buffer
        at the widget's origin, so draw calls use widget-local coords. }
      FDeltaX := 0;
      FDeltaY := 0;
    end
    else
      fpGUI_Hilog(LOG_WARN, 'DoBeginDraw CHILD share FAIL: parent buf is nil ct=' + IntToHex(PtrUInt(CanvasTarget), 8));
  end;
end;

procedure TOhosHybridCanvas.DoPutBufferToScreen(x, y, w, h: TfpgCoord);
var
  widgetRect: TfpgRect;
  winRect: TfpgRect;
  dx, dy: TfpgCoord;
begin
  { 扩展子区域刷新为全窗口刷新，匹配非 AGG 行为。
    光标闪烁时，XOR 修改缓冲区，全窗刷新保证显示一致不闪烁。 }
  {if Assigned(FWidget) then
  begin
	  widgetRect := FWidget.GetClientRect;  // (0, 0, 实际宽, 实际高)
	  dx := 0; dy := 0;
	  FWidget.WidgetToWindow(dx, dy);      // 转换到窗口坐标

	  x := dx;
	  y := dy;
	  w := widgetRect.Width;
	  h := widgetRect.Height;
  end;}
  if Assigned(FWidget) and Assigned(FWidget.Window) then
  begin
    winRect := FWidget.Window.GetClientRect;
    if (winRect.Width > 0) and (winRect.Height > 0) then
    begin
      x := 0;
      y := 0;
      { 用窗口实际物理尺寸（resize 反馈更新）换算的逻辑客户区：GetClientRect
        滞后时提交区域偏小 → 窗口拖大后扩大部分无数据（黑色）。
        buffer_manager 内部会再 ×gHiDPIScaleFactor 还原为物理。 }
      if FWidget.Window is TfpgOhosWindow then
      begin
        if TfpgOhosWindow(FWidget.Window).PhysicalWidth > 0 then
          w := Round(TfpgOhosWindow(FWidget.Window).PhysicalWidth / gHiDPIScaleFactor)
        else
          w := winRect.Width;
        if TfpgOhosWindow(FWidget.Window).PhysicalHeight > 0 then
          h := Round(TfpgOhosWindow(FWidget.Window).PhysicalHeight / gHiDPIScaleFactor)
        else
          h := winRect.Height;
      end
      else
      begin
        w := winRect.Width;
        h := winRect.Height;
      end;
    end;
  end;  
  {fpGUI_Hilog(LOG_INFO, 'DoPutBufferToScreen x=' + IntToStr(x) + ' y=' + IntToStr(y) + ' w=' + IntToStr(w) + ' h=' + IntToStr(h) + ' FBufData=' + IntToHex(PtrUInt(FBufData), 8) + ' BM=' + IntToHex(PtrUInt(FBufferManager), 8));}
  if Assigned(FBufferManager) and (FBufData <> nil) then
  begin
    EnsureWindowAttached;
    FBufferManager.PutBufferToScreen(x, y, w, h);
  end;
end;

procedure TOhosHybridCanvas.DoEndDraw;
begin
  { Called during FreeResources (widget destruction).
    Detach from window and release resources. }
  FWindowAttached := False;
  FAttachedWindow := nil;
  if Assigned(FBufferManager) then
    FBufferManager.DetachWindow;
  FCanvasTarget := nil;
end;

function TOhosHybridCanvas.GetBufferAllocated: Boolean;
begin
  if (FCanvasTarget <> nil) and (FCanvasTarget <> Self) then
  begin
    { Alien widget: check the parent's buffer }
    Result := TOhosHybridCanvas(FCanvasTarget).GetBufferAllocated;
  end
  else
  begin
    Result := Assigned(FBufData);
    if Result and Assigned(FWidget) then
    begin
      { If the widget's window was destroyed (popup close/hide), the
        buffer cannot be blitted to screen.  Return False so that the
        Expose handler falls through to InvalidateRect and triggers a
        full repaint when the window is recreated on re-show. }
      if not Assigned(FWidget.Window) then
      begin
        Result := False;
        Exit;
      end;
    end;
  end;
end;

procedure TOhosHybridCanvas.DoAllocateBuffer;
const
  ResizeThreshold = 50;
var
  AllocW, AllocH: Integer;
begin
  if not Assigned(FBufferManager) then
    Exit;
  if not Assigned(FWidget) then
    Exit;

  {$ifdef OHOS}
  { On OHOS, AllocPhysicalBuffer (called from DoBeginDraw) handles
    buffer allocation at physical pixel size. Skip to avoid redundant
    logical-sized allocation. }
  EnsureWindowAttached;
  Exit;
  {$endif}

  { Buffer allocation needs the display connection, so ensure
    the window is attached first (BeginDraw calls us before DoBeginDraw). }
  EnsureWindowAttached;

  AllocW := FWidget.ActualWidth + ResizeThreshold;
  AllocH := FWidget.ActualHeight + ResizeThreshold;

  FBufferManager.AllocateBuffer(AllocW, AllocH, FBufData, FBufStride);
  FBufWidth := AllocW;
  FBufHeight := AllocH;

  { Attach the Agg2D rendering engine to our buffer }
  FAgg.attach(int8u_ptr(FBufData), FBufWidth, FBufHeight, FBufStride);

  // Buffer content is initialised by BeginDraw's Clear or by
  // subsequent DoFillRectangle / DoDrawString calls.
end;

procedure TOhosHybridCanvas.DoRestoreFromBuffer(const ARect: TfpgRect);
begin
  { RestoreFromBuffer can be called from the Expose event handler, outside
    of a BeginDraw/EndDraw pair.  The buffer manager's cached window handle
    may be stale (popup windows are destroyed and recreated between show/hide
    cycles).  Re-attach to the current window so we blit to the right target,
    matching how the X11 canvas reads FWidget.Window.WinHandle directly. }
  EnsureWindowAttached;
  if Assigned(FBufferManager) then
    FBufferManager.RestoreFromBuffer(ARect);
end;

procedure TOhosHybridCanvas.CopyRect(ADest_x, ADest_y: TfpgCoord; ASrcCanvas: TfpgCanvasBase;
  var ASrcRect: TfpgRect);
var
  src: TOhosHybridCanvas;
  sf: Double;
  sx0, sy0, dx0, dy0, pw, ph, i: Integer;
  sRow, dRow: PByte;
begin
  if (ASrcCanvas = nil) or (FBufData = nil) or (FBufStride < 1) then Exit;
  SortRect(ASrcRect);
  if (ASrcRect.Right < ASrcRect.Left) or (ASrcRect.Bottom < ASrcRect.Top) then Exit;

  { Same-canvas copy: fall back to the base per-pixel implementation
    (avoids overlapping memcpy hazards; base Pixels[] is a fast in-memory
    access on this backend). }
  if (ASrcCanvas = Self) or not (ASrcCanvas is TOhosHybridCanvas) then
  begin
    inherited CopyRect(ADest_x, ADest_y, ASrcCanvas, ASrcRect);
    Exit;
  end;

  src := TOhosHybridCanvas(ASrcCanvas);
  if (src.FBufData = nil) or (src.FBufStride < 1) then Exit;

  { Logical coordinates → physical buffer pixels. }
  sf := gHiDPIScaleFactor;
  sx0 := Round(ASrcRect.Left * sf);
  sy0 := Round(ASrcRect.Top * sf);
  pw  := Round((ASrcRect.Right - ASrcRect.Left + 1) * sf);
  ph  := Round((ASrcRect.Bottom - ASrcRect.Top + 1) * sf);
  dx0 := Round(ADest_x * sf);
  dy0 := Round(ADest_y * sf);

  { Clip to source buffer. }
  if sx0 < 0 then begin pw := pw + sx0; sx0 := 0; end;
  if sy0 < 0 then begin ph := ph + sy0; sy0 := 0; end;
  if sx0 + pw > src.FBufWidth  then pw := src.FBufWidth - sx0;
  if sy0 + ph > src.FBufHeight then ph := src.FBufHeight - sy0;
  { Clip to destination buffer. }
  if dx0 < 0 then begin sx0 := sx0 - dx0; pw := pw + dx0; dx0 := 0; end;
  if dy0 < 0 then begin sy0 := sy0 - dy0; ph := ph + dy0; dy0 := 0; end;
  if dx0 + pw > FBufWidth  then pw := FBufWidth - dx0;
  if dy0 + ph > FBufHeight then ph := FBufHeight - dy0;
  if (pw < 1) or (ph < 1) then Exit;

  for i := 0 to ph - 1 do
  begin
    dRow := PByte(FBufData) + (dy0 + i) * FBufStride + dx0 * 4;
    sRow := PByte(src.FBufData) + (sy0 + i) * src.FBufStride + sx0 * 4;
    Move(sRow^, dRow^, pw * 4);
  end;
end;


{ AggFontResourceClass is registered by each platform's fpg_interface.pas
  initialisation block, not here, so this unit remains free of any
  font-engine dependency. }

end.
