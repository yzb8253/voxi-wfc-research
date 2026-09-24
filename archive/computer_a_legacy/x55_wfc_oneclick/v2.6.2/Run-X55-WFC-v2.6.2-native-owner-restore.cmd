@echo off
setlocal EnableExtensions
title X55 VOXI WFC v2.6.2 Native Owner Restore

set "SCRIPT=%~dp0X55-WFC-OneClick-v2.6.2-native-owner-restore.ps1"

if not exist "%SCRIPT%" (
    echo [ERROR] Script not found:
    echo %SCRIPT%
    echo.
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "RC=%ERRORLEVEL%"

echo.
echo Script exit code: %RC%
pause
exit /b %RC%
