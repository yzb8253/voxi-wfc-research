@echo off
setlocal
cd /d "%~dp0"
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0X55-WFC-AGGRESSIVE-FAST-HOLDER-v0.ps1"
set "RC=%ERRORLEVEL%"
echo.
echo AGGRESSIVE_FAST_HOLDER_v0 exit=%RC%
exit /b %RC%
