{
    This unit is part of the fpGUI Toolkit project.

    Copyright (c) 2026 fpGUI OHOS port.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      OpenHarmony (OHOS) adaptation of the FPC SimpleIPC transport layer.

      It reuses the public API and the wire protocol of FPC's `simpleipc`
      unit (TSimpleIPCServer / TSimpleIPCClient / TMsgHeader / TIPCServerMsg)
      and only replaces the platform communication classes. The classes are
      injected through the official extension points
      `DefaultIPCServerClass` / `DefaultIPCClientClass` (same mechanism the
      Unix FIFO and Windows named-pipe implementations use), so existing
      SimpleIPC based code (e.g. fpg_dbugintf, dbugsrv) keeps working
      unchanged.

      Two backends are available, selected per component instance:

        TCP loopback (127.0.0.1)  -- device-wide, default for debugging
          Server:  TSimpleIPCServer.Global       = True
          Client:  TSimpleIPCClient.SystemGlobal = True
          Works between different apps/processes and with PC-side tools
          through `hdc rport tcp:<port> tcp:<port>` port forwarding.

        AF_UNIX stream socket inside the application sandbox
          Server:  TSimpleIPCServer.Global       = False
          Client:  TSimpleIPCClient.SystemGlobal = False
          Same application (same bundle) only. Fastest and most secure.

      The wire protocol is byte-identical to the Unix FIFO implementation:
      a packed TMsgHeader (Version, MsgType, MsgLen) followed by the raw
      payload. This keeps full compatibility with existing SimpleIPC peers
      (e.g. FPC's dbugsrv running on a development PC).

      The unit also compiles on Windows and desktop Linux, which allows
      running a TCP debug server on the development PC.

      Note on OHOS sandbox: the original Unix SimpleIPC backend creates a
      FIFO in GetTempDir() (/tmp), which is not writable inside the OHOS
      application sandbox. That is the reason this unit exists.
}

unit fpg_simpleipc_ohos;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  simpleipc,
  ctypes,
  sockets
  {$IFDEF UNIX}
  , baseunix
  {$ELSE}
  , windows
  {$ENDIF}
  ;

const
  OHOSIPCBasePort   = 40000;  // TCP loopback port range base
  OHOSIPCPortCount  = 10000;  // port range size: 40000..49999
  OHOSIPCIDDirName  = '.ipc'; // AF_UNIX socket directory inside the sandbox
  {$IFDEF UNIX}
  OHOSERR_WOULDBLOCK = EsysEWOULDBLOCK;
  {$ELSE}
  OHOSERR_WOULDBLOCK = 10035;  // WSAEWOULDBLOCK
  {$ENDIF}

type
  {$IFDEF UNIX}
  TOHOSFdSet = TFDSet;
  {$ELSE}
  { Minimal winsock2 fd_set emulation (avoid pulling winsock2 into uses to
    prevent identifier clashes with the sockets unit). NOTE: SOCKET is
    UINT_PTR, i.e. 64-bit on Win64, so fd_array elements must match. }
  TSocketHandle = {$IFDEF CPU64}QWord{$ELSE}cuint32{$ENDIF};
  TWinFdSet = record
    fd_count: cuint32;
    fd_array: array[0..63] of TSocketHandle;  // FD_SETSIZE = 64
  end;
  PWinFdSet = ^TWinFdSet;
  TWinTimeVal = record
    tv_sec: LongInt;
    tv_usec: LongInt;
  end;
  PWinTimeVal = ^TWinTimeVal;
  TOHOSFdSet = TWinFdSet;
  {$ENDIF}

  { ---------------------------------------------------------------------
    TOHOSServerComm
  ---------------------------------------------------------------------}
  TOHOSServerComm = class(TIPCServerComm)
  private
    FUseTCP: Boolean;
    FListenSock: cint;
    FSocketPath: String;
    FHaveReadSet: Boolean;
    FReadSet: TOHOSFdSet;
    FReadMaxFD: cint;
    { Per-client message assembly state (parallel arrays). }
    FClientSock: array of cint;
    FClientHdr: array of TMsgHeader;
    FClientHdrPos: array of Integer;
    FClientData: array of TMemoryStream;
    FClientDataPos: array of Integer;
    procedure AddClient(ASock: cint);
    procedure DropClient(AIndex: Integer);
    procedure CompactClients;
    procedure AcceptPending;
    function ReadAvailable: Boolean;
    function BuildReadSet: Boolean;
    procedure SetupTCP(const AName: String);
    procedure SetupUnix(const AName: String);
  public
    constructor Create(AOwner: TSimpleIPCServer); override;
    destructor Destroy; override;
    procedure StartServer; override;
    procedure StopServer; override;
    function PeekMessage(Timeout: Integer): Boolean; override;
    procedure ReadMessage; override;
    function GetInstanceID: String; override;
  end;

  { ---------------------------------------------------------------------
    TOHOSClientComm
  ---------------------------------------------------------------------}
  TOHOSClientComm = class(TIPCClientComm)
  private
    FUseTCP: Boolean;
    FSock: cint;
    function ConnectSocket: cint;
  public
    constructor Create(AOwner: TSimpleIPCClient); override;
    destructor Destroy; override;
    procedure Connect; override;
    procedure Disconnect; override;
    function ServerRunning: Boolean; override;
    procedure SendMessage(MsgType: TMessageType; Stream: TStream); override;
  end;

{ Maps a SimpleIPC ServerID (+instance suffix) to a TCP loopback port in
  the range 40000..49999. Both server and client must agree on the name. }
function OHOSIPCGetPort(const AName: String): Word;

{ Returns the directory used for AF_UNIX socket files. On OHOS this is a
  ".ipc" subdirectory of the application sandbox; on other platforms it
  falls back to the system temp directory (for local testing). }
function OHOSIPCDataDir: String;

{ Returns the full path of the AF_UNIX socket file for AName. }
function OHOSIPCSocketPath(const AName: String): String;

resourcestring
  SErrOHOSSocketFailed = 'Failed to create IPC socket: %s';
  SErrOHOSBindFailed   = 'Failed to bind IPC endpoint "%s": %s';
  SErrOHOSServerActive = 'IPC server with ID %s is already running';

implementation

{$IFDEF WINDOWS}
{ Minimal winsock2 externals (ws2_32). The sockets unit already performed
  WSAStartup in its initialization. }
function WinSelect(nfds: cint; rfds, wfds, efds: PWinFdSet; tv: PWinTimeVal): cint;
  stdcall; external 'ws2_32.dll' name 'select';
function WinGetLastError: cint;
  stdcall; external 'ws2_32.dll' name 'WSAGetLastError';
function WinIoctlSocket(s: cint; cmd: cint; var arg: cuint32): cint;
  stdcall; external 'ws2_32.dll' name 'ioctlsocket';
{$ENDIF}

{ ---------------------------------------------------------------------
  Small helpers
  ---------------------------------------------------------------------}

function OHOSCRC32(const S: String): Cardinal;
{ CRC-32 (IEEE 802.3), bitwise implementation - no table needed. }
const
  CRCPoly: Cardinal = $EDB88320;
var
  i, j: Integer;
  c: Cardinal;
begin
  c := Cardinal($FFFFFFFF);
  for i := 1 to Length(S) do
  begin
    c := c xor Ord(S[i]);
    for j := 0 to 7 do
      if (c and 1) <> 0 then
        c := (c shr 1) xor CRCPoly
      else
        c := c shr 1;
  end;
  Result := not c;
end;

function OHOSHTons(V: Word): Word;
{ htons() - all supported targets (x86_64/aarch64, Windows) are little-endian. }
begin
  Result := (V shl 8) or (V shr 8);
end;

function OHOSSocketError: cint;
begin
  {$IFDEF UNIX}
  Result := fpgeterrno;
  {$ELSE}
  Result := WinGetLastError;
  {$ENDIF}
end;

procedure OHOSCloseSocket(S: cint);
begin
  if S < 0 then
    Exit;
  {$IFDEF UNIX}
  fpClose(S);
  {$ELSE}
  CloseSocket(S);
  {$ENDIF}
end;

procedure OHOSSetNonBlocking(S: cint);
{ Puts the socket into non-blocking mode (used for the listening socket so
  that AcceptPending can drain the backlog without blocking). }
{$IFDEF WINDOWS}
const
  FIONBIO: cuint32 = $8004667E;
var
  Arg: cuint32;
{$ENDIF}
begin
  {$IFDEF UNIX}
  { Linux/OHOS (musl) ABI constants: F_SETFL = 4, O_NONBLOCK = $800. }
  fpFcntl(S, 4, $800);
  {$ELSE}
  Arg := 1;
  WinIoctlSocket(S, FIONBIO, Arg);
  {$ENDIF}
end;

procedure OHOSSetNoDelay(S: cint);
{ Disables Nagle's algorithm. On Windows loopback, Nagle + delayed ACK can
  stall and even abort small write pairs (header + payload), which the
  SimpleIPC message framing relies on. }
const
  TCP_NODELAY = 1;
  IPPROTO_TCP = 6;
var
  Opt: cint;
begin
  Opt := 1;
  fpsetsockopt(S, IPPROTO_TCP, TCP_NODELAY, @Opt, SizeOf(Opt));
end;

function OHOSGetProcessID: LongInt;
begin
  {$IFDEF UNIX}
  Result := fpGetPID;
  {$ELSE}
  Result := GetCurrentProcessId;
  {$ENDIF}
end;

function OHOSIPCGetPort(const AName: String): Word;
begin
  Result := OHOSIPCBasePort + (OHOSCRC32(AName) mod OHOSIPCPortCount);
end;

function OHOSIPCDataDir: String;
var
  d: String;
begin
  d := '';
  {$IFDEF OHOS}
  { 应用沙箱可写目录：HOME 已由 fpg_ohos 启动时重定向到 Context.filesDir；
    禁止硬编码 /data/storage/... 绝对路径（官方沙箱规范要求经 Context 获取）。 }
  d := GetEnvironmentVariable('HOME');
  if (d = '') or (not DirectoryExists(d)) then
    d := GetTempDir;
  if (d = '') or (not DirectoryExists(d)) then
    d := GetCurrentDir;
  {$ELSE}
  d := GetTempDir;
  {$ENDIF}
  Result := IncludeTrailingPathDelimiter(d) + OHOSIPCIDDirName;
  if not DirectoryExists(Result) then
    ForceDirectories(Result);
end;

function OHOSIPCSocketPath(const AName: String): String;
const
  MaxSunPath = 107;  // sockaddr_un sun_path[108], last byte is the NUL terminator
{$IFDEF UNIX}
var
  p: String;
{$ENDIF}
begin
  {$IFDEF UNIX}
  p := IncludeTrailingPathDelimiter(OHOSIPCDataDir) + AName;
  if Length(p) > MaxSunPath then
    p := Copy(p, 1, MaxSunPath);
  Result := p;
  {$ELSE}
  Result := '';
  {$ENDIF}
end;

{$IFDEF UNIX}
procedure OHOSFD_ZERO(var S: TOHOSFdSet); inline;
begin
  fpFD_ZERO(S);
end;
procedure OHOSFD_SET(Fd: cint; var S: TOHOSFdSet); inline;
begin
  fpFD_SET(Fd, S);
end;
function OHOSFD_ISSET(Fd: cint; const S: TOHOSFdSet): Boolean; inline;
begin
  Result := fpFD_ISSET(Fd, S) <> 0;
end;
{$ELSE}
procedure OHOSFD_ZERO(var S: TOHOSFdSet); inline;
begin
  S.fd_count := 0;
end;
procedure OHOSFD_SET(Fd: cint; var S: TOHOSFdSet);
var
  i: Integer;
begin
  for i := 0 to Integer(S.fd_count) - 1 do
    if S.fd_array[i] = TSocketHandle(Fd) then
      Exit;
  if S.fd_count < 64 then
  begin
    S.fd_array[S.fd_count] := TSocketHandle(Fd);
    Inc(S.fd_count);
  end;
end;
function OHOSFD_ISSET(Fd: cint; const S: TOHOSFdSet): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to Integer(S.fd_count) - 1 do
    if S.fd_array[i] = TSocketHandle(Fd) then
      Exit(True);
end;
{$ENDIF}

function IPCSelect(var AFdSet: TOHOSFdSet; AMaxFD: cint; ATimeoutMs: Integer): cint;
{ select() wrapper. The fd set is passed by reference on purpose: select()
  modifies it in place so the caller can tell which descriptors are ready. }
{$IFDEF UNIX}
begin
  Result := fpSelect(AMaxFD + 1, @AFdSet, nil, nil, ATimeoutMs);
end;
{$ELSE}
var
  tv: TWinTimeVal;
begin
  if ATimeoutMs < 0 then
    Result := WinSelect(0, @AFdSet, nil, nil, nil)
  else
  begin
    tv.tv_sec := ATimeoutMs div 1000;
    tv.tv_usec := (ATimeoutMs mod 1000) * 1000;
    Result := WinSelect(0, @AFdSet, nil, nil, @tv);
  end;
end;
{$ENDIF}

procedure OHOSSendAll(ASock: cint; ABuf: Pointer; ALen: Integer);
{ Full-write loop; mirrors the blocking semantics of the FIFO backend. }
var
  p: PByte;
  Done: Integer;
  r: ssize_t;
begin
  p := PByte(ABuf);
  Done := 0;
  while Done < ALen do
  begin
    r := fpsend(ASock, p + Done, ALen - Done, 0);
    if r < 0 then
    begin
      if OHOSSocketError = {$IFDEF UNIX}EsysEINTR{$ELSE}10004{WSAEINTR}{$ENDIF} then
        Continue;
      raise EIPCError.CreateFmt('IPC send failed (socket error %d)', [OHOSSocketError]);
    end;
    Inc(Done, r);
  end;
end;

function OHOSTCPConnect(APort: Word): cint;
{ Connects to 127.0.0.1:APort. Returns the connected socket or -1. }
var
  Addr: TInetSockAddr;
  s: cint;
begin
  Result := -1;
  s := fpsocket(AF_INET, SOCK_STREAM, 0);
  if s < 0 then
    Exit;
  OHOSSetNoDelay(s);
  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_port := OHOSHTons(APort);
  Addr.sin_addr.s_addr := $0100007F;   { 127.0.0.1 in network byte order }
  if fpconnect(s, @Addr, SizeOf(Addr)) <> 0 then
  begin
    OHOSCloseSocket(s);
    Exit;
  end;
  Result := s;
end;

{ ---------------------------------------------------------------------
  TOHOSServerComm
  ---------------------------------------------------------------------}

constructor TOHOSServerComm.Create(AOwner: TSimpleIPCServer);
begin
  inherited Create(AOwner);
  FListenSock := -1;
  FSocketPath := '';
  FHaveReadSet := False;
  {$IFDEF UNIX}
  FUseTCP := AOwner.Global;
  {$ELSE}
  FUseTCP := True;
  {$ENDIF}
end;

destructor TOHOSServerComm.Destroy;
begin
  if FListenSock >= 0 then
    StopServer;
  inherited Destroy;
end;

procedure TOHOSServerComm.StartServer;
var
  Name: String;
begin
  Name := Owner.ServerID;
  if not Owner.Global then
    Name := Name + '-' + IntToStr(OHOSGetProcessID);
  if FUseTCP then
    SetupTCP(Name)
  else
    SetupUnix(Name);
end;

procedure TOHOSServerComm.SetupTCP(const AName: String);
var
  Port: Word;
  Addr: TInetSockAddr;
  Opt: cint;
begin
  Port := OHOSIPCGetPort(AName);
  { Detect an already running server. A bind probe alone is not reliable
    on Windows where SO_REUSEADDR permits a second bind of the same port. }
  if OHOSTCPConnect(Port) >= 0 then
    DoError(SErrOHOSServerActive, [Owner.ServerID]);
  FListenSock := fpsocket(AF_INET, SOCK_STREAM, 0);
  if FListenSock < 0 then
    DoError(SErrOHOSSocketFailed, [IntToStr(OHOSSocketError)]);
  Opt := 1;
  fpsetsockopt(FListenSock, SOL_SOCKET, SO_REUSEADDR, @Opt, SizeOf(Opt));
  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_port := OHOSHTons(Port);
  Addr.sin_addr.s_addr := $0100007F;   { 127.0.0.1 in network byte order }
  if fpbind(FListenSock, @Addr, SizeOf(Addr)) <> 0 then
  begin
    if OHOSSocketError = {$IFDEF UNIX}EsysEADDRINUSE{$ELSE}10048{WSAEADDRINUSE}{$ENDIF} then
      DoError(SErrOHOSServerActive, [Owner.ServerID])
    else
      DoError(SErrOHOSBindFailed, [Owner.ServerID, IntToStr(OHOSSocketError)]);
  end;
  if fplisten(FListenSock, 16) <> 0 then
    DoError(SErrOHOSBindFailed, [Owner.ServerID, IntToStr(OHOSSocketError)]);
  { Non-blocking listen socket so AcceptPending can drain the backlog
    without blocking on an empty accept queue. }
  OHOSSetNonBlocking(FListenSock);
end;

procedure TOHOSServerComm.SetupUnix(const AName: String);
{$IFDEF UNIX}
var
  Addr: TUnixSockAddr;
  L: Integer;
{$ENDIF}
begin
  {$IFDEF UNIX}
  FSocketPath := OHOSIPCSocketPath(AName);
  { Remove a stale socket file left behind by a crashed server. }
  fpUnlink(PAnsiChar(FSocketPath));
  FListenSock := fpsocket(AF_UNIX, SOCK_STREAM, 0);
  if FListenSock < 0 then
    DoError(SErrOHOSSocketFailed, [IntToStr(OHOSSocketError)]);
  FillChar(Addr, SizeOf(Addr), 0);
  Addr.family := AF_UNIX;
  L := Length(FSocketPath);
  if L > High(Addr.path) then
    L := High(Addr.path);
  Move(PAnsiChar(FSocketPath)^, Addr.path[0], L);
  if fpbind(FListenSock, @Addr, SizeOf(Addr.family) + L) <> 0 then
    DoError(SErrOHOSBindFailed, [Owner.ServerID, IntToStr(OHOSSocketError)]);
  if fplisten(FListenSock, 16) <> 0 then
    DoError(SErrOHOSBindFailed, [Owner.ServerID, IntToStr(OHOSSocketError)]);
  OHOSSetNonBlocking(FListenSock);
  {$ELSE}
  { AF_UNIX is not available on Windows; the TCP backend is always used. }
  DoError(SErrOHOSBindFailed, [Owner.ServerID, 'AF_UNIX unsupported']);
  {$ENDIF}
end;

procedure TOHOSServerComm.StopServer;
var
  i: Integer;
begin
  for i := 0 to High(FClientSock) do
    OHOSCloseSocket(FClientSock[i]);
  SetLength(FClientSock, 0);
  for i := 0 to High(FClientData) do
    if FClientData[i] <> nil then
      FClientData[i].Free;
  SetLength(FClientData, 0);
  SetLength(FClientHdr, 0);
  SetLength(FClientHdrPos, 0);
  SetLength(FClientDataPos, 0);
  if FListenSock >= 0 then
  begin
    OHOSCloseSocket(FListenSock);
    FListenSock := -1;
  end;
  if FSocketPath <> '' then
  begin
    {$IFDEF UNIX}
    fpUnlink(PAnsiChar(FSocketPath));
    {$ENDIF}
    FSocketPath := '';
  end;
end;

procedure TOHOSServerComm.AddClient(ASock: cint);
var
  L: Integer;
begin
  L := Length(FClientSock);
  SetLength(FClientSock, L + 1);
  SetLength(FClientHdr, L + 1);
  SetLength(FClientHdrPos, L + 1);
  SetLength(FClientData, L + 1);
  SetLength(FClientDataPos, L + 1);
  FClientSock[L] := ASock;
  FClientHdrPos[L] := 0;
  FClientData[L] := nil;
  FClientDataPos[L] := 0;
end;

procedure TOHOSServerComm.DropClient(AIndex: Integer);
{ Marks the client at AIndex as dead (sock < 0). Actual removal from the
  arrays happens in CompactClients, which is called after the read pass.
  This keeps array indices stable while a message is being assembled. }
begin
  if FClientSock[AIndex] >= 0 then
    OHOSCloseSocket(FClientSock[AIndex]);
  FClientSock[AIndex] := -1;
  if FClientData[AIndex] <> nil then
  begin
    FClientData[AIndex].Free;
    FClientData[AIndex] := nil;
  end;
  FClientHdrPos[AIndex] := 0;
  FClientDataPos[AIndex] := 0;
end;

procedure TOHOSServerComm.CompactClients;
var
  Src, Dst: Integer;
begin
  Dst := 0;
  for Src := 0 to High(FClientSock) do
    if FClientSock[Src] >= 0 then
    begin
      if Src <> Dst then
      begin
        FClientSock[Dst] := FClientSock[Src];
        FClientHdr[Dst] := FClientHdr[Src];
        FClientHdrPos[Dst] := FClientHdrPos[Src];
        FClientData[Dst] := FClientData[Src];
        FClientDataPos[Dst] := FClientDataPos[Src];
      end;
      Inc(Dst);
    end;
  SetLength(FClientSock, Dst);
  SetLength(FClientHdr, Dst);
  SetLength(FClientHdrPos, Dst);
  SetLength(FClientData, Dst);
  SetLength(FClientDataPos, Dst);
end;

function TOHOSServerComm.BuildReadSet: Boolean;
var
  i: Integer;
begin
  OHOSFD_ZERO(FReadSet);
  FReadMaxFD := -1;
  OHOSFD_SET(FListenSock, FReadSet);
  FReadMaxFD := FListenSock;
  for i := 0 to High(FClientSock) do
  begin
    OHOSFD_SET(FClientSock[i], FReadSet);
    if FClientSock[i] > FReadMaxFD then
      FReadMaxFD := FClientSock[i];
  end;
  Result := True;
end;

procedure TOHOSServerComm.AcceptPending;
{ Accepts every connection that is currently pending. The listening socket
  is non-blocking, so the loop stops cleanly once the backlog is empty. }
var
  s: cint;
begin
  if not OHOSFD_ISSET(FListenSock, FReadSet) then
    Exit;
  repeat
    s := fpaccept(FListenSock, nil, nil);
    if s < 0 then
      Break;   { no more pending connections (EWOULDBLOCK) or transient error }
    OHOSSetNoDelay(s);
    { Make the accepted socket non-blocking too: on Windows it inherits the
      listen socket's FIONBIO state, and on Unix it starts blocking. The
      read path handles WSAEWOULDBLOCK/EWOULDBLOCK as "not ready yet" and
      never blocks. }
    OHOSSetNonBlocking(s);
    AddClient(s);
  until Length(FClientSock) >= 64;   { safety bound }
end;

function TOHOSServerComm.ReadAvailable: Boolean;
var
  i: Integer;
  n: ssize_t;
  Buf: array[0..4095] of Byte;
  ToRead: Integer;
begin
  Result := False;
  i := 0;
  while i <= High(FClientSock) do
  begin
    if not OHOSFD_ISSET(FClientSock[i], FReadSet) then
    begin
      Inc(i);
      Continue;
    end;
    { Header phase: assemble the fixed-size TMsgHeader. }
    while FClientHdrPos[i] < SizeOf(TMsgHeader) do
    begin
      n := fprecv(FClientSock[i], @PByte(@FClientHdr[i])[FClientHdrPos[i]],
                  SizeOf(TMsgHeader) - FClientHdrPos[i], 0);
      if n < 0 then
      begin
        if OHOSSocketError = OHOSERR_WOULDBLOCK then
          Break;   { data not (yet) available: keep the partial state, retry next cycle }
        DropClient(i);   { hard error or peer closed }
        Break;
      end;
      if n = 0 then
      begin
        DropClient(i);   { peer closed }
        Break;
      end;
      Inc(FClientHdrPos[i], n);
    end;
    if FClientSock[i] < 0 then
    begin
      Inc(i);
      Continue;
    end;
    if FClientHdrPos[i] < SizeOf(TMsgHeader) then
    begin
      Inc(i);
      Continue;   { header incomplete (should not happen after select) }
    end;
    { Payload phase: read exactly Hdr.MsgLen bytes. }
    if FClientData[i] = nil then
      FClientData[i] := TMemoryStream.Create;
    while FClientDataPos[i] < FClientHdr[i].MsgLen do
    begin
      ToRead := SizeOf(Buf);
      if ToRead > FClientHdr[i].MsgLen - FClientDataPos[i] then
        ToRead := FClientHdr[i].MsgLen - FClientDataPos[i];
      n := fprecv(FClientSock[i], @Buf, ToRead, 0);
      if n < 0 then
      begin
        if OHOSSocketError = OHOSERR_WOULDBLOCK then
          Break;   { data not (yet) available: keep the partial state, retry next cycle }
        DropClient(i);
        Break;           { payload loop: continue with the next client }
      end;
      if n = 0 then
      begin
        DropClient(i);
        Break;
      end;
      FClientData[i].WriteBuffer(Buf, n);
      Inc(FClientDataPos[i], n);
    end;
    if FClientSock[i] < 0 then
    begin
      Inc(i);
      Continue;
    end;
    if FClientDataPos[i] < FClientHdr[i].MsgLen then
    begin
      Inc(i);
      Continue;   { payload incomplete (should not happen after select) }
    end;
    { Complete message: push one message and reset the client state. }
    FClientData[i].Seek(0, soFromBeginning);
    PushMessage(FClientHdr[i], FClientData[i]);
    FClientData[i].Free;
    FClientData[i] := nil;
    FClientDataPos[i] := 0;
    FClientHdrPos[i] := 0;
    Result := True;
    Break;   { one message per ReadMessage call }
  end;
  { Remove clients that were dropped during this pass. }
  CompactClients;
end;

function TOHOSServerComm.PeekMessage(Timeout: Integer): Boolean;
var
  n: cint;
begin
  Result := False;
  if FListenSock < 0 then
    Exit;
  BuildReadSet;
  FHaveReadSet := True;
  n := IPCSelect(FReadSet, FReadMaxFD, Timeout);
  if n < 0 then
  begin
    { Transient error (e.g. EINTR); the next call retries. }
    Result := False;
    Exit;
  end;
  Result := n > 0;
end;

procedure TOHOSServerComm.ReadMessage;
begin
  if FListenSock < 0 then
    Exit;
  if not FHaveReadSet then
  begin
    { Defensive: called without a preceding PeekMessage. }
    BuildReadSet;
    IPCSelect(FReadSet, FReadMaxFD, 0);
  end;
  AcceptPending;
  { Refresh the ready set: select() modifies the set to contain only ready
    descriptors, so the just-accepted sockets are not part of it yet. A
    zero-timeout re-select yields the current ready set without waiting. }
  BuildReadSet;
  IPCSelect(FReadSet, FReadMaxFD, 0);
  ReadAvailable;
  FHaveReadSet := False;
end;

function TOHOSServerComm.GetInstanceID: String;
begin
  Result := IntToStr(OHOSGetProcessID);
end;

{ ---------------------------------------------------------------------
  TOHOSClientComm
  ---------------------------------------------------------------------}

constructor TOHOSClientComm.Create(AOwner: TSimpleIPCClient);
begin
  inherited Create(AOwner);
  FSock := -1;
  {$IFDEF UNIX}
  FUseTCP := AOwner.SystemGlobal;
  {$ELSE}
  FUseTCP := True;
  {$ENDIF}
end;

destructor TOHOSClientComm.Destroy;
begin
  Disconnect;
  inherited Destroy;
end;

procedure TOHOSClientComm.Disconnect;
begin
  if FSock >= 0 then
  begin
    OHOSCloseSocket(FSock);
    FSock := -1;
  end;
end;

function TOHOSClientComm.ConnectSocket: cint;
var
  Name: String;
  {$IFDEF UNIX}
  Path: String;
  UAddr: TUnixSockAddr;
  L: Integer;
  s: cint;
  {$ENDIF}
begin
  Result := -1;
  Name := Owner.ServerID;
  if Owner.ServerInstance <> '' then
    Name := Name + '-' + Owner.ServerInstance;
  if FUseTCP then
    Result := OHOSTCPConnect(OHOSIPCGetPort(Name))
  else
  begin
    {$IFDEF UNIX}
    s := fpsocket(AF_UNIX, SOCK_STREAM, 0);
    if s < 0 then
      Exit;
    Path := OHOSIPCSocketPath(Name);
    FillChar(UAddr, SizeOf(UAddr), 0);
    UAddr.family := AF_UNIX;
    L := Length(Path);
    if L > High(UAddr.path) then
      L := High(UAddr.path);
    Move(PAnsiChar(Path)^, UAddr.path[0], L);
    if fpconnect(s, @UAddr, SizeOf(UAddr.family) + L) <> 0 then
    begin
      OHOSCloseSocket(s);
      Exit;
    end;
    Result := s;
    {$ENDIF}
  end;
end;

procedure TOHOSClientComm.Connect;
begin
  FSock := ConnectSocket;
  if FSock < 0 then
    DoError(SErrServerNotActive, [Owner.ServerID]);
end;

function TOHOSClientComm.ServerRunning: Boolean;
var
  s: cint;
begin
  s := ConnectSocket;
  if s >= 0 then
  begin
    OHOSCloseSocket(s);
    Result := True;
  end
  else
    Result := False;
end;

procedure TOHOSClientComm.SendMessage(MsgType: TMessageType; Stream: TStream);
var
  Hdr: TMsgHeader;
  Buf: array[0..4095] of Byte;
  n: Integer;
begin
  if FSock < 0 then
    DoError(SErrServerNotActive, [Owner.ServerID]);
  Hdr.Version := MsgVersion;
  Hdr.MsgType := MsgType;
  Hdr.MsgLen := Stream.Size;
  OHOSSendAll(FSock, @Hdr, SizeOf(Hdr));
  Stream.Position := 0;
  while Stream.Position < Stream.Size do
  begin
    n := Stream.Read(Buf, SizeOf(Buf));
    OHOSSendAll(FSock, @Buf, n);
  end;
end;

initialization
  DefaultIPCServerClass := TOHOSServerComm;
  DefaultIPCClientClass := TOHOSClientComm;
  {$IFDEF UNIX}
  { musl (used by OHOS) terminates the process on SIGPIPE by default.
    A debug client writing to a dead server must not kill the application. }
  fpSignal(SIGPIPE, SignalHandler(SIG_IGN));
  {$ENDIF}

end.