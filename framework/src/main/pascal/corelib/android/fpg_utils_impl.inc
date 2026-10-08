{
    This file is part of the fpGUI Toolkit project.

    Copyright (c) 2026 by Graeme Geldenhuys.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      Android specific utility function implementations.
}

{%mainunit fpg_utils.pas}

uses
  fpg_constants, fpg_stringutils, baseunix, jni, fpg_android_jni;

// Android uses UTF-8 natively

function fpgToOSEncoding(aString: TfpgString): string;
begin
  Result := aString;
end;

function fpgFromOSEncoding(aString: string): TfpgString;
begin
  Result := aString;
end;

{ ------------------------------------------------------------------ fpgOpenURL

  Android has no xdg-open/shell; hand the URL to the Java shell
  (FpActivity.openUrl) which starts an ACTION_VIEW intent. The JNI
  helpers are safe to call before the activity is known: the method
  lookup fails and the call becomes a no-op. }

procedure fpgOpenURL(const aURL: TfpgString);
var
  env: PJNIEnv;
  id: jmethodID;
  js: jstring;
  args: array[0..0] of jvalue;
begin
  if aURL = '' then
    Exit;
  env := AndroidGetEnv;
  if (env = nil) or (AndroidActivityRef = nil) then
    Exit;
  id := AndroidActivityMethod('openUrl', '(Ljava/lang/String;)V');
  if id = nil then
    Exit;
  js := AndroidStringToJString(env, aURL);
  if js = nil then
    Exit;
  args[0].l := js;
  env^^.CallVoidMethodA(env, AndroidActivityRef, id, @args[0]);
  env^^.DeleteLocalRef(env, js);
end;

function fpgFileSize(const AFilename: TfpgString): integer;
var
  Info: baseunix.stat;
begin
  if fpstat(PChar(AFilename), Info) = 0 then
    Result := Info.st_size
  else
    Result := -1;
end;
