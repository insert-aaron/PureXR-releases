How to share/run on another Windows PC
=====================================

1) On your dev machine, build:
   - CaptureService: Release | x86
   - RvgCaptureGui: Release | x64

2) Copy this folder to the other PC (USB/zip):
   - RvgCaptureGui\bin\Release\

   It must contain:
   - RvgCaptureGui.exe
   - CaptureService.exe
   - NTwain.dll (and any other dlls)

3) On the other PC:
   - Install RVG drivers (TWAIN sources must be available to 32-bit apps)
   - Ensure .NET Framework 4.8 exists (Windows 10/11 typically has it)

4) Run:
   - SetupAndRun.bat  (preferred "one entry point")
     or Run-RvgCaptureGui.bat (just launches + basic checks)

If you want to distribute ONLY one file and download the app:
   - BootstrapFromUrl.bat
     Edit it and set APP_ZIP_URL to your hosted ZIP.
     ZIP can contain nested folders (script will locate RvgCaptureGui.exe).
     Script also creates a Desktop shortcut (uses Assets\app.ico if present; else exe icon).

The app defaults output to:
  Desktop\X-Ray Images - DO NOT Delete
and will create it if missing.

