rem ==================================================
rem STEP 8 - VERIFY X55
rem ==================================================

echo.
echo [8/10] Verifying X55 restart...

"%ADB%" -s %SERIAL% shell "su -c 'echo STATE=$(cat /sys/bus/msm_subsys/devices/subsys10/state); echo CRASH_COUNT=$(cat /sys/bus/msm_subsys/devices/subsys10/crash_count); echo ===HOLDER===; lsof /dev/subsys_esoc0 2>/dev/null'"

echo.
echo === RECENT ESOC LOG ===
"%ADB%" -s %SERIAL% shell "su -c 'cat /sys/kernel/debug/ipc_logging/esoc-mdm/log 2>/dev/null | tail -n 45'"

echo.
echo [OK] X55 restart stage complete.


rem ==================================================
rem STEP 9 - LOCATE CODEX WFC MODULE
rem ==================================================

echo.
echo [9/10] Checking Codex VOXI software-reinsert module...

set "WFCCTL=/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh"

"%ADB%" -s %SERIAL% shell "su -c 'if [ -f /data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh ]; then echo FOUND; else echo MISSING; fi'" > "%TEMP%\voxi_module.txt" 2>&1

set "MODULESTATE="
set /p MODULESTATE=<"%TEMP%\voxi_module.txt"

echo MODULE=%MODULESTATE%

if /I not "%MODULESTATE%"=="FOUND" (
    echo.
    echo ================================================
    echo [STOP] CODEX WFC MODULE NOT FOUND
    echo ================================================
    echo.
    echo Expected:
    echo /data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh
    echo.
    echo X55 restart itself has completed successfully.
    echo Do NOT perform an unknown software SIM command.
    echo You can still manually reinsert the VOXI SIM.
    echo.
    goto FINAL_PAUSE
)

echo.
echo Installed module:
"%ADB%" -s %SERIAL% shell "su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh version'"

echo.
echo Initial WFC status:
"%ADB%" -s %SERIAL% shell "su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh status'"

echo.


rem ==================================================
rem STEP 10 - SOFTWARE SIM REINSERT #1
rem ==================================================

echo.
echo ================================================
echo SOFTWARE SIM REINSERT - ATTEMPT 1
echo ================================================
echo.
echo This will perform the Codex UICC false - true cycle
echo for VOXI subId 11 / slot 1 only.
echo.

call :RUN_SOFT_REINSERT 1

echo.
echo Checking WFC health after attempt 1...
call :CHECK_WFC

if not errorlevel 1 (
    goto WFC_SUCCESS
)


rem ==================================================
rem SOFTWARE SIM REINSERT #2
rem ==================================================

echo.
echo ================================================
echo ATTEMPT 1 DID NOT RESTORE WFC
echo STARTING SOFTWARE REINSERT ATTEMPT 2
echo ================================================
echo.

call :RUN_SOFT_REINSERT 2

echo.
echo Checking WFC health after attempt 2...
call :CHECK_WFC

if not errorlevel 1 (
    goto WFC_SUCCESS
)


rem ==================================================
rem BOTH ATTEMPTS FAILED
rem ==================================================

echo.
echo ================================================
echo       AUTOMATIC WFC RECOVERY FAILED
echo ================================================
echo.
echo X55 restart: SUCCESS
echo Software SIM reinsert #1: WFC not healthy
echo Software SIM reinsert #2: WFC not healthy
echo.
echo No third software reinsert will be attempted.
echo.
echo Keep airplane mode ON.
echo Keep X55 HOLDER running.
echo.
echo Next fallback:
echo manually remove and insert the VOXI SIM.
echo.

"%ADB%" -s %SERIAL% shell "su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh status'"

goto FINAL_PAUSE



rem ==================================================
rem SUCCESS
rem ==================================================

:WFC_SUCCESS

echo.
echo ================================================
echo.
echo          VOXI WFC RECOVERY SUCCESS
echo.
echo ================================================
echo.
echo X55 independent restart : SUCCESS
echo VOXI software reinsertion: SUCCESS
echo IMS over WLAN            : REGISTERED
echo WFC                      : AVAILABLE
echo.
echo NO physical SIM reinsertion is required.
echo.
echo Keep the X55 HOLDER window running.
echo.

"%ADB%" -s %SERIAL% shell "su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh status'"

goto FINAL_PAUSE



rem ==================================================
rem RUN ONE SOFTWARE REINSERT
rem ==================================================

:RUN_SOFT_REINSERT

set "ATTEMPT=%~1"

echo.
echo Running Codex deep-recover attempt %ATTEMPT%...
echo.

"%ADB%" -s %SERIAL% shell "su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh deep-recover'" > "%TEMP%\voxi_reinsert_%ATTEMPT%.txt" 2>&1

type "%TEMP%\voxi_reinsert_%ATTEMPT%.txt"

echo.
echo Software reinsert attempt %ATTEMPT% finished.
echo.

exit /b 0



rem ==================================================
rem CHECK REAL WFC HEALTH
rem ==================================================

:CHECK_WFC

echo.
echo Reading IMS / IWLAN / WFC state...

"%ADB%" -s %SERIAL% shell "su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh status-json'" > "%TEMP%\voxi_status.json" 2>&1

type "%TEMP%\voxi_status.json"

echo.

powershell.exe -NoProfile -Command ^
  "$ErrorActionPreference='Stop'; try { $j=Get-Content -Raw '%TEMP%\voxi_status.json' | ConvertFrom-Json; $ok=($j.subscription.active -eq $true) -and ($j.subscription.areUiccApplicationsEnabled -eq $true) -and ($j.ims.registrationStateRaw -eq 2) -and ($j.ims.registrationTransportRaw -eq 2) -and ($j.mmtel.voiceIwlanAvailable -eq $true) -and ($j.wfc.wifiCallingAvailable -eq $true); if($ok){exit 0}else{exit 1} } catch { exit 2 }"

if errorlevel 2 (
    echo [WARN] Unable to parse WFC status JSON.
    exit /b 1
)

if errorlevel 1 (
    echo.
    echo [NOT READY]
    echo IMS/WLAN/WFC health gate did not pass.
    exit /b 1
)

echo.
echo [HEALTHY]
echo IMS REGISTERED + WLAN + VOICE/IWLAN + WFC AVAILABLE

exit /b 0



rem ==================================================
rem FINAL SCREEN - DO NOT AUTO CLOSE
rem ==================================================

:FINAL_PAUSE

echo.
echo ================================================
echo Script finished.
echo This window will stay open.
echo ================================================
echo.
pause
exit /b 0

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
exit /b