{
    This unit is part of the fpGUI Toolkit project.

    Copyright (C) 2026 See the file AUTHORS.txt, included in this
    distribution, for details of the copyright.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      This translates platform specific classes to platform independant
      classes for Android.

      Handle semantics used by the Android backend:
        * The main form's handle is the ANativeWindow* behind the activity's
          SurfaceView (see fpg_android_ndk.pas).
        * Secondary windows (forms/dialogs/popups) do not own a system window:
          their handle is the TfpgAndroidWindow instance itself and their
          pixels are composited into the screen buffer owned by the main
          window's buffer manager.
}

unit fpg_impl;

{$I fpg_defines.inc}

interface

type
  TfpgWinHandle = Pointer;  { main window: ANativeWindow*; others: TfpgAndroidWindow* }
  TfpgDCHandle  = Pointer;  { unused on Android (AGG canvas draws into memory) }


implementation

end.
