@echo off
REM Double-click this to add paramux to your PATH (runs install-paramux.ps1).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-paramux.ps1" %*
echo.
pause
