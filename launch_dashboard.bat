@echo off
setlocal
title TinyQV RV2A03 NES APU Web Dashboard

echo ============================================================
echo   Launching TinyQV RV2A03 NES APU Web Serial Dashboard
echo ============================================================
echo.

where python >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo [OK] Python detected. Starting local HTTP server on port 8080...
    echo [INFO] Opening http://localhost:8080/web/ in your browser...
    echo [TIP] Press Ctrl+C in this window to stop the server.
    echo.
    start "" http://localhost:8080/web/
    python -m http.server 8080
) else (
    echo [INFO] Python not found in PATH. Using native PowerShell launcher...
    powershell -ExecutionPolicy Bypass -File "%~dp0launch_dashboard.ps1"
)

pause
