{
    fpGUI  -  Free Pascal GUI Toolkit

    Copyright (c) 2026 See the file AUTHORS.txt, included in this
    distribution, for details of the copyright.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      HarmonyOS GL display / window management for the Phase 0 + Phase 1
      presentation layer.

      TfpgOhosGLDisplay owns the process-wide EGLDisplay / EGLConfig /
      EGLContext.  TfpgOhosGLWindow owns one EGLSurface per OHNativeWindow
      and draws a full-screen textured quad to present a CPU-rendered frame.

      This unit deliberately does not depend on fpg_ohos.  The platform
      backend talks to it through fpg_ohos_gl_iface only, avoiding a
      circular unit reference.
}

unit fpg_ohos_gl;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  CTypes,
  fpg_impl,
  fpg_ohos_egl,
  fpg_ohos_gl_iface;

const
  GL_LOG_INFO  = 4;
  GL_LOG_WARN  = 5;
  GL_LOG_ERROR = 6;

procedure GL_Log(level: Integer; const Msg: string);

type
  TGLWindowState = (glsNoSurface, glsReady, glsLost);

  { Process-wide EGL state.  Created lazily on the first presenter attach. }
  TfpgOhosGLDisplay = class
  private
    FDisplay: EGLDisplay;
    FConfig: EGLConfig;
    FContext: EGLContext;
    FInitialized: Boolean;
    FAttempted: Boolean;
    FIsES3: Boolean;
    function ChooseConfig(AES3, AWithStencil: Boolean): Boolean;
    function CreateContext(AES3: Boolean): Boolean;
  public
    class function Instance: TfpgOhosGLDisplay;
    function  TryInitialize: Boolean;
    procedure Shutdown;
    destructor Destroy; override;
    property  Display: EGLDisplay read FDisplay;
    property  Config: EGLConfig read FConfig;
    property  Context: EGLContext read FContext;
    property  IsES3: Boolean read FIsES3;
  end;

  { One EGLSurface per native window, plus the present shader/VBO. }
  TfpgOhosGLWindow = class
  private
    FWinHandle: TfpgWinHandle;
    FEGLSurface: EGLSurface;
    FState: TGLWindowState;
    FWidth: Integer;
    FHeight: Integer;
    FFirstFrameSent: Boolean;
    FPresentProgram: GLuint;
    FPresentVBO: GLuint;
    FUniformTex: GLint;
    FUniformUVMax: GLint;
    FUniformFlipY: GLint;
    FUniformSwizzleRB: GLint;
    FFBO: GLuint;
    FColorTex: GLuint;
    FStencilRB: GLuint;
    FFBOWidth: Integer;
    FFBOHeight: Integer;
    FHasFBO: Boolean;
    FPresentPending: Boolean;
    function  QuerySurfaceSize(out AW, AH: Integer): Boolean;
    function  CompileShader(AShaderType: GLuint; const ASource: string): GLuint;
    function  LinkProgram(AVert, AFrag: GLuint): GLuint;
    procedure CreatePresentResources;
    procedure ReleasePresentResources;
  public
    constructor Create;
    destructor  Destroy; override;
    function  MakeCurrent: Boolean;
    function  Attach(AWinHandle: TfpgWinHandle; AWidth, AHeight: Integer): Boolean;
    procedure Resize(AWidth, AHeight: Integer);
    procedure Suspend;
    procedure ResetFirstFrame;
    function  PresentTexture(ATexture: GLuint; ATexW, ATexH,
      AWinW, AWinH: Integer; AFlipY, ASwizzleRB: Boolean): Boolean;
    { Phase 2: retained off-screen render target. }
    function  EnsureFBO(AWidth, AHeight: Integer): Boolean;
    procedure BindFBO;
    procedure PresentFBO;
    procedure ReleaseFBO;
    { Phase 3: recreate the EGLSurface/FBO after context loss. }
    function  Recover(AWidth, AHeight: Integer): Boolean;
    property  State: TGLWindowState read FState;
    property  PresentPending: Boolean read FPresentPending write FPresentPending;
    property  WinHandle: TfpgWinHandle read FWinHandle;
    property  Width: Integer read FWidth;
    property  Height: Integer read FHeight;
    property  HasFBO: Boolean read FHasFBO;
    property  FBOWidth: Integer read FFBOWidth;
    property  FBOHeight: Integer read FFBOHeight;
    property  ColorTexture: GLuint read FColorTex;
  end;

var
  { When False, eglSwapBuffers does not block on vsync (lower latency, may
    tear).  Set before the first window is created.  Default: on. }
  GLVSyncEnabled: Boolean = True;

implementation

uses
  fpg_ohos_gl_shaders;

{ ── logging ────────────────────────────────────────────────────────── }

procedure OH_LOG_Print(logType: Integer; logLevel: Integer;
  domain: Cardinal; tag: PChar; fmt: PChar); cdecl; varargs;
  external 'libhilog_ndk.z.so';

const
  LOG_APP = 0;
  FP_LOG_DOMAIN = $FF00;
  FP_LOG_TAG = 'fpGUI-GL';

procedure GL_Log(level: Integer; const Msg: string);
var
  buf: array[0..1023] of Char;
begin
  StrPLCopy(buf, Msg, SizeOf(buf) - 1);
  buf[High(buf)] := #0;
  OH_LOG_Print(LOG_APP, level, FP_LOG_DOMAIN, FP_LOG_TAG, '%{public}s', buf);
end;

{ ── TfpgOhosGLDisplay ──────────────────────────────────────────────── }

var
  GDisplay: TfpgOhosGLDisplay = nil;

class function TfpgOhosGLDisplay.Instance: TfpgOhosGLDisplay;
begin
  if GDisplay = nil then
    GDisplay := TfpgOhosGLDisplay.Create;
  Result := GDisplay;
end;

function TfpgOhosGLDisplay.ChooseConfig(AES3, AWithStencil: Boolean): Boolean;
var
  attribs: array[0..15] of EGLint;
  numConfigs: EGLint;
begin
  Result := False;
  FillChar(attribs, SizeOf(attribs), 0);

  attribs[0]  := EGL_SURFACE_TYPE;
  attribs[1]  := EGL_WINDOW_BIT;
  attribs[2]  := EGL_RENDERABLE_TYPE;
  if AES3 then
    attribs[3] := EGL_OPENGL_ES3_BIT
  else
    attribs[3] := EGL_OPENGL_ES2_BIT;
  attribs[4]  := EGL_RED_SIZE;
  attribs[5]  := 8;
  attribs[6]  := EGL_GREEN_SIZE;
  attribs[7]  := 8;
  attribs[8]  := EGL_BLUE_SIZE;
  attribs[9]  := 8;
  attribs[10] := EGL_ALPHA_SIZE;
  attribs[11] := 8;
  attribs[12] := EGL_STENCIL_SIZE;
  if AWithStencil then
    attribs[13] := 8
  else
    attribs[13] := 0;
  attribs[14] := EGL_NONE;
  attribs[15] := 0;

  numConfigs := 0;
  if eglChooseConfig(FDisplay, @attribs[0], @FConfig, 1, @numConfigs) = 0 then
    Exit;
  Result := numConfigs > 0;
end;

function TfpgOhosGLDisplay.CreateContext(AES3: Boolean): Boolean;
var
  attribs: array[0..2] of EGLint;
begin
  attribs[0] := EGL_CONTEXT_CLIENT_VERSION;
  if AES3 then
    attribs[1] := 3
  else
    attribs[1] := 2;
  attribs[2] := EGL_NONE;

  FContext := eglCreateContext(FDisplay, FConfig, EGL_NO_CONTEXT, @attribs[0]);
  FIsES3 := AES3;
  Result := FContext <> EGL_NO_CONTEXT;
end;

function TfpgOhosGLDisplay.TryInitialize: Boolean;
var
  major, minor: EGLint;
  version, renderer: PChar;
  vstr, rstr: string;
begin
  if FInitialized then
    Exit(True);
  if FAttempted then
    Exit(False);
  FAttempted := True;

  FDisplay := eglGetDisplay(EGL_DEFAULT_DISPLAY);
  if FDisplay = EGL_NO_DISPLAY then
  begin
    GL_Log(GL_LOG_ERROR, 'eglGetDisplay failed');
    Exit(False);
  end;

  major := 0;
  minor := 0;
  if eglInitialize(FDisplay, @major, @minor) = 0 then
  begin
    GL_Log(GL_LOG_ERROR, 'eglInitialize failed: ' + IntToStr(eglGetError));
    FDisplay := EGL_NO_DISPLAY;
    Exit(False);
  end;

  if eglBindAPI(EGL_OPENGL_ES_API) = 0 then
  begin
    GL_Log(GL_LOG_ERROR, 'eglBindAPI(EGL_OPENGL_ES_API) failed: ' + IntToStr(eglGetError));
    eglTerminate(FDisplay);
    FDisplay := EGL_NO_DISPLAY;
    Exit(False);
  end;

  { Preferred: ES3 + stencil.  Fall back to ES3 without stencil, then ES2. }
  if not (ChooseConfig(True, True) and CreateContext(True)) then
  begin
    FContext := EGL_NO_CONTEXT;
    if not (ChooseConfig(True, False) and CreateContext(True)) then
    begin
      FContext := EGL_NO_CONTEXT;
      if not (ChooseConfig(False, False) and CreateContext(False)) then
      begin
        GL_Log(GL_LOG_ERROR, 'no usable EGL config/context: ' + IntToStr(eglGetError));
        eglTerminate(FDisplay);
        FDisplay := EGL_NO_DISPLAY;
        Exit(False);
      end;
    end;
  end;

  FInitialized := True;

  { Query GL strings with the context current.  EGL allows a context with no
    draw surface; if the driver rejects it, keep the log generic. }
  version := nil;
  renderer := nil;
  if eglMakeCurrent(FDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, FContext) <> 0 then
  begin
    version := glGetString(GL_VERSION);
    renderer := glGetString(GL_RENDERER);
    eglMakeCurrent(FDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  end;
  if version <> nil then
    vstr := StrPas(version)
  else
    vstr := '?';
  if renderer <> nil then
    rstr := StrPas(renderer)
  else
    rstr := '?';

  GL_Log(GL_LOG_INFO, 'EGL ' + IntToStr(major) + '.' + IntToStr(minor) +
    ' ES3=' + BoolToStr(FIsES3, True) +
    ' GL=' + vstr +
    ' renderer=' + rstr);
  Result := True;
end;

procedure TfpgOhosGLDisplay.Shutdown;
begin
  if FDisplay = EGL_NO_DISPLAY then
    Exit;
  if FContext <> EGL_NO_CONTEXT then
  begin
    eglMakeCurrent(FDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(FDisplay, FContext);
    FContext := EGL_NO_CONTEXT;
  end;
  eglTerminate(FDisplay);
  FDisplay := EGL_NO_DISPLAY;
  FConfig := nil;
  FInitialized := False;
end;

destructor TfpgOhosGLDisplay.Destroy; // called via FreeAndNil(GDisplay)
begin
  Shutdown;
  inherited Destroy;
end;

{ ── TfpgOhosGLWindow ───────────────────────────────────────────────── }

constructor TfpgOhosGLWindow.Create;
begin
  inherited Create;
  FWinHandle := nil;
  FEGLSurface := EGL_NO_SURFACE;
  FState := glsNoSurface;
  FWidth := 0;
  FHeight := 0;
  FFirstFrameSent := False;
  FPresentProgram := 0;
  FPresentVBO := 0;
  FUniformTex := -1;
  FUniformUVMax := -1;
  FUniformFlipY := -1;
  FUniformSwizzleRB := -1;
  FFBO := 0;
  FColorTex := 0;
  FStencilRB := 0;
  FFBOWidth := 0;
  FFBOHeight := 0;
  FHasFBO := False;
  FPresentPending := False;
end;

destructor TfpgOhosGLWindow.Destroy;
begin
  if (FState = glsReady) and MakeCurrent then
  begin
    ReleasePresentResources;
    ReleaseFBO;
  end
  else
  begin
    FPresentProgram := 0;
    FPresentVBO := 0;
    FFBO := 0;
    FColorTex := 0;
    FStencilRB := 0;
    FHasFBO := False;
  end;
  Suspend;
  inherited Destroy;
end;

function TfpgOhosGLWindow.MakeCurrent: Boolean;
begin
  Result := False;
  if (FEGLSurface = EGL_NO_SURFACE) or (FState = glsNoSurface) then
    Exit;
  if TfpgOhosGLDisplay.Instance.Display = EGL_NO_DISPLAY then
    Exit;
  if eglMakeCurrent(TfpgOhosGLDisplay.Instance.Display, FEGLSurface, FEGLSurface,
    TfpgOhosGLDisplay.Instance.Context) = 0 then
  begin
    GL_Log(GL_LOG_WARN, 'eglMakeCurrent failed: ' + IntToStr(eglGetError));
    FState := glsLost;
    Exit;
  end;
  Result := True;
end;

function TfpgOhosGLWindow.QuerySurfaceSize(out AW, AH: Integer): Boolean;
var
  w, h: EGLint;
begin
  Result := False;
  AW := 0;
  AH := 0;
  if FEGLSurface = EGL_NO_SURFACE then
    Exit;
  w := 0;
  h := 0;
  if eglQuerySurface(TfpgOhosGLDisplay.Instance.Display, FEGLSurface,
    EGL_WIDTH, @w) = 0 then
    Exit;
  if eglQuerySurface(TfpgOhosGLDisplay.Instance.Display, FEGLSurface,
    EGL_HEIGHT, @h) = 0 then
    Exit;
  AW := w;
  AH := h;
  Result := (AW > 0) and (AH > 0);
end;

function TfpgOhosGLWindow.CompileShader(AShaderType: GLuint;
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
    GL_Log(GL_LOG_ERROR, 'GL shader compile failed: ' + StrPas(@log[0]));
    glDeleteShader(Result);
    Result := 0;
  end;
end;

function TfpgOhosGLWindow.LinkProgram(AVert, AFrag: GLuint): GLuint;
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
  glBindAttribLocation(Result, 1, 'aUV');
  glLinkProgram(Result);
  status := 0;
  glGetProgramiv(Result, GL_LINK_STATUS, @status);
  if status = 0 then
  begin
    FillChar(log, SizeOf(log), 0);
    len := 0;
    glGetProgramInfoLog(Result, SizeOf(log), @len, @log[0]);
    GL_Log(GL_LOG_ERROR, 'GL program link failed: ' + StrPas(@log[0]));
    glDeleteProgram(Result);
    Result := 0;
  end;
end;

procedure TfpgOhosGLWindow.CreatePresentResources;
var
  vert, frag: GLuint;
begin
  if FPresentProgram <> 0 then
    Exit;

  if TfpgOhosGLDisplay.Instance.IsES3 then
  begin
    vert := CompileShader(GL_VERTEX_SHADER, PRESENT_VERT_SRC_ES3);
    if vert = 0 then
      Exit;
    frag := CompileShader(GL_FRAGMENT_SHADER, PRESENT_FRAG_SRC_ES3);
  end
  else
  begin
    vert := CompileShader(GL_VERTEX_SHADER, PRESENT_VERT_SRC_ES2);
    if vert = 0 then
      Exit;
    frag := CompileShader(GL_FRAGMENT_SHADER, PRESENT_FRAG_SRC_ES2);
  end;
  if frag = 0 then
  begin
    glDeleteShader(vert);
    Exit;
  end;

  FPresentProgram := LinkProgram(vert, frag);
  glDeleteShader(vert);
  glDeleteShader(frag);
  if FPresentProgram = 0 then
    Exit;

  FUniformTex := glGetUniformLocation(FPresentProgram, 'uTex');
  FUniformUVMax := glGetUniformLocation(FPresentProgram, 'uUVMax');
  FUniformFlipY := glGetUniformLocation(FPresentProgram, 'uFlipY');
  FUniformSwizzleRB := glGetUniformLocation(FPresentProgram, 'uSwizzleRB');

  glGenBuffers(1, @FPresentVBO);
  if FPresentVBO = 0 then
  begin
    glDeleteProgram(FPresentProgram);
    FPresentProgram := 0;
    Exit;
  end;
  glBindBuffer(GL_ARRAY_BUFFER, FPresentVBO);
  glBufferData(GL_ARRAY_BUFFER, GLsizeiptr(SizeOf(PRESENT_VERTS)),
    @PRESENT_VERTS[0], GL_STATIC_DRAW);
end;

procedure TfpgOhosGLWindow.ReleasePresentResources;
begin
  if FPresentVBO <> 0 then
  begin
    glDeleteBuffers(1, @FPresentVBO);
    FPresentVBO := 0;
  end;
  if FPresentProgram <> 0 then
  begin
    glDeleteProgram(FPresentProgram);
    FPresentProgram := 0;
  end;
  FUniformTex := -1;
  FUniformUVMax := -1;
  FUniformFlipY := -1;
  FUniformSwizzleRB := -1;
end;

{ ── Phase 2: retained FBO ─────────────────────────────────────────── }

function TfpgOhosGLWindow.EnsureFBO(AWidth, AHeight: Integer): Boolean;
var
  internalFmt: GLint;
begin
  Result := False;
  if (AWidth <= 0) or (AHeight <= 0) then
    Exit;
  if FHasFBO and (FFBOWidth = AWidth) and (FFBOHeight = AHeight) then
    Exit(True);
  if not MakeCurrent then
    Exit;

  ReleaseFBO;
  FFBOWidth := AWidth;
  FFBOHeight := AHeight;

  glGenTextures(1, @FColorTex);
  if FColorTex = 0 then
    Exit;
  glBindTexture(GL_TEXTURE_2D, FColorTex);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  if TfpgOhosGLDisplay.Instance.IsES3 then
    internalFmt := GL_RGBA8
  else
    internalFmt := GL_RGBA;
  glTexImage2D(GL_TEXTURE_2D, 0, internalFmt, AWidth, AHeight, 0,
    GL_RGBA, GL_UNSIGNED_BYTE, nil);

  glGenFramebuffers(1, @FFBO);
  if FFBO = 0 then
  begin
    ReleaseFBO;
    Exit;
  end;
  glBindFramebuffer(GL_FRAMEBUFFER, FFBO);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
    GL_TEXTURE_2D, FColorTex, 0);

  glGenRenderbuffers(1, @FStencilRB);
  if FStencilRB <> 0 then
  begin
    glBindRenderbuffer(GL_RENDERBUFFER, FStencilRB);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_STENCIL_INDEX8, AWidth, AHeight);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT,
      GL_RENDERBUFFER, FStencilRB);
  end;

  if glCheckFramebufferStatus(GL_FRAMEBUFFER) <> GL_FRAMEBUFFER_COMPLETE then
  begin
    GL_Log(GL_LOG_ERROR, 'GL FBO incomplete');
    ReleaseFBO;
    Exit;
  end;

  glViewport(0, 0, AWidth, AHeight);
  glDisable(GL_SCISSOR_TEST);
  glClearColor(1.0, 1.0, 1.0, 1.0);
  glClear(GL_COLOR_BUFFER_BIT or GL_STENCIL_BUFFER_BIT);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);

  FHasFBO := True;
  Result := True;
end;

procedure TfpgOhosGLWindow.BindFBO;
begin
  if not FHasFBO then
    Exit;
  glBindFramebuffer(GL_FRAMEBUFFER, FFBO);
  glViewport(0, 0, FFBOWidth, FFBOHeight);
end;

procedure TfpgOhosGLWindow.PresentFBO;
begin
  if not FHasFBO then
    Exit;
  PresentTexture(FColorTex, FFBOWidth, FFBOHeight,
    FFBOWidth, FFBOHeight, False, False);
end;

procedure TfpgOhosGLWindow.ReleaseFBO;
begin
  if FFBO <> 0 then
  begin
    glDeleteFramebuffers(1, @FFBO);
    FFBO := 0;
  end;
  if FStencilRB <> 0 then
  begin
    glDeleteRenderbuffers(1, @FStencilRB);
    FStencilRB := 0;
  end;
  if FColorTex <> 0 then
  begin
    glDeleteTextures(1, @FColorTex);
    FColorTex := 0;
  end;
  FHasFBO := False;
  FFBOWidth := 0;
  FFBOHeight := 0;
end;

function TfpgOhosGLWindow.Recover(AWidth, AHeight: Integer): Boolean;
begin
  Result := False;
  if FState = glsReady then
    Exit(True);
  { The display/context may also have been lost; TryInitialize is idempotent
    and rebuilds it when needed. }
  if not TfpgOhosGLDisplay.Instance.TryInitialize then
    Exit;
  Suspend;
  if FWinHandle = nil then
    Exit;
  if AWidth <= 0 then
    AWidth := FWidth;
  if AHeight <= 0 then
    AHeight := FHeight;
  Result := Attach(FWinHandle, AWidth, AHeight);
  if Result then
    Result := EnsureFBO(AWidth, AHeight);
  if Result then
  begin
    FState := glsReady;
    FFirstFrameSent := False;
  end;
end;

function TfpgOhosGLWindow.Attach(AWinHandle: TfpgWinHandle;
  AWidth, AHeight: Integer): Boolean;
begin
  Result := False;
  if AWinHandle = nil then
    Exit;

  if (FState = glsReady) and (FWinHandle = AWinHandle) then
  begin
    if (AWidth > 0) and (AHeight > 0) and
       ((AWidth <> FWidth) or (AHeight <> FHeight)) then
      Resize(AWidth, AHeight);
    Exit(True);
  end;

  Suspend;

  if not TfpgOhosGLDisplay.Instance.TryInitialize then
    Exit;

  FWinHandle := AWinHandle;
  FEGLSurface := eglCreateWindowSurface(TfpgOhosGLDisplay.Instance.Display,
    TfpgOhosGLDisplay.Instance.Config, EGLNativeWindowType(AWinHandle), nil);
  if FEGLSurface = EGL_NO_SURFACE then
  begin
    GL_Log(GL_LOG_ERROR, 'eglCreateWindowSurface failed: ' + IntToStr(eglGetError));
    FWinHandle := nil;
    Exit;
  end;

  if not MakeCurrent then
  begin
    eglDestroySurface(TfpgOhosGLDisplay.Instance.Display, FEGLSurface);
    FEGLSurface := EGL_NO_SURFACE;
    FWinHandle := nil;
    Exit;
  end;

  eglSwapInterval(TfpgOhosGLDisplay.Instance.Display, Ord(GLVSyncEnabled));
  CreatePresentResources;

  FWidth := AWidth;
  FHeight := AHeight;
  FState := glsReady;
  FFirstFrameSent := False;
  Result := True;
end;

procedure TfpgOhosGLWindow.Resize(AWidth, AHeight: Integer);
begin
  if AWidth > 0 then
    FWidth := AWidth;
  if AHeight > 0 then
    FHeight := AHeight;
end;

procedure TfpgOhosGLWindow.Suspend;
begin
  if FEGLSurface <> EGL_NO_SURFACE then
  begin
    if TfpgOhosGLDisplay.Instance.Display <> EGL_NO_DISPLAY then
    begin
      eglMakeCurrent(TfpgOhosGLDisplay.Instance.Display,
        EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
      eglDestroySurface(TfpgOhosGLDisplay.Instance.Display, FEGLSurface);
    end;
    FEGLSurface := EGL_NO_SURFACE;
  end;
  FWinHandle := nil;
  FState := glsLost;
end;

procedure TfpgOhosGLWindow.ResetFirstFrame;
begin
  FFirstFrameSent := False;
end;

function TfpgOhosGLWindow.PresentTexture(ATexture: GLuint;
  ATexW, ATexH, AWinW, AWinH: Integer; AFlipY, ASwizzleRB: Boolean): Boolean;
var
  sw, sh, vw, vh, surfW, surfH: Integer;
  uvx, uvy: Single;
begin
  Result := False;
  if (FState <> glsReady) or (ATexture = 0) or (FPresentProgram = 0) then
    Exit;
  if not MakeCurrent then
    Exit;

  { Surface size is authoritative; ETS may have resized it since Attach. }
  sw := 0;
  sh := 0;
  if QuerySurfaceSize(sw, sh) then
  begin
    if (sw > 0) and (sh > 0) and ((sw <> FWidth) or (sh <> FHeight)) then
    begin
      FWidth := sw;
      FHeight := sh;
    end;
  end;

  if AWinW <= 0 then
    AWinW := FWidth;
  if AWinH <= 0 then
    AWinH := FHeight;
  if AWinW <= 0 then
    AWinW := ATexW;
  if AWinH <= 0 then
    AWinH := ATexH;
  if (AWinW <= 0) or (AWinH <= 0) or (ATexW <= 0) or (ATexH <= 0) then
    Exit;

  { Only draw the region actually covered by the CPU buffer.  The rest of
    the window is cleared to the same white the software path uses, so a
    stale/garbage area never appears while the surface catches up. }
  surfW := FWidth;
  if surfW <= 0 then
    surfW := AWinW;
  surfH := FHeight;
  if surfH <= 0 then
    surfH := AWinH;

  vw := AWinW;
  if ATexW < vw then
    vw := ATexW;
  if surfW < vw then
    vw := surfW;
  vh := AWinH;
  if ATexH < vh then
    vh := ATexH;
  if surfH < vh then
    vh := surfH;
  if (vw <= 0) or (vh <= 0) then
    Exit;

  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glDisable(GL_SCISSOR_TEST);
  glDisable(GL_BLEND);
  glClearColor(1.0, 1.0, 1.0, 1.0);
  glClear(GL_COLOR_BUFFER_BIT);

  { Top-left aligned, in GL's bottom-left coordinate system. }
  glViewport(0, surfH - vh, vw, vh);

  uvx := vw / ATexW;
  uvy := vh / ATexH;

  glUseProgram(FPresentProgram);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, ATexture);
  glUniform1i(FUniformTex, 0);
  glUniform2f(FUniformUVMax, uvx, uvy);
  if AFlipY then
    glUniform1f(FUniformFlipY, 1.0)
  else
    glUniform1f(FUniformFlipY, 0.0);
  if ASwizzleRB then
    glUniform1f(FUniformSwizzleRB, 1.0)
  else
    glUniform1f(FUniformSwizzleRB, 0.0);

  glBindBuffer(GL_ARRAY_BUFFER, FPresentVBO);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, SizeOf(TPresentVertex),
    Pointer(PtrUInt(0)));
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, SizeOf(TPresentVertex),
    Pointer(PtrUInt(8)));
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

  if eglSwapBuffers(TfpgOhosGLDisplay.Instance.Display, FEGLSurface) = 0 then
  begin
    GL_Log(GL_LOG_WARN, 'eglSwapBuffers failed: ' + IntToStr(eglGetError));
    FState := glsLost;
    Exit;
  end;

  if not FFirstFrameSent then
  begin
    FFirstFrameSent := True;
    if Assigned(GLNotifyFirstFrame) then
      GLNotifyFirstFrame(FWinHandle);
  end;

  Result := True;
end;

initialization
  { Nothing: the display is created lazily by TfpgOhosGLDisplay.Instance. }

finalization
  FreeAndNil(GDisplay);

end.
