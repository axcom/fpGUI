{
    fpGUI  -  Free Pascal GUI Toolkit

    Copyright (c) 2026 See the file AUTHORS.txt, included in this
    distribution, for details of the copyright.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      HarmonyOS EGL / OpenGL ES bindings used by the GL presentation layer.

      Only the subset needed by the Phase 0/1 GL presenter is declared here.
      The unit intentionally has no dependency on fpg_base or fpg_ohos so it
      can be used by both the platform backend and the presenter.

      Libraries (OHOS NDK):
        libEGL.so      - EGL
        libGLESv3.so   - OpenGL ES 3.0 (also exports the ES2 entry points)
}

unit fpg_ohos_egl;

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  CTypes;

const
  LIB_EGL   = 'libEGL.so';
  LIB_GLES3 = 'libGLESv3.so';

  { ── EGL ───────────────────────────────────────────────────────────── }
  EGL_NO_DISPLAY      = Pointer(0);
  EGL_NO_SURFACE      = Pointer(0);
  EGL_NO_CONTEXT      = Pointer(0);
  EGL_DEFAULT_DISPLAY = Pointer(0);

  EGL_OPENGL_ES_API   = $30A0;
  EGL_OPENGL_ES2_BIT  = $0004;
  EGL_OPENGL_ES3_BIT  = $0040;

  EGL_SURFACE_TYPE    = $3033;
  EGL_WINDOW_BIT      = $0004;
  EGL_RENDERABLE_TYPE = $3040;
  EGL_RED_SIZE        = $3024;
  EGL_GREEN_SIZE      = $3023;
  EGL_BLUE_SIZE       = $3022;
  EGL_ALPHA_SIZE      = $3021;
  EGL_DEPTH_SIZE      = $3025;
  EGL_STENCIL_SIZE    = $3026;
  EGL_NONE            = $3038;

  EGL_CONTEXT_CLIENT_VERSION = $3098;
  EGL_WIDTH  = $3057;
  EGL_HEIGHT = $3056;

  { ── GLES 3.0 / 2.0 core constants ────────────────────────────────── }
  GL_FALSE = 0;
  GL_TRUE  = 1;
  GL_NO_ERROR = 0;

  GL_POINTS         = $0000;
  GL_LINES          = $0001;
  GL_TRIANGLES      = $0004;
  GL_TRIANGLE_STRIP = $0005;
  GL_TRIANGLE_FAN   = $0006;

  GL_ALWAYS   = $0207;
  GL_NOTEQUAL = $0205;
  GL_KEEP     = $1E00;
  GL_INVERT   = $150A;
  GL_REPLACE  = $1E01;

  GL_DEPTH_BUFFER_BIT   = $00000100;
  GL_STENCIL_BUFFER_BIT = $00000400;
  GL_COLOR_BUFFER_BIT   = $00004000;

  GL_BLEND              = $0BE2;
  GL_SCISSOR_TEST       = $0C11;
  GL_STENCIL_TEST       = $0B90;

  GL_ZERO                = 0;
  GL_ONE                 = 1;
  GL_SRC_ALPHA           = $0302;
  GL_ONE_MINUS_SRC_ALPHA = $0303;

  GL_FLOAT          = $1406;
  GL_UNSIGNED_BYTE  = $1401;
  GL_RGBA           = $1908;
  GL_RGBA8          = $8058;
  GL_RED            = $1903;
  GL_R8             = $8229;

  GL_TEXTURE_2D          = $0DE1;
  GL_TEXTURE0            = $84C0;
  GL_TEXTURE_MIN_FILTER  = $2801;
  GL_TEXTURE_MAG_FILTER  = $2800;
  GL_TEXTURE_WRAP_S      = $2802;
  GL_TEXTURE_WRAP_T      = $2803;
  GL_CLAMP_TO_EDGE       = $812F;
  GL_NEAREST             = $2600;
  GL_LINEAR              = $2601;

  GL_ARRAY_BUFFER   = $8892;
  GL_STATIC_DRAW    = $88E4;
  GL_STREAM_DRAW    = $88E0;

  GL_VERTEX_SHADER   = $8B31;
  GL_FRAGMENT_SHADER = $8B30;
  GL_COMPILE_STATUS  = $8B81;
  GL_LINK_STATUS     = $8B82;
  GL_INFO_LOG_LENGTH = $8B84;

  GL_FRAMEBUFFER          = $8D40;
  GL_READ_FRAMEBUFFER     = $8CA8;
  GL_DRAW_FRAMEBUFFER     = $8CA9;
  GL_RENDERBUFFER         = $8D41;
  GL_COLOR_ATTACHMENT0    = $8CE0;
  GL_STENCIL_ATTACHMENT   = $8D20;
  GL_STENCIL_INDEX8       = $8D48;
  GL_FRAMEBUFFER_COMPLETE = $8CD5;
  GL_FRAMEBUFFER_BINDING  = $8CA6;

  GL_MAX_TEXTURE_SIZE = $0D33;
  GL_VERSION          = $1F02;
  GL_RENDERER         = $1F01;
  GL_VENDOR           = $1F00;

  GL_UNPACK_ALIGNMENT   = $0CF5;
  GL_UNPACK_ROW_LENGTH  = $0CF2;
  GL_PACK_ALIGNMENT     = $0D05;

type
  EGLint     = Int32;
  EGLBoolean = UInt32;
  EGLenum    = UInt32;
  EGLDisplay = Pointer;
  EGLConfig  = Pointer;
  EGLSurface = Pointer;
  EGLContext = Pointer;

  EGLNativeDisplayType = Pointer;
  EGLNativeWindowType  = Pointer;

  PEGLint    = ^EGLint;
  PEGLConfig = ^EGLConfig;

  GLuint     = UInt32;
  GLint      = Int32;
  GLsizei    = Int32;
  GLenum     = UInt32;
  GLboolean  = Byte;
  GLbitfield = UInt32;
  GLfloat    = Single;
  GLchar     = Char;
  PGLint     = ^GLint;
  PGLuint    = ^GLuint;
  PGLfloat   = ^GLfloat;
  PGLchar    = PChar;
  PPGLchar   = ^PChar;
  GLsizeiptr = PtrInt;

{ ── EGL functions ───────────────────────────────────────────────────── }
function eglGetDisplay(display_id: EGLNativeDisplayType): EGLDisplay; cdecl; external LIB_EGL;
function eglInitialize(dpy: EGLDisplay; major, minor: PEGLint): EGLBoolean; cdecl; external LIB_EGL;
function eglBindAPI(api: EGLenum): EGLBoolean; cdecl; external LIB_EGL;
function eglChooseConfig(dpy: EGLDisplay; attrib_list: PEGLint;
  configs: PEGLConfig; config_size: EGLint; num_config: PEGLint): EGLBoolean; cdecl; external LIB_EGL;
function eglCreateWindowSurface(dpy: EGLDisplay; config: EGLConfig;
  win: EGLNativeWindowType; attrib_list: PEGLint): EGLSurface; cdecl; external LIB_EGL;
function eglCreateContext(dpy: EGLDisplay; config: EGLConfig;
  share_context: EGLContext; attrib_list: PEGLint): EGLContext; cdecl; external LIB_EGL;
function eglMakeCurrent(dpy: EGLDisplay; draw, read: EGLSurface;
  ctx: EGLContext): EGLBoolean; cdecl; external LIB_EGL;
function eglSwapBuffers(dpy: EGLDisplay; surface: EGLSurface): EGLBoolean; cdecl; external LIB_EGL;
function eglSwapInterval(dpy: EGLDisplay; interval: EGLint): EGLBoolean; cdecl; external LIB_EGL;
function eglQuerySurface(dpy: EGLDisplay; surface: EGLSurface;
  attribute: EGLint; value: PEGLint): EGLBoolean; cdecl; external LIB_EGL;
function eglDestroySurface(dpy: EGLDisplay; surface: EGLSurface): EGLBoolean; cdecl; external LIB_EGL;
function eglDestroyContext(dpy: EGLDisplay; ctx: EGLContext): EGLBoolean; cdecl; external LIB_EGL;
function eglTerminate(dpy: EGLDisplay): EGLBoolean; cdecl; external LIB_EGL;
function eglGetError: EGLint; cdecl; external LIB_EGL;
function eglGetProcAddress(procname: PChar): Pointer; cdecl; external LIB_EGL;

{ ── GLES functions ──────────────────────────────────────────────────── }
function glGetError: GLenum; cdecl; external LIB_GLES3;
function glGetString(name: GLenum): PChar; cdecl; external LIB_GLES3;
procedure glGetIntegerv(pname: GLenum; params: PGLint); cdecl; external LIB_GLES3;

procedure glClearColor(red, green, blue, alpha: GLfloat); cdecl; external LIB_GLES3;
procedure glClear(mask: GLbitfield); cdecl; external LIB_GLES3;
procedure glViewport(x, y: GLint; width, height: GLsizei); cdecl; external LIB_GLES3;
procedure glEnable(cap: GLenum); cdecl; external LIB_GLES3;
procedure glDisable(cap: GLenum); cdecl; external LIB_GLES3;
procedure glBlendFunc(sfactor, dfactor: GLenum); cdecl; external LIB_GLES3;
procedure glScissor(x, y: GLint; width, height: GLsizei); cdecl; external LIB_GLES3;
procedure glColorMask(red, green, blue, alpha: GLboolean); cdecl; external LIB_GLES3;
procedure glStencilFunc(func: GLenum; ref_: GLint; mask: GLuint); cdecl; external LIB_GLES3;
procedure glStencilOp(fail, zfail, zpass: GLenum); cdecl; external LIB_GLES3;
procedure glStencilMask(mask: GLuint); cdecl; external LIB_GLES3;
procedure glClearStencil(s: GLint); cdecl; external LIB_GLES3;

procedure glGenTextures(n: GLsizei; textures: PGLuint); cdecl; external LIB_GLES3;
procedure glDeleteTextures(n: GLsizei; textures: PGLuint); cdecl; external LIB_GLES3;
procedure glBindTexture(target: GLenum; texture: GLuint); cdecl; external LIB_GLES3;
procedure glTexImage2D(target: GLenum; level: GLint; internalformat: GLint;
  width, height: GLsizei; border: GLint; format, type_: GLenum; pixels: Pointer); cdecl; external LIB_GLES3;
procedure glTexSubImage2D(target: GLenum; level, xoffset, yoffset: GLint;
  width, height: GLsizei; format, type_: GLenum; pixels: Pointer); cdecl; external LIB_GLES3;
procedure glCopyTexSubImage2D(target: GLenum; level, xoffset, yoffset,
  x, y: GLint; width, height: GLsizei); cdecl; external LIB_GLES3;
procedure glTexParameteri(target, pname: GLenum; param: GLint); cdecl; external LIB_GLES3;
procedure glPixelStorei(pname: GLenum; param: GLint); cdecl; external LIB_GLES3;
procedure glActiveTexture(texture: GLenum); cdecl; external LIB_GLES3;

function glCreateShader(shaderType: GLenum): GLuint; cdecl; external LIB_GLES3;
procedure glShaderSource(shader: GLuint; count: GLsizei;
  const string_: PPGLchar; const length: PGLint); cdecl; external LIB_GLES3;
procedure glCompileShader(shader: GLuint); cdecl; external LIB_GLES3;
procedure glGetShaderiv(shader: GLuint; pname: GLenum; params: PGLint); cdecl; external LIB_GLES3;
procedure glGetShaderInfoLog(shader: GLuint; bufSize: GLsizei;
  length: PGLint; infoLog: PChar); cdecl; external LIB_GLES3;
function glCreateProgram: GLuint; cdecl; external LIB_GLES3;
procedure glAttachShader(AProgram, shader: GLuint); cdecl; external LIB_GLES3;
procedure glBindAttribLocation(AProgram: GLuint; index: GLuint; name: PChar); cdecl; external LIB_GLES3;
procedure glLinkProgram(AProgram: GLuint); cdecl; external LIB_GLES3;
procedure glGetProgramiv(AProgram: GLuint; pname: GLenum; params: PGLint); cdecl; external LIB_GLES3;
procedure glGetProgramInfoLog(AProgram: GLuint; bufSize: GLsizei;
  length: PGLint; infoLog: PChar); cdecl; external LIB_GLES3;
procedure glUseProgram(AProgram: GLuint); cdecl; external LIB_GLES3;
procedure glDeleteShader(shader: GLuint); cdecl; external LIB_GLES3;
procedure glDeleteProgram(AProgram: GLuint); cdecl; external LIB_GLES3;
function glGetUniformLocation(AProgram: GLuint; name: PChar): GLint; cdecl; external LIB_GLES3;
procedure glUniform1i(location: GLint; v0: GLint); cdecl; external LIB_GLES3;
procedure glUniform1f(location: GLint; v0: GLfloat); cdecl; external LIB_GLES3;
procedure glUniform2f(location: GLint; v0, v1: GLfloat); cdecl; external LIB_GLES3;
procedure glUniform4f(location: GLint; v0, v1, v2, v3: GLfloat); cdecl; external LIB_GLES3;

procedure glGenBuffers(n: GLsizei; buffers: PGLuint); cdecl; external LIB_GLES3;
procedure glDeleteBuffers(n: GLsizei; buffers: PGLuint); cdecl; external LIB_GLES3;
procedure glBindBuffer(target: GLenum; buffer: GLuint); cdecl; external LIB_GLES3;
procedure glBufferData(target: GLenum; size: GLsizeiptr; data: Pointer;
  usage: GLenum); cdecl; external LIB_GLES3;
procedure glVertexAttribPointer(index: GLuint; size: GLint; type_: GLenum;
  normalized: GLboolean; stride: GLsizei; const pointer: Pointer); cdecl; external LIB_GLES3;
procedure glEnableVertexAttribArray(index: GLuint); cdecl; external LIB_GLES3;
procedure glDrawArrays(mode: GLenum; first: GLint; count: GLsizei); cdecl; external LIB_GLES3;

procedure glBindFramebuffer(target: GLenum; framebuffer: GLuint); cdecl; external LIB_GLES3;
procedure glGenFramebuffers(n: GLsizei; framebuffers: PGLuint); cdecl; external LIB_GLES3;
procedure glDeleteFramebuffers(n: GLsizei; framebuffers: PGLuint); cdecl; external LIB_GLES3;
procedure glFramebufferTexture2D(target, attachment, textarget: GLenum;
  texture: GLuint; level: GLint); cdecl; external LIB_GLES3;
procedure glGenRenderbuffers(n: GLsizei; renderbuffers: PGLuint); cdecl; external LIB_GLES3;
procedure glDeleteRenderbuffers(n: GLsizei; renderbuffers: PGLuint); cdecl; external LIB_GLES3;
procedure glBindRenderbuffer(target: GLenum; renderbuffer: GLuint); cdecl; external LIB_GLES3;
procedure glRenderbufferStorage(target, internalformat: GLenum;
  width, height: GLsizei); cdecl; external LIB_GLES3;
procedure glFramebufferRenderbuffer(target, attachment, renderbuffertarget: GLenum;
  renderbuffer: GLuint); cdecl; external LIB_GLES3;
function glCheckFramebufferStatus(target: GLenum): GLenum; cdecl; external LIB_GLES3;

procedure glReadPixels(x, y: GLint; width, height: GLsizei;
  format, type_: GLenum; pixels: Pointer); cdecl; external LIB_GLES3;
procedure glFinish; cdecl; external LIB_GLES3;
procedure glFlush; cdecl; external LIB_GLES3;

implementation

end.
