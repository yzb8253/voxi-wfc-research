@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0X55-WFC-GOLDEN-SIMPLE-V1.ps1"
set "rc=%ERRORLEVEL%"
echo.
echo GOLDEN_SIMPLE_V1 exit=%rc%
exit /b %rc%
