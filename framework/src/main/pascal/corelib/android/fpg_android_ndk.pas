{
    fpGUI  -  Free Pascal GUI Toolkit

    Copyright (c) 2026 See the file AUTHORS.txt, included in this
    distribution, for details of the copyright.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      Android NDK bindings used by the fpGUI Android backend:
      ANativeWindow (surface access for the hybrid AGG canvas) and the
      logcat writer. Kept free of fpGUI dependencies so it can be used
      from low-level units without circular unit references.
}

unit fpg_android_ndk;

{$mode objfpc}{$H+}

interface

uses
  ctypes;

const
  libandroid = 'android';
  liblog     = 'log';

  { ANativeWindow buffer formats }
  WINDOW_FORMAT_RGBA_8888 = 1;
  WINDOW_FORMAT_RGBX_8888 = 2;
  WINDOW_FORMAT_RGB_565   = 4;

  { logcat priorities }
  ANDROID_LOG_VERBOSE = 2;
  ANDROID_LOG_DEBUG   = 3;
  ANDROID_LOG_INFO    = 4;
  ANDROID_LOG_WARN    = 5;
  ANDROID_LOG_ERROR   = 6;

  { MotionEvent actions (getActionMasked) }
  AMOTION_EVENT_ACTION_DOWN         = 0;
  AMOTION_EVENT_ACTION_UP           = 1;
  AMOTION_EVENT_ACTION_MOVE         = 2;
  AMOTION_EVENT_ACTION_CANCEL       = 3;
  AMOTION_EVENT_ACTION_POINTER_DOWN = 5;
  AMOTION_EVENT_ACTION_POINTER_UP   = 6;

  { KeyEvent key codes (subset used by the backend) }
  AKEYCODE_BACK    = 4;
  AKEYCODE_DPAD_UP = 19;
  AKEYCODE_DPAD_DOWN = 20;
  AKEYCODE_DPAD_LEFT = 21;
  AKEYCODE_DPAD_RIGHT = 22;
  AKEYCODE_DPAD_CENTER = 23;
  AKEYCODE_ALT_LEFT  = 57;
  AKEYCODE_ALT_RIGHT = 58;
  AKEYCODE_SHIFT_LEFT  = 59;
  AKEYCODE_SHIFT_RIGHT = 60;
  AKEYCODE_TAB     = 61;
  AKEYCODE_SPACE   = 62;
  AKEYCODE_ENTER   = 66;
  AKEYCODE_DEL     = 67;
  AKEYCODE_PAGE_UP = 92;
  AKEYCODE_PAGE_DOWN = 93;
  AKEYCODE_ESCAPE  = 111;
  AKEYCODE_FORWARD_DEL = 112;
  AKEYCODE_MOVE_HOME   = 122;
  AKEYCODE_MOVE_END    = 123;
  AKEYCODE_INSERT      = 124;
  AKEYCODE_MENU        = 82;
  AKEYCODE_NUMPAD_ENTER = 160;

type
  TANativeWindow = record end;
  PANativeWindow = ^TANativeWindow;

  TARect = record
    Left, Top, Right, Bottom: cint32;
  end;
  PARect = ^TARect;

  { Locked window buffer. Stride is in PIXELS, not bytes. }
  TANativeWindowBuffer = record
    Width: cint32;
    Height: cint32;
    Stride: cint32;
    Format: cint32;
    Bits: Pointer;
    Reserved: array[0..5] of cuint32;
  end;
  PANativeWindowBuffer = ^TANativeWindowBuffer;

function ANativeWindow_fromSurface(env: Pointer; surface: Pointer): PANativeWindow;
  cdecl; external libandroid;
procedure ANativeWindow_acquire(window: PANativeWindow); cdecl; external libandroid;
procedure ANativeWindow_release(window: PANativeWindow); cdecl; external libandroid;
function ANativeWindow_getWidth(window: PANativeWindow): cint32; cdecl; external libandroid;
function ANativeWindow_getHeight(window: PANativeWindow): cint32; cdecl; external libandroid;
function ANativeWindow_getFormat(window: PANativeWindow): cint32; cdecl; external libandroid;
function ANativeWindow_setBuffersGeometry(window: PANativeWindow;
  width, height, format: cint32): cint32; cdecl; external libandroid;
function ANativeWindow_lock(window: PANativeWindow; buffer: PANativeWindowBuffer;
  dirtyBounds: PARect): cint32; cdecl; external libandroid;
function ANativeWindow_unlockAndPost(window: PANativeWindow): cint32; cdecl; external libandroid;

function __android_log_write(prio: cint; tag, text: PAnsiChar): cint;
  cdecl; external liblog;

{ Write one line to logcat under the 'fpGUI' tag. }
procedure AndroidLog(prio: cint; const msg: string);
{ Formatted variant. }
procedure AndroidLog(prio: cint; const fmt: string; const args: array of const);

implementation

uses
  SysUtils;

const
  FpGuiLogTag = 'fpGUI';

procedure AndroidLog(prio: cint; const msg: string);
begin
  __android_log_write(prio, FpGuiLogTag, PAnsiChar(AnsiString(msg)));
end;

procedure AndroidLog(prio: cint; const fmt: string; const args: array of const);
begin
  AndroidLog(prio, Format(fmt, args));
end;

end.
