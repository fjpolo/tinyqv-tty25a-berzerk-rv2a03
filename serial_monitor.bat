@echo off
REM Tang Nano 20K Serial Monitor Launcher for VS Code Terminal / Windows CMD
REM Automatically detects USB-UART port and connects at 115200 8N1

powershell -ExecutionPolicy Bypass -File "%~dp0serial_monitor.ps1" %*
