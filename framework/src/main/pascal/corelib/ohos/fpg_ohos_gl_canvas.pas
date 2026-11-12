{
    fpGUI  -  Free Pascal GUI Toolkit

    Copyright (c) 2026 See the file AUTHORS.txt, included in this
    distribution, for details of the copyright.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      Phase 2 GL canvas backend for HarmonyOS.

      All TfpgCanvasBase primitives are rendered with GLES into a retained
      per-window FBO.  Child widgets share the parent's FBO and use scissor
      clipping, so the existing fpGUI alien-widget model works unchanged.

      Text uses a text-run texture cache (TfpgOhosGLTextCache) that reuses
      TfpgFontResourceBase.DrawTextToBuffer; images use a small texture cache
      (TfpgOhosGLTextureCache).  Batching and a glyph atlas are Phase 3 work.
}

unit fpg_ohos_gl_canvas;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  Math,
  CTypes,
  fpg_base,
  fpg_impl,
  fpg_ohos,
  fpg_ohos_egl,
  fpg_ohos_gl,
  fpg_ohos_gl_iface,
  fpg_ohos_gl_draw,
  fpg_ohos_gl_text,
  fpg_ohos_gl_texture;

type
  TfpgGLCanvas = class(TfpgCanvasBase)
  protected
    FGLWindow: TfpgOhosGLWindow;
    FLastGLHandle: TfpgWinHandle;
    FClipRect: TfpgRect;
    function  ResolveWindow(awidget: TfpgWidgetBase;
      out AWidth, AHeight: Integer): TfpgOhosGLWindow;
    procedure UpdateScissor;
    procedure DoSetFontRes(fntres: TfpgFontResourceBase); override;
    procedure DoSetTextColor(cl: TfpgColor); override;
    procedure DoSetColor(cl: TfpgColor); override;
    procedure DoSetLineStyle(awidth: integer; astyle: TfpgLineStyle); override;
    procedure DoFillRectangle(x, y, w, h: TfpgCoord); override;
    procedure DoXORFillRectangle(col: TfpgColor; x, y, w, h: TfpgCoord); override;
    procedure DoFillTriangle(x1, y1, x2, y2, x3, y3: TfpgCoord); override;
    procedure DoDrawRectangle(x, y, w, h: TfpgCoord); override;
    procedure DoDrawLine(x1, y1, x2, y2: TfpgCoord); override;
    procedure DoDrawImagePart(x, y: TfpgCoord; img: TfpgImageBase;
      xi, yi, w, h: integer); override;
    procedure DoStretchDraw(x, y, w, h: TfpgCoord; ASource: TfpgImageBase); override;
    procedure DoDrawString(x, y: TfpgCoord; const txt: string); override;
    procedure DoSetClipRect(const ARect: TfpgRect); override;
    function  DoGetClipRect: TfpgRect; override;
    procedure DoAddClipRect(const ARect: TfpgRect); override;
    procedure DoClearClipRect; override;
    procedure DoBeginDraw(awidget: TfpgWidgetBase;
      CanvasTarget: TfpgCanvasBase); override;
    procedure DoPutBufferToScreen(x, y, w, h: TfpgCoord); override;
    procedure DoEndDraw; override;
    function  GetPixel(X, Y: integer): TfpgColor; override;
    procedure SetPixel(X, Y: integer; const AValue: TfpgColor); override;
    procedure DoDrawArc(x, y, w, h: TfpgCoord; a1, a2: double); override;
    procedure DoFillArc(x, y, w, h: TfpgCoord; a1, a2: double); override;
    procedure DoDrawPolygon(const Points: array of TPoint); override;
    function  GetBufferAllocated: Boolean; override;
    procedure DoAllocateBuffer; override;
    procedure DoRestoreFromBuffer(const ARect: TfpgRect); override;
    { Phase 3: dash/dot line styles. }
    procedure DrawStyledLine(X1, Y1, X2, Y2: Double; AWidth: Integer;
      AColor: TfpgColor);
    { Phase 3: refresh a dirty region of an in-place-modified image. }
    procedure UpdateImageRegion(AImage: TfpgImageBase;
      X, Y, W, H: Integer); override;
  public
    constructor Create(awidget: TfpgWidgetBase); override;
    destructor  Destroy; override;
    procedure GradientFill(ARect: TfpgRect; AStart, AStop: TfpgColor;
      ADirection: TGradientDirection); override;
    procedure CopyRect(ADest_x, ADest_y: TfpgCoord; ASrcCanvas: TfpgCanvasBase;
      var ASrcRect: TfpgRect); override;
  end;

implementation

type
  TGLWindowEntry = class
  public
    Handle: TfpgWinHandle;
    Window: TfpgOhosGLWindow;
  end;

var
  GGLWindows: TList = nil;

function FindWindowEntry(AHandle: TfpgWinHandle): TGLWindowEntry;
var
  i: Integer;
begin
  Result := nil;
  if (GGLWindows = nil) or (AHandle = nil) then
    Exit;
  for i := 0 to GGLWindows.Count - 1 do
    if TGLWindowEntry(GGLWindows[i]).Handle = AHandle then
      Exit(TGLWindowEntry(GGLWindows[i]));
end;

function GetOrCreateGLWindow(AHandle: TfpgWinHandle;
  AWidth, AHeight: Integer): TfpgOhosGLWindow;
var
  e: TGLWindowEntry;
  w: TfpgOhosGLWindow;
begin
  Result := nil;
  if AHandle = nil then
    Exit;

  e := FindWindowEntry(AHandle);
  if e <> nil then
  begin
    if e.Window.State <> glsReady then
    begin
      { Context loss / hide-show: rebuild the surface and FBO.  GL objects
        from the lost context (textures, shaders) are invalid, so drop the
        caches; they re-upload on the next paint. }
      if not e.Window.Recover(AWidth, AHeight) then
        Exit;
      if GLTextCache <> nil then
        GLTextCache.InvalidateAll;
      if GLTextureCache <> nil then
        GLTextureCache.InvalidateAll;
      Exit(e.Window);
    end;
    if (AWidth > 0) and (AHeight > 0) and
       ((e.Window.FBOWidth <> AWidth) or (e.Window.FBOHeight <> AHeight)) then
    begin
      e.Window.Resize(AWidth, AHeight);
      if e.Window.MakeCurrent then
        e.Window.EnsureFBO(AWidth, AHeight);
    end;
    Exit(e.Window);
  end;

  w := TfpgOhosGLWindow.Create;
  if not w.Attach(AHandle, AWidth, AHeight) then
  begin
    w.Free;
    Exit;
  end;
  if not w.EnsureFBO(AWidth, AHeight) then
  begin
    w.Free;
    Exit;
  end;

  e := TGLWindowEntry.Create;
  e.Handle := AHandle;
  e.Window := w;
  if GGLWindows = nil then
    GGLWindows := TList.Create;
  GGLWindows.Add(e);
  Result := w;
end;

procedure ReleaseGLWindow(AHandle: TfpgWinHandle);
var
  e: TGLWindowEntry;
begin
  e := FindWindowEntry(AHandle);
  if e = nil then
    Exit;
  GGLWindows.Remove(e);
  FreeAndNil(e.Window);
  e.Free;
end;

procedure ReleaseAllGLWindows;
var
  i: Integer;
  e: TGLWindowEntry;
begin
  if GGLWindows = nil then
    Exit;
  for i := GGLWindows.Count - 1 downto 0 do
  begin
    e := TGLWindowEntry(GGLWindows[i]);
    FreeAndNil(e.Window);
    e.Free;
  end;
  GGLWindows.Clear;
end;

procedure CanvasWindowNotify(AWinHandle: TfpgWinHandle;
  AEvent: TGLWindowEvent; AWidth, AHeight: Integer);
var
  e: TGLWindowEntry;
begin
  case AEvent of
    gleResize:
      begin
        e := FindWindowEntry(AWinHandle);
        if e <> nil then
        begin
          e.Window.Resize(AWidth, AHeight);
          if e.Window.MakeCurrent then
            e.Window.EnsureFBO(AWidth, AHeight);
        end;
      end;
    gleHide:
      begin
        e := FindWindowEntry(AWinHandle);
        if e <> nil then
          e.Window.Suspend;
      end;
    gleDestroy:
      begin
        e := FindWindowEntry(AWinHandle);
        if e <> nil then
          e.Window.Suspend;
      end;
    gleResetFirstFrame:
      begin
        e := FindWindowEntry(AWinHandle);
        if e <> nil then
          e.Window.ResetFirstFrame;
      end;
  end;
end;

{ ── TfpgGLCanvas ───────────────────────────────────────────────────── }

constructor TfpgGLCanvas.Create(awidget: TfpgWidgetBase);
begin
  inherited Create(awidget);
  FGLWindow := nil;
  FLastGLHandle := nil;
  FClipRect.Clear;
end;

destructor TfpgGLCanvas.Destroy;
begin
  FGLWindow := nil;
  inherited Destroy;
end;

function TfpgGLCanvas.ResolveWindow(awidget: TfpgWidgetBase;
  out AWidth, AHeight: Integer): TfpgOhosGLWindow;
var
  win: TfpgOhosWindow;
  r: TfpgRect;
begin
  Result := nil;
  AWidth := 0;
  AHeight := 0;
  if (awidget = nil) or (awidget.Window = nil) then
    Exit;
  if not (awidget.Window is TfpgOhosWindow) then
    Exit;
  win := TfpgOhosWindow(awidget.Window);
  if win.WinHandle = nil then
    Exit;

  AWidth := win.PhysicalWidth;
  AHeight := win.PhysicalHeight;
  if (AWidth <= 0) or (AHeight <= 0) then
  begin
    r := win.GetClientRect;
    AWidth := Round(r.Width * gHiDPIScaleFactor);
    AHeight := Round(r.Height * gHiDPIScaleFactor);
  end;
  if (AWidth <= 0) or (AHeight <= 0) then
    Exit;

  FLastGLHandle := win.WinHandle;
  Result := GetOrCreateGLWindow(win.WinHandle, AWidth, AHeight);
end;

procedure TfpgGLCanvas.UpdateScissor;
var
  sr: TfpgRect;
begin
  if (FGLWindow = nil) or (GLDraw = nil) then
    Exit;
  { FClipRect is kept in widget-local coordinates (the contract of
    GetClipRect); the GL scissor needs window/FBO coordinates. }
  if FClipRect.IsUnassigned then
  begin
    GLDraw.SetScissor(FClipRect, False);
    Exit;
  end;
  sr := FClipRect;
  sr.OffsetRect(FDeltaX, FDeltaY);
  sr.IntersectRect(sr, GetWidgetWindowRect);
  GLDraw.SetScissor(sr, True);
end;

procedure TfpgGLCanvas.DoSetFontRes(fntres: TfpgFontResourceBase);
begin
  FFont := fntres;
end;

procedure TfpgGLCanvas.DoSetTextColor(cl: TfpgColor);
begin
  FTextColor := cl;
end;

procedure TfpgGLCanvas.DoSetColor(cl: TfpgColor);
begin
  FColor := cl;
end;

procedure TfpgGLCanvas.DoSetLineStyle(awidth: integer; astyle: TfpgLineStyle);
begin
  FLineWidth := awidth;
  FLineStyle := astyle;
end;

procedure TfpgGLCanvas.DoFillRectangle(x, y, w, h: TfpgCoord);
var
  r: TfpgRect;
begin
  if (w <= 0) or (h <= 0) or (FGLWindow = nil) then
    Exit;
  UpdateScissor;
  r.SetRect(x + FDeltaX, y + FDeltaY, w, h);
  GLDraw.DrawSolidQuad(r, FColor);
end;

procedure TfpgGLCanvas.DoXORFillRectangle(col: TfpgColor;
  x, y, w, h: TfpgCoord);
var
  i, j: Integer;
  c, old: TfpgColor;
begin
  if (w <= 0) or (h <= 0) or (FGLWindow = nil) then
    Exit;
  UpdateScissor;
  c := fpgColor(fpgGetRed(col), fpgGetGreen(col), fpgGetBlue(col), $FF);
  for j := 0 to h - 1 do
    for i := 0 to w - 1 do
    begin
      old := GLDraw.ReadPixel(x + FDeltaX + i, y + FDeltaY + j);
      GLDraw.WritePixel(x + FDeltaX + i, y + FDeltaY + j, old xor c);
    end;
end;

procedure TfpgGLCanvas.DoFillTriangle(x1, y1, x2, y2, x3, y3: TfpgCoord);
begin
  if FGLWindow = nil then
    Exit;
  UpdateScissor;
  GLDraw.DrawSolidTriangle(x1 + FDeltaX, y1 + FDeltaY,
    x2 + FDeltaX, y2 + FDeltaY, x3 + FDeltaX, y3 + FDeltaY, FColor);
end;

procedure TfpgGLCanvas.DrawStyledLine(X1, Y1, X2, Y2: Double;
  AWidth: Integer; AColor: TfpgColor);
var
  pat: array of Double;
  dx, dy, len, t, e: Double;
  seg: Integer;
begin
  if FLineStyle = lsSolid then
  begin
    GLDraw.DrawLine(X1, Y1, X2, Y2, AWidth, AColor);
    Exit;
  end;

  case FLineStyle of
    lsDash:
      begin
        SetLength(pat, 2); pat[0] := 6; pat[1] := 4;
      end;
    lsDot:
      begin
        SetLength(pat, 2); pat[0] := 1; pat[1] := 3;
      end;
    lsDashDot:
      begin
        SetLength(pat, 4);
        pat[0] := 6; pat[1] := 4; pat[2] := 1; pat[3] := 4;
      end;
    lsDashDotDot:
      begin
        SetLength(pat, 6);
        pat[0] := 6; pat[1] := 4; pat[2] := 1;
        pat[3] := 4; pat[4] := 1; pat[5] := 4;
      end;
  else
    GLDraw.DrawLine(X1, Y1, X2, Y2, AWidth, AColor);
    Exit;
  end;

  dx := X2 - X1;
  dy := Y2 - Y1;
  len := Sqrt(dx * dx + dy * dy);
  if len < 0.01 then
    Exit;
  dx := dx / len;
  dy := dy / len;
  t := 0;
  seg := 0;
  while t < len do
  begin
    e := t + pat[seg];
    if e > len then
      e := len;
    if (seg and 1) = 0 then
      GLDraw.DrawLine(X1 + dx * t, Y1 + dy * t,
        X1 + dx * e, Y1 + dy * e, AWidth, AColor);
    t := e;
    seg := (seg + 1) mod Length(pat);
  end;
end;

procedure TfpgGLCanvas.DoDrawRectangle(x, y, w, h: TfpgCoord);
var
  lw: Integer;
  x1, y1, x2, y2: TfpgCoord;
begin
  if (w <= 0) or (h <= 0) or (FGLWindow = nil) then
    Exit;
  UpdateScissor;
  lw := FLineWidth;
  if lw < 1 then
    lw := 1;
  x1 := x + FDeltaX;
  y1 := y + FDeltaY;
  x2 := x1 + w - 1;
  y2 := y1 + h - 1;
  DrawStyledLine(x1, y1, x2, y1, lw, FColor);
  DrawStyledLine(x2, y1, x2, y2, lw, FColor);
  DrawStyledLine(x2, y2, x1, y2, lw, FColor);
  DrawStyledLine(x1, y2, x1, y1, lw, FColor);
end;

procedure TfpgGLCanvas.DoDrawLine(x1, y1, x2, y2: TfpgCoord);
var
  lw: Integer;
begin
  if FGLWindow = nil then
    Exit;
  UpdateScissor;
  lw := FLineWidth;
  if lw < 1 then
    lw := 1;
  DrawStyledLine(x1 + FDeltaX, y1 + FDeltaY,
    x2 + FDeltaX, y2 + FDeltaY, lw, FColor);
end;

procedure TfpgGLCanvas.DoDrawImagePart(x, y: TfpgCoord;
  img: TfpgImageBase; xi, yi, w, h: integer);
var
  tex: GLuint;
  swizzle: Boolean;
  r: TfpgRect;
  uv: TGLUV;
  imgW, imgH: Integer;
begin
  if (img = nil) or (FGLWindow = nil) or (w <= 0) or (h <= 0) then
    Exit;
  if GLTextureCache = nil then
    Exit;
  UpdateScissor;
  tex := GLTextureCache.GetTexture(img, swizzle);
  if tex = 0 then
    Exit;
  imgW := img.Width;
  imgH := img.Height;
  if (imgW <= 0) or (imgH <= 0) then
    Exit;
  r.SetRect(x + FDeltaX, y + FDeltaY, w, h);
  uv.U1 := xi / imgW;
  uv.V1 := yi / imgH;
  uv.U2 := (xi + w) / imgW;
  uv.V2 := (yi + h) / imgH;
  GLDraw.DrawTexturedQuad(r, tex, clWhite, swizzle, False, True, uv);
end;

procedure TfpgGLCanvas.DoStretchDraw(x, y, w, h: TfpgCoord;
  ASource: TfpgImageBase);
var
  tex: GLuint;
  swizzle: Boolean;
  r: TfpgRect;
  uv: TGLUV;
begin
  if (ASource = nil) or (FGLWindow = nil) or (w <= 0) or (h <= 0) then
    Exit;
  if GLTextureCache = nil then
    Exit;
  UpdateScissor;
  tex := GLTextureCache.GetTexture(ASource, swizzle);
  if tex = 0 then
  begin
    inherited DoStretchDraw(x, y, w, h, ASource);
    Exit;
  end;
  r.SetRect(x + FDeltaX, y + FDeltaY, w, h);
  uv.U1 := 0; uv.V1 := 0; uv.U2 := 1; uv.V2 := 1;
  GLDraw.DrawTexturedQuad(r, tex, clWhite, swizzle, True, True, uv);
end;

procedure TfpgGLCanvas.DoDrawString(x, y: TfpgCoord; const txt: string);
begin
  if (txt = '') or (FGLWindow = nil) or (FFont = nil) then
    Exit;
  if GLTextCache = nil then
    Exit;
  UpdateScissor;
  GLTextCache.DrawText(GLDraw, FFont, txt, x + FDeltaX, y + FDeltaY,
    FTextColor, gHiDPIScaleFactor);
end;

procedure TfpgGLCanvas.DoSetClipRect(const ARect: TfpgRect);
begin
  { GetClipRect must return widget-local coordinates: widgets (notably
    TfpgBaseTextEdit's caret/text baseline) use GetClipRect.Top/Left as local
    offsets.  Only UpdateScissor converts to window coordinates. }
  FClipRect := ARect;
  UpdateScissor;
end;

function TfpgGLCanvas.DoGetClipRect: TfpgRect;
begin
  Result := FClipRect;
end;

procedure TfpgGLCanvas.DoAddClipRect(const ARect: TfpgRect);
var
  r: TfpgRect;
begin
  r := ARect;
  r.IntersectRect(r, FClipRect);
  FClipRect := r;
  UpdateScissor;
end;

procedure TfpgGLCanvas.DoClearClipRect;
var
  r: TfpgRect;
begin
  if FWidget = nil then
    Exit;
  r.SetRect(0, 0, FWidget.ActualWidth, FWidget.ActualHeight);
  DoSetClipRect(r);
end;

procedure TfpgGLCanvas.DoBeginDraw(awidget: TfpgWidgetBase;
  CanvasTarget: TfpgCanvasBase);
var
  w, h: Integer;
begin
  if CanvasTarget = Self then
  begin
    FGLWindow := ResolveWindow(awidget, w, h);
    if FGLWindow = nil then
      Exit;
    if not FGLWindow.MakeCurrent then
      Exit;
    if not FGLWindow.EnsureFBO(w, h) then
    begin
      FGLWindow := nil;
      Exit;
    end;
    GLDraw.BeginFrame(FGLWindow, gHiDPIScaleFactor);
  end
  else if CanvasTarget is TfpgGLCanvas then
  begin
    FGLWindow := TfpgGLCanvas(CanvasTarget).FGLWindow;
    if FGLWindow = nil then
      Exit;
    if not FGLWindow.MakeCurrent then
      Exit;
    GLDraw.BeginFrame(FGLWindow, gHiDPIScaleFactor);
  end
  else
    Exit;

  FClipRect.SetRect(0, 0, awidget.ActualWidth, awidget.ActualHeight);
  UpdateScissor;
end;

procedure TfpgGLCanvas.DoPutBufferToScreen(x, y, w, h: TfpgCoord);
begin
  if FGLWindow = nil then
    Exit;
  GLDraw.Flush;
  { Phase 3: defer the swap; the message pump presents once per iteration
    (VSync commit coalescing). }
  FGLWindow.PresentPending := True;
end;

procedure TfpgGLCanvas.DoEndDraw;
begin
  FGLWindow := nil;
end;

function TfpgGLCanvas.GetPixel(X, Y: integer): TfpgColor;
begin
  if FGLWindow = nil then
    Exit(0);
  Result := GLDraw.ReadPixel(X + FDeltaX, Y + FDeltaY);
end;

procedure TfpgGLCanvas.SetPixel(X, Y: integer; const AValue: TfpgColor);
begin
  if FGLWindow = nil then
    Exit;
  UpdateScissor;
  GLDraw.WritePixel(X + FDeltaX, Y + FDeltaY, AValue);
end;

procedure TfpgGLCanvas.DoDrawArc(x, y, w, h: TfpgCoord; a1, a2: double);
const
  Segments = 32;
var
  i: Integer;
  a, step, cx, cy, rx, ry: Double;
  p1, p2: TPoint;
begin
  if (FGLWindow = nil) or (w <= 0) or (h <= 0) then
    Exit;
  UpdateScissor;
  cx := x + FDeltaX + w / 2;
  cy := y + FDeltaY + h / 2;
  rx := w / 2;
  ry := h / 2;
  step := a2 / Segments;
  for i := 0 to Segments - 1 do
  begin
    a := a1 + i * step;
    p1 := Point(Round(cx + rx * Cos(a)), Round(cy + ry * Sin(a)));
    p2 := Point(Round(cx + rx * Cos(a + step)), Round(cy + ry * Sin(a + step)));
    DrawStyledLine(p1.X, p1.Y, p2.X, p2.Y, FLineWidth, FColor);
  end;
end;

procedure TfpgGLCanvas.DoFillArc(x, y, w, h: TfpgCoord; a1, a2: double);
const
  Segments = 32;
var
  i: Integer;
  a, step, cx, cy, rx, ry: Double;
  p1, p2: TPoint;
begin
  if (FGLWindow = nil) or (w <= 0) or (h <= 0) then
    Exit;
  UpdateScissor;
  cx := x + FDeltaX + w / 2;
  cy := y + FDeltaY + h / 2;
  rx := w / 2;
  ry := h / 2;
  step := a2 / Segments;
  for i := 0 to Segments - 1 do
  begin
    a := a1 + i * step;
    p1 := Point(Round(cx + rx * Cos(a)), Round(cy + ry * Sin(a)));
    p2 := Point(Round(cx + rx * Cos(a + step)), Round(cy + ry * Sin(a + step)));
    GLDraw.DrawSolidTriangle(cx, cy, p1.X, p1.Y, p2.X, p2.Y, FColor);
  end;
end;

procedure TfpgGLCanvas.DoDrawPolygon(const Points: array of TPoint);
var
  pts: array of TPoint;
  i: Integer;
begin
  if (FGLWindow = nil) or (Length(Points) < 2) then
    Exit;
  UpdateScissor;
  SetLength(pts, Length(Points));
  for i := 0 to High(Points) do
  begin
    pts[i].X := Points[i].X + FDeltaX;
    pts[i].Y := Points[i].Y + FDeltaY;
  end;
  GLDraw.DrawPolygon(pts, FColor);
end;

function TfpgGLCanvas.GetBufferAllocated: Boolean;
begin
  Result := (FGLWindow <> nil) and FGLWindow.HasFBO;
end;

procedure TfpgGLCanvas.DoAllocateBuffer;
var
  w, h: Integer;
begin
  if FWidget = nil then
    Exit;
  FGLWindow := ResolveWindow(FWidget, w, h);
  if FGLWindow = nil then
    Exit;
  if FGLWindow.MakeCurrent then
    FGLWindow.EnsureFBO(w, h);
end;

procedure TfpgGLCanvas.DoRestoreFromBuffer(const ARect: TfpgRect);
begin
  if FGLWindow <> nil then
    FGLWindow.PresentFBO;
end;

procedure TfpgGLCanvas.GradientFill(ARect: TfpgRect; AStart, AStop: TfpgColor;
  ADirection: TGradientDirection);
var
  r: TfpgRect;
begin
  if FGLWindow = nil then
    Exit;
  UpdateScissor;
  r := ARect;
  r.OffsetRect(FDeltaX, FDeltaY);
  GLDraw.DrawGradientQuad(r, AStart, AStop, ADirection = gdVertical);
end;

procedure TfpgGLCanvas.CopyRect(ADest_x, ADest_y: TfpgCoord;
  ASrcCanvas: TfpgCanvasBase; var ASrcRect: TfpgRect);
var
  src: TfpgGLCanvas;
  sx, sy, dx, dy, w, h: Integer;
begin
  if (ASrcCanvas = nil) or (FGLWindow = nil) then
    Exit;
  if ASrcCanvas is TfpgGLCanvas then
  begin
    src := TfpgGLCanvas(ASrcCanvas);
    if src.FGLWindow <> nil then
    begin
      SortRect(ASrcRect);
      w := ASrcRect.Width;
      h := ASrcRect.Height;
      if (w <= 0) or (h <= 0) then
        Exit;
      sx := ASrcRect.Left + src.FDeltaX;
      sy := ASrcRect.Top + src.FDeltaY;
      dx := ADest_x + FDeltaX;
      dy := ADest_y + FDeltaY;
      if src.FGLWindow = FGLWindow then
        GLDraw.CopyRect(sx, sy, dx, dy, w, h)
      else
        GLDraw.CopyRectFromWindow(src.FGLWindow, sx, sy, dx, dy, w, h);
      Exit;
    end;
  end;
  inherited CopyRect(ADest_x, ADest_y, ASrcCanvas, ASrcRect);
end;

procedure TfpgGLCanvas.UpdateImageRegion(AImage: TfpgImageBase;
  X, Y, W, H: Integer);
begin
  if (GLTextureCache <> nil) and (AImage <> nil) then
    GLTextureCache.UpdateRegion(AImage, X, Y, W, H);
end;

{ Present every window whose FBO changed since the last pump iteration. }
procedure FlushPresents;
var
  i: Integer;
  e: TGLWindowEntry;
begin
  if GGLWindows = nil then
    Exit;
  for i := 0 to GGLWindows.Count - 1 do
  begin
    e := TGLWindowEntry(GGLWindows[i]);
    if (e.Window <> nil) and e.Window.PresentPending then
    begin
      e.Window.PresentPending := False;
      if e.Window.MakeCurrent then
        e.Window.PresentFBO;
    end;
  end;
end;

initialization
  GLFlushPresents := @FlushPresents;
  AddGLWindowListener(@CanvasWindowNotify);

finalization
  GLFlushPresents := nil;
  RemoveGLWindowListener(@CanvasWindowNotify);
  ReleaseAllGLWindows;
  FreeAndNil(GGLWindows);

end.
