{
    This unit is part of the fpGUI Toolkit project.

    Copyright (c) 2026 fpGUI OHOS port.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      Binder (IPC Kit) transport backend for SimpleIPC on OHOS.

      Maps the one-way SimpleIPC message stream onto Binder transactions:
        - each message becomes one ASYNC transaction (fire-and-forget)
        - the TMsgHeader + raw payload are carried in the parcel via
          OH_IPCParcel_WriteBuffer / ReadBuffer (same wire framing as the
          TCP / AF_UNIX / PC-side backends)
        - ServerRunning is a SYNC ping transaction
      The server side hosts an OHIPCRemoteStub whose OnRemoteRequest callback
      (pure Pascal) pushes reconstructed messages into the TSimpleIPCServer
      queue. Because the callback runs on a Binder worker thread, the server
      MUST be started in threaded mode (TSimpleIPCServer.Threaded := True),
      whose queue lock / add-event make PushMessage cross-thread safe.

      Requirements:
        - API 12+ (IPC Kit C API), SystemCapability.Communication.IPC.Core
        - the C++ bridge (libfp_bridge.so) provides the proxy handle
          (native child process for P1, ServiceExtensionAbility for P2) and
          calls back into this unit via ohos_binder_on_proxy.
      When the bridge / proxy is unavailable, callers should fall back to the
      TCP / AF_UNIX backend (see fpg_simpleipc_ohos).
}

unit fpg_simpleipc_ohos_binder;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  simpleipc,
  fpg_ohos_ipc_kit;

const
  { Interface descriptor used by the stub/proxy and interface-token check. }
  BINDER_DESCRIPTOR = 'fpGUI.SimpleIPC';

  { Transaction codes (range [0x01, 0x00ffffff]) }
  BINDER_MSG_SEND = 1;   { one-way message (ASYNC) }
  BINDER_MSG_PING = 2;   { liveness probe (SYNC)   }

  { Safety cap for a single message (Binder transaction size limit). }
  BINDER_MAX_MESSAGE = 1 * 1024 * 1024;

type
  { ---------------------------------------------------------------------
    TOHOSBinderServerComm
  ---------------------------------------------------------------------}
  TOHOSBinderServerComm = class(TIPCServerComm)
  private
    FStub: POHIPCRemoteStub;
    FStarted: Boolean;
  public
    constructor Create(AOwner: TSimpleIPCServer); override;
    destructor Destroy; override;
    procedure StartServer; override;
    procedure StopServer; override;
    function PeekMessage(Timeout: Integer): Boolean; override;
    procedure ReadMessage; override;
    function GetInstanceID: String; override;
    { Called from the (pure Pascal) stub callback to hand a reconstructed
      message to the SimpleIPC queue. }
    procedure BinderPushMessage(const AHdr: TMsgHeader; APayload: TStream);
    property Stub: POHIPCRemoteStub read FStub;
  end;

  { ---------------------------------------------------------------------
    TOHOSBinderClientComm
  ---------------------------------------------------------------------}
  TOHOSBinderClientComm = class(TIPCClientComm)
  private
    FProxy: POHIPCRemoteProxy;
    FConnected: Boolean;
  public
    constructor Create(AOwner: TSimpleIPCClient); override;
    destructor Destroy; override;
    procedure Connect; override;
    procedure Disconnect; override;
    function ServerRunning: Boolean; override;
    procedure SendMessage(MsgType: TMessageType; Stream: TStream); override;
  end;

{ Switches the injected default comm classes to the Binder backend.
  Call before creating TSimpleIPCServer / TSimpleIPCClient components. }
procedure OHOSIPCEnableBinder;

{ The C++ bridge calls these Pascal-exported entry points. }
procedure ohos_binder_on_proxy(AProxy: Pointer); cdecl; export;
procedure ohos_binder_on_dead; cdecl; export;

{ Bridge proxy accessor (nil when no proxy has been delivered yet). }
function OHOSIPCGetBinderProxy: Pointer;

{ Waits up to ATimeoutMs for the bridge to deliver the proxy. }
function OHOSIPCBinderWaitProxy(ATimeoutMs: Integer): Boolean;

{ Resolves + invokes the C++ bridge function that spawns the native child
  process hosting the server (P1). Returns True if it could be invoked. }
function OHOSBinderSpawnServer: Boolean;

{ ---------------------------------------------------------------------
  Native child process hosting (P1).
  The child process loads the same libhelloworld.so. It exports
  NativeChildProcess_OnConnect (returns the stub) and
  NativeChildProcessMainProc (runs the server loop). These helpers drive a
  threaded TSimpleIPCServer whose OnRemoteRequest callback (pure Pascal)
  pushes messages into the SimpleIPC queue.
  ---------------------------------------------------------------------}

{ Creates (once) a threaded TSimpleIPCServer with the Binder backend and
  returns the OHIPCRemoteStub handle for NativeChildProcess_OnConnect. }
function OHOSBinderStartChildServer(const AServerID: String;
  AOnMessage: TNotifyEvent): Pointer;
{ Runs the SimpleIPC server message loop until terminated. }
procedure OHOSBinderRunChildLoop(ATimeoutMs: Integer);
{ Stops and frees the child-process server. }
procedure OHOSBinderStopChildServer;

resourcestring
  SErrBinderNoProxy   = 'Binder proxy not available for server ID %s';
  SErrBinderStub      = 'Failed to create IPC binder stub';
  SErrBinderKitUnavailable = 'IPC Kit not available on this device (API 12+ required): %s';

implementation

uses
  ctypes
  {$IFDEF UNIX}
  , baseunix
  {$ENDIF}
  ;

const
  RTLD_LAZY = 1;

var
  gBinderProxy: Pointer = nil;
  gBridgeHandle: Pointer = nil;
  gChildServer: TSimpleIPCServer = nil;
  gLastServerStub: Pointer = nil;

{ ---------------------------------------------------------------------
  Bridge helpers (dlsym from libfp_bridge.so, same pattern as fpg_ohos)
  ---------------------------------------------------------------------}

function dlopen(__filename: PChar; __mode: Integer): Pointer; cdecl; external 'c';
function dlsym(__handle: Pointer; __name: PChar): Pointer; cdecl; external 'c';

function BinderBridgeSym(const AName: PChar): Pointer;
begin
  Result := nil;
  if gBridgeHandle = nil then
    gBridgeHandle := dlopen('libfp_bridge.so', RTLD_LAZY);
  if gBridgeHandle <> nil then
    Result := dlsym(gBridgeHandle, AName);
end;

type
  TBinderSpawnServerFn = function: cint; cdecl;

function OHOSBinderSpawnServer: Boolean;
var
  Fn: TBinderSpawnServerFn;
begin
  Result := False;
  Fn := TBinderSpawnServerFn(BinderBridgeSym('ohos_binder_spawn_server'));
  if Assigned(Fn) then
    Result := Fn() = 0;
end;

procedure OHOSIPCEnableBinder;
begin
  DefaultIPCServerClass := TOHOSBinderServerComm;
  DefaultIPCClientClass := TOHOSBinderClientComm;
end;

function OHOSBinderStartChildServer(const AServerID: String;
  AOnMessage: TNotifyEvent): Pointer;
begin
  Result := nil;
  if gChildServer = nil then
  begin
    OHOSIPCEnableBinder;
    gChildServer := TSimpleIPCServer.Create(nil);
    gChildServer.ServerID := AServerID;
    gChildServer.Threaded := True;   { Binder stub callbacks are cross-thread }
    gChildServer.OnMessage := AOnMessage;
    gChildServer.StartServer;
  end;
  if (gChildServer <> nil) then
    Result := gLastServerStub;
end;

procedure OHOSBinderRunChildLoop(ATimeoutMs: Integer);
begin
  while (gChildServer <> nil) do
  begin
    { Threaded mode: PeekMessage waits on the queue-add event and delivers
      messages to OnMessage. }
    gChildServer.PeekMessage(ATimeoutMs, True);
  end;
end;

procedure OHOSBinderStopChildServer;
begin
  if gChildServer <> nil then
  begin
    gChildServer.StopServer;
    FreeAndNil(gChildServer);
  end;
end;

procedure ohos_binder_on_proxy(AProxy: Pointer); cdecl; export;
begin
  gBinderProxy := AProxy;
end;

procedure ohos_binder_on_dead; cdecl; export;
begin
  gBinderProxy := nil;
end;

function OHOSIPCGetBinderProxy: Pointer;
begin
  Result := gBinderProxy;
end;

function OHOSIPCBinderWaitProxy(ATimeoutMs: Integer): Boolean;
var
  Elapsed: Integer;
begin
  Result := False;
  Elapsed := 0;
  while (gBinderProxy = nil) and (Elapsed < ATimeoutMs) do
  begin
    Sleep(50);
    Inc(Elapsed, 50);
  end;
  Result := gBinderProxy <> nil;
end;

{ ---------------------------------------------------------------------
  Stub callback (pure Pascal). Runs on a Binder worker thread.
  ---------------------------------------------------------------------}

function BinderOnRemoteRequest(ACode: cuint32; const AData: POHIPCParcel;
  AReply: POHIPCParcel; AUserData: Pointer): cint; cdecl;
var
  Comm: TOHOSBinderServerComm;
  Hdr: TMsgHeader;
  HdrPtr, PayPtr: PByte;
  Pay: TMemoryStream;
begin
  Result := OH_IPC_CHECK_PARAM_ERROR;
  if AUserData = nil then
    Exit;
  Comm := TOHOSBinderServerComm(AUserData);
  case ACode of
    BINDER_MSG_PING:
      begin
        { Liveness probe: reply with a single byte. }
        Result := OH_IPCParcel_WriteInt8(AReply, 1);
      end;

    BINDER_MSG_SEND:
      begin
        { Read the fixed TMsgHeader then the raw payload. }
        HdrPtr := OH_IPCParcel_ReadBuffer(AData, SizeOf(TMsgHeader));
        if HdrPtr = nil then
          Exit;
        Move(HdrPtr^, Hdr, SizeOf(TMsgHeader));
        if (Hdr.Version <> MsgVersion) or (Hdr.MsgLen < 0) or
           (Hdr.MsgLen > BINDER_MAX_MESSAGE) then
          Exit;
        Pay := TMemoryStream.Create;
        try
          if Hdr.MsgLen > 0 then
          begin
            PayPtr := OH_IPCParcel_ReadBuffer(AData, cint32(Hdr.MsgLen));
            if PayPtr = nil then
              Exit;
            Pay.WriteBuffer(PayPtr^, Hdr.MsgLen);
          end;
          Pay.Seek(0, soFromBeginning);
          Comm.BinderPushMessage(Hdr, Pay);
          Result := OH_IPC_SUCCESS;
        finally
          Pay.Free;
        end;
      end;

  else
    Result := OH_IPC_CODE_OUT_OF_RANGE;
  end;
end;

{ ---------------------------------------------------------------------
  TOHOSBinderServerComm
  ---------------------------------------------------------------------}

constructor TOHOSBinderServerComm.Create(AOwner: TSimpleIPCServer);
begin
  inherited Create(AOwner);
  FStub := nil;
  FStarted := False;
end;

destructor TOHOSBinderServerComm.Destroy;
begin
  if FStarted then
    StopServer;
  inherited Destroy;
end;

procedure TOHOSBinderServerComm.StartServer;
begin
  if FStarted then
    Exit;
  if not OHOSIPCKitAvailable then
    DoError(SErrBinderKitUnavailable, [OHOSIPCKitError]);
  FStub := OH_IPCRemoteStub_Create(BINDER_DESCRIPTOR, @BinderOnRemoteRequest, nil, Self);
  if FStub = nil then
    DoError(SErrBinderStub, []);
  gLastServerStub := FStub;
  FStarted := True;
end;

procedure TOHOSBinderServerComm.StopServer;
begin
  if FStub <> nil then
  begin
    OH_IPCRemoteStub_Destroy(FStub);
    FStub := nil;
  end;
  gLastServerStub := nil;
  FStarted := False;
end;

function TOHOSBinderServerComm.PeekMessage(Timeout: Integer): Boolean;
begin
  { Messages arrive via the stub callback, which pushes straight into the
    SimpleIPC queue (threaded mode). No polling is needed; just avoid a
    busy-spin in the server thread. }
  if Timeout > 0 then
    Sleep(Timeout);
  Result := False;
end;

procedure TOHOSBinderServerComm.ReadMessage;
begin
  { Nothing to read directly; the callback already pushed the message. }
end;

function TOHOSBinderServerComm.GetInstanceID: String;
begin
  Result := 'binder:' + IntToStr(Integer(OH_IPCSkeleton_GetSelfTokenId));
end;

procedure TOHOSBinderServerComm.BinderPushMessage(const AHdr: TMsgHeader;
  APayload: TStream);
begin
  PushMessage(AHdr, APayload);
end;

{ ---------------------------------------------------------------------
  TOHOSBinderClientComm
  ---------------------------------------------------------------------}

constructor TOHOSBinderClientComm.Create(AOwner: TSimpleIPCClient);
begin
  inherited Create(AOwner);
  FProxy := nil;
  FConnected := False;
end;

destructor TOHOSBinderClientComm.Destroy;
begin
  Disconnect;
  inherited Destroy;
end;

procedure TOHOSBinderClientComm.Connect;
begin
  if FConnected then
    Exit;
  if not OHOSIPCKitAvailable then
    DoError(SErrBinderKitUnavailable, [OHOSIPCKitError]);
  FProxy := POHIPCRemoteProxy(gBinderProxy);
  if FProxy = nil then
    DoError(SErrBinderNoProxy, [Owner.ServerID]);
  FConnected := True;
end;

procedure TOHOSBinderClientComm.Disconnect;
begin
  { The proxy handle is owned by the C++ bridge; just drop our reference. }
  FProxy := nil;
  FConnected := False;
end;

function TOHOSBinderClientComm.ServerRunning: Boolean;
var
  Proxy: POHIPCRemoteProxy;
  Parcel, Reply: POHIPCParcel;
  Opt: TOH_IPC_MessageOption;
  Ret: cint;
  V: cint8;
begin
  Result := False;
  Proxy := POHIPCRemoteProxy(gBinderProxy);
  if Proxy = nil then
    Exit;
  Parcel := OH_IPCParcel_Create;
  Reply := OH_IPCParcel_Create;
  if (Parcel = nil) or (Reply = nil) then
  begin
    if Parcel <> nil then OH_IPCParcel_Destroy(Parcel);
    if Reply <> nil then OH_IPCParcel_Destroy(Reply);
    Exit;
  end;
  try
    OH_IPCParcel_WriteInterfaceToken(Parcel, BINDER_DESCRIPTOR);
    Opt.mode := OH_IPC_REQUEST_MODE_SYNC;
    Opt.timeout := 0;
    Opt.reserved := nil;
    Ret := OH_IPCRemoteProxy_SendRequest(Proxy, BINDER_MSG_PING, Parcel, Reply, @Opt);
    Result := (Ret = OH_IPC_SUCCESS) and
              (OH_IPCParcel_ReadInt8(Reply, @V) = OH_IPC_SUCCESS);
  finally
    OH_IPCParcel_Destroy(Parcel);
    OH_IPCParcel_Destroy(Reply);
  end;
end;

procedure TOHOSBinderClientComm.SendMessage(MsgType: TMessageType; Stream: TStream);
var
  Parcel: POHIPCParcel;
  Opt: TOH_IPC_MessageOption;
  Hdr: TMsgHeader;
  Buf: array[0..4095] of Byte;
  n: Integer;
  Ret: cint;
begin
  if (not FConnected) or (FProxy = nil) then
    DoError(SErrBinderNoProxy, [Owner.ServerID]);
  Parcel := OH_IPCParcel_Create;
  if Parcel = nil then
    raise EIPCError.Create('Failed to create IPC parcel');
  try
    OH_IPCParcel_WriteInterfaceToken(Parcel, BINDER_DESCRIPTOR);
    Hdr.Version := MsgVersion;
    Hdr.MsgType := MsgType;
    Hdr.MsgLen := Stream.Size;
    if Hdr.MsgLen > BINDER_MAX_MESSAGE then
      raise EIPCError.CreateFmt('Binder message too large (%d bytes)', [Hdr.MsgLen]);
    OH_IPCParcel_WriteBuffer(Parcel, PByte(@Hdr), SizeOf(TMsgHeader));
    Stream.Position := 0;
    while Stream.Position < Stream.Size do
    begin
      n := Stream.Read(Buf, SizeOf(Buf));
      OH_IPCParcel_WriteBuffer(Parcel, @Buf, n);
    end;
    Opt.mode := OH_IPC_REQUEST_MODE_ASYNC;
    Opt.timeout := 0;
    Opt.reserved := nil;
    Ret := OH_IPCRemoteProxy_SendRequest(FProxy, BINDER_MSG_SEND, Parcel, nil, @Opt);
    if Ret <> OH_IPC_SUCCESS then
      raise EIPCError.CreateFmt('IPC binder send failed (error %d)', [Ret]);
  finally
    OH_IPCParcel_Destroy(Parcel);
  end;
end;

end.