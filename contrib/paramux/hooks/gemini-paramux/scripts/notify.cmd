@echo off
setlocal DisableDelayedExpansion

pushd "%~dp0" >nul
if errorlevel 1 (
  >&2 echo paramux Gemini hook: could not enter the trusted extension directory.
  exit /b 1
)

set "NODE_EXE="
for %%I in (node.exe) do set "NODE_EXE=%%~$PATH:I"
if not defined NODE_EXE (
  popd
  >&2 echo paramux Gemini hook: node.exe was not found on PATH.
  exit /b 1
)

"%NODE_EXE%" "%~dp0notify.cjs"
set "HOOK_EXIT=%ERRORLEVEL%"
popd
exit /b %HOOK_EXIT%
