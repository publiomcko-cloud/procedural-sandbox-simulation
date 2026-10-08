@echo off
setlocal
"%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-F2SandboxReadiness.ps1"
if errorlevel 1 (
  echo F2 Sandbox launch stopped. Review the error above; no security setting was changed.
  pause
  exit /b 1
)
echo Review the guest security report. Close this window when finished.
pause
exit /b 0
