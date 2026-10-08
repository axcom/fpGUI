{
    This unit is part of the fpGUI Toolkit project.

    Copyright (c) 2026 fpGUI OHOS port.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      HarmonyOS IPC Kit (Binder) C API Pascal bindings.
      Translated from the NDK headers under IPCKit/:
        ipc_cparcel.h, ipc_cremote_object.h, ipc_cskeleton.h, ipc_error_code.h
      Library: libipc_capi.so  (API 12+, SystemCapability.Communication.IPC.Core)

      IMPORTANT: the library is loaded LAZILY at runtime (dlopen + dlsym),
      NOT linked at build time. This keeps libhelloworld.so loadable on
      devices/emulator images that do not ship libipc_capi.so (OpenHarmony
      < API 12 or stripped images): the Binder backend then degrades
      gracefully (OHOSIPCKitAvailable = False) instead of failing the
      dlopen of the whole Pascal library.
      Use OHOSIPCKitLoad / OHOSIPCKitAvailable before calling any OH_* API.
}

unit fpg_ohos_ipc_kit;

{$mode objfpc}{$H+}

interface

uses
  CTypes;

const
  LIB_IPC = 'libipc_capi.so';

  { OH_IPC_RequestMode (C enum = int) }
  OH_IPC_REQUEST_MODE_SYNC  = 0;
  OH_IPC_REQUEST_MODE_ASYNC = 1;

  { OH_IPC_ErrorCode }
  OH_IPC_SUCCESS               = 0;
  OH_IPC_ERROR_CODE_BASE       = 1901000;
  OH_IPC_CHECK_PARAM_ERROR     = 1901000;
  OH_IPC_PARCEL_WRITE_ERROR    = 1901001;
  OH_IPC_PARCEL_READ_ERROR     = 1901002;
  OH_IPC_MEM_ALLOCATOR_ERROR   = 1901003;
  OH_IPC_CODE_OUT_OF_RANGE     = 1901004;
  OH_IPC_DEAD_REMOTE_OBJECT    = 1901005;
  OH_IPC_INVALID_USER_ERROR_CODE = 1901006;
  OH_IPC_INNER_ERROR           = 1901007;
  OH_IPC_ERROR_CODE_MAX        = 1902000;
  OH_IPC_USER_ERROR_CODE_MIN   = 1909000;
  OH_IPC_USER_ERROR_CODE_MAX   = 1909999;

type
  { Opaque handle types (pointers to incomplete C structs) }
  POHIPCParcel       = type Pointer;   { OHIPCParcel*  }
  POHIPCRemoteStub   = type Pointer;   { OHIPCRemoteStub*  }
  POHIPCRemoteProxy  = type Pointer;   { OHIPCRemoteProxy* }
  POHIPCDeathRecipient = type Pointer; { OHIPCDeathRecipient* }

  { OH_IPC_MemAllocator }
  TOH_IPC_MemAllocator = function(ALen: cint32): Pointer; cdecl;

  { Callbacks }
  TOH_OnRemoteRequestCallback = function(ACode: cuint32; const AData: POHIPCParcel;
    AReply: POHIPCParcel; AUserData: Pointer): cint; cdecl;
  TOH_OnRemoteDestroyCallback = procedure(AUserData: Pointer); cdecl;
  TOH_OnDeathRecipientCallback = procedure(AUserData: Pointer); cdecl;
  TOH_OnDeathRecipientDestroyCallback = procedure(AUserData: Pointer); cdecl;

  { OH_IPC_MessageOption (C: #pragma pack(4)) }
  POH_IPC_MessageOption = ^TOH_IPC_MessageOption;
  TOH_IPC_MessageOption = packed record
    mode: cint;          { OH_IPC_RequestMode (int) }
    timeout: cuint32;    { reserved for RPC; invalid for IPC }
    reserved: Pointer;   { must be NULL }
  end;

{ Loads libipc_capi.so and resolves all symbols (idempotent). }
procedure OHOSIPCKitLoad;
{ True once all IPCKit symbols have been resolved successfully. }
function  OHOSIPCKitAvailable: Boolean;
{ Human-readable reason when the kit could not be loaded. }
function  OHOSIPCKitError: String;

{ ---------------------------------------------------------------------
  Parcel
  ---------------------------------------------------------------------}
function  OH_IPCParcel_Create: POHIPCParcel;
procedure OH_IPCParcel_Destroy(parcel: POHIPCParcel);
function  OH_IPCParcel_GetDataSize(const parcel: POHIPCParcel): cint;
function  OH_IPCParcel_GetWritableBytes(const parcel: POHIPCParcel): cint;
function  OH_IPCParcel_GetReadableBytes(const parcel: POHIPCParcel): cint;
function  OH_IPCParcel_GetReadPosition(const parcel: POHIPCParcel): cint;
function  OH_IPCParcel_GetWritePosition(const parcel: POHIPCParcel): cint;
function  OH_IPCParcel_RewindReadPosition(parcel: POHIPCParcel; newReadPos: cuint32): cint;
function  OH_IPCParcel_RewindWritePosition(parcel: POHIPCParcel; newWritePos: cuint32): cint;
function  OH_IPCParcel_WriteInt8(parcel: POHIPCParcel; value: cint8): cint;
function  OH_IPCParcel_ReadInt8(const parcel: POHIPCParcel; value: pcint8): cint;
function  OH_IPCParcel_WriteInt16(parcel: POHIPCParcel; value: cint16): cint;
function  OH_IPCParcel_ReadInt16(const parcel: POHIPCParcel; value: pcint16): cint;
function  OH_IPCParcel_WriteInt32(parcel: POHIPCParcel; value: cint32): cint;
function  OH_IPCParcel_ReadInt32(const parcel: POHIPCParcel; value: pcint32): cint;
function  OH_IPCParcel_WriteInt64(parcel: POHIPCParcel; value: cint64): cint;
function  OH_IPCParcel_ReadInt64(const parcel: POHIPCParcel; value: pcint64): cint;
function  OH_IPCParcel_WriteFloat(parcel: POHIPCParcel; value: cfloat): cint;
function  OH_IPCParcel_ReadFloat(const parcel: POHIPCParcel; value: pcfloat): cint;
function  OH_IPCParcel_WriteDouble(parcel: POHIPCParcel; value: cdouble): cint;
function  OH_IPCParcel_ReadDouble(const parcel: POHIPCParcel; value: pcdouble): cint;
function  OH_IPCParcel_WriteString(parcel: POHIPCParcel; str: PChar): cint;
function  OH_IPCParcel_ReadString(const parcel: POHIPCParcel): PChar;
function  OH_IPCParcel_WriteBuffer(parcel: POHIPCParcel; buffer: PByte; len: cint32): cint;
function  OH_IPCParcel_ReadBuffer(const parcel: POHIPCParcel; len: cint32): PByte;
function  OH_IPCParcel_WriteRemoteStub(parcel: POHIPCParcel; const stub: POHIPCRemoteStub): cint;
function  OH_IPCParcel_ReadRemoteStub(const parcel: POHIPCParcel): POHIPCRemoteStub;
function  OH_IPCParcel_WriteRemoteProxy(parcel: POHIPCParcel; const proxy: POHIPCRemoteProxy): cint;
function  OH_IPCParcel_ReadRemoteProxy(const parcel: POHIPCParcel): POHIPCRemoteProxy;
function  OH_IPCParcel_WriteFileDescriptor(parcel: POHIPCParcel; fd: cint32): cint;
function  OH_IPCParcel_ReadFileDescriptor(const parcel: POHIPCParcel; fd: pcint32): cint;
function  OH_IPCParcel_Append(parcel: POHIPCParcel; const data: POHIPCParcel): cint;
function  OH_IPCParcel_WriteInterfaceToken(parcel: POHIPCParcel; token: PChar): cint;
function  OH_IPCParcel_ReadInterfaceToken(const parcel: POHIPCParcel; token: PPChar; len: pcint32;
  allocator: TOH_IPC_MemAllocator): cint;

{ ---------------------------------------------------------------------
  Stub / Proxy
  ---------------------------------------------------------------------}
function  OH_IPCRemoteStub_Create(descriptor: PChar; requestCallback: TOH_OnRemoteRequestCallback;
  destroyCallback: TOH_OnRemoteDestroyCallback; userData: Pointer): POHIPCRemoteStub;
procedure OH_IPCRemoteStub_Destroy(stub: POHIPCRemoteStub);
procedure OH_IPCRemoteProxy_Destroy(proxy: POHIPCRemoteProxy);
function  OH_IPCRemoteProxy_SendRequest(const proxy: POHIPCRemoteProxy; code: cuint32;
  const data: POHIPCParcel; reply: POHIPCParcel; const option: POH_IPC_MessageOption): cint;
function  OH_IPCRemoteProxy_GetInterfaceDescriptor(proxy: POHIPCRemoteProxy; descriptor: PPChar;
  len: pcint32; allocator: TOH_IPC_MemAllocator): cint;
function  OH_IPCDeathRecipient_Create(deathRecipientCallback: TOH_OnDeathRecipientCallback;
  destroyCallback: TOH_OnDeathRecipientDestroyCallback; userData: Pointer): POHIPCDeathRecipient;
procedure OH_IPCDeathRecipient_Destroy(recipient: POHIPCDeathRecipient);
function  OH_IPCRemoteProxy_AddDeathRecipient(proxy: POHIPCRemoteProxy; recipient: POHIPCDeathRecipient): cint;
function  OH_IPCRemoteProxy_RemoveDeathRecipient(proxy: POHIPCRemoteProxy; recipient: POHIPCDeathRecipient): cint;
function  OH_IPCRemoteProxy_IsRemoteDead(const proxy: POHIPCRemoteProxy): cint;

{ ---------------------------------------------------------------------
  Skeleton (work threads / caller identity)
  ---------------------------------------------------------------------}
procedure OH_IPCSkeleton_JoinWorkThread;
procedure OH_IPCSkeleton_StopWorkThread;
function  OH_IPCSkeleton_GetCallingTokenId: cuint64;
function  OH_IPCSkeleton_GetFirstTokenId: cuint64;
function  OH_IPCSkeleton_GetSelfTokenId: cuint64;
function  OH_IPCSkeleton_GetCallingPid: cuint64;
function  OH_IPCSkeleton_GetCallingUid: cuint64;
function  OH_IPCSkeleton_IsLocalCalling: cint;
function  OH_IPCSkeleton_SetMaxWorkThreadNum(const maxThreadNum: cint): cint;
function  OH_IPCSkeleton_ResetCallingIdentity(identity: PPChar; len: pcint32;
  allocator: TOH_IPC_MemAllocator): cint;
function  OH_IPCSkeleton_SetCallingIdentity(identity: PChar): cint;
function  OH_IPCSkeleton_IsHandlingTransaction: cint;

implementation

const
  RTLD_LAZY = 1;

function dlopen(__filename: PChar; __mode: Integer): Pointer; cdecl; external 'c';
function dlsym(__handle: Pointer; __name: PChar): Pointer; cdecl; external 'c';

var
  gIPCKitLoaded: Boolean = False;
  gIPCKitAvailable: Boolean = False;
  gIPCKitError: String = '';
  gIPCLib: Pointer = nil;

{ Resolved function pointers (one per bound API) }
var
  pOH_IPCParcel_Create: function: POHIPCParcel; cdecl;
  pOH_IPCParcel_Destroy: procedure(parcel: POHIPCParcel); cdecl;
  pOH_IPCParcel_GetDataSize: function(const parcel: POHIPCParcel): cint; cdecl;
  pOH_IPCParcel_GetWritableBytes: function(const parcel: POHIPCParcel): cint; cdecl;
  pOH_IPCParcel_GetReadableBytes: function(const parcel: POHIPCParcel): cint; cdecl;
  pOH_IPCParcel_GetReadPosition: function(const parcel: POHIPCParcel): cint; cdecl;
  pOH_IPCParcel_GetWritePosition: function(const parcel: POHIPCParcel): cint; cdecl;
  pOH_IPCParcel_RewindReadPosition: function(parcel: POHIPCParcel; newReadPos: cuint32): cint; cdecl;
  pOH_IPCParcel_RewindWritePosition: function(parcel: POHIPCParcel; newWritePos: cuint32): cint; cdecl;
  pOH_IPCParcel_WriteInt8: function(parcel: POHIPCParcel; value: cint8): cint; cdecl;
  pOH_IPCParcel_ReadInt8: function(const parcel: POHIPCParcel; value: pcint8): cint; cdecl;
  pOH_IPCParcel_WriteInt16: function(parcel: POHIPCParcel; value: cint16): cint; cdecl;
  pOH_IPCParcel_ReadInt16: function(const parcel: POHIPCParcel; value: pcint16): cint; cdecl;
  pOH_IPCParcel_WriteInt32: function(parcel: POHIPCParcel; value: cint32): cint; cdecl;
  pOH_IPCParcel_ReadInt32: function(const parcel: POHIPCParcel; value: pcint32): cint; cdecl;
  pOH_IPCParcel_WriteInt64: function(parcel: POHIPCParcel; value: cint64): cint; cdecl;
  pOH_IPCParcel_ReadInt64: function(const parcel: POHIPCParcel; value: pcint64): cint; cdecl;
  pOH_IPCParcel_WriteFloat: function(parcel: POHIPCParcel; value: cfloat): cint; cdecl;
  pOH_IPCParcel_ReadFloat: function(const parcel: POHIPCParcel; value: pcfloat): cint; cdecl;
  pOH_IPCParcel_WriteDouble: function(parcel: POHIPCParcel; value: cdouble): cint; cdecl;
  pOH_IPCParcel_ReadDouble: function(const parcel: POHIPCParcel; value: pcdouble): cint; cdecl;
  pOH_IPCParcel_WriteString: function(parcel: POHIPCParcel; str: PChar): cint; cdecl;
  pOH_IPCParcel_ReadString: function(const parcel: POHIPCParcel): PChar; cdecl;
  pOH_IPCParcel_WriteBuffer: function(parcel: POHIPCParcel; buffer: PByte; len: cint32): cint; cdecl;
  pOH_IPCParcel_ReadBuffer: function(const parcel: POHIPCParcel; len: cint32): PByte; cdecl;
  pOH_IPCParcel_WriteRemoteStub: function(parcel: POHIPCParcel; const stub: POHIPCRemoteStub): cint; cdecl;
  pOH_IPCParcel_ReadRemoteStub: function(const parcel: POHIPCParcel): POHIPCRemoteStub; cdecl;
  pOH_IPCParcel_WriteRemoteProxy: function(parcel: POHIPCParcel; const proxy: POHIPCRemoteProxy): cint; cdecl;
  pOH_IPCParcel_ReadRemoteProxy: function(const parcel: POHIPCParcel): POHIPCRemoteProxy; cdecl;
  pOH_IPCParcel_WriteFileDescriptor: function(parcel: POHIPCParcel; fd: cint32): cint; cdecl;
  pOH_IPCParcel_ReadFileDescriptor: function(const parcel: POHIPCParcel; fd: pcint32): cint; cdecl;
  pOH_IPCParcel_Append: function(parcel: POHIPCParcel; const data: POHIPCParcel): cint; cdecl;
  pOH_IPCParcel_WriteInterfaceToken: function(parcel: POHIPCParcel; token: PChar): cint; cdecl;
  pOH_IPCParcel_ReadInterfaceToken: function(const parcel: POHIPCParcel; token: PPChar; len: pcint32;
    allocator: TOH_IPC_MemAllocator): cint; cdecl;
  pOH_IPCRemoteStub_Create: function(descriptor: PChar; requestCallback: TOH_OnRemoteRequestCallback;
    destroyCallback: TOH_OnRemoteDestroyCallback; userData: Pointer): POHIPCRemoteStub; cdecl;
  pOH_IPCRemoteStub_Destroy: procedure(stub: POHIPCRemoteStub); cdecl;
  pOH_IPCRemoteProxy_Destroy: procedure(proxy: POHIPCRemoteProxy); cdecl;
  pOH_IPCRemoteProxy_SendRequest: function(const proxy: POHIPCRemoteProxy; code: cuint32;
    const data: POHIPCParcel; reply: POHIPCParcel; const option: POH_IPC_MessageOption): cint; cdecl;
  pOH_IPCRemoteProxy_GetInterfaceDescriptor: function(proxy: POHIPCRemoteProxy; descriptor: PPChar;
    len: pcint32; allocator: TOH_IPC_MemAllocator): cint; cdecl;
  pOH_IPCDeathRecipient_Create: function(deathRecipientCallback: TOH_OnDeathRecipientCallback;
    destroyCallback: TOH_OnDeathRecipientDestroyCallback; userData: Pointer): POHIPCDeathRecipient; cdecl;
  pOH_IPCDeathRecipient_Destroy: procedure(recipient: POHIPCDeathRecipient); cdecl;
  pOH_IPCRemoteProxy_AddDeathRecipient: function(proxy: POHIPCRemoteProxy;
    recipient: POHIPCDeathRecipient): cint; cdecl;
  pOH_IPCRemoteProxy_RemoveDeathRecipient: function(proxy: POHIPCRemoteProxy;
    recipient: POHIPCDeathRecipient): cint; cdecl;
  pOH_IPCRemoteProxy_IsRemoteDead: function(const proxy: POHIPCRemoteProxy): cint; cdecl;
  pOH_IPCSkeleton_JoinWorkThread: procedure; cdecl;
  pOH_IPCSkeleton_StopWorkThread: procedure; cdecl;
  pOH_IPCSkeleton_GetCallingTokenId: function: cuint64; cdecl;
  pOH_IPCSkeleton_GetFirstTokenId: function: cuint64; cdecl;
  pOH_IPCSkeleton_GetSelfTokenId: function: cuint64; cdecl;
  pOH_IPCSkeleton_GetCallingPid: function: cuint64; cdecl;
  pOH_IPCSkeleton_GetCallingUid: function: cuint64; cdecl;
  pOH_IPCSkeleton_IsLocalCalling: function: cint; cdecl;
  pOH_IPCSkeleton_SetMaxWorkThreadNum: function(const maxThreadNum: cint): cint; cdecl;
  pOH_IPCSkeleton_ResetCallingIdentity: function(identity: PPChar; len: pcint32;
    allocator: TOH_IPC_MemAllocator): cint; cdecl;
  pOH_IPCSkeleton_SetCallingIdentity: function(identity: PChar): cint; cdecl;
  pOH_IPCSkeleton_IsHandlingTransaction: function: cint; cdecl;

function Resolve(Lib: Pointer; const AName: String; var AFn): Boolean;
begin
  Pointer(AFn) := dlsym(Lib, PChar(AName));
  Result := Pointer(AFn) <> nil;
end;

procedure OHOSIPCKitLoad;
begin
  if gIPCKitLoaded then
    Exit;
  gIPCKitLoaded := True;
  gIPCLib := dlopen(LIB_IPC, RTLD_LAZY);
  if gIPCLib = nil then
  begin
    gIPCKitError := 'dlopen ' + LIB_IPC + ' failed';
    Exit;
  end;
  if not Resolve(gIPCLib, 'OH_IPCParcel_Create', pOH_IPCParcel_Create) then
    gIPCKitError := 'symbol OH_IPCParcel_Create not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_Destroy', pOH_IPCParcel_Destroy) then
    gIPCKitError := 'symbol OH_IPCParcel_Destroy not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_GetDataSize', pOH_IPCParcel_GetDataSize) then
    gIPCKitError := 'symbol OH_IPCParcel_GetDataSize not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_GetWritableBytes', pOH_IPCParcel_GetWritableBytes) then
    gIPCKitError := 'symbol OH_IPCParcel_GetWritableBytes not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_GetReadableBytes', pOH_IPCParcel_GetReadableBytes) then
    gIPCKitError := 'symbol OH_IPCParcel_GetReadableBytes not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_GetReadPosition', pOH_IPCParcel_GetReadPosition) then
    gIPCKitError := 'symbol OH_IPCParcel_GetReadPosition not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_GetWritePosition', pOH_IPCParcel_GetWritePosition) then
    gIPCKitError := 'symbol OH_IPCParcel_GetWritePosition not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_RewindReadPosition', pOH_IPCParcel_RewindReadPosition) then
    gIPCKitError := 'symbol OH_IPCParcel_RewindReadPosition not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_RewindWritePosition', pOH_IPCParcel_RewindWritePosition) then
    gIPCKitError := 'symbol OH_IPCParcel_RewindWritePosition not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_WriteInt8', pOH_IPCParcel_WriteInt8) then
    gIPCKitError := 'symbol OH_IPCParcel_WriteInt8 not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_ReadInt8', pOH_IPCParcel_ReadInt8) then
    gIPCKitError := 'symbol OH_IPCParcel_ReadInt8 not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_WriteInt16', pOH_IPCParcel_WriteInt16) then
    gIPCKitError := 'symbol OH_IPCParcel_WriteInt16 not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_ReadInt16', pOH_IPCParcel_ReadInt16) then
    gIPCKitError := 'symbol OH_IPCParcel_ReadInt16 not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_WriteInt32', pOH_IPCParcel_WriteInt32) then
    gIPCKitError := 'symbol OH_IPCParcel_WriteInt32 not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_ReadInt32', pOH_IPCParcel_ReadInt32) then
    gIPCKitError := 'symbol OH_IPCParcel_ReadInt32 not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_WriteInt64', pOH_IPCParcel_WriteInt64) then
    gIPCKitError := 'symbol OH_IPCParcel_WriteInt64 not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_ReadInt64', pOH_IPCParcel_ReadInt64) then
    gIPCKitError := 'symbol OH_IPCParcel_ReadInt64 not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_WriteFloat', pOH_IPCParcel_WriteFloat) then
    gIPCKitError := 'symbol OH_IPCParcel_WriteFloat not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_ReadFloat', pOH_IPCParcel_ReadFloat) then
    gIPCKitError := 'symbol OH_IPCParcel_ReadFloat not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_WriteDouble', pOH_IPCParcel_WriteDouble) then
    gIPCKitError := 'symbol OH_IPCParcel_WriteDouble not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_ReadDouble', pOH_IPCParcel_ReadDouble) then
    gIPCKitError := 'symbol OH_IPCParcel_ReadDouble not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_WriteString', pOH_IPCParcel_WriteString) then
    gIPCKitError := 'symbol OH_IPCParcel_WriteString not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_ReadString', pOH_IPCParcel_ReadString) then
    gIPCKitError := 'symbol OH_IPCParcel_ReadString not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_WriteBuffer', pOH_IPCParcel_WriteBuffer) then
    gIPCKitError := 'symbol OH_IPCParcel_WriteBuffer not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_ReadBuffer', pOH_IPCParcel_ReadBuffer) then
    gIPCKitError := 'symbol OH_IPCParcel_ReadBuffer not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_WriteRemoteStub', pOH_IPCParcel_WriteRemoteStub) then
    gIPCKitError := 'symbol OH_IPCParcel_WriteRemoteStub not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_ReadRemoteStub', pOH_IPCParcel_ReadRemoteStub) then
    gIPCKitError := 'symbol OH_IPCParcel_ReadRemoteStub not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_WriteRemoteProxy', pOH_IPCParcel_WriteRemoteProxy) then
    gIPCKitError := 'symbol OH_IPCParcel_WriteRemoteProxy not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_ReadRemoteProxy', pOH_IPCParcel_ReadRemoteProxy) then
    gIPCKitError := 'symbol OH_IPCParcel_ReadRemoteProxy not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_WriteFileDescriptor', pOH_IPCParcel_WriteFileDescriptor) then
    gIPCKitError := 'symbol OH_IPCParcel_WriteFileDescriptor not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_ReadFileDescriptor', pOH_IPCParcel_ReadFileDescriptor) then
    gIPCKitError := 'symbol OH_IPCParcel_ReadFileDescriptor not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_Append', pOH_IPCParcel_Append) then
    gIPCKitError := 'symbol OH_IPCParcel_Append not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_WriteInterfaceToken', pOH_IPCParcel_WriteInterfaceToken) then
    gIPCKitError := 'symbol OH_IPCParcel_WriteInterfaceToken not found'
  else if not Resolve(gIPCLib, 'OH_IPCParcel_ReadInterfaceToken', pOH_IPCParcel_ReadInterfaceToken) then
    gIPCKitError := 'symbol OH_IPCParcel_ReadInterfaceToken not found'
  else if not Resolve(gIPCLib, 'OH_IPCRemoteStub_Create', pOH_IPCRemoteStub_Create) then
    gIPCKitError := 'symbol OH_IPCRemoteStub_Create not found'
  else if not Resolve(gIPCLib, 'OH_IPCRemoteStub_Destroy', pOH_IPCRemoteStub_Destroy) then
    gIPCKitError := 'symbol OH_IPCRemoteStub_Destroy not found'
  else if not Resolve(gIPCLib, 'OH_IPCRemoteProxy_Destroy', pOH_IPCRemoteProxy_Destroy) then
    gIPCKitError := 'symbol OH_IPCRemoteProxy_Destroy not found'
  else if not Resolve(gIPCLib, 'OH_IPCRemoteProxy_SendRequest', pOH_IPCRemoteProxy_SendRequest) then
    gIPCKitError := 'symbol OH_IPCRemoteProxy_SendRequest not found'
  else if not Resolve(gIPCLib, 'OH_IPCRemoteProxy_GetInterfaceDescriptor',
    pOH_IPCRemoteProxy_GetInterfaceDescriptor) then
    gIPCKitError := 'symbol OH_IPCRemoteProxy_GetInterfaceDescriptor not found'
  else if not Resolve(gIPCLib, 'OH_IPCDeathRecipient_Create', pOH_IPCDeathRecipient_Create) then
    gIPCKitError := 'symbol OH_IPCDeathRecipient_Create not found'
  else if not Resolve(gIPCLib, 'OH_IPCDeathRecipient_Destroy', pOH_IPCDeathRecipient_Destroy) then
    gIPCKitError := 'symbol OH_IPCDeathRecipient_Destroy not found'
  else if not Resolve(gIPCLib, 'OH_IPCRemoteProxy_AddDeathRecipient',
    pOH_IPCRemoteProxy_AddDeathRecipient) then
    gIPCKitError := 'symbol OH_IPCRemoteProxy_AddDeathRecipient not found'
  else if not Resolve(gIPCLib, 'OH_IPCRemoteProxy_RemoveDeathRecipient',
    pOH_IPCRemoteProxy_RemoveDeathRecipient) then
    gIPCKitError := 'symbol OH_IPCRemoteProxy_RemoveDeathRecipient not found'
  else if not Resolve(gIPCLib, 'OH_IPCRemoteProxy_IsRemoteDead', pOH_IPCRemoteProxy_IsRemoteDead) then
    gIPCKitError := 'symbol OH_IPCRemoteProxy_IsRemoteDead not found'
  else if not Resolve(gIPCLib, 'OH_IPCSkeleton_JoinWorkThread', pOH_IPCSkeleton_JoinWorkThread) then
    gIPCKitError := 'symbol OH_IPCSkeleton_JoinWorkThread not found'
  else if not Resolve(gIPCLib, 'OH_IPCSkeleton_StopWorkThread', pOH_IPCSkeleton_StopWorkThread) then
    gIPCKitError := 'symbol OH_IPCSkeleton_StopWorkThread not found'
  else if not Resolve(gIPCLib, 'OH_IPCSkeleton_GetCallingTokenId', pOH_IPCSkeleton_GetCallingTokenId) then
    gIPCKitError := 'symbol OH_IPCSkeleton_GetCallingTokenId not found'
  else if not Resolve(gIPCLib, 'OH_IPCSkeleton_GetFirstTokenId', pOH_IPCSkeleton_GetFirstTokenId) then
    gIPCKitError := 'symbol OH_IPCSkeleton_GetFirstTokenId not found'
  else if not Resolve(gIPCLib, 'OH_IPCSkeleton_GetSelfTokenId', pOH_IPCSkeleton_GetSelfTokenId) then
    gIPCKitError := 'symbol OH_IPCSkeleton_GetSelfTokenId not found'
  else if not Resolve(gIPCLib, 'OH_IPCSkeleton_GetCallingPid', pOH_IPCSkeleton_GetCallingPid) then
    gIPCKitError := 'symbol OH_IPCSkeleton_GetCallingPid not found'
  else if not Resolve(gIPCLib, 'OH_IPCSkeleton_GetCallingUid', pOH_IPCSkeleton_GetCallingUid) then
    gIPCKitError := 'symbol OH_IPCSkeleton_GetCallingUid not found'
  else if not Resolve(gIPCLib, 'OH_IPCSkeleton_IsLocalCalling', pOH_IPCSkeleton_IsLocalCalling) then
    gIPCKitError := 'symbol OH_IPCSkeleton_IsLocalCalling not found'
  else if not Resolve(gIPCLib, 'OH_IPCSkeleton_SetMaxWorkThreadNum',
    pOH_IPCSkeleton_SetMaxWorkThreadNum) then
    gIPCKitError := 'symbol OH_IPCSkeleton_SetMaxWorkThreadNum not found'
  else if not Resolve(gIPCLib, 'OH_IPCSkeleton_ResetCallingIdentity',
    pOH_IPCSkeleton_ResetCallingIdentity) then
    gIPCKitError := 'symbol OH_IPCSkeleton_ResetCallingIdentity not found'
  else if not Resolve(gIPCLib, 'OH_IPCSkeleton_SetCallingIdentity',
    pOH_IPCSkeleton_SetCallingIdentity) then
    gIPCKitError := 'symbol OH_IPCSkeleton_SetCallingIdentity not found'
  else if not Resolve(gIPCLib, 'OH_IPCSkeleton_IsHandlingTransaction',
    pOH_IPCSkeleton_IsHandlingTransaction) then
    gIPCKitError := 'symbol OH_IPCSkeleton_IsHandlingTransaction not found'
  else
    gIPCKitAvailable := True;
end;

function OHOSIPCKitAvailable: Boolean;
begin
  if not gIPCKitLoaded then
    OHOSIPCKitLoad;
  Result := gIPCKitAvailable;
end;

function OHOSIPCKitError: String;
begin
  if not gIPCKitLoaded then
    OHOSIPCKitLoad;
  Result := gIPCKitError;
end;

{ ---------------------------------------------------------------------
  Parcel wrappers
  ---------------------------------------------------------------------}
function OH_IPCParcel_Create: POHIPCParcel;
begin
  if not OHOSIPCKitAvailable then
    Result := nil
  else
    Result := pOH_IPCParcel_Create();
end;
procedure OH_IPCParcel_Destroy(parcel: POHIPCParcel);
begin
  if OHOSIPCKitAvailable then
    pOH_IPCParcel_Destroy(parcel);
end;
function OH_IPCParcel_GetDataSize(const parcel: POHIPCParcel): cint;
begin
  if not OHOSIPCKitAvailable then Result := 0 else Result := pOH_IPCParcel_GetDataSize(parcel);
end;
function OH_IPCParcel_GetWritableBytes(const parcel: POHIPCParcel): cint;
begin
  if not OHOSIPCKitAvailable then Result := 0 else Result := pOH_IPCParcel_GetWritableBytes(parcel);
end;
function OH_IPCParcel_GetReadableBytes(const parcel: POHIPCParcel): cint;
begin
  if not OHOSIPCKitAvailable then Result := 0 else Result := pOH_IPCParcel_GetReadableBytes(parcel);
end;
function OH_IPCParcel_GetReadPosition(const parcel: POHIPCParcel): cint;
begin
  if not OHOSIPCKitAvailable then Result := 0 else Result := pOH_IPCParcel_GetReadPosition(parcel);
end;
function OH_IPCParcel_GetWritePosition(const parcel: POHIPCParcel): cint;
begin
  if not OHOSIPCKitAvailable then Result := 0 else Result := pOH_IPCParcel_GetWritePosition(parcel);
end;
function OH_IPCParcel_RewindReadPosition(parcel: POHIPCParcel; newReadPos: cuint32): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR
  else Result := pOH_IPCParcel_RewindReadPosition(parcel, newReadPos);
end;
function OH_IPCParcel_RewindWritePosition(parcel: POHIPCParcel; newWritePos: cuint32): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR
  else Result := pOH_IPCParcel_RewindWritePosition(parcel, newWritePos);
end;
function OH_IPCParcel_WriteInt8(parcel: POHIPCParcel; value: cint8): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_WriteInt8(parcel, value);
end;
function OH_IPCParcel_ReadInt8(const parcel: POHIPCParcel; value: pcint8): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_ReadInt8(parcel, value);
end;
function OH_IPCParcel_WriteInt16(parcel: POHIPCParcel; value: cint16): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_WriteInt16(parcel, value);
end;
function OH_IPCParcel_ReadInt16(const parcel: POHIPCParcel; value: pcint16): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_ReadInt16(parcel, value);
end;
function OH_IPCParcel_WriteInt32(parcel: POHIPCParcel; value: cint32): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_WriteInt32(parcel, value);
end;
function OH_IPCParcel_ReadInt32(const parcel: POHIPCParcel; value: pcint32): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_ReadInt32(parcel, value);
end;
function OH_IPCParcel_WriteInt64(parcel: POHIPCParcel; value: cint64): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_WriteInt64(parcel, value);
end;
function OH_IPCParcel_ReadInt64(const parcel: POHIPCParcel; value: pcint64): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_ReadInt64(parcel, value);
end;
function OH_IPCParcel_WriteFloat(parcel: POHIPCParcel; value: cfloat): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_WriteFloat(parcel, value);
end;
function OH_IPCParcel_ReadFloat(const parcel: POHIPCParcel; value: pcfloat): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_ReadFloat(parcel, value);
end;
function OH_IPCParcel_WriteDouble(parcel: POHIPCParcel; value: cdouble): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_WriteDouble(parcel, value);
end;
function OH_IPCParcel_ReadDouble(const parcel: POHIPCParcel; value: pcdouble): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_ReadDouble(parcel, value);
end;
function OH_IPCParcel_WriteString(parcel: POHIPCParcel; str: PChar): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_WriteString(parcel, str);
end;
function OH_IPCParcel_ReadString(const parcel: POHIPCParcel): PChar;
begin
  if not OHOSIPCKitAvailable then Result := nil else Result := pOH_IPCParcel_ReadString(parcel);
end;
function OH_IPCParcel_WriteBuffer(parcel: POHIPCParcel; buffer: PByte; len: cint32): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_WriteBuffer(parcel, buffer, len);
end;
function OH_IPCParcel_ReadBuffer(const parcel: POHIPCParcel; len: cint32): PByte;
begin
  if not OHOSIPCKitAvailable then Result := nil else Result := pOH_IPCParcel_ReadBuffer(parcel, len);
end;
function OH_IPCParcel_WriteRemoteStub(parcel: POHIPCParcel; const stub: POHIPCRemoteStub): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_WriteRemoteStub(parcel, stub);
end;
function OH_IPCParcel_ReadRemoteStub(const parcel: POHIPCParcel): POHIPCRemoteStub;
begin
  if not OHOSIPCKitAvailable then Result := nil else Result := pOH_IPCParcel_ReadRemoteStub(parcel);
end;
function OH_IPCParcel_WriteRemoteProxy(parcel: POHIPCParcel; const proxy: POHIPCRemoteProxy): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_WriteRemoteProxy(parcel, proxy);
end;
function OH_IPCParcel_ReadRemoteProxy(const parcel: POHIPCParcel): POHIPCRemoteProxy;
begin
  if not OHOSIPCKitAvailable then Result := nil else Result := pOH_IPCParcel_ReadRemoteProxy(parcel);
end;
function OH_IPCParcel_WriteFileDescriptor(parcel: POHIPCParcel; fd: cint32): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_WriteFileDescriptor(parcel, fd);
end;
function OH_IPCParcel_ReadFileDescriptor(const parcel: POHIPCParcel; fd: pcint32): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_ReadFileDescriptor(parcel, fd);
end;
function OH_IPCParcel_Append(parcel: POHIPCParcel; const data: POHIPCParcel): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_Append(parcel, data);
end;
function OH_IPCParcel_WriteInterfaceToken(parcel: POHIPCParcel; token: PChar): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR else Result := pOH_IPCParcel_WriteInterfaceToken(parcel, token);
end;
function OH_IPCParcel_ReadInterfaceToken(const parcel: POHIPCParcel; token: PPChar; len: pcint32;
  allocator: TOH_IPC_MemAllocator): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR
  else Result := pOH_IPCParcel_ReadInterfaceToken(parcel, token, len, allocator);
end;

{ ---------------------------------------------------------------------
  Stub / Proxy wrappers
  ---------------------------------------------------------------------}
function OH_IPCRemoteStub_Create(descriptor: PChar; requestCallback: TOH_OnRemoteRequestCallback;
  destroyCallback: TOH_OnRemoteDestroyCallback; userData: Pointer): POHIPCRemoteStub;
begin
  if not OHOSIPCKitAvailable then
    Result := nil
  else
    Result := pOH_IPCRemoteStub_Create(descriptor, requestCallback, destroyCallback, userData);
end;
procedure OH_IPCRemoteStub_Destroy(stub: POHIPCRemoteStub);
begin
  if OHOSIPCKitAvailable then
    pOH_IPCRemoteStub_Destroy(stub);
end;
procedure OH_IPCRemoteProxy_Destroy(proxy: POHIPCRemoteProxy);
begin
  if OHOSIPCKitAvailable then
    pOH_IPCRemoteProxy_Destroy(proxy);
end;
function OH_IPCRemoteProxy_SendRequest(const proxy: POHIPCRemoteProxy; code: cuint32;
  const data: POHIPCParcel; reply: POHIPCParcel; const option: POH_IPC_MessageOption): cint;
begin
  if not OHOSIPCKitAvailable then
    Result := OH_IPC_DEAD_REMOTE_OBJECT
  else
    Result := pOH_IPCRemoteProxy_SendRequest(proxy, code, data, reply, option);
end;
function OH_IPCRemoteProxy_GetInterfaceDescriptor(proxy: POHIPCRemoteProxy; descriptor: PPChar;
  len: pcint32; allocator: TOH_IPC_MemAllocator): cint;
begin
  if not OHOSIPCKitAvailable then
    Result := OH_IPC_INNER_ERROR
  else
    Result := pOH_IPCRemoteProxy_GetInterfaceDescriptor(proxy, descriptor, len, allocator);
end;
function OH_IPCDeathRecipient_Create(deathRecipientCallback: TOH_OnDeathRecipientCallback;
  destroyCallback: TOH_OnDeathRecipientDestroyCallback; userData: Pointer): POHIPCDeathRecipient;
begin
  if not OHOSIPCKitAvailable then
    Result := nil
  else
    Result := pOH_IPCDeathRecipient_Create(deathRecipientCallback, destroyCallback, userData);
end;
procedure OH_IPCDeathRecipient_Destroy(recipient: POHIPCDeathRecipient);
begin
  if OHOSIPCKitAvailable then
    pOH_IPCDeathRecipient_Destroy(recipient);
end;
function OH_IPCRemoteProxy_AddDeathRecipient(proxy: POHIPCRemoteProxy; recipient: POHIPCDeathRecipient): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR
  else Result := pOH_IPCRemoteProxy_AddDeathRecipient(proxy, recipient);
end;
function OH_IPCRemoteProxy_RemoveDeathRecipient(proxy: POHIPCRemoteProxy; recipient: POHIPCDeathRecipient): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR
  else Result := pOH_IPCRemoteProxy_RemoveDeathRecipient(proxy, recipient);
end;
function OH_IPCRemoteProxy_IsRemoteDead(const proxy: POHIPCRemoteProxy): cint;
begin
  if not OHOSIPCKitAvailable then Result := 1 else Result := pOH_IPCRemoteProxy_IsRemoteDead(proxy);
end;

{ ---------------------------------------------------------------------
  Skeleton wrappers
  ---------------------------------------------------------------------}
procedure OH_IPCSkeleton_JoinWorkThread;
begin
  if OHOSIPCKitAvailable then
    pOH_IPCSkeleton_JoinWorkThread();
end;
procedure OH_IPCSkeleton_StopWorkThread;
begin
  if OHOSIPCKitAvailable then
    pOH_IPCSkeleton_StopWorkThread();
end;
function OH_IPCSkeleton_GetCallingTokenId: cuint64;
begin
  if not OHOSIPCKitAvailable then Result := 0 else Result := pOH_IPCSkeleton_GetCallingTokenId();
end;
function OH_IPCSkeleton_GetFirstTokenId: cuint64;
begin
  if not OHOSIPCKitAvailable then Result := 0 else Result := pOH_IPCSkeleton_GetFirstTokenId();
end;
function OH_IPCSkeleton_GetSelfTokenId: cuint64;
begin
  if not OHOSIPCKitAvailable then Result := 0 else Result := pOH_IPCSkeleton_GetSelfTokenId();
end;
function OH_IPCSkeleton_GetCallingPid: cuint64;
begin
  if not OHOSIPCKitAvailable then Result := 0 else Result := pOH_IPCSkeleton_GetCallingPid();
end;
function OH_IPCSkeleton_GetCallingUid: cuint64;
begin
  if not OHOSIPCKitAvailable then Result := 0 else Result := pOH_IPCSkeleton_GetCallingUid();
end;
function OH_IPCSkeleton_IsLocalCalling: cint;
begin
  if not OHOSIPCKitAvailable then Result := 1 else Result := pOH_IPCSkeleton_IsLocalCalling();
end;
function OH_IPCSkeleton_SetMaxWorkThreadNum(const maxThreadNum: cint): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR
  else Result := pOH_IPCSkeleton_SetMaxWorkThreadNum(maxThreadNum);
end;
function OH_IPCSkeleton_ResetCallingIdentity(identity: PPChar; len: pcint32;
  allocator: TOH_IPC_MemAllocator): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR
  else Result := pOH_IPCSkeleton_ResetCallingIdentity(identity, len, allocator);
end;
function OH_IPCSkeleton_SetCallingIdentity(identity: PChar): cint;
begin
  if not OHOSIPCKitAvailable then Result := OH_IPC_INNER_ERROR
  else Result := pOH_IPCSkeleton_SetCallingIdentity(identity);
end;
function OH_IPCSkeleton_IsHandlingTransaction: cint;
begin
  if not OHOSIPCKitAvailable then Result := 0 else Result := pOH_IPCSkeleton_IsHandlingTransaction();
end;

initialization
  { Nothing to do at load time: the kit is resolved lazily on first use,
    keeping libhelloworld.so loadable on devices without IPCKit. }

end.