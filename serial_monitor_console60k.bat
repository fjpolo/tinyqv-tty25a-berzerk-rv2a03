@echo off
rem ============================================================================
rem Tang Console 60K Serial Monitor Launcher (Bypasses execution policy)
rem Automatically connects to COM19 at 115200 8N1
rem ============================================================================

setlocal
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serial_monitor_console60k.ps1" %*
exit /b %ERRORLEVEL%
