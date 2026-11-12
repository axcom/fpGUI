{
    fpGUI  -  Free Pascal GUI Toolkit

    Copyright (c) 2026 See the file AUTHORS.txt, included in this
    distribution, for details of the copyright.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      TfpgImageBase -> GL texture cache for TfpgGLCanvas.

      TfpgImageBase stores 32-bit ARGB values ($AARRGGBB); 8/16/24-bit images
      are read through Colors[x,y].  This cache converts them to RGBA8888,
      applies the 1-bit mask (if any) to the alpha channel, and uploads a
      texture.  TfpgImageBase.Generation is used to invalidate stale entries
      when the image is updated in place.

      Phase 3:
        * same image/size + new Generation updates the existing texture with
          glTexSubImage2D instead of deleting/recreating it;
        * UpdateRegion() uploads only a dirty sub-rectangle (terminal grids);
        * the LRU limit is configurable (GLTextureCacheLimit).
}

unit fpg_ohos_gl_texture;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  fpg_base,
  fpg_ohos_egl,
  fpg_ohos_gl;

type
  TfpgOhosGLTextureCache = class
  private
    FEntries: TList;
    FClock: Cardinal;
    function  FindEntry(AImage: TfpgImageBase): TObject;
    procedure EvictOldest;
    procedure BuildRGBARegion(AImage: TfpgImageBase;
      AX, AY, AW, AH: Integer; ADst: PByte);
  public
    constructor Create;
    destructor  Destroy; override;
    function  GetTexture(AImage: TfpgImageBase; out ASwizzleRB: Boolean): GLuint;
    { Upload only (AX,AY,AW,AH) of AImage into its cached texture.  Does
      nothing when the image has not been uploaded yet (the next GetTexture
      performs a full upload). }
    procedure UpdateRegion(AImage: TfpgImageBase; AX, AY, AW, AH: Integer);
    { Drop all entries without touching GL (context loss / teardown). }
    procedure InvalidateAll;
    procedure Clear;
  end;

var
  GLTextureCache: TfpgOhosGLTextureCache = nil;
  { Maximum cached textures (LRU).  May be changed before first use. }
  GLTextureCacheLimit: Integer = 512;

implementation

type
  TImageEntry = class
  public
    Image: TfpgImageBase;
    DataPtr: Pointer;
    Generation: Cardinal;
    W: Integer;
    H: Integer;
    Masked: Boolean;
    Texture: GLuint;
    LastUsed: Cardinal;
  end;

constructor TfpgOhosGLTextureCache.Create;
begin
  inherited Create;
  FEntries := TList.Create;
  FClock := 0;
end;

destructor TfpgOhosGLTextureCache.Destroy;
begin
  Clear;
  FreeAndNil(FEntries);
  inherited Destroy;
end;

function TfpgOhosGLTextureCache.FindEntry(AImage: TfpgImageBase): TObject;
var
  i: Integer;
  e: TImageEntry;
begin
  Result := nil;
  for i := 0 to FEntries.Count - 1 do
  begin
    e := TImageEntry(FEntries[i]);
    if (e.Image = AImage) and (e.DataPtr = AImage.ImageData) and
       (e.W = AImage.Width) and (e.H = AImage.Height) and
       (e.Masked = AImage.Masked) then
    begin
      Inc(FClock);
      e.LastUsed := FClock;
      Exit(e);
    end;
  end;
end;

procedure TfpgOhosGLTextureCache.EvictOldest;
var
  i, oldest: Integer;
  e: TImageEntry;
begin
  if FEntries.Count < GLTextureCacheLimit then
    Exit;
  oldest := 0;
  for i := 1 to FEntries.Count - 1 do
    if TImageEntry(FEntries[i]).LastUsed <
       TImageEntry(FEntries[oldest]).LastUsed then
      oldest := i;
  e := TImageEntry(FEntries[oldest]);
  if e.Texture <> 0 then
    glDeleteTextures(1, @e.Texture);
  FEntries.Delete(oldest);
  e.Free;
end;

procedure TfpgOhosGLTextureCache.BuildRGBARegion(AImage: TfpgImageBase;
  AX, AY, AW, AH: Integer; ADst: PByte);
var
  x, y, mskLineLen, byteIdx, bitIdx: Integer;
  c: TfpgColor;
  r, g, b, a: Byte;
  src: PLongWord;
  v: LongWord;
  mask: PByte;
begin
  mask := PByte(AImage.MaskData);
  mskLineLen := ((AImage.Width + 31) div 32) * 4;

  if AImage.ColorDepth = 32 then
  begin
    src := PLongWord(AImage.ImageData);
    Inc(src, AY * AImage.Width + AX);
    for y := 0 to AH - 1 do
    begin
      for x := 0 to AW - 1 do
      begin
        v := src^;
        Inc(src);
        r := (v shr 16) and $FF;
        g := (v shr 8) and $FF;
        b := v and $FF;
        a := (v shr 24) and $FF;
        if AImage.Masked and (mask <> nil) then
        begin
          byteIdx := (AX + x) div 8;
          bitIdx := 7 - ((AX + x) mod 8);
          if ((mask + (AY + y) * mskLineLen + byteIdx)^ shr bitIdx) and 1 = 0 then
            a := 0
          else
            a := 255;
        end;
        ADst[0] := r;
        ADst[1] := g;
        ADst[2] := b;
        ADst[3] := a;
        Inc(ADst, 4);
      end;
      { src advanced AW pixels; skip the rest of the row. }
      Inc(src, AImage.Width - AW);
    end;
  end
  else
  begin
    { 8/16/24-bit: use the generic accessor, which normalises to ARGB. }
    for y := 0 to AH - 1 do
    begin
      for x := 0 to AW - 1 do
      begin
        c := AImage.Colors[AX + x, AY + y];
        r := fpgGetRed(c);
        g := fpgGetGreen(c);
        b := fpgGetBlue(c);
        a := fpgGetAlpha(c);
        if AImage.Masked and (mask <> nil) then
        begin
          byteIdx := (AX + x) div 8;
          bitIdx := 7 - ((AX + x) mod 8);
          if ((mask + (AY + y) * mskLineLen + byteIdx)^ shr bitIdx) and 1 = 0 then
            a := 0
          else
            a := 255;
        end;
        ADst[0] := r;
        ADst[1] := g;
        ADst[2] := b;
        ADst[3] := a;
        Inc(ADst, 4);
      end;
    end;
  end;
end;

function TfpgOhosGLTextureCache.GetTexture(AImage: TfpgImageBase;
  out ASwizzleRB: Boolean): GLuint;
var
  e: TImageEntry;
  buf: PByte;
  internalFmt: GLint;
begin
  Result := 0;
  ASwizzleRB := False;
  if (AImage = nil) or (AImage.ImageData = nil) or
     (AImage.Width <= 0) or (AImage.Height <= 0) then
    Exit;

  e := TImageEntry(FindEntry(AImage));
  if e <> nil then
  begin
    if e.Generation = AImage.Generation then
      Exit(e.Texture);
    { Same image/size, new content: update in place. }
    buf := GetMem(AImage.Width * AImage.Height * 4);
    if buf = nil then
      Exit(e.Texture);
    try
      BuildRGBARegion(AImage, 0, 0, AImage.Width, AImage.Height, buf);
      glBindTexture(GL_TEXTURE_2D, e.Texture);
      glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, AImage.Width, AImage.Height,
        GL_RGBA, GL_UNSIGNED_BYTE, buf);
    finally
      FreeMem(buf);
    end;
    e.Generation := AImage.Generation;
    Exit(e.Texture);
  end;

  buf := GetMem(AImage.Width * AImage.Height * 4);
  if buf = nil then
    Exit;
  try
    BuildRGBARegion(AImage, 0, 0, AImage.Width, AImage.Height, buf);

    glGenTextures(1, @Result);
    if Result = 0 then
      Exit;
    glBindTexture(GL_TEXTURE_2D, Result);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    if TfpgOhosGLDisplay.Instance.IsES3 then
      internalFmt := GL_RGBA8
    else
      internalFmt := GL_RGBA;
    glTexImage2D(GL_TEXTURE_2D, 0, internalFmt, AImage.Width, AImage.Height, 0,
      GL_RGBA, GL_UNSIGNED_BYTE, buf);
  finally
    FreeMem(buf);
  end;

  if Result = 0 then
    Exit;

  EvictOldest;
  e := TImageEntry.Create;
  e.Image := AImage;
  e.DataPtr := AImage.ImageData;
  e.Generation := AImage.Generation;
  e.W := AImage.Width;
  e.H := AImage.Height;
  e.Masked := AImage.Masked;
  e.Texture := Result;
  Inc(FClock);
  e.LastUsed := FClock;
  FEntries.Add(e);
end;

procedure TfpgOhosGLTextureCache.UpdateRegion(AImage: TfpgImageBase;
  AX, AY, AW, AH: Integer);
var
  e: TImageEntry;
  buf: PByte;
begin
  if (AImage = nil) or (AImage.ImageData = nil) then
    Exit;
  if (AW <= 0) or (AH <= 0) then
    Exit;
  if (AX < 0) or (AY < 0) or
     (AX + AW > AImage.Width) or (AY + AH > AImage.Height) then
    Exit;
  e := TImageEntry(FindEntry(AImage));
  if e = nil then
    Exit;   { not uploaded yet; GetTexture will do a full upload }

  buf := GetMem(AW * AH * 4);
  if buf = nil then
    Exit;
  try
    BuildRGBARegion(AImage, AX, AY, AW, AH, buf);
    glBindTexture(GL_TEXTURE_2D, e.Texture);
    glTexSubImage2D(GL_TEXTURE_2D, 0, AX, AY, AW, AH,
      GL_RGBA, GL_UNSIGNED_BYTE, buf);
  finally
    FreeMem(buf);
  end;
  e.Generation := AImage.Generation;
end;

procedure TfpgOhosGLTextureCache.InvalidateAll;
begin
  Clear;
end;

procedure TfpgOhosGLTextureCache.Clear;
var
  i: Integer;
  e: TImageEntry;
begin
  if FEntries = nil then
    Exit;
  for i := 0 to FEntries.Count - 1 do
  begin
    e := TImageEntry(FEntries[i]);
    { No glDeleteTextures at finalization: the EGL context may not be
      current.  Context teardown reclaims the textures. }
    e.Free;
  end;
  FEntries.Clear;
end;

initialization
  GLTextureCache := TfpgOhosGLTextureCache.Create;

finalization
  FreeAndNil(GLTextureCache);

end.
