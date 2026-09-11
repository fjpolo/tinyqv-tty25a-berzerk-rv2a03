@echo off
rem ============================================================================
rem Gowin Build Flow Launcher (Bypasses PowerShell execution policy)
rem ============================================================================

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0FPGA\GOWIN\nano20k\build.ps1" %*
exit /b %ERRORLEVEL%
