@echo off
setlocal EnableExtensions
title X55 VOXI WFC State Searcher v3.4

set "SCRIPT=%~dp0X55-WFC-StateSearcher-v3.4.ps1"

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
echo ============================================================
echo v3.4 finished. ExitCode=%RC%
echo.
echo If there was an error, check:
echo %USERPROFILE%\Desktop\WFC-StateSearch-v3\v3-crash.log
echo ============================================================
echo.
pause
exit /b %RC%
