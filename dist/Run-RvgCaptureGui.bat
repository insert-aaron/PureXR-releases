@echo off
setlocal enabledelayedexpansion

REM Run this from the folder containing RvgCaptureGui.exe
set "HERE=%~dp0"
pushd "%HERE%" >nul

if not exist "RvgCaptureGui.exe" (
  echo ERROR: RvgCaptureGui.exe not found in: %HERE%
  echo Copy this .bat into the same folder as RvgCaptureGui.exe.
  pause
  exit /b 1
)

REM Create default output folder on Desktop
set "OUTDIR=%USERPROFILE%\Desktop\X-Ray Images - DO NOT Delete"
if not exist "%OUTDIR%" (
  mkdir "%OUTDIR%" 2>nul
)

REM Basic dependency check: CaptureService must be next to GUI
if not exist "CaptureService.exe" (
  echo ERROR: CaptureService.exe not found next to RvgCaptureGui.exe
  echo Build CaptureService (Release|x86) and ensure it is copied into this folder.
  pause
  exit /b 1
)

REM Quick TWAIN check (non-fatal)
for /f "usebackq delims=" %%L in (`"CaptureService.exe --list-sources 2^>nul"`) do (
  set "HAS_SOURCES=1"
  goto :sources_done
)
:sources_done
if not defined HAS_SOURCES (
  echo WARNING: No TWAIN sources detected by CaptureService.
  echo Ensure RVG drivers are installed and TWAIN sources show up in a 32-bit TWAIN tool.
  echo.
)

start "" "RvgCaptureGui.exe"
popd >nul
exit /b 0

