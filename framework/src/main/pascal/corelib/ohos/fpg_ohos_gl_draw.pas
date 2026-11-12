{
    fpGUI  -  Free Pascal GUI Toolkit

    Copyright (c) 2026 See the file AUTHORS.txt, included in this
    distribution, for details of the copyright.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      Shared immediate-mode GLES draw helper for TfpgGLCanvas (Phase 2).

      All primitives are converted to NDC on the CPU and drawn into the
      window's retained FBO.  The canvas keeps logical coordinates and
      passes gHiDPIScaleFactor via BeginFrame; this unit applies the scale
      and the FBO's physical size.

      Vertices are accumulated in a CPU batch and uploaded once per state
      change (program/texture/scissor) or when the batch is full (Phase 3).
}

unit fpg_ohos_gl_draw;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  CTypes,
  fpg_base,
  fpg_ohos_egl,
  fpg_ohos_gl,
  fpg_ohos_gl_shaders;

type
  TGLColor = record
    R, G, B, A: Single;
  end;

  TGLUV = record
    U1, V1, U2, V2: Single;
  end;

  TGLBatchKind = (bkNone, bkSolid, bkTextured);

  TfpgOhosGLDraw = class
  private
    FSolidProgram: GLuint;
    FTexturedProgram: GLuint;
    FVBO: GLuint;
    FTexTexLoc: GLint;
    FTexSwizzleLoc: GLint;
    FTexPremultiplyLoc: GLint;
    FWindow: TfpgOhosGLWindow;
    FScale: Double;
    FCopyTex: GLuint;
    FCopyW: Integer;
    FCopyH: Integer;
    { Phase 3: accumulated vertices, flushed on state change / capacity. }
    FBatch: array of TGLDrawVertex;
    FBatchCount: Integer;
    FBatchKind: TGLBatchKind;
    FBatchTex: GLuint;
    FBatchSwizzle: Boolean;
    FBatchSmooth: Boolean;
    FBatchPremultiply: Boolean;
    function  CompileShader(AShaderType: GLuint; const ASource: string): GLuint;
    function  LinkProgram(AVert, AFrag: GLuint;
      AHasUV: Boolean): GLuint;
    procedure EnsureCreated;
    function  ToColor(C: TfpgColor): TGLColor;
    function  NdcX(X: Single): Single;
    function  NdcY(Y: Single): Single;
    procedure BindSolid;
    procedure BindTextured(ATexture: GLuint;
      ASwizzleRB, ASmooth, APremultiply: Boolean);
    procedure FlushBatch;
    procedure UseSolid;
    procedure UseTextured(ATexture: GLuint;
      ASwizzleRB, ASmooth, APremultiply: Boolean);
    procedure AppendVertex(const V: TGLDrawVertex);
    procedure AppendQuad(x1, y1, x2, y2: Single; const AUV: TGLUV;
      const C1, C2: TGLColor; AVerticalGradient: Boolean);
    procedure AppendTri(const V0, V1, V2: TGLDrawVertex);
    procedure AppendFan(const Points: array of TPoint; const C: TGLColor);
  public
    constructor Create;
    destructor  Destroy; override;
    procedure BeginFrame(AWindow: TfpgOhosGLWindow; AScale: Double);
    procedure SetScissor(const R: TfpgRect; AValid: Boolean);
    procedure ClearScissor;
    procedure DrawSolidQuad(const R: TfpgRect; AColor: TfpgColor);
    procedure DrawGradientQuad(const R: TfpgRect; AStart, AStop: TfpgColor;
      AVertical: Boolean);
    procedure DrawSolidTriangle(X1, Y1, X2, Y2, X3, Y3: Single;
      AColor: TfpgColor);
    procedure DrawTexturedQuad(const R: TfpgRect; ATexture: GLuint;
      AColor: TfpgColor; ASwizzleRB, ASmooth, APremultiply: Boolean;
      const AUV: TGLUV);
    procedure DrawLine(X1, Y1, X2, Y2: Single; AWidth: Integer;
      AColor: TfpgColor);
    procedure DrawPolygon(const Points: array of TPoint; AColor: TfpgColor);
    function  ReadPixel(X, Y: Integer): TfpgColor;
    procedure WritePixel(X, Y: Integer; AColor: TfpgColor);
    procedure CopyRect(ASrcX, ASrcY, ADstX, ADstY, AW, AH: Integer);
    { Phase 3: copy between two windows' FBOs via the shared EGL context. }
    procedure CopyRectFromWindow(ASrcWindow: TfpgOhosGLWindow;
      ASrcX, ASrcY, ADstX, ADstY, AW, AH: Integer);
    procedure Flush;
    property  Window: TfpgOhosGLWindow read FWindow;
  end;

var
  GLDraw: TfpgOhosGLDraw = nil;

implementation

constructor TfpgOhosGLDraw.Create;
begin
  inherited Create;
  FSolidProgram := 0;
  FTexturedProgram := 0;
  FVBO := 0;
  FTexTexLoc := -1;
  FTexSwizzleLoc := -1;
  FTexPremultiplyLoc := -1;
  FWindow := nil;
  FScale := 1.0;
  FCopyTex := 0;
  FCopyW := 0;
  FCopyH := 0;
  FBatchCount := 0;
  FBatchKind := bkNone;
  FBatchTex := 0;
  FBatchSwizzle := False;
  FBatchSmooth := False;
  FBatchPremultiply := False;
  SetLength(FBatch, 4096);
end;

destructor TfpgOhosGLDraw.Destroy;
begin
  { GL objects are released by the context teardown. }
  inherited Destroy;
end;

function TfpgOhosGLDraw.CompileShader(AShaderType: GLuint;
  const ASource: string): GLuint;
var
  src: PChar;
  status: GLint;
  log: array[0..1023] of Char;
  len: GLint;
begin
  Result := glCreateShader(AShaderType);
  if Result = 0 then
    Exit;
  src := PChar(ASource);
  glShaderSource(Result, 1, @src, nil);
  glCompileShader(Result);
  status := 0;
  glGetShaderiv(Result, GL_COMPILE_STATUS, @status);
  if status = 0 then
  begin
    FillChar(log, SizeOf(log), 0);
    len := 0;
    glGetShaderInfoLog(Result, SizeOf(log), @len, @log[0]);
    GL_Log(GL_LOG_ERROR, 'GL canvas shader compile failed: ' + StrPas(@log[0]));
    glDeleteShader(Result);
    Result := 0;
  end;
end;

function TfpgOhosGLDraw.LinkProgram(AVert, AFrag: GLuint;
  AHasUV: Boolean): GLuint;
var
  status: GLint;
  log: array[0..1023] of Char;
  len: GLint;
begin
  Result := glCreateProgram;
  if Result = 0 then
    Exit;
  glAttachShader(Result, AVert);
  glAttachShader(Result, AFrag);
  glBindAttribLocation(Result, 0, 'aPos');
  if AHasUV then
  begin
    glBindAttribLocation(Result, 1, 'aUV');
    glBindAttribLocation(Result, 2, 'aColor');
  end
  else
    glBindAttribLocation(Result, 1, 'aColor');
  glLinkProgram(Result);
  status := 0;
  glGetProgramiv(Result, GL_LINK_STATUS, @status);
  if status = 0 then
  begin
    FillChar(log, SizeOf(log), 0);
    len := 0;
    glGetProgramInfoLog(Result, SizeOf(log), @len, @log[0]);
    GL_Log(GL_LOG_ERROR, 'GL canvas program link failed: ' + StrPas(@log[0]));
    glDeleteProgram(Result);
    Result := 0;
  end;
end;

procedure TfpgOhosGLDraw.EnsureCreated;
var
  vert, frag: GLuint;
begin
  if FSolidProgram <> 0 then
    Exit;

  if TfpgOhosGLDisplay.Instance.IsES3 then
  begin
    vert := CompileShader(GL_VERTEX_SHADER, SOLID_VERT_SRC_ES3);
    if vert = 0 then Exit;
    frag := CompileShader(GL_FRAGMENT_SHADER, SOLID_FRAG_SRC_ES3);
  end
  else
  begin
    vert := CompileShader(GL_VERTEX_SHADER, SOLID_VERT_SRC_ES2);
    if vert = 0 then Exit;
    frag := CompileShader(GL_FRAGMENT_SHADER, SOLID_FRAG_SRC_ES2);
  end;
  if frag = 0 then
  begin
    glDeleteShader(vert);
    Exit;
  end;
  FSolidProgram := LinkProgram(vert, frag, False);
  glDeleteShader(vert);
  glDeleteShader(frag);
  if FSolidProgram = 0 then
    Exit;

  if TfpgOhosGLDisplay.Instance.IsES3 then
  begin
    vert := CompileShader(GL_VERTEX_SHADER, TEX_VERT_SRC_ES3);
    if vert = 0 then Exit;
    frag := CompileShader(GL_FRAGMENT_SHADER, TEX_FRAG_SRC_ES3);
  end
  else
  begin
    vert := CompileShader(GL_VERTEX_SHADER, TEX_VERT_SRC_ES2);
    if vert = 0 then Exit;
    frag := CompileShader(GL_FRAGMENT_SHADER, TEX_FRAG_SRC_ES2);
  end;
  if frag = 0 then
  begin
    glDeleteShader(vert);
    Exit;
  end;
  FTexturedProgram := LinkProgram(vert, frag, True);
  glDeleteShader(vert);
  glDeleteShader(frag);
  if FTexturedProgram = 0 then
    Exit;

  FTexTexLoc := glGetUniformLocation(FTexturedProgram, 'uTex');
  FTexSwizzleLoc := glGetUniformLocation(FTexturedProgram, 'uSwizzleRB');
  FTexPremultiplyLoc := glGetUniformLocation(FTexturedProgram, 'uPremultiply');

  glGenBuffers(1, @FVBO);
end;

function TfpgOhosGLDraw.ToColor(C: TfpgColor): TGLColor;
var
  a: Single;
begin
  a := fpgGetAlpha(C) / 255;
  if a = 0 then
    a := 1;
  Result.R := fpgGetRed(C) / 255 * a;
  Result.G := fpgGetGreen(C) / 255 * a;
  Result.B := fpgGetBlue(C) / 255 * a;
  Result.A := a;
end;
function TfpgOhosGLDraw.NdcX(X: Single): Single;
begin
  Result := (X * FScale / FWindow.FBOWidth) * 2 - 1;
end;

function TfpgOhosGLDraw.NdcY(Y: Single): Single;
begin
  Result := 1 - (Y * FScale / FWindow.FBOHeight) * 2;
end;

procedure TfpgOhosGLDraw.BeginFrame(AWindow: TfpgOhosGLWindow; AScale: Double);
begin
  { Normally empty: DoPutBufferToScreen flushes before presenting. }
  FlushBatch;
  FWindow := AWindow;
  FScale := AScale;
  if FScale <= 0 then
    FScale := 1.0;
  if FWindow = nil then
    Exit;
  if not FWindow.MakeCurrent then
    Exit;
  FWindow.BindFBO;
  EnsureCreated;
  glDisable(GL_SCISSOR_TEST);
  glEnable(GL_BLEND);
  glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
  glViewport(0, 0, FWindow.FBOWidth, FWindow.FBOHeight);
end;

procedure TfpgOhosGLDraw.SetScissor(const R: TfpgRect; AValid: Boolean);
var
  x, y, w, h: Integer;
begin
  FlushBatch;
  if (not AValid) or (FWindow = nil) then
  begin
    glDisable(GL_SCISSOR_TEST);
    Exit;
  end;
  x := Round(R.Left * FScale);
  y := Round(FWindow.FBOHeight - (R.Top + R.Height) * FScale);
  w := Round(R.Width * FScale);
  h := Round(R.Height * FScale);
  if x < 0 then begin Dec(w, -x); x := 0; end;
  if y < 0 then begin Dec(h, -y); y := 0; end;
  if x + w > FWindow.FBOWidth then w := FWindow.FBOWidth - x;
  if y + h > FWindow.FBOHeight then h := FWindow.FBOHeight - y;
  if (w <= 0) or (h <= 0) then
  begin
    glDisable(GL_SCISSOR_TEST);
    Exit;
  end;
  glEnable(GL_SCISSOR_TEST);
  glScissor(x, y, w, h);
end;

procedure TfpgOhosGLDraw.ClearScissor;
begin
  FlushBatch;
  glDisable(GL_SCISSOR_TEST);
end;

procedure TfpgOhosGLDraw.BindSolid;
begin
  glUseProgram(FSolidProgram);
  glBindBuffer(GL_ARRAY_BUFFER, FVBO);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, SizeOf(TGLDrawVertex),
    Pointer(PtrUInt(0)));
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, SizeOf(TGLDrawVertex),
    Pointer(PtrUInt(16)));
end;

procedure TfpgOhosGLDraw.BindTextured(ATexture: GLuint;
  ASwizzleRB, ASmooth, APremultiply: Boolean);
begin
  glUseProgram(FTexturedProgram);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, ATexture);
  if ASmooth then
  begin
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  end
  else
  begin
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  end;
  glUniform1i(FTexTexLoc, 0);
  if ASwizzleRB then
    glUniform1f(FTexSwizzleLoc, 1.0)
  else
    glUniform1f(FTexSwizzleLoc, 0.0);
  if APremultiply then
    glUniform1f(FTexPremultiplyLoc, 1.0)
  else
    glUniform1f(FTexPremultiplyLoc, 0.0);
  glBindBuffer(GL_ARRAY_BUFFER, FVBO);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, SizeOf(TGLDrawVertex),
    Pointer(PtrUInt(0)));
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, SizeOf(TGLDrawVertex),
    Pointer(PtrUInt(8)));
  glEnableVertexAttribArray(2);
  glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, SizeOf(TGLDrawVertex),
    Pointer(PtrUInt(16)));
end;

procedure SetColor(var V: TGLDrawVertex; const C: TGLColor); inline;
begin
  V.R := C.R;
  V.G := C.G;
  V.B := C.B;
  V.A := C.A;
end;

procedure TfpgOhosGLDraw.FlushBatch;
begin
  if FBatchCount <= 0 then
    Exit;
  case FBatchKind of
    bkSolid:
      BindSolid;
    bkTextured:
      BindTextured(FBatchTex, FBatchSwizzle, FBatchSmooth, FBatchPremultiply);
  else
    FBatchCount := 0;
    Exit;
  end;
  glBufferData(GL_ARRAY_BUFFER,
    GLsizeiptr(FBatchCount * SizeOf(TGLDrawVertex)),
    @FBatch[0], GL_STREAM_DRAW);
  glDrawArrays(GL_TRIANGLES, 0, FBatchCount);
  FBatchCount := 0;
end;

procedure TfpgOhosGLDraw.UseSolid;
begin
  if FBatchKind <> bkSolid then
  begin
    FlushBatch;
    FBatchKind := bkSolid;
    FBatchTex := 0;
  end;
end;

procedure TfpgOhosGLDraw.UseTextured(ATexture: GLuint;
  ASwizzleRB, ASmooth, APremultiply: Boolean);
begin
  if (FBatchKind <> bkTextured) or (FBatchTex <> ATexture) or
     (FBatchSwizzle <> ASwizzleRB) or (FBatchSmooth <> ASmooth) or
     (FBatchPremultiply <> APremultiply) then
  begin
    FlushBatch;
    FBatchKind := bkTextured;
    FBatchTex := ATexture;
    FBatchSwizzle := ASwizzleRB;
    FBatchSmooth := ASmooth;
    FBatchPremultiply := APremultiply;
  end;
end;

procedure TfpgOhosGLDraw.AppendVertex(const V: TGLDrawVertex);
begin
  if FBatchCount >= Length(FBatch) then
    FlushBatch;
  if FBatchCount >= Length(FBatch) then
    Exit;
  FBatch[FBatchCount] := V;
  Inc(FBatchCount);
end;

procedure TfpgOhosGLDraw.AppendQuad(x1, y1, x2, y2: Single;
  const AUV: TGLUV; const C1, C2: TGLColor; AVerticalGradient: Boolean);
var
  v: array[0..5] of TGLDrawVertex;
begin
  v[0].X := NdcX(x1); v[0].Y := NdcY(y1);
  v[1].X := NdcX(x2); v[1].Y := NdcY(y1);
  v[2].X := NdcX(x2); v[2].Y := NdcY(y2);
  v[3].X := v[0].X;   v[3].Y := v[0].Y;
  v[4].X := v[2].X;   v[4].Y := v[2].Y;
  v[5].X := NdcX(x1); v[5].Y := NdcY(y2);

  v[0].U := AUV.U1; v[0].V := AUV.V1;
  v[1].U := AUV.U2; v[1].V := AUV.V1;
  v[2].U := AUV.U2; v[2].V := AUV.V2;
  v[3].U := AUV.U1; v[3].V := AUV.V1;
  v[4].U := AUV.U2; v[4].V := AUV.V2;
  v[5].U := AUV.U1; v[5].V := AUV.V2;

  if AVerticalGradient then
  begin
    SetColor(v[0], C1); SetColor(v[1], C1); SetColor(v[3], C1);
    SetColor(v[2], C2); SetColor(v[4], C2); SetColor(v[5], C2);
  end
  else
  begin
    SetColor(v[0], C1); SetColor(v[3], C1); SetColor(v[5], C1);
    SetColor(v[1], C2); SetColor(v[2], C2); SetColor(v[4], C2);
  end;

  AppendVertex(v[0]); AppendVertex(v[1]); AppendVertex(v[2]);
  AppendVertex(v[3]); AppendVertex(v[4]); AppendVertex(v[5]);
end;

procedure TfpgOhosGLDraw.AppendTri(const V0, V1, V2: TGLDrawVertex);
begin
  AppendVertex(V0); AppendVertex(V1); AppendVertex(V2);
end;

procedure TfpgOhosGLDraw.AppendFan(const Points: array of TPoint;
  const C: TGLColor);
var
  i, n: Integer;
  v0, v1, v2: TGLDrawVertex;
begin
  n := Length(Points);
  if n < 3 then
    Exit;
  v0.X := NdcX(Points[0].X); v0.Y := NdcY(Points[0].Y);
  SetColor(v0, C);
  for i := 1 to n - 2 do
  begin
    v1.X := NdcX(Points[i].X); v1.Y := NdcY(Points[i].Y);
    v2.X := NdcX(Points[i + 1].X); v2.Y := NdcY(Points[i + 1].Y);
    SetColor(v1, C);
    SetColor(v2, C);
    AppendTri(v0, v1, v2);
  end;
end;

procedure TfpgOhosGLDraw.DrawSolidQuad(const R: TfpgRect; AColor: TfpgColor);
var
  c: TGLColor;
  uv: TGLUV;
begin
  if (R.Width <= 0) or (R.Height <= 0) or (FWindow = nil) then
    Exit;
  c := ToColor(AColor);
  uv.U1 := 0; uv.V1 := 0; uv.U2 := 0; uv.V2 := 0;
  UseSolid;
  AppendQuad(R.Left, R.Top, R.Left + R.Width, R.Top + R.Height,
    uv, c, c, False);
end;

procedure TfpgOhosGLDraw.DrawGradientQuad(const R: TfpgRect;
  AStart, AStop: TfpgColor; AVertical: Boolean);
var
  c1, c2: TGLColor;
  uv: TGLUV;
begin
  if (R.Width <= 0) or (R.Height <= 0) or (FWindow = nil) then
    Exit;
  c1 := ToColor(AStart);
  c2 := ToColor(AStop);
  uv.U1 := 0; uv.V1 := 0; uv.U2 := 0; uv.V2 := 0;
  UseSolid;
  AppendQuad(R.Left, R.Top, R.Left + R.Width, R.Top + R.Height,
    uv, c1, c2, AVertical);
end;

procedure TfpgOhosGLDraw.DrawSolidTriangle(X1, Y1, X2, Y2, X3, Y3: Single;
  AColor: TfpgColor);
var
  c: TGLColor;
  v: array[0..2] of TGLDrawVertex;
begin
  if FWindow = nil then
    Exit;
  c := ToColor(AColor);
  v[0].X := NdcX(X1); v[0].Y := NdcY(Y1);
  v[1].X := NdcX(X2); v[1].Y := NdcY(Y2);
  v[2].X := NdcX(X3); v[2].Y := NdcY(Y3);
  SetColor(v[0], c);
  SetColor(v[1], c);
  SetColor(v[2], c);
  UseSolid;
  AppendTri(v[0], v[1], v[2]);
end;

procedure TfpgOhosGLDraw.DrawTexturedQuad(const R: TfpgRect;
  ATexture: GLuint; AColor: TfpgColor; ASwizzleRB, ASmooth, APremultiply: Boolean;
  const AUV: TGLUV);
var
  c: TGLColor;
begin
  if (R.Width <= 0) or (R.Height <= 0) or (FWindow = nil) or (ATexture = 0) then
    Exit;
  c := ToColor(AColor);
  UseTextured(ATexture, ASwizzleRB, ASmooth, APremultiply);
  AppendQuad(R.Left, R.Top, R.Left + R.Width, R.Top + R.Height,
    AUV, c, c, False);
end;

procedure TfpgOhosGLDraw.DrawLine(X1, Y1, X2, Y2: Single;
  AWidth: Integer; AColor: TfpgColor);
var
  dx, dy, len, nx, ny, hw: Single;
  c: TGLColor;
  v: array[0..5] of TGLDrawVertex;
begin
  if FWindow = nil then
    Exit;
  dx := X2 - X1;
  dy := Y2 - Y1;
  len := Sqrt(dx * dx + dy * dy);
  if len < 0.01 then
    Exit;
  hw := AWidth / 2;
  if hw < 0.5 then
    hw := 0.5;
  nx := -dy / len * hw;
  ny := dx / len * hw;

  c := ToColor(AColor);
  v[0].X := NdcX(X1 + nx); v[0].Y := NdcY(Y1 + ny);
  v[1].X := NdcX(X2 + nx); v[1].Y := NdcY(Y2 + ny);
  v[2].X := NdcX(X2 - nx); v[2].Y := NdcY(Y2 - ny);
  v[3].X := v[0].X;        v[3].Y := v[0].Y;
  v[4].X := v[2].X;        v[4].Y := v[2].Y;
  v[5].X := NdcX(X1 - nx); v[5].Y := NdcY(Y1 - ny);

  SetColor(v[0], c);
  SetColor(v[1], c);
  SetColor(v[2], c);
  SetColor(v[3], c);
  SetColor(v[4], c);
  SetColor(v[5], c);

  UseSolid;
  AppendVertex(v[0]); AppendVertex(v[1]); AppendVertex(v[2]);
  AppendVertex(v[3]); AppendVertex(v[4]); AppendVertex(v[5]);
end;

procedure TfpgOhosGLDraw.DrawPolygon(const Points: array of TPoint;
  AColor: TfpgColor);
var
  i, n, minX, minY, maxX, maxY: Integer;
  c: TGLColor;
  r: TfpgRect;
  uv: TGLUV;
begin
  n := Length(Points);
  if (n < 3) or (FWindow = nil) then
    Exit;

  minX := Points[0].X; maxX := minX;
  minY := Points[0].Y; maxY := minY;
  for i := 1 to n - 1 do
  begin
    if Points[i].X < minX then minX := Points[i].X;
    if Points[i].X > maxX then maxX := Points[i].X;
    if Points[i].Y < minY then minY := Points[i].Y;
    if Points[i].Y > maxY then maxY := Points[i].Y;
  end;
  r.SetRect(minX, minY, maxX - minX + 1, maxY - minY + 1);
  c := ToColor(AColor);
  uv.U1 := 0; uv.V1 := 0; uv.U2 := 0; uv.V2 := 0;

  { Even-odd fill via the stencil buffer.  Flush between the stencil pass
    (fan) and the fill pass (quad) because the GL state changes in between. }
  FlushBatch;
  glEnable(GL_STENCIL_TEST);
  glStencilMask($FF);
  glClearStencil(0);
  glClear(GL_STENCIL_BUFFER_BIT);
  glStencilFunc(GL_ALWAYS, 0, $FF);
  glStencilOp(GL_KEEP, GL_KEEP, GL_INVERT);
  glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
  UseSolid;
  AppendFan(Points, c);
  FlushBatch;
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
  glStencilFunc(GL_NOTEQUAL, 0, $FF);
  glStencilOp(GL_KEEP, GL_KEEP, GL_ZERO);
  UseSolid;
  AppendQuad(r.Left, r.Top, r.Left + r.Width, r.Top + r.Height,
    uv, c, c, False);
  FlushBatch;
  glDisable(GL_STENCIL_TEST);
end;

function TfpgOhosGLDraw.ReadPixel(X, Y: Integer): TfpgColor;
var
  px: array[0..3] of Byte;
  fx, fy: Integer;
begin
  Result := 0;
  if FWindow = nil then
    Exit;
  FlushBatch;
  { X/Y are logical canvas coordinates; the FBO is in physical pixels.
    ReadPixel must apply the same FScale as DrawSolidQuad/NdcX/NdcY,
    otherwise XOR readbacks sample a different pixel than the one drawn. }
  fx := Round(X * FScale);
  fy := Round(Y * FScale);
  if (fx < 0) or (fy < 0) or
     (fx >= FWindow.FBOWidth) or (fy >= FWindow.FBOHeight) then
    Exit;
  FWindow.BindFBO;
  glReadPixels(fx, FWindow.FBOHeight - fy - 1, 1, 1,
    GL_RGBA, GL_UNSIGNED_BYTE, @px[0]);
  Result := (TfpgColor(px[0]) shl 16) or (TfpgColor(px[1]) shl 8) or
    TfpgColor(px[2]) or $FF000000;
end;

procedure TfpgOhosGLDraw.WritePixel(X, Y: Integer; AColor: TfpgColor);
var
  r: TfpgRect;
begin
  r.SetRect(X, Y, 1, 1);
  DrawSolidQuad(r, AColor);
end;

procedure TfpgOhosGLDraw.CopyRect(ASrcX, ASrcY, ADstX, ADstY, AW, AH: Integer);
var
  uv: TGLUV;
  r: TfpgRect;
  sw, sh, sx, sy: Integer;
  cw: TGLColor;
begin
  if (FWindow = nil) or (AW <= 0) or (AH <= 0) then
    Exit;

  { Source rect and scratch texture live in physical pixels; the destination
    quad stays logical and DrawTexturedQuad applies FScale. }
  sw := Round(AW * FScale);
  sh := Round(AH * FScale);
  if sw <= 0 then
    sw := AW;
  if sh <= 0 then
    sh := AH;

  if (FCopyTex = 0) or (FCopyW < sw) or (FCopyH < sh) then
  begin
    if FCopyTex <> 0 then
      glDeleteTextures(1, @FCopyTex);
    FCopyW := sw;
    FCopyH := sh;
    glGenTextures(1, @FCopyTex);
    glBindTexture(GL_TEXTURE_2D, FCopyTex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, FCopyW, FCopyH, 0,
      GL_RGBA, GL_UNSIGNED_BYTE, nil);
  end;

  FlushBatch;
  sx := Round(ASrcX * FScale);
  sy := Round(ASrcY * FScale);
  FWindow.BindFBO;
  glBindTexture(GL_TEXTURE_2D, FCopyTex);
  glCopyTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0,
    sx, FWindow.FBOHeight - sy - sh, sw, sh);

  r.SetRect(ADstX, ADstY, AW, AH);
  uv.U1 := 0; uv.V1 := 0;
  uv.U2 := sw / FCopyW; uv.V2 := sh / FCopyH;
  cw := ToColor(clWhite);
  UseTextured(FCopyTex, False, False, False);
  AppendQuad(r.Left, r.Top, r.Left + r.Width, r.Top + r.Height,
    uv, cw, cw, False);
end;

procedure TfpgOhosGLDraw.CopyRectFromWindow(ASrcWindow: TfpgOhosGLWindow;
  ASrcX, ASrcY, ADstX, ADstY, AW, AH: Integer);
var
  uv: TGLUV;
  r: TfpgRect;
  sw, sh, sx, sy: Integer;
  cw: TGLColor;
begin
  if (FWindow = nil) or (ASrcWindow = nil) or (AW <= 0) or (AH <= 0) then
    Exit;

  sw := Round(AW * FScale);
  sh := Round(AH * FScale);
  if sw <= 0 then
    sw := AW;
  if sh <= 0 then
    sh := AH;

  if (FCopyTex = 0) or (FCopyW < sw) or (FCopyH < sh) then
  begin
    if FCopyTex <> 0 then
      glDeleteTextures(1, @FCopyTex);
    FCopyW := sw;
    FCopyH := sh;
    glGenTextures(1, @FCopyTex);
    glBindTexture(GL_TEXTURE_2D, FCopyTex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, FCopyW, FCopyH, 0,
      GL_RGBA, GL_UNSIGNED_BYTE, nil);
  end;

  FlushBatch;
  sx := Round(ASrcX * FScale);
  sy := Round(ASrcY * FScale);
  ASrcWindow.BindFBO;
  glBindTexture(GL_TEXTURE_2D, FCopyTex);
  glCopyTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0,
    sx, ASrcWindow.FBOHeight - sy - sh, sw, sh);
  FWindow.BindFBO;

  r.SetRect(ADstX, ADstY, AW, AH);
  uv.U1 := 0; uv.V1 := 0;
  uv.U2 := sw / FCopyW; uv.V2 := sh / FCopyH;
  cw := ToColor(clWhite);
  UseTextured(FCopyTex, False, False, False);
  AppendQuad(r.Left, r.Top, r.Left + r.Width, r.Top + r.Height,
    uv, cw, cw, False);
end;

procedure TfpgOhosGLDraw.Flush;
begin
  FlushBatch;
end;

initialization
  GLDraw := TfpgOhosGLDraw.Create;

finalization
  FreeAndNil(GLDraw);

end.
