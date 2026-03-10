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
SET WATCHER_NAME=Purechart_Watcher_Austin_e70abf0a.py
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
        echo Update complete. Restarting...
        start "" "%INSTALL_DIR%\SetupAndRun.bat"
        exit /b 0
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
if defined PYCMD goto :watcher_deps

REM Python not found — install it
echo [7/7] Python not found. Installing Python 3.12...
winget --version >nul 2>&1
if %errorlevel%==0 (
    winget install Python.Python.3.12 --accept-package-agreements --accept-source-agreements
    SET "PATH=%LOCALAPPDATA%\Programs\Python\Python312;%LOCALAPPDATA%\Programs\Python\Python312\Scripts;%PATH%"
    python --version >nul 2>&1
    if %errorlevel%==0 set PYCMD=python
)
if defined PYCMD goto :watcher_deps

certutil -urlcache -split -f "https://www.python.org/ftp/python/3.12.8/python-3.12.8-amd64.exe" "%TEMP%\python_installer.exe" >nul 2>&1
"%TEMP%\python_installer.exe" /quiet InstallAllUsers=0 PrependPath=1 Include_pip=1
del "%TEMP%\python_installer.exe" >nul 2>&1
SET "PATH=%LOCALAPPDATA%\Programs\Python\Python312;%LOCALAPPDATA%\Programs\Python\Python312\Scripts;%PATH%"
python --version >nul 2>&1
if %errorlevel%==0 set PYCMD=python

if not defined PYCMD (
    echo WARNING: Could not install Python. PureChart watcher will not run.
    goto :launch
)

:watcher_deps
echo [7/7] Python OK. Installing watcher dependencies...
%PYCMD% -m pip install --quiet --upgrade pip >nul 2>&1
%PYCMD% -m pip install --quiet watchdog requests

REM Copy watcher script from dist into the X-Ray output folder
echo [7/7] Deploying watcher to output folder...
copy /Y "%INSTALL_DIR%\dist\%WATCHER_NAME%" "%OUTDIR%\%WATCHER_NAME%" >nul 2>&1
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
