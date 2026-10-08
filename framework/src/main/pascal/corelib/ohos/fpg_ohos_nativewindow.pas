{
    This unit is part of the fpGUI Toolkit project.

    Copyright (c) 2026 by Graeme Geldenhuys.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

    Description:
      HarmonyOS native_window API Pascal bindings.
      Translated from native_window C headers (external_window.h /
      buffer_handle.h). Mirrors fpg_ohos_drawing.pas (native_drawing
      bindings) as the window/surface counterpart.

      Moved here from fpg_ohos.pas so the main backend unit no longer
      carries NDK API declarations; fpg_ohos.pas and
      fpg_ohos_buffer_manager.pas both depend on this unit.
}

unit fpg_ohos_nativewindow;

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  CTypes;

const
  native_window = 'libnative_window.so';
  native_display_manager = 'libnative_display_manager.so';

type
  TOH_Region_Rect = record
    x: Int32; y: Int32; w: UInt32; h: UInt32;
  end;

  TOH_Region = record
    rects: ^TOH_Region_Rect;
    rectNumber: Int32;
  end;
  POH_Region = ^TOH_Region;

  { C struct: fd, width, stride, height, size (see buffer_handle.h) }
  BufferHandle = record
    fd: Int32;
    width: Int32;
    stride: Int32;   { bytes per row (NOT height!) }
    height: Int32;
    size: UInt32;
  end;
  PBufferHandle = ^BufferHandle;

function OH_NativeWindow_CreateNativeWindowFromSurfaceId(surfaceId: QWord; window: PPointer): Int32; cdecl; external native_window;
procedure OH_NativeWindow_DestroyNativeWindow(window: Pointer); cdecl; external native_window;
function OH_NativeWindow_NativeWindowHandleOpt(window: Pointer; code: Int32): Int32; cdecl; external native_window; varargs;
function OH_NativeWindow_NativeWindowRequestBuffer(window: Pointer; buffer: PPointer; fenceFd: PInt32): Int32; cdecl; external native_window;
function OH_NativeWindow_GetBufferHandleFromNative(buffer: Pointer): PBufferHandle; cdecl; external native_window;
function OH_NativeWindow_NativeWindowAbortBuffer(window: Pointer; buffer: Pointer): Int32; cdecl; external native_window;
function OH_NativeWindow_NativeWindowFlushBuffer(window: Pointer; buffer: Pointer; fenceFd: Int32; region: TOH_Region): Int32; cdecl; external native_window;
{ API 20+ 已移除 OH_NativeWindow_LockBuffer / UnlockAndFlushBuffer（external_window.h 确认），
  统一使用 RequestBuffer + FlushBuffer（API 9+ 全版本兼容）}

{ libc mmap/munmap — shared by fpg_ohos.pas (DoPutBufferToScreen) and
  fpg_ohos_buffer_manager.pas (buffer mapping). }
function fpmmap(addr: Pointer; len: QWord; prot, flags, fd: cint; offset: QWord): Pointer; cdecl; external 'libc.so' name 'mmap';
function fpmunmap(addr: Pointer; len: QWord): cint; cdecl; external 'libc.so' name 'munmap';

{ ── display_manager（运行期旋转/分辨率重查：fpg_ohos 'd' 配置变化分支使用）── }
function OH_NativeDisplayManager_GetDefaultDisplayWidth(out width: Int32): Int32; cdecl; external native_display_manager;
function OH_NativeDisplayManager_GetDefaultDisplayHeight(out height: Int32): Int32; cdecl; external native_display_manager;
function OH_NativeDisplayManager_GetDefaultDisplayDensityDpi(out dpi: Int32): Int32; cdecl; external native_display_manager;
function OH_NativeDisplayManager_GetDefaultDisplayVirtualPixelRatio(out ratio: Single): Int32; cdecl; external native_display_manager;

implementation

end.
