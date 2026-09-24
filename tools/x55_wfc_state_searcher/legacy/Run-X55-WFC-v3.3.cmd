@echo off
setlocal EnableExtensions
title X55 VOXI WFC State Searcher v3.3

set "SCRIPT=%~dp0X55-WFC-StateSearcher-v3.3.ps1"

echo ============================================================
echo  X55 + VOXI WFC STATE SEARCHER v3.3
echo ============================================================
echo.

if not exist "%SCRIPT%" (
    echo [ERROR] Script not found:
    echo %SCRIPT%
    echo.
    echo Put this CMD and X55-WFC-StateSearcher-v3.3.ps1 in the same folder.
    echo.
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "RC=%ERRORLEVEL%"

echo.
echo ============================================================
echo v3.3 finished. ExitCode=%RC%
echo.
echo If there was an error, check:
echo %USERPROFILE%\Desktop\WFC-StateSearch-v3\v3-crash.log
echo ============================================================
echo.
pause
exit /b %RC%
