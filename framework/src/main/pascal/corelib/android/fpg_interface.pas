{
    fpGUI  -  Free Pascal GUI Toolkit

    Copyright (c) 2026 by Graeme Geldenhuys.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

    Description:
      This unit defines alias types to bind each backend graphics library
      to fpg_main without the need for IFDEF's - Android edition.
}

unit fpg_interface;

{$I fpg_defines.inc}

interface

uses
  fpg_android,
  fpg_freetype_agg_fontresource,
  fpg_hybrid_canvas,
  fpg_android_hybrid_canvas,
  fpg_android_buffer_manager;

type
  TfpgFontResourceImpl  = class(TfpgFreeTypeFontResource);
  TfpgImageImpl         = class(TfpgAndroidImage);
  TfpgCanvasImpl        = class(TAndroidHybridCanvas);
  TfpgWindowImpl        = class(TfpgAndroidWindow);
  TfpgApplicationImpl   = class(TfpgAndroidApplication);
  TfpgClipboardImpl     = class(TfpgAndroidClipboard);
  TfpgFileListImpl      = class(TfpgAndroidFileList);
  TfpgMimeDataImpl      = class(TfpgAndroidMimeData);
  TfpgDragImpl          = class(TfpgAndroidDrag);
  TfpgDropImpl          = class(TfpgAndroidDrop);
  TfpgTimerImpl         = class(TfpgAndroidTimer);
  TfpgSystemTrayHandler = class(TfpgAndroidSystemTrayIcon);

implementation

uses
  fpg_main,
  fpg_fontmanager;

initialization
  { Android always uses the AGG hybrid canvas: the NDK exposes no public
    Skia API, so software rendering with FreeType glyphs is the canvas.
    The buffer-manager factory is qualified: fpg_hybrid_canvas declares an
    identically named hook that fpg_main probes, and the Android canvas
    reads its own. }
  DefaultCanvasClass := TAndroidHybridCanvas;
  fpg_android_hybrid_canvas.CreateBufferManager := @CreateAndroidBufferManager;
  AggFontResourceClass := TfpgFreeTypeFontResource;

end.
