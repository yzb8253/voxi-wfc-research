@echo off
setlocal
cd /d "%~dp0"
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0X55-WFC-AGGRESSIVE-CONSERVATIVE-v1.2H.ps1"
set "RC=%ERRORLEVEL%"
echo.
echo AGGRESSIVE_CONSERVATIVE_v1.2H exit=%RC%
exit /b %RC%
