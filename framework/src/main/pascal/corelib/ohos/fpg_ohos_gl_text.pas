{
    fpGUI  -  Free Pascal GUI Toolkit

    Copyright (c) 2026 See the file AUTHORS.txt, included in this
    distribution, for details of the copyright.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      Glyph-atlas text renderer for TfpgGLCanvas (Phase 3).

      Each UTF-8 codepoint is rasterised once with
      TfpgFontResourceBase.DrawTextToBuffer into a shared RGBA atlas
      (white RGB + coverage in alpha).  A text run becomes one quad per
      glyph, all sharing the atlas texture, so the batching layer emits a
      single draw call for the whole run (and across runs).

      The per-glyph advance comes from AFont.GetTextWidth(ch); the bitmap
      is rendered at physical size (gHiDPIScaleFactor) and drawn back at
      logical size, matching the canvas coordinate system.
}

unit fpg_ohos_gl_text;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  fpg_base,
  fpg_ohos_egl,
  fpg_ohos_gl,
  fpg_ohos_gl_draw;

type
  TfpgOhosGLTextCache = class
  private
    FAtlas: GLuint;
    FAtlasW: Integer;
    FAtlasH: Integer;
    FCurX: Integer;
    FCurY: Integer;
    FRowH: Integer;
    FGlyphs: TList;
    FClock: Cardinal;
    function  FindGlyph(const AFontDesc, ACh: string): TObject;
    function  AddGlyph(AFont: TfpgFontResourceBase; const ACh: string;
      AScale: Double): TObject;
    procedure CreateAtlas;
    procedure ResetAtlas;
    function  AllocRegion(AW, AH: Integer; out AX, AY: Integer): Boolean;
  public
    constructor Create;
    destructor  Destroy; override;
    { Draw AText at window coordinates (X, Y); returns the total advance. }
    function  DrawText(ADraw: TfpgOhosGLDraw; AFont: TfpgFontResourceBase;
      const AText: string; X, Y: Integer; AColor: TfpgColor;
      AScale: Double): Integer;
    { Drop all glyphs without touching GL (context loss / teardown). }
    procedure InvalidateAll;
    procedure Clear;
  end;

var
  GLTextCache: TfpgOhosGLTextCache = nil;
  { Atlas edge length in physical pixels.  May be changed before first use. }
  GLTextAtlasSize: Integer = 1024;

implementation

type
  TGlyphEntry = class
  public
    FontDesc: string;
    Ch: string;
    U, V, W, H: Integer;   { atlas region, physical pixels }
    Advance: Integer;      { logical advance }
    Empty: Boolean;
    LastUsed: Cardinal;
  end;

function UTF8CharLen(const S: string; AIndex: Integer): Integer;
var
  b: Byte;
begin
  b := Ord(S[AIndex]);
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
  if AIndex + Result - 1 > Length(S) then
    Result := Length(S) - AIndex + 1;
end;

constructor TfpgOhosGLTextCache.Create;
begin
  inherited Create;
  FGlyphs := TList.Create;
  FClock := 0;
  FAtlas := 0;
  FAtlasW := GLTextAtlasSize;
  FAtlasH := GLTextAtlasSize;
  FCurX := 0;
  FCurY := 0;
  FRowH := 0;
end;

destructor TfpgOhosGLTextCache.Destroy;
begin
  Clear;
  FreeAndNil(FGlyphs);
  inherited Destroy;
end;

procedure TfpgOhosGLTextCache.CreateAtlas;
var
  internalFmt: GLint;
begin
  if FAtlas <> 0 then
    Exit;
  if FAtlasW < 64 then
    FAtlasW := 64;
  if FAtlasH < 64 then
    FAtlasH := 64;
  glGenTextures(1, @FAtlas);
  if FAtlas = 0 then
    Exit;
  glBindTexture(GL_TEXTURE_2D, FAtlas);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  if TfpgOhosGLDisplay.Instance.IsES3 then
    internalFmt := GL_RGBA8
  else
    internalFmt := GL_RGBA;
  glTexImage2D(GL_TEXTURE_2D, 0, internalFmt, FAtlasW, FAtlasH, 0,
    GL_RGBA, GL_UNSIGNED_BYTE, nil);
  FCurX := 0;
  FCurY := 0;
  FRowH := 0;
end;

procedure TfpgOhosGLTextCache.ResetAtlas;
var
  i: Integer;
begin
  for i := 0 to FGlyphs.Count - 1 do
    TGlyphEntry(FGlyphs[i]).Free;
  FGlyphs.Clear;
  FCurX := 0;
  FCurY := 0;
  FRowH := 0;
end;

function TfpgOhosGLTextCache.AllocRegion(AW, AH: Integer;
  out AX, AY: Integer): Boolean;
begin
  Result := False;
  if (AW <= 0) or (AH <= 0) or (AW > FAtlasW) or (AH > FAtlasH) then
    Exit;
  if FCurX + AW > FAtlasW then
  begin
    FCurX := 0;
    Inc(FCurY, FRowH);
    FRowH := 0;
  end;
  if FCurY + AH > FAtlasH then
    Exit;
  AX := FCurX;
  AY := FCurY;
  Inc(FCurX, AW + 1);
  if AH > FRowH then
    FRowH := AH;
  Result := True;
end;

function TfpgOhosGLTextCache.FindGlyph(const AFontDesc, ACh: string): TObject;
var
  i: Integer;
  g: TGlyphEntry;
begin
  Result := nil;
  for i := 0 to FGlyphs.Count - 1 do
  begin
    g := TGlyphEntry(FGlyphs[i]);
    if (g.FontDesc = AFontDesc) and (g.Ch = ACh) then
    begin
      Inc(FClock);
      g.LastUsed := FClock;
      Exit(g);
    end;
  end;
end;

function TfpgOhosGLTextCache.AddGlyph(AFont: TfpgFontResourceBase;
  const ACh: string; AScale: Double): TObject;
var
  adv, fontH, gw, gh, stride, i, a, maxA: Integer;
  buf: PByte;
  p: PByte;
  ax, ay: Integer;
  g: TGlyphEntry;
begin
  Result := nil;
  adv := AFont.GetTextWidth(ACh);
  fontH := AFont.GetHeight;
  if fontH <= 0 then
    Exit;
  if AScale <= 0 then
    AScale := 1.0;

  { +2 physical pixels of transparent padding on each axis. }
  gw := Round(adv * AScale) + 2;
  if gw < 1 then
    gw := 1;
  gh := Round(fontH * AScale) + 2;
  if gh < 1 then
    gh := 1;
  stride := gw * 4;

  buf := GetMem(stride * gh);
  if buf = nil then
    Exit;
  try
    FillChar(buf^, stride * gh, 0);
    AFont.DrawTextToBuffer(buf, stride, gw, gh, 0, AFont.GetAscent, ACh,
      $FFFFFFFF, 0, 0, adv, fontH);

    { DrawTextToBuffer writes RGB coverage but not alpha.  Convert to a
      white glyph with coverage in alpha (same convention as the shader). }
    maxA := 0;
    for i := 0 to gw * gh - 1 do
    begin
      p := buf + i * 4;
      a := p[0];
      if p[1] > a then a := p[1];
      if p[2] > a then a := p[2];
      p[3] := a;
      if a > 0 then
      begin
        p[0] := 255;
        p[1] := 255;
        p[2] := 255;
      end;
      if a > maxA then
        maxA := a;
    end;

    g := TGlyphEntry.Create;
    g.FontDesc := AFont.FontDesc;
    g.Ch := ACh;
    g.Advance := adv;
    g.Empty := maxA = 0;
    if not g.Empty then
    begin
      if not AllocRegion(gw, gh, ax, ay) then
      begin
        { Atlas full: discard all glyphs and start over. }
        ResetAtlas;
        if not AllocRegion(gw, gh, ax, ay) then
        begin
          g.Free;
          Exit;
        end;
      end;
      glBindTexture(GL_TEXTURE_2D, FAtlas);
      glTexSubImage2D(GL_TEXTURE_2D, 0, ax, ay, gw, gh,
        GL_RGBA, GL_UNSIGNED_BYTE, buf);
      g.U := ax;
      g.V := ay;
      g.W := gw;
      g.H := gh;
    end;
  finally
    FreeMem(buf);
  end;

  Inc(FClock);
  g.LastUsed := FClock;
  FGlyphs.Add(g);
  Result := g;
end;

function TfpgOhosGLTextCache.DrawText(ADraw: TfpgOhosGLDraw;
  AFont: TfpgFontResourceBase; const AText: string; X, Y: Integer;
  AColor: TfpgColor; AScale: Double): Integer;
var
  i, len, clen, penX: Integer;
  ch: string;
  g: TGlyphEntry;
  r: TfpgRect;
  uv: TGLUV;
begin
  Result := 0;
  if (ADraw = nil) or (AFont = nil) or (AText = '') then
    Exit;
  if AScale <= 0 then
    AScale := 1.0;
  CreateAtlas;
  if FAtlas = 0 then
    Exit;

  penX := X;
  i := 1;
  len := Length(AText);
  while i <= len do
  begin
    clen := UTF8CharLen(AText, i);
    ch := Copy(AText, i, clen);
    g := TGlyphEntry(FindGlyph(AFont.FontDesc, ch));
    if g = nil then
      g := TGlyphEntry(AddGlyph(AFont, ch, AScale));
    if g <> nil then
    begin
      if not g.Empty then
      begin
        r.SetRect(penX, Y, Round(g.W / AScale), Round(g.H / AScale));
        uv.U1 := g.U / FAtlasW;
        uv.V1 := g.V / FAtlasH;
        uv.U2 := (g.U + g.W) / FAtlasW;
        uv.V2 := (g.V + g.H) / FAtlasH;
        ADraw.DrawTexturedQuad(r, FAtlas, AColor, False, True, True, uv);
      end;
      Inc(penX, g.Advance);
    end;
    Inc(i, clen);
  end;
  Result := penX - X;
end;

procedure TfpgOhosGLTextCache.InvalidateAll;
begin
  ResetAtlas;
  { The atlas texture died with the GL context; recreate it on next use. }
  FAtlas := 0;
end;

procedure TfpgOhosGLTextCache.Clear;
begin
  if FGlyphs = nil then
    Exit;
  ResetAtlas;
  { No glDeleteTextures: the context may already be gone. }
  FAtlas := 0;
end;

initialization
  GLTextCache := TfpgOhosGLTextCache.Create;

finalization
  FreeAndNil(GLTextCache);

end.
