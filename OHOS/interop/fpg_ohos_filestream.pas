{
  ===========================================================================
  fpg_ohos_filestream.pas — OHOS 系统文件流（file:// URI 随机读写代理）

  背景：
    系统文件选择器（fpg_ohos_filepicker）返回的是 file://docs/... 形式的
    授权 URI，位于应用沙箱之外，POSIX open 无法直接访问；必须经 ETS
    @kit.CoreFileKit fs.*Sync（文件管理服务代理）读写，URI 携带临时授权。

  本单元提供全功能 TStream 代理：
    TOhosFileStream（TStream 派生）
      - 构造：Create(URI, Mode)，Mode 兼容 FPC TFileStream：
          fmOpenRead / fmOpenWrite / fmOpenReadWrite / fmCreate
      - 虚方法：Read / Write（分块 1MB 透传）、Seek(Int64)、GetSize、
        SetSize64（截断/扩展）、Flush（fsync）、析构自动 close
      - pread/pwrite 语义：读写均带显式文件偏移，互不移动句柄位置；
        支持稀疏写（越过 EOF 写）与任意 Seek
      - 桥缺失/超时/ETS 错误抛 EStreamError 系异常；打开失败抛
        EFOpenError/EFCreateError（与 TFileStream 一致）
    OhosFileExists / OhosFileSize / OhosDeleteFile：免打开 URI 工具函数

  典型用法：
    var St: TStream; L: TStringList;
    St := TOhosFileStream.Create(uri, fmOpenRead);
    L.LoadFromStream(St);   // 或 L.LoadFromStream(TOhosFileStream.Create(...))
    St.Free;
    ...
    L.SaveToStream(TOhosFileStream.Create(saveUri, fmCreate));

  链路（与文件选择器同一桥模式，桥协议 v7）：
    本单元 → C++ ohos_file_io（命令 21，ArrayBuffer 二进制载荷）
      → ETS FpgFileIo.handleFileIo（fs.openSync/readSync/writeSync/...）
      → fpbridge.notifyFileIoResult(reqId, json, data?)
      → C++ → FileIoResultCallback（JS 线程：拷贝+摘除+SetEvent）

  解耦：本单元单向 uses fpg_ohos；框架单元不引用本单元。
  结果回调在 initialization 经 SetOhosFileIoResultCallback 注入。
  ===========================================================================
}

unit fpg_ohos_filestream;

{$mode objfpc}{$H+}
{$PACKRECORDS C}

interface

uses
  Classes, SysUtils;

type
  { 对 file:// 授权 URI 的同步文件流。返回码/异常约定与 Classes.THandleStream 对齐 }
  TOhosFileStream = class(TStream)
  private
    FHandle: Integer;        { ETS 句柄 id；-1=未打开 }
    FUri: string;
    FPosition: Int64;        { 本流逻辑位置（pread/pwrite，不依赖共享句柄位置）}
    FSize: Int64;            { 最近一次操作回传的文件大小 }
    FReadOnly: Boolean;
    procedure CheckWritable;
    procedure CheckOpen;
  protected
    function  GetSize: Int64; override;
    procedure SetSize64(const NewSize: Int64); override;
  public
    { Mode 同 TFileStream：fmOpenRead/fmOpenWrite/fmOpenReadWrite/fmCreate }
    constructor Create(const AUri: string; Mode: Word);
    destructor  Destroy; override;

    function  Read(var Buffer; Count: Longint): Longint; override;
    function  Write(const Buffer; Count: Longint): Longint; override;
    function  Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;

    procedure Flush;                         { fsync，错误抛异常 }
    function  FileName: string;              { 兼容 TFileStream 习惯 }

    property  Uri: string read FUri;
    property  Handle: Integer read FHandle;
  end;

{ 免打开 URI 工具（内部走 stat/unlink 子操作）}
function  OhosFileExists(const AUri: string): Boolean;
function  OhosFileSize(const AUri: string): Int64;
procedure OhosDeleteFile(const AUri: string);

implementation

uses
  SyncObjs,
  fpg_ohos;

const
  { 单次 I/O 透传分块：1MB。每次往返为 tsfn + JS 线程同步 fs 调用 + NAPI 回传，
    分块限制单次内存与命令体积，Count 更大时由 Read/Write 循环拼接。 }
  IO_CHUNK: Int64 = 1024 * 1024;

  { I/O 超时（ms）。fs.*Sync 在 JS 线程本地执行，正常为毫秒级；
    30s 足以覆盖大文件刷盘，超时按链路故障抛异常。 }
  FILEIO_TIMEOUT_MS = 30000;

  { OHOS fs.OpenMode 位掩码（与 @ohos.file.fs OpenMode 一致；
    对应八进制 0o0 / 0o2 / 0o4 / 0o100 / 0o1000）}
  OHOS_OPEN_READ_ONLY  = 0;
  OHOS_OPEN_WRITE_ONLY = 2;
  OHOS_OPEN_READ_WRITE = 4;
  OHOS_OPEN_CREATE     = 64;
  OHOS_OPEN_TRUNC      = 512;

  { 文件流子操作（与 C++ FileIoOp、ETS FileIoOp 严格一致）}
  OP_OPEN     = 0;
  OP_READ     = 1;
  OP_WRITE    = 2;
  OP_TRUNCATE = 3;
  OP_FSYNC    = 4;
  OP_CLOSE    = 5;
  OP_STAT     = 6;
  OP_DELETE   = 7;

type
  TFileIoReply = record
    Code: Integer;       { 0=成功 -2=错误 }
    ErrCode: Integer;    { OHOS BusinessError.code（诊断用）}
    Handle: Integer;     { open 分配的 ETS 句柄 id }
    N: Integer;          { read/write 实际字节数 }
    Size: Int64;         { 操作后文件大小（-1=未取到）}
  end;

  TFileIoRequest = class
    Done: TEvent;         { 自动复位 }
    Json: string;
    Data: TBytes;         { read 回传字节 }
  end;

  { C++ 独立导出符号（LibEntrySym 懒加载，与文件选择器同模式）}
  TOhosFileIoFn = procedure(reqId, op, arg: Integer;
    offset, length: Int64; uri: PChar; data: PByte; dataLen: Integer); cdecl;

var
  g_io_reqId: Integer = 0;
  g_io_pending: TStringList = nil;   { Names[reqId] → Objects[TFileIoRequest] }
  g_io_lock: TCriticalSection = nil;
  _ohos_file_io: TOhosFileIoFn = nil;

{ ── 极简固定 schema JSON 整数提取（不引 fpjson）────────────────────────── }

function JsonGetInt64(const S, Key: string; out V: Int64): Boolean;
var
  p, i: Integer;
  neg: Boolean;
  ch: Char;
begin
  Result := False;
  V := 0;
  p := Pos('"' + Key + '"', S);
  if p = 0 then Exit;
  i := p + Length(Key) + 2;          { 越过 "key" }
  while (i <= Length(S)) and (S[i] in [' ', #9]) do Inc(i);
  if (i > Length(S)) or (S[i] <> ':') then Exit;
  Inc(i);
  while (i <= Length(S)) and (S[i] in [' ', #9]) do Inc(i);
  neg := False;
  if i <= Length(S) then
  begin
    if S[i] = '-' then
    begin
      neg := True;
      Inc(i);
    end;
  end;
  while i <= Length(S) do
  begin
    ch := S[i];
    if ch in ['0'..'9'] then
      V := V * 10 + (Ord(ch) - Ord('0'))
    else
      Break;
    Inc(i);
  end;
  if neg then V := -V;
  Result := True;
end;

{ ── 同步请求往返（JS 线程回传，竞态防护同文件选择器）──────────────────── }

procedure FileIoResultCallback(reqId: Integer; json: PChar;
  data: PByte; dataLen: Integer); cdecl;
var
  req: TFileIoRequest;
  idx: Integer;
  s: string;
begin
  s := '';
  if json <> nil then s := json;   { C++ 串仅本次调用有效，立即拷贝 }
  g_io_lock.Enter;
  try
    idx := g_io_pending.IndexOf(IntToStr(reqId));
    if idx >= 0 then
    begin
      req := TFileIoRequest(g_io_pending.Objects[idx]);
      req.Json := s;
      if dataLen > 0 then
      begin
        SetLength(req.Data, dataLen);
        if Assigned(data) then
          Move(data^, req.Data[0], dataLen);
      end
      else
        SetLength(req.Data, 0);
      g_io_pending.Delete(idx);    { 锁内摘除后 SetEvent，杜绝迟到/超时 UAF }
      req.Done.SetEvent;
    end;
  finally
    g_io_lock.Leave;
  end;
end;

{ 发起一次文件 I/O 子操作并阻塞等待回复；失败统一抛 EStreamError，
  打开/创建失败由调用方改抛 EFOpenError/EFCreateError。
  AOutData 返回 read 的数据（其余操作为空数组）。}
function IoSync(op, arg: Integer; const AOffset, ALength: Int64;
  const AUri: string; AData: PByte; ADataLen: Integer;
  out AOutData: TBytes): TFileIoReply;
var
  reqId, idx: Integer;
  req: TFileIoRequest;
  wres: TWaitResult;
  json: string;
  vi: Int64;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Size := -1;
  SetLength(AOutData, 0);

  g_io_lock.Enter;
  try
    Inc(g_io_reqId);
    reqId := g_io_reqId;
  finally
    g_io_lock.Leave;
  end;

  req := TFileIoRequest.Create;
  req.Done := TEvent.Create(nil, False, False, '');
  g_io_lock.Enter;
  try
    g_io_pending.AddObject(IntToStr(reqId), req);
  finally
    g_io_lock.Leave;
  end;

  try
    if not Assigned(_ohos_file_io) then
      Pointer(_ohos_file_io) := LibBridgeSym('ohos_file_io');
    if not Assigned(_ohos_file_io) then
      raise EStreamError.Create('TOhosFileStream: 桥符号 ohos_file_io 不可用');

    _ohos_file_io(reqId, op, arg, AOffset, ALength,
      PChar(AUri), AData, ADataLen);

    wres := req.Done.WaitFor(FILEIO_TIMEOUT_MS);

    g_io_lock.Enter;
    try
      json := req.Json;
      AOutData := Copy(req.Data);
    finally
      g_io_lock.Leave;
    end;

    if wres <> wrSignaled then
      raise EStreamError.CreateFmt(
        'TOhosFileStream: I/O 超时(op=%d uri=%s)', [op, AUri]);

    Result.Code := -2;
    if JsonGetInt64(json, 'code', vi) then Result.Code := Integer(vi);
    if JsonGetInt64(json, 'errCode', vi) then Result.ErrCode := Integer(vi);
    if JsonGetInt64(json, 'handle', vi) then Result.Handle := Integer(vi);
    if JsonGetInt64(json, 'n', vi) then Result.N := Integer(vi);
    if JsonGetInt64(json, 'size', vi) then Result.Size := vi;

    if Result.Code <> 0 then
      raise EStreamError.CreateFmt(
        'TOhosFileStream: I/O 错误 op=%d uri=%s OHOS=%d',
        [op, AUri, Result.ErrCode]);
  finally
    g_io_lock.Enter;
    try
      idx := g_io_pending.IndexOf(IntToStr(reqId));
      if idx >= 0 then g_io_pending.Delete(idx);
    finally
      g_io_lock.Leave;
    end;
    req.Done.Free;
    req.Free;
  end;
end;

{ 忽略异常的关闭（析构路径用；ETS 对未知/重复句柄也回 code=0）}
procedure TryCloseHandle(AHandle: Integer);
var
  outData: TBytes;
begin
  if AHandle < 0 then Exit;
  try
    IoSync(OP_CLOSE, AHandle, 0, 0, '', nil, 0, outData);
  except
    { 析构中吞掉关闭异常，避免掩盖原异常 }
  end;
end;

{ ── TOhosFileStream ───────────────────────────────────────────────────── }

constructor TOhosFileStream.Create(const AUri: string; Mode: Word);
var
  openMode: Integer;
  createMode: Boolean;
  outData: TBytes;
  reply: TFileIoReply;
  access: Word;
begin
  inherited Create;
  FHandle := -1;
  FUri := AUri;
  FPosition := 0;
  FSize := 0;

  createMode := Mode = fmCreate;
  if createMode then
  begin
    { 对齐 POSIX TFileStream(fmCreate)：O_RDWR|O_CREAT|O_TRUNC }
    openMode := OHOS_OPEN_READ_WRITE or OHOS_OPEN_CREATE or OHOS_OPEN_TRUNC;
    FReadOnly := False;
  end
  else
  begin
    access := Mode and 3;
    case access of
      fmOpenRead:
        begin
          openMode := OHOS_OPEN_READ_ONLY;
          FReadOnly := True;
        end;
      fmOpenWrite:
        begin
          openMode := OHOS_OPEN_WRITE_ONLY;
          FReadOnly := False;
        end;
      fmOpenReadWrite:
        begin
          openMode := OHOS_OPEN_READ_WRITE;
          FReadOnly := False;
        end;
    else
      raise EFOpenError.CreateFmt('TOhosFileStream: 不支持的打开模式 %d: %s',
        [Mode, AUri]);
    end;
  end;

  try
    reply := IoSync(OP_OPEN, openMode, 0, 0, AUri, nil, 0, outData);
  except
    on E: EStreamError do
    begin
      if createMode then
        raise EFCreateError.CreateFmt('无法创建文件 %s: %s', [AUri, E.Message])
      else
        raise EFOpenError.CreateFmt('无法打开文件 %s: %s', [AUri, E.Message]);
    end;
  end;

  FHandle := reply.Handle;
  FSize := reply.Size;
  FPosition := 0;
end;

destructor TOhosFileStream.Destroy;
begin
  TryCloseHandle(FHandle);
  inherited Destroy;
end;

procedure TOhosFileStream.CheckOpen;
begin
  if FHandle < 0 then
    raise EStreamError.CreateFmt('TOhosFileStream: 句柄未打开: %s', [FUri]);
end;

procedure TOhosFileStream.CheckWritable;
begin
  CheckOpen;
  if FReadOnly then
    raise EWriteError.CreateFmt('TOhosFileStream: 流以只读方式打开: %s', [FUri]);
end;

function TOhosFileStream.Read(var Buffer; Count: Longint): Longint;
var
  p: PByte;
  remaining, want, got: Longint;
  outData: TBytes;
  reply: TFileIoReply;
begin
  Result := 0;
  if Count <= 0 then Exit;
  CheckOpen;

  p := PByte(@Buffer);
  remaining := Count;
  while remaining > 0 do
  begin
    if remaining > IO_CHUNK then want := Longint(IO_CHUNK) else want := remaining;
    reply := IoSync(OP_READ, FHandle, FPosition, want, '', nil, 0, outData);
    got := reply.N;
    if reply.Size >= 0 then FSize := reply.Size;
    if got > 0 then
    begin
      if got > Length(outData) then got := Length(outData);
      Move(outData[0], p^, got);
      Inc(FPosition, got);
      Inc(Result, got);
      Dec(remaining, got);
      p := p + got;
    end;
    { 短读即 EOF：fs.readSync 返回值小于请求字节数 }
    if got < want then Break;
  end;
end;

function TOhosFileStream.Write(const Buffer; Count: Longint): Longint;
var
  p: PByte;
  remaining, want, put: Longint;
  outData: TBytes;
  reply: TFileIoReply;
begin
  Result := 0;
  if Count <= 0 then Exit;
  CheckWritable;

  p := PByte(@Buffer);
  remaining := Count;
  while remaining > 0 do
  begin
    if remaining > IO_CHUNK then want := Longint(IO_CHUNK) else want := remaining;
    reply := IoSync(OP_WRITE, FHandle, FPosition, want, '', p, want, outData);
    put := reply.N;
    if put <= 0 then
      raise EWriteError.CreateFmt(
        'TOhosFileStream: 写入 0 字节 (pos=%d uri=%s)', [FPosition, FUri]);
    if reply.Size >= 0 then FSize := reply.Size;
    Inc(FPosition, put);
    Inc(Result, put);
    Dec(remaining, put);
    p := p + put;
    if put < want then Break;  { 理论上不应发生，防御性退出 }
  end;
end;

function TOhosFileStream.Seek(const Offset: Int64;
  Origin: TSeekOrigin): Int64;
begin
  CheckOpen;
  case Origin of
    soBeginning: FPosition := Offset;
    soCurrent:   FPosition := FPosition + Offset;
    soEnd:       FPosition := FSize + Offset;
  end;
  if FPosition < 0 then FPosition := 0;
  Result := FPosition;
end;

function TOhosFileStream.GetSize: Int64;
begin
  Result := FSize;
end;

procedure TOhosFileStream.SetSize64(const NewSize: Int64);
var
  outData: TBytes;
  reply: TFileIoReply;
begin
  CheckWritable;
  reply := IoSync(OP_TRUNCATE, FHandle, 0, NewSize, '', nil, 0, outData);
  if reply.Size >= 0 then FSize := reply.Size;
end;

procedure TOhosFileStream.Flush;
var
  outData: TBytes;
begin
  CheckOpen;
  IoSync(OP_FSYNC, FHandle, 0, 0, '', nil, 0, outData);
end;

function TOhosFileStream.FileName: string;
begin
  Result := FUri;
end;

{ ── 免打开 URI 工具 ───────────────────────────────────────────────────── }

function OhosFileExists(const AUri: string): Boolean;
var
  outData: TBytes;
begin
  try
    IoSync(OP_STAT, 0, 0, 0, AUri, nil, 0, outData);
    Result := True;
  except
    Result := False;
  end;
end;

function OhosFileSize(const AUri: string): Int64;
var
  outData: TBytes;
  reply: TFileIoReply;
begin
  reply := IoSync(OP_STAT, 0, 0, 0, AUri, nil, 0, outData);
  Result := reply.Size;
end;

procedure OhosDeleteFile(const AUri: string);
var
  outData: TBytes;
begin
  IoSync(OP_DELETE, 0, 0, 0, AUri, nil, 0, outData);
end;

initialization
  pascalApi.file_io_result := @FileIoResultCallback;
  if gBridgeInitialized then ohos_bridge_connect;

  g_io_lock := TCriticalSection.Create;
  g_io_pending := TStringList.Create;
  g_io_pending.Sorted := True;
  g_io_pending.Duplicates := dupError;

finalization
  FreeAndNil(g_io_pending);
  FreeAndNil(g_io_lock);

end.
