unit fpg_ohos_invoke;
{ =========================================================================
  fpGUI → ArkTS 反向调用（arkTS_Invoke）v1
  =========================================================================
  业务侧：
    ArkTS_Invoke(method, params, timeout)  同步取回 ArkTS 方法返回串
    ArkTS_InvokeAsync(method, params)      即发即忘（受理码）
  框架侧：
    pending 表（callId 'p_N' → TEvent + ResultJson）+ 超时安全摘除
    InvokeResultCallback：C++ 在 JS 线程调用，只做 拷贝+锁+摘除+SetEvent
  线程模型：
    Pascal 任意线程 ──arkts_invoke──► C++（JS 线程内联 / TSFN 投递）
    JS 线程        ──invoke_result─► 本单元回调 → SetEvent 唤醒等待方
  竞态防护（与 FilePickerResultCallback 同款）：
    回调：持锁 → 摘 pending → 写 ResultJson → SetEvent → 解锁
    等待方：WaitFor 返回后必须持锁读 ResultJson；finally 持锁摘除后才 Free
  ========================================================================= }
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs;

type
  TArkTsInvokeFn       = function(callId, method, params: PChar): Integer; cdecl;
  TArkTsInvokeResultFn = procedure(callId, resultJson: PChar; failed: Integer); cdecl;

const
  INVOKE_DEFAULT_TIMEOUT_MS = 5000;

function ArkTS_InvokeReady: Boolean;
function ArkTS_Invoke(const Method, Params: string;
  TimeoutMs: Cardinal = INVOKE_DEFAULT_TIMEOUT_MS): string;
function ArkTS_InvokeAsync(const Method, Params: string): Integer;

implementation

uses
  fpg_ohos;

const
  { 与 C++ ohos_arkts_invoke 返回码一致 }
  INVOKE_OK       = 0;
  INVOKE_BAD_ARGS = -1;
  INVOKE_NO_CONN  = -2;
  INVOKE_NO_METHOD= -3;
  INVOKE_Q_FULL   = -4;

type
  TInvokePending = class
  public
    Done: TEvent;
    ResultJson: string;
    Failed: Boolean;
  end;

var
  g_lock: TCriticalSection = nil;
  g_pending: TStringList = nil;    { Names[callId] → Objects[TInvokePending] }
  g_callSeq: Integer = 0;

  _arkts_invoke: TArkTsInvokeFn = nil;                                       { v13 }

function JsonEscape(const S: string): string;
var
  i: Integer; c: AnsiChar;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    case c of
      '"':  Result := Result + '\"';
      '\':  Result := Result + '\\';
      #8:   Result := Result + '\b';
      #9:   Result := Result + '\t';
      #10:  Result := Result + '\n';
      #12:  Result := Result + '\f';
      #13:  Result := Result + '\r';
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

function StatusEnvelope(Ret: Integer): string;
begin
  case Ret of
    INVOKE_OK:        Result := '';
    INVOKE_BAD_ARGS:  Result := JsonError('BAD_ARGS', 'invalid callId/method');
    INVOKE_NO_CONN:   Result := JsonError('NOT_CONNECTED', 'bridge TSFN not initialized');
    INVOKE_NO_METHOD: Result := JsonError('NO_METHOD', 'method not registered in ArkTS');
    INVOKE_Q_FULL:    Result := JsonError('QUEUE_FULL', 'tsfn queue full or closing');
  else
    Result := JsonError('INTERNAL', 'ohos_arkts_invoke returned ' + IntToStr(Ret));
  end;
end;

function GetInvokeFn: TArkTsInvokeFn;
begin
  { 槽位优先（v13 正式通路）→ dlsym 兜底（槽位未填但符号已导出的中间态） }
  Result := _arkts_invoke;
  if Result = nil then
    Result := TArkTsInvokeFn(LibBridgeSym('ohos_arkts_invoke'));
end;

function ArkTS_InvokeReady: Boolean;
begin
  Result := GetInvokeFn() <> nil;
end;

{ ── 结果回调（C++ 在 JS 线程调用）───────────────────────────────────── }
procedure InvokeResultCallback(callId, resultJson: PChar; failed: Integer); cdecl;
var
  s: string;
  idx: Integer;
  req: TInvokePending;
begin
  s := '';
  if resultJson <> nil then s := resultJson;   { 立即拷贝：C++ 串仅本次调用有效 }
  if callId = nil then Exit;
  req := nil;
  g_lock.Enter;
  try
    idx := g_pending.IndexOf(string(callId));
    if idx >= 0 then
    begin
      req := TInvokePending(g_pending.Objects[idx]);
      req.ResultJson := s;
      req.Failed := failed <> 0;
      g_pending.Delete(idx);                    { 摘除 → 迟到/超时竞态由锁串行化 }
      req.Done.SetEvent;
    end;
    { 未命中：ArkTS_InvokeAsync（不等待）或已超时摘除 → 丢弃 }
  finally
    g_lock.Leave;
  end;
end;

{ ── 同步调用 ────────────────────────────────────────────────────────── }
function ArkTS_Invoke(const Method, Params: string; TimeoutMs: Cardinal): string;
var
  callId, json: string;
  req: TInvokePending;
  fn: TArkTsInvokeFn;
  ret: Integer;
  wres: TWaitResult;
  idx: Integer;
begin
  Result := '';
  fn := GetInvokeFn();
  if fn = nil then
  begin
    Result := JsonError('NOT_CONNECTED', 'libfp_bridge.so not connected');
    Exit;
  end;
  if Trim(Method) = '' then
  begin
    Result := JsonError('BAD_ARGS', 'empty method');
    Exit;
  end;

  { ① 先生成 callId 并登记 pending，再调 C++（杜绝"结果先于登记"竞态） }
  g_lock.Enter;
  try
    Inc(g_callSeq);
    callId := 'p_' + IntToStr(g_callSeq);
    req := TInvokePending.Create;
    req.Done := TEvent.Create(nil, False, False, '');
    req.Failed := False;
    g_pending.AddObject(callId, req);
  finally
    g_lock.Leave;
  end;

  try
    { ② 投递（JS 线程重入场景由 C++ 内联快路径立即完成回调） }
    ret := fn(PChar(callId), PChar(Method), PChar(Params));
    if ret <> INVOKE_OK then
    begin
      Result := StatusEnvelope(ret);
      Exit;
    end;

    { ③ 等待结果 }
    wres := req.Done.WaitFor(TimeoutMs);

    { ④ 与回调 happens-before：回调持同一把锁完成写入后才 SetEvent }
    g_lock.Enter;
    try
      json := req.ResultJson;
    finally
      g_lock.Leave;
    end;

    if wres <> wrSignaled then
      Result := JsonError('TIMEOUT',
        Format('arkTS_Invoke timeout %d ms: %s', [TimeoutMs, Method]))
    else
      Result := json;    { 成功串 或 C++ 生成的错误信封（JS_EXCEPTION 等），原样返回 }
  finally
    { ⑤ 超时/出错兜底摘除：迟到回传将因 pending 未命中被安全丢弃 }
    g_lock.Enter;
    try
      idx := g_pending.IndexOf(callId);
      if idx >= 0 then g_pending.Delete(idx);
    finally
      g_lock.Leave;
    end;
    req.Done.Free;
    req.Free;
  end;
end;

{ ── 即发即忘 ────────────────────────────────────────────────────────── }
function ArkTS_InvokeAsync(const Method, Params: string): Integer;
var
  callId: string;
  fn: TArkTsInvokeFn;
begin
  fn := GetInvokeFn();
  if fn = nil then Exit(INVOKE_NO_CONN);
  if Trim(Method) = '' then Exit(INVOKE_BAD_ARGS);
  g_lock.Enter;
  try
    Inc(g_callSeq);
    callId := 'n_' + IntToStr(g_callSeq);   { 不登记 pending，结果由回调丢弃 }
  finally
    g_lock.Leave;
  end;
  Result := fn(PChar(callId), PChar(Method), PChar(Params));
end;

initialization
  { 先建锁/表，再晚注册回调（比 filepicker 更保守：注册即可能被 C++ 触达） }
  g_lock := TCriticalSection.Create;
  g_pending := TStringList.Create;
  pascalApi.arkts_invoke_result := @InvokeResultCallback;
  if gBridgeInitialized then ohos_bridge_connect;   { 已连接则重连，把槽位补进 g_pascal }

finalization
  if g_pending <> nil then
    while g_pending.Count > 0 do
    begin
      TInvokePending(g_pending.Objects[0]).Done.Free;
      TInvokePending(g_pending.Objects[0]).Free;
      g_pending.Delete(0);
    end;
  FreeAndNil(g_pending);
  FreeAndNil(g_lock);

end.
