{
    This unit is part of the fpGUI Toolkit project.

    Copyright (c) 2026 by Graeme Geldenhuys.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      Platform-independent glyph cache for the hybrid canvas. Wraps
      the AggPas FreeType font engine and font_cache_manager to rasterise
      glyphs as gray8 bitmaps, then composites them directly into a BGRA
      pixel buffer via a tight alpha-blend loop — bypassing the full AGG
      scanline renderer pipeline for maximum performance.

      Font file resolution uses the existing fpg_fontcache infrastructure
      (TFontCacheList / gFontCache) which discovers TTF/OTF files across
      OS-specific search paths and caches family+style -> filepath mappings.
}

unit fpg_glyph_cache;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  fpg_base;

type

  { TGlyphCache — cached FreeType bitmap glyph renderer.

    Rasterises glyphs once via FreeType into gray8 alpha-coverage bitmaps,
    caches them via agg_font_cache_manager, and composites into a BGRA
    pixel buffer using a direct alpha-blend loop (no AGG renderer pipeline).

    Usage:
      1. Call SetFont() when the font changes (resolves descriptor to file path)
      2. Call DrawText() to render text into the buffer
      3. Call TextWidth() to measure text width }

  TGlyphCache = class(TObject)
  private
    FInitialised: Boolean;
    FCurrentFontDesc: string;
    FCurrentFontPath: string;
    FCurrentSize: double;
    FCurrentBold: Boolean;
    FCurrentItalic: Boolean;
    FCurrentScale: Double;
    FScale: Double;
    FAscent: Integer;
    FDescent: Integer;
    FLineHeight: Integer;
    FEnginePtr: Pointer;       { ^font_engine_freetype_int32 }
    FCacheManagerPtr: Pointer;  { ^font_cache_manager }
    { CJK/glyph fallback engine: used when the primary font has no glyph
      for a code point (e.g. Roboto has no Han characters). }
    FFallbackTried: Boolean;
    FFallbackPath: string;
    FFallbackEnginePtr: Pointer;
    FFallbackCacheManagerPtr: Pointer;
    FFallbackSizedSize: double;
    FFallbackSizedScale: Double;
    procedure SetScale(AValue: Double);
    procedure EnsureInitialised;
    procedure EnsureFallback;
    procedure SizeFallbackEngine;
    { Returns a glyph_cache_ptr (agg unit type not visible in the
      interface); Pointer keeps the declaration unit-independent. }
    function TryFallbackGlyph(ACharId: Cardinal): Pointer;
    procedure BlitGlyph(ABuf: PByte; AStride, ABufW, ABufH: Integer;
      AGlyphData: PByte; ADataSize: Cardinal;
      ADestX, ADestY: Integer;
      AR, AG, AB: Byte;
      AClipX1, AClipY1, AClipX2, AClipY2: Integer);
    function ResolveFontPath(const AFontDesc: string;
      out ASize: double; out ABold, AItalic: Boolean): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetFont(AFontRes: TfpgFontResourceBase);
    { DrawText renders at baseline Y — caller must add Ascent to convert
      from top-of-text to baseline. }
    procedure DrawText(ABuf: PByte; AStride, ABufW, ABufH: Integer;
      AX, AY: Integer; const AText: string; AColor: TfpgColor); overload;
    procedure DrawText(ABuf: PByte; AStride, ABufW, ABufH: Integer;
      AX, AY: Integer; const AText: string; AColor: TfpgColor;
      AClipX1, AClipY1, AClipX2, AClipY2: Integer); overload;
    function TextWidth(const AText: string): Integer;
    { Font metrics from the same FreeType instance that renders glyphs.
      Guaranteed consistent with rendered output.
      NOTE: metrics and glyph bitmaps are in DEVICE pixels when Scale<>1;
      the caller converts to logical units by dividing by Scale. }
    property Ascent: Integer read FAscent;
    property Descent: Integer read FDescent;
    property LineHeight: Integer read FLineHeight;
    { Device pixels per logical pixel (HiDPI). 1.0 = no scaling.
      Positions passed to DrawText must already be scaled by the caller. }
    property Scale: Double read FScale write SetScale;
  end;


implementation

uses
  fpg_main,
  fpg_fontcache,
  fpg_stringutils,
  agg_basics,
  agg_font_freetype,
  agg_font_freetype_lib,
  agg_font_engine,
  agg_font_cache_manager;


type
  PFontEngine = ^font_engine_freetype_int32;
  PCacheManager = ^font_cache_manager;

{$IFDEF OHOS}
procedure OH_LOG_Print(logType: Integer; logLevel: Integer;
  domain: Cardinal; tag: PChar; fmt: PChar); cdecl; varargs;
  external 'libhilog_ndk.z.so';
const
  LOG_APP  = 0;
  LOG_INFO = 3;
  LOG_WARN = 4;
  LOG_ERROR = 5;
  FP_LOG_DOMAIN = $FF00;
  FP_LOG_TAG = 'fpGUI';
procedure fpGUI_Hilog(level: Integer; const Msg: String);
var
  buf: array[0..1023] of Char;
begin
  StrPCopy(buf, Msg);
  OH_LOG_Print(LOG_APP, level, FP_LOG_DOMAIN, FP_LOG_TAG, '%{public}s', buf);
end;
{$ELSE}
{$IFDEF ANDROID}
procedure __android_log_write(prio: LongInt; tag, text: PAnsiChar); cdecl;
  external 'log';
const
  LOG_INFO  = 4;
  LOG_WARN  = 5;
  LOG_ERROR = 6;
  FP_LOG_TAG = 'fpGUI-font';
procedure fpGUI_Hilog(level: Integer; const Msg: String);
begin
  { 字形/字体诊断日志量极大（每字形多条），发布构建默认只放行错误；
    调试时定义 FPGLYPH_VERBOSE 打开全部。 }
  {$IFNDEF FPGLYPH_VERBOSE}
  if level < LOG_ERROR then
    Exit;
  {$ENDIF}
  __android_log_write(level, FP_LOG_TAG, PAnsiChar(AnsiString(Msg)));
end;
{$ELSE}
const
  LOG_INFO  = 4;
  LOG_WARN  = 5;
  LOG_ERROR = 6;
procedure fpGUI_Hilog(level: Integer; const Msg: String);
begin
  { Desktop backends: no log sink wired here. }
  if level = 0 then ;
  if Msg = '' then ;
end;
{$ENDIF}
{$ENDIF}

{ Helper: read a little-endian int32 from serialised scanline data }
function ReadInt32(var p: PByte): Int32;
begin
  Result := Int32(p[0]) or (Int32(p[1]) shl 8) or
            (Int32(p[2]) shl 16) or (Int32(p[3]) shl 24);
  Inc(p, 4);
end;


{ TGlyphCache }

constructor TGlyphCache.Create;
begin
  inherited Create;
  FInitialised := False;
  FCurrentFontDesc := '';
  FCurrentFontPath := '';
  FCurrentSize := 0;
  FCurrentBold := False;
  FAscent := 0;
  FDescent := 0;
  FCurrentItalic := False;
  FCurrentScale := 1.0;
  FScale := 1.0;
  FEnginePtr := nil;
  FCacheManagerPtr := nil;
  FFallbackTried := False;
  FFallbackPath := '';
  FFallbackEnginePtr := nil;
  FFallbackCacheManagerPtr := nil;
  FFallbackSizedSize := 0;
  FFallbackSizedScale := 0;
end;

procedure TGlyphCache.SetScale(AValue: Double);
begin
  if AValue < 1.0 then
    AValue := 1.0;
  if FScale = AValue then
    Exit;
  FScale := AValue;
  { Force the next SetFont to reload at the new device size. }
  FCurrentSize := 0;
  FCurrentScale := 0;
end;

destructor TGlyphCache.Destroy;
begin
  if FInitialised then
  begin
    PCacheManager(FCacheManagerPtr)^.Destruct;
    PFontEngine(FEnginePtr)^.Destruct;
    FreeMem(FCacheManagerPtr);
    FreeMem(FEnginePtr);
  end;
  if FFallbackCacheManagerPtr <> nil then
  begin
    PCacheManager(FFallbackCacheManagerPtr)^.Destruct;
    PFontEngine(FFallbackEnginePtr)^.Destruct;
    FreeMem(FFallbackCacheManagerPtr);
    FreeMem(FFallbackEnginePtr);
  end;
  inherited Destroy;
end;

procedure TGlyphCache.EnsureInitialised;
begin
  if FInitialised then
    Exit;
  FEnginePtr := AllocMem(SizeOf(font_engine_freetype_int32));
  FCacheManagerPtr := AllocMem(SizeOf(font_cache_manager));
  PFontEngine(FEnginePtr)^.Construct;
  PCacheManager(FCacheManagerPtr)^.Construct(font_engine_ptr(FEnginePtr));
  FInitialised := True;
end;

function TGlyphCache.ResolveFontPath(const AFontDesc: string;
  out ASize: double; out ABold, AItalic: Boolean): string;
var
  fnt: TFontCacheItem;
  i: Integer;
  facename: string;
  cp: Integer;
  c: char;
  token: string;
  prop: string;

  function NextC: char;
  begin
    Inc(cp);
    if cp > Length(AFontDesc) then
      c := #0
    else
      c := AFontDesc[cp];
    Result := c;
  end;

  procedure NextToken;
  begin
    token := '';
    while (c <> #0) and (c in [' ', 'a'..'z', 'A'..'Z', '_', '0'..'9', '.']) do
    begin
      token := token + c;
      NextC;
    end;
  end;

begin
  Result := '';
  ASize := 10;
  ABold := False;
  AItalic := False;

  { Parse font descriptor: FamilyName-Size[:bold][:italic] }
  cp := 0;
  NextC;
  NextToken;
  facename := token;

  { Substitute common bitmap font names to outline equivalents }
  if CompareText(facename, 'Helv') = 0 then
    facename := FPG_DEFAULT_SANS
  else if CompareText(facename, 'Helvetica') = 0 then
    facename := FPG_DEFAULT_SANS
  else if CompareText(facename, 'Tms Rmn') = 0 then
    facename := 'Times New Roman'
  else if CompareText(facename, 'Times') = 0 then
    facename := 'Times New Roman'
  else if CompareText(facename, 'System Proportional') = 0 then
    facename := FPG_DEFAULT_SANS
  else if CompareText(facename, 'System Monospaced') = 0 then
    facename := FPG_DEFAULT_FIXED
  else if CompareText(facename, 'System VIO') = 0 then
    facename := FPG_DEFAULT_FIXED
  else if CompareText(facename, 'Courier') = 0 then
    facename := 'Courier New'
  else if CompareText(facename, 'Monospace') = 0 then
    facename := FPG_DEFAULT_FIXED;

  if c = '-' then
  begin
    NextC;
    NextToken;
    ASize := StrToIntDef(token, 10);
  end;

  while c = ':' do
  begin
    NextC;
    NextToken;
    prop := UpperCase(token);
    if prop = 'BOLD' then
      ABold := True
    else if prop = 'ITALIC' then
      AItalic := True;
    { Skip '=' value if present }
    if c = '=' then
    begin
      NextC;
      NextToken;
    end;
  end;

  { Look up in font cache }
  fnt := TFontCacheItem.Create('');
  try
    fnt.FamilyName := facename;
    if ABold then
      fnt.IsBold := True;
    if AItalic then
      fnt.IsItalic := True;
    i := gFontCache.Find(fnt);
    if i >= 0 then
      Result := gFontCache.Items[i].FileName
    else
    begin
      { Fallback to default sans }
      fnt.FamilyName := FPG_DEFAULT_SANS;
      fnt.StyleFlags := 0;
      i := gFontCache.Find(fnt);
      if i >= 0 then
        Result := gFontCache.Items[i].FileName;
    end;
    if (Result = '') and (gFontCache.Count > 0) then
    begin
      { Last resort: any cacheable font with a real family name (prefer a
        plain face). Keeps text rendering on systems whose font families
        differ from the built-in defaults (e.g. a minimal Android image
        without Roboto). }
      for i := 0 to gFontCache.Count - 1 do
        if (gFontCache.Items[i] <> nil) and
           (gFontCache.Items[i].FamilyName <> '') and
           (gFontCache.Items[i].StyleFlags = (1 shl 0)) then
        begin
          Result := gFontCache.Items[i].FileName;
          Break;
        end;
      if Result = '' then
        for i := 0 to gFontCache.Count - 1 do
          if (gFontCache.Items[i] <> nil) and
             (gFontCache.Items[i].FamilyName <> '') then
          begin
            Result := gFontCache.Items[i].FileName;
            Break;
          end;
    end;
  finally
    fnt.Free;
    fpGUI_Hilog(LOG_INFO, 'ResolveFontPath: desc="' + AFontDesc +
      '" facename="' + facename + '" size=' + FloatToStr(ASize) +
      ' result="' + Result + '"');
  end;
end;

{ Pick a font file that can supply CJK (and other missing) glyphs. }
procedure TGlyphCache.EnsureFallback;
var
  i: Integer;
  item: TFontCacheItem;
  fam, fname: string;
  candidate: string;
begin
  if FFallbackTried then
    Exit;
  FFallbackTried := True;
  candidate := '';

  { Priority 1: CJK-capable families by family name. }
  for i := 0 to gFontCache.Count - 1 do
  begin
    item := gFontCache.Items[i];
    if (item = nil) or (item.FamilyName = '') then
      Continue;
    fam := item.FamilyName;
    if (Pos('CJK', fam) > 0) or (Pos('Noto Sans SC', fam) > 0) or
       (Pos('Noto Sans TC', fam) > 0) or (Pos('Droid Sans Fallback', fam) > 0) then
    begin
      candidate := item.FileName;
      Break;
    end;
  end;

  { Priority 2: known fallback file names. }
  if candidate = '' then
    for i := 0 to gFontCache.Count - 1 do
    begin
      item := gFontCache.Items[i];
      if item = nil then
        Continue;
      fname := ExtractFileName(item.FileName);
      if (Pos('CJK', fname) > 0) or (Pos('DroidSansFallback', fname) > 0) or
         (Pos('NotoSans', fname) > 0) then
      begin
        candidate := item.FileName;
        Break;
      end;
    end;

  if candidate = '' then
    Exit;

  FFallbackEnginePtr := AllocMem(SizeOf(font_engine_freetype_int32));
  FFallbackCacheManagerPtr := AllocMem(SizeOf(font_cache_manager));
  PFontEngine(FFallbackEnginePtr)^.Construct;
  PCacheManager(FFallbackCacheManagerPtr)^.Construct(font_engine_ptr(FFallbackEnginePtr));
  PFontEngine(FFallbackEnginePtr)^.load_font(
    PChar(candidate), 0, glyph_ren_agg_gray8);
  PFontEngine(FFallbackEnginePtr)^.hinting_(True);
  PFontEngine(FFallbackEnginePtr)^.flip_y_(True);
  FFallbackPath := candidate;
  FFallbackSizedSize := 0;
  FFallbackSizedScale := 0;
  fpGUI_Hilog(LOG_INFO, 'glyph fallback font: ' + candidate);
end;

{ Keep the fallback engine at the same device size as the primary font. }
procedure TGlyphCache.SizeFallbackEngine;
var
  px: Integer;
begin
  if FFallbackEnginePtr = nil then
    Exit;
  if (FFallbackSizedSize = FCurrentSize) and (FFallbackSizedScale = FCurrentScale) then
    Exit;
  px := Round(FCurrentSize * fpgApplication.Screen_dpi / 72 * FCurrentScale);
  if px < 1 then
    px := 1;
  PFontEngine(FFallbackEnginePtr)^.height_(px);
  if PFontEngine(FFallbackEnginePtr)^.m_cur_face <> nil then
    FT_Set_Pixel_Sizes(PFontEngine(FFallbackEnginePtr)^.m_cur_face, px, px);
  FFallbackSizedSize := FCurrentSize;
  FFallbackSizedScale := FCurrentScale;
end;

function TGlyphCache.TryFallbackGlyph(ACharId: Cardinal): Pointer;
begin
  Result := nil;
  if FCurrentSize <= 0 then
    Exit;
  EnsureFallback;
  if FFallbackCacheManagerPtr = nil then
    Exit;
  SizeFallbackEngine;
  Result := Pointer(PCacheManager(FFallbackCacheManagerPtr)^.glyph(ACharId));
end;

procedure TGlyphCache.SetFont(AFontRes: TfpgFontResourceBase);
var
  desc: string;
  fontpath: string;
  sz: double;
  bold, italic: Boolean;
begin
  if not Assigned(AFontRes) then
    Exit;

  desc := AFontRes.FontDesc;
  if (desc = FCurrentFontDesc) and (FScale = FCurrentScale) then
    Exit;  { Same font and scale, nothing to do }

  EnsureInitialised;

  fontpath := ResolveFontPath(desc, sz, bold, italic);
  if fontpath = '' then
    Exit;  { Font not found }

  if (fontpath <> FCurrentFontPath) or (sz <> FCurrentSize) or
     (bold <> FCurrentBold) or (italic <> FCurrentItalic) or
     (FScale <> FCurrentScale) then
  begin
    PFontEngine(FEnginePtr)^.load_font(
      PChar(fontpath), 0, glyph_ren_agg_gray8);

    PFontEngine(FEnginePtr)^.hinting_(True);
    PFontEngine(FEnginePtr)^.flip_y_(True);
    PFontEngine(FEnginePtr)^.height_(
      sz * fpgApplication.Screen_dpi / 72 * FScale);

    { Force-correct pixel size. height_ calls FT_Set_Pixel_Sizes via
      update_char_size but may not take effect on some FreeType versions.
      Calling it directly with explicit non-zero pixel_width guarantees
      the face size is set correctly. }
    if PFontEngine(FEnginePtr)^.m_cur_face <> nil then
    begin
      FT_Set_Pixel_Sizes(
        PFontEngine(FEnginePtr)^.m_cur_face,
        Round(sz * fpgApplication.Screen_dpi / 72 * FScale),  { pixel_width }
        Round(sz * fpgApplication.Screen_dpi / 72 * FScale)); { pixel_height }
    end;
                
    { Read metrics from face->size->metrics (populated by FT_Set_Pixel_Sizes).
      These are 26.6 fixed-point values scaled by units_per_EM, which matches
      how X11/Xft computes ascent and descent.

      The AGG wrapper's _ascender/_descender use a different scaling:
        face.ascender * pixel_height / face.height
      where face.height can differ from units_per_EM. This produces
      values that are too small, causing squashed line spacing. }
    FAscent  := (PFontEngine(FEnginePtr)^.m_cur_face^.size^.metrics.ascender + 63) shr 6;
    FDescent := (-PFontEngine(FEnginePtr)^.m_cur_face^.size^.metrics.descender + 63) shr 6;
    FLineHeight := (PFontEngine(FEnginePtr)^.m_cur_face^.size^.metrics.height + 63) shr 6;

    fpGUI_Hilog(LOG_INFO, 'FONT: y_ppem=' +
      IntToStr(PFontEngine(FEnginePtr)^.m_cur_face^.size^.metrics.y_ppem) +
      ' ascent=' + IntToStr(FAscent) +
      ' descent=' + IntToStr(FDescent) +
      ' height=' + IntToStr(FLineHeight));

    FCurrentFontPath := fontpath;
    FCurrentSize := sz;
    FCurrentBold := bold;
    FCurrentItalic := italic;
    FCurrentScale := FScale;
  end;

  FCurrentFontDesc := desc;
end;

procedure TGlyphCache.BlitGlyph(ABuf: PByte; AStride, ABufW, ABufH: Integer;
  AGlyphData: PByte; ADataSize: Cardinal;
  ADestX, ADestY: Integer;
  AR, AG, AB: Byte;
  AClipX1, AClipY1, AClipX2, AClipY2: Integer);
var
  p: PByte;
  minX, minY, maxX, maxY: Int32;
  slSize, slY, numSpans: Int32;
  spanX, spanLen: Int32;
  cover: Byte;
  row: PByte;
  px: PByte;
  srcAlpha, invAlpha: Cardinal;
  drawX, drawY: Integer;
  i, clipLeft, clipRight, clipStart: Integer;
begin
  {$IFDEF FPGLYPH_VERBOSE}
  fpGUI_Hilog(LOG_INFO, 'BlitGlyph ENTER: ADestX=' + IntToStr(ADestX) + ' ADestY=' + IntToStr(ADestY) +
    ' ADataSize=' + IntToStr(ADataSize) + ' AR=' + IntToStr(AR) + ' AG=' + IntToStr(AG) + ' AB=' + IntToStr(AB));
  {$ENDIF}

  if (AGlyphData = nil) or (ADataSize = 0) then
    Exit;

  p := AGlyphData;

  { Read bounding box header: min_x, min_y, max_x, max_y }
  minX := ReadInt32(p);
  minY := ReadInt32(p);
  maxX := ReadInt32(p);
  maxY := ReadInt32(p);
  {$IFDEF FPGLYPH_VERBOSE}
  fpGUI_Hilog(LOG_INFO, 'BlitGlyph bbox: minX=' + IntToStr(minX) + ' minY=' + IntToStr(minY) + ' maxX=' + IntToStr(maxX) + ' maxY=' + IntToStr(maxY) + ' remaining=' + IntToStr(ADataSize - 16));
  {$ENDIF}

  { Iterate serialised scanlines }
  while PtrUInt(p) < PtrUInt(AGlyphData) + ADataSize do
  begin
    slSize := ReadInt32(p);     { scanline size in bytes (including this field) }
    slY := ReadInt32(p);        { Y coordinate of this scanline }
    numSpans := ReadInt32(p);   { number of spans }

    drawY := ADestY + slY;

    { Skip scanlines outside clip rect vertically }
    if (drawY < AClipY1) or (drawY >= AClipY2) then
    begin
      { Skip past remaining span data.
        slSize includes its own 4 bytes, and we already read Y and numSpans (8 bytes),
        so remaining = slSize - 12 }
      Inc(p, slSize - 12);
      Continue;
    end;

    row := ABuf + drawY * AStride;

    while numSpans > 0 do
    begin
      spanX := ReadInt32(p);
      spanLen := ReadInt32(p);

      drawX := ADestX + spanX;

      if spanLen < 0 then
      begin
        { Solid span: single coverage value, |spanLen| pixels }
        cover := p^;
        Inc(p, 1);
        spanLen := -spanLen;

        { Clip horizontally against clip rect }
        clipLeft := drawX;
        clipRight := drawX + spanLen;
        if clipLeft < AClipX1 then clipLeft := AClipX1;
        if clipRight > AClipX2 then clipRight := AClipX2;

        if clipLeft < clipRight then
        begin
          srcAlpha := Cardinal(cover);
          invAlpha := 255 - srcAlpha;
          for i := clipLeft to clipRight - 1 do
          begin
            px := row + i * 4;  { BGRA pixel }
            px[0] := Byte((Cardinal(AB) * srcAlpha + Cardinal(px[0]) * invAlpha + 127) div 255);
            px[1] := Byte((Cardinal(AG) * srcAlpha + Cardinal(px[1]) * invAlpha + 127) div 255);
            px[2] := Byte((Cardinal(AR) * srcAlpha + Cardinal(px[2]) * invAlpha + 127) div 255);
          end;
        end;
      end
      else
      begin
        { Variable span: one coverage byte per pixel }
        clipStart := 0;
        clipLeft := drawX;
        clipRight := drawX + spanLen;
        if clipLeft < AClipX1 then
        begin
          clipStart := AClipX1 - clipLeft;
          clipLeft := AClipX1;
        end;
        if clipRight > AClipX2 then
          clipRight := AClipX2;

        if clipLeft < clipRight then
        begin
          for i := clipStart to clipStart + (clipRight - clipLeft) - 1 do
          begin
            cover := (p + i)^;
            if cover > 0 then
            begin
              px := row + (drawX + i) * 4;  { BGRA pixel }
              srcAlpha := Cardinal(cover);
              invAlpha := 255 - srcAlpha;
              px[0] := Byte((Cardinal(AB) * srcAlpha + Cardinal(px[0]) * invAlpha + 127) div 255);
              px[1] := Byte((Cardinal(AG) * srcAlpha + Cardinal(px[1]) * invAlpha + 127) div 255);
              px[2] := Byte((Cardinal(AR) * srcAlpha + Cardinal(px[2]) * invAlpha + 127) div 255);
            end;
          end;
        end;
        Inc(p, spanLen);
      end;

      Dec(numSpans);
    end;
  end;
end;

procedure TGlyphCache.DrawText(ABuf: PByte; AStride, ABufW, ABufH: Integer;
  AX, AY: Integer; const AText: string; AColor: TfpgColor);
begin
  { Default: clip to full buffer bounds }
  DrawText(ABuf, AStride, ABufW, ABufH, AX, AY, AText, AColor,
    0, 0, ABufW, ABufH);
end;

procedure TGlyphCache.DrawText(ABuf: PByte; AStride, ABufW, ABufH: Integer;
  AX, AY: Integer; const AText: string; AColor: TfpgColor;
  AClipX1, AClipY1, AClipX2, AClipY2: Integer);
var
  engine: PFontEngine;
  cache: PCacheManager;
  glyph: glyph_cache_ptr;
  startY: double;
  lAdv: Double;
  rgb: TfpgColor;
  r, g, b: Byte;
  str_: PChar;
  charLen: int;
  charId: int32u;
  lIsFallback: Boolean;
begin
  if (AText = '') or (ABuf = nil) or not FInitialised then
    Exit;
  {$IFDEF FPGLYPH_VERBOSE}
  fpGUI_Hilog(LOG_WARN, 'AGGDrawText:'+AText);
  {$ENDIF}

  engine := PFontEngine(FEnginePtr);
  cache := PCacheManager(FCacheManagerPtr);

  { Clamp clip rect to buffer bounds }
  if AClipX1 < 0 then AClipX1 := 0;
  if AClipY1 < 0 then AClipY1 := 0;
  if AClipX2 > ABufW then AClipX2 := ABufW;
  if AClipY2 > ABufH then AClipY2 := ABufH;

  { Resolve named colours and extract RGB }
  rgb := fpgColorToRGB(AColor);
  r := (rgb shr 16) and $FF;
  g := (rgb shr 8) and $FF;
  b := rgb and $FF;

  { AY is the baseline Y — caller has already added Ascent. }
  startY := AY;
  lAdv := 0;

  { Iterate UTF-8 characters.

    Advances are quantised to the LOGICAL pixel grid
    (Round(advance / FScale) * FScale) and kerning is not applied: this makes
    the rendered text width strictly additive - width(s) = sum(width(ch)) -
    which the fpGUI edit controls rely on (they mix per-character sums and
    substring widths for the caret position and erase regions; with raw
    fractional advances those two disagree and the caret drifts from the
    glyphs, leaving slivers behind after Backspace). }
  str_ := PChar(AText);

  while str_^ <> #0 do
  begin
    charId := UTF8CharToUnicode(str_, charLen);
    Inc(str_, charLen);

    glyph := cache^.glyph(charId);
    lIsFallback := False;
    { A missing character does NOT yield nil: FreeType renders glyph index 0
      (.notdef, a box). Detect it via glyph_index=0 and try the CJK fallback
      font; draw nothing when even that fails (never a tofu box). }
    if (glyph = nil) or (glyph^.glyph_index = 0) then
    begin
      glyph := glyph_cache_ptr(TryFallbackGlyph(charId));
      lIsFallback := (glyph <> nil) and (glyph^.glyph_index <> 0);
      if not lIsFallback then
        glyph := nil;
    end;
    if glyph <> nil then
    begin
      { Only handle gray8 bitmap data (the fast path) }
      if glyph^.data_type = glyph_data_gray8 then
      begin
        if not lIsFallback then
          cache^.init_embedded_adaptors(glyph, AX + lAdv, startY);
        BlitGlyph(ABuf, AStride, ABufW, ABufH,
          glyph^.data, glyph^.data_size,
          Trunc(AX + lAdv), Trunc(startY),
          r, g, b,
          AClipX1, AClipY1, AClipX2, AClipY2);
      end;

      lAdv := lAdv + Round(glyph^.advance_x / FScale) * FScale;
      startY := startY + glyph^.advance_y;
    end;
  end;
end;

function TGlyphCache.TextWidth(const AText: string): Integer;
var
  cache: PCacheManager;
  glyph: glyph_cache_ptr;
  x: double;
  str_: PChar;
  charLen: int;
  charId: int32u;
  lIsFallback: Boolean;
begin
  Result := 0;
  if (AText = '') or not FInitialised then
    Exit;

  cache := PCacheManager(FCacheManagerPtr);
  x := 0;
  str_ := PChar(AText);

  { Must mirror DrawText exactly: no kerning, advances quantised to the
    logical grid (Round(advance / FScale) * FScale), so that
    width(s) = sum(width(ch)) holds and the edit controls' caret math agrees
    with the rendered glyph positions. }
  while str_^ <> #0 do
  begin
    charId := UTF8CharToUnicode(str_, charLen);
    Inc(str_, charLen);

    glyph := cache^.glyph(charId);
    lIsFallback := False;
    if (glyph = nil) or (glyph^.glyph_index = 0) then
    begin
      glyph := glyph_cache_ptr(TryFallbackGlyph(charId));
      lIsFallback := (glyph <> nil) and (glyph^.glyph_index <> 0);
      if not lIsFallback then
        glyph := nil;
    end;
    if glyph <> nil then
      x := x + Round(glyph^.advance_x / FScale) * FScale;
  end;

  Result := Round(x);
end;


end.
