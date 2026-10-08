{
    fpGUI  -  Free Pascal GUI Toolkit

    Copyright (c) 2026 See the file AUTHORS.txt, included in this
    distribution, for details of the copyright.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      JNI bridge between the Java shell (FpActivity + FpSurfaceView) and the
      Pascal backend. The application library exports JNI_OnLoad which must
      call AndroidRegisterNativeMethods(vm); all other entry points are
      JNI native methods registered on com/fpgui/FpSurfaceView and invoked
      from the Java UI thread. Pascal -> Java calls (soft keyboard,
      clipboard, finish) use cached method IDs and attach the calling
      thread on demand.

      See DESIGN.zh-CN.md (Android) for the threading model.
}

unit fpg_android_bridge;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  jni,
  fpg_android,
  fpg_android_ndk,
  fpg_android_jni;

{ Register all native methods on FpSurfaceView and install the
  Pascal -> Java hooks. Call from JNI_OnLoad; returns the JNI version on
  success or JNI_ERR. }
function AndroidRegisterNativeMethods(aVM: PJavaVM): jint;

implementation

uses
  SysUtils,
  SyncObjs;

const
  FpWindowViewClass = 'com/fpgui/FpWindowView';

type
  { One freeform secondary window: global refs to its Activity and View
    (jmethodIDs are class-bound, so the view class is cached separately). }
  TAndroidWinRef = record
    Id: Integer;
    Activity: jobject;
    View: jobject;
  end;

var
  gWindowRefs: array of TAndroidWinRef;
  gWindowRefsLock: TCriticalSection = nil;

procedure BindJavaRefs(aEnv: PJNIEnv; aActivity, aView: jobject);
var
  cls: jclass;
  newRef, oldRef: jobject;
begin
  { Refs are REPLACED, not just set once: a borderless main-window re-attach
    brings a new Activity/View and backend->Java calls (presentFrame, IME,
    clipboard, ...) must target the live instance. Create the new reference
    first, then swap, then release the old one - the loop thread may read
    these globals at any time. }
  if aActivity <> nil then
  begin
    newRef := aEnv^^.NewGlobalRef(aEnv, aActivity);
    oldRef := AndroidActivityRef;
    AndroidActivityRef := newRef;
    if oldRef <> nil then
      aEnv^^.DeleteGlobalRef(aEnv, oldRef);
    if AndroidActivityClassRef = nil then
    begin
      cls := aEnv^^.GetObjectClass(aEnv, aActivity);
      if cls <> nil then
        AndroidActivityClassRef := aEnv^^.NewGlobalRef(aEnv, cls);
    end;
  end;
  if aView <> nil then
  begin
    newRef := aEnv^^.NewGlobalRef(aEnv, aView);
    oldRef := AndroidViewRef;
    AndroidViewRef := newRef;
    if oldRef <> nil then
      aEnv^^.DeleteGlobalRef(aEnv, oldRef);
    if AndroidViewClassRef = nil then
    begin
      cls := aEnv^^.GetObjectClass(aEnv, aView);
      if cls <> nil then
        AndroidViewClassRef := aEnv^^.NewGlobalRef(aEnv, cls);
    end;
  end;
end;

{ ---- Pascal -> Java hooks ---- }

procedure SetKeyboardVisible(aWindowId: Integer; aVisible: Boolean; aKbType: Integer);
var
  env: PJNIEnv;
  id: jmethodID;
  target: jobject;
  i: Integer;
  args: array[0..1] of jvalue;
begin
  if aKbType = 0 then ;   { reserved: keyboard type hints for the IME }
  env := AndroidGetEnv;
  if env = nil then
    Exit;
  if aWindowId > 0 then
    id := AndroidWinViewMethod('setKeyboardVisible', '(Z)V')
  else
    id := AndroidViewMethod('setKeyboardVisible', '(Z)V');
  if id = nil then
    Exit;
  target := AndroidViewRef;                    { main window view }
  if aWindowId > 0 then
  begin
    gWindowRefsLock.Enter;
    try
      for i := 0 to High(gWindowRefs) do
        if gWindowRefs[i].Id = aWindowId then
        begin
          target := gWindowRefs[i].View;
          Break;
        end;
    finally
      gWindowRefsLock.Leave;
    end;
  end;
  if target = nil then
    Exit;
  if aVisible then
    args[0].z := JNI_TRUE
  else
    args[0].z := JNI_FALSE;
  env^^.CallVoidMethodA(env, target, id, @args[0]);
  AndroidCheckException(env, 'setKeyboardVisible');
end;

function GetClipboardText: string;
var
  env: PJNIEnv;
  id: jmethodID;
  js: jstring;
begin
  Result := '';
  env := AndroidGetEnv;
  if env = nil then
    Exit;
  id := AndroidActivityMethod('getClipboard', '()Ljava/lang/String;');
  if id = nil then
    Exit;
  js := env^^.CallObjectMethod(env, AndroidActivityRef, id);
  Result := AndroidJStringToString(env, js);
  if js <> nil then
    env^^.DeleteLocalRef(env, js);
end;

procedure SetClipboardText(const AText: string);
var
  env: PJNIEnv;
  id: jmethodID;
  js: jstring;
  args: array[0..0] of jvalue;
begin
  env := AndroidGetEnv;
  if env = nil then
    Exit;
  id := AndroidActivityMethod('setClipboard', '(Ljava/lang/String;)V');
  if id = nil then
    Exit;
  js := AndroidStringToJString(env, AText);
  if js = nil then
    Exit;
  args[0].l := js;
  env^^.CallVoidMethodA(env, AndroidActivityRef, id, @args[0]);
  env^^.DeleteLocalRef(env, js);
end;

procedure FinishAndroidActivity;
var
  env: PJNIEnv;
  id: jmethodID;
begin
  env := AndroidGetEnv;
  if env = nil then
    Exit;
  id := AndroidActivityMethod('finishActivity', '()V');
  if id = nil then
    Exit;
  env^^.CallVoidMethod(env, AndroidActivityRef, id);
end;

{ Java Canvas presentation fallback: wraps the tightly packed ARGB pixels in
  a direct ByteBuffer and lets the view draw them with
  SurfaceHolder.lockCanvas/drawBitmap. Used when the surface buffers are not
  CPU-mappable (host-side GL emulators). The Java call is synchronous, so the
  local buffer reference is safe to delete afterwards. }
procedure PresentFrameViaJava(aPixels: Pointer; aWidth, aHeight: Integer);
var
  env: PJNIEnv;
  id: jmethodID;
  buf: jobject;
  args: array[0..2] of jvalue;
begin
  if (aPixels = nil) or (aWidth < 1) or (aHeight < 1) then
    Exit;
  env := AndroidGetEnv;
  if (env = nil) or (AndroidViewRef = nil) then
    Exit;
  id := AndroidViewMethod('presentFrame', '(Ljava/nio/ByteBuffer;II)V');
  if id = nil then
    Exit;
  buf := env^^.NewDirectByteBuffer(env, aPixels, Int64(aWidth) * Int64(aHeight) * 4);
  if buf = nil then
    Exit;
  args[0].l := buf;
  args[1].i := aWidth;
  args[2].i := aHeight;
  env^^.CallVoidMethodA(env, AndroidViewRef, id, @args[0]);
  env^^.DeleteLocalRef(env, buf);
end;

{ ---- Native methods called from Java ---- }

procedure NativeInit(aEnv: PJNIEnv; {%H-}aObj: jobject; aActivity, aView: jobject;
  aFiles, aCache, aExternal: jstring; aDensity: jfloat; aPresenter: jint;
  aSupportsFreeform: jboolean); cdecl;
begin
  BindJavaRefs(aEnv, aActivity, aView);
  AndroidSetSandboxPaths(AndroidJStringToString(aEnv, aFiles),
    AndroidJStringToString(aEnv, aCache),
    AndroidJStringToString(aEnv, aExternal));
  AndroidSetScreenMetrics(0, 0, 0, aDensity);
  { 0 = Java Canvas presenter (default), 1 = native ANativeWindow lock. }
  gAndroidUseJavaPresenter := aPresenter <> 1;
  gSupportsFreeform := aSupportsFreeform <> JNI_FALSE;
  if gAndroidUseJavaPresenter then
    AndroidLog(ANDROID_LOG_INFO, 'nativeInit done (presenter=java canvas)')
  else
    AndroidLog(ANDROID_LOG_INFO, 'nativeInit done (presenter=native window)');
  if gSupportsFreeform then
    AndroidLog(ANDROID_LOG_INFO, 'freeform window management available')
  else
    AndroidLog(ANDROID_LOG_INFO, 'freeform not available (popup fallback)');
end;

procedure NativeSurfaceCreated(aEnv: PJNIEnv; aObj: jobject; aToken: jint;
  aActivity: jobject; aSurface: jobject); cdecl;
var
  win: PANativeWindow;
begin
  { Replace the Java refs: after a borderless main-window re-attach this is
    the new Activity/View that backend->Java calls must target. }
  BindJavaRefs(aEnv, aActivity, aObj);
  win := ANativeWindow_fromSurface(aEnv, aSurface);
  AndroidSetMainSurface(aToken, win);
  { AndroidSetMainSurface acquired its own reference. }
  if win <> nil then
    ANativeWindow_release(win);
  AndroidStartApp;
end;

procedure NativeSurfaceChanged({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aToken, aWidth, aHeight: jint; aDensity: jfloat); cdecl;
begin
  AndroidSetScreenMetrics(aToken, aWidth, aHeight, aDensity);
end;

procedure NativeSurfaceDestroyed({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aToken: jint); cdecl;
begin
  AndroidDetachMainSurface(aToken);
end;

procedure NativeTouch({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aAction: jint; aX, aY: jfloat; aButton: jint); cdecl;
begin
  AndroidEnqueueTouch(aAction, aX, aY, aButton);
end;

procedure NativeHover({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aX, aY: jfloat); cdecl;
begin
  AndroidEnqueueHover(aX, aY);
end;

procedure NativeWheel({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aDelta: jint); cdecl;
begin
  AndroidEnqueueWheel(aDelta);
end;

{ ---- floating secondary windows ---- }

procedure NativeSubSurfaceCreated(aEnv: PJNIEnv; {%H-}aObj: jobject;
  aId: jint; aSurface: jobject); cdecl;
var
  win: PANativeWindow;
begin
  win := ANativeWindow_fromSurface(aEnv, aSurface);
  { The queue takes ownership of this reference. }
  AndroidAttachSubSurface(aId, win);
  if win <> nil then
    ANativeWindow_release(win);
  AndroidLog(ANDROID_LOG_INFO, Format('sub surface created: id=%d win=%p',
    [aId, Pointer(win)]));
end;

procedure NativeSubSurfaceChanged({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aId: jint; aWidth, aHeight: jint); cdecl;
begin
  AndroidLog(ANDROID_LOG_INFO, Format('sub surface changed: id=%d %dx%d',
    [aId, aWidth, aHeight]));
end;

procedure NativeSubSurfaceDestroyed({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aId: jint); cdecl;
begin
  AndroidAttachSubSurface(aId, nil);
end;

procedure NativeSubWindowDismissed({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aId: jint); cdecl;
begin
  AndroidSubWindowDismissed(aId);
end;

procedure NativeSubTouch({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aId: jint; aAction: jint; aX, aY: jfloat; aButton: jint); cdecl;
begin
  AndroidEnqueueSubTouch(aId, aAction, aX, aY, aButton);
end;

procedure NativeSubHover({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aId: jint; aX, aY: jfloat); cdecl;
begin
  AndroidEnqueueSubHover(aId, aX, aY);
end;

procedure NativeSubWheel({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aId: jint; aDelta: jint); cdecl;
begin
  AndroidEnqueueSubWheel(aId, aDelta);
end;

{ ---- Pascal -> Java hooks for floating windows ---- }

procedure CreateSubWindowViaJava(aId, aX, aY, aW, aH: Integer;
  aDismissOnOutside: Boolean; aBorderless: Boolean; aOwnerId: Integer);
var
  env: PJNIEnv;
  id: jmethodID;
  args: array[0..7] of jvalue;
begin
  env := AndroidGetEnv;
  if (env = nil) or (AndroidActivityRef = nil) then
    Exit;
  id := AndroidActivityMethod('createSubWindow', '(IIIIIZZI)V');
  if id = nil then
    Exit;
  args[0].i := aId;
  args[1].i := aX;
  args[2].i := aY;
  args[3].i := aW;
  args[4].i := aH;
  if aDismissOnOutside then
    args[5].z := JNI_TRUE
  else
    args[5].z := JNI_FALSE;
  if aBorderless then
    args[6].z := JNI_TRUE
  else
    args[6].z := JNI_FALSE;
  args[7].i := aOwnerId;
  env^^.CallVoidMethodA(env, AndroidActivityRef, id, @args[0]);
  AndroidCheckException(env, 'createSubWindow');
end;

procedure SetMainDecorationViaJava(aBorderless, aFullScreen: Boolean;
  const ATitle: string);
var
  env: PJNIEnv;
  id: jmethodID;
  js: jstring;
  args: array[0..2] of jvalue;
begin
  env := AndroidGetEnv;
  if (env = nil) or (AndroidActivityRef = nil) then
    Exit;
  id := AndroidActivityMethod('setMainDecoration', '(ZZLjava/lang/String;)V');
  if id = nil then
    Exit;
  js := AndroidStringToJString(env, ATitle);
  if aBorderless then
    args[0].z := JNI_TRUE
  else
    args[0].z := JNI_FALSE;
  if aFullScreen then
    args[1].z := JNI_TRUE
  else
    args[1].z := JNI_FALSE;
  args[2].l := js;
  env^^.CallVoidMethodA(env, AndroidActivityRef, id, @args[0]);
  if js <> nil then
    env^^.DeleteLocalRef(env, js);
  AndroidCheckException(env, 'setMainDecoration');
end;

procedure SetModalWindowViaJava(aId: Integer);
var
  env: PJNIEnv;
  id: jmethodID;
  args: array[0..0] of jvalue;
begin
  env := AndroidGetEnv;
  if (env = nil) or (AndroidActivityRef = nil) then
    Exit;
  id := AndroidActivityMethod('setModalWindow', '(I)V');
  if id = nil then
    Exit;
  args[0].i := aId;
  env^^.CallVoidMethodA(env, AndroidActivityRef, id, @args[0]);
  AndroidCheckException(env, 'setModalWindow');
end;

procedure MoveSubWindowViaJava(aId, aX, aY, aW, aH: Integer);
var
  env: PJNIEnv;
  id: jmethodID;
  args: array[0..4] of jvalue;
begin
  env := AndroidGetEnv;
  if (env = nil) or (AndroidActivityRef = nil) then
    Exit;
  id := AndroidActivityMethod('moveSubWindow', '(IIIII)V');
  if id = nil then
    Exit;
  args[0].i := aId;
  args[1].i := aX;
  args[2].i := aY;
  args[3].i := aW;
  args[4].i := aH;
  env^^.CallVoidMethodA(env, AndroidActivityRef, id, @args[0]);
end;

procedure ShowSubWindowViaJava(aId: Integer; aVisible: Boolean);
var
  env: PJNIEnv;
  id: jmethodID;
  args: array[0..1] of jvalue;
begin
  env := AndroidGetEnv;
  if (env = nil) or (AndroidActivityRef = nil) then
    Exit;
  id := AndroidActivityMethod('setSubWindowVisible', '(IZ)V');
  if id = nil then
    Exit;
  args[0].i := aId;
  if aVisible then
    args[1].z := JNI_TRUE
  else
    args[1].z := JNI_FALSE;
  env^^.CallVoidMethodA(env, AndroidActivityRef, id, @args[0]);
end;

procedure DestroySubWindowViaJava(aId: Integer);
var
  env: PJNIEnv;
  id: jmethodID;
  args: array[0..0] of jvalue;
begin
  env := AndroidGetEnv;
  if (env = nil) or (AndroidActivityRef = nil) then
    Exit;
  id := AndroidActivityMethod('destroySubWindow', '(I)V');
  if id = nil then
    Exit;
  args[0].i := aId;
  env^^.CallVoidMethodA(env, AndroidActivityRef, id, @args[0]);
end;

procedure PresentSubFrameViaJava(aId: Integer; aPixels: Pointer;
  aWidth, aHeight: Integer);
var
  env: PJNIEnv;
  id: jmethodID;
  buf: jobject;
  args: array[0..3] of jvalue;
begin
  if (aPixels = nil) or (aWidth < 1) or (aHeight < 1) then
    Exit;
  env := AndroidGetEnv;
  if (env = nil) or (AndroidActivityRef = nil) then
    Exit;
  id := AndroidActivityMethod('presentSubFrame', '(ILjava/nio/ByteBuffer;II)V');
  if id = nil then
    Exit;
  buf := env^^.NewDirectByteBuffer(env, aPixels, Int64(aWidth) * Int64(aHeight) * 4);
  if buf = nil then
    Exit;
  args[0].i := aId;
  args[1].l := buf;
  args[2].i := aWidth;
  args[3].i := aHeight;
  env^^.CallVoidMethodA(env, AndroidActivityRef, id, @args[0]);
  env^^.DeleteLocalRef(env, buf);
end;

function NativeKey({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aKeyCode: jint; aDown: jboolean; aMetaState: jint; aUnicode: jint): jboolean; cdecl;
begin
  AndroidEnqueueKey(aKeyCode, Ord(aDown = JNI_FALSE), aMetaState, LongWord(aUnicode));
  { Report handled only for keys the backend maps; everything else falls
    through to the system (volume, media, ...) and to super.onKeyDown. }
  if AndroidKeyToFpgKey(aKeyCode) <> 0 then
    Result := JNI_TRUE
  else
    Result := JNI_FALSE;
end;

procedure NativeText(aEnv: PJNIEnv; {%H-}aObj: jobject; aText: jstring); cdecl;
begin
  AndroidEnqueueText(AndroidJStringToString(aEnv, aText));
end;

procedure NativeDelete({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aBefore, aAfter: jint); cdecl;
begin
  AndroidEnqueueDelete(aBefore, aAfter);
end;

function NativeBack({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject): jboolean; cdecl;
begin
  if AndroidHandleBack then
    Result := JNI_TRUE
  else
    Result := JNI_FALSE;
end;

procedure NativeStop({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject; aToken: jint); cdecl;
begin
  AndroidLog(ANDROID_LOG_INFO, 'nativeStop token=' + IntToStr(aToken));
  { Ignore the destroy of a superseded main-window instance (borderless
    re-attach): the Pascal application must keep running. }
  if AndroidIsCurrentMainToken(aToken) then
    AndroidRequestStop;
end;

{ ---- Freeform secondary-window natives (FpWindowView class) ---------- }

procedure NativeWindowAttached(aEnv: PJNIEnv; {%H-}aObj: jobject;
  aId: jint; aActivity, aView: jobject); cdecl;
var
  cls: jclass;
begin
  if (aEnv = nil) or (aView = nil) then
    Exit;
  { Cache the FpWindowView class once (method lookups are class-bound). }
  if AndroidWinViewClassRef = nil then
  begin
    cls := aEnv^^.GetObjectClass(aEnv, aView);
    if cls <> nil then
      AndroidWinViewClassRef := aEnv^^.NewGlobalRef(aEnv, cls);
  end;
  gWindowRefsLock.Enter;
  try
    SetLength(gWindowRefs, Length(gWindowRefs) + 1);
    with gWindowRefs[High(gWindowRefs)] do
    begin
      Id := aId;
      Activity := aEnv^^.NewGlobalRef(aEnv, aActivity);
      View := aEnv^^.NewGlobalRef(aEnv, aView);
    end;
  finally
    gWindowRefsLock.Leave;
  end;
  AndroidLog(ANDROID_LOG_INFO, Format('window attached: id=%d', [aId]));
  { The Pascal side may have painted before this Activity existed; ask for
    a repaint so the first frame is not lost. }
  AndroidEnqueueWindowRepaint(aId);
end;

procedure NativeSubWindowAttached({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aId: jint); cdecl;
begin
  { PopupWindow fallback path: the view is attached, request a repaint. }
  AndroidEnqueueWindowRepaint(aId);
end;

procedure NativeWindowClosed(aEnv: PJNIEnv; {%H-}aObj: jobject; aId: jint); cdecl;
var
  i: Integer;
begin
  gWindowRefsLock.Enter;
  try
    for i := 0 to High(gWindowRefs) do
      if gWindowRefs[i].Id = aId then
      begin
        if gWindowRefs[i].Activity <> nil then
          aEnv^^.DeleteGlobalRef(aEnv, gWindowRefs[i].Activity);
        if gWindowRefs[i].View <> nil then
          aEnv^^.DeleteGlobalRef(aEnv, gWindowRefs[i].View);
        gWindowRefs[i] := gWindowRefs[High(gWindowRefs)];
        SetLength(gWindowRefs, Length(gWindowRefs) - 1);
        Break;
      end;
  finally
    gWindowRefsLock.Leave;
  end;
  AndroidEnqueueWindowClosed(aId);
end;

procedure NativeWindowBoundsChanged({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aId, aX, aY, aW, aH: jint); cdecl;
begin
  AndroidEnqueueWindowBounds(aId, aX, aY, aW, aH);
end;

procedure NativeWindowFocused({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject; aId: jint); cdecl;
begin
  AndroidEnqueueWindowFocused(aId);
end;

procedure NativeWindowTouch({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aId, aAction: jint; aX, aY: jfloat; aButton: jint); cdecl;
begin
  AndroidEnqueueSubTouch(aId, aAction, aX, aY, aButton);
end;

procedure NativeWindowHover({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aId: jint; aX, aY: jfloat); cdecl;
begin
  AndroidEnqueueSubHover(aId, aX, aY);
end;

procedure NativeWindowWheel({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aId, aDelta: jint); cdecl;
begin
  AndroidEnqueueSubWheel(aId, aDelta);
end;

procedure NativeWindowText(aEnv: PJNIEnv; {%H-}aObj: jobject;
  aId: jint; aText: jstring); cdecl;
begin
  AndroidEnqueueSubText(aId, AndroidJStringToString(aEnv, aText));
end;

function NativeWindowKey({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aId, aKeyCode: jint; aDown: jboolean; aMetaState, aUnicode: jint): jboolean; cdecl;
begin
  AndroidEnqueueSubKey(aId, aKeyCode, Ord(aDown = JNI_FALSE), aMetaState,
    LongWord(aUnicode));
  Result := JNI_TRUE;
end;

procedure NativeWindowDelete({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject;
  aId, aBefore, aAfter: jint); cdecl;
begin
  AndroidEnqueueSubDelete(aId, aBefore, aAfter);
end;

function NativeWindowBack({%H-}aEnv: PJNIEnv; {%H-}aObj: jobject; aId: jint): jboolean; cdecl;
begin
  { Let the Pascal side close the window/menu chain (it destroys the window,
    which finishes this Activity). }
  AndroidEnqueueWindowClosed(aId);
  Result := JNI_TRUE;
end;

const
  NativeMethods: array[0..11] of JNINativeMethod = (
    (name: 'nativeInit';
     signature: '(Landroid/app/Activity;Landroid/view/View;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;FIZ)V';
     fnPtr: @NativeInit),
    (name: 'nativeSurfaceCreated';
     signature: '(ILandroid/app/Activity;Landroid/view/Surface;)V';
     fnPtr: @NativeSurfaceCreated),
    (name: 'nativeSurfaceChanged';
     signature: '(IIIF)V';
     fnPtr: @NativeSurfaceChanged),
    (name: 'nativeSurfaceDestroyed';
     signature: '(I)V';
     fnPtr: @NativeSurfaceDestroyed),
    (name: 'nativeTouch';
     signature: '(IFFI)V';
     fnPtr: @NativeTouch),
    (name: 'nativeHover';
     signature: '(FF)V';
     fnPtr: @NativeHover),
    (name: 'nativeWheel';
     signature: '(I)V';
     fnPtr: @NativeWheel),
    (name: 'nativeKey';
     signature: '(IZII)Z';
     fnPtr: @NativeKey),
    (name: 'nativeText';
     signature: '(Ljava/lang/String;)V';
     fnPtr: @NativeText),
    (name: 'nativeDelete';
     signature: '(II)V';
     fnPtr: @NativeDelete),
    (name: 'nativeBack';
     signature: '()Z';
     fnPtr: @NativeBack),
    (name: 'nativeStop';
     signature: '(I)V';
     fnPtr: @NativeStop)
  );

  { Floating-window natives are declared (as static methods) on the
    FpSubWindow class. The window uses a plain View (Java canvas
    presentation), so there are no surface callbacks. }
  SubNativeMethods: array[0..4] of JNINativeMethod = (
    (name: 'nativeSubWindowAttached';
     signature: '(I)V';
     fnPtr: @NativeSubWindowAttached),
    (name: 'nativeSubWindowDismissed';
     signature: '(I)V';
     fnPtr: @NativeSubWindowDismissed),
    (name: 'nativeSubTouch';
     signature: '(IIFFI)V';
     fnPtr: @NativeSubTouch),
    (name: 'nativeSubHover';
     signature: '(IFF)V';
     fnPtr: @NativeSubHover),
    (name: 'nativeSubWheel';
     signature: '(II)V';
     fnPtr: @NativeSubWheel)
  );

  { Freeform window natives live on FpWindowView. }
  WindowNativeMethods: array[0..10] of JNINativeMethod = (
    (name: 'nativeWindowAttached';
     signature: '(ILcom/fpgui/FpActivity;Lcom/fpgui/FpWindowView;)V';
     fnPtr: @NativeWindowAttached),
    (name: 'nativeWindowTouch';
     signature: '(IIFFI)V';
     fnPtr: @NativeWindowTouch),
    (name: 'nativeWindowHover';
     signature: '(IFF)V';
     fnPtr: @NativeWindowHover),
    (name: 'nativeWindowWheel';
     signature: '(II)V';
     fnPtr: @NativeWindowWheel),
    (name: 'nativeWindowText';
     signature: '(ILjava/lang/String;)V';
     fnPtr: @NativeWindowText),
    (name: 'nativeWindowKey';
     signature: '(IIZII)Z';
     fnPtr: @NativeWindowKey),
    (name: 'nativeWindowDelete';
     signature: '(III)V';
     fnPtr: @NativeWindowDelete),
    (name: 'nativeWindowBack';
     signature: '(I)Z';
     fnPtr: @NativeWindowBack),
    (name: 'nativeWindowBoundsChanged';
     signature: '(IIIII)V';
     fnPtr: @NativeWindowBoundsChanged),
    (name: 'nativeWindowClosed';
     signature: '(I)V';
     fnPtr: @NativeWindowClosed),
    (name: 'nativeWindowFocused';
     signature: '(I)V';
     fnPtr: @NativeWindowFocused)
  );

function AndroidRegisterNativeMethods(aVM: PJavaVM): jint;
var
  env: PJNIEnv;
  cls: jclass;
begin
  Result := JNI_ERR;
  env := nil;
  if aVM^^.GetEnv(aVM, @env, JNI_VERSION_1_6) <> JNI_OK then
  begin
    AndroidLog(ANDROID_LOG_ERROR, 'AndroidRegisterNativeMethods: GetEnv failed');
    Exit;
  end;
  AndroidJavaVM := aVM;

  { Install the Pascal -> Java hooks. }
  AndroidShowKeyboardProc := @SetKeyboardVisible;
  AndroidClipboardGetProc := @GetClipboardText;
  AndroidClipboardSetProc := @SetClipboardText;
  AndroidFinishProc := @FinishAndroidActivity;
  AndroidPresentFrameProc := @PresentFrameViaJava;
  AndroidCreateSubWindowProc := @CreateSubWindowViaJava;
  AndroidMoveSubWindowProc := @MoveSubWindowViaJava;
  AndroidShowSubWindowProc := @ShowSubWindowViaJava;
  AndroidDestroySubWindowProc := @DestroySubWindowViaJava;
  AndroidPresentSubFrameProc := @PresentSubFrameViaJava;
  AndroidSetModalWindowProc := @SetModalWindowViaJava;
  AndroidSetMainDecorationProc := @SetMainDecorationViaJava;

  cls := env^^.FindClass(env, FpSurfaceViewClass);
  if cls = nil then
  begin
    AndroidCheckException(env, 'FindClass ' + FpSurfaceViewClass);
    AndroidLog(ANDROID_LOG_ERROR, 'AndroidRegisterNativeMethods: class not found: ' + FpSurfaceViewClass);
    Exit;
  end;
  if env^^.RegisterNatives(env, cls, @NativeMethods[0], Length(NativeMethods)) <> JNI_OK then
  begin
    AndroidCheckException(env, 'RegisterNatives');
    AndroidLog(ANDROID_LOG_ERROR, 'AndroidRegisterNativeMethods: RegisterNatives failed');
    Exit;
  end;

  { Floating-window natives live on FpSubWindow. }
  cls := env^^.FindClass(env, FpSubWindowClass);
  if cls = nil then
  begin
    AndroidCheckException(env, 'FindClass ' + FpSubWindowClass);
    AndroidLog(ANDROID_LOG_ERROR, 'AndroidRegisterNativeMethods: class not found: ' + FpSubWindowClass);
    Exit;
  end;
  if env^^.RegisterNatives(env, cls, @SubNativeMethods[0], Length(SubNativeMethods)) <> JNI_OK then
  begin
    AndroidCheckException(env, 'RegisterNatives FpSubWindow');
    AndroidLog(ANDROID_LOG_ERROR, 'AndroidRegisterNativeMethods: FpSubWindow RegisterNatives failed');
    Exit;
  end;

  { Freeform-window natives live on FpWindowView. }
  cls := env^^.FindClass(env, FpWindowViewClass);
  if cls = nil then
  begin
    AndroidCheckException(env, 'FindClass ' + FpWindowViewClass);
    AndroidLog(ANDROID_LOG_ERROR, 'AndroidRegisterNativeMethods: class not found: ' + FpWindowViewClass);
    Exit;
  end;
  if env^^.RegisterNatives(env, cls, @WindowNativeMethods[0], Length(WindowNativeMethods)) <> JNI_OK then
  begin
    AndroidCheckException(env, 'RegisterNatives FpWindowView');
    AndroidLog(ANDROID_LOG_ERROR, 'AndroidRegisterNativeMethods: FpWindowView RegisterNatives failed');
    Exit;
  end;

  AndroidLog(ANDROID_LOG_INFO, 'native methods registered');
  Result := JNI_VERSION_1_6;
end;

initialization
  gWindowRefsLock := TCriticalSection.Create;

finalization
  FreeAndNil(gWindowRefsLock);

end.
