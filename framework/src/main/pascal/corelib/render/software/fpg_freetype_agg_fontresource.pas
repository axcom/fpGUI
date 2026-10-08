{
    This unit is part of the fpGUI Toolkit project.

    Copyright (c) 2026 by Graeme Geldenhuys.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      FreeType-based font resource for the hybrid canvas. Provides accurate
      font metrics (GetTextWidth, GetAscent, GetDescent, GetHeight) using the
      same FreeType engine that TGlyphCache uses for rendering, ensuring
      measurement and rendering are always consistent.

      RenderScale (default 1.0) supports HiDPI backends: glyphs are
      rasterised at device size (logical size x RenderScale) while the
      public metrics stay in logical units.
}

unit fpg_freetype_agg_fontresource;

{$mode objfpc}{$H+}

interface

uses
  fpg_base,
  fpg_glyph_cache;

type

  { TfpgFreeTypeFontResource — font resource backed by TGlyphCache/FreeType.
    Each instance owns a TGlyphCache that provides metrics matching the
    rendered output exactly. }

  TfpgFreeTypeFontResource = class(TfpgFontResourceBase)
  private
    FGlyphCache: TGlyphCache;
    FRenderScale: Double;
    FValid: Boolean;
    procedure SetRenderScale(AValue: Double);
  public
    constructor Create(const AFontDesc: string); override;
    destructor Destroy; override;
    function HandleIsValid: boolean; override;
    function GetAscent: integer; override;
    function GetDescent: integer; override;
    function GetHeight: integer; override;
    function GetTextWidth(const txt: string): integer; override;
    procedure DrawTextToBuffer(ABuf: PByte; AStride, ABufW, ABufH,
      AX, AY: Integer; const AText: string; AColor: TfpgColor;
      AClipX1, AClipY1, AClipX2, AClipY2: Integer); override;
    { Device pixels per logical pixel. Glyphs are rasterised at
      logical size x RenderScale; metrics/text width reported here are
      logical. DrawTextToBuffer positions are DEVICE pixels — the canvas
      scales them before calling. }
    property RenderScale: Double read FRenderScale write SetRenderScale;
  end;


implementation


{ TfpgFreeTypeFontResource }

constructor TfpgFreeTypeFontResource.Create(const AFontDesc: string);
begin
  inherited Create(AFontDesc);
  FRenderScale := 1.0;
  FGlyphCache := TGlyphCache.Create;
  { SetFont triggers FreeType font loading and metric capture }
  FGlyphCache.SetFont(Self);
  FValid := (FGlyphCache.Ascent > 0) or (FGlyphCache.Descent > 0);
end;

destructor TfpgFreeTypeFontResource.Destroy;
begin
  FGlyphCache.Free;
  inherited Destroy;
end;

procedure TfpgFreeTypeFontResource.SetRenderScale(AValue: Double);
begin
  if AValue < 1.0 then
    AValue := 1.0;
  if FRenderScale = AValue then
    Exit;
  FRenderScale := AValue;
  FGlyphCache.Scale := AValue;
  FGlyphCache.SetFont(Self);   { reload at new device size }
  FValid := (FGlyphCache.Ascent > 0) or (FGlyphCache.Descent > 0);
end;

function TfpgFreeTypeFontResource.HandleIsValid: boolean;
begin
  Result := FValid;
end;

function TfpgFreeTypeFontResource.GetAscent: integer;
begin
  if FRenderScale = 1.0 then
    Result := FGlyphCache.Ascent
  else
    Result := Round(FGlyphCache.Ascent / FRenderScale);
end;

function TfpgFreeTypeFontResource.GetDescent: integer;
begin
  if FRenderScale = 1.0 then
    Result := FGlyphCache.Descent
  else
    Result := Round(FGlyphCache.Descent / FRenderScale);
end;

function TfpgFreeTypeFontResource.GetHeight: integer;
begin
  if FRenderScale = 1.0 then
    Result := FGlyphCache.LineHeight
  else
    Result := Round(FGlyphCache.LineHeight / FRenderScale);
end;

function TfpgFreeTypeFontResource.GetTextWidth(const txt: string): integer;
begin
  if FRenderScale = 1.0 then
    Result := FGlyphCache.TextWidth(txt)
  else
    Result := Round(FGlyphCache.TextWidth(txt) / FRenderScale);
end;

procedure TfpgFreeTypeFontResource.DrawTextToBuffer(ABuf: PByte;
  AStride, ABufW, ABufH, AX, AY: Integer; const AText: string;
  AColor: TfpgColor; AClipX1, AClipY1, AClipX2, AClipY2: Integer);
begin
  FGlyphCache.DrawText(ABuf, AStride, ABufW, ABufH, AX, AY, AText, AColor,
    AClipX1, AClipY1, AClipX2, AClipY2);
end;


end.
