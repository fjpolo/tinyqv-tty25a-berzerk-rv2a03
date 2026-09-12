@echo off
rem ============================================================================
rem Gowin Build Flow Launcher for Sipeed Tang Console 60K
rem ============================================================================

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0FPGA\GOWIN\console60k\build.ps1" %*
exit /b %ERRORLEVEL%
