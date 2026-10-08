{
    This unit is part of the fpGUI Toolkit project.

    Description:
      HarmonyOS 系统文件选择器桥（Pascal 侧）。
      经 C++ 桥（ohos_show_file_picker / notifyFilePickerResult）拉起系统
      FileManager / Gallery / 音频选择器，无需申请权限。覆盖三类选择器：
        ptDocument → DocumentViewPicker（文档/通用文件）
        ptPhoto    → PhotoViewPicker（图片/视频）
        ptAudio    → AudioViewPicker（音频）

      链路：
        TfpgOhosFilePicker.OpenXxx（同步阻塞 TEvent）
          → C++ ohos_show_file_picker(reqId,type,optsJson)
          → ETS FpgFilePicker.showFilePicker（系统选择器）
          → fpbridge.notifyFilePickerResult（reqId，uris 数组 + code）
          → C++ → FilePickerResultCallback（JS 线程，仅拷贝+SetEvent）
          → 主线程唤醒，返回 URI 列表。

      解耦：本单元单向 uses fpg_ohos；框架单元不引用本单元。
      结果回调在 initialization 注入
      （fpg_ohos 初始化早于本单元，故走实时补注）。

      返回 URI 为只读临时权限，应用退出后失效；如需持久化由应用层
      自行 fileIo.persistPermission。官方警告：不要在回调中立即打开 URI。
}

unit fpg_ohos_filepicker;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { Picker 类型（与 C++/ETS PickerType 一致）}
  TfpgPickerType = (
    ptDocument,     { 0: 文档/通用文件 DocumentViewPicker }
    ptPhoto,        { 1: 图片/视频 PhotoViewPicker }
    ptAudio,        { 2: 音频 AudioViewPicker }
    ptDocumentSave  { 3: 文档"另存为" DocumentViewPicker.save }
  );

  { 文档选择选项 }
  TfpgDocumentPickerOptions = record
    SuffixFilters: array of string;  { 如 ['.txt', '.pdf']；空=不过滤 }
    MaxSelectNumber: Integer;        { 0=系统默认 }
  end;

  { 文档"另存为"选项 }
  TfpgDocumentSaveOptions = record
    SuggestedFileName: string;        { 预填文件名（含后缀，如 'ESC.INF'）；空=由用户输入 }
    SuffixFilters: array of string;   { 允许的后缀，如 ['.txt']；空=不限制 }
  end;

  { 图片/视频选择选项 }
  TfpgPhotoPickerOptions = record
    MimeType: string;                { 'image' | 'video' | 'image_video'；空=image_video }
    MaxSelectNumber: Integer;
  end;

  { 音频选择选项 }
  TfpgAudioPickerOptions = record
    MaxSelectNumber: Integer;
  end;

  { 系统文件选择器（同步阻塞 API；fpGUI 主线程调用）。
    返回值为新建 TStringList（调用方负责 Free）；用户取消/出错/超时返回空列表。 }
  TfpgOhosFilePicker = class
  public
    class function OpenDocument(const AOptions: TfpgDocumentPickerOptions): TStringList; overload;
    class function OpenDocument(var filepath: string; SuffixFilters:string=''): integer; overload;
    class function OpenDocument(var sl: TStringList; SuffixFilters:string=''; MaxSelectNumber:integer=0): integer; overload;
    class function SaveDocument(const AOptions: TfpgDocumentSaveOptions): string;
    class function OpenPhoto(const AOptions: TfpgPhotoPickerOptions): TStringList;
    class function OpenAudio(const AOptions: TfpgAudioPickerOptions): TStringList;
  end;

implementation

uses
  SyncObjs,
  fpg_ohos;

const
  { 等待 ETS 结果的超时（ms）。系统选择器为模态 UI，给足用户操作时间；
    超时后挂起请求自动摘除，迟到的回传按 reqId 查不到会被安全丢弃。 }
  PICKER_TIMEOUT_MS = 120000;

type
  { 挂起的选择请求（reqId → 请求对象映射，支持并发多个选择器）}
  TFilePickerRequest = class
    Done: TEvent;         { 自动复位事件：结果到达时 SetEvent 唤醒主线程 }
    ResultJson: string;   { ETS 回传 JSON（uris 数组 + code 字段）}
  end;

  { 本单元内部使用的字符串动态数组（避免依赖 Classes.TStringDynArray 可见性）}
  TPickerStringArray = array of string;

  { C++ 独立导出符号（LibEntrySym 懒加载，与 ohos_set_modal_window 同模式）}
  TOhosShowFilePicker = procedure(reqId: Integer; pickerType: Integer;
    optsJson: PChar); cdecl;

var
  g_reqId: Integer = 0;
  g_pending: TStringList = nil;   { Names[reqId] → Objects[TFilePickerRequest] }
  g_lock: TCriticalSection = nil;
  { 文件选择器 }
  _ohos_show_file_picker: TOhosShowFilePicker = nil;

{ ── 极简 JSON 辅助（固定 schema，避免引入 fpjson 依赖）────────────────── }

function JsonEscape(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    case S[i] of
      '"':  Result := Result + '\"';
      '\':  Result := Result + '\\';
      #10:  Result := Result + '\n';
      #13:  Result := Result + '\r';
      #9:   Result := Result + '\t';
      #0..#8, #11, #12, #14..#31:
        Result := Result + '\u' + IntToHex(Ord(S[i]), 4);
    else
      Result := Result + S[i];
    end;
end;

function JsonQuote(const S: string): string;
begin
  Result := '"' + JsonEscape(S) + '"';
end;

function StringArrayToJsonArray(const A: array of string): string;
var
  i: Integer;
begin
  Result := '[';
  for i := Low(A) to High(A) do
  begin
    if i > Low(A) then Result := Result + ',';
    Result := Result + JsonQuote(A[i]);
  end;
  Result := Result + ']';
end;

function CodePointToUtf8(cp: UInt32): string;
begin
  Result := '';
  if cp < $80 then
    Result := Chr(cp)
  else if cp < $800 then
    Result := Chr($C0 or (cp shr 6)) + Chr($80 or (cp and $3F))
  else if cp < $10000 then
    Result := Chr($E0 or (cp shr 12)) +
              Chr($80 or ((cp shr 6) and $3F)) +
              Chr($80 or (cp and $3F))
  else
    Result := Chr($F0 or (cp shr 18)) +
              Chr($80 or ((cp shr 12) and $3F)) +
              Chr($80 or ((cp shr 6) and $3F)) +
              Chr($80 or (cp and $3F));
end;

{ 解析 JSON 字符串字面量（S[pos] 必须为开引号），返回值并把 pos 移到闭引号后 }
function ParseJsonString(const S: string; var pos: Integer): string;
var
  v, hi, lo: LongWord;
begin
  Result := '';
  if (pos > Length(S)) or (S[pos] <> '"') then Exit;
  Inc(pos);
  while pos <= Length(S) do
  begin
    if S[pos] = '"' then
    begin
      Inc(pos);
      Exit;
    end;
    if S[pos] = '\' then
    begin
      Inc(pos);
      if pos > Length(S) then Break;
      case S[pos] of
        '"':  Result := Result + '"';
        '\':  Result := Result + '\';
        '/':  Result := Result + '/';
        'n':  Result := Result + #10;
        'r':  Result := Result + #13;
        't':  Result := Result + #9;
        'b':  Result := Result + #8;
        'f':  Result := Result + #12;
        'u':
          begin
            if pos + 4 <= Length(S) then
            begin
              v := StrToInt64Def('$' + Copy(S, pos + 1, 4), 0);
              Inc(pos, 4);
              { UTF-16 代理对：此时 pos 指向首个 \uXXXX 的末位十六进制字符，
                第二个转义符 '\' 位于 pos+1，'u' 位于 pos+2，低代理 4 位在 pos+3 }
              if (v >= $D800) and (v <= $DBFF) and (pos + 6 <= Length(S)) and
                 (Copy(S, pos + 1, 2) = '\u') then
              begin
                lo := StrToInt64Def('$' + Copy(S, pos + 3, 4), 0);
                if (lo >= $DC00) and (lo <= $DFFF) then
                begin
                  Inc(pos, 6);
                  hi := $10000 + ((v - $D800) shl 10) + (lo - $DC00);
                  Result := Result + CodePointToUtf8(hi);
                end
                else
                  Result := Result + CodePointToUtf8(v);
              end
              else
                Result := Result + CodePointToUtf8(v);
            end;
          end;
      end;
      Inc(pos);
    end
    else
    begin
      Result := Result + S[pos];
      Inc(pos);
    end;
  end;
end;

{ 定位 "key" 后冒号后的位置（跳过空白）；找不到返回 -1 }
function FindJsonValue(const AJson, AKey: string; var outPos: Integer): Boolean;
var
  i, p, e: Integer;
begin
  Result := False;
  outPos := -1;
  i := 1;
  while i <= Length(AJson) do
  begin
    if AJson[i] = '"' then
    begin
      p := i + 1;
      e := p;
      while (e <= Length(AJson)) and (AJson[e] <> '"') do
      begin
        if AJson[e] = '\' then Inc(e, 2) else Inc(e);
      end;
      if (e - p = Length(AKey)) and (Copy(AJson, p, e - p) = AKey) then
      begin
        i := e + 1;
        while (i <= Length(AJson)) and (AJson[i] in [' ', #9, #10, #13]) do Inc(i);
        if (i <= Length(AJson)) and (AJson[i] = ':') then
        begin
          Inc(i);
          while (i <= Length(AJson)) and (AJson[i] in [' ', #9, #10, #13]) do Inc(i);
          outPos := i;
          Exit(True);
        end;
      end;
      i := e + 1;
    end
    else
      Inc(i);
  end;
end;

function JsonGetInt(const AJson, AKey: string): Integer;
var
  pos: Integer;
  s: string;
begin
  Result := 0;
  if not FindJsonValue(AJson, AKey, pos) then Exit;
  s := '';
  if (pos <= Length(AJson)) and (AJson[pos] = '-') then
  begin
    s := '-';
    Inc(pos);
  end;
  while (pos <= Length(AJson)) and (AJson[pos] in ['0'..'9']) do
  begin
    s := s + AJson[pos];
    Inc(pos);
  end;
  if s <> '' then Result := StrToIntDef(s, 0);
end;

function JsonGetStringArray(const AJson, AKey: string): TPickerStringArray;
var
  pos: Integer;
  list: TStringList;
begin
  Result := nil;
  if not FindJsonValue(AJson, AKey, pos) then Exit;
  if (pos > Length(AJson)) or (AJson[pos] <> '[') then Exit;
  Inc(pos);
  list := TStringList.Create;
  try
    while pos <= Length(AJson) do
    begin
      while (pos <= Length(AJson)) and (AJson[pos] in [' ', #9, #10, #13, ',']) do Inc(pos);
      if AJson[pos] = ']' then Break;
      if AJson[pos] = '"' then
        list.Add(ParseJsonString(AJson, pos))
      else
        Inc(pos);  { 跳过非预期字符 }
    end;
    SetLength(Result, list.Count);
    for pos := 0 to list.Count - 1 do
      Result[pos] := list[pos];
  finally
    list.Free;
  end;
end;

{ ── 结果回调（C++ 在 JS/ETS 线程调用）────────────────────────────────────
  安全约定（与主线程超时/释放的竞态防护）：
  对 req 的全部访问（写 ResultJson + SetEvent）都在 g_lock 内完成并先从
  g_pending 摘除；主线程在 WaitFor 返回后必须先获取 g_lock 再读 ResultJson，
  并在 finally 持锁摘除后才释放 req。回调出锁后不再触碰 req，故无 UAF。 }
procedure FilePickerResultCallback(reqId: Integer; resultJson: PChar); cdecl;
var
  req: TFilePickerRequest;
  idx: Integer;
  s: string;
begin
  s := '';
  if resultJson <> nil then s := resultJson;   { 立即拷贝：C++ 串仅本次调用有效 }
  req := nil;
  g_lock.Enter;
  try
    idx := g_pending.IndexOf(IntToStr(reqId));
    if idx >= 0 then
    begin
      req := TFilePickerRequest(g_pending.Objects[idx]);
      req.ResultJson := s;
      g_pending.Delete(idx);
      req.Done.SetEvent;
    end;
  finally
    g_lock.Leave;
  end;
end;

{ 通用同步发起：登记挂起 → C++ 发令 → 等事件 → 解析 JSON }
function ShowPickerSync(APickerType: Integer; const AOptsJson: string): TStringList;
var
  reqId, idx, code, i: Integer;
  req: TFilePickerRequest;
  uris: TPickerStringArray;
  wres: TWaitResult;
  json: string;
begin
  Result := TStringList.Create;

  g_lock.Enter;
  try
    Inc(g_reqId);
    reqId := g_reqId;
  finally
    g_lock.Leave;
  end;

  req := TFilePickerRequest.Create;
  req.Done := TEvent.Create(nil, False, False, '');
  g_lock.Enter;
  try
    g_pending.AddObject(IntToStr(reqId), req);
  finally
    g_lock.Leave;
  end;

  try
    if not Assigned(_ohos_show_file_picker) then
      Pointer(_ohos_show_file_picker) := LibBridgeSym('ohos_show_file_picker');
    if not Assigned(_ohos_show_file_picker) then Exit;

    _ohos_show_file_picker(reqId, APickerType, PChar(AOptsJson));

    wres := req.Done.WaitFor(PICKER_TIMEOUT_MS);

    { 与回调的 happens-before：回调在 SetEvent 前持同一把锁完成写入 }
    g_lock.Enter;
    try
      json := req.ResultJson;
    finally
      g_lock.Leave;
    end;

    if wres <> wrSignaled then Exit;  { 超时：finally 中摘除并释放，迟到回传安全丢弃 }

    code := JsonGetInt(json, 'code');
    if code <> 0 then Exit;           { -1=用户取消 -2=错误：返回空列表 }

    uris := JsonGetStringArray(json, 'uris');
    for i := 0 to High(uris) do
      Result.Add(uris[i]);
  finally
    g_lock.Enter;
    try
      idx := g_pending.IndexOf(IntToStr(reqId));
      if idx >= 0 then g_pending.Delete(idx);
    finally
      g_lock.Leave;
    end;
    req.Done.Free;
    req.Free;
  end;
end;

{ ── TfpgOhosFilePicker ────────────────────────────────────────────────── }

class function TfpgOhosFilePicker.OpenDocument(
  const AOptions: TfpgDocumentPickerOptions): TStringList; overload;
var
  json: string;
begin
  json := '{"suffix":' + StringArrayToJsonArray(AOptions.SuffixFilters) +
          ',"max":' + IntToStr(AOptions.MaxSelectNumber) + '}';
  Result := ShowPickerSync(Ord(ptDocument), json);
end;

class function TfpgOhosFilePicker.OpenDocument(var filepath: string; SuffixFilters:string=''): integer; overload;
var 
  json: string;
  l: TStringList;
begin
  json := '{"suffix":' + '"'+StringReplace(SuffixFilters,',','","',[rfReplaceAll]) +'","max": 1}';
  l := ShowPickerSync(Ord(ptDocument), json);
  result := l.Count;
  filepath := trim(l.Text);
  l.Free;
end;

class function TfpgOhosFilePicker.OpenDocument(var sl: TStringList; SuffixFilters:string=''; MaxSelectNumber:integer=0): integer; overload;
var 
  json: string;
  l: TStringList;
begin
  json := '{"suffix":' + '"'+StringReplace(SuffixFilters,',','","',[rfReplaceAll]) +'"'+
          ',"max":' + IntToStr(MaxSelectNumber) + '}';
  l := ShowPickerSync(Ord(ptDocument), json);
  result := l.Count;
  if assigned(sl) then 
  begin 
    sl.Assign(l);
    l.free;
  end else
  begin
    sl := l;
  end;
end;

class function TfpgOhosFilePicker.SaveDocument(
  const AOptions: TfpgDocumentSaveOptions): string;
var
  list: TStringList;
  json: string;
begin
  Result := '';
  { ETS 端：name→DocumentSaveOptions.newFileNames（预填，用户可改），
    suffix→fileSuffixFilters；save() 仅回传一个可写 URI }
  json := '{"name":' + JsonQuote(AOptions.SuggestedFileName) +
          ',"suffix":' + StringArrayToJsonArray(AOptions.SuffixFilters) + '}';
  list := ShowPickerSync(Ord(ptDocumentSave), json);
  try
    if list.Count > 0 then Result := list[0];
  finally
    list.Free;
  end;
end;

class function TfpgOhosFilePicker.OpenPhoto(
  const AOptions: TfpgPhotoPickerOptions): TStringList;
var
  json, mime: string;
begin
  mime := AOptions.MimeType;
  if mime = '' then mime := 'image_video';
  json := '{"mime":' + JsonQuote(mime) +
          ',"max":' + IntToStr(AOptions.MaxSelectNumber) + '}';
  Result := ShowPickerSync(Ord(ptPhoto), json);
end;

class function TfpgOhosFilePicker.OpenAudio(
  const AOptions: TfpgAudioPickerOptions): TStringList;
var
  json: string;
begin
  json := '{"max":' + IntToStr(AOptions.MaxSelectNumber) + '}';
  Result := ShowPickerSync(Ord(ptAudio), json);
end;

initialization
  { fpg_ohos.initialization（ohos_bridge_connect）先于本单元执行，
    桥已连接：注册过程立即把回调指针补注到 C++ g_pascal 槽位。 }
  pascalApi.file_picker_result       := @FilePickerResultCallback;
  if gBridgeInitialized then ohos_bridge_connect;

  g_lock := TCriticalSection.Create;
  g_pending := TStringList.Create;

finalization
  FreeAndNil(g_pending);
  FreeAndNil(g_lock);

end.
