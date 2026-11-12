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
  {$ifdef GLBackend}
  , fpg_ohos_gl_canvas
  {$endif}
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
  {$ifdef GLBackend}
  TfpgCanvasImpl        = class(TfpgGLCanvas);
  {$else}
    {$ifdef AGGCanvas}
    TfpgCanvasImpl      = class(TOhosHybridCanvas);
    {$else}
    TfpgCanvasImpl      = class(TfpgOhosCanvas);
    {$endif}
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

uses
  fpg_main,
  fpg_fontmanager
  {$if defined(GLBackend) or defined(AGGCanvas)}
  , fpg_ohos_agg_fontresource
  {$endif}
  {$ifdef GLBackend}
  , fpg_ohos_gl
  {$endif}
  ;

initialization
{$ifdef GLBackend}
  if TfpgOhosGLDisplay.Instance.TryInitialize then
  begin
    DefaultCanvasClass   := TfpgGLCanvas;
    AggFontResourceClass := TfpgOhosAggFontResource;
  end
  else
  begin
    { EGL/GLES is unavailable: keep the software backend. }
    {$ifdef AGGCanvas}
    DefaultCanvasClass   := TOhosHybridCanvas;
    CreateBufferManager  := @CreateOhosBufferManager;
    AggFontResourceClass := TfpgOhosAggFontResource;
    {$else}
    DefaultCanvasClass   := TfpgOhosCanvas;
    {$endif}
  end;
{$else}
  {$ifdef AGGCanvas}
  DefaultCanvasClass   := TOhosHybridCanvas;
  CreateBufferManager  := @CreateOhosBufferManager;
  AggFontResourceClass := TfpgOhosAggFontResource;
  {$endif}
{$endif}

end.
