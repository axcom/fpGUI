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
      OHOS native_drawing-backed font resource for the hybrid canvas.
      Renders text into the AggPas pixel buffer via a temporary OHOS
      bitmap and OH_Drawing_TextBlob, bypassing AggPas FreeType glyph
      rendering which does not produce scanlines on OHOS.
}

unit fpg_ohos_agg_fontresource;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  fpg_base,
  fpg_ohos_drawing;

type

  TfpgOhosAggFontResource = class(TfpgFontResourceBase)
  private
    FNativeFont: POH_Drawing_Font;
    FNativeTypeface: POH_Drawing_Typeface;
    FAscent: Integer;
    FDescent: Integer;
    FHeight: Integer;
    FIsBold: Boolean;
    FMetricsValid: Boolean;
    FMetrics: TOH_Drawing_FontMetrics;
    { 文本渲染缓存：避免每次绘制创建/销毁临时位图/canvas/笔刷 }
    FCacheBmp: POH_Drawing_Bitmap;
    FCacheCanvas: POH_Drawing_Canvas;
    FCacheBrush: POH_Drawing_Brush;
    FCachePen: POH_Drawing_Pen;      // 描边笔刷（Agg2D 空心/描边文字）
    FCacheW: Integer;   // 缓存位图宽度（物理像素）
    FCacheH: Integer;   // 缓存位图高度
    { 字符 fallback 字体链（缺 glyph 时备用） }
    FFallbackTypefaces: array of POH_Drawing_Typeface;
    procedure   RefreshMetrics;
    procedure   BuildFallbackTypefaces;
    function    LoadTypefaceForName(const APathOrFamily: string): POH_Drawing_Typeface;
  public
    constructor Create(const AFontDesc: string); override;
    destructor  Destroy; override;
    function    HandleIsValid: boolean; override;
    function    GetAscent: integer; override;
    function    GetDescent: integer; override;
    function    GetHeight: integer; override;
    function    GetTextWidth(const txt: string): integer; override;
    procedure   DrawTextToBuffer(ABuf: PByte; AStride, ABufW, ABufH,
      AX, AY: Integer; const AText: string; AColor: TfpgColor;
      AClipX1, AClipY1, AClipX2, AClipY2: Integer); override;
    procedure   DrawTextExtToBuffer(ABuf: PByte; AStride, ABufW, ABufH,
      AX, AY: Integer; const AText: string; AFillColor: TfpgColor;
      AStrokeColor: TfpgColor; AStrokeWidth: Double; AAngleRad: Double;
      AFlipY: Boolean; APivotX, APivotY: Double;
      AClipX1, AClipY1, AClipX2, AClipY2: Integer); override;
    procedure   SetFontFace(const APathOrFamily: string); override;
    procedure   SetTextSize(APtSize: Integer); override;
  end;


implementation

uses
  Math, fpg_main, fpg_ohos;

{ Byte length of one UTF-8 code point, given its first byte.
  Matches the per-character width accumulation used by fpGUI's caret math. }
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

function TryLoadTypeface(out APath: string; AIsBold, AIsItalic: Boolean;
  const AFaceName: string = ''): POH_Drawing_Typeface;
var
  p: string;
  fname: string;
  ttcIdx: Integer;
  hpos: Integer;
  cands: array of string;
begin
  Result := nil;
  APath := '';
  { 应用内置字体文件优先：FontDesc 直接以文件名指定（如 'simsun.ttc#1-12'）时，
    从 resfile/filesDir/libs 解析并按文件创建，优先于系统家族匹配——
    与 fpg_ohos.pas 原生字体链的 TryLoadTypeface 补丁保持一致
    （原生/AGG 两条链行为对齐；任一侧修改需同步）。
    '#N' 后缀指定 TTC 集合内索引（simsun.ttc#1 = NSimSun 严格等宽）；候选名
    同时含小写变体（NormalizeFaceName 会把 'simsun.ttc' 规范为 'Simsun.ttc'，
    而目标文件系统大小写敏感）。 }
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
          IntToStr(ttcIdx) + ' bold=' + IntToStr(Integer(AIsBold)) +
          ' italic=' + IntToStr(Integer(AIsItalic)));
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
  { 应用内置字体文件兜底（resfile/filesDir/libs；系统字体不按路径读，
    见 OhosFindFontFile）}
  if AIsItalic then
    p := OhosResolveFontFile(OhosItalicFontFiles)
  else
    p := OhosResolveFontFile(OhosCJKFontFiles);
  if p <> '' then
  begin
    Result := OH_Drawing_TypefaceCreateFromFile(PChar(p), 0);
    if Result <> nil then
      APath := p;
  end;
end;


{ 字体文件解析统一走 fpg_ohos.OhosFindFontFile：仅应用沙箱目录
  （CWD=resfile、Context.resourceDir/filesDir、bundleCodeDir/libs/<abi>），
  系统字体仅经 FontMgr 家族接口，不按路径读取系统字体文件。 }


{ Agg2D.Font('xxx.ttf') 的文件名 → 字体家族映射（OHOS 无 serif 系统字体时
  映射到最接近的家族；'times' 等家族缺失时 TryLoadSystemTypeface 自动回退
  sans-serif）。返回 '' 表示直接用原名。 }
function MapFontFileToFamily(const AFileName: string): string;
var
  base: string;
  lc: string;
begin
  Result := '';
  base := ExtractFileName(AFileName);
  lc := LowerCase(ChangeFileExt(base, ''));
  { 去掉常见粗体/斜体后缀 }
  if (Length(lc) > 2) and (Copy(lc, Length(lc) - 1, 2) = 'bd') then
    lc := Copy(lc, 1, Length(lc) - 2)
  else if (Length(lc) > 1) and (lc[Length(lc)] = 'i') and
          (Pos('times', lc) = 1) then
    lc := Copy(lc, 1, Length(lc) - 1);

  if (lc = 'times') or (lc = 'tmsrmn') or (lc = 'timesnewroman') then
    Result := 'Times New Roman'
  else if (lc = 'arial') or (lc = 'helv') or (lc = 'helvetica') then
    Result := 'Arial'
  else if (lc = 'verdana') then
    Result := 'Verdana'
  else if (lc = 'courier') or (lc = 'couriernew') then
    Result := 'Courier New'
  else if (lc = 'mono') or (lc = 'monospace') then
    Result := 'monospace'
  else if (lc = 'serif') then
    Result := 'serif'
  else if (lc = 'sans') or (lc = 'sansserif') then
    Result := 'sans-serif';
end;


{ TfpgOhosAggFontResource 按 Agg2D.Font() 请求的文件名/家族切换原生字体。
   优先随包应用字体文件（resfile/filesDir，官方沙箱路径解析），否则按家族名
   走系统 FontMgr；均失败时保持当前字体不变。 }
function TfpgOhosAggFontResource.LoadTypefaceForName(
  const APathOrFamily: string): POH_Drawing_Typeface;
var
  p: string;
  fam: string;
begin
  Result := nil;
  if APathOrFamily = '' then Exit;
  { 1) 应用内置字体文件：resfile(resourceDir)/filesDir/libs，官方路径解析 }
  p := OhosFindFontFile(APathOrFamily);
  if p <> '' then
  begin
    Result := OH_Drawing_TypefaceCreateFromFile(PChar(p), 0);
    if Result <> nil then
    begin
      fpGUI_Hilog(LOG_INFO, 'FONT FILE LOADED: ' + p);
      Exit;
    end;
    fpGUI_Hilog(LOG_INFO, 'FONT FILE FAILED: ' + p);
  end
  else
    fpGUI_Hilog(LOG_INFO, 'FONT FILE NOT FOUND: ' + APathOrFamily);
  { 2) 文件名 → 家族映射（'times.ttf' → 'Times New Roman' 等） }
  fam := MapFontFileToFamily(APathOrFamily);
  if fam = '' then
  begin
    { 无映射时直接用去扩展名后的名字（可能本身就是 'HarmonyOS Sans SC' 之类） }
    fam := ChangeFileExt(ExtractFileName(APathOrFamily), '');
  end;
  fpGUI_Hilog(LOG_INFO, 'FONT FAMILY FALLBACK: ' + fam);
  Result := TryLoadSystemTypeface(p, FIsBold, False, fam);
end;

procedure TfpgOhosAggFontResource.SetFontFace(const APathOrFamily: string);
var
  tf: POH_Drawing_Typeface;
begin
  if APathOrFamily = '' then Exit;
  tf := LoadTypefaceForName(APathOrFamily);
  if tf = nil then Exit;   { 加载失败：保持当前字体 }

  if FNativeTypeface <> nil then
    OH_Drawing_TypefaceDestroy(FNativeTypeface);
  FNativeTypeface := tf;
  if FNativeFont <> nil then
  begin
    OH_Drawing_FontSetTypeface(FNativeFont, FNativeTypeface);
    if FIsBold then
      OH_Drawing_FontSetFakeBoldText(FNativeFont, True);
  end;
  RefreshMetrics;
  { 失效渲染缓存（位图尺寸依赖新字体的 ascent/descent） }
  FCacheW := 0;
  FCacheH := 0;
end;


{ TfpgOhosAggFontResource }

constructor TfpgOhosAggFontResource.Create(const AFontDesc: string);
var
  fd: TfpgFontDefinition;
  dummy: string;
begin
  inherited Create(AFontDesc);
  fd := TfpgFontDefinition.Create(AFontDesc);
  try
    { Font height in PHYSICAL pixels. The Agg2D canvas applies
      gHiDPIScaleFactor (logical→physical), and the logical font height
      is fd.Size * 96/72 (96dpi design, pt→px). So the physical height
      must be logical * gHiDPIScaleFactor, and GetHeight (= FHeight/sf)
      returns the logical value the layout engine expects.
      NOTE: the old '160/96 * gZoomScale' term was an Android-dpi leftover
      that made fonts ~12% smaller than the design height. }
    FHeight := Round(fd.Size * 96 / 72 * gScaleFactor * gHiDPIScaleFactor);
    FIsBold := fpgFontBold in fd.Attributes;

    FNativeTypeface := TryLoadTypeface(dummy, fpgFontBold in fd.Attributes,
      fpgFontItalic in fd.Attributes, fd.FaceName);
    FNativeFont := OH_Drawing_FontCreate();
    if FNativeFont <> nil then
    begin
      if FNativeTypeface <> nil then
        OH_Drawing_FontSetTypeface(FNativeFont, FNativeTypeface);
      OH_Drawing_FontSetTextSize(FNativeFont, FHeight);
      { 合成粗体：系统无独立 Bold 文件；FontMgr 命中真实粗体 style 时不叠加 }
      if FIsBold and (Pos('FontMgr:', dummy) = 0) then
        OH_Drawing_FontSetFakeBoldText(FNativeFont, True);
    end;

    { 渲染缓存初始化 }
    FCacheBmp := nil;
    FCacheCanvas := nil;
    FCacheBrush := nil;
    FCachePen := nil;
    FCacheW := 0;
    FCacheH := 0;

    { 字符 fallback 字体链 }
    BuildFallbackTypefaces;

    RefreshMetrics;
  finally
    fd.Free;
  end;
end;

destructor TfpgOhosAggFontResource.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FFallbackTypefaces) do
    if FFallbackTypefaces[i] <> nil then
      OH_Drawing_TypefaceDestroy(FFallbackTypefaces[i]);
  SetLength(FFallbackTypefaces, 0);
  if FCachePen <> nil then
    OH_Drawing_PenDestroy(FCachePen);
  if FCacheBrush <> nil then
    OH_Drawing_BrushDestroy(FCacheBrush);
  if FCacheCanvas <> nil then
    OH_Drawing_CanvasDestroy(FCacheCanvas);
  if FCacheBmp <> nil then
    OH_Drawing_BitmapDestroy(FCacheBmp);
  if FNativeFont <> nil then
    OH_Drawing_FontDestroy(FNativeFont);
  if FNativeTypeface <> nil then
    OH_Drawing_TypefaceDestroy(FNativeTypeface);
  inherited Destroy;
end;

{ 构建 fallback 字体链：CJK 兜底 + 表情。
  系统字体优先经 FontMgr 家族接口（官方 API，不读系统字体文件），
  失败再试应用内置字体文件（resfile/filesDir）。 }
procedure TfpgOhosAggFontResource.BuildFallbackTypefaces;
var
  p, dummy: string;
  tf: POH_Drawing_Typeface;

  procedure AddTypeface(ATypeface: POH_Drawing_Typeface);
  begin
    if ATypeface = nil then Exit;
    SetLength(FFallbackTypefaces, Length(FFallbackTypefaces) + 1);
    FFallbackTypefaces[High(FFallbackTypefaces)] := ATypeface;
  end;

begin
  SetLength(FFallbackTypefaces, 0);
  { CJK 兜底：FontMgr 家族优先；失败再试应用内置 CJK 文件 }
  dummy := '';
  tf := TryLoadSystemTypeface(dummy, FIsBold, False, '');
  if tf = nil then
  begin
    p := OhosResolveFontFile(OhosCJKFontFiles);
    if p <> '' then
      tf := OH_Drawing_TypefaceCreateFromFile(PChar(p), 0);
  end;
  AddTypeface(tf);
  { emoji：FontMgr 家族优先；失败再试应用内置 emoji 文件 }
  dummy := '';
  tf := TryLoadEmojiTypeface(dummy);
  if tf = nil then
  begin
    p := OhosResolveFontFile(OhosEmojiFontFiles);
    if p <> '' then
      tf := OH_Drawing_TypefaceCreateFromFile(PChar(p), 0);
  end;
  AddTypeface(tf);
end;

procedure TfpgOhosAggFontResource.RefreshMetrics;
begin
  FMetricsValid := False;
  FillChar(FMetrics, SizeOf(FMetrics), 0);
  if (FNativeFont <> nil) and (FNativeTypeface <> nil) then
    FMetricsValid := (OH_Drawing_FontGetMetrics(FNativeFont, @FMetrics) <> 0);
  if FMetricsValid then
  begin
    FAscent := Round(-FMetrics.fAscent);
    FDescent := Round(FMetrics.fDescent);
  end
  else begin
    FAscent := FHeight * 3 div 4;
    FDescent := FHeight div 4;
  end;
end;

function TfpgOhosAggFontResource.HandleIsValid: boolean;
begin
  Result := FNativeFont <> nil;
end;

function TfpgOhosAggFontResource.GetAscent: integer;
var
  sf: Double;
begin
  Result := FAscent;
  { Convert from physical px to logical Agg2D coordinates.
    The Agg2D canvas applies gHiDPIScaleFactor to logical→physical,
    so GetAscent must return logical units to match. }
  sf := gHiDPIScaleFactor;
  if sf <> 1.0 then
    Result := Round(FAscent / sf);
end;

function TfpgOhosAggFontResource.GetDescent: integer;
var
  sf: Double;
begin
  sf := gHiDPIScaleFactor;
  if sf <> 1.0 then
    Result := Round(FDescent / sf)
  else
    Result := FDescent;
end;

function TfpgOhosAggFontResource.GetHeight: integer;
begin
  if FMetricsValid then
    Result := GetAscent + GetDescent
  else
    Result := Round(FHeight / gHiDPIScaleFactor);
//fpGUI_Hilog(LOG_WARN, 'GetHeight=' + IntToStr(Result) + ' gHiDPI=' + FloatToStr(gHiDPIScaleFactor) + ' FHeight=' + IntToStr(FHeight));
end;

function TfpgOhosAggFontResource.GetTextWidth(const txt: string): integer;
var
  i, clen, total: Integer;
  ch: string;
  textWidth: Single;
  ret: Int32;
  sf: Double;
begin
  if txt = '' then Exit(0);
  sf := gHiDPIScaleFactor;
  if sf < 1.0 then sf := 1.0;
  { 逐字符 Round 累加（物理宽 ÷sf 取整后累加）：与渲染步进
    （DrawTextToBuffer 内 Round(chW/sf)*sf）及 fpg_edit 光标/滚动
    定位口径一致，避免整串测量与逐字符定位的累计偏差。 }
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
        textWidth := FHeight * 3 div 5;
    end
    else
      textWidth := FHeight * 3 div 5;

    total := total + Round(textWidth / sf);
    Inc(i, clen);
  end;
  Result := total;
end;

procedure TfpgOhosAggFontResource.DrawTextToBuffer(ABuf: PByte;
  AStride, ABufW, ABufH, AX, AY: Integer; const AText: string;
  AColor: TfpgColor; AClipX1, AClipY1, AClipX2, AClipY2: Integer);
var
  fmt: TOH_Drawing_BitmapFormat;
  textBlob: POH_Drawing_TextBlob;
  textW: Single;
  bmpW, bmpH: Integer;
  srcPixels: PByte;
  srcX, srcY: Integer;
  dstY, dstX: Integer;
  srcPixel: LongWord;
  srcA, srcR, srcG, srcB: Byte;
  invAlpha: Cardinal;
  dstRow: PByte;
  dstOfs: Integer;
  nativeColor: UInt32;
  rgb: TfpgColor;
  sf: Single;
  physX, physY, physCX1, physCY1, physCX2, physCY2: Integer;
  i, clen: Integer;
  ch: string;
  curX, chW: Single;
begin
  if (AText = '') or (ABuf = nil) or (FNativeFont = nil) then Exit;

  { Scale logical coordinates to physical using the Agg2D scale factor.
    gScaleFactor (= VirtualPixelRatio = 1.9) is the OHOS display density,
    but the Agg2D canvas uses gHiDPIScaleFactor (= gFontScaleX = dpi/96)
    for coordinate transformation. These differ on OHOS because the window
    creation also uses gFontScaleX (see DoAllocateWindowHandle). }
  sf := gHiDPIScaleFactor;
  if sf < 1.0 then sf := 1.0;
  physX   := Round(AX * sf);
  physY   := Round(AY * sf);
  physCX1 := Round(AClipX1 * sf);
  physCY1 := Round(AClipY1 * sf);
  physCX2 := Round(AClipX2 * sf);
  physCY2 := Round(AClipY2 * sf);

  { Measure text width — per-character accumulation, matching the drawing
    step used below (and GetTextWidth), so the cache bitmap is never
    narrower than the drawn text. }
  textW := 0;
  i := 1;
  while i <= Length(AText) do
  begin
    clen := Utf8CharLen(Byte(AText[i]));
    if clen < 1 then clen := 1;
    if i + clen - 1 > Length(AText) then clen := Length(AText) - i + 1;
    ch := Copy(AText, i, clen);
    chW := 0;
    OH_Drawing_FontMeasureText(FNativeFont, PChar(ch), Length(ch),
      TEXT_ENCODING_UTF8, nil, @chW);
    textW := textW + chW;
    Inc(i, clen);
  end;
  if (textW <= 0) then
    textW := Length(AText) * FHeight * 0.6;   // 估算宽度，仍尝试 TextBlob 绘制

  bmpW := Round(textW) + 2;
  bmpH := FAscent + FDescent + 2;
  if (bmpW < 1) or (bmpH < 1) then Exit;

  { Convert fpGUI color to native ARGB (R/B swapped, alpha forced) }
  rgb := fpgColorToRGB(AColor);
  if ((rgb shr 24) and $FF) = 0 then
    rgb := rgb or $FF000000;
  nativeColor := (rgb and $FF00FF00) or ((rgb shr 16) and $FF) or ((rgb shl 16) and $FF0000);
  { nativeColor is now AARRGGBB with R and B swapped for OHOS native_drawing }

  { 复用缓存位图/canvas（尺寸不足时重建） }
  fmt.colorFormat := COLOR_FORMAT_RGBA_8888;
  fmt.alphaFormat := ALPHA_FORMAT_UNPREMUL;
  if (FCacheBmp = nil) or (FCacheCanvas = nil) or
     (FCacheW < bmpW) or (FCacheH < bmpH) then
  begin
    if FCacheCanvas <> nil then OH_Drawing_CanvasDestroy(FCacheCanvas);
    if FCacheBmp <> nil then OH_Drawing_BitmapDestroy(FCacheBmp);
    FCacheBmp := OH_Drawing_BitmapCreate();
    FCacheCanvas := OH_Drawing_CanvasCreate();
    FCacheW := 0;
    FCacheH := 0;
    if (FCacheBmp = nil) or (FCacheCanvas = nil) then Exit;
    OH_Drawing_BitmapBuild(FCacheBmp, bmpW, bmpH, @fmt);
    OH_Drawing_CanvasBind(FCacheCanvas, FCacheBmp);
    FCacheW := bmpW;
    FCacheH := bmpH;
  end;

  { Clear to transparent }
  OH_Drawing_CanvasClear(FCacheCanvas, $00000000);

  { 复用笔刷 }
  if FCacheBrush = nil then
    FCacheBrush := OH_Drawing_BrushCreate();
  if FCacheBrush <> nil then
  begin
    OH_Drawing_BrushSetColor(FCacheBrush, nativeColor);
    OH_Drawing_BrushSetAntiAlias(FCacheBrush, True);
    OH_Drawing_CanvasAttachBrush(FCacheCanvas, FCacheBrush);

    { Draw per character and advance by the per-character measured width,
      matching fpGUI's caret/scroll math (TfpgBaseEdit accumulates
      GetTextWidth of each char). A single full-string TextBlob applies
      cross-character kerning and drifts from that model on long text. }
    curX := 0.0;
    i := 1;
    while i <= Length(AText) do
    begin
      clen := Utf8CharLen(Byte(AText[i]));
      if clen < 1 then clen := 1;
      if i + clen - 1 > Length(AText) then clen := Length(AText) - i + 1;
      ch := Copy(AText, i, clen);

      textBlob := OH_Drawing_TextBlobCreateFromText(PChar(ch), Length(ch), FNativeFont,
        TEXT_ENCODING_UTF8);
      if textBlob <> nil then
      begin
        OH_Drawing_CanvasDrawTextBlob(FCacheCanvas, textBlob, curX, FAscent);
        OH_Drawing_TextBlobDestroy(textBlob);
      end;

      chW := 0;
      OH_Drawing_FontMeasureText(FNativeFont, PChar(ch), Length(ch),
        TEXT_ENCODING_UTF8, nil, @chW);
      { Step in physical pixels by the logical per-char width (rounded),
        exactly matching fpGUI's caret math: it accumulates
        Round(measure_phys / sf) per char, then the canvas scales by sf. }
      curX := curX + Round(chW / sf) * sf;
      Inc(i, clen);
    end;

    OH_Drawing_CanvasDetachBrush(FCacheCanvas);
  end;

  { Read pixels back and alpha-blend into target buffer }
  srcPixels := OH_Drawing_BitmapGetPixels(FCacheBmp);
  if srcPixels <> nil then
  begin
    for srcY := 0 to bmpH - 1 do
    begin
      dstY := physY - FAscent + srcY;
      if (dstY < physCY1) or (dstY >= physCY2) then Continue;
      if (dstY < 0) or (dstY >= ABufH) then Continue;

      dstRow := ABuf + dstY * AStride;

      for srcX := 0 to bmpW - 1 do
      begin
        dstX := physX + srcX;
        if (dstX < physCX1) or (dstX >= physCX2) then Continue;
        if (dstX < 0) or (dstX >= ABufW) then Continue;

        { Read RGBA_8888 pixel: R at byte 0, G at byte 1, B at byte 2, A at byte 3.
          缓存位图行宽为 FCacheW（可能大于当前 bmpW），行偏移必须用 FCacheW }
        srcR := srcPixels[(srcY * FCacheW + srcX) * 4 + 0];
        srcG := srcPixels[(srcY * FCacheW + srcX) * 4 + 1];
        srcB := srcPixels[(srcY * FCacheW + srcX) * 4 + 2];
        srcA := srcPixels[(srcY * FCacheW + srcX) * 4 + 3];

        if srcA = 0 then Continue;

        { 三层交换合成恒等（意图色 → 最终缓冲逐位正确）：
          ① nativeColor 以 AARRGGBB 值做 R/B 交换（:378-382）→ OHOS 按
             ARGB 值渲染 → 缓存位图字节 [渲染R, G, 渲染B, A]，其中
             渲染R = 意图B、渲染B = 意图R；
          ② 读回 srcR=byte0 / srcB=byte2 → 变量实际持有意图 B/R
             （名字与显示通道相反，勿按名读）；
          ③ 混合写回 RGBA 序目标缓冲：byte0 ← srcB(=意图R)、
             byte2 ← srcR(=意图B)——与 fpgColorToAgg 的交换同构
             （目标缓冲内存恒为 [意图R, G, 意图B, A]）→ 显示正确。
          黑/白文本 R=G=B 使交换不可见，勿以黑白场景判断本条正确性。 }
        dstOfs := dstX * 4;

        if srcA < 255 then
        begin
          invAlpha := 255 - srcA;
          dstRow[dstOfs + 0] := Byte((Cardinal(srcB) * srcA + Cardinal(dstRow[dstOfs + 0]) * invAlpha + 127) div 255);  // B
          dstRow[dstOfs + 1] := Byte((Cardinal(srcG) * srcA + Cardinal(dstRow[dstOfs + 1]) * invAlpha + 127) div 255);  // G
          dstRow[dstOfs + 2] := Byte((Cardinal(srcR) * srcA + Cardinal(dstRow[dstOfs + 2]) * invAlpha + 127) div 255);  // R
        end
        else
        begin
          dstRow[dstOfs + 0] := srcB;  // B
          dstRow[dstOfs + 1] := srcG;  // G
          dstRow[dstOfs + 2] := srcR;  // R
        end;
        { Alpha byte (byte 3) is left unchanged (opaque buffer) }
      end;
    end;
  end;
end;

{ Agg2D vector-text 模式：填充 + 可选描边（空心/描边字）、旋转（弧度）、
  垂直镜像（倒影）。实现要点：
  - 用 AFillColor 填充（对应 Agg2D 的 FillColor）
  - AStrokeWidth>0 且 AStrokeColor.a<>0 时用 pen 描边（对应 LineColor/LineWidth）
  - 缓存位图内以与 DrawTextToBuffer 完全相同的逐字符方式绘制（基线
    y = FAscent + pad），不调用任何 canvas 变换 API（设备端矩阵会跨调用
    累积且无法复位，导致文字移出位图）；
  - 旋转/翻转在"读回 → 混合进目标缓冲"阶段用逆变换 + 双线性采样实现。
  angle=0 且无翻转且无描边时直接走 DrawTextToBuffer 快路径。 }
procedure TfpgOhosAggFontResource.DrawTextExtToBuffer(ABuf: PByte;
  AStride, ABufW, ABufH, AX, AY: Integer; const AText: string;
  AFillColor: TfpgColor; AStrokeColor: TfpgColor; AStrokeWidth: Double;
  AAngleRad: Double; AFlipY: Boolean; APivotX, APivotY: Double;
  AClipX1, AClipY1, AClipX2, AClipY2: Integer);
var
  sf: Single;
  physBX, physBY: Integer;
  physPX, physPY: Integer;
  offX, offY: Double;
  physCX1, physCY1, physCX2, physCY2: Integer;
  strokePhysW: Single;
  cosA, sinA: Double;
  asc, desc: Integer;
  textW: Double;
  pad, bmpW, bmpH: Integer;
  minX, maxX, minY, maxY: Double;
  cornerX, cornerY, rx2, ry2: Double;
  corners: array[0..3] of record x, y: Double; end;
  i, clen: Integer;
  fmt: TOH_Drawing_BitmapFormat;
  textBlob: POH_Drawing_TextBlob;
  ch: string;
  curX, chW: Single;
  rgb: TfpgColor;
  nativeColor: UInt32;
  srcPixels: PByte;
  dstX0, dstY0, dstX1, dstY1: Integer;
  dx, dy, x0, y0: Integer;
  rx, ry, sx, sy, cx, cy, tx, ty, wx0, wy0: Double;
  r00, g00, b00, a00, r10, g10, b10, a10: Byte;
  r01, g01, b01, a01, r11, g11, b11, a11: Byte;
  outA, outR, outG, outB: Integer;
  invAlpha: Cardinal;
  dstRow: PByte;
  dstOfs: Integer;
  drawFill, drawStroke: Boolean;

  { 采样缓存位图像素（越界 → 全透明） }
  procedure CachePix(px, py: Integer; out pr, pg, pb, pa: Byte);
  begin
    if (px < 0) or (py < 0) or (px >= bmpW) or (py >= bmpH) then
    begin
      pr := 0; pg := 0; pb := 0; pa := 0;
      Exit;
    end;
    pr := srcPixels[(py * FCacheW + px) * 4 + 0];
    pg := srcPixels[(py * FCacheW + px) * 4 + 1];
    pb := srcPixels[(py * FCacheW + px) * 4 + 2];
    pa := srcPixels[(py * FCacheW + px) * 4 + 3];
  end;

begin
  if (AText = '') or (ABuf = nil) or (FNativeFont = nil) then Exit;

  drawFill   := ((AFillColor shr 24) and $FF) <> 0;
  drawStroke := (AStrokeWidth > 0.0) and (((AStrokeColor shr 24) and $FF) <> 0);
  if (not drawFill) and (not drawStroke) then Exit;

  { 快路径：无旋转/翻转且无描边 → 与普通文本渲染完全一致 }
  if (AAngleRad = 0.0) and (not AFlipY) and (not drawStroke) then
  begin
    DrawTextToBuffer(ABuf, AStride, ABufW, ABufH, AX, AY, AText, AFillColor,
      AClipX1, AClipY1, AClipX2, AClipY2);
    Exit;
  end;

  sf := gHiDPIScaleFactor;
  if sf < 1.0 then sf := 1.0;
  { B = 文字块基线起点（缓存内基点）；P = AGG 锚点（旋转中心，
    与桌面引擎 T(-x,-y)·R(θ)·T(x,y) 的 (x,y) 一致）。 }
  physBX := Round(AX * sf);
  physBY := Round(AY * sf);
  physPX := Round(APivotX * sf);
  physPY := Round(APivotY * sf);
  offX := physBX - physPX;
  offY := physBY - physPY;
  { Clip 参数与 DrawTextToBuffer 同口径：逻辑值 × sf → 物理像素 }
  physCX1 := Round(AClipX1 * sf);
  physCY1 := Round(AClipY1 * sf);
  physCX2 := Round(AClipX2 * sf);
  physCY2 := Round(AClipY2 * sf);

  strokePhysW := AStrokeWidth * sf;
  if drawStroke and (strokePhysW < 1.0) then strokePhysW := 1.0;

  cosA := Cos(AAngleRad);
  sinA := Sin(AAngleRad);

  asc  := FAscent;
  desc := FDescent;

  { 测量文本物理宽度（逐字符浮点累加，与绘制步进一致） }
  textW := 0;
  i := 1;
  while i <= Length(AText) do
  begin
    clen := Utf8CharLen(Byte(AText[i]));
    if clen < 1 then clen := 1;
    if i + clen - 1 > Length(AText) then clen := Length(AText) - i + 1;
    ch := Copy(AText, i, clen);
    chW := 0;
    OH_Drawing_FontMeasureText(FNativeFont, PChar(ch), Length(ch),
      TEXT_ENCODING_UTF8, nil, @chW);
    textW := textW + chW;
    Inc(i, clen);
  end;
  if textW <= 0 then textW := Length(AText) * FHeight * 0.6;
  { 向上取整并留 1px 余量，避免旋转后末字符边缘被裁剪 }
  textW := Ceil(textW) + 1;

  { 描边向外扩展 strokePhysW/2，再加 AA 余量 }
  pad := 2 + Max(1, Ceil(strokePhysW / 2.0));
  bmpW := Trunc(textW) + 2 * pad;
  bmpH := asc + desc + 2 * pad;

  { 颜色 → 原生 ARGB（与 DrawTextToBuffer 相同的 R/B 交换约定） }
  rgb := fpgColorToRGB(AFillColor);
  if ((rgb shr 24) and $FF) = 0 then
    rgb := rgb or $FF000000;
  nativeColor := (rgb and $FF00FF00) or ((rgb shr 16) and $FF) or ((rgb shl 16) and $FF0000);

  { 复用缓存位图/canvas（尺寸不足时重建） }
  fmt.colorFormat := COLOR_FORMAT_RGBA_8888;
  fmt.alphaFormat := ALPHA_FORMAT_UNPREMUL;
  if (FCacheBmp = nil) or (FCacheCanvas = nil) or
     (FCacheW < bmpW) or (FCacheH < bmpH) then
  begin
    if FCacheCanvas <> nil then OH_Drawing_CanvasDestroy(FCacheCanvas);
    if FCacheBmp <> nil then OH_Drawing_BitmapDestroy(FCacheBmp);
    FCacheBmp := OH_Drawing_BitmapCreate();
    FCacheCanvas := OH_Drawing_CanvasCreate();
    FCacheW := 0;
    FCacheH := 0;
    if (FCacheBmp = nil) or (FCacheCanvas = nil) then Exit;
    OH_Drawing_BitmapBuild(FCacheBmp, bmpW, bmpH, @fmt);
    OH_Drawing_CanvasBind(FCacheCanvas, FCacheBmp);
    FCacheW := bmpW;
    FCacheH := bmpH;
  end;

  { 清透明背景 }
  OH_Drawing_CanvasClear(FCacheCanvas, $00000000);

  { 复用笔刷/描边笔 }
  if FCacheBrush = nil then
    FCacheBrush := OH_Drawing_BrushCreate();
  if FCachePen = nil then
    FCachePen := OH_Drawing_PenCreate();

  if drawFill and (FCacheBrush <> nil) then
  begin
    OH_Drawing_BrushSetColor(FCacheBrush, nativeColor);
    OH_Drawing_BrushSetAntiAlias(FCacheBrush, True);
    OH_Drawing_CanvasAttachBrush(FCacheCanvas, FCacheBrush);
  end
  else
    OH_Drawing_CanvasDetachBrush(FCacheCanvas);

  if drawStroke and (FCachePen <> nil) then
  begin
    rgb := fpgColorToRGB(AStrokeColor);
    if ((rgb shr 24) and $FF) = 0 then
      rgb := rgb or $FF000000;
    OH_Drawing_PenSetColor(FCachePen,
      (rgb and $FF00FF00) or ((rgb shr 16) and $FF) or ((rgb shl 16) and $FF0000));
    OH_Drawing_PenSetAntiAlias(FCachePen, True);
    OH_Drawing_PenSetWidth(FCachePen, strokePhysW);
    OH_Drawing_CanvasAttachPen(FCacheCanvas, FCachePen);
  end
  else
    OH_Drawing_CanvasDetachPen(FCacheCanvas);

  { 逐字符绘制：与 DrawTextToBuffer 完全相同的布局（基线 y = FAscent + pad，
    行 0 = 基线 - FAscent，即文本块顶），不使用任何 canvas 变换。 }
  curX := 0.0;
  i := 1;
  while i <= Length(AText) do
  begin
    clen := Utf8CharLen(Byte(AText[i]));
    if clen < 1 then clen := 1;
    if i + clen - 1 > Length(AText) then clen := Length(AText) - i + 1;
    ch := Copy(AText, i, clen);

    textBlob := OH_Drawing_TextBlobCreateFromText(PChar(ch), Length(ch), FNativeFont,
      TEXT_ENCODING_UTF8);
    if textBlob <> nil then
    begin
      OH_Drawing_CanvasDrawTextBlob(FCacheCanvas, textBlob, curX, FAscent + pad);
      OH_Drawing_TextBlobDestroy(textBlob);
    end;

    chW := 0;
    OH_Drawing_FontMeasureText(FNativeFont, PChar(ch), Length(ch),
      TEXT_ENCODING_UTF8, nil, @chW);
    curX := curX + Round(chW / sf) * sf;
    Inc(i, clen);
  end;

  OH_Drawing_CanvasDetachBrush(FCacheCanvas);
  OH_Drawing_CanvasDetachPen(FCacheCanvas);

  srcPixels := OH_Drawing_BitmapGetPixels(FCacheBmp);
  if srcPixels = nil then Exit;

  { 目标包围盒：文本块四角（相对基线）→ 翻转（绕基线）→ 平移到块起点
    相对锚点的偏移 → 绕锚点旋转 → 加回锚点，与桌面引擎的
    dst = P + R(θ)·((B-P) + corner) 完全一致 }
  corners[0].x := 0;     corners[0].y := -asc;
  corners[1].x := textW; corners[1].y := -asc;
  corners[2].x := 0;     corners[2].y := desc;
  corners[3].x := textW; corners[3].y := desc;
  minX := 0; maxX := 0; minY := 0; maxY := 0;
  for i := 0 to 3 do
  begin
    cornerX := corners[i].x + offX;
    cornerY := corners[i].y;
    if AFlipY then
      cornerY := -cornerY;                    { 绕基线镜像 }
    cornerY := cornerY + offY;
    rx2 := cornerX * cosA - cornerY * sinA;   { 正旋转（与桌面 Agg 一致） }
    ry2 := cornerX * sinA + cornerY * cosA;
    if (i = 0) or (rx2 < minX) then minX := rx2;
    if (i = 0) or (rx2 > maxX) then maxX := rx2;
    if (i = 0) or (ry2 < minY) then minY := ry2;
    if (i = 0) or (ry2 > maxY) then maxY := ry2;
  end;

  { 描边区域外扩 }
  if drawStroke then
  begin
    minX := minX - strokePhysW * 0.5;
    maxX := maxX + strokePhysW * 0.5;
    minY := minY - strokePhysW * 0.5;
    maxY := maxY + strokePhysW * 0.5;
  end;

  dstX0 := physPX + Trunc(Floor(minX));
  dstX1 := physPX + Trunc(Ceil(maxX));
  dstY0 := physPY + Trunc(Floor(minY));
  dstY1 := physPY + Trunc(Ceil(maxY));

  { 逐目标像素：相对锚点逆旋转 → 减去 (B-P) 偏移 → 逆镜像 → 缓存坐标
    → 双线性采样 → 混合 }
  for dy := dstY0 to dstY1 do
  begin
    if (dy < 0) or (dy >= ABufH) then Continue;
    if (dy < physCY1) or (dy >= physCY2) then Continue;

    dstRow := ABuf + dy * AStride;

    for dx := dstX0 to dstX1 do
    begin
      if (dx < 0) or (dx >= ABufW) then Continue;
      if (dx < physCX1) or (dx >= physCX2) then Continue;

      rx := dx - physPX;
      ry := dy - physPY;
      sx := rx * cosA + ry * sinA;            { 逆旋转（相对锚点） }
      sy := -rx * sinA + ry * cosA;
      sx := sx - offX;                        { 转为相对块基线起点 }
      sy := sy - offY;
      if AFlipY then sy := -sy;               { 逆镜像（绕基线） }
      cx := sx + pad;                          { 缓存坐标：基线 x = pad }
      cy := sy + FAscent + pad;                { 缓存坐标：基线 y = FAscent + pad }

      if (cx < 0) or (cy < 0) or (cx > bmpW - 1) or (cy > bmpH - 1) then Continue;
      x0 := Trunc(cx);
      y0 := Trunc(cy);
      tx := cx - x0;
      ty := cy - y0;
      wx0 := 1.0 - tx;
      wy0 := 1.0 - ty;

      CachePix(x0, y0, r00, g00, b00, a00);
      CachePix(x0 + 1, y0, r10, g10, b10, a10);
      CachePix(x0, y0 + 1, r01, g01, b01, a01);
      CachePix(x0 + 1, y0 + 1, r11, g11, b11, a11);

      { 双线性插值（各通道） }
      outA := Round((a00 * wx0 + a10 * tx) * wy0 + (a01 * wx0 + a11 * tx) * ty);
      if outA <= 0 then Continue;
      if outA > 255 then outA := 255;
      outR := Round((r00 * wx0 + r10 * tx) * wy0 + (r01 * wx0 + r11 * tx) * ty);
      outG := Round((g00 * wx0 + g10 * tx) * wy0 + (g01 * wx0 + g11 * tx) * ty);
      outB := Round((b00 * wx0 + b10 * tx) * wy0 + (b01 * wx0 + b11 * tx) * ty);

      dstOfs := dx * 4;

      if outA < 255 then
      begin
        invAlpha := 255 - outA;
        dstRow[dstOfs + 0] := Byte((Cardinal(outB) * outA + Cardinal(dstRow[dstOfs + 0]) * invAlpha + 127) div 255);
        dstRow[dstOfs + 1] := Byte((Cardinal(outG) * outA + Cardinal(dstRow[dstOfs + 1]) * invAlpha + 127) div 255);
        dstRow[dstOfs + 2] := Byte((Cardinal(outR) * outA + Cardinal(dstRow[dstOfs + 2]) * invAlpha + 127) div 255);
      end
      else
      begin
        dstRow[dstOfs + 0] := outB;
        dstRow[dstOfs + 1] := outG;
        dstRow[dstOfs + 2] := outR;
      end;
    end;
  end;
end;

procedure TfpgOhosAggFontResource.SetTextSize(APtSize: Integer);
var
  physH: Integer;
begin
  { Convert pt → physical px (same formula as constructor):
    logical px = APtSize * 96/72 (pt→px);
    physical px = logical * gScaleFactor * gHiDPIScaleFactor.
    This mirrors what FreeType/WinFonts paths do via m_fontEngine.height_()
    and keeps FHeight, FAscent, FDescent in sync with the new native font size. }
  physH := Round(APtSize * 96 / 72 * gScaleFactor * gHiDPIScaleFactor);
  if physH < 6 then physH := 6;
  if physH = FHeight then Exit;   { no-op if already at this size }

  FHeight := physH;
  FAscent := physH * 3 div 4;
  FDescent := physH div 4;
  FMetricsValid := False;

  if FNativeFont <> nil then
    OH_Drawing_FontSetTextSize(FNativeFont, physH);

  { Invalidate the cache bitmap — its size was computed from the old
    metrics (bmpH = FAscent + FDescent), and the DrawTextToBuffer call
    that follows will rebuild it at the correct new size. }
  FCacheW := 0;
  FCacheH := 0;
end;

end.
