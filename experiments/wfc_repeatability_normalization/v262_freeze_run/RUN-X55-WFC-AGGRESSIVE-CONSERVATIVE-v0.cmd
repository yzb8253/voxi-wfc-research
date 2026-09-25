@echo off
setlocal
cd /d "%~dp0"
echo MODE=AGGRESSIVE_CONSERVATIVE_V0
echo This is an experimental fail-closed wrapper. The golden entry remains separate.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0X55-WFC-AGGRESSIVE-CONSERVATIVE-v0.ps1"
set "RC=%ERRORLEVEL%"
echo.
echo AGGRESSIVE_CONSERVATIVE_EXIT=%RC%
pause
exit /b %RC%
