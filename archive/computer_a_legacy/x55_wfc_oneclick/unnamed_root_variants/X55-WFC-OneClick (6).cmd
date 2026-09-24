@echo off
setlocal
title X55 + VOXI WFC One-Click Recovery
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0X55-WFC-OneClick.ps1"
set "RC=%ERRORLEVEL%"
echo.
echo PowerShell exited with code %RC%.
echo.
pause
exit /b %RC%
