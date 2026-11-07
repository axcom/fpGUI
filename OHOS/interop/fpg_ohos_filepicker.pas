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
    { 旧式简化接口：SuffixFilters 为逗号分隔的后缀列表（如 '.txt,.pdf'），
      可带空格；空串=不过滤。单次最多选 1 个，filepath 为选中路径。 }
    class function OpenDocument(var filepath: string; SuffixFilters:string=''): integer; overload;
    { 同上；MaxSelectNumber=0 表示系统默认（多选）。sl 为 nil 时返回新建列表
      （调用方 Free），非 nil 时结果复制进 sl（调用方保留所有权）。 }
    class function OpenDocument(var sl: TStringList; SuffixFilters:string=''; MaxSelectNumber:integer=0): integer; overload;
    class function SaveDocument(const AOptions: TfpgDocumentSaveOptions): string;
    class function OpenPhoto(const AOptions: TfpgPhotoPickerOptions): TStringList;
    class function OpenAudio(const AOptions: TfpgAudioPickerOptions): TStringList;
  end;

implementation

uses
  SyncObjs,
  fpg_ohos,
  fpg_jsonutil;

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

  { 本单元内部使用的字符串动态数组（来自 fpg_jsonutil）}
  TPickerStringArray = TJsonStringArray;

  { C++ 独立导出符号（LibEntrySym 懒加载，与 ohos_set_modal_window 同模式）}
  TOhosShowFilePicker = procedure(reqId: Integer; pickerType: Integer;
    optsJson: PChar); cdecl;

var
  g_reqId: Integer = 0;
  g_pending: TStringList = nil;   { Names[reqId] → Objects[TFilePickerRequest] }
  g_lock: TCriticalSection = nil;
  { 文件选择器 }
  _ohos_show_file_picker: TOhosShowFilePicker = nil;

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

{ 把 "a,b,c" 形式的后缀过滤器拆成 JSON 字符串数组。
  逗号分隔，逐项 Trim 并丢弃空项；空串输出 []（不能输出 ""，
  ETS 侧按数组使用，字符串会让 fileSuffixFilters 类型不符）。
  每项都走 JsonArrayOfStrings 转义，含引号/反斜杠的后缀也不会破坏 JSON。 }
function SuffixFiltersToJson(const ASuffixFilters: string): string;
var
  parts: array of string;
  count, i, start: Integer;
  item: string;
begin
  count := 0;
  SetLength(parts, 0);
  start := 1;
  for i := 1 to Length(ASuffixFilters) + 1 do
  begin
    if (i > Length(ASuffixFilters)) or (ASuffixFilters[i] = ',') then
    begin
      item := Trim(Copy(ASuffixFilters, start, i - start));
      if item <> '' then
      begin
        SetLength(parts, count + 1);
        parts[count] := item;
        Inc(count);
      end;
      start := i + 1;
    end;
  end;
  Result := JsonArrayOfStrings(parts);
end;

{ ── TfpgOhosFilePicker ────────────────────────────────────────────────── }

class function TfpgOhosFilePicker.OpenDocument(
  const AOptions: TfpgDocumentPickerOptions): TStringList; overload;
var
  json: string;
begin
  json := '{"suffix":' + JsonArrayOfStrings(AOptions.SuffixFilters) +
          ',"max":' + IntToStr(AOptions.MaxSelectNumber) + '}';
  Result := ShowPickerSync(Ord(ptDocument), json);
end;

class function TfpgOhosFilePicker.OpenDocument(var filepath: string; SuffixFilters:string=''): integer; overload;
var 
  json: string;
  l: TStringList;
begin
  json := '{"suffix":' + SuffixFiltersToJson(SuffixFilters) + ',"max":1}';
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
  json := '{"suffix":' + SuffixFiltersToJson(SuffixFilters) +
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
          ',"suffix":' + JsonArrayOfStrings(AOptions.SuffixFilters) + '}';
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
