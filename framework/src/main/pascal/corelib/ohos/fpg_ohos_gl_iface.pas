{
    fpGUI  -  Free Pascal GUI Toolkit

    Copyright (c) 2026 See the file AUTHORS.txt, included in this
    distribution, for details of the copyright.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      Small interface unit between the OHOS platform backend (fpg_ohos) and
      the optional GL presentation layer.

      fpg_ohos must not depend on the GL implementation units (that would
      create a circular unit reference: the GL presenter needs fpg_base and
      fpg_impl, and fpg_ohos is the platform backend).  This unit carries the
      event callback slots only.  fpg_ohos calls NotifyGLWindow() when a
      native window is resized, shown, hidden or destroyed; the presenter
      registers a listener at unit initialization.
}

unit fpg_ohos_gl_iface;

{$mode objfpc}{$H+}

interface

uses
  fpg_impl;

type
  { Lifecycle events forwarded from TfpgOhosWindow. }
  TGLWindowEvent = (
    gleResize,
    gleShow,
    gleHide,
    gleDestroy,
    gleResetFirstFrame
  );

  TGLWindowNotify = procedure(AWinHandle: TfpgWinHandle;
    AEvent: TGLWindowEvent; AWidth, AHeight: Integer);

var
  { Called by the GL window after the first successful eglSwapBuffers().
    fpg_ohos assigns this to its internal _notify_first_frame wrapper. }
  GLNotifyFirstFrame: procedure(AWinHandle: TfpgWinHandle) = nil;

  { Called by the application message pump after delivering paint messages:
    presents every GL window whose FBO changed since the last flush (VSync
    commit coalescing).  fpg_ohos_gl_canvas installs this. }
  GLFlushPresents: procedure = nil;

procedure AddGLWindowListener(ANotify: TGLWindowNotify);
procedure RemoveGLWindowListener(ANotify: TGLWindowNotify);
procedure NotifyGLWindow(AWinHandle: TfpgWinHandle; AEvent: TGLWindowEvent;
  AWidth, AHeight: Integer);

implementation

var
  FListeners: array of TGLWindowNotify;

procedure AddGLWindowListener(ANotify: TGLWindowNotify);
var
  i: Integer;
begin
  if not Assigned(ANotify) then
    Exit;
  for i := 0 to High(FListeners) do
    if FListeners[i] = ANotify then
      Exit;
  SetLength(FListeners, Length(FListeners) + 1);
  FListeners[High(FListeners)] := ANotify;
end;

procedure RemoveGLWindowListener(ANotify: TGLWindowNotify);
var
  i, j: Integer;
begin
  for i := 0 to High(FListeners) do
  begin
    if FListeners[i] = ANotify then
    begin
      for j := i to High(FListeners) - 1 do
        FListeners[j] := FListeners[j + 1];
      SetLength(FListeners, Length(FListeners) - 1);
      Exit;
    end;
  end;
end;

procedure NotifyGLWindow(AWinHandle: TfpgWinHandle; AEvent: TGLWindowEvent;
  AWidth, AHeight: Integer);
var
  i: Integer;
  list: array of TGLWindowNotify;
begin
  if Length(FListeners) = 0 then
    Exit;
  { Copy first: a listener may add/remove listeners (e.g. destroy). }
  list := FListeners;
  for i := 0 to High(list) do
    if Assigned(list[i]) then
      list[i](AWinHandle, AEvent, AWidth, AHeight);
end;

finalization
  SetLength(FListeners, 0);

end.
