@echo off
setlocal
cd /d "%~dp0"
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0X55-WFC-STABLE-CNE-V1.ps1"
set "RC=%ERRORLEVEL%"
echo.
echo STABLE_CNE_V1 exit=%RC%
exit /b %RC%
