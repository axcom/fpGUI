{
    fpGUI  -  Free Pascal GUI Toolkit

    Copyright (c) 2026 See the file AUTHORS.txt, included in this
    distribution, for details of the copyright.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      Thin JNI helpers shared by the Android backend and the bridge unit:
      JavaVM storage, environment attach for worker threads, string
      conversion and cached method lookups. Built on the FPC 'jni' unit
      (packages/jni) so no external dependency is needed.
}

unit fpg_android_jni;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  jni;

type
  TAndroidMethodCache = record
    ClassName: string;
    MethodName: string;
    Signature: string;
    Id: jmethodID;
  end;
  TAndroidMethodCacheArray = array of TAndroidMethodCache;

var
  { Set by AndroidRegisterNatives (JNI_OnLoad). }
  AndroidJavaVM: PJavaVM = nil;
  { Global reference to the Java view object; set by nativeInit. }
  AndroidViewRef: jobject = nil;
  { Global reference to the Activity object; set by nativeInit. }
  AndroidActivityRef: jobject = nil;
  { Classes of view/activity, as global refs (method cache owners). }
  AndroidViewClassRef: jclass = nil;
  AndroidActivityClassRef: jclass = nil;
  { Class of FpWindowView (freeform secondary windows); set on the first
    nativeWindowAttached callback. jmethodIDs are class-bound, so methods
    invoked on a window view must be looked up against this class. }
  AndroidWinViewClassRef: jclass = nil;

{ Environment for the calling thread. Attaches the thread when needed
  (Pascal worker threads are unknown to the JVM). Returns nil on failure. }
function AndroidGetEnv: PJNIEnv;

{ Java string -> UTF-8 Pascal string; '' for nil. }
function AndroidJStringToString(env: PJNIEnv; s: jstring): string;
{ UTF-8 Pascal string -> Java string (local ref; caller keeps the frame). }
function AndroidStringToJString(env: PJNIEnv; const s: string): jstring;

{ Look up a method on the view class, caching the result. }
function AndroidViewMethod(const aName, aSignature: string): jmethodID;
{ Look up a method on the activity class, caching the result. }
function AndroidActivityMethod(const aName, aSignature: string): jmethodID;
{ Look up a method on the FpWindowView class, caching the result. }
function AndroidWinViewMethod(const aName, aSignature: string): jmethodID;

{ Human-readable JNI exception check + clear (log only). }
procedure AndroidCheckException(env: PJNIEnv; const aWhere: string);

const
  FpActivityClass = 'com/fpgui/FpActivity';
  FpSurfaceViewClass = 'com/fpgui/FpSurfaceView';
  FpSubWindowClass = 'com/fpgui/FpSubWindow';

implementation

uses
  fpg_android_ndk;

var
  GViewMethodCache: TAndroidMethodCacheArray;
  GActivityMethodCache: TAndroidMethodCacheArray;
  GWinViewMethodCache: TAndroidMethodCacheArray;

function AndroidGetEnv: PJNIEnv;
var
  env: PJNIEnv;
begin
  Result := nil;
  if AndroidJavaVM = nil then
    Exit;
  env := nil;
  if AndroidJavaVM^^.GetEnv(AndroidJavaVM, @env, JNI_VERSION_1_6) = JNI_OK then
    Exit(env);
  { Not attached yet (Pascal worker thread): attach as daemon so the JVM
    does not need to wait for this thread on exit. }
  env := nil;
  if AndroidJavaVM^^.AttachCurrentThread(AndroidJavaVM, @env, nil) <> JNI_OK then
    Exit(nil);
  Result := env;
end;

function AndroidJStringToString(env: PJNIEnv; s: jstring): string;
var
  chars: PAnsiChar;
begin
  Result := '';
  if (env = nil) or (s = nil) then
    Exit;
  chars := env^^.GetStringUTFChars(env, s, nil);
  if chars = nil then
    Exit;
  try
    Result := AnsiString(chars);
  finally
    env^^.ReleaseStringUTFChars(env, s, chars);
  end;
end;

function AndroidStringToJString(env: PJNIEnv; const s: string): jstring;
begin
  Result := nil;
  if env = nil then
    Exit;
  Result := env^^.NewStringUTF(env, PAnsiChar(AnsiString(s)));
end;

procedure AndroidCheckException(env: PJNIEnv; const aWhere: string);
var
  exc: jthrowable;
begin
  if env = nil then
    Exit;
  exc := env^^.ExceptionOccurred(env);
  if exc = nil then
    Exit;
  env^^.ExceptionClear(env);
  AndroidLog(ANDROID_LOG_ERROR, 'JNI exception in ' + aWhere);
end;

function FindCachedMethod(env: PJNIEnv; aClass: jclass;
  var aCache: TAndroidMethodCacheArray; const aName, aSignature: string): jmethodID;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to High(aCache) do
    if SameText(aCache[i].MethodName, aName) and
       (aCache[i].Signature = aSignature) then
      Exit(aCache[i].Id);
  if (env = nil) or (aClass = nil) then
    Exit;
  Result := env^^.GetMethodID(env, aClass, PAnsiChar(AnsiString(aName)),
    PAnsiChar(AnsiString(aSignature)));
  if Result = nil then
  begin
    AndroidCheckException(env, 'GetMethodID ' + aName);
    AndroidLog(ANDROID_LOG_ERROR, 'JNI: method not found: ' + aName + aSignature);
    Exit;
  end;
  i := Length(aCache);
  SetLength(aCache, i + 1);
  aCache[i].MethodName := aName;
  aCache[i].Signature := aSignature;
  aCache[i].Id := Result;
end;

function AndroidViewMethod(const aName, aSignature: string): jmethodID;
begin
  Result := FindCachedMethod(AndroidGetEnv, AndroidViewClassRef,
    GViewMethodCache, aName, aSignature);
end;

function AndroidActivityMethod(const aName, aSignature: string): jmethodID;
begin
  Result := FindCachedMethod(AndroidGetEnv, AndroidActivityClassRef,
    GActivityMethodCache, aName, aSignature);
end;

function AndroidWinViewMethod(const aName, aSignature: string): jmethodID;
begin
  Result := FindCachedMethod(AndroidGetEnv, AndroidWinViewClassRef,
    GWinViewMethodCache, aName, aSignature);
end;

end.
