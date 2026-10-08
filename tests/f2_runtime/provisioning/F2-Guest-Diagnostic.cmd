@echo off
setlocal DisableDelayedExpansion
title F2 Sandbox Readiness - Diagnostic Only
echo.
echo =========================================================
echo F2 GUEST WRAPPER STARTED
echo F2 STAGE: CMD_ENTRY
echo =========================================================
echo Guest-local diagnostic startup only.
echo F2 native runtime: NOT RUN
if not exist "C:\F2Input\Start-F2SandboxDiagnostics.ps1" goto :missing_bootstrap
echo F2 STAGE: BOOTSTRAP_PRESENT
if not exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" goto :missing_powershell
echo F2 STAGE: POWERSHELL_LAUNCH
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\F2Input\Start-F2SandboxDiagnostics.ps1"
set "F2_PS_EXIT=%ERRORLEVEL%"
echo.
echo F2 STAGE: POWERSHELL_RETURNED
echo F2 PowerShell process exit code: %F2_PS_EXIT%
echo CAUTION: Process exit 0 is NOT proof of guest readiness.
goto :complete

:missing_bootstrap
echo F2 STATUS: BLOCKED_ENVIRONMENT
echo F2 ERROR: Reviewed bootstrap missing from C:\F2Input.
goto :complete

:missing_powershell
echo F2 STATUS: BLOCKED_ENVIRONMENT
echo F2 ERROR: Guest Windows PowerShell executable is missing.
goto :complete

:complete
echo.
echo F2 native runtime: NOT RUN
echo F2 WRAPPER FINISHED - cmd.exe /k must keep this console open.
echo Capture this window; close Sandbox normally to discard guest-local state.
