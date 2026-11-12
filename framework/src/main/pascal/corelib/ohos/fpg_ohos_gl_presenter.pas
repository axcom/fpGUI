{
    fpGUI  -  Free Pascal GUI Toolkit

    Copyright (c) 2026 See the file AUTHORS.txt, included in this
    distribution, for details of the copyright.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      Phase 1 GL presenter.

      Keeps the existing software canvas (OH_Drawing_Bitmap or AggPas) and
      replaces only the final "put buffer to screen" step:

        CPU pixels -> GL texture -> full-screen quad -> eglSwapBuffers

      This removes the RequestBuffer/mmap/memcpy/FlushBuffer round trip and
      validates the EGLSurface / first-frame / hide-show lifecycle before
      the Phase 2 TfpgGLCanvas work.

      One presenter is kept per OHNativeWindow handle.  It is released when
      fpg_ohos reports gleDestroy (before the native window is destroyed).
}

unit fpg_ohos_gl_presenter;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  fpg_impl,
  fpg_ohos_egl,
  fpg_ohos_gl,
  fpg_ohos_gl_iface;

type
  TfpgOhosGLPresenter = class
  private
    FWindow: TfpgOhosGLWindow;
    FTexture: GLuint;
    FTexW: Integer;
    FTexH: Integer;
    FWinHandle: TfpgWinHandle;
    FAttached: Boolean;
    procedure EnsureTexture(AW, AH: Integer);
    procedure UploadTexture(AData: Pointer; AStride, AW, AH: Integer);
  public
    constructor Create;
    destructor  Destroy; override;
    function  Attach(AWinHandle: TfpgWinHandle; ABufW, ABufH: Integer): Boolean;
    function  UploadAndPresent(AData: Pointer; AStride,
      ABufW, ABufH, AWinW, AWinH: Integer;
      AFlipY, ASwizzleRB: Boolean): Boolean;
    procedure ResizeWindow(AWinW, AWinH: Integer);
    procedure Suspend;
    procedure Resume(AWinHandle: TfpgWinHandle);
    procedure ResetFirstFrame;
    procedure Detach;
  end;

{ Registry keyed by OHNativeWindow handle.  Returns nil when EGL is not
  available or the surface cannot be created; callers then fall back to the
  existing software path. }
function  GetGLPresenter(AWinHandle: TfpgWinHandle;
  ABufW, ABufH: Integer): TfpgOhosGLPresenter;
function  FindGLPresenter(AWinHandle: TfpgWinHandle): TfpgOhosGLPresenter;
procedure ReleaseGLPresenter(AWinHandle: TfpgWinHandle);
procedure ReleaseAllGLPresenters;

implementation

type
  TGLPresenterEntry = class
  public
    Handle: TfpgWinHandle;
    Presenter: TfpgOhosGLPresenter;
  end;

var
  GPresenters: TList = nil;
  GLastAttachFail: QWord = 0;

{ ── TfpgOhosGLPresenter ────────────────────────────────────────────── }

constructor TfpgOhosGLPresenter.Create;
begin
  inherited Create;
  FWindow := nil;
  FTexture := 0;
  FTexW := 0;
  FTexH := 0;
  FWinHandle := nil;
  FAttached := False;
end;

destructor TfpgOhosGLPresenter.Destroy;
begin
  Detach;
  inherited Destroy;
end;

procedure TfpgOhosGLPresenter.EnsureTexture(AW, AH: Integer);
begin
  if (AW <= 0) or (AH <= 0) then
    Exit;
  if (FTexture <> 0) and (FTexW = AW) and (FTexH = AH) then
    Exit;

  if FTexture <> 0 then
  begin
    glDeleteTextures(1, @FTexture);
    FTexture := 0;
  end;

  glGenTextures(1, @FTexture);
  if FTexture = 0 then
  begin
    GL_Log(GL_LOG_ERROR, 'glGenTextures failed');
    Exit;
  end;

  glBindTexture(GL_TEXTURE_2D, FTexture);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  if TfpgOhosGLDisplay.Instance.IsES3 then
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, AW, AH, 0,
      GL_RGBA, GL_UNSIGNED_BYTE, nil)
  else
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, AW, AH, 0,
      GL_RGBA, GL_UNSIGNED_BYTE, nil);

  FTexW := AW;
  FTexH := AH;
end;

procedure TfpgOhosGLPresenter.UploadTexture(AData: Pointer;
  AStride, AW, AH: Integer);
var
  tmp: PByte;
  y: Integer;
begin
  if (AData = nil) or (AW <= 0) or (AH <= 0) then
    Exit;

  glBindTexture(GL_TEXTURE_2D, FTexture);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

  if AStride = AW * 4 then
  begin
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, AW, AH,
      GL_RGBA, GL_UNSIGNED_BYTE, AData);
    Exit;
  end;

  if TfpgOhosGLDisplay.Instance.IsES3 then
  begin
    glPixelStorei(GL_UNPACK_ROW_LENGTH, AStride div 4);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, AW, AH,
      GL_RGBA, GL_UNSIGNED_BYTE, AData);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
    Exit;
  end;

  { ES2 has no GL_UNPACK_ROW_LENGTH: copy rows into a tight buffer. }
  tmp := GetMem(AW * AH * 4);
  if tmp = nil then
    Exit;
  try
    for y := 0 to AH - 1 do
      Move(PByte(AData)[y * AStride], tmp[y * AW * 4], AW * 4);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, AW, AH,
      GL_RGBA, GL_UNSIGNED_BYTE, tmp);
  finally
    FreeMem(tmp);
  end;
end;

function TfpgOhosGLPresenter.Attach(AWinHandle: TfpgWinHandle;
  ABufW, ABufH: Integer): Boolean;
begin
  Result := False;
  if AWinHandle = nil then
    Exit;
  if FWindow = nil then
    FWindow := TfpgOhosGLWindow.Create;
  if not FWindow.Attach(AWinHandle, ABufW, ABufH) then
    Exit;

  FWinHandle := AWinHandle;
  FAttached := True;

  if (ABufW > 0) and (ABufH > 0) and FWindow.MakeCurrent then
    EnsureTexture(ABufW, ABufH);

  Result := True;
end;

function TfpgOhosGLPresenter.UploadAndPresent(AData: Pointer; AStride,
  ABufW, ABufH, AWinW, AWinH: Integer;
  AFlipY, ASwizzleRB: Boolean): Boolean;
begin
  Result := False;
  if (AData = nil) or (ABufW <= 0) or (ABufH <= 0) then
    Exit;
  if FWindow = nil then
    Exit;
  if not FWindow.MakeCurrent then
    Exit;

  EnsureTexture(ABufW, ABufH);
  if FTexture = 0 then
    Exit;

  UploadTexture(AData, AStride, ABufW, ABufH);

  if AWinW <= 0 then
    AWinW := ABufW;
  if AWinH <= 0 then
    AWinH := ABufH;

  Result := FWindow.PresentTexture(FTexture, FTexW, FTexH,
    AWinW, AWinH, AFlipY, ASwizzleRB);
end;

procedure TfpgOhosGLPresenter.ResizeWindow(AWinW, AWinH: Integer);
begin
  if FWindow <> nil then
    FWindow.Resize(AWinW, AWinH);
end;

procedure TfpgOhosGLPresenter.Suspend;
begin
  if FWindow <> nil then
    FWindow.Suspend;
  FAttached := False;
end;

procedure TfpgOhosGLPresenter.Resume(AWinHandle: TfpgWinHandle);
begin
  if AWinHandle <> nil then
    FWinHandle := AWinHandle;
  if (FWindow <> nil) and (FWinHandle <> nil) then
    FAttached := FWindow.Attach(FWinHandle, FTexW, FTexH);
end;

procedure TfpgOhosGLPresenter.ResetFirstFrame;
begin
  if FWindow <> nil then
    FWindow.ResetFirstFrame;
end;

procedure TfpgOhosGLPresenter.Detach;
begin
  if FWindow <> nil then
  begin
    if (FTexture <> 0) and FWindow.MakeCurrent then
    begin
      glDeleteTextures(1, @FTexture);
      FTexture := 0;
    end;
    FreeAndNil(FWindow);
  end;
  FTexture := 0;
  FTexW := 0;
  FTexH := 0;
  FWinHandle := nil;
  FAttached := False;
end;

{ ── registry ───────────────────────────────────────────────────────── }

function FindEntry(AHandle: TfpgWinHandle): TGLPresenterEntry;
var
  i: Integer;
begin
  Result := nil;
  if (GPresenters = nil) or (AHandle = nil) then
    Exit;
  for i := 0 to GPresenters.Count - 1 do
    if TGLPresenterEntry(GPresenters[i]).Handle = AHandle then
      Exit(TGLPresenterEntry(GPresenters[i]));
end;

function FindGLPresenter(AWinHandle: TfpgWinHandle): TfpgOhosGLPresenter;
var
  e: TGLPresenterEntry;
begin
  e := FindEntry(AWinHandle);
  if e <> nil then
    Result := e.Presenter
  else
    Result := nil;
end;

function GetGLPresenter(AWinHandle: TfpgWinHandle;
  ABufW, ABufH: Integer): TfpgOhosGLPresenter;
var
  e: TGLPresenterEntry;
begin
  Result := nil;
  if AWinHandle = nil then
    Exit;

  e := FindEntry(AWinHandle);
  if e <> nil then
  begin
    Result := e.Presenter;
    Exit;
  end;

  if not TfpgOhosGLDisplay.Instance.TryInitialize then
    Exit;

  { Avoid retrying a failing eglCreateWindowSurface on every frame. }
  if (GLastAttachFail <> 0) and (GetTickCount64 - GLastAttachFail < 500) then
    Exit;

  e := TGLPresenterEntry.Create;
  e.Handle := AWinHandle;
  e.Presenter := TfpgOhosGLPresenter.Create;
  if not e.Presenter.Attach(AWinHandle, ABufW, ABufH) then
  begin
    GLastAttachFail := GetTickCount64;
    e.Presenter.Free;
    e.Free;
    Exit;
  end;

  GLastAttachFail := 0;
  if GPresenters = nil then
    GPresenters := TList.Create;
  GPresenters.Add(e);
  Result := e.Presenter;
end;

procedure ReleaseGLPresenter(AWinHandle: TfpgWinHandle);
var
  e: TGLPresenterEntry;
begin
  e := FindEntry(AWinHandle);
  if e = nil then
    Exit;
  GPresenters.Remove(e);
  e.Presenter.Detach;
  e.Presenter.Free;
  e.Free;
end;

procedure ReleaseAllGLPresenters;
var
  i: Integer;
  e: TGLPresenterEntry;
begin
  if GPresenters = nil then
    Exit;
  for i := GPresenters.Count - 1 downto 0 do
  begin
    e := TGLPresenterEntry(GPresenters[i]);
    e.Presenter.Detach;
    e.Presenter.Free;
    e.Free;
  end;
  GPresenters.Clear;
end;

{ ── fpg_ohos lifecycle listener ────────────────────────────────────── }

procedure PresenterWindowNotify(AWinHandle: TfpgWinHandle;
  AEvent: TGLWindowEvent; AWidth, AHeight: Integer);
var
  p: TfpgOhosGLPresenter;
begin
  case AEvent of
    gleResize:
      begin
        p := FindGLPresenter(AWinHandle);
        if p <> nil then
          p.ResizeWindow(AWidth, AHeight);
      end;
    gleShow:
      begin
        p := FindGLPresenter(AWinHandle);
        if p <> nil then
          p.Resume(AWinHandle);
      end;
    gleHide:
      ReleaseGLPresenter(AWinHandle);
    gleDestroy:
      ReleaseGLPresenter(AWinHandle);
    gleResetFirstFrame:
      begin
        p := FindGLPresenter(AWinHandle);
        if p <> nil then
          p.ResetFirstFrame;
      end;
  end;
end;

initialization
  AddGLWindowListener(@PresenterWindowNotify);

finalization
  RemoveGLWindowListener(@PresenterWindowNotify);
  ReleaseAllGLPresenters;
  FreeAndNil(GPresenters);

end.
