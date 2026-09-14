@echo off
rem ============================================================================
rem TinyQV RV2A03 Firmware Build Launcher
rem ============================================================================

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_firmware.ps1" %*
exit /b %ERRORLEVEL%
