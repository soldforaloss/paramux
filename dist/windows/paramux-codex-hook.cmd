@echo off
setlocal DisableDelayedExpansion

pushd "%~dp0" >nul
if errorlevel 1 (
  >&2 echo paramux Codex hook: could not enter the trusted Paramux install directory.
  exit /b 1
)

set "NODE_EXE="
for %%I in (node.exe) do set "NODE_EXE=%%~$PATH:I"
if not defined NODE_EXE (
  popd
  >&2 echo paramux Codex hook: node.exe was not found on PATH.
  exit /b 1
)

"%NODE_EXE%" "%~dp0agent-hooks\codex\paramux-hook.cjs"
set "HOOK_EXIT=%ERRORLEVEL%"
popd
exit /b %HOOK_EXIT%
