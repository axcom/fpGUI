{
    This file is part of the fpGUI Toolkit project.

    Copyright (c) 2026 by Graeme Geldenhuys.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      HarmonyOS specific utility function implementations.
}

{%mainunit fpg_utils.pas}

uses
  fpg_constants, fpg_stringutils, baseunix;

// HarmonyOS uses UTF-8 natively

function fpgToOSEncoding(aString: TfpgString): string;
begin
  Result := aString;
end;

function fpgFromOSEncoding(aString: string): TfpgString;
begin
  Result := aString;
end;

{ ------------------------------------------------------------------ fpgOpenURL

  HarmonyOS does not have xdg-open.  The bridge to the ArkTS / AbilityKit
  layer lives in libfp_bridge.so, which exports a Pascal-callable function
  `ohos_open_url(const url: PChar)`.  The C++ side forwards the URL to the
  JS thread and calls openLink() / startAbility() to hand it to the system.

  We resolve the symbol lazily so the rest of the toolkit keeps working if
  the bridge (or an old bridge without this symbol) is not available.
}

type
  TOHOSOpenURL = procedure(url: PChar); cdecl;

var
  _ohos_open_url: TOHOSOpenURL = nil;
  _ohos_open_url_resolved: Boolean = False;

function dlopen(__filename: PChar; __mode: Integer): Pointer; cdecl; external 'c' name 'dlopen';
function dlsym(__handle: Pointer; __name: PChar): Pointer; cdecl; external 'c' name 'dlsym';

const
  RTLD_LAZY = 1;

var
  _ohos_bridge_handle: Pointer = nil;

procedure fpgOpenURL(const aURL: TfpgString);
var
  p: Pointer;
begin
  if aURL = '' then
    Exit;

  { Resolve the bridge symbol exactly once (success or failure). }
  if not _ohos_open_url_resolved then
  begin
    _ohos_open_url_resolved := True;
    if _ohos_bridge_handle = nil then
      _ohos_bridge_handle := dlopen('libfp_bridge.so', RTLD_LAZY);
    if _ohos_bridge_handle <> nil then
    begin
      p := dlsym(_ohos_bridge_handle, 'ohos_open_url');
      if p <> nil then
        _ohos_open_url := TOHOSOpenURL(p);
    end;
  end;

  if Assigned(_ohos_open_url) then
    _ohos_open_url(PChar(aURL));
  { else: bridge symbol unavailable — nothing we can do on OHOS (no shell). }
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
