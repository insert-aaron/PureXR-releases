@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ==========================================================
REM RVG Capture - 1-file bootstrapper (downloads from URL)
REM ==========================================================
REM You distribute ONLY this .bat file.
REM It downloads a ZIP containing:
REM   - RvgCaptureGui.exe (x64)
REM   - CaptureService.exe (x86)
REM   - NTwain.dll and other required dlls
REM Then it extracts to %LOCALAPPDATA%\RvgCapture\app and runs.
REM
REM NOTE: If the target PC is missing .NET 4.8 or RVG drivers,
REM Windows will show normal installer/UAC prompts. That is unavoidable.

REM ---- Configure these URLs ----
set "APP_ZIP_URL=__PUT_YOUR_APP_ZIP_URL_HERE__"
set "DOTNET48_URL=https://go.microsoft.com/fwlink/?linkid=2088631"

REM Optional: if you host a checksum text file, set this and enable the check below.
set "APP_ZIP_SHA256=__OPTIONAL_SHA256_HEX__"

REM ---- Install locations ----
set "INSTALL_DIR=%LOCALAPPDATA%\RvgCapture\app"
set "TMP_DIR=%TEMP%\RvgCapture"
set "ZIP_PATH=%TMP_DIR%\RvgCapture.zip"
set "OUTDIR=%USERPROFILE%\Desktop\X-Ray Images - DO NOT Delete"
set "SHORTCUT_PATH=%PUBLIC%\Desktop\RVG Capture.lnk"

REM ---- Basic sanity ----
if "%APP_ZIP_URL%"=="__PUT_YOUR_APP_ZIP_URL_HERE__" (
  echo ERROR: APP_ZIP_URL is not set in this .bat.
  echo Edit BootstrapFromUrl.bat and set APP_ZIP_URL to your hosted ZIP.
  pause
  exit /b 1
)

REM ---- Ensure temp/output directories ----
if not exist "%TMP_DIR%" mkdir "%TMP_DIR%" >nul 2>&1
if not exist "%OUTDIR%" mkdir "%OUTDIR%" >nul 2>&1

REM ---- Check .NET Framework 4.8 presence ----
set "DOTNET48_OK="
for /f "usebackq delims=" %%R in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$r=(Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction SilentlyContinue).Release; if($r -ge 528040){'OK'} else {'NO'}"`) do (
  set "DOTNET48_OK=%%R"
)

if /i not "%DOTNET48_OK%"=="OK" (
  echo .NET Framework 4.8 not detected. Downloading installer...

  REM Need admin for installing .NET in many environments.
  net session >nul 2>&1
  if errorlevel 1 (
    echo Requesting admin permission (UAC)...
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
  )

  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%DOTNET48_URL%' -OutFile '%TMP_DIR%\dotnet48-installer.exe'"

  if not exist "%TMP_DIR%\dotnet48-installer.exe" (
    echo ERROR: Failed to download .NET 4.8 installer.
    pause
    exit /b 1
  )

  echo Installing .NET Framework 4.8 (this may take a few minutes)...
  start /wait "" "%TMP_DIR%\dotnet48-installer.exe"
)

REM ---- Download app zip ----
echo Downloading RVG Capture app...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%APP_ZIP_URL%' -OutFile '%ZIP_PATH%'"

if not exist "%ZIP_PATH%" (
  echo ERROR: App ZIP download failed: %ZIP_PATH%
  pause
  exit /b 1
)

REM ---- Optional: verify SHA256 ----
if not "%APP_ZIP_SHA256%"=="__OPTIONAL_SHA256_HEX__" (
  for /f "usebackq delims=" %%H in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "(Get-FileHash -Algorithm SHA256 -Path '%ZIP_PATH%').Hash"`) do (
    set "ACTUAL_SHA256=%%H"
  )
  if /i not "!ACTUAL_SHA256!"=="%APP_ZIP_SHA256%" (
    echo ERROR: SHA256 mismatch.
    echo Expected: %APP_ZIP_SHA256%
    echo Actual:   !ACTUAL_SHA256!
    pause
    exit /b 1
  )
)

REM ---- Extract ----
echo Extracting to: %INSTALL_DIR%
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "if(Test-Path '%INSTALL_DIR%'){ } ; Expand-Archive -Path '%ZIP_PATH%' -DestinationPath '%INSTALL_DIR%' -Force"

REM ---- Locate app folder (handles ZIPs that include bin\Release\ etc) ----
set "APP_DIR="
for /f "usebackq delims=" %%D in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$exe=Get-ChildItem -Path '%INSTALL_DIR%' -Filter 'RvgCaptureGui.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1; if($exe){$exe.Directory.FullName}"`) do (
  set "APP_DIR=%%D"
)

if not defined APP_DIR (
  echo ERROR: RvgCaptureGui.exe not found after extraction.
  echo Make sure your ZIP contains the built Release output (RvgCaptureGui.exe).
  pause
  exit /b 1
)

if not exist "%APP_DIR%\CaptureService.exe" (
  echo ERROR: CaptureService.exe not found next to RvgCaptureGui.exe.
  echo Ensure your ZIP includes CaptureService.exe in the same folder as RvgCaptureGui.exe.
  pause
  exit /b 1
)

REM ---- Quick TWAIN check (warn only) ----
set "HAS_TWAIN="
for /f "usebackq delims=" %%L in (`"%APP_DIR%\CaptureService.exe --list-sources 2>nul"`) do (
  set "HAS_TWAIN=1"
  goto :twain_done
)
:twain_done
if not defined HAS_TWAIN (
  echo WARNING: No TWAIN sources detected.
  echo Install RVG drivers / TWAIN source on this PC, then re-run.
  echo.
)

REM ---- Launch ----
echo Starting RVG Capture GUI...
start "" "%APP_DIR%\RvgCaptureGui.exe"

REM ---- Create Desktop shortcut (optional) ----
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$s='%SHORTCUT_PATH%'; $target='%APP_DIR%\RvgCaptureGui.exe'; $wd='%APP_DIR%'; $ico=Join-Path '%APP_DIR%' 'Assets\app.ico'; if(!(Test-Path $ico)){$ico=$target};" ^
  "$w=New-Object -ComObject WScript.Shell; $sc=$w.CreateShortcut($s); $sc.TargetPath=$target; $sc.WorkingDirectory=$wd; $sc.IconLocation=$ico; $sc.Save();" >nul 2>&1

exit /b 0

