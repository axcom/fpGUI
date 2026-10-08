{
    This unit is part of the fpGUI Toolkit project.

    Copyright (c) 2026 by Graeme Geldenhuys.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

    Description:
      This unit defines alias types to bind each backend graphics library
      to fpg_main without the need for IFDEF's
}

unit fpg_interface;

{$I fpg_defines.inc}

interface

uses
  fpg_ohos
  {$ifdef AGGCanvas}
  , fpg_hybrid_canvas
  , fpg_ohos_hybrid_canvas
  , fpg_ohos_buffer_manager
  {$endif}
  ;

type
  TfpgFontResourceImpl  = class(TfpgOhosFontResource);
  TfpgImageImpl         = class(TfpgOhosImage);
  {$NOTES OFF}
  {$ifdef AGGCanvas}
  TfpgCanvasImpl        = class(TOhosHybridCanvas);
  {$else}
  TfpgCanvasImpl        = class(TfpgOhosCanvas);
  {$endif}
  {$NOTES ON}
  TfpgWindowImpl        = class(TfpgOhosWindow);
  TfpgApplicationImpl   = class(TfpgOhosApplication);
  TfpgClipboardImpl     = class(TfpgOhosClipboard);
  TfpgFileListImpl      = class(TfpgOhosFileList);
  TfpgMimeDataImpl      = class(TfpgOhosMimeData);
  TfpgDragImpl          = class(TfpgOhosDrag);
  TfpgDropImpl          = class(TfpgOhosDrop);
  TfpgTimerImpl         = class(TfpgOhosTimer);
  TfpgSystemTrayHandler = class(TfpgOhosSystemTrayIcon);

implementation

{$ifdef AGGCanvas}
uses
  fpg_main,
  fpg_fontmanager,
  fpg_ohos_agg_fontresource;

initialization
  DefaultCanvasClass   := TOhosHybridCanvas; 
  CreateBufferManager  := @CreateOhosBufferManager;
  AggFontResourceClass := TfpgOhosAggFontResource;
{$endif}

end.
