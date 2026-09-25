@echo off
setlocal
cd /d "%~dp0"
title X55 VOXI WFC STABLE v1

echo ============================================================
echo      X55 + VOXI WFC STABLE WRAPPER v1
echo ============================================================
echo.
echo This launcher uses the proven v2.6.2 recovery core.
echo It can automatically return to A0 and retry once after failure.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0X55-WFC-STABLE-v1.ps1"
set RC=%ERRORLEVEL%

echo.
echo ============================================================
echo Stable wrapper exit code: %RC%
echo ============================================================
pause
exit /b %RC%
