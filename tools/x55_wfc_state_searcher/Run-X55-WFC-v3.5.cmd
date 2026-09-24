@echo off
setlocal EnableExtensions
title X55 VOXI WFC Timing Searcher v3.5

set "SCRIPT=%~dp0X55-WFC-StateSearcher-v3.5.ps1"

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
echo v3.5 finished. ExitCode=%RC%
echo.
echo Results:
echo %USERPROFILE%\Desktop\WFC-StateSearch-v3.5
echo.
echo If there was an error:
echo %USERPROFILE%\Desktop\WFC-StateSearch-v3.5\v3.5-crash.log
echo ============================================================
echo.
pause
exit /b %RC%
