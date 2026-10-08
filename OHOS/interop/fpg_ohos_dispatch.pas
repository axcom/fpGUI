unit fpg_ohos_dispatch;
{ =========================================================================
  fpGUI OHOS 动态分发（Registry-Dispatch）v2
  =========================================================================
  业务侧：
    - 同步：function(const Params: string): string
    - 异步：procedure(const Params, JobId: string)，完成后 CompleteJob/FailJob
    - 注册：RegisterSync / RegisterAsync（可带 Schema 参数校验）
  框架侧：
    - fpgui_dispatch_entry  ：任意线程受理（入队即返回，结果经注入 Sink 回传）
    - fpgui_dispatch_free   ：释放入口返回的 PChar（C++ 调用）
    - fpgui_dispatch_pump   ：fpGUI 主线程消费队列
    - 异步并发上限 + 作业超时守护 + 合作式取消 + 同步看门狗
  线程模型：
    ArkTS(NAPI) 线程 ──entry──► 队列 + Wake
    fpGUI 主线程    ──pump───► 同步 Handler 直接执行 / 异步 Handler 起 TAsyncWorker
    Handler 完成    ──sink───► C++ dispatch_result → TSFN → Promise
  本单元 interface 不依赖 fpg_ohos；Wake/ResultSink/UIThreadId 由 fpg_ohos 注入。
  ========================================================================= }
{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, SyncObjs;

type
  TfpguiHandlerFn      = function(const Params: string): string;
  TfpguiAsyncHandlerFn = procedure(const Params: string; const JobId: string);
  TfpguiValidator      = function(const Params: string; out ErrorMsg: string): Boolean;

  { ---- Schema（可选参数校验；fpjson 实现）---- }
  TfpguiParamType = (ptString, ptNumber, ptBoolean, ptObject, ptArray, ptAny);
  TfpguiParamSpec = record
    Name: string;
    ParamType: TfpguiParamType;
    Required: Boolean;
    DefaultValue: string;
  end;
  TfpguiParamSchema = array of TfpguiParamSpec;

  TDispatchResultSink = procedure(const JobId, ResultJson: string; Failed: Boolean);
  TDispatchWakeProc   = procedure;
  TDispatchLogProc    = procedure(const Msg: string);
  TUIWorkProc         = procedure;
  TStringFunc         = function: string;

function Param(const AName: string; AType: TfpguiParamType;
  ARequired: Boolean = True; const ADefault: string = ''): TfpguiParamSpec;

{ ---- 注册 API ---- }
procedure RegisterSync(const OpType: string; Handler: TfpguiHandlerFn);
procedure RegisterSync(const OpType: string; Handler: TfpguiHandlerFn;
  const Schema: TfpguiParamSchema);
procedure RegisterAsync(const OpType: string; Handler: TfpguiAsyncHandlerFn);
procedure RegisterAsync(const OpType: string; Handler: TfpguiAsyncHandlerFn;
  const Schema: TfpguiParamSchema);
procedure UnregisterHandler(const OpType: string);
function  IsRegistered(const OpType: string): Boolean;

{ ---- 异步 Handler 完成 / 取消查询 ---- }
procedure CompleteJob(const JobId, ResultJson: string);
procedure FailJob(const JobId, ErrorMsg: string);
function  IsJobCancelled(const JobId: string): Boolean;

{ ---- UI 线程编组（异步 Handler 内使用）---- }
procedure RunOnUIThreadAsync(AProc: TUIWorkProc);
procedure RunOnUIThreadSync(AProc: TUIWorkProc; TimeoutMs: Cardinal = 5000);
function  RunOnUIThreadString(AFunc: TStringFunc; TimeoutMs: Cardinal = 5000): string;

{ ---- 框架入口 ---- }
function  fpgui_dispatch_entry(opType, params: PChar): PChar; cdecl;
procedure fpgui_dispatch_free(p: PChar); cdecl;
procedure fpgui_dispatch_pump;
function  fpgui_dispatch_has_pending: Boolean;

{ ---- 注入（fpg_ohos.pas 调用）---- }
procedure SetDispatchUIThreadId(AId: TThreadID);
{procedure SetDispatchWake(AWake: TDispatchWakeProc);
procedure SetDispatchResultSink(ASink: TDispatchResultSink);
procedure SetDispatchLog(AProc: TDispatchLogProc);
procedure SetDispatchTimeout(ATimeoutMs: Cardinal);
procedure SetMaxAsyncJobs(AMax: Integer);}

implementation

uses fpg_ohos, fpg_main;

const
  DEFAULT_TIMEOUT_MS = 30000; { 0 = 禁用超时（不做过期回收）；>0 设定毫秒阈值 }
  DEFAULT_MAX_ASYNC   = 4;
  SYNC_WATCHDOG_MS    = 200;
  CANCEL_GRACE_MS     = 1000;

type
  TDispatchEntry = class
  public
    OpType: string;
    IsAsync: Boolean;
    SyncFn: TfpguiHandlerFn;
    AsyncFn: TfpguiAsyncHandlerFn;
    Schema: TfpguiParamSchema;
  end;

  TDispatchJob = class
  public
    OpType: string;
    Params: string;
    JobId: string;
    IsAsync: Boolean;
    SyncFn: TfpguiHandlerFn;
    AsyncFn: TfpguiAsyncHandlerFn;
    Done: Boolean;
    Failed: Boolean;
    CancelRequested: Boolean;
    CancelTick: QWord;
    ResultJson: string;
    CreatedTick: QWord;
  end;

  { 队列项：dispatch 作业 或 UI 线程任务 }
  TDispatchQueueItem = class
  public
    procedure Run; virtual; abstract;
  end;

  TDispatchJobItem = class(TDispatchQueueItem)
  public
    Job: TDispatchJob;
    procedure Run; override;
  end;

  TUIWorkItem = class(TDispatchQueueItem)
  public
    Proc: TUIWorkProc;
    Func: TStringFunc;
    Event: TEvent;
    ResultStr: string;
    AutoFree: Boolean;
    procedure Run; override;
  end;

  { 异步作业执行线程（作业即由本线程释放） }
  TAsyncWorker = class(TThread)
  private
    FJob: TDispatchJob;
    FJobId: string;
  protected
    procedure Execute; override;
  public
    constructor Create(AJob: TDispatchJob);
  end;

  { 作业超时守护 }
  TJobJanitor = class(TThread)
  protected
    procedure Execute; override;
  end;

  { 动态分发结果回传（C++ 实现 dispatch_result；Pascal 消费）}
  TDispatchResultFn = procedure(jobId, resultJson: PChar; failed: Integer); cdecl;
  
var
  gRegLock: TCriticalSection = nil;
  gJobLock: TCriticalSection = nil;
  gQueueLock: TCriticalSection = nil;
  gAsyncLock: TCriticalSection = nil;

  gEntries: TStringList = nil;   { opType(小写) -> TDispatchEntry }
  gJobs: TStringList = nil;      { jobId -> TDispatchJob（未完成） }
  gQueue: TList = nil;           { TDispatchQueueItem 待 UI 线程执行 }
  gAsyncWait: TList = nil;       { 已受理、等待异步 Worker 空位的 job }
  gJobSeq: Integer = 0;
  gAsyncActive: Integer = 0;
  gMaxAsync: Integer = DEFAULT_MAX_ASYNC; { 异步并发上限 }

  { 动态分发结果回传（C++ dispatch_result）}
  _fpgui_dispatch_result: TDispatchResultFn = nil;

//  gWake: TDispatchWakeProc = nil;
//  gSink: TDispatchResultSink = nil;
//  gLog: TDispatchLogProc = nil;
  gUIThreadId: TThreadID = TThreadID(0);
  gUIThreadSet: Boolean = False;
  gTimeoutMs: Cardinal = DEFAULT_TIMEOUT_MS; { 异步作业超时；0=禁用 }

  gJanitor: TJobJanitor = nil;
  gShutdown: Boolean = False;

{ =====================================================================
  辅助
  ===================================================================== }

{ 唤醒 fpGUI 主循环：dispatch 入口入队后调用（任意线程），
  经 WakeChannel.Signal 唤醒 select，主循环继而 fpgui_dispatch_pump。 }
procedure OhosDispatchWake;
begin
  if fpgApplication <> nil then
    fpgApplication.WakeMainThread;
end;

{ 分发结果回传：Pascal Handler 完成 → C++ dispatch_result(jobId,json,failed)
  → napi_threadsafe_function → ArkTS Promise resolve/reject。 }
procedure OhosDispatchResultSink(const JobId, ResultJson: string; Failed: Boolean);
begin
  if not Assigned(_fpgui_dispatch_result) then
    Pointer(_fpgui_dispatch_result) :=  LibBridgeSym('ohos_dispatch_result');
  if Assigned(_fpgui_dispatch_result) then
    _fpgui_dispatch_result(PChar(JobId), PChar(ResultJson), Ord(Failed));
end;

{ 日志（看门狗/超时/取消等）转发到 hilog。 }
procedure DLog(const Msg: string);
begin
  fpGUI_Hilog(LOG_INFO, Msg);
end;

function JsonEscape(const S: string): string;
var
  i: Integer;
  c: AnsiChar;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    case c of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8:  Result := Result + '\b';
      #9:  Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if Ord(c) < 32 then
        Result := Result + '\u' + LowerCase(IntToHex(Ord(c), 4))
      else
        Result := Result + c;
    end;
  end;
end;

function JsonError(const Code, Msg: string): string;
begin
  Result := '{"ok":false,"code":"' + JsonEscape(Code) +
            '","error":"' + JsonEscape(Msg) + '"}';
end;

function ExtractJsonString(const S, Key: string): string;
var
  pat: string;
  p, q: Integer;
begin
  Result := '';
  pat := '"' + Key + '":"';
  p := Pos(pat, S);
  if p = 0 then Exit;
  p := p + Length(pat);
  q := p;
  while (q <= Length(S)) and (S[q] <> '"') do Inc(q);
  if q > p then Result := Copy(S, p, q - p);
end;

function NormalizeOp(const S: string): string;
begin
  Result := LowerCase(Trim(S));
end;

function AllocResult(const S: string): PChar;
begin
  Result := StrAlloc(Length(S) + 1);
  StrPCopy(Result, S);
end;

function Param(const AName: string; AType: TfpguiParamType;
  ARequired: Boolean; const ADefault: string): TfpguiParamSpec;
begin
  Result.Name := AName;
  Result.ParamType := AType;
  Result.Required := ARequired;
  Result.DefaultValue := ADefault;
end;

{ =====================================================================
  Schema 校验（内置轻量 JSON 对象解析，无 fpjson 依赖）
  ===================================================================== }

const
  JSON_WS = [' ', #9, #10, #13];

{ 返回顶层 "key": 后 value 的起始位置（已跳过空白）；未找到返回 0 }
function JsonValuePos(const Obj, Key: string): Integer;
var
  pat: string;
  p, q: Integer;
begin
  Result := 0;
  pat := '"' + Key + '"';
  p := Pos(pat, Obj);
  while p > 0 do
  begin
    q := p + Length(pat);
    while (q <= Length(Obj)) and (Obj[q] in JSON_WS) do Inc(q);
    if (q <= Length(Obj)) and (Obj[q] = ':') then
    begin
      Inc(q);
      while (q <= Length(Obj)) and (Obj[q] in JSON_WS) do Inc(q);
      Exit(q);
    end;
    p := Pos(pat, Obj, p + 1);
  end;
end;

function JsonKindAt(const Obj: string; pos: Integer): TfpguiParamType;
var
  c: AnsiChar;
begin
  Result := ptAny;
  if (pos < 1) or (pos > Length(Obj)) then Exit;
  c := Obj[pos];
  case c of
    '"': Result := ptString;
    '{': Result := ptObject;
    '[': Result := ptArray;
    't', 'f': Result := ptBoolean;
    '-', '0'..'9': Result := ptNumber;
  else
    Result := ptAny;
  end;
end;

function ValidateParams(const Params: string; const Schema: TfpguiParamSchema;
  out ErrorMsg: string): Boolean;
var
  i, pos: Integer;
  spec: TfpguiParamSpec;
begin
  Result := False;
  ErrorMsg := '';
  if Length(Schema) = 0 then
  begin
    Result := True;
    Exit;
  end;

  for i := 0 to High(Schema) do
  begin
    spec := Schema[i];
    pos := JsonValuePos(Params, spec.Name);
    if pos = 0 then
    begin
      if spec.Required then
      begin
        ErrorMsg := 'missing required param: ' + spec.Name;
        Exit;
      end;
      Continue;
    end;
    case spec.ParamType of
      ptString:  if JsonKindAt(Params, pos) <> ptString then
        begin ErrorMsg := spec.Name + ' must be string'; Exit; end;
      ptNumber:  if JsonKindAt(Params, pos) <> ptNumber then
        begin ErrorMsg := spec.Name + ' must be number'; Exit; end;
      ptBoolean: if JsonKindAt(Params, pos) <> ptBoolean then
        begin ErrorMsg := spec.Name + ' must be boolean'; Exit; end;
      ptObject:  if JsonKindAt(Params, pos) <> ptObject then
        begin ErrorMsg := spec.Name + ' must be object'; Exit; end;
      ptArray:   if JsonKindAt(Params, pos) <> ptArray then
        begin ErrorMsg := spec.Name + ' must be array'; Exit; end;
      ptAny: ;
    end;
  end;
  Result := True;
end;

{ =====================================================================
  作业表
  ===================================================================== }

function TakeJob(const JobId: string): TDispatchJob;
var
  idx: Integer;
begin
  Result := nil;
  gJobLock.Acquire;
  try
    idx := gJobs.IndexOf(JobId);
    if idx >= 0 then
    begin
      Result := TDispatchJob(gJobs.Objects[idx]);
      gJobs.Delete(idx);
    end;
  finally
    gJobLock.Release;
  end;
end;

function JobPending(const JobId: string): Boolean;
var
  idx: Integer;
  job: TDispatchJob;
begin
  Result := False;
  gJobLock.Acquire;
  try
    idx := gJobs.IndexOf(JobId);
    if idx >= 0 then
    begin
      job := TDispatchJob(gJobs.Objects[idx]);
      Result := not job.Done;
    end;
  finally
    gJobLock.Release;
  end;
end;

procedure EmitResult(const JobId, ResultJson: string; Failed: Boolean);
var
  job: TDispatchJob;
begin
  job := TakeJob(JobId);   { 不存在（已完成/已取消/已超时）则不重复回传 }
  if job = nil then Exit;
  job.Done := True;
  job.Failed := Failed;
  job.ResultJson := ResultJson;
  OhosDispatchResultSink(JobId, ResultJson, Failed);
end;

procedure CompleteJob(const JobId, ResultJson: string);
begin
  EmitResult(JobId, ResultJson, False);
end;

procedure FailJob(const JobId, ErrorMsg: string);
begin
  EmitResult(JobId, JsonError('INTERNAL', ErrorMsg), True);
end;

function IsJobCancelled(const JobId: string): Boolean;
var
  idx: Integer;
  job: TDispatchJob;
begin
  Result := True;   { 作业已不在表中（已取消/完成/超时）→ 视为需退出 }
  gJobLock.Acquire;
  try
    idx := gJobs.IndexOf(JobId);
    if idx >= 0 then
    begin
      job := TDispatchJob(gJobs.Objects[idx]);
      Result := job.CancelRequested or job.Done;
    end;
  finally
    gJobLock.Release;
  end;
end;

{ =====================================================================
  异步 Worker（带并发上限）
  ===================================================================== }

procedure StartNextAsyncJob;
var
  job: TDispatchJob;
begin
  job := nil;
  gAsyncLock.Acquire;
  try
    if (not gShutdown) and (gAsyncActive < gMaxAsync) and (gAsyncWait.Count > 0) then
    begin
      job := TDispatchJob(gAsyncWait[0]);
      gAsyncWait.Delete(0);
      Inc(gAsyncActive);
    end;
  finally
    gAsyncLock.Release;
  end;
  if job <> nil then
    TAsyncWorker.Create(job).Start;
end;

procedure StartAsyncJob(job: TDispatchJob);
var
  start: Boolean;
begin
  start := False;
  gAsyncLock.Acquire;
  try
    if gShutdown then
      start := False
    else if gAsyncActive < gMaxAsync then
    begin
      Inc(gAsyncActive);
      start := True;
    end
    else
      gAsyncWait.Add(job);
  finally
    gAsyncLock.Release;
  end;
  if start then
    TAsyncWorker.Create(job).Start
  else if gShutdown then
    FailJob(job.JobId, 'shutdown');
end;

constructor TAsyncWorker.Create(AJob: TDispatchJob);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FJob := AJob;
  FJobId := AJob.JobId;
end;

procedure TAsyncWorker.Execute;
var
  job: TDispatchJob;
begin
  job := FJob;
  try
    if JobPending(job.JobId) then
    try
      if Assigned(job.AsyncFn) then
        job.AsyncFn(job.Params, job.JobId)
      else
        FailJob(job.JobId, 'async handler not assigned');
    except
      on E: Exception do
        FailJob(job.JobId, 'async handler error: ' + E.Message);
    end;

    { Handler 返回但未 CompleteJob → 视为失败（避免作业悬挂） }
    if JobPending(job.JobId) then
      EmitResult(job.JobId, JsonError('INTERNAL',
        'async handler returned without CompleteJob'), True);
  finally
    job.Free;
    gAsyncLock.Acquire;
    try
      if gAsyncActive > 0 then Dec(gAsyncActive);
    finally
      gAsyncLock.Release;
    end;
    StartNextAsyncJob;
  end;
end;

{ =====================================================================
  队列项
  ===================================================================== }

procedure TDispatchJobItem.Run;
var
  t0: QWord;
  el: QWord;
  r: string;
begin
  if Job.IsAsync then
  begin
    StartAsyncJob(Job);
    Exit;
  end;

  t0 := GetTickCount64;
  try
    r := Job.SyncFn(Job.Params);
    Job.Failed := False;
  except
    on E: Exception do
    begin
      r := JsonError('INTERNAL', 'handler error: ' + E.Message);
      Job.Failed := True;
    end;
  end;
  el := GetTickCount64 - t0;
  if el > SYNC_WATCHDOG_MS then
    DLog(Format('dispatch WARN: sync handler "%s" took %d ms (blocks UI thread)',
      [Job.OpType, el]));
  EmitResult(Job.JobId, r, Job.Failed);
  Job.Free;
end;

procedure TUIWorkItem.Run;
begin
  try
    if Assigned(Func) then
      ResultStr := Func()
    else if Assigned(Proc) then
      Proc();
  except
    on E: Exception do
      ResultStr := '';
  end;
  if Event <> nil then
    Event.SetEvent;
  if AutoFree then
    Self.Free;
end;

{ =====================================================================
  注册表
  ===================================================================== }

procedure RegisterEntry(const OpType: string; IsAsync: Boolean;
  SyncFn: TfpguiHandlerFn; AsyncFn: TfpguiAsyncHandlerFn;
  const Schema: TfpguiParamSchema);
var
  e: TDispatchEntry;
  key: string;
  idx: Integer;
begin
  key := NormalizeOp(OpType);
  if key = '' then Exit;
  e := TDispatchEntry.Create;
  e.OpType := key;
  e.IsAsync := IsAsync;
  e.SyncFn := SyncFn;
  e.AsyncFn := AsyncFn;
  e.Schema := Schema;
  gRegLock.Acquire;
  try
    idx := gEntries.IndexOf(key);
    if idx >= 0 then
    begin
      gEntries.Objects[idx].Free;
      gEntries.Objects[idx] := e;
    end
    else
      gEntries.AddObject(key, e);
  finally
    gRegLock.Release;
  end;
end;

procedure RegisterSync(const OpType: string; Handler: TfpguiHandlerFn);
begin
  RegisterEntry(OpType, False, Handler, nil, nil);
end;

procedure RegisterSync(const OpType: string; Handler: TfpguiHandlerFn;
  const Schema: TfpguiParamSchema);
begin
  RegisterEntry(OpType, False, Handler, nil, Schema);
end;

procedure RegisterAsync(const OpType: string; Handler: TfpguiAsyncHandlerFn);
begin
  RegisterEntry(OpType, True, nil, Handler, nil);
end;

procedure RegisterAsync(const OpType: string; Handler: TfpguiAsyncHandlerFn;
  const Schema: TfpguiParamSchema);
begin
  RegisterEntry(OpType, True, nil, Handler, Schema);
end;

procedure UnregisterHandler(const OpType: string);
var
  key: string;
  idx: Integer;
begin
  key := NormalizeOp(OpType);
  gRegLock.Acquire;
  try
    idx := gEntries.IndexOf(key);
    if idx >= 0 then
    begin
      gEntries.Objects[idx].Free;
      gEntries.Delete(idx);
    end;
  finally
    gRegLock.Release;
  end;
end;

function IsRegistered(const OpType: string): Boolean;
var
  idx: Integer;
begin
  gRegLock.Acquire;
  try
    idx := gEntries.IndexOf(NormalizeOp(OpType));
    Result := idx >= 0;
  finally
    gRegLock.Release;
  end;
end;

{ =====================================================================
  受理
  ===================================================================== }

function DispatchStart(const op, params: string): string;
var
  idx: Integer;
  entry: TDispatchEntry;
  job: TDispatchJob;
  item: TDispatchJobItem;
  seq: Integer;
  id: string;
  err: string;
begin
  job := nil;
  gRegLock.Acquire;
  try
    idx := gEntries.IndexOf(op);
    if idx < 0 then
    begin
      Result := JsonError('NO_HANDLER', 'no handler: ' + op);
      Exit;
    end;
    entry := TDispatchEntry(gEntries.Objects[idx]);
    if not ValidateParams(params, entry.Schema, err) then
    begin
      Result := JsonError('SCHEMA_FAIL', err);
      Exit;
    end;
    job := TDispatchJob.Create;
    job.OpType := op;
    job.Params := params;
    job.IsAsync := entry.IsAsync;
    job.SyncFn := entry.SyncFn;
    job.AsyncFn := entry.AsyncFn;
    job.Done := False;
    job.Failed := False;
    job.CancelRequested := False;
    job.CreatedTick := GetTickCount64;
  finally
    gRegLock.Release;
  end;

  seq := InterlockedIncrement(gJobSeq);
  id := 'job_' + IntToStr(seq);
  job.JobId := id;

  gJobLock.Acquire;
  try
    gJobs.AddObject(id, job);
  finally
    gJobLock.Release;
  end;

  gQueueLock.Acquire;
  try
    item := TDispatchJobItem.Create;
    item.Job := job;
    gQueue.Add(item);
  finally
    gQueueLock.Release;
  end;

  OhosDispatchWake();

  Result := '{"ok":true,"async":true,"jobId":"' + id + '"}';
end;

function DispatchCancel(const params: string): string;
var
  jobId: string;
  idx: Integer;
  job: TDispatchJob;
begin
  jobId := ExtractJsonString(params, 'jobId');
  gJobLock.Acquire;
  try
    idx := gJobs.IndexOf(jobId);
    if idx < 0 then
      Result := '{"ok":true,"cancelRequested":false}'
    else
    begin
      job := TDispatchJob(gJobs.Objects[idx]);
      job.CancelRequested := True;
      job.CancelTick := GetTickCount64;
      Result := '{"ok":true,"cancelRequested":true}';
    end;
  finally
    gJobLock.Release;
  end;
end;

function DispatchOps: string;
var
  i: Integer;
  e: TDispatchEntry;
  sb: string;
begin
  sb := '';
  gRegLock.Acquire;
  try
    for i := 0 to gEntries.Count - 1 do
    begin
      e := TDispatchEntry(gEntries.Objects[i]);
      if i > 0 then sb := sb + ',';
      sb := sb + '{"op":"' + JsonEscape(e.OpType) + '","async":' +
            BoolToStr(e.IsAsync, 'true', 'false') + '}';
    end;
  finally
    gRegLock.Release;
  end;
  Result := '{"ok":true,"ops":[' + sb + ']}';
end;

function DispatchStats: string;
var
  q, jn, aw, aa: Integer;
begin
  gQueueLock.Acquire; try q := gQueue.Count; finally gQueueLock.Release; end;
  gJobLock.Acquire;   try jn := gJobs.Count; finally gJobLock.Release; end;
  gAsyncLock.Acquire; try aw := gAsyncWait.Count; aa := gAsyncActive; finally gAsyncLock.Release; end;
  Result := Format('{"ok":true,"queued":%d,"pending":%d,"asyncActive":%d,"asyncWaiting":%d,"maxAsync":%d}',
    [q, jn, aa, aw, gMaxAsync]);
end;

function fpgui_dispatch_entry(opType, params: PChar): PChar; cdecl;
var
  op, p, res: string;
begin
  if opType <> nil then op := LowerCase(Trim(string(opType))) else op := '';
  if params <> nil then p := string(params) else p := '';

  if op = '' then
    res := JsonError('BAD_ARGS', 'empty opType')
  else if op = '__ping' then
    res := '{"ok":true,"pong":true}'
  else if op = '__ops' then
    res := DispatchOps
  else if op = '__stats' then
    res := DispatchStats
  else if op = '__cancel' then
    res := DispatchCancel(p)
  else
    res := DispatchStart(op, p);

  Result := AllocResult(res);
end;

procedure fpgui_dispatch_free(p: PChar); cdecl;
begin
  if p <> nil then
    StrDispose(p);
end;

procedure fpgui_dispatch_pump;
var
  item: TDispatchQueueItem;
begin
  while True do
  begin
    item := nil;
    gQueueLock.Acquire;
    try
      if gQueue.Count > 0 then
      begin
        item := TDispatchQueueItem(gQueue[0]);
        gQueue.Delete(0);
      end;
    finally
      gQueueLock.Release;
    end;
    if item = nil then Break;
    item.Run;
  end;
end;

function fpgui_dispatch_has_pending: Boolean;
begin
  Result := False;
  gQueueLock.Acquire;
  try
    Result := gQueue.Count > 0;
  finally
    gQueueLock.Release;
  end;
end;

{ =====================================================================
  UI 线程编组
  ===================================================================== }

procedure EnqueueUIWork(item: TUIWorkItem);
begin
  gQueueLock.Acquire;
  try
    gQueue.Add(item);
  finally
    gQueueLock.Release;
  end;
  OhosDispatchWake();
end;

procedure RunOnUIThreadAsync(AProc: TUIWorkProc);
var
  item: TUIWorkItem;
begin
  if Assigned(AProc) then
  begin
    if (not gUIThreadSet) or (GetCurrentThreadId = gUIThreadId) then
      AProc()
    else
    begin
      item := TUIWorkItem.Create;
      item.Proc := AProc;
      item.Event := nil;
      item.AutoFree := True;
      EnqueueUIWork(item);
    end;
  end;
end;

procedure RunOnUIThreadSync(AProc: TUIWorkProc; TimeoutMs: Cardinal);
var
  item: TUIWorkItem;
begin
  if not Assigned(AProc) then Exit;
  if (not gUIThreadSet) or (GetCurrentThreadId = gUIThreadId) then
  begin
    AProc();
    Exit;
  end;
  item := TUIWorkItem.Create;
  try
    item.Proc := AProc;
    item.Event := TEvent.Create(nil, True, False, '');
    item.AutoFree := False;
    EnqueueUIWork(item);
    if item.Event.WaitFor(TimeoutMs) <> wrSignaled then
      DLog('dispatch WARN: RunOnUIThreadSync timeout');
  finally
    item.Event.Free;
    item.Free;
  end;
end;

function RunOnUIThreadString(AFunc: TStringFunc; TimeoutMs: Cardinal): string;
var
  item: TUIWorkItem;
begin
  Result := '';
  if not Assigned(AFunc) then Exit;
  if (not gUIThreadSet) or (GetCurrentThreadId = gUIThreadId) then
  begin
    Result := AFunc();
    Exit;
  end;
  item := TUIWorkItem.Create;
  try
    item.Func := AFunc;
    item.Event := TEvent.Create(nil, True, False, '');
    item.AutoFree := False;
    EnqueueUIWork(item);
    if item.Event.WaitFor(TimeoutMs) = wrSignaled then
      Result := item.ResultStr
    else
      DLog('dispatch WARN: RunOnUIThreadString timeout');
  finally
    item.Event.Free;
    item.Free;
  end;
end;

{ =====================================================================
  超时守护
  ===================================================================== }

procedure TJobJanitor.Execute;
var
  nowTick: QWord;
  toKill: TStringList;
  i: Integer;
  job: TDispatchJob;
begin
  while (not Terminated) and (not gShutdown) do
  begin
    Sleep(1000);
    nowTick := GetTickCount64;
    toKill := TStringList.Create;
    try
      gJobLock.Acquire;
      try
        for i := 0 to gJobs.Count - 1 do
        begin
          job := TDispatchJob(gJobs.Objects[i]);
          if job.Done or (not job.IsAsync) then Continue;   { 同步作业不参与超时 }
          { gTimeoutMs = 0 → 禁用超时（不做超时处理）；取消宽限仍生效 }
          if (gTimeoutMs > 0) and ((nowTick - job.CreatedTick) > gTimeoutMs) then
            toKill.Add(job.JobId)
          else if job.CancelRequested and
                  ((nowTick - job.CancelTick) > CANCEL_GRACE_MS) then
            toKill.Add(job.JobId);
        end;
      finally
        gJobLock.Release;
      end;
      for i := 0 to toKill.Count - 1 do
      begin
        if toKill[i] <> '' then
        begin
          DLog('dispatch WARN: job timeout/cancelled -> ' + toKill[i]);
          EmitResult(toKill[i], JsonError('TIMEOUT', 'job timeout or cancelled'), True);
        end;
      end;
    finally
      toKill.Free;
    end;
  end;
end;

{ =====================================================================
  注入
  ===================================================================== }

procedure SetDispatchUIThreadId(AId: TThreadID);
begin
  gUIThreadId := AId;
  gUIThreadSet := True;
end;

(*procedure SetDispatchWake(AWake: TDispatchWakeProc);
begin
  gWake := AWake;
end;

procedure SetDispatchResultSink(ASink: TDispatchResultSink);
begin
  gSink := ASink;
end;

procedure SetDispatchLog(AProc: TDispatchLogProc);
begin
  gLog := AProc;
end;

procedure SetDispatchTimeout(ATimeoutMs: Cardinal);
begin
  { 0 = 禁用超时（不做过期回收）；>0 设定毫秒阈值 }
  gTimeoutMs := ATimeoutMs;
end;

procedure SetMaxAsyncJobs(AMax: Integer);
begin
  if AMax > 0 then gMaxAsync := AMax;
end;*)

initialization
  fpg_ohos.gDispatchPump 		:= @fpgui_dispatch_pump;
  fpg_ohos.gDispatchHasPending 	:= @fpgui_dispatch_has_pending;
  fpg_ohos.gDispatchUIThreadId 	:= @SetDispatchUIThreadId;

  fpg_ohos.pascalApi.dispatch             := @fpgui_dispatch_entry;    { v6 动态分发入口 }
  fpg_ohos.pascalApi.dispatch_free        := @fpgui_dispatch_free;     { v7 释放入口返回的 PChar }
  if gBridgeInitialized then ohos_bridge_connect;

  gRegLock := TCriticalSection.Create;
  gJobLock := TCriticalSection.Create;
  gQueueLock := TCriticalSection.Create;
  gAsyncLock := TCriticalSection.Create;
  gEntries := TStringList.Create;
  gEntries.Sorted := True;
  gEntries.CaseSensitive := True;
  gJobs := TStringList.Create;
  gQueue := TList.Create;
  gAsyncWait := TList.Create;
  gJobSeq := 0;
  gShutdown := False;

  gJanitor := TJobJanitor.Create(True);
  gJanitor.FreeOnTerminate := False;
  gJanitor.Start;

finalization
  gShutdown := True;
  if gJanitor <> nil then
  begin
    gJanitor.Terminate;
    gJanitor.WaitFor;
    gJanitor.Free;
  end;
  if gJobs <> nil then
    while gJobs.Count > 0 do
    begin
      TDispatchJob(gJobs.Objects[0]).Free;
      gJobs.Delete(0);
    end;
  if gEntries <> nil then
    while gEntries.Count > 0 do
    begin
      gEntries.Objects[0].Free;
      gEntries.Delete(0);
    end;
  if gAsyncWait <> nil then
    while gAsyncWait.Count > 0 do
    begin
      TDispatchJob(gAsyncWait[0]).Free;
      gAsyncWait.Delete(0);
    end;
  FreeAndNil(gAsyncWait);
  FreeAndNil(gQueue);
  FreeAndNil(gJobs);
  FreeAndNil(gEntries);
  FreeAndNil(gAsyncLock);
  FreeAndNil(gQueueLock);
  FreeAndNil(gJobLock);
  FreeAndNil(gRegLock);

end.
