forked from https://github.com/graemeg/fpGUI

本项目基于 fpGUI 2.1.0 Realse 添加 OHOS 及 Android 系统支持。

源码目录结构：

```
fpGUI-2.1.0/
├── framework/src/main/pascal/
│   ├── corelib/       — 核心库（fpg_base/fpg_main/fpg_widget 等）
│   │     ├── ohos/        - 鸿蒙适配代码
│   │     └── android/     — 安卓适配代码
│   └── gui/           — 控件库（fpg_form/fpg_button 等）
├── OHOS/              — 鸿蒙
│   ├── docs/              — 鸿蒙系统适配使用文档
│   ├── interop/           — HarmonyOS 扩展单元(ipc/invoke/dispatch/picker 等)
│   └── libfp_bridge/      — libfp_bridge.so 桥接库源码
└── Android/           — 安卓
    ├── docs/              — 设计文档
    ├── app/               — Java 壳源码
    └── tools/             — APK 的小工具
```

## OHOS
    编译 fpGUI 工程为.so库。

1- pascal工程（示例）：

```    
library fpgapp;

{$mode objfpc}{$H+}

uses
  cthreads, classes, sysutils, frm_main;   { 项目自己的 uses }

{ ── 应用启动 ───────────────────────────────────────────── }
function MainProc;
var
  frm: TfrmMain;
begin
  fpgApplication.Initialize;
  frm := TfrmMain.Create(nil);
  frm.Show;
  fpgApplication.Run;
  frm.Free;
end;

{ 导出符号：C++ 端（libfp_bridge.so start NAPI）经 dlsym 调用 }
exports
  MainProc;
end.
```

2- 编译ohos的.so库（示例）：

```
修改 OHOS\build.bat 中 FPCDIR\FPC\SYSROOT\FPSRC\RESDIR 路径为你本机的路径，执行build.bat(可将BAT复制到工程目录使用)
```

3- 复制 build-ohos 下  <ABI> 目录内的.so库 到 DevEco 工程目录下的 libs 目录对应的 <ABI> 目录下。



## Android

1- pascal工程（示例）：

```    
library fpgapp;

{$mode objfpc}{$H+}

uses
  cthreads, classes, sysutils, jni,fpg_android,fpg_android_ndk,fpg_android_bridge, 
  frm_main;   { 项目自己的 uses }

{ ── 应用启动 ───────────────────────────────────────────── }
function MainProc;
var
  frm: TfrmMain;
begin
  fpgApplication.Initialize;
  frm := TfrmMain.Create(nil);
  frm.Show;
  fpgApplication.Run;
  frm.Free;
end;

function JNI_OnLoad(aVM: PJavaVM; aReserved: Pointer): jint; cdecl;
begin
  if aReserved = nil then ;
  AndroidSetAppMain(@MainProc);
  Result := AndroidRegisterNativeMethods(aVM);
end;

{ 导出符号 }
exports
  JNI_OnLoad;
end.
```

2- 编译android的.APK应用（示例）：

```
修改 Android\build.bat 中 FPCDIR\BINUTILS\NDK\SDK\BUILD_TOOLS\ANDROID_JAR\ADB\FPSRC\RESDIR 路径为你本机的路径，执行build.bat（只能放在Android目录引用使用）
```



加入QQ讨论群：【1126734621】

