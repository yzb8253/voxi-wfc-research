@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

set "ADB=C:\Users\ZJH\Desktop\platform-tools\adb.exe"
set "SERIAL=fd0ff892"
set "WFCCTL=/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh"
set "OLDRESET=/data/adb/modules/voxi_radio_ims_softreset_v2/voxi-radio-reset.sh"

if /I "%~1"=="holder" goto HOLDER

title Qualcomm SDX55M WFC Recovery

echo.
echo ================================================
echo      Qualcomm SDX55M + VOXI WFC Recovery
echo ================================================
echo.
echo Preconditions:
echo   Airplane mode = ON after reproducing polluted state
echo   Wi-Fi / proxy / location unchanged
echo   Phone rooted with Magisk
echo.
pause

rem ==================================================
rem STEP 1 - ADB
rem ==================================================
echo.
echo [1/10] Checking ADB...

if not exist "%ADB%" (
    echo [FAIL] adb.exe not found:
    echo %ADB%
    goto FINAL_PAUSE
)

"%ADB%" -s %SERIAL% get-state >nul 2>&1
if errorlevel 1 (
    echo [FAIL] Device %SERIAL% not connected.
    goto FINAL_PAUSE
)

echo [OK] ADB connected.

rem ==================================================
rem STEP 2 - ROOT
rem ==================================================
echo.
echo [2/10] Checking ROOT...

"%ADB%" -s %SERIAL% shell "su -c 'id'" > "%TEMP%\x55_root.txt" 2>&1
type "%TEMP%\x55_root.txt"
findstr /C:"uid=0(root)" "%TEMP%\x55_root.txt" >nul
if errorlevel 1 (
    echo [FAIL] ROOT access unavailable.
    goto FINAL_PAUSE
)

echo [OK] ROOT confirmed.

rem ==================================================
rem STEP 3 - MODEM COMPATIBILITY
rem ==================================================
echo.
echo [3/10] Checking modem compatibility...

"%ADB%" -s %SERIAL% shell "su -c 'cat /sys/bus/msm_subsys/devices/subsys10/name'" > "%TEMP%\x55_subsys.txt" 2>&1
"%ADB%" -s %SERIAL% shell "su -c 'cat /sys/bus/esoc/devices/esoc0/esoc_name'" > "%TEMP%\x55_esoc.txt" 2>&1

set "SUBSYS="
set "ESOC="
set /p SUBSYS=<"%TEMP%\x55_subsys.txt"
set /p ESOC=<"%TEMP%\x55_esoc.txt"

echo SUBSYS=%SUBSYS%
echo MODEM=%ESOC%

if /I not "%SUBSYS%"=="esoc0" (
    echo [FAIL] subsys10 is not esoc0.
    goto FINAL_PAUSE
)

if /I not "%ESOC%"=="SDX55M" (
    echo [FAIL] modem is not SDX55M.
    goto FINAL_PAUSE
)

echo [OK] Qualcomm SDX55M confirmed.

rem ==================================================
rem STEP 4 - STOP PERIPHERAL MANAGER
rem ==================================================
echo.
echo [4/10] Stopping vendor.per_mgr...

"%ADB%" -s %SERIAL% shell "su -c 'setprop ctl.stop vendor.per_mgr'"
timeout /t 2 /nobreak >nul

"%ADB%" -s %SERIAL% shell "su -c 'getprop init.svc.vendor.per_mgr'" > "%TEMP%\x55_perm.txt" 2>&1
set "PERMGR="
set /p PERMGR=<"%TEMP%\x55_perm.txt"
echo PER_MGR=%PERMGR%

if /I not "%PERMGR%"=="stopped" (
    echo [FAIL] vendor.per_mgr did not stop.
    goto FINAL_PAUSE
)

rem ==================================================
rem STEP 5 - CLEAN OUR PREVIOUS HOLDER
rem ==================================================
echo.
echo [5/10] Cleaning previous X55 holder...

"%ADB%" -s %SERIAL% shell "su -c 'if [ -f /data/local/tmp/x55_holder.pid ]; then p=$(cat /data/local/tmp/x55_holder.pid); if [ x$(readlink /proc/$p/fd/9 2>/dev/null) = x/dev/subsys_esoc0 ]; then echo Killing_saved_holder_PID=$p; kill -9 $p; fi; rm -f /data/local/tmp/x55_holder.pid; fi'"
timeout /t 2 /nobreak >nul

echo Checking for unknown holders...
"%ADB%" -s %SERIAL% shell "su -c 'lsof /dev/subsys_esoc0 2>/dev/null'" > "%TEMP%\x55_holders.txt" 2>&1
type "%TEMP%\x55_holders.txt"
findstr /C:"/dev/subsys_esoc0" "%TEMP%\x55_holders.txt" >nul
if not errorlevel 1 (
    echo.
    echo [FAIL] Unknown X55 holder still exists.
    echo Close the old manual holder first. Script will not kill it.
    goto FINAL_PAUSE
)

rem ==================================================
rem STEP 6 - WAIT FOR TRUE OFFLINE
rem ==================================================
echo.
echo [6/10] Waiting for true X55 OFFLINE...

set "OFFLINE_OK=0"
for /L %%I in (1,1,20) do (
    "%ADB%" -s %SERIAL% shell "su -c 'cat /sys/bus/msm_subsys/devices/subsys10/state'" > "%TEMP%\x55_state.txt" 2>&1
    set "STATE="
    set /p STATE=<"%TEMP%\x55_state.txt"
    echo Attempt %%I/20 - STATE=!STATE!
    if /I "!STATE!"=="OFFLINE" (
        set "OFFLINE_OK=1"
        goto X55_OFFLINE
    )
    timeout /t 1 /nobreak >nul
)

:X55_OFFLINE
if not "%OFFLINE_OK%"=="1" (
    echo [FAIL] X55 did not enter OFFLINE.
    goto FINAL_PAUSE
)

"%ADB%" -s %SERIAL% shell "su -c 'cat /sys/bus/msm_subsys/devices/subsys10/crash_count'" > "%TEMP%\x55_crash.txt" 2>&1
set "CRASH="
set /p CRASH=<"%TEMP%\x55_crash.txt"

echo STATE=OFFLINE
echo CRASH_COUNT=%CRASH%
if not "%CRASH%"=="0" (
    echo [FAIL] CRASH_COUNT is not zero.
    goto FINAL_PAUSE
)

echo [OK] Clean shutdown confirmed.

rem ==================================================
rem STEP 7 - START HOLDER / WAIT ONLINE
rem ==================================================
echo.
echo [7/10] Starting new X55 holder...

start "X55 HOLDER - DO NOT CLOSE" /min "%ComSpec%" /d /c ""%~f0" holder"
timeout /t 2 /nobreak >nul

set "ONLINE_OK=0"
for /L %%I in (1,1,30) do (
    "%ADB%" -s %SERIAL% shell "su -c 'cat /sys/bus/msm_subsys/devices/subsys10/state'" > "%TEMP%\x55_state.txt" 2>&1
    set "STATE="
    set /p STATE=<"%TEMP%\x55_state.txt"
    echo Attempt %%I/30 - STATE=!STATE!
    if /I "!STATE!"=="ONLINE" (
        set "ONLINE_OK=1"
        goto X55_ONLINE
    )
    timeout /t 1 /nobreak >nul
)

:X55_ONLINE
if not "%ONLINE_OK%"=="1" (
    echo [FAIL] X55 did not return ONLINE.
    goto FINAL_PAUSE
)

echo [OK] X55 is ONLINE.

rem ==================================================
rem STEP 8 - VERIFY X55
rem ==================================================
echo.
echo [8/10] Verifying X55 restart...

"%ADB%" -s %SERIAL% shell "su -c 'echo STATE=$(cat /sys/bus/msm_subsys/devices/subsys10/state); echo CRASH_COUNT=$(cat /sys/bus/msm_subsys/devices/subsys10/crash_count); echo ===HOLDER===; lsof /dev/subsys_esoc0 2>/dev/null'"

"%ADB%" -s %SERIAL% shell "su -c 'cat /sys/bus/msm_subsys/devices/subsys10/crash_count'" > "%TEMP%\x55_crash.txt" 2>&1
set "CRASH="
set /p CRASH=<"%TEMP%\x55_crash.txt"
if not "%CRASH%"=="0" (
    echo [FAIL] X55 returned ONLINE but CRASH_COUNT is not zero.
    goto FINAL_PAUSE
)

echo.
echo === RECENT ESOC LOG ===
"%ADB%" -s %SERIAL% shell "su -c 'cat /sys/kernel/debug/ipc_logging/esoc-mdm/log 2>/dev/null | tail -n 60'"

echo.
echo [OK] X55 restart stage complete.

rem ==================================================
rem STEP 9 - SOFTWARE REINSERT MODULE
rem ==================================================
echo.
echo [9/10] Checking Codex VOXI software-reinsert module...

"%ADB%" -s %SERIAL% shell "su -c 'if [ -f %WFCCTL% ]; then echo NEW_FOUND; elif [ -f %OLDRESET% ]; then echo OLD_FOUND; else echo MISSING; fi'" > "%TEMP%\voxi_module.txt" 2>&1
set "MODULESTATE="
set /p MODULESTATE=<"%TEMP%\voxi_module.txt"
echo MODULE=%MODULESTATE%

if /I "%MODULESTATE%"=="OLD_FOUND" (
    echo.
    echo [STOP] Older voxi_radio_ims_softreset_v2 module was found.
    echo Its command interface is not assumed automatically in this build.
    echo X55 restart is complete; do not run an unverified reset command.
    echo.
    echo Old module path:
    echo %OLDRESET%
    goto FINAL_PAUSE
)

if /I not "%MODULESTATE%"=="NEW_FOUND" (
    echo.
    echo [STOP] VOXI WFC Recovery module not found.
    echo Expected:
    echo %WFCCTL%
    echo.
    echo X55 restart is complete. You may use physical SIM reinsertion.
    goto FINAL_PAUSE
)

echo.
echo Installed module:
"%ADB%" -s %SERIAL% shell "su -c '%WFCCTL% version'"

echo.
echo Initial WFC state:
"%ADB%" -s %SERIAL% shell "su -c '%WFCCTL% status'"

rem ==================================================
rem STEP 10 - SOFTWARE SIM REINSERT WITH ONE RETRY
rem ==================================================
echo.
echo [10/10] Software SIM reinsertion attempt 1...
call :RUN_SOFT_REINSERT 1

echo.
echo Checking WFC health after attempt 1...
call :CHECK_WFC
if not errorlevel 1 goto WFC_SUCCESS

echo.
echo ================================================
echo Attempt 1 did not restore WFC.
echo Starting software SIM reinsertion attempt 2.
echo ================================================
timeout /t 5 /nobreak >nul

call :RUN_SOFT_REINSERT 2

echo.
echo Checking WFC health after attempt 2...
call :CHECK_WFC
if not errorlevel 1 goto WFC_SUCCESS

echo.
echo ================================================
echo        AUTOMATIC WFC RECOVERY FAILED
echo ================================================
echo.
echo X55 restart succeeded.
echo Two software SIM reinsertion attempts were made.
echo No third automatic attempt will be performed.
echo.
echo Keep airplane mode ON and keep the X55 HOLDER alive.
echo Next fallback: physically remove and reinsert VOXI SIM.
echo.
"%ADB%" -s %SERIAL% shell "su -c '%WFCCTL% status'"
goto FINAL_PAUSE

:WFC_SUCCESS
echo.
echo ================================================
echo          VOXI WFC RECOVERY SUCCESS
echo ================================================
echo.
echo X55 independent restart : SUCCESS
echo VOXI software reinsert  : SUCCESS
echo IMS over WLAN           : REGISTERED
echo WFC                     : AVAILABLE
echo.
echo No physical SIM reinsertion is required.
echo Keep the X55 HOLDER window running.
echo.
"%ADB%" -s %SERIAL% shell "su -c '%WFCCTL% status'"
goto FINAL_PAUSE

rem ==================================================
rem SUBROUTINE - RUN ONE SOFTWARE REINSERT
rem ==================================================
:RUN_SOFT_REINSERT
set "ATTEMPT=%~1"
echo.
echo Running Codex deep-recover attempt %ATTEMPT%...
"%ADB%" -s %SERIAL% shell "su -c '%WFCCTL% deep-recover'" > "%TEMP%\voxi_reinsert_%ATTEMPT%.txt" 2>&1
type "%TEMP%\voxi_reinsert_%ATTEMPT%.txt"
echo.
echo Software reinsert attempt %ATTEMPT% finished.
exit /b 0

rem ==================================================
rem SUBROUTINE - CHECK REAL WFC HEALTH
rem ==================================================
:CHECK_WFC
echo.
echo Reading IMS / IWLAN / WFC state...
"%ADB%" -s %SERIAL% shell "su -c '%WFCCTL% status-json'" > "%TEMP%\voxi_status.json" 2>&1
type "%TEMP%\voxi_status.json"
echo.

powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; try { $j=Get-Content -Raw '%TEMP%\voxi_status.json' | ConvertFrom-Json; $ok=($j.subscription.active -eq $true) -and ($j.subscription.areUiccApplicationsEnabled -eq $true) -and ($j.ims.registrationStateRaw -eq 2) -and ($j.ims.registrationTransportRaw -eq 2) -and ($j.mmtel.voiceIwlanAvailable -eq $true) -and ($j.wfc.wifiCallingAvailable -eq $true); if($ok){exit 0}else{exit 1} } catch { exit 2 }"

if errorlevel 2 (
    echo [WARN] Unable to parse WFC status JSON.
    exit /b 1
)
if errorlevel 1 (
    echo [NOT READY] IMS/WLAN/WFC health gate did not pass.
    exit /b 1
)

echo [HEALTHY] IMS REGISTERED + WLAN + VOICE/IWLAN + WFC AVAILABLE
exit /b 0

rem ==================================================
rem FINAL SCREEN
rem ==================================================
:FINAL_PAUSE
echo.
echo ================================================
echo Script finished. This window will stay open.
echo ================================================
echo.
pause
exit /b 0

rem ==================================================
rem HOLDER MODE
rem ==================================================
:HOLDER
title X55 HOLDER - DO NOT CLOSE
echo.
echo ================================================
echo             X55 HOLDER ACTIVE
echo ================================================
echo.
echo DO NOT CLOSE THIS WINDOW.
echo.

"%ADB%" -s %SERIAL% shell "su -c 'echo $$ >/data/local/tmp/x55_holder.pid; exec 9</dev/subsys_esoc0 || exit 91; echo ===X55_HOLDER_OPEN===; while true; do sleep 60; done'"

echo.
echo ================================================
echo X55 HOLDER EXITED
echo X55 may now lose its subsystem vote.
echo ================================================
echo.
pause
exit /b 0
