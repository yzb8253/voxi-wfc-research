@echo off
setlocal
cd /d "%~dp0"
title X55 VOXI WFC STABLE v1

echo ============================================================
echo      X55 + VOXI WFC STABLE WRAPPER v1
echo ============================================================
echo.
echo USER ENTRY:
echo - Start with airplane mode OFF.
echo - Keep USB debugging/root available.
echo - The script prepares A0, turns airplane mode ON,
echo   runs the proven v2.6.2 recovery core, and on success
echo   leaves the phone in airplane mode ON + WFC HEALTHY.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0X55-WFC-STABLE-v1.ps1"
set RC=%ERRORLEVEL%

echo.
echo ============================================================
echo Stable wrapper exit code: %RC%
echo ============================================================
pause
exit /b %RC%
