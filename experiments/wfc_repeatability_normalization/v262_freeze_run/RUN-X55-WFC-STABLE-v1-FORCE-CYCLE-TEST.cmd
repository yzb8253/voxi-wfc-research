@echo off
setlocal
cd /d "%~dp0"
title X55 VOXI WFC STABLE v1 - FORCE CYCLE TEST

echo ============================================================
echo   X55 + VOXI WFC STABLE v1 - FORCE CYCLE VALIDATION
echo ============================================================
echo.
echo TEST MODE:
echo - Intentionally cycles from a currently healthy WFC state.
echo - Uses the same stable wrapper and unchanged v2.6.2 recovery core.
echo - On success, freezes the healthy state again.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0X55-WFC-STABLE-v1.ps1" -ForceCycle
set RC=%ERRORLEVEL%

echo.
echo ============================================================
echo Force-cycle test exit code: %RC%
echo ============================================================
pause
exit /b %RC%
