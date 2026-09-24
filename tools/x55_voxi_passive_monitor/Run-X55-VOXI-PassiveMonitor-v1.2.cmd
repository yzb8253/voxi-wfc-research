@echo off
setlocal EnableExtensions
title X55 VOXI WFC Deep Passive Monitor v1.2

set "SCRIPT=%~dp0X55-VOXI-PassiveMonitor-v1.2.ps1"

if not exist "%SCRIPT%" (
    echo [ERROR] Script not found:
    echo %SCRIPT%
    echo.
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"

echo.
echo Monitor window closed.
echo.
pause
