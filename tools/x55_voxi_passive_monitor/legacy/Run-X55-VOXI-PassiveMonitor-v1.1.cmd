@echo off
setlocal EnableExtensions
title X55 VOXI WFC Passive Monitor v1.1

set "SCRIPT=%~dp0X55-VOXI-PassiveMonitor-v1.1.ps1"

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
