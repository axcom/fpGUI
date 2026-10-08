@echo off
rem ============================================================================
rem  fpGUI OHOS library builder (standalone FPC cross-build, no hvigor/DevEco).
rem
rem  Usage:  build.bat [ABI] [source.lpr] [-o libs-dir]
rem     ABI        : x86_64 | arm64-v8a | aarch64 | all   (default: all)
rem     source.lpr : Pascal library source in the current directory
rem                  (default: fpgapp.lpr)
rem     -o libs-dir: also copy the built library to libs-dir\ABI\libNAME.so
rem                  e.g. -o "F:\proj\entry\libs" for a HAP module
rem
rem  Run it from any project directory: the current directory is compiled.
rem  Examples:
rem     cd /d D:\myapp
rem     F:\fpGUI\fpGUI-2.1.0\test\helloworld\build.bat all
rem     build.bat x86_64 fpgapp.lpr
rem
rem  Output (per selected ABI), inside the project directory:
rem     build-ohos\ABI\libNAME.so     final library
rem     build-ohos\units-ABI\         FPC unit cache (per ABI)
rem
rem  Environment:
rem     FPCEXTRA : extra FPC switches, e.g. set FPCEXTRA=-O2 -dDEBUG
rem ============================================================================
setlocal EnableExtensions

rem ---- installation paths (edit if yours differ) ----------------------------
set "FPCDIR=F:\Lazarus48_fpc331\fpc"
set "FPC=%FPCDIR%\bin\x86_64-win64\fpc.exe"
set "SYSROOT=F:/Huawei/DevEcoStudio/sdk/default/openharmony/native/sysroot"

set "FPSRC=D:\fpGUI\fpGUI-2.1.0\framework\src\main\pascal"
set "RESDIR=D:\fpGUI\fpGUI-2.1.0\framework\src\main\resources"

rem ---- project directory = current working directory ------------------------
set "PROJECT=%CD%"
set "OUT=%PROJECT%\build-ohos"

rem ---- parse arguments -------------------------------------------------------
set "ABISEL=all"
set "SRCNAME=fpgapp.lpr"
set "COPYDIR="
:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="x64"       (set "ABISEL=x86_64"    & shift & goto parse_args)
if /i "%~1"=="x86_64"    (set "ABISEL=x86_64"    & shift & goto parse_args)
if /i "%~1"=="arm64"     (set "ABISEL=arm64-v8a" & shift & goto parse_args)
if /i "%~1"=="aarch64"   (set "ABISEL=arm64-v8a" & shift & goto parse_args)
if /i "%~1"=="arm64-v8a" (set "ABISEL=arm64-v8a" & shift & goto parse_args)
if /i "%~1"=="all"       (set "ABISEL=all"       & shift & goto parse_args)
if /i "%~1"=="-o"        (set "COPYDIR=%~2"      & shift & shift & goto parse_args)
if /i "%~x1"==".lpr"     (set "SRCNAME=%~nx1"    & shift & goto parse_args)
echo Unknown argument: %~1
goto usage

:args_done
rem NOTE: always use quoted set "VAR=value" - unquoted assignments inside
rem parenthesised blocks would capture the trailing space before '&'.
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
if not exist "%FPC%" (
  echo ERROR: FPC compiler not found: "%FPC%"
  goto fail
)

rem lib name: fpgapp.lpr - libfpgapp.so
for %%F in ("%SRCNAME%") do set "LIBNAME=lib%%~nF.so"
if not exist "%OUT%" mkdir "%OUT%"
if defined FPCEXTRA echo [info] FPCEXTRA=%FPCEXTRA%

rem ---- per-ABI native libraries ----------------------------------------------
if "%BUILD_X64%"=="1" (
  call :build_abi x86_64
  if errorlevel 1 goto fail
)
if "%BUILD_ARM64%"=="1" (
  call :build_abi arm64-v8a
  if errorlevel 1 goto fail
)

echo.
echo done: %SRCNAME% built for %ABISEL% in "%OUT%"
endlocal
exit /b 0

rem ============================================================================
rem  :build_abi ABI   - cross-compile libNAME.so for one OHOS ABI
rem ============================================================================
:build_abi
set "ABI=%~1"
set "TGT=x86_64"
if /i "%~1"=="arm64-v8a" (
  set "TGT=aarch64"
)
set "ABIOUT=%OUT%\%ABI%"
if not exist "%ABIOUT%" mkdir "%ABIOUT%"

echo.
echo [%ABI%] compiling %SRCNAME% -^> %LIBNAME% ...
"%FPC%" -B -Tohos -P%TGT% -XP%TGT%-ohos- -Sh -FcUTF8 -dUseCThreads %FPCEXTRA% ^
  -Fi"%FPSRC%\corelib" -Fi"%FPSRC%\corelib\ohos" -Fi"%FPSRC%\corelib\render\software" -Fi"%FPSRC%\gui" -Fi"%RESDIR%" ^
  -Fu"%FPSRC%\corelib" -Fu"%FPSRC%\corelib\ohos" -Fu"%FPSRC%\corelib\render\software" -Fu"%FPSRC%\gui" -Fu"%RESDIR%" ^
  -Fl"%SYSROOT%/usr/lib/%TGT%-linux-ohos" ^
  -k--sysroot="%SYSROOT%" -k-L"%SYSROOT%/usr/lib" -k--export-dynamic -k"--eh-frame-hdr" ^
  -Cg -dOHOS -dzh_CN ^
  -FU"%ABIOUT%" -FE"%ABIOUT%" -o"%LIBNAME%" "%PROJECT%\%SRCNAME%"
if errorlevel 1 exit /b 1

echo [%ABI%] built: "%ABIOUT%\%LIBNAME%"
if defined COPYDIR (
  if not exist "%COPYDIR%\%ABI%" mkdir "%COPYDIR%\%ABI%"
  copy /y "%ABIOUT%\%LIBNAME%" "%COPYDIR%\%ABI%\%LIBNAME%" >nul
  if errorlevel 1 exit /b 1
  echo [%ABI%] copied: "%COPYDIR%\%ABI%\%LIBNAME%"
)
exit /b 0

rem ============================================================================
:usage
echo.
echo Usage: build.bat [ABI] [source.lpr] [-o libs-dir]
echo    ABI        : x86_64 ^| arm64-v8a ^| aarch64 ^| all   (default: all)
echo    source.lpr : Pascal source in the current directory (default: fpgapp.lpr)
echo    -o dir     : also copy result to dir\ABI\libNAME.so
endlocal
exit /b 1

:fail
echo.
echo BUILD FAILED
endlocal
exit /b 1
