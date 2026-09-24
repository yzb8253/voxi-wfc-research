param(
    [switch]$Holder
)

$ErrorActionPreference = 'Stop'
$Adb = 'C:\Users\ZJH\Desktop\platform-tools\adb.exe'
$Serial = 'fd0ff892'
$WfcCtl = '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh'
$HolderPidFile = '/data/local/tmp/x55_holder.pid'
$SubsysPath = '/sys/bus/msm_subsys/devices/subsys10'
$EsocLog = '/sys/kernel/debug/ipc_logging/esoc-mdm/log'

# IMPORTANT: Binder transaction 182 is validated only on this exact ROM/build.
$ExpectedDevice = 'cas'
$ExpectedAndroid = '13'
$ExpectedBuild = 'V816.0.4.0.TJJCNXM'
$ExpectedFingerprint = 'Xiaomi/cas/cas:13/TKQ1.221114.001/V816.0.4.0.TJJCNXM:user/release-keys'
$SimPowerTransaction = 182
$PostPonSettleSeconds = 10
$SimPowerOffHoldSeconds = 8
$ScriptVersion = 'v2.2'

function Invoke-AdbResult {
    param(
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [switch]$Quiet,
        [switch]$NoLog
    )

    $display = 'adb ' + ($Arguments -join ' ')
    if (-not $NoLog -and $script:LogFile) {
        Add-Content -LiteralPath $script:LogFile -Value ('[{0}] CMD: {1}' -f (Get-Date -Format 'HH:mm:ss.fff'), $display)
    }

    $lines = @(& $Adb @Arguments 2>&1)
    $code = $LASTEXITCODE
    $text = ($lines | ForEach-Object { [string]$_ }) -join [Environment]::NewLine

    if (-not $NoLog -and $script:LogFile -and $text) {
        Add-Content -LiteralPath $script:LogFile -Value $text
    }
    if (-not $Quiet -and $text) {
        Write-Host $text
    }

    [pscustomobject]@{
        Code = $code
        Text = $text.Trim()
    }
}

function Invoke-Root {
    param(
        [Parameter(Mandatory=$true)][string]$Command,
        [switch]$Quiet,
        [switch]$NoLog
    )
    Invoke-AdbResult -Arguments @('-s', $Serial, 'shell', "su -c '$Command'") -Quiet:$Quiet -NoLog:$NoLog
}

function Write-Log {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss.fff'), $Message
    Add-Content -LiteralPath $script:LogFile -Value $line
}

function Fail {
    param([string]$Message)
    Write-Host ''
    Write-Host ('[FAIL] ' + $Message) -ForegroundColor Red
    Write-Log ('FAIL: ' + $Message)
    throw $Message
}

function Get-Prop {
    param([string]$Name)
    $r = Invoke-AdbResult -Arguments @('-s', $Serial, 'shell', 'getprop', $Name) -Quiet
    if ($r.Code -ne 0) { return '' }
    return $r.Text.Trim()
}

function Get-X55State {
    $r = Invoke-Root -Command "cat $SubsysPath/state" -Quiet
    if ($r.Code -ne 0) { return '' }
    return $r.Text.Trim()
}

function Get-CrashCount {
    $r = Invoke-Root -Command "cat $SubsysPath/crash_count" -Quiet
    if ($r.Code -ne 0) { return $null }
    $v = 0
    if ([int]::TryParse($r.Text.Trim(), [ref]$v)) { return $v }
    return $null
}

function Get-LastPonSuccess {
    $r = Invoke-Root -Command "cat $EsocLog 2>/dev/null | grep PON_SUCCESS | tail -n 1" -Quiet
    return $r.Text.Trim()
}

function Test-WfcHealthy {
    param(
        [switch]$ShowStatus,
        [string]$Tag = 'status'
    )

    # Do not use the old module's overall SAFE/UNSAFE result here.
    # The success decision below intentionally ignores Result: UNSAFE and the protected-slot0 gate.
    # In airplane mode the protected slot0 gate can be FAIL even while VOXI WFC is healthy.
    $r = Invoke-Root -Command "$WfcCtl status" -Quiet
    $text = $r.Text
    if ($ShowStatus -and $text) { Write-Host $text }

    $ims = $text -match '(?m)^IMS:\s+REGISTERED\s+\(raw 2\)\s*$'
    $transport = $text -match '(?m)^Transport:\s+WLAN\s+\(raw 2\)\s*$'
    $voiceIwlan = $text -match '(?m)^VOICE/IWLAN:\s+AVAILABLE\s*$'
    $wfc = $text -match '(?m)^WFC:\s+AVAILABLE\s*$'
    $healthy = $ims -and $transport -and $voiceIwlan -and $wfc

    Write-Log ("HEALTH {0}: ims={1} transportWlan={2} voiceIwlan={3} wfc={4}" -f $Tag,$ims,$transport,$voiceIwlan,$wfc)
    return $healthy
}

function Wait-WfcHealthy {
    param(
        [int]$MaxSeconds = 30,
        [string]$Tag = 'wait'
    )

    # Physical/software reinsertion on this device can need 10+ seconds.
    # First check at ~5s, then every 3s. For 30s this checks near 5,8,11,...,29s.
    $elapsed = 0
    $check = 0
    $firstWait = if ($MaxSeconds -le 8) { 3 } else { 5 }
    Start-Sleep -Seconds $firstWait
    $elapsed += $firstWait

    while ($true) {
        $check++
        if (Test-WfcHealthy -Tag ("{0}_{1}" -f $Tag,$check)) {
            Write-Host ("[HEALTHY] WFC ready at approximately {0}s." -f $elapsed) -ForegroundColor Green
            Write-Log ("WFC HEALTHY tag={0} elapsed={1}s check={2}" -f $Tag,$elapsed,$check)
            return $true
        }

        Write-Host ("Check {0}: not healthy yet - elapsed {1}s" -f $check,$elapsed)
        if ($elapsed -ge $MaxSeconds) {
            Write-Log ("WFC NOT HEALTHY tag={0} after {1}s" -f $Tag,$elapsed)
            return $false
        }

        $sleep = [Math]::Min(3, $MaxSeconds - $elapsed)
        if ($sleep -le 0) { return $false }
        Start-Sleep -Seconds $sleep
        $elapsed += $sleep
    }
}

function Get-HolderLsof {
    $r = Invoke-Root -Command 'lsof /dev/subsys_esoc0 2>/dev/null' -Quiet
    return $r.Text
}

function Start-HolderWindow {
    Write-Log 'Starting dedicated X55 holder PowerShell window'
    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-Holder'
    )
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Minimized | Out-Null
}

function Stop-OurPreviousHolder {
    $pidRead = Invoke-Root -Command "if [ -f $HolderPidFile ]; then cat $HolderPidFile; fi" -Quiet
    $pidText = $pidRead.Text.Trim()

    if ($pidText -match '^\d+$') {
        $HolderPid = [int]$pidText
        $fd = Invoke-Root -Command "readlink /proc/$HolderPid/fd/9 2>/dev/null" -Quiet
        if ($fd.Text.Trim() -eq '/dev/subsys_esoc0') {
            Write-Host "Killing saved script-owned holder PID=$HolderPid"
            Write-Log "Killing saved script-owned holder PID=$HolderPid"
            [void](Invoke-Root -Command "kill -9 $HolderPid" -Quiet)
            Start-Sleep -Seconds 2
        }
    }

    [void](Invoke-Root -Command "rm -f $HolderPidFile" -Quiet)
}

function Get-Sim2LifecycleSnapshot {
    param([string]$Tag)

    Write-Log ("SIM2 lifecycle snapshot: {0}" -f $Tag)

    # Read-only evidence only. Snapshot collection must NEVER block recovery.
    # Avoid nested shell quoting inside su -c '...'.
    $commands = @(
        "echo ===SIM_STATE===; getprop gsm.sim.state",
        "echo ===ISUB_ID11===; dumpsys isub | grep id=11 | head -n 10",
        "echo ===ISUB_SLOTMAP===; dumpsys isub | grep sSlotIndexToSubId | head -n 10",
        "echo ===PHONE_ID1===; dumpsys phone | grep phoneId=1 | head -n 20",
        "echo ===PHONE_SUB11===; dumpsys phone | grep subId=11 | head -n 20"
    )

    foreach ($cmd in $commands) {
        try {
            $r = Invoke-Root -Command $cmd -Quiet
            if ($r.Text) {
                Add-Content -LiteralPath $script:LogFile -Value $r.Text
            }
            if ($r.Code -ne 0) {
                Write-Log ("SNAPSHOT_WARN tag={0} code={1} cmd={2}" -f $Tag,$r.Code,$cmd)
            }
        } catch {
            Write-Log ("SNAPSHOT_WARN tag={0} error={1}" -f $Tag,$_.Exception.Message)
        }
    }
}

function Invoke-SimPowerCycle {
    param([int]$Attempt)

    $OffHoldSeconds = $SimPowerOffHoldSeconds

    Write-Host ''
    Write-Host ("--- SIM2 software power cycle #{0} ---" -f $Attempt) -ForegroundColor Cyan
    Write-Log ("SIM cycle {0}: POWER OFF -> hold {1}s -> POWER ON using transaction {2}" -f $Attempt,$OffHoldSeconds,$SimPowerTransaction)

    try { Get-Sim2LifecycleSnapshot -Tag ("before_cycle_{0}" -f $Attempt) } catch { Write-Log ("SNAPSHOT_NONFATAL before cycle {0}: {1}" -f $Attempt,$_.Exception.Message) }

    $off = Invoke-Root -Command "service call phone $SimPowerTransaction i32 1 i32 0"
    if ($off.Code -ne 0) {
        throw "SIM2 POWER OFF ADB/service-call error on attempt $Attempt."
    }

    $script:SimMayBeOff = $true
    Write-Host ("SIM2 POWER OFF command accepted. Holding OFF state for {0} seconds..." -f $OffHoldSeconds)
    Write-Log ("SIM cycle {0}: POWER OFF accepted" -f $Attempt)

    # Capture the framework/UICC view after the software removal request.
    Start-Sleep -Seconds 2
    try { Get-Sim2LifecycleSnapshot -Tag ("after_power_off_{0}" -f $Attempt) } catch { Write-Log ("SNAPSHOT_NONFATAL after POWER OFF cycle {0}: {1}" -f $Attempt,$_.Exception.Message) }

    # Preserve the successful manual timing instead of the previous 3-second hold.
    Start-Sleep -Seconds ($OffHoldSeconds - 2)

    $on = Invoke-Root -Command "service call phone $SimPowerTransaction i32 1 i32 1"
    if ($on.Code -ne 0) {
        Write-Host '[WARN] POWER ON returned an ADB error. Sending one safety POWER ON retry.' -ForegroundColor Yellow
        Write-Log "SIM cycle ${Attempt}: first POWER ON returned code $($on.Code); retrying once"
        Start-Sleep -Seconds 1
        $on = Invoke-Root -Command "service call phone $SimPowerTransaction i32 1 i32 1"
        if ($on.Code -ne 0) {
            throw "SIM2 POWER ON failed twice on attempt $Attempt."
        }
    }

    $script:SimMayBeOff = $false
    Write-Host 'SIM2 POWER ON command accepted. Waiting for telephony/IMS/WFC rebuild...'
    Write-Log "SIM cycle ${Attempt}: POWER ON sent"

    # Small read-only snapshot after reinsertion. WFC health polling starts separately.
    Start-Sleep -Seconds 2
    try { Get-Sim2LifecycleSnapshot -Tag ("after_power_on_{0}" -f $Attempt) } catch { Write-Log ("SNAPSHOT_NONFATAL after POWER ON cycle {0}: {1}" -f $Attempt,$_.Exception.Message) }
}

function Ensure-ModemNotLeftOffline {
    if (-not $script:PerMgrStopped) { return }

    try {
        $state = Get-X55State
        if ($state -ne 'OFFLINE') { return }

        $holders = Get-HolderLsof
        if ($holders -match '/dev/subsys_esoc0') { return }

        Write-Host ''
        Write-Host '[RECOVERY GUARD] X55 is OFFLINE with no holder. Starting one holder to avoid leaving the modem down.' -ForegroundColor Yellow
        Write-Log 'Recovery guard: X55 OFFLINE with no holder; starting emergency holder once'
        Start-HolderWindow
        Start-Sleep -Seconds 3
    } catch {
        Write-Log ('Recovery guard error: ' + $_.Exception.Message)
    }
}

# Holder mode: keep the verified subsystem cdev vote open in a dedicated window.
if ($Holder) {
    $Host.UI.RawUI.WindowTitle = 'X55 HOLDER - DO NOT CLOSE'
    Write-Host ''
    Write-Host '============================================================'
    Write-Host '                 X55 HOLDER ACTIVE'
    Write-Host '============================================================'
    Write-Host 'DO NOT CLOSE THIS WINDOW while WFC recovery is in use.'
    Write-Host ''

    if (-not (Test-Path -LiteralPath $Adb)) {
        Write-Host "adb.exe not found: $Adb"
        Read-Host 'Press Enter to close'
        exit 91
    }

    # Single quotes are doubled for PowerShell; $$ stays literal and is evaluated by Android sh.
    $holderCmd = "su -c 'echo `$`$ >$HolderPidFile; exec 9</dev/subsys_esoc0 || exit 91; echo ===X55_HOLDER_OPEN===; while true; do sleep 60; done'"
    & $Adb -s $Serial shell $holderCmd
    $rc = $LASTEXITCODE

    Write-Host ''
    Write-Host "X55 HOLDER exited with code $rc. X55 may lose its subsystem vote." -ForegroundColor Yellow
    Read-Host 'Press Enter to close'
    exit $rc
}

# Main mode logging.
$LogDir = Join-Path $PSScriptRoot 'X55-Logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$script:LogFile = Join-Path $LogDir ('X55-WFC-{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$script:PerMgrStopped = $false
$script:SimMayBeOff = $false
$finalResult = 'NOT_COMPLETED'

Write-Log '============================================================'
Write-Log ('X55 + VOXI WFC one-click recovery started ' + $ScriptVersion)
Write-Log "Serial=$Serial"
Write-Log '============================================================'

try {
    $Host.UI.RawUI.WindowTitle = 'X55 + VOXI WFC One-Click Recovery'

    Write-Host ''
    Write-Host '============================================================'
    Write-Host '         X55 + VOXI WFC ONE-CLICK RECOVERY'
    Write-Host '============================================================'
    Write-Host ''
    Write-Host 'Preconditions:'
    Write-Host '  1. Reproduce polluted state: airplane mode OFF -> ON.'
    Write-Host '  2. Airplane mode must now remain ON.'
    Write-Host '  3. Keep Wi-Fi, proxy and location unchanged.'
    Write-Host '  4. USB debugging and Magisk root must be available.'
    Write-Host ''
    Write-Host 'This build is locked to the validated cas / Android 13 ROM.'
    Write-Host ''
    Write-Host 'Starting automatically...'
    Start-Sleep -Seconds 1

    # STEP 1
    Write-Host ''
    Write-Host '[1/10] Checking ADB and root...'
    if (-not (Test-Path -LiteralPath $Adb)) { Fail "adb.exe not found: $Adb" }

    $state = Invoke-AdbResult -Arguments @('-s',$Serial,'get-state') -Quiet
    if ($state.Code -ne 0 -or $state.Text.Trim() -ne 'device') { Fail "Device $Serial is not connected." }

    $root = Invoke-Root -Command 'id' -Quiet
    if ($root.Code -ne 0 -or $root.Text -notmatch 'uid=0\(root\)') { Fail 'Root access unavailable.' }
    Write-Host '[OK] ADB connected and root confirmed.' -ForegroundColor Green
    Write-Log 'STEP1 PASS: ADB connected; root confirmed'

    # STEP 2
    Write-Host ''
    Write-Host '[2/10] Checking exact device, ROM and modem safety gate...'
    $device = Get-Prop 'ro.product.device'
    $android = Get-Prop 'ro.build.version.release'
    $build = Get-Prop 'ro.build.version.incremental'
    $fingerprint = Get-Prop 'ro.build.fingerprint'

    Write-Host "DEVICE=$device"
    Write-Host "ANDROID=$android"
    Write-Host "BUILD=$build"
    Write-Host "FINGERPRINT=$fingerprint"
    Write-Log "DEVICE=$device ANDROID=$android BUILD=$build"
    Write-Log "FINGERPRINT=$fingerprint"

    if ($device -ne $ExpectedDevice) { Fail "Unsupported device. Expected $ExpectedDevice, got $device." }
    if ($android -ne $ExpectedAndroid) { Fail "Unsupported Android version. Expected $ExpectedAndroid, got $android." }
    if ($build -ne $ExpectedBuild) { Fail "Unvalidated ROM build. Expected $ExpectedBuild, got $build. Binder transaction $SimPowerTransaction is blocked." }
    if ($fingerprint -ne $ExpectedFingerprint) { Fail "Unvalidated ROM fingerprint. Binder transaction $SimPowerTransaction is blocked." }

    $subsysName = (Invoke-Root -Command "cat $SubsysPath/name" -Quiet).Text.Trim()
    $esocName = (Invoke-Root -Command 'cat /sys/bus/esoc/devices/esoc0/esoc_name' -Quiet).Text.Trim()
    Write-Host "SUBSYS=$subsysName"
    Write-Host "MODEM=$esocName"
    Write-Log "SUBSYS=$subsysName MODEM=$esocName"

    if ($subsysName -ne 'esoc0') { Fail 'subsys10 is not esoc0.' }
    if ($esocName -ne 'SDX55M') { Fail 'Detected modem is not SDX55M.' }
    Write-Host '[OK] Exact validated platform confirmed.' -ForegroundColor Green

    # STEP 3
    Write-Host ''
    Write-Host '[3/10] Checking airplane mode and WFC probe...'
    $airplane = (Invoke-Root -Command 'settings get global airplane_mode_on' -Quiet).Text.Trim()
    Write-Host "AIRPLANE_MODE=$airplane"
    if ($airplane -ne '1') { Fail 'Airplane mode is not ON. Reproduce OFF-to-ON polluted state first.' }

    $probe = Invoke-Root -Command "if [ -f $WfcCtl ]; then echo FOUND; else echo MISSING; fi" -Quiet
    if ($probe.Text.Trim() -ne 'FOUND') { Fail "WFC status probe not found at $WfcCtl. Install VOXI WFC Recovery v2.0 first." }
    Write-Host '[OK] Airplane mode ON; WFC probe found.' -ForegroundColor Green

    if (Test-WfcHealthy -ShowStatus -Tag 'initial') {
        $finalResult = 'ALREADY_HEALTHY'
        Write-Host '[OK] WFC is already healthy. Zero recovery writes executed.' -ForegroundColor Green
        throw [System.OperationCanceledException]::new('ALREADY_HEALTHY')
    }

    # STEP 4
    Write-Host ''
    Write-Host '[4/10] Preparing controlled X55 shutdown...'
    $prePon = Get-LastPonSuccess
    Write-Log ('Previous PON_SUCCESS line: ' + $prePon)

    $stop = Invoke-Root -Command 'setprop ctl.stop vendor.per_mgr' -Quiet
    if ($stop.Code -ne 0) { Fail 'Failed to request vendor.per_mgr stop.' }
    $script:PerMgrStopped = $true
    Start-Sleep -Seconds 2

    $perMgr = (Invoke-Root -Command 'getprop init.svc.vendor.per_mgr' -Quiet).Text.Trim()
    Write-Host "PER_MGR=$perMgr"
    if ($perMgr -ne 'stopped') { Fail 'vendor.per_mgr did not stop.' }

    # STEP 5
    Write-Host ''
    Write-Host '[5/10] Cleaning previous script-owned holder...'
    Stop-OurPreviousHolder

    $unknownHolders = Get-HolderLsof
    if ($unknownHolders -match '/dev/subsys_esoc0') {
        Write-Host $unknownHolders
        Fail 'Unknown holder still owns /dev/subsys_esoc0. Script will not kill unknown processes.'
    }
    Write-Host '[OK] No unknown X55 holder remains.' -ForegroundColor Green

    # STEP 6
    Write-Host ''
    Write-Host '[6/10] Waiting for true X55 OFFLINE...'
    $offline = $false
    for ($i=1; $i -le 20; $i++) {
        $x55 = Get-X55State
        Write-Host "Attempt $i/20 - STATE=$x55"
        if ($x55 -eq 'OFFLINE') { $offline = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $offline) { Fail 'X55 did not enter OFFLINE within 20 seconds.' }

    $crash = Get-CrashCount
    Write-Host "STATE=OFFLINE"
    Write-Host "CRASH_COUNT=$crash"
    if ($null -eq $crash -or $crash -ne 0) { Fail "CRASH_COUNT is $crash, expected 0." }
    Write-Host '[OK] Clean X55 shutdown confirmed.' -ForegroundColor Green
    Write-Log 'X55 OFFLINE; CRASH_COUNT=0'

    # STEP 7
    Write-Host ''
    Write-Host '[7/10] Starting new X55 holder...'
    Start-HolderWindow
    Start-Sleep -Seconds 2

    $online = $false
    for ($i=1; $i -le 30; $i++) {
        $x55 = Get-X55State
        Write-Host "Attempt $i/30 - STATE=$x55"
        if ($x55 -eq 'ONLINE') { $online = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $online) { Fail 'X55 did not return ONLINE within 30 seconds.' }

    $crash = Get-CrashCount
    if ($null -eq $crash -or $crash -ne 0) { Fail "X55 returned ONLINE but CRASH_COUNT=$crash." }

    $holderLsof = Get-HolderLsof
    if ($holderLsof -notmatch '/dev/subsys_esoc0') { Fail 'X55 is ONLINE but the holder is missing.' }
    Write-Host '[OK] X55 ONLINE, CRASH_COUNT=0, holder active.' -ForegroundColor Green
    Write-Host $holderLsof
    Write-Log 'X55 ONLINE; CRASH_COUNT=0; holder active'

    # STEP 8
    Write-Host ''
    Write-Host '[8/10] Verifying this cycle reached a new PON_SUCCESS...'
    $postPon = ''
    $ponVerified = $false
    for ($i=1; $i -le 15; $i++) {
        $postPon = Get-LastPonSuccess
        Write-Host "PON check $i/15"
        if ($postPon -and $postPon -ne $prePon) {
            $ponVerified = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    if (-not $ponVerified) {
        [void](Invoke-Root -Command "cat $EsocLog 2>/dev/null | tail -n 80")
        Fail 'No new PON_SUCCESS was observed for this X55 cycle. SIM power cycle is blocked.'
    }
    Write-Host '[OK] New PON_SUCCESS confirmed.' -ForegroundColor Green
    Write-Log ('New PON_SUCCESS: ' + $postPon)
    [void](Invoke-Root -Command "cat $EsocLog 2>/dev/null | tail -n 50")

    Write-Host ''
    Write-Host 'Allowing X55 / qcrild / UICC stack to settle for 10 seconds...'
    Write-Log ("Post-PON stabilization wait: {0}s" -f $PostPonSettleSeconds)
    Start-Sleep -Seconds $PostPonSettleSeconds

    Write-Host ''
    Write-Host 'Checking whether X55 restart alone already restored WFC...'
    if (Wait-WfcHealthy -MaxSeconds 5 -Tag 'after_x55_only') {
        $finalResult = 'X55_ONLY_SUCCESS'
        throw [System.OperationCanceledException]::new('RECOVERY_SUCCESS')
    }

    # STEP 9
    Write-Host ''
    Write-Host '[9/10] Software SIM2 power cycle attempt 1...'
    Invoke-SimPowerCycle -Attempt 1
    if (Wait-WfcHealthy -MaxSeconds 30 -Tag 'after_sim_cycle_1') {
        $finalResult = 'SIM_CYCLE_1_SUCCESS'
        throw [System.OperationCanceledException]::new('RECOVERY_SUCCESS')
    }

    Write-Host ''
    Write-Host '[INFO] Attempt 1 did not restore WFC within 30 seconds.' -ForegroundColor Yellow
    Write-Log 'SIM cycle 1 completed; WFC not healthy after wait window'

    # STEP 10
    Write-Host ''
    Write-Host '[10/10] Software SIM2 power cycle attempt 2...'
    Invoke-SimPowerCycle -Attempt 2
    if (Wait-WfcHealthy -MaxSeconds 30 -Tag 'after_sim_cycle_2') {
        $finalResult = 'SIM_CYCLE_2_SUCCESS'
        throw [System.OperationCanceledException]::new('RECOVERY_SUCCESS')
    }

    $finalResult = 'AUTO_RECOVERY_FAILED'
    Write-Host ''
    Write-Host '============================================================'
    Write-Host '              AUTOMATIC RECOVERY FAILED' -ForegroundColor Red
    Write-Host '============================================================'
    Write-Host 'X55 restart succeeded.'
    Write-Host 'Two SIM2 POWER OFF -> 8s hold -> POWER ON cycles were executed.'
    Write-Host 'No third automatic SIM power cycle will be attempted.'
    Write-Host 'Keep airplane mode ON and keep the X55 HOLDER alive.'
    Write-Host 'Fallback: physically remove and reinsert the VOXI SIM; if WFC does not return, repeat the physical reinsertion once.'
    Write-Host ''
    [void](Test-WfcHealthy -ShowStatus -Tag 'final_failed')
    Write-Log 'FINAL_RESULT=AUTO_RECOVERY_FAILED'
}
catch [System.OperationCanceledException] {
    if ($finalResult -eq 'ALREADY_HEALTHY') {
        # Intentional clean early exit.
    } elseif ($finalResult -match 'SUCCESS$') {
        # Intentional successful early exit.
    } else {
        Write-Log ('Controlled exit: ' + $_.Exception.Message)
    }
}
catch {
    if ($finalResult -eq 'NOT_COMPLETED') { $finalResult = 'ERROR' }
    Write-Host ''
    Write-Host ('[ERROR] ' + $_.Exception.Message) -ForegroundColor Red
    Write-Log ('ERROR: ' + $_.Exception.ToString())
}
finally {
    # If an exception ever occurs after SIM OFF but before SIM ON, send ON once.
    if ($script:SimMayBeOff) {
        try {
            Write-Host '[RECOVERY GUARD] SIM2 may be powered off. Sending one POWER ON command.' -ForegroundColor Yellow
            Write-Log 'Recovery guard: SIM2 may be off; sending POWER ON once'
            [void](Invoke-Root -Command "service call phone $SimPowerTransaction i32 1 i32 1" -Quiet)
            $script:SimMayBeOff = $false
        } catch {
            Write-Log ('SIM recovery guard error: ' + $_.Exception.Message)
        }
    }

    Ensure-ModemNotLeftOffline
}

if ($finalResult -eq 'ALREADY_HEALTHY' -or $finalResult -match 'SUCCESS$') {
    Write-Host ''
    Write-Host '============================================================'
    Write-Host '               VOXI WFC RECOVERY SUCCESS' -ForegroundColor Green
    Write-Host '============================================================'
    Write-Host "RESULT=$finalResult"
    Write-Host 'IMS         : REGISTERED'
    Write-Host 'Transport   : WLAN'
    Write-Host 'VOICE/IWLAN : AVAILABLE'
    Write-Host 'WFC         : AVAILABLE'
    Write-Host ''
    if ($finalResult -ne 'ALREADY_HEALTHY') {
        Write-Host 'Keep the X55 HOLDER window running.'
    }
    Write-Host 'No physical SIM reinsertion is required.'
    Write-Host ''
    [void](Test-WfcHealthy -ShowStatus -Tag 'final_success')
    Write-Log "FINAL_RESULT=$finalResult"
}

Write-Host ''
Write-Host '============================================================'
Write-Host "Finished. Log: $script:LogFile"
Write-Host '============================================================'
Write-Host ''
Read-Host 'Press Enter to close this window'

if ($finalResult -eq 'ALREADY_HEALTHY' -or $finalResult -match 'SUCCESS$') { exit 0 }
if ($finalResult -eq 'AUTO_RECOVERY_FAILED') { exit 20 }
exit 1
