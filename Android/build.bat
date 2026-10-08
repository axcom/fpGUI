@echo off
rem ============================================================================
rem  fpGUI Android demo builder (no Gradle; offline).
rem
rem  Usage:  build.bat [ABI] [source.lpr] [-i]
rem     ABI        : arm64-v8a | aarch64 | x86_64 | all   (default: all)
rem     source.lpr : Pascal library source in the current directory
rem                  (default: fpgapp.lpr)
rem     -i         : install the built APK to the attached device via adb
rem
rem  Run it from any project directory: the current directory is compiled and
rem  everything is written to build-android inside that directory.
rem
rem  Output (inside the project directory):
rem     build-android\<name>.apk        signed APK (contains selected ABIs)
rem     build-android\<ABI>\            lib<name>.so + FPC units (one dir per ABI)
rem     build-android\jniLibs\<ABI>\    staged native libraries for packaging
rem
rem  The Android Java shell (app\java, app\res, AndroidManifest.xml, tools and
rem  the bundled FreeType builder) is taken from SHELLDIR - the directory this
rem  script lives in, or the fallback fpGUI android directory below.
rem  The manifest meta-data "com.fpgui.lib_name" is rewritten to <name>, so the
rem  Java shell loads lib<name>.so (fpgapp.lpr - fpgapp).
rem
rem  Steps (per selected ABI):
rem    1. build bundled FreeType (reused from SHELLDIR\app\jniLibs if present)
rem    2. prepare NDK linker stubs for FPC's ancient binutils
rem    3. cross-compile the Pascal application library (lib<name>.so)
rem  Then (shared):
rem    4. compile the Java shell (FpActivity / FpSurfaceView)
rem    5. dex + aapt2 link + zip dex/libs + zipalign + sign
rem
rem  Environment:
rem    FPCEXTRA : extra FPC switches, e.g. set FPCEXTRA=-dDEBUG to keep the
rem               symbol table in lib<name>.so (crash symbolization).
rem ============================================================================
setlocal EnableExtensions

rem ---- installation paths (edit if yours differ) ----------------------------
set "FPCDIR=F:\Lazarus48_fpc331\fpc"
set "BINUTILS=%FPCDIR%\bin\x86_64-win64"
set "NDK=D:\Android\NDK\android-ndk-r27d"
set "SDK=D:\Android\SDK"
set "BUILD_TOOLS=%SDK%\build-tools\36.0.0"
set "ANDROID_JAR=%SDK%\platforms\android-37.0\android.jar"
set "JAVA_HOME=D:\Android\AndroidStudio\jbr"
set "ADB=%SDK%\platform-tools\adb.exe"

set "FPSRC=D:\fpGUI\fpGUI-2.1.0\framework\src\main\pascal"
set "RESDIR=D:\fpGUI\fpGUI-2.1.0\framework\src\main\resources"
set "LLVM_STRIP=%NDK%\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-strip.exe"

rem ---- shell (support) directory: script location, with a fallback ----------
set "SHELLDIR=%~dp0"
if not exist "%SHELLDIR%app\AndroidManifest.xml" set "SHELLDIR=D:\fpGUI\fpGUI-2.1.0\test\android\"

rem ---- project directory = current working directory ------------------------
set "PROJECT=%CD%"
set "OUT=%PROJECT%\build-android"

rem ---- parse arguments -------------------------------------------------------
rem NOTE: always use quoted set "VAR=value" - unquoted assignments inside
rem parenthesised blocks would capture the trailing space before '&'.
set "ABISEL=all"
set "SRCNAME=fpgapp.lpr"
set "INSTALL=0"
:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="-i"        (set "INSTALL=1" & shift & goto parse_args)
if /i "%~1"=="arm64"     (set "ABISEL=arm64-v8a" & shift & goto parse_args)
if /i "%~1"=="arm64-v8a" (set "ABISEL=arm64-v8a" & shift & goto parse_args)
if /i "%~1"=="aarch64"   (set "ABISEL=arm64-v8a" & shift & goto parse_args)
if /i "%~1"=="x64"       (set "ABISEL=x86_64"    & shift & goto parse_args)
if /i "%~1"=="x86_64"    (set "ABISEL=x86_64"    & shift & goto parse_args)
if /i "%~1"=="all"       (set "ABISEL=all"       & shift & goto parse_args)
if /i "%~x1"==".lpr"     (set "SRCNAME=%~nx1"    & shift & goto parse_args)
echo Unknown argument: %~1
goto usage

:args_done
set "BUILD_ARM64=0"
set "BUILD_X64=0"
if /i "%ABISEL%"=="all"       (set "BUILD_ARM64=1" & set "BUILD_X64=1")
if /i "%ABISEL%"=="arm64-v8a" set "BUILD_ARM64=1"
if /i "%ABISEL%"=="x86_64"    set "BUILD_X64=1"
if "%BUILD_ARM64%%BUILD_X64%"=="00" goto usage

if not exist "%PROJECT%\%SRCNAME%" (
  echo ERROR: source not found: "%PROJECT%\%SRCNAME%"
  echo        pass the .lpr file name as an argument, for example:
  echo        build.bat x86_64 myapp.lpr
  goto fail
)
if not exist "%SHELLDIR%app\AndroidManifest.xml" (
  echo ERROR: Android shell not found in "%SHELLDIR%"
  echo        edit SHELLDIR in this script to point at the fpGUI android directory.
  goto fail
)

rem lib name: fpgapp.lpr - libfpgapp.so, apk name fpgapp.apk
for %%F in ("%SRCNAME%") do set "LIBBASE=%%~nF"
set "LIBNAME=lib%LIBBASE%.so"
set "APKNAME=%LIBBASE%.apk"

rem ---- shared directories ----------------------------------------------------
if not exist "%OUT%" mkdir "%OUT%"
if not exist "%OUT%\classes" mkdir "%OUT%\classes"
if not exist "%OUT%\dex" mkdir "%OUT%\dex"

rem ---- manifest patched for this project's library name ----------------------
powershell -NoProfile -ExecutionPolicy Bypass -File "%SHELLDIR%tools\manifest-setlib.ps1" -In "%SHELLDIR%app\AndroidManifest.xml" -Out "%OUT%\AndroidManifest.xml" -LibName "%LIBBASE%"
if errorlevel 1 goto fail

rem ---- 1..3. per-ABI native libraries ----------------------------------------
if "%BUILD_ARM64%"=="1" (
  call :build_abi arm64-v8a
  if errorlevel 1 goto fail
)
if "%BUILD_X64%"=="1" (
  call :build_abi x86_64
  if errorlevel 1 goto fail
)

rem ---- 4. Java shell ----------------------------------------------------------
echo.
echo [java] compiling Java shell...
if exist "%OUT%\classes\com" rmdir /s /q "%OUT%\classes\com"
"%JAVA_HOME%\bin\javac" -source 8 -target 8 -encoding UTF-8 ^
  -bootclasspath "%ANDROID_JAR%" -d "%OUT%\classes" ^
  "%SHELLDIR%app\java\com\fpgui\FpActivity.java" ^
  "%SHELLDIR%app\java\com\fpgui\FpLongPressGesture.java" ^
  "%SHELLDIR%app\java\com\fpgui\FpMouseGesture.java" ^
  "%SHELLDIR%app\java\com\fpgui\FpSurfaceView.java" ^
  "%SHELLDIR%app\java\com\fpgui\FpSubWindow.java" ^
  "%SHELLDIR%app\java\com\fpgui\FpWindowView.java"
if errorlevel 1 goto fail

rem ---- 5. dex + resources + package ------------------------------------------
echo [package] dex + aapt2 + zip + align + sign...
if exist "%OUT%\dex\classes.dex" del /q "%OUT%\dex\classes.dex"
rem d8 rejects a directory argument in this build; feed an @argfile.
del /q "%OUT%\dex\classes.lst" 2>nul
dir /b /s "%OUT%\classes\com\fpgui\*.class" > "%OUT%\dex\classes.lst"
call "%BUILD_TOOLS%\d8.bat" "@%OUT%\dex\classes.lst" ^
  --lib "%ANDROID_JAR%" --min-api 21 --output "%OUT%\dex"
if errorlevel 1 goto fail

rem App resources (res/values/styles.xml: FpTheme with windowDisablePreview).
rem RESZIP carries its own quotes: the path may contain spaces.
set "RESZIP="
if exist "%OUT%\res.zip" del /q "%OUT%\res.zip"
if exist "%SHELLDIR%app\res" (
  call "%BUILD_TOOLS%\aapt2.exe" compile --dir "%SHELLDIR%app\res" -o "%OUT%\res.zip"
  if errorlevel 1 goto fail
  set "RESZIP="%OUT%\res.zip""
)

if exist "%OUT%\base.apk" del /q "%OUT%\base.apk"
call "%BUILD_TOOLS%\aapt2.exe" link -o "%OUT%\base.apk" ^
  --manifest "%OUT%\AndroidManifest.xml" ^
  -I "%ANDROID_JAR%" --min-sdk-version 21 --target-sdk-version 35 --auto-add-overlay ^
  %RESZIP%
if errorlevel 1 goto fail

powershell -NoProfile -ExecutionPolicy Bypass -File "%SHELLDIR%tools\zipadd.ps1" -Zip "%OUT%\base.apk" -Source "%OUT%\dex\classes.dex" -Entry "classes.dex" >nul
if errorlevel 1 goto fail
if "%BUILD_ARM64%"=="1" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%SHELLDIR%tools\zipadd.ps1" -Zip "%OUT%\base.apk" -Source "%OUT%\jniLibs\arm64-v8a\%LIBNAME%" -Entry "lib/arm64-v8a/%LIBNAME%" >nul
  if errorlevel 1 goto fail
  powershell -NoProfile -ExecutionPolicy Bypass -File "%SHELLDIR%tools\zipadd.ps1" -Zip "%OUT%\base.apk" -Source "%OUT%\jniLibs\arm64-v8a\libfreetype.so" -Entry "lib/arm64-v8a/libfreetype.so" >nul
  if errorlevel 1 goto fail
)
if "%BUILD_X64%"=="1" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%SHELLDIR%tools\zipadd.ps1" -Zip "%OUT%\base.apk" -Source "%OUT%\jniLibs\x86_64\%LIBNAME%" -Entry "lib/x86_64/%LIBNAME%" >nul
  if errorlevel 1 goto fail
  powershell -NoProfile -ExecutionPolicy Bypass -File "%SHELLDIR%tools\zipadd.ps1" -Zip "%OUT%\base.apk" -Source "%OUT%\jniLibs\x86_64\libfreetype.so" -Entry "lib/x86_64/libfreetype.so" >nul
  if errorlevel 1 goto fail
)

if exist "%OUT%\aligned.apk" del /q "%OUT%\aligned.apk"
call "%BUILD_TOOLS%\zipalign.exe" -p -f 4 "%OUT%\base.apk" "%OUT%\aligned.apk"
if errorlevel 1 goto fail

if not exist "%SHELLDIR%debug.keystore" (
  "%JAVA_HOME%\bin\keytool.exe" -genkeypair -keystore "%SHELLDIR%debug.keystore" ^
    -alias androiddebugkey -storepass android -keypass android ^
    -keyalg RSA -keysize 2048 -validity 10000 ^
    -dname "CN=Android Debug,O=Android,C=US"
  if errorlevel 1 goto fail
)
if exist "%OUT%\%APKNAME%" del /q "%OUT%\%APKNAME%"
call "%BUILD_TOOLS%\apksigner.bat" sign ^
  --ks "%SHELLDIR%debug.keystore" --ks-pass pass:android --key-pass pass:android ^
  --out "%OUT%\%APKNAME%" "%OUT%\aligned.apk"
if errorlevel 1 goto fail
call "%BUILD_TOOLS%\apksigner.bat" verify "%OUT%\%APKNAME%"
if errorlevel 1 goto fail

echo.
echo done: %OUT%\%APKNAME%  (ABI: %ABISEL%)
if "%INSTALL%"=="1" (
  "%ADB%" install -r "%OUT%\%APKNAME%"
)
endlocal
exit /b 0

rem ============================================================================
rem  :build_abi <abi>   - FreeType + stubs + Pascal library for one ABI
rem ============================================================================
:build_abi
set "ABI=%~1"
if /i "%~1"=="arm64-v8a" (
  set "FPCCOMP=%FPCDIR%\bin\x86_64-win64\ppcrossa64.exe"
  set "FPCARCH=aarch64"
  set "FPCXP=aarch64-linux-android-"
  set "LIBARCH=aarch64-linux-android"
) else (
  set "FPCCOMP=%FPCDIR%\bin\x86_64-win64\ppcrossx64.exe"
  set "FPCARCH=x86_64"
  set "FPCXP=x86_64-linux-android-"
  set "LIBARCH=x86_64-linux-android"
)
set "NDKLIBS=%NDK%\toolchains\llvm\prebuilt\windows-x86_64\sysroot\usr\lib\%LIBARCH%"
set "STUBDIR=%OUT%\stubs\%ABI%"
set "JNIDIR=%OUT%\jniLibs\%ABI%"
set "ABIOUT=%OUT%\%ABI%"

echo.
echo [%ABI% 1/3] FreeType...
if not exist "%JNIDIR%\libfreetype.so" (
  if not exist "%SHELLDIR%app\jniLibs\%ABI%\libfreetype.so" (
    call "%SHELLDIR%build-freetype.bat" %ABI%
    if errorlevel 1 exit /b 1
  )
  if not exist "%JNIDIR%" mkdir "%JNIDIR%"
  copy /y "%SHELLDIR%app\jniLibs\%ABI%\libfreetype.so" "%JNIDIR%\libfreetype.so" >nul
  if errorlevel 1 exit /b 1
)

echo [%ABI% 2/3] linker stubs...
if not exist "%STUBDIR%\.done" (
  if not exist "%STUBDIR%" mkdir "%STUBDIR%"
  for %%L in (liblog.so libandroid.so libc.so libdl.so libEGL.so libGLESv2.so libm.so libz.so) do (
    copy /y "%NDKLIBS%\21\%%L" "%STUBDIR%\%%L" >nul
  )
  if errorlevel 1 exit /b 1
  "%LLVM_STRIP%" --strip-debug "%STUBDIR%\*.so"
  if errorlevel 1 exit /b 1
  echo done > "%STUBDIR%\.done"
)

echo [%ABI% 3/3] compiling %LIBNAME%...
if not exist "%ABIOUT%" mkdir "%ABIOUT%"
pushd "%PROJECT%"
"%FPCCOMP%" -Tandroid -P%FPCARCH% -XP%FPCXP% -FD"%BINUTILS%" -Xd ^
  -Fi"%FPSRC%\corelib" -Fi"%FPSRC%\corelib\android" -Fi"%FPSRC%\corelib\render\software" -Fi"%FPSRC%\gui" -Fi"%RESDIR%" ^
  -Fu"%FPSRC%\corelib" -Fu"%FPSRC%\corelib\android" -Fu"%FPSRC%\corelib\render\software" -Fu"%FPSRC%\gui" -Fu"%FPSRC%" -Fu"%RESDIR%" ^
  -Fl"%STUBDIR%" -Fl"%NDKLIBS%\21" -Fl"%JNIDIR%" ^
  -Cg -B -dUseCThreads %FPCEXTRA% -FU"%ABIOUT%" -FE"%ABIOUT%" -o"%LIBNAME%" "%SRCNAME%"
if errorlevel 1 (
  popd
  exit /b 1
)
popd
if not exist "%JNIDIR%" mkdir "%JNIDIR%"
copy /y "%ABIOUT%\%LIBNAME%" "%JNIDIR%\%LIBNAME%" >nul
if errorlevel 1 exit /b 1

exit /b 0

rem ============================================================================
:usage
echo.
echo Usage: build.bat [ABI] [source.lpr] [-i]
echo    ABI        : x86_64 ^| arm64-v8a ^| aarch64 ^| all   (default: all)
echo    source.lpr : Pascal source in the current directory (default: fpgapp.lpr)
echo    -i         : install the APK to the attached device
endlocal
exit /b 1

:fail
echo.
echo BUILD FAILED
endlocal
exit /b 1
