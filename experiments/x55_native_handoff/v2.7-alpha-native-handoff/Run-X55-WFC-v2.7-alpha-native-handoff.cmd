@echo off
setlocal
set "SCRIPT=%~dp0X55-WFC-OneClick-v2.7-alpha-native-handoff.ps1"
if /I "%~1"=="execute" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Execute -Confirmation EXECUTE-V2.7-ALPHA-NATIVE-HANDOFF
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
)
exit /b %ERRORLEVEL%
