@echo off
setlocal
cd /d "%~dp0"
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0X55-WFC-HOLDER-AB-r2.ps1" -ABVariant FAST
set "RC=%ERRORLEVEL%"
echo.
echo HOLDER_AB_R2 FAST exit=%RC%
exit /b %RC%
