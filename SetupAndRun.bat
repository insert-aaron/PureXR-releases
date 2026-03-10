@echo off
setlocal enabledelayedexpansion

REM ============================================
REM PureXR - Setup + Run (one entry point)
REM ============================================
REM FIRST RUN: Place this .bat anywhere and
REM double-click. It will:
REM   1. Check/install Git
REM   2. Clone the PureXR releases repo
REM   3. Check .NET 4.8
REM   4. Check TWAIN / RVG drivers
REM   5. Create output folder + shortcut
REM   6. Setup PureChart file watcher
REM   7. Launch PureXR
REM
REM SUBSEQUENT RUNS (via Desktop shortcut):
REM   - Auto-checks GitHub for updates
REM   - Silently pulls if update available
REM   - Restarts PureChart watcher
REM   - Launches PureXR
REM
REM Optional bundled installers (place next to this .bat):
REM   dotnet48-installer.exe
REM   rvg-driver-setup.exe
REM ============================================

REM ============================================
REM  CONFIGURE THESE
REM ============================================
SET REPO_URL=https://github.com/insert-aaron/PureXR-releases.git
SET INSTALL_DIR=C:\PureXR
SET EXE_NAME=RvgCaptureGui.exe
SET SERVICE_NAME=CaptureService.exe
REM ============================================
REM  PURECHART WATCHER (pre-filled for this facility)
REM ============================================
SET WATCHER_NAME=Purechart_Watcher_Austin_ea9e095e.py
REM ============================================

SET "EXE_PATH=%INSTALL_DIR%\%EXE_NAME%"
SET "SERVICE_PATH=%INSTALL_DIR%\%SERVICE_NAME%"
SET "SHORTCUT_PATH=%USERPROFILE%\Desktop\PureXR.lnk"
SET "OUTDIR=%USERPROFILE%\Desktop\X-Ray Images - DO NOT Delete"
SET "HERE=%~dp0"

REM ============================================
REM  DETECT OS BITNESS (64 vs 32)
REM ============================================
SET "ARCH=64"
IF /I "%PROCESSOR_ARCHITECTURE%"=="x86" IF "%PROCESSOR_ARCHITEW6432%"=="" SET "ARCH=32"
echo Detected Windows %ARCH%-bit.
echo.

REM ============================================
REM  STEP 0 — Relaunch elevated (UAC)
REM ============================================
net session >nul 2>&1
if errorlevel 1 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

echo ================================
echo   PureXR Launcher
echo ================================
echo.

REM ============================================
REM  STEP 1 — Check Git installed
REM ============================================
git --version >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    echo [1/7] Git not found. Installing Git silently...

    REM Prefer 64-bit Git, but fall back to 32-bit on 32-bit Windows
    IF "!ARCH!"=="64" (
        SET "GIT_URL=https://github.com/git-for-windows/git/releases/download/v2.47.0.windows.1/Git-2.47.0-64-bit.exe"
        SET "GIT_PATH=C:\Program Files\Git\cmd"
    ) ELSE (
        SET "GIT_URL=https://github.com/git-for-windows/git/releases/download/v2.47.0.windows.1/Git-2.47.0-32-bit.exe"
        SET "GIT_PATH=C:\Program Files (x86)\Git\cmd"
    )

    powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri $env:GIT_URL -OutFile '%TEMP%\git-installer.exe'"
    "%TEMP%\git-installer.exe" /VERYSILENT /NORESTART /CLOSEAPPLICATIONS

    echo Git installed.
    REM Prepend so git.exe is found immediately in this session
    SET "PATH=!GIT_PATH!;%PATH%"
) ELSE (
    echo [1/7] Git OK.
)

REM ============================================
REM  STEP 2 — Clone or Update via Git
REM ============================================
IF NOT EXIST "%INSTALL_DIR%\.git" (
    echo [2/7] First-time install: Downloading PureXR...
    git clone "%REPO_URL%" "%INSTALL_DIR%"
    IF %ERRORLEVEL% NEQ 0 (
        echo ERROR: Failed to download PureXR.
        echo Check your internet connection and try again.
        pause
        exit /b 1
    )
    echo Download complete.
) ELSE (
    echo [2/7] Checking for updates...
    cd /d "%INSTALL_DIR%"

    REM Try to reach GitHub — skip update if offline
    git fetch --depth=1 origin main >nul 2>&1
    IF %ERRORLEVEL% NEQ 0 (
        echo Could not reach update server. Running current version.
        goto :SKIP_UPDATE
    )

    REM Compare local vs remote commit hash
    FOR /F %%i IN ('git rev-parse HEAD') DO SET LOCAL_HASH=%%i
    FOR /F %%i IN ('git rev-parse origin/main') DO SET REMOTE_HASH=%%i

    IF NOT "!LOCAL_HASH!"=="!REMOTE_HASH!" (
        echo Update found! Downloading...
        git fetch --depth=1 origin main
        git reset --hard origin/main
        echo Update complete.
    ) ELSE (
        echo Already up to date.
    )
)
:SKIP_UPDATE

REM Display current version
IF EXIST "%INSTALL_DIR%\version.txt" (
    SET /P CURRENT_VERSION=<"%INSTALL_DIR%\version.txt"
    echo Version: !CURRENT_VERSION!
)
echo.

REM ============================================
REM  STEP 3 — Verify files exist
REM ============================================
echo [3/7] Verifying installation...
IF NOT EXIST "%EXE_PATH%" (
    echo ERROR: %EXE_NAME% not found in %INSTALL_DIR%
    echo The download may have failed. Delete %INSTALL_DIR% and run again.
    pause
    exit /b 1
)
IF NOT EXIST "%SERVICE_PATH%" (
    echo ERROR: %SERVICE_NAME% not found in %INSTALL_DIR%
    pause
    exit /b 1
)
echo Files OK.

REM ============================================
REM  STEP 4 — Check .NET Framework 4.8
REM ============================================
echo [4/7] Checking .NET Framework 4.8...
set "DOTNET48_OK="
for /f "usebackq delims=" %%R in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$r=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -EA SilentlyContinue).Release; if($r -ge 528040){'OK'} else {'NO'}"`) do (
  set "DOTNET48_OK=%%R"
)

IF /I NOT "%DOTNET48_OK%"=="OK" (
    echo .NET 4.8 not detected.
    IF EXIST "%HERE%dotnet48-installer.exe" (
        echo Installing .NET Framework 4.8... (this may take a few minutes)
        start /wait "" "%HERE%dotnet48-installer.exe"
    ) ELSE IF EXIST "%INSTALL_DIR%\dotnet48-installer.exe" (
        start /wait "" "%INSTALL_DIR%\dotnet48-installer.exe"
    ) ELSE (
        echo WARNING: dotnet48-installer.exe not found.
        echo Please install .NET Framework 4.8 manually if the app fails to launch.
    )
) ELSE (
    echo .NET 4.8 OK.
)

REM ============================================
REM  STEP 5 — Check TWAIN / RVG drivers
REM ============================================
echo [5/7] Checking TWAIN sources...
set "HAS_TWAIN="
for /f "usebackq delims=" %%L in (`"%SERVICE_PATH%" --list-sources 2^>nul`) do (
    echo TWAIN source detected: %%L
    set "HAS_TWAIN=1"
    goto :twain_done
)
:twain_done

IF NOT DEFINED HAS_TWAIN (
    echo WARNING: No TWAIN sources detected.
    IF EXIST "%HERE%rvg-driver-setup.exe" (
        echo Launching RVG driver installer...
        start /wait "" "%HERE%rvg-driver-setup.exe"
    ) ELSE IF EXIST "%INSTALL_DIR%\rvg-driver-setup.exe" (
        start /wait "" "%INSTALL_DIR%\rvg-driver-setup.exe"
    ) ELSE (
        echo No RVG driver installer found. Continuing anyway.
    )
) ELSE (
    echo TWAIN OK.
)

REM ============================================
REM  STEP 6 — Create output folder + shortcut
REM ============================================
echo [6/7] Finalizing...

REM Create X-Ray output folder on Desktop
IF NOT EXIST "%OUTDIR%" (
    mkdir "%OUTDIR%" 2>nul
    echo Created output folder on Desktop.
)

REM Create Desktop shortcut pointing to installed location
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$s='%SHORTCUT_PATH%';" ^
  "$target='%EXE_PATH%';" ^
  "$wd='%INSTALL_DIR%';" ^
  "$ico=Join-Path '%INSTALL_DIR%' 'Assets\app.ico';" ^
  "if(!(Test-Path $ico)){$ico=$target};" ^
  "$w=New-Object -ComObject WScript.Shell;" ^
  "$sc=$w.CreateShortcut($s);" ^
  "$sc.TargetPath=$target;" ^
  "$sc.WorkingDirectory=$wd;" ^
  "$sc.IconLocation=$ico;" ^
  "$sc.Save();" >nul 2>&1

echo Desktop shortcut updated.

REM ============================================
REM  STEP 7 — PureChart File Watcher
REM ============================================
echo [7/7] Setting up PureChart file watcher...

REM Find Python
set PYCMD=
python --version >nul 2>&1
if %errorlevel%==0 set PYCMD=python
if not defined PYCMD (
    py --version >nul 2>&1
    if %errorlevel%==0 set PYCMD=py
)

REM Install Python if not found
if not defined PYCMD (
    echo [7/7] Python not found. Installing Python 3.12...
    winget --version >nul 2>&1
    if %errorlevel%==0 (
        winget install Python.Python.3.12 --accept-package-agreements --accept-source-agreements
        SET "PATH=%LOCALAPPDATA%\Programs\Python\Python312;%LOCALAPPDATA%\Programs\Python\Python312\Scripts;%PATH%"
        python --version >nul 2>&1
        if %errorlevel%==0 set PYCMD=python
    )
    if not defined PYCMD (
        REM Prefer 64-bit Python, but fall back to 32-bit on 32-bit Windows
        IF "!ARCH!"=="64" (
            SET "PY_URL=https://www.python.org/ftp/python/3.12.8/python-3.12.8-amd64.exe"
        ) ELSE (
            SET "PY_URL=https://www.python.org/ftp/python/3.12.8/python-3.12.8.exe"
        )

        powershell -Command "Invoke-WebRequest -Uri '!PY_URL!' -OutFile '%TEMP%\python_installer.exe'"
        "%TEMP%\python_installer.exe" /quiet InstallAllUsers=0 PrependPath=1 Include_pip=1
        del "%TEMP%\python_installer.exe" >nul 2>&1
        SET "PATH=%LOCALAPPDATA%\Programs\Python\Python312;%LOCALAPPDATA%\Programs\Python\Python312\Scripts;%PATH%"
        python --version >nul 2>&1
        if %errorlevel%==0 set PYCMD=python
    )
)

if not defined PYCMD (
    echo WARNING: Could not install Python. PureChart watcher will not run.
    goto :launch
)

echo [7/7] Python OK. Installing watcher dependencies...
%PYCMD% -m pip install --quiet --upgrade pip >nul 2>&1
%PYCMD% -m pip install --quiet watchdog requests

REM Extract watcher script into the X-Ray output folder (always overwrite to keep it current)
echo [7/7] Deploying watcher to output folder...
echo IyEvdXNyL2Jpbi9lbnYgcHl0aG9uMwoiIiIKUHVyZUNoYXJ0IEZpbGUgVXBsb2FkIExpdmUgLSBEcm9wLUluIEZvbGRlciBXYXRjaGVyCgpQbGFjZSB0aGlzIHNjcmlwdCBpbiB0aGUgZm9sZGVyIHlvdSB3YW50IHRvIG1vbml0b3IuCkl0IHdhdGNoZXMgaXRzIG93biBkaXJlY3RvcnkgZm9yIG5ldyBmaWxlcyBhbmQgdXBsb2FkcyB0aGVtIHRvIFB1cmVDaGFydC4KCkluc3RhbGwgZGVwZW5kZW5jaWVzOgogIHBpcCBpbnN0YWxsIHJlcXVlc3RzIHdhdGNoZG9nCgpVc2FnZToKICAxLiBDb3B5IHRoaXMgZmlsZSBpbnRvIHRoZSBmb2xkZXIgdG8gbW9uaXRvciAoZS5nLiBDOlxcUGFub3JhbWljWHJheXMpCiAgMi4gRG91YmxlLWNsaWNrIG9yIHJ1bjogcHl0aG9uIHB1cmVjaGFydF93YXRjaGVyLnB5CiIiIgoKaW1wb3J0IG9zCmltcG9ydCBzeXMKaW1wb3J0IHRpbWUKaW1wb3J0IGhhc2hsaWIKaW1wb3J0IGJhc2U2NAppbXBvcnQgbG9nZ2luZwppbXBvcnQganNvbgppbXBvcnQgcGxhdGZvcm0KaW1wb3J0IHN1YnByb2Nlc3MKaW1wb3J0IHJlcXVlc3RzCmZyb20gd2F0Y2hkb2cuZXZlbnRzIGltcG9ydCBGaWxlU3lzdGVtRXZlbnRIYW5kbGVyCgojIFVzZSBQb2xsaW5nT2JzZXJ2ZXIgb24gV2luZG93cyBmb3IgcmVsaWFiaWxpdHkgKFJlYWREaXJlY3RvcnlDaGFuZ2VzVyBjYW4gbWlzcyBldmVudHMpCmlmIHBsYXRmb3JtLnN5c3RlbSgpID09ICJXaW5kb3dzIjoKICAgIGZyb20gd2F0Y2hkb2cub2JzZXJ2ZXJzLnBvbGxpbmcgaW1wb3J0IFBvbGxpbmdPYnNlcnZlciBhcyBPYnNlcnZlcgplbHNlOgogICAgZnJvbSB3YXRjaGRvZy5vYnNlcnZlcnMgaW1wb3J0IE9ic2VydmVyCgojIOKUgOKUgOKUgCBDb25maWd1cmF0aW9uIChwcmUtZmlsbGVkIGZyb20gUHVyZUNoYXJ0KSDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKU1VQQUJBU0VfVVJMID0gImh0dHBzOi8vd2h6b2hienFocWFvaHBvaG1xYWguc3VwYWJhc2UuY28iCkFOT05fS0VZID0gImV5SmhiR2NpT2lKSVV6STFOaUlzSW5SNWNDSTZJa3BYVkNKOS5leUpwYzNNaU9pSnpkWEJoWW1GelpTSXNJbkpsWmlJNkluZG9lbTlvWW5weGFIRmhiMmh3YjJodGNXRm9JaXdpY205c1pTSTZJbUZ1YjI0aUxDSnBZWFFpT2pFM05Ua3lOVFV6TnpRc0ltVjRjQ0k2TWpBM05EZ3pNVE0zTkgwLnBfQloxWGFQSWloU2RvLTQxWUticjRabVMtTlpSZkdyOUFlckVFZ3BtY2MiCk9SR0FOSVpBVElPTl9JRCA9ICIzM2IwMDdmMi03NTNiLTQ0YTQtYmFmZS0wOGIxMzcwZjY2YTciCkZBQ0lMSVRZX0lEID0gIjU1MGU4NDAwLWUyOWItNDFkNC1hNzE2LTQ0NjY1NTQ0MDAwNSIKU0NSSVBUX0lEID0gImU3MGFiZjBhLTYwY2EtNGRiMC1hYTlkLWI2NzIzOWMxYjkwZiIKRklMRV9FWFRFTlNJT05TID0gWyIuanBnIiwiLmpwZWciLCIucG5nIiwiLnRpZmYiLCIudGlmIiwiLnBkZiJdCk1BWF9GSUxFX1NJWkUgPSA1MCAqIDEwMjQgKiAxMDI0ICAjIDUwTUIKQ0xFQU5VUF9BR0VfSE9VUlMgPSA0OCAgIyBEZWxldGUgdXBsb2FkZWQgZmlsZXMgb2xkZXIgdGhhbiB0aGlzCgojIFdhdGNoIHRoZSBmb2xkZXIgd2hlcmUgdGhpcyBzY3JpcHQgbGl2ZXMKV0FUQ0hfRk9MREVSID0gb3MucGF0aC5kaXJuYW1lKG9zLnBhdGguYWJzcGF0aChfX2ZpbGVfXykpCgojIENvbXBvdW5kIGV4dGVuc2lvbnMgdGhhdCBvcy5wYXRoLnNwbGl0ZXh0IGNhbm5vdCBoYW5kbGUKQ09NUE9VTkRfRVhURU5TSU9OUyA9IFsiLm5paS5neiJdCgojIOKUgOKUgOKUgCBMb2dnaW5nIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApsb2dnaW5nLmJhc2ljQ29uZmlnKAogICAgbGV2ZWw9bG9nZ2luZy5JTkZPLAogICAgZm9ybWF0PSIlKGFzY3RpbWUpcyBbJShsZXZlbG5hbWUpc10gJShtZXNzYWdlKXMiLAogICAgaGFuZGxlcnM9WwogICAgICAgIGxvZ2dpbmcuU3RyZWFtSGFuZGxlcigpLAogICAgICAgIGxvZ2dpbmcuRmlsZUhhbmRsZXIoCiAgICAgICAgICAgIG9zLnBhdGguam9pbihXQVRDSF9GT0xERVIsICJwdXJlY2hhcnRfdXBsb2FkLmxvZyIpLCBlbmNvZGluZz0idXRmLTgiCiAgICAgICAgKSwKICAgIF0sCikKbG9nID0gbG9nZ2luZy5nZXRMb2dnZXIoInB1cmVjaGFydC11cGxvYWQiKQoKIyBUcmFjayBwcm9jZXNzZWQgZmlsZSBoYXNoZXMgdG8gYXZvaWQgcmUtdXBsb2FkaW5nCnByb2Nlc3NlZF9oYXNoZXMgPSBzZXQoKQpIQVNIX0NBQ0hFX0ZJTEUgPSBvcy5wYXRoLmpvaW4oV0FUQ0hfRk9MREVSLCAiLnB1cmVjaGFydF9oYXNoZXMuanNvbiIpClBJRF9GSUxFID0gb3MucGF0aC5qb2luKFdBVENIX0ZPTERFUiwgIi5wdXJlY2hhcnRfd2F0Y2hlci5waWQiKQoKCmRlZiBsb2FkX2hhc2hfY2FjaGUoKToKICAgIGdsb2JhbCBwcm9jZXNzZWRfaGFzaGVzCiAgICBpZiBvcy5wYXRoLmV4aXN0cyhIQVNIX0NBQ0hFX0ZJTEUpOgogICAgICAgIHRyeToKICAgICAgICAgICAgd2l0aCBvcGVuKEhBU0hfQ0FDSEVfRklMRSwgInIiKSBhcyBmOgogICAgICAgICAgICAgICAgcHJvY2Vzc2VkX2hhc2hlcyA9IHNldChqc29uLmxvYWQoZikpCiAgICAgICAgICAgIGxvZy5pbmZvKGYiTG9hZGVkIHtsZW4ocHJvY2Vzc2VkX2hhc2hlcyl9IGNhY2hlZCBoYXNoZXMiKQogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICAgICAgbG9nLndhcm5pbmcoZiJDb3VsZCBub3QgbG9hZCBoYXNoIGNhY2hlOiB7ZX0iKQoKCmRlZiBzYXZlX2hhc2hfY2FjaGUoKToKICAgIHRyeToKICAgICAgICB3aXRoIG9wZW4oSEFTSF9DQUNIRV9GSUxFLCAidyIpIGFzIGY6CiAgICAgICAgICAgIGpzb24uZHVtcChsaXN0KHByb2Nlc3NlZF9oYXNoZXMpLCBmKQogICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOgogICAgICAgIGxvZy53YXJuaW5nKGYiQ291bGQgbm90IHNhdmUgaGFzaCBjYWNoZToge2V9IikKCgpkZWYgY29tcHV0ZV9zaGEyNTYoZmlsZXBhdGgsIHJldHJpZXM9NSk6CiAgICAiIiJDb21wdXRlIFNIQS0yNTYgd2l0aCByZXRyeSBmb3IgV2luZG93cyBmaWxlIGxvY2tpbmcuIiIiCiAgICBmb3IgYXR0ZW1wdCBpbiByYW5nZShyZXRyaWVzKToKICAgICAgICB0cnk6CiAgICAgICAgICAgIHNoYTI1NiA9IGhhc2hsaWIuc2hhMjU2KCkKICAgICAgICAgICAgd2l0aCBvcGVuKGZpbGVwYXRoLCAicmIiKSBhcyBmOgogICAgICAgICAgICAgICAgZm9yIGNodW5rIGluIGl0ZXIobGFtYmRhOiBmLnJlYWQoODE5MiksIGIiIik6CiAgICAgICAgICAgICAgICAgICAgc2hhMjU2LnVwZGF0ZShjaHVuaykKICAgICAgICAgICAgcmV0dXJuIHNoYTI1Ni5oZXhkaWdlc3QoKQogICAgICAgIGV4Y2VwdCBQZXJtaXNzaW9uRXJyb3I6CiAgICAgICAgICAgIGlmIGF0dGVtcHQgPCByZXRyaWVzIC0gMToKICAgICAgICAgICAgICAgIGxvZy53YXJuaW5nKGYiRmlsZSBsb2NrZWQgKHthdHRlbXB0ICsgMX0ve3JldHJpZXN9KSwgcmV0cnlpbmc6IHtvcy5wYXRoLmJhc2VuYW1lKGZpbGVwYXRoKX0iKQogICAgICAgICAgICAgICAgdGltZS5zbGVlcCgxKQogICAgICAgICAgICBlbHNlOgogICAgICAgICAgICAgICAgcmFpc2UKICAgICAgICBleGNlcHQgT1NFcnJvcjoKICAgICAgICAgICAgcmFpc2UgICMgRG9uJ3QgcmV0cnkgZm9yIGZpbGUtbm90LWZvdW5kIG9yIG90aGVyIE9TIGVycm9ycwoKCmRlZiBnZXRfaG9zdG5hbWUoKToKICAgIGltcG9ydCBzb2NrZXQKICAgIHRyeToKICAgICAgICByZXR1cm4gc29ja2V0LmdldGhvc3RuYW1lKCkKICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgcmV0dXJuICJ1bmtub3duIgoKCmRlZiBnZXRfcHVibGljX2lwKCk6CiAgICB0cnk6CiAgICAgICAgcmVzcCA9IHJlcXVlc3RzLmdldCgiaHR0cHM6Ly9hcGkuaXBpZnkub3JnP2Zvcm1hdD1qc29uIiwgdGltZW91dD01KQogICAgICAgIHJldHVybiByZXNwLmpzb24oKS5nZXQoImlwIiwgIiIpCiAgICBleGNlcHQgRXhjZXB0aW9uOgogICAgICAgIHJldHVybiAiIgoKCmRlZiBnZXRfZmlsZV9leHQoZmlsZXBhdGgpOgogICAgIiIiR2V0IGZpbGUgZXh0ZW5zaW9uLCBoYW5kbGluZyBjb21wb3VuZCBleHRlbnNpb25zIGxpa2UgLm5paS5nei4iIiIKICAgIGJhc2VuYW1lID0gb3MucGF0aC5iYXNlbmFtZShmaWxlcGF0aCkubG93ZXIoKQogICAgZm9yIGNvbXBvdW5kIGluIENPTVBPVU5EX0VYVEVOU0lPTlM6CiAgICAgICAgaWYgYmFzZW5hbWUuZW5kc3dpdGgoY29tcG91bmQpOgogICAgICAgICAgICByZXR1cm4gY29tcG91bmQKICAgIHJldHVybiBvcy5wYXRoLnNwbGl0ZXh0KGJhc2VuYW1lKVsxXQoKCmRlZiBpc19vd25fZmlsZShmaWxlcGF0aCk6CiAgICAiIiJTa2lwIG91ciBvd24gbG9nL2NhY2hlL3NjcmlwdCBmaWxlcy4iIiIKICAgIGJhc2VuYW1lID0gb3MucGF0aC5iYXNlbmFtZShmaWxlcGF0aCkubG93ZXIoKQogICAgaWYgYmFzZW5hbWUgaW4gKCJwdXJlY2hhcnRfdXBsb2FkLmxvZyIsICIucHVyZWNoYXJ0X2hhc2hlcy5qc29uIiwgIi5wdXJlY2hhcnRfd2F0Y2hlci5waWQiKToKICA> "%OUTDIR%\pc_watcher.b64"
echo gICAgICByZXR1cm4gVHJ1ZQogICAgaWYgYmFzZW5hbWUuc3RhcnRzd2l0aCgicHVyZWNoYXJ0X3dhdGNoZXIiKSBhbmQgYmFzZW5hbWUuZW5kc3dpdGgoIi5weSIpOgogICAgICAgIHJldHVybiBUcnVlCiAgICByZXR1cm4gRmFsc2UKCgpkZWYgd2FpdF9mb3JfZmlsZV9zdGFibGUoZmlsZXBhdGgsIHRpbWVvdXQ9NjApOgogICAgIiIiV2FpdCB1bnRpbCBmaWxlIHNpemUgc3RvcHMgY2hhbmdpbmcgQU5EIGZpbGUgaXMgcmVhZGFibGUgKG5vdCBsb2NrZWQpLiIiIgogICAgaWYgbm90IG9zLnBhdGguZXhpc3RzKGZpbGVwYXRoKToKICAgICAgICByZXR1cm4gRmFsc2UKICAgIHByZXZfc2l6ZSA9IC0xCiAgICBzdGFibGVfY291bnQgPSAwCiAgICBtaXNzaW5nX2NvdW50ID0gMAogICAgc3RhcnQgPSB0aW1lLnRpbWUoKQogICAgd2hpbGUgdGltZS50aW1lKCkgLSBzdGFydCA8IHRpbWVvdXQ6CiAgICAgICAgdHJ5OgogICAgICAgICAgICBzaXplID0gb3MucGF0aC5nZXRzaXplKGZpbGVwYXRoKQogICAgICAgICAgICBpZiBzaXplID09IHByZXZfc2l6ZSBhbmQgc2l6ZSA+IDA6CiAgICAgICAgICAgICAgICBzdGFibGVfY291bnQgKz0gMQogICAgICAgICAgICAgICAgaWYgc3RhYmxlX2NvdW50ID49IDM6CiAgICAgICAgICAgICAgICAgICAgIyBWZXJpZnkgZmlsZSBpcyBhY3R1YWxseSByZWFkYWJsZSAobm90IGxvY2tlZCBvbiBXaW5kb3dzKQogICAgICAgICAgICAgICAgICAgIHRyeToKICAgICAgICAgICAgICAgICAgICAgICAgd2l0aCBvcGVuKGZpbGVwYXRoLCAicmIiKSBhcyBmOgogICAgICAgICAgICAgICAgICAgICAgICAgICAgZi5yZWFkKDEpCiAgICAgICAgICAgICAgICAgICAgICAgIHJldHVybiBUcnVlCiAgICAgICAgICAgICAgICAgICAgZXhjZXB0IChQZXJtaXNzaW9uRXJyb3IsIE9TRXJyb3IpOgogICAgICAgICAgICAgICAgICAgICAgICBsb2cuZGVidWcoZiJGaWxlIHN0YWJsZSBidXQgc3RpbGwgbG9ja2VkOiB7b3MucGF0aC5iYXNlbmFtZShmaWxlcGF0aCl9IikKICAgICAgICAgICAgICAgICAgICAgICAgc3RhYmxlX2NvdW50ID0gMCAgIyBSZXNldCDigJQgZmlsZSBzdGlsbCBsb2NrZWQKICAgICAgICAgICAgZWxzZToKICAgICAgICAgICAgICAgIHN0YWJsZV9jb3VudCA9IDAKICAgICAgICAgICAgcHJldl9zaXplID0gc2l6ZQogICAgICAgIGV4Y2VwdCBPU0Vycm9yOgogICAgICAgICAgICBtaXNzaW5nX2NvdW50ICs9IDEKICAgICAgICAgICAgaWYgbWlzc2luZ19jb3VudCA+PSAzOgogICAgICAgICAgICAgICAgcmV0dXJuIEZhbHNlICAjIEZpbGUgZGlzYXBwZWFyZWQg4oCUIHN0b3Agd2FpdGluZwogICAgICAgIHRpbWUuc2xlZXAoMC41KQogICAgcmV0dXJuIHByZXZfc2l6ZSA+IDAKCgpkZWYgdXBsb2FkX2ZpbGUoZmlsZXBhdGgpOgogICAgaWYgaXNfb3duX2ZpbGUoZmlsZXBhdGgpOgogICAgICAgIHJldHVybgoKICAgIGlmIG5vdCBvcy5wYXRoLmV4aXN0cyhmaWxlcGF0aCk6CiAgICAgICAgcmV0dXJuCgogICAgZmlsZW5hbWUgPSBvcy5wYXRoLmJhc2VuYW1lKGZpbGVwYXRoKQogICAgZXh0ID0gZ2V0X2ZpbGVfZXh0KGZpbGVwYXRoKQoKICAgIGlmIGV4dCBub3QgaW4gRklMRV9FWFRFTlNJT05TOgogICAgICAgIHJldHVybgoKICAgIHRyeToKICAgICAgICBmaWxlX3NpemUgPSBvcy5wYXRoLmdldHNpemUoZmlsZXBhdGgpCiAgICBleGNlcHQgT1NFcnJvciBhcyBlOgogICAgICAgIGxvZy53YXJuaW5nKGYiQ2Fubm90IHJlYWQge2ZpbGVuYW1lfToge2V9IikKICAgICAgICByZXR1cm4KCiAgICBpZiBmaWxlX3NpemUgPT0gMDoKICAgICAgICBsb2cud2FybmluZyhmIlNraXBwaW5nIHtmaWxlbmFtZX06IGVtcHR5IGZpbGUiKQogICAgICAgIHJldHVybgoKICAgIGlmIGZpbGVfc2l6ZSA+IE1BWF9GSUxFX1NJWkU6CiAgICAgICAgbG9nLndhcm5pbmcoZiJTa2lwcGluZyB7ZmlsZW5hbWV9OiB0b28gbGFyZ2UgKHtmaWxlX3NpemV9IGJ5dGVzKSIpCiAgICAgICAgcmV0dXJuCgogICAgdHJ5OgogICAgICAgIGZpbGVfaGFzaCA9IGNvbXB1dGVfc2hhMjU2KGZpbGVwYXRoKQogICAgZXhjZXB0IChQZXJtaXNzaW9uRXJyb3IsIE9TRXJyb3IpIGFzIGU6CiAgICAgICAgbG9nLndhcm5pbmcoZiJDYW5ub3QgcmVhZCB7ZmlsZW5hbWV9IChmaWxlIGxvY2tlZD8pOiB7ZX0iKQogICAgICAgIHJldHVybgoKICAgIGlmIGZpbGVfaGFzaCBpbiBwcm9jZXNzZWRfaGFzaGVzOgogICAgICAgIGxvZy5pbmZvKGYiU2tpcHBpbmcge2ZpbGVuYW1lfTogYWxyZWFkeSBwcm9jZXNzZWQgKGhhc2ggbWF0Y2gpIikKICAgICAgICByZXR1cm4KCiAgICAjIFJlYWQgYW5kIGVuY29kZSBmaWxlIChyZXRyeSBmb3IgV2luZG93cyBmaWxlIGxvY2tpbmcpCiAgICBmb3IgYXR0ZW1wdCBpbiByYW5nZSgzKToKICAgICAgICB0cnk6CiAgICAgICAgICAgIHdpdGggb3BlbihmaWxlcGF0aCwgInJiIikgYXMgZjoKICAgICAgICAgICAgICAgIGZpbGVfZGF0YSA9IGYucmVhZCgpCiAgICAgICAgICAgIGJyZWFrCiAgICAgICAgZXhjZXB0IChQZXJtaXNzaW9uRXJyb3IsIE9TRXJyb3IpIGFzIGU6CiAgICAgICAgICAgIGlmIGF0dGVtcHQgPCAyOgogICAgICAgICAgICAgICAgbG9nLndhcm5pbmcoZiJGaWxlIGxvY2tlZCwgcmV0cnlpbmcgcmVhZCAoe2F0dGVtcHQgKyAxfS8zKToge2ZpbGVuYW1lfSIpCiAgICAgICAgICAgICAgICB0aW1lLnNsZWVwKDEpCiAgICAgICAgICAgIGVsc2U6CiAgICAgICAgICAgICAgICBsb2cud2FybmluZyhmIkNhbm5vdCByZWFkIHtmaWxlbmFtZX0gYWZ0ZXIgcmV0cmllczoge2V9IikKICAgICAgICAgICAgICAgIHJldHVybgogICAgYmFzZTY0X2RhdGEgPSBiYXNlNjQuYjY0ZW5jb2RlKGZpbGVfZGF0YSkuZGVjb2RlKCJ1dGYtOCIpCgogICAgIyBEZXRlcm1pbmUgTUlNRSB0eXBlCiAgICBtaW1lX21hcCA9IHsKICAgICAgICAiLnBuZyI6ICJpbWFnZS9wbmciLAogICAgICAgICIuanBnIjogImltYWdlL2pwZWciLAogICAgICAgICIuanBlZyI6ICJpbWFnZS9qcGVnIiwKICAgICAgICAiLnRpZmYiOiAiaW1hZ2UvdGlmZiIsCiAgICAgICAgIi50aWYiOiAiaW1hZ2UvdGlmZiIsCiAgICAgICAgIi5wZGYiOiAiYXBwbGljYXRpb24vcGRmIiwKICAgICAgICAiLmRjbSI6ICJhcHBsaWNhdGlvbi9kaWNvbSIsCiAgICAgICAgIi5zdGwiOiAibW9kZWwvc3RsIiwKICAgICAgICAiLm9iaiI6ICJtb2RlbC9vYmoiLAogICAgICAgICIubmlpIjogImFwcGxpY2F0aW9uL3gtbmlmdGkiLAogICAgICAgICIubmlpLmd6IjogImFwcGxpY2F0aW9uL3gtbmlmdGkiLAogICAgfQogICAgbWltZV90eXBlID0gbWltZV9tYXAuZ2V0KGV4dCwgImFwcGxpY2F0aW9uL29jdGV0LXN0cmVhbSIpCgogICAgcGF5bG9hZCA9IHsKICAgICAgICAiYmFzZTY0RGF0YSI6IGJhc2U2NF9kYXRhLAogICAgICAgICJvcmdhbml6YXRpb25JZCI6IE9SR0FOSVpBVElPTl9JRCwKICAgICAgICAiZmFjaWxpdHlJZCI6IEZBQ0lMSVRZX0lELAogICAgICAgICJzY3JpcHRJZCI6IFNDUklQVF9JRCwKICAgICAgICAiZmlsZUhhc2giOiBmaWxlX2hhc2gsCiAgICAgICAgIm9yaWdpbmFsRmlsZW5hbWUiOiBmaWxlbmFtZSwKICAgICAgICAibWltZVR5cGUiOiBtaW1lX3R5cGUsCiAgICAgICAgImZpbGVTaXplIjogZmlsZV9zaXplLAogICAgICAgICJ1cGxvYWRTb3VyY2VJcCI6IGdldF9wdWJsaWNfaXAoKSwKICAgICAgICAidXBsb2FkRGV2aWNlTmFtZSI6IGdldF9ob3N0bmFtZSgpLAogICAgICAgICJsb2NhbEZpbGVQYXRoIjogZmlsZXBhdGgsCiAgICB9CgogICAgdXJsID0gZiJ7U1VQQUJBU0VfVVJMfS9mdW5jdGlvbnMvdjEvZmFjaWxpdHktdXBsb2FkLWxpdmUiCiAgICBoZWFkZXJzID0gewogICAgICAgICJBdXRob3JpemF0aW9uIjogZiJCZWFyZXIge0FOT05fS0VZfSIsCiAgICAgICAgImFwaWtleSI6IEFOT05fS0VZLAogICAgICAgICJDb250ZW50LVR5cGUiOiAiYXBwbGljYXRpb24vanNvbiIsCiAgICB9CgogICAgdHJ5OgogICAgICAgIGxvZy5pbmZvKGYiVXBsb2FkaW5nIHtmaWxlbmFtZX0gKHtmaWxlX3NpemV9IGJ5dGVzLCBoYXNoPXtmaWxlX2hhc2hbOjEyXX0uLi4pIikKICAgICAgICByZXNwID0gcmVxdWVzdHMucG9zdCh1cmwsIGpzb249cGF5bG9hZCwgaGVhZGVycz1oZWFkZXJzLCB0aW1lb3V0PTEyMCkKICAgICAgICByZXN1bHQgPSByZXNwLmpzb24oKQoKICAgICAgICBpZiByZXN1bHQuZ2V0KCJzdWNjZXNzIik6CiAgICAgICAgICAgIHByb2Nlc3NlZF9oYXNoZXMuYWRkKGZpbGVfaGFzaCkKICAgICAgICAgICAgc2F2ZV9oYXNoX2NhY2hlKCkKICAgICAgICAgICAgaWYgcmVzdWx0LmdldCgiZHVwbGljYXRlIik6CiAgICAgICAgICAgICAgICBsb2cuaW5mbyhmIiAgLT4gRHVwbGljYXRlIGRldGVjdGVkIChleGlzdGluZyBJRDoge3Jlc3VsdC5nZXQoJ2V4aXN0aW5nSWQnKX0pIikKICAgICAgICAgICAgZWxzZToKICAgICAgICAgICAgICAgIGxvZy5pbmZvKGYiICAtPiBVcGxvYWRlZCBPSyAoSUQ6IHtyZXN1bHQuZ2V0KCdpZCcpfSkiKQogICAgICAgIGVsaWYgcmVzdWx0LmdldCgiZXJyb3IiLCAiIikuc3RhcnRzd2l0aCgiU2NyaXB0IGRlYWN0aXZhdGVkIik6CiAgICAgICAgICAgIGxvZy5lcnJvcihmIiAgLT4gU2NyaXB0IGhhcyBiZWVuIGRlYWN0aXZhdGVkLiBTdG9wcGluZy>> "%OUTDIR%\pc_watcher.b64"
echo B3YXRjaGVyLiIpCiAgICAgICAgICAgIHJlbW92ZV9hdXRvc3RhcnQoKQogICAgICAgICAgICBzeXMuZXhpdCgxKQogICAgICAgIGVsc2U6CiAgICAgICAgICAgIGxvZy5lcnJvcihmIiAgLT4gVXBsb2FkIGZhaWxlZDoge3Jlc3VsdC5nZXQoJ2Vycm9yJyl9IikKICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICBsb2cuZXJyb3IoZiIgIC0+IE5ldHdvcmsgZXJyb3I6IHtlfSIpCgoKY2xhc3MgTmV3RmlsZUhhbmRsZXIoRmlsZVN5c3RlbUV2ZW50SGFuZGxlcik6CiAgICBkZWYgb25fY3JlYXRlZChzZWxmLCBldmVudCk6CiAgICAgICAgaWYgZXZlbnQuaXNfZGlyZWN0b3J5OgogICAgICAgICAgICByZXR1cm4KICAgICAgICB0cnk6CiAgICAgICAgICAgIGZpbGVwYXRoID0gZXZlbnQuc3JjX3BhdGgKICAgICAgICAgICAgaWYgbm90IG9zLnBhdGguZXhpc3RzKGZpbGVwYXRoKToKICAgICAgICAgICAgICAgIHJldHVybgogICAgICAgICAgICBleHQgPSBnZXRfZmlsZV9leHQoZmlsZXBhdGgpCiAgICAgICAgICAgIGlmIGV4dCBpbiBGSUxFX0VYVEVOU0lPTlMgYW5kIG5vdCBpc19vd25fZmlsZShmaWxlcGF0aCk6CiAgICAgICAgICAgICAgICBsb2cuaW5mbyhmIk5ldyBmaWxlIGRldGVjdGVkOiB7b3MucGF0aC5iYXNlbmFtZShmaWxlcGF0aCl9IikKICAgICAgICAgICAgICAgIGlmIHdhaXRfZm9yX2ZpbGVfc3RhYmxlKGZpbGVwYXRoKToKICAgICAgICAgICAgICAgICAgICB1cGxvYWRfZmlsZShmaWxlcGF0aCkKICAgICAgICAgICAgICAgIGVsc2U6CiAgICAgICAgICAgICAgICAgICAgbG9nLndhcm5pbmcoZiJGaWxlIG5vdCBzdGFibGUgYWZ0ZXIgdGltZW91dDoge29zLnBhdGguYmFzZW5hbWUoZmlsZXBhdGgpfSIpCiAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOgogICAgICAgICAgICBsb2cuZXJyb3IoZiJFcnJvciBoYW5kbGluZyBuZXcgZmlsZToge2V9IikKCiAgICBkZWYgb25fbW9kaWZpZWQoc2VsZiwgZXZlbnQpOgogICAgICAgIGlmIGV2ZW50LmlzX2RpcmVjdG9yeToKICAgICAgICAgICAgcmV0dXJuCiAgICAgICAgdHJ5OgogICAgICAgICAgICBmaWxlcGF0aCA9IGV2ZW50LnNyY19wYXRoCiAgICAgICAgICAgIGlmIG5vdCBvcy5wYXRoLmV4aXN0cyhmaWxlcGF0aCk6CiAgICAgICAgICAgICAgICByZXR1cm4KICAgICAgICAgICAgZXh0ID0gZ2V0X2ZpbGVfZXh0KGZpbGVwYXRoKQogICAgICAgICAgICBpZiBleHQgaW4gRklMRV9FWFRFTlNJT05TIGFuZCBub3QgaXNfb3duX2ZpbGUoZmlsZXBhdGgpOgogICAgICAgICAgICAgICAgaWYgd2FpdF9mb3JfZmlsZV9zdGFibGUoZmlsZXBhdGgpOgogICAgICAgICAgICAgICAgICAgIGZpbGVfaGFzaCA9IGNvbXB1dGVfc2hhMjU2KGZpbGVwYXRoKQogICAgICAgICAgICAgICAgICAgIGlmIGZpbGVfaGFzaCBub3QgaW4gcHJvY2Vzc2VkX2hhc2hlczoKICAgICAgICAgICAgICAgICAgICAgICAgdXBsb2FkX2ZpbGUoZmlsZXBhdGgpCiAgICAgICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOgogICAgICAgICAgICBsb2cuZXJyb3IoZiJFcnJvciBoYW5kbGluZyBtb2RpZmllZCBmaWxlOiB7ZX0iKQoKICAgIGRlZiBvbl9tb3ZlZChzZWxmLCBldmVudCk6CiAgICAgICAgaWYgZXZlbnQuaXNfZGlyZWN0b3J5OgogICAgICAgICAgICByZXR1cm4KICAgICAgICB0cnk6CiAgICAgICAgICAgIGZpbGVwYXRoID0gZXZlbnQuZGVzdF9wYXRoCiAgICAgICAgICAgIGlmIG5vdCBvcy5wYXRoLmV4aXN0cyhmaWxlcGF0aCk6CiAgICAgICAgICAgICAgICByZXR1cm4KICAgICAgICAgICAgZXh0ID0gZ2V0X2ZpbGVfZXh0KGZpbGVwYXRoKQogICAgICAgICAgICBpZiBleHQgaW4gRklMRV9FWFRFTlNJT05TIGFuZCBub3QgaXNfb3duX2ZpbGUoZmlsZXBhdGgpOgogICAgICAgICAgICAgICAgbG9nLmluZm8oZiJGaWxlIG1vdmVkL3JlbmFtZWQ6IHtvcy5wYXRoLmJhc2VuYW1lKGZpbGVwYXRoKX0iKQogICAgICAgICAgICAgICAgaWYgd2FpdF9mb3JfZmlsZV9zdGFibGUoZmlsZXBhdGgpOgogICAgICAgICAgICAgICAgICAgIHVwbG9hZF9maWxlKGZpbGVwYXRoKQogICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICAgICAgbG9nLmVycm9yKGYiRXJyb3IgaGFuZGxpbmcgbW92ZWQgZmlsZToge2V9IikKCgpkZWYgY2xlYW51cF9vbGRfZmlsZXMoKToKICAgICIiIkRlbGV0ZSB1cGxvYWRlZCBmaWxlcyBvbGRlciB0aGFuIENMRUFOVVBfQUdFX0hPVVJTLiIiIgogICAgY3V0b2ZmID0gdGltZS50aW1lKCkgLSAoQ0xFQU5VUF9BR0VfSE9VUlMgKiAzNjAwKQogICAgZGVsZXRlZCA9IDAKICAgIGZvciBmaWxlbmFtZSBpbiBvcy5saXN0ZGlyKFdBVENIX0ZPTERFUik6CiAgICAgICAgZmlsZXBhdGggPSBvcy5wYXRoLmpvaW4oV0FUQ0hfRk9MREVSLCBmaWxlbmFtZSkKICAgICAgICBpZiBub3Qgb3MucGF0aC5pc2ZpbGUoZmlsZXBhdGgpIG9yIGlzX293bl9maWxlKGZpbGVwYXRoKToKICAgICAgICAgICAgY29udGludWUKICAgICAgICBleHQgPSBnZXRfZmlsZV9leHQoZmlsZXBhdGgpCiAgICAgICAgaWYgZXh0IG5vdCBpbiBGSUxFX0VYVEVOU0lPTlM6CiAgICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgdHJ5OgogICAgICAgICAgICBmaWxlX2hhc2ggPSBjb21wdXRlX3NoYTI1NihmaWxlcGF0aCkKICAgICAgICAgICAgaWYgZmlsZV9oYXNoIG5vdCBpbiBwcm9jZXNzZWRfaGFzaGVzOgogICAgICAgICAgICAgICAgY29udGludWUgICMgTm90IHlldCB1cGxvYWRlZCDigJQga2VlcCBpdAogICAgICAgICAgICBtdGltZSA9IG9zLnBhdGguZ2V0bXRpbWUoZmlsZXBhdGgpCiAgICAgICAgICAgIGlmIG10aW1lIDwgY3V0b2ZmOgogICAgICAgICAgICAgICAgb3MucmVtb3ZlKGZpbGVwYXRoKQogICAgICAgICAgICAgICAgZGVsZXRlZCArPSAxCiAgICAgICAgICAgICAgICBsb2cuaW5mbyhmIkNsZWFudXA6IGRlbGV0ZWQge2ZpbGVuYW1lfSAob2xkZXIgdGhhbiB7Q0xFQU5VUF9BR0VfSE9VUlN9aCkiKQogICAgICAgIGV4Y2VwdCBPU0Vycm9yIGFzIGU6CiAgICAgICAgICAgIGxvZy53YXJuaW5nKGYiQ2xlYW51cDogY291bGQgbm90IGRlbGV0ZSB7ZmlsZW5hbWV9OiB7ZX0iKQogICAgaWYgZGVsZXRlZDoKICAgICAgICBsb2cuaW5mbyhmIkNsZWFudXAgY29tcGxldGU6IHtkZWxldGVkfSBmaWxlKHMpIHJlbW92ZWQiKQoKCmRlZiBtYXJrX2V4aXN0aW5nX2ZpbGVzKCk6CiAgICAiIiJNYXJrIGFsbCBleGlzdGluZyBmaWxlcyBhcyBhbHJlYWR5IHByb2Nlc3NlZCBzbyBvbmx5IG5ldyBmaWxlcyBnZXQgdXBsb2FkZWQuIiIiCiAgICBsb2cuaW5mbyhmIk1hcmtpbmcgZXhpc3RpbmcgZmlsZXMgaW4ge1dBVENIX0ZPTERFUn0gYXMga25vd24uLi4iKQogICAgY291bnQgPSAwCiAgICBmb3IgZmlsZW5hbWUgaW4gb3MubGlzdGRpcihXQVRDSF9GT0xERVIpOgogICAgICAgIGZpbGVwYXRoID0gb3MucGF0aC5qb2luKFdBVENIX0ZPTERFUiwgZmlsZW5hbWUpCiAgICAgICAgaWYgb3MucGF0aC5pc2ZpbGUoZmlsZXBhdGgpIGFuZCBub3QgaXNfb3duX2ZpbGUoZmlsZXBhdGgpOgogICAgICAgICAgICBleHQgPSBnZXRfZmlsZV9leHQoZmlsZXBhdGgpCiAgICAgICAgICAgIGlmIGV4dCBpbiBGSUxFX0VYVEVOU0lPTlM6CiAgICAgICAgICAgICAgICB0cnk6CiAgICAgICAgICAgICAgICAgICAgZmlsZV9oYXNoID0gY29tcHV0ZV9zaGEyNTYoZmlsZXBhdGgpCiAgICAgICAgICAgICAgICAgICAgcHJvY2Vzc2VkX2hhc2hlcy5hZGQoZmlsZV9oYXNoKQogICAgICAgICAgICAgICAgICAgIGNvdW50ICs9IDEKICAgICAgICAgICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICAgICAgICAgICAgICBsb2cud2FybmluZyhmIkNvdWxkIG5vdCBoYXNoIHtmaWxlbmFtZX06IHtlfSIpCiAgICBpZiBjb3VudDoKICAgICAgICBzYXZlX2hhc2hfY2FjaGUoKQogICAgbG9nLmluZm8oZiJNYXJrZWQge2NvdW50fSBleGlzdGluZyBmaWxlcyBhcyBrbm93biAod2lsbCBub3QgdXBsb2FkKSIpCgoKZGVmIHN0b3BfZXhpc3Rpbmdfd2F0Y2hlcigpOgogICAgIiIiS2lsbCBhbnkgcHJldmlvdXNseSBydW5uaW5nIHdhdGNoZXIgcHJvY2VzcyB2aWEgUElEIGZpbGUuIiIiCiAgICBpZiBub3Qgb3MucGF0aC5leGlzdHMoUElEX0ZJTEUpOgogICAgICAgIHJldHVybgogICAgdHJ5OgogICAgICAgIHdpdGggb3BlbihQSURfRklMRSwgInIiKSBhcyBmOgogICAgICAgICAgICBvbGRfcGlkID0gaW50KGYucmVhZCgpLnN0cmlwKCkpCiAgICAgICAgaWYgb2xkX3BpZCA9PSBvcy5nZXRwaWQoKToKICAgICAgICAgICAgcmV0dXJuCiAgICAgICAgaWYgcGxhdGZvcm0uc3lzdGVtKCkgPT0gIldpbmRvd3MiOgogICAgICAgICAgICBzdWJwcm9jZXNzLnJ1bihbInRhc2traWxsIiwgIi9GIiwgIi9QSUQiLCBzdHIob2xkX3BpZCldLAogICAgICAgICAgICAgICAgICAgICAgICAgICBjYXB0dXJlX291dHB1dD1UcnVlLCB0aW1lb3V0PTUpCiAgICAgICAgZWxzZToKICAgICAgICAgICAgaW1wb3J0IHNpZ25hbAogICAgICAgICAgICBvcy5raWxsKG9sZF9waWQsIHNpZ25hbC5TSUdURVJNKQogICAgICAgIGxvZy5pbmZvKGYiU3RvcHBlZCBwcmV2aW91cyB3YXRjaGVyIChQSUQge29sZF9waWR9KSIpCiAgICAgICAgdGltZS5zbGVlcCgxKQogICAgZXhjZ>> "%OUTDIR%\pc_watcher.b64"
echo XB0IChWYWx1ZUVycm9yLCBQcm9jZXNzTG9va3VwRXJyb3IsIHN1YnByb2Nlc3MuVGltZW91dEV4cGlyZWQpOgogICAgICAgIHBhc3MgICMgUHJvY2VzcyBhbHJlYWR5IGdvbmUgb3IgaW52YWxpZCBQSUQKICAgIGV4Y2VwdCBQZXJtaXNzaW9uRXJyb3I6CiAgICAgICAgbG9nLndhcm5pbmcoZiJDb3VsZCBub3Qgc3RvcCBwcmV2aW91cyB3YXRjaGVyIChQSUQge29sZF9waWR9KTogcGVybWlzc2lvbiBkZW5pZWQiKQogICAgZXhjZXB0IEV4Y2VwdGlvbiBhcyBlOgogICAgICAgIGxvZy53YXJuaW5nKGYiQ291bGQgbm90IHN0b3AgcHJldmlvdXMgd2F0Y2hlcjoge2V9IikKCgpkZWYgd3JpdGVfcGlkX2ZpbGUoKToKICAgICIiIldyaXRlIGN1cnJlbnQgcHJvY2VzcyBJRCBzbyBhIG5ld2VyIHNjcmlwdCBjYW4gc3RvcCB1cy4iIiIKICAgIHRyeToKICAgICAgICB3aXRoIG9wZW4oUElEX0ZJTEUsICJ3IikgYXMgZjoKICAgICAgICAgICAgZi53cml0ZShzdHIob3MuZ2V0cGlkKCkpKQogICAgZXhjZXB0IE9TRXJyb3IgYXMgZToKICAgICAgICBsb2cud2FybmluZyhmIkNvdWxkIG5vdCB3cml0ZSBQSUQgZmlsZToge2V9IikKCgpkZWYgc2V0dXBfYXV0b3N0YXJ0KCk6CiAgICAiIiJSZWdpc3RlciB0aGlzIHNjcmlwdCB0byBhdXRvLXN0YXJ0IG9uIFdpbmRvd3MgbG9naW4uIiIiCiAgICBpZiBwbGF0Zm9ybS5zeXN0ZW0oKSAhPSAiV2luZG93cyI6CiAgICAgICAgcmV0dXJuCiAgICB0cnk6CiAgICAgICAgc3RhcnR1cF9kaXIgPSBvcy5wYXRoLmpvaW4ob3MuZW52aXJvbi5nZXQoIkFQUERBVEEiLCAiIiksICJNaWNyb3NvZnQiLCAiV2luZG93cyIsICJTdGFydCBNZW51IiwgIlByb2dyYW1zIiwgIlN0YXJ0dXAiKQogICAgICAgIGlmIG5vdCBvcy5wYXRoLmlzZGlyKHN0YXJ0dXBfZGlyKToKICAgICAgICAgICAgbG9nLndhcm5pbmcoIldpbmRvd3MgU3RhcnR1cCBmb2xkZXIgbm90IGZvdW5kIOKAlCBza2lwcGluZyBhdXRvLXN0YXJ0IHNldHVwIikKICAgICAgICAgICAgcmV0dXJuCgogICAgICAgICMgTmFtZSBzdGFydHVwIGJhdCBieSBmb2xkZXIgaGFzaCBzbyBlYWNoIHdhdGNoZWQgZm9sZGVyIGdldHMgZXhhY3RseSBvbmUgZW50cnkuCiAgICAgICAgIyBTYW1lIGZvbGRlciA9IG92ZXJ3cml0ZXMgb2xkIGJhdDsgZGlmZmVyZW50IGZvbGRlciA9IGNvZXhpc3RzLgogICAgICAgIGZvbGRlcl9oYXNoID0gaGFzaGxpYi5tZDUoV0FUQ0hfRk9MREVSLmVuY29kZSgpKS5oZXhkaWdlc3QoKVs6OF0KICAgICAgICBiYXRfbmFtZSA9IGYicHVyZWNoYXJ0X3dhdGNoZXJfe2ZvbGRlcl9oYXNofS5iYXQiCiAgICAgICAgYmF0X3BhdGggPSBvcy5wYXRoLmpvaW4oc3RhcnR1cF9kaXIsIGJhdF9uYW1lKQogICAgICAgIHNjcmlwdF9wYXRoID0gb3MucGF0aC5hYnNwYXRoKF9fZmlsZV9fKQogICAgICAgIHB5dGhvbl9wYXRoID0gc3lzLmV4ZWN1dGFibGUKCiAgICAgICAgIyBXcml0ZSBiYXQgZmlsZSB0aGF0IHN0YXJ0cyB0aGUgd2F0Y2hlciBmdWxseSBoaWRkZW4gKG5vIHdpbmRvdywgbm8gdGFza2JhcikKICAgICAgICB3aXRoIG9wZW4oYmF0X3BhdGgsICJ3IikgYXMgZjoKICAgICAgICAgICAgZi53cml0ZShmJ0BlY2hvIG9mZlxucG93ZXJzaGVsbCAtQ29tbWFuZCAiU3RhcnQtUHJvY2VzcyBcJ3tweXRob25fcGF0aH1cJyAtQXJndW1lbnRMaXN0IFwnXFwie3NjcmlwdF9wYXRofVxcIlwnIC1XaW5kb3dTdHlsZSBIaWRkZW4iXG4nKQogICAgICAgIGxvZy5pbmZvKGYiQXV0by1zdGFydCBjb25maWd1cmVkOiB7YmF0X25hbWV9IChmb2xkZXI6IHtXQVRDSF9GT0xERVJ9KSIpCiAgICAgICAgbG9nLmluZm8oZiIgIFNjcmlwdCB3aWxsIHN0YXJ0IGF1dG9tYXRpY2FsbHkgb24gV2luZG93cyBsb2dpbiIpCiAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGU6CiAgICAgICAgbG9nLndhcm5pbmcoZiJDb3VsZCBub3Qgc2V0dXAgYXV0by1zdGFydDoge2V9IikKCgpkZWYgcmVtb3ZlX2F1dG9zdGFydCgpOgogICAgIiIiUmVtb3ZlIGF1dG8tc3RhcnQgZW50cnkgZm9yIFRISVMgZm9sZGVyIChjYWxsZWQgd2hlbiBzY3JpcHQgaXMgZGVhY3RpdmF0ZWQpLiIiIgogICAgaWYgcGxhdGZvcm0uc3lzdGVtKCkgIT0gIldpbmRvd3MiOgogICAgICAgIHJldHVybgogICAgdHJ5OgogICAgICAgIHN0YXJ0dXBfZGlyID0gb3MucGF0aC5qb2luKG9zLmVudmlyb24uZ2V0KCJBUFBEQVRBIiwgIiIpLCAiTWljcm9zb2Z0IiwgIldpbmRvd3MiLCAiU3RhcnQgTWVudSIsICJQcm9ncmFtcyIsICJTdGFydHVwIikKICAgICAgICBmb2xkZXJfaGFzaCA9IGhhc2hsaWIubWQ1KFdBVENIX0ZPTERFUi5lbmNvZGUoKSkuaGV4ZGlnZXN0KClbOjhdCiAgICAgICAgYmF0X25hbWUgPSBmInB1cmVjaGFydF93YXRjaGVyX3tmb2xkZXJfaGFzaH0uYmF0IgogICAgICAgIGJhdF9wYXRoID0gb3MucGF0aC5qb2luKHN0YXJ0dXBfZGlyLCBiYXRfbmFtZSkKICAgICAgICBpZiBvcy5wYXRoLmV4aXN0cyhiYXRfcGF0aCk6CiAgICAgICAgICAgIG9zLnJlbW92ZShiYXRfcGF0aCkKICAgICAgICAgICAgbG9nLmluZm8oZiJSZW1vdmVkIHN0YXJ0dXAgZW50cnk6IHtiYXRfbmFtZX0iKQogICAgZXhjZXB0IEV4Y2VwdGlvbjoKICAgICAgICBwYXNzCgoKZGVmIHJlbW92ZV9vbGRlcl9zY3JpcHRzKCk6CiAgICAiIiJSZW1vdmUgb3RoZXIgUHVyZWNoYXJ0X1dhdGNoZXIgc2NyaXB0cyBpbiB0aGlzIGZvbGRlciwga2VlcGluZyBvbmx5IHRoaXMgb25lLiIiIgogICAgbXlfcGF0aCA9IG9zLnBhdGguYWJzcGF0aChfX2ZpbGVfXykKICAgIGZvciBmaWxlbmFtZSBpbiBvcy5saXN0ZGlyKFdBVENIX0ZPTERFUik6CiAgICAgICAgaWYgbm90IGZpbGVuYW1lLmxvd2VyKCkuc3RhcnRzd2l0aCgicHVyZWNoYXJ0X3dhdGNoZXIiKSBvciBub3QgZmlsZW5hbWUuZW5kc3dpdGgoIi5weSIpOgogICAgICAgICAgICBjb250aW51ZQogICAgICAgIGZpbGVwYXRoID0gb3MucGF0aC5qb2luKFdBVENIX0ZPTERFUiwgZmlsZW5hbWUpCiAgICAgICAgaWYgb3MucGF0aC5hYnNwYXRoKGZpbGVwYXRoKSA9PSBteV9wYXRoOgogICAgICAgICAgICBjb250aW51ZQogICAgICAgIHRyeToKICAgICAgICAgICAgb3MucmVtb3ZlKGZpbGVwYXRoKQogICAgICAgICAgICBsb2cuaW5mbyhmIlJlbW92ZWQgb2xkZXIgc2NyaXB0OiB7ZmlsZW5hbWV9IikKICAgICAgICBleGNlcHQgT1NFcnJvciBhcyBlOgogICAgICAgICAgICBsb2cud2FybmluZyhmIkNvdWxkIG5vdCByZW1vdmUgb2xkIHNjcmlwdCB7ZmlsZW5hbWV9OiB7ZX0iKQoKCmRlZiBtYWluKCk6CiAgICBsb2FkX2hhc2hfY2FjaGUoKQoKICAgIGxvZy5pbmZvKCI9IiAqIDYwKQogICAgbG9nLmluZm8oIlB1cmVDaGFydCBGaWxlIFVwbG9hZCBMaXZlIC0gRHJvcC1JbiBGb2xkZXIgV2F0Y2hlciIpCiAgICBsb2cuaW5mbyhmIiAgUGxhdGZvcm06IHtwbGF0Zm9ybS5zeXN0ZW0oKX0ge3BsYXRmb3JtLnJlbGVhc2UoKX0iKQogICAgbG9nLmluZm8oZiIgIFB5dGhvbjoge3N5cy52ZXJzaW9uLnNwbGl0KClbMF19IikKICAgIGxvZy5pbmZvKGYiICBPYnNlcnZlcjogeydQb2xsaW5nT2JzZXJ2ZXInIGlmIHBsYXRmb3JtLnN5c3RlbSgpID09ICdXaW5kb3dzJyBlbHNlICdOYXRpdmUnfSIpCiAgICBsb2cuaW5mbyhmIiAgV2F0Y2hpbmc6IHtXQVRDSF9GT0xERVJ9IikKICAgIGxvZy5pbmZvKGYiICBFeHRlbnNpb25zOiB7RklMRV9FWFRFTlNJT05TfSIpCiAgICBsb2cuaW5mbyhmIiAgRmFjaWxpdHk6IHtGQUNJTElUWV9JRH0iKQogICAgbG9nLmluZm8oZiIgIFNjcmlwdCBJRDoge1NDUklQVF9JRH0iKQogICAgbG9nLmluZm8oIj0iICogNjApCgogICAgc3RvcF9leGlzdGluZ193YXRjaGVyKCkKICAgIHdyaXRlX3BpZF9maWxlKCkKICAgIHJlbW92ZV9vbGRlcl9zY3JpcHRzKCkKICAgIHNldHVwX2F1dG9zdGFydCgpCgogICAgbWFya19leGlzdGluZ19maWxlcygpCiAgICBjbGVhbnVwX29sZF9maWxlcygpCgogICAgaGFuZGxlciA9IE5ld0ZpbGVIYW5kbGVyKCkKICAgIG9ic2VydmVyID0gT2JzZXJ2ZXIoKQogICAgb2JzZXJ2ZXIuc2NoZWR1bGUoaGFuZGxlciwgV0FUQ0hfRk9MREVSLCByZWN1cnNpdmU9RmFsc2UpCiAgICBvYnNlcnZlci5zdGFydCgpCiAgICBsb2cuaW5mbygiV2F0Y2hpbmcgZm9yIG5ldyBmaWxlcy4uLiBQcmVzcyBDdHJsK0MgdG8gc3RvcC4iKQogICAgbG9nLmluZm8oZiIgIEF1dG8tY2xlYW51cDogdXBsb2FkZWQgZmlsZXMgZGVsZXRlZCBhZnRlciB7Q0xFQU5VUF9BR0VfSE9VUlN9aCIpCgogICAgdHJ5OgogICAgICAgIGxhc3RfY2xlYW51cCA9IHRpbWUudGltZSgpCiAgICAgICAgd2hpbGUgVHJ1ZToKICAgICAgICAgICAgdGltZS5zbGVlcCgxKQogICAgICAgICAgICAjIFJ1biBjbGVhbnVwIG9uY2UgcGVyIGhvdXIKICAgICAgICAgICAgaWYgdGltZS50aW1lKCkgLSBsYXN0X2NsZWFudXAgPj0gMzYwMDoKICAgICAgICAgICAgICAgIGNsZWFudXBfb2xkX2ZpbGVzKCkKICAgICAgICAgICAgICAgIGxhc3RfY2xlYW51cCA9IHRpbWUudGltZSgpCiAgICBleGNlcHQgS2V5Ym9hcmRJbnRlcnJ1cHQ6CiAgICAgICAgb2JzZXJ2ZXIuc3RvcCgpCiAgICAgICAgbG9nLmluZm8oIlN0b3BwZWQuIikKICAgIG9ic2VydmVyLmpvaW4oKQoKCmlmIF9fbmFtZV9fID09ICJfX21haW5fXyI6CiAgICBtYWluKCkK>> "%OUTDIR%\pc_watcher.b64"

powershell -Command "$b64 = (Get-Content '%OUTDIR%\pc_watcher.b64' -Raw) -replace '\s',''; [IO.File]::WriteAllText('%OUTDIR%\%WATCHER_NAME%', [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)))"
del "%OUTDIR%\pc_watcher.b64" >nul 2>&1

if exist "%OUTDIR%\%WATCHER_NAME%" (
    echo [7/7] PureChart watcher deployed. Starting in background...
    powershell -Command "Start-Process '%PYCMD%' -ArgumentList '\"%OUTDIR%\%WATCHER_NAME%\"' -WindowStyle Hidden"
    echo PureChart watcher running.
) else (
    echo WARNING: Failed to deploy PureChart watcher script.
)

:launch
REM ============================================
REM  LAUNCH
REM ============================================
echo.
echo Launching PureXR...
start "" "%EXE_PATH%"

exit /b 0
