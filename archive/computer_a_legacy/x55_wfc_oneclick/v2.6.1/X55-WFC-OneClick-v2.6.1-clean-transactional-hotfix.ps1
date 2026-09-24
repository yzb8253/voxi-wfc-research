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
$SimPowerOffHoldSeconds = 3
$ScriptVersion = 'v2.6.1-clean-transactional-hotfix'

function ConvertTo-WindowsCommandLineArg {
    param([AllowEmptyString()][string]$Value)

    if ($null -eq $Value -or $Value.Length -eq 0) {
        return '""'
    }

    # No quoting needed if there is no whitespace or quote character.
    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    # Quote using the Windows CommandLineToArgvW / CRT backslash rules.
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $slashCount = 0

    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq '\') {
            $slashCount++
            continue
        }

        if ($ch -eq '"') {
            if ($slashCount -gt 0) {
                [void]$sb.Append(('\' * ($slashCount * 2)))
                $slashCount = 0
            }
            [void]$sb.Append('\"')
            continue
        }

        if ($slashCount -gt 0) {
            [void]$sb.Append(('\' * $slashCount))
            $slashCount = 0
        }

        [void]$sb.Append($ch)
    }

    if ($slashCount -gt 0) {
        # Backslashes before the closing quote must be doubled.
        [void]$sb.Append(('\' * ($slashCount * 2)))
    }

    [void]$sb.Append('"')
    return $sb.ToString()
}


function Append-LogSafe {
    param([AllowEmptyString()][string]$Text)

    if (-not $script:LogFile) { return }

    try {
        $enc = New-Object System.Text.UTF8Encoding($false)
        $bytes = $enc.GetBytes($Text + [Environment]::NewLine)
        $fs = New-Object System.IO.FileStream(
            $script:LogFile,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite
        )
        try {
            [void]$fs.Seek(0, [System.IO.SeekOrigin]::End)
            $fs.Write($bytes, 0, $bytes.Length)
            $fs.Flush()
        }
        finally {
            $fs.Dispose()
        }
    }
    catch {
        # Logging must never abort WFC recovery.
        try {
            $fallback = Join-Path $env:TEMP 'X55-WFC-fallback.log'
            [System.IO.File]::AppendAllText(
                $fallback,
                ('[{0}] LOG_WRITE_WARN: {1}{2}' -f (Get-Date -Format 'HH:mm:ss.fff'), $_.Exception.Message, [Environment]::NewLine)
            )
        } catch {}
    }
}

function Invoke-AdbResult {
    param(
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [switch]$Quiet,
        [switch]$NoLog
    )

    $display = 'adb ' + ($Arguments -join ' ')
    if (-not $NoLog -and $script:LogFile) {
        Append-LogSafe ('[{0}] CMD: {1}' -f (Get-Date -Format 'HH:mm:ss.fff'), $display)
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Adb
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $quoted = @()
    foreach ($arg in $Arguments) {
        $quoted += (ConvertTo-WindowsCommandLineArg -Value $arg)
    }
    $psi.Arguments = ($quoted -join ' ')

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    try {
        if (-not $proc.Start()) {
            throw "Failed to start adb.exe"
        }

        # Start both reads before waiting to avoid stdout/stderr pipe deadlocks.
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        $proc.WaitForExit()

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $code = $proc.ExitCode

        $parts = @()
        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            $parts += $stdout.TrimEnd("`r","`n")
        }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            $parts += $stderr.TrimEnd("`r","`n")
        }
        $outText = ($parts -join [Environment]::NewLine)

        if (-not $NoLog -and $script:LogFile -and $outText) {
            Append-LogSafe $outText
        }
        if (-not $Quiet -and $outText) {
            Write-Host $outText
        }

        return [pscustomobject]@{
            Code = $code
            Text = $outText.Trim()
        }
    }
    catch {
        if (-not $NoLog -and $script:LogFile) {
            Append-LogSafe ('[{0}] ADB_EXEC_ERROR: {1}' -f (Get-Date -Format 'HH:mm:ss.fff'), $_.Exception.ToString())
        }
        throw
    }
    finally {
        if ($null -ne $proc) {
            $proc.Dispose()
        }
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
    Append-LogSafe $line
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
                Append-LogSafe $r.Text
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

    Write-Host ''
    Write-Host ("--- SIM2 software power cycle #{0} ---" -f $Attempt) -ForegroundColor Cyan
    Write-Log ("SIM cycle {0}: POWER OFF -> hold {1}s -> POWER ON once; transaction {2}" -f $Attempt,$SimPowerOffHoldSeconds,$SimPowerTransaction)

    try { Get-Sim2LifecycleSnapshot -Tag ("before_cycle_{0}" -f $Attempt) } catch { Write-Log ("SNAPSHOT_NONFATAL before cycle {0}: {1}" -f $Attempt,$_.Exception.Message) }

    # 1) Software removal.
    $off = Invoke-Root -Command "service call phone $SimPowerTransaction i32 1 i32 0"
    if ($off.Code -ne 0) {
        throw "SIM2 POWER OFF ADB/service-call error on attempt $Attempt."
    }

    $script:SimMayBeOff = $true
    Write-Host ("SIM2 POWER OFF accepted. Holding OFF for {0} seconds..." -f $SimPowerOffHoldSeconds)
    Write-Log ("SIM cycle {0}: POWER OFF accepted" -f $Attempt)

    Start-Sleep -Seconds 1
    try { Get-Sim2LifecycleSnapshot -Tag ("after_power_off_{0}" -f $Attempt) } catch { Write-Log ("SNAPSHOT_NONFATAL after POWER OFF cycle {0}: {1}" -f $Attempt,$_.Exception.Message) }

    $remainingOff = [Math]::Max(0, $SimPowerOffHoldSeconds - 1)
    if ($remainingOff -gt 0) { Start-Sleep -Seconds $remainingOff }

    # 2) Single POWER ON.
    $on1 = Invoke-Root -Command "service call phone $SimPowerTransaction i32 1 i32 1"
    if ($on1.Code -ne 0) {
        throw "SIM2 POWER ON failed on attempt $Attempt."
    }

    $script:SimMayBeOff = $false
    Write-Host 'SIM2 POWER ON accepted. No second POWER ON trigger will be sent.'
    Write-Log ("SIM cycle {0}: single POWER ON sent; duplicate POWER ON disabled" -f $Attempt)

    Start-Sleep -Seconds 2
    try { Get-Sim2LifecycleSnapshot -Tag ("after_power_on_{0}" -f $Attempt) } catch { Write-Log ("SNAPSHOT_NONFATAL after POWER ON cycle {0}: {1}" -f $Attempt,$_.Exception.Message) }

    Write-Host 'Waiting for telephony / qti.cne / IMS / ePDG / WFC rebuild...'
}

function Get-CneRegistrationState {
    $r = Invoke-Root -Command "$WfcCtl status" -Quiet
    if ($r.Text -match 'qti\.cne:\s+registered=YES') { return 'YES' }
    if ($r.Text -match 'qti\.cne:\s+registered=NO')  { return 'NO' }
    return 'UNKNOWN'
}

function Get-CneSnapshot {
    $r = Invoke-Root -Command "$WfcCtl status" -Quiet

    $registered = 'UNKNOWN'
    $active = 'UNKNOWN'
    $request = 'null'
    $satisfied = 'null'

    if ($r.Text -match 'qti\.cne:\s+registered=([A-Z]+)\s+active=([A-Z]+)\s+request=([^\s]+)\s+satisfied=([^\s]+)') {
        $registered = $Matches[1]
        $active = $Matches[2]
        $request = $Matches[3]
        $satisfied = $Matches[4]
    }

    return [pscustomobject]@{
        Registered = $registered
        Active = $active
        Request = $request
        Satisfied = $satisfied
        Raw = $r.Text
    }
}

function Get-PerMgrState {
    $r = Invoke-Root -Command 'getprop init.svc.vendor.per_mgr' -Quiet
    return $r.Text.Trim()
}

function Get-SavedHolderPid {
    $r = Invoke-Root -Command "if [ -f $HolderPidFile ]; then cat $HolderPidFile; fi" -Quiet
    $pidText = $r.Text.Trim()

    if ($pidText -match '^\d+$') {
        return [int]$pidText
    }

    return $null
}

function Test-HolderPidOwnsFd {
    param([int]$HolderPid)

    if ($HolderPid -le 0) { return $false }

    $fd = Invoke-Root -Command "readlink /proc/$HolderPid/fd/9 2>/dev/null" -Quiet
    return ($fd.Text.Trim() -eq '/dev/subsys_esoc0')
}

function Start-HolderWindow {
    Write-Log 'Starting dedicated temporary X55 holder PowerShell window'
    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-Holder'
    )
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Minimized | Out-Null
}

function Wait-HolderStarted {
    param([int]$MaxSeconds = 10)

    for ($i=1; $i -le $MaxSeconds; $i++) {
        $holderPid = Get-SavedHolderPid

        if ($null -ne $holderPid -and (Test-HolderPidOwnsFd -HolderPid $holderPid)) {
            $script:HolderPidCreated = $holderPid
            Write-Log ("Temporary holder confirmed PID={0}" -f $holderPid)
            return $true
        }

        Start-Sleep -Seconds 1
    }

    return $false
}

function Stop-ExactHolder {
    param(
        [Parameter(Mandatory=$true)][int]$HolderPid,
        [string]$Reason = 'cleanup'
    )

    if (-not (Test-HolderPidOwnsFd -HolderPid $HolderPid)) {
        Write-Log ("Holder PID={0} is no longer holding fd9; nothing to kill ({1})" -f $HolderPid,$Reason)

        $saved = Get-SavedHolderPid
        if ($saved -eq $HolderPid) {
            [void](Invoke-Root -Command "rm -f $HolderPidFile" -Quiet)
        }

        return $true
    }

    Write-Host ("Stopping temporary X55 holder PID={0}..." -f $HolderPid)
    Write-Log ("Stopping temporary holder PID={0} reason={1}" -f $HolderPid,$Reason)

    [void](Invoke-Root -Command "kill $HolderPid 2>/dev/null" -Quiet)
    Start-Sleep -Seconds 2

    if (Test-HolderPidOwnsFd -HolderPid $HolderPid) {
        Write-Log ("Holder PID={0} ignored TERM; sending targeted KILL" -f $HolderPid)
        [void](Invoke-Root -Command "kill -9 $HolderPid 2>/dev/null" -Quiet)
        Start-Sleep -Seconds 1
    }

    if (Test-HolderPidOwnsFd -HolderPid $HolderPid) {
        Write-Log ("CLEANUP_FAIL: holder PID={0} still owns /dev/subsys_esoc0" -f $HolderPid)
        return $false
    }

    $saved = Get-SavedHolderPid
    if ($saved -eq $HolderPid) {
        [void](Invoke-Root -Command "rm -f $HolderPidFile" -Quiet)
    }

    return $true
}

function Wait-PerMgrRunning {
    param([int]$MaxSeconds = 15)

    for ($i=1; $i -le $MaxSeconds; $i++) {
        if ((Get-PerMgrState) -eq 'running') { return $true }
        Start-Sleep -Seconds 1
    }

    return $false
}

function Wait-X55Online {
    param([int]$MaxSeconds = 15)

    for ($i=1; $i -le $MaxSeconds; $i++) {
        if ((Get-X55State) -eq 'ONLINE') { return $true }
        Start-Sleep -Seconds 1
    }

    return $false
}

function Assert-CleanEntryEnvironment {
    $script:PrePerMgrState = Get-PerMgrState
    $savedHolder = Get-SavedHolderPid
    $script:PreHolderPid = if ($null -eq $savedHolder) { '' } else { [string]$savedHolder }

    $holderText = if ($script:PreHolderPid) { $script:PreHolderPid } else { 'NONE' }

    Write-Host ("PRE_PER_MGR={0}" -f $script:PrePerMgrState)
    Write-Host ("PRE_SAVED_HOLDER={0}" -f $holderText)
    Write-Log ("ENTRY_BASELINE per_mgr={0} savedHolder={1}" -f $script:PrePerMgrState,$holderText)

    if ($null -ne $savedHolder) {
        if (Test-HolderPidOwnsFd -HolderPid $savedHolder) {
            Fail ("Old script-owned X55 holder PID={0} is still active. Reboot once before the first v2.6 test; v2.6 will clean up its own holder after every run." -f $savedHolder)
        }

        # Dead/stale PID file only: safe to remove.
        [void](Invoke-Root -Command "rm -f $HolderPidFile" -Quiet)
        Write-Log ("Removed stale dead holder pid file PID={0}" -f $savedHolder)
    }

    if ($script:PrePerMgrState -ne 'running') {
        Fail ("vendor.per_mgr entry state is '{0}', not normal boot state 'running'. Reboot once before the first v2.6 test." -f $script:PrePerMgrState)
    }

    $x55 = Get-X55State
    if ($x55 -ne 'ONLINE') {
        Fail ("X55 entry state is '{0}', expected ONLINE for a clean boot-normal baseline." -f $x55)
    }

    Write-Host '[OK] Clean boot-normal power-management baseline confirmed.' -ForegroundColor Green
    Write-Log 'ENTRY_BASELINE PASS: vendor.per_mgr=running, no active script holder, X55=ONLINE'
}

function Invoke-TransactionalCleanup {
    Write-Host ''
    Write-Host '============================================================'
    Write-Host '         TRANSACTIONAL CLEANUP / BASELINE RESTORE'
    Write-Host '============================================================'
    Write-Log 'CLEANUP_START'

    if (-not $script:EnvironmentTouched) {
        $script:CleanupOk = $true
        $script:CleanupDetail = 'NOT_NEEDED'
        Write-Host '[CLEANUP] No X55 power-management changes were made.'
        Write-Log 'CLEANUP_RESULT=NOT_NEEDED'
        return
    }

    # Keep the temporary holder alive while vendor.per_mgr is restarted.
    $perMgr = Get-PerMgrState

    if ($perMgr -ne 'running') {
        Write-Host '[CLEANUP] Starting vendor.per_mgr while temporary holder is still active...'
        Write-Log ("CLEANUP: starting vendor.per_mgr from state={0}" -f $perMgr)

        $start = Invoke-Root -Command 'setprop ctl.start vendor.per_mgr' -Quiet
        if ($start.Code -ne 0) {
            $script:CleanupOk = $false
            $script:CleanupDetail = 'PER_MGR_START_COMMAND_FAILED'
            Write-Host '[CLEANUP FAIL] vendor.per_mgr start command failed. Holder is intentionally kept for safety.' -ForegroundColor Red
            Write-Log 'CLEANUP_RESULT=FAIL reason=PER_MGR_START_COMMAND_FAILED'
            return
        }
    }

    if (-not (Wait-PerMgrRunning -MaxSeconds 15)) {
        $script:CleanupOk = $false
        $script:CleanupDetail = 'PER_MGR_NOT_RUNNING'
        Write-Host '[CLEANUP FAIL] vendor.per_mgr did not become running. Holder is intentionally kept for safety.' -ForegroundColor Red
        Write-Log 'CLEANUP_RESULT=FAIL reason=PER_MGR_NOT_RUNNING'
        return
    }

    $script:PerMgrStopped = $false
    Write-Host '[CLEANUP] vendor.per_mgr=running. Waiting 3 seconds before releasing temporary holder...'
    Write-Log 'CLEANUP: vendor.per_mgr running; takeover settle 3s'
    Start-Sleep -Seconds 3

    if (-not (Wait-X55Online -MaxSeconds 10)) {
        $script:CleanupOk = $false
        $script:CleanupDetail = 'X55_NOT_ONLINE_BEFORE_HOLDER_RELEASE'
        Write-Host '[CLEANUP FAIL] X55 is not ONLINE before holder release. Holder is intentionally kept for safety.' -ForegroundColor Red
        Write-Log 'CLEANUP_RESULT=FAIL reason=X55_NOT_ONLINE_BEFORE_HOLDER_RELEASE'
        return
    }

    if ($script:HolderPidCreated) {
        if (-not (Stop-ExactHolder -HolderPid ([int]$script:HolderPidCreated) -Reason 'transactional_cleanup')) {
            $script:CleanupOk = $false
            $script:CleanupDetail = 'HOLDER_STOP_FAILED'
            Write-Host '[CLEANUP FAIL] Temporary holder could not be stopped.' -ForegroundColor Red
            Write-Log 'CLEANUP_RESULT=FAIL reason=HOLDER_STOP_FAILED'
            return
        }
    }
    else {
        [void](Invoke-Root -Command "rm -f $HolderPidFile" -Quiet)
    }

    Write-Host '[CLEANUP] Temporary holder released. Verifying normal power-management state...'
    Start-Sleep -Seconds 4

    $perMgrAfter = Get-PerMgrState
    $x55After = Get-X55State

    # Cleanup-only repair. This is not a WFC recovery step.
    if ($perMgrAfter -ne 'running' -or $x55After -ne 'ONLINE') {
        Write-Log ("CLEANUP_REPAIR: per_mgr={0} x55={1}; restarting vendor.per_mgr once" -f $perMgrAfter,$x55After)
        [void](Invoke-Root -Command 'setprop ctl.restart vendor.per_mgr' -Quiet)
        Start-Sleep -Seconds 3
        [void](Wait-PerMgrRunning -MaxSeconds 10)
        [void](Wait-X55Online -MaxSeconds 10)
        $perMgrAfter = Get-PerMgrState
        $x55After = Get-X55State
    }

    $savedAfter = Get-SavedHolderPid
    $savedAfterText = if ($null -eq $savedAfter) { 'NONE' } else { [string]$savedAfter }

    Write-Host ("[CLEANUP] PER_MGR={0} X55={1} SCRIPT_HOLDER={2}" -f $perMgrAfter,$x55After,$savedAfterText)
    Write-Log ("CLEANUP_VERIFY per_mgr={0} x55={1} savedHolder={2}" -f $perMgrAfter,$x55After,$savedAfterText)

    if ($perMgrAfter -eq 'running' -and $x55After -eq 'ONLINE' -and $null -eq $savedAfter) {
        $script:CleanupOk = $true
        $script:CleanupDetail = 'CLEAN'
        Write-Host '[CLEANUP OK] Normal vendor.per_mgr control restored; no script holder remains.' -ForegroundColor Green
        Write-Log 'CLEANUP_RESULT=CLEAN'
        return
    }

    # Safety fallback: never intentionally leave X55 OFFLINE.
    if ($x55After -ne 'ONLINE') {
        Write-Host '[CLEANUP SAFETY] X55 not ONLINE. Re-opening an emergency holder; reboot is required before another test.' -ForegroundColor Yellow
        Write-Log 'CLEANUP_SAFETY: X55 not ONLINE; starting emergency holder'

        try {
            Start-HolderWindow
            Start-Sleep -Seconds 3
        }
        catch {
            Write-Log ('CLEANUP_SAFETY holder start error: ' + $_.Exception.Message)
        }
    }

    $script:CleanupOk = $false
    $script:CleanupDetail = ("VERIFY_FAILED_perMgr={0}_x55={1}_holder={2}" -f $perMgrAfter,$x55After,$savedAfterText)
    Write-Host '[CLEANUP FAIL] Could not return to the clean boot-normal baseline. Reboot before another experiment.' -ForegroundColor Red
    Write-Log ("CLEANUP_RESULT=FAIL detail={0}" -f $script:CleanupDetail)
}

# Holder mode: temporary verified subsystem cdev vote.
# v2.6 auto-closes this PowerShell window when cleanup releases the Android holder.
if ($Holder) {
    $Host.UI.RawUI.WindowTitle = 'X55 TEMP HOLDER - AUTO CLEANUP'
    Write-Host ''
    Write-Host '============================================================'
    Write-Host '              X55 TEMPORARY HOLDER ACTIVE'
    Write-Host '============================================================'
    Write-Host 'This window is temporary and will close automatically during cleanup.'
    Write-Host ''

    if (-not (Test-Path -LiteralPath $Adb)) {
        Write-Host "adb.exe not found: $Adb"
        exit 91
    }

    # $$ is evaluated by Android sh and written to the fixed holder PID file.
    $holderCmd = "su -c 'echo `$`$ >$HolderPidFile; exec 9</dev/subsys_esoc0 || exit 91; echo ===X55_HOLDER_OPEN===; while true; do sleep 60; done'"
    & $Adb -s $Serial shell $holderCmd
    $rc = $LASTEXITCODE

    Write-Host ''
    Write-Host "X55 temporary holder exited with code $rc."
    exit $rc
}

# Main mode logging.
$LogDir = Join-Path $PSScriptRoot 'X55-Logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$script:LogFile = Join-Path $LogDir ('X55-WFC-{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$script:PerMgrStopped = $false
$script:SimMayBeOff = $false
$script:EnvironmentTouched = $false
$script:HolderPidCreated = ''
$script:PrePerMgrState = ''
$script:PreHolderPid = ''
$script:CleanupOk = $true
$script:CleanupDetail = 'NOT_NEEDED'
$script:PostCleanupWfc = 'NOT_APPLICABLE'
$finalResult = 'NOT_COMPLETED'

Write-Log '============================================================'
Write-Log ('X55 + VOXI WFC one-click recovery started ' + $ScriptVersion)
Write-Log "Serial=$Serial"
Write-Log '============================================================'

try {
    $Host.UI.RawUI.WindowTitle = 'X55 + VOXI WFC v2.6 Clean Transactional Recovery'

    Write-Host ''
    Write-Host '============================================================'
    Write-Host '      X55 + VOXI WFC v2.6 CLEAN TRANSACTIONAL'
    Write-Host '============================================================'
    Write-Host ''
    Write-Host 'Preconditions:'
    Write-Host '  1. Reproduce polluted state: airplane mode OFF -> ON.'
    Write-Host '  2. Airplane mode must now remain ON.'
    Write-Host '  3. Keep Wi-Fi, proxy and location unchanged.'
    Write-Host '  4. USB debugging and Magisk root must be available.'
    Write-Host '  5. First v2.6 test should start after a full reboot, with vendor.per_mgr in normal running state.'
    Write-Host ''
    Write-Host 'This build is locked to the validated cas / Android 13 ROM.'
    Write-Host ''
    Write-Host 'Starting automatically...'
    Start-Sleep -Seconds 1

    # STEP 1
    Write-Host ''
    Write-Host '[1/9] Checking ADB and root...'
    if (-not (Test-Path -LiteralPath $Adb)) { Fail "adb.exe not found: $Adb" }

    $state = Invoke-AdbResult -Arguments @('-s',$Serial,'get-state') -Quiet
    if ($state.Code -ne 0 -or $state.Text.Trim() -ne 'device') { Fail "Device $Serial is not connected." }

    $root = Invoke-Root -Command 'id' -Quiet
    if ($root.Code -ne 0 -or $root.Text -notmatch 'uid=0\(root\)') { Fail 'Root access unavailable.' }
    Write-Host '[OK] ADB connected and root confirmed.' -ForegroundColor Green
    Write-Log 'STEP1 PASS: ADB connected; root confirmed'

    # STEP 2
    Write-Host ''
    Write-Host '[2/9] Checking exact device, ROM and modem safety gate...'
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
    Write-Host '[3/9] Checking airplane mode and WFC probe...'
    $airplane = (Invoke-Root -Command 'settings get global airplane_mode_on' -Quiet).Text.Trim()
    Write-Host "AIRPLANE_MODE=$airplane"
    if ($airplane -ne '1') { Fail 'Airplane mode is not ON. Reproduce OFF-to-ON polluted state first.' }

    $probe = Invoke-Root -Command "if [ -f $WfcCtl ]; then echo FOUND; else echo MISSING; fi" -Quiet
    if ($probe.Text.Trim() -ne 'FOUND') { Fail "WFC status probe not found at $WfcCtl. Install VOXI WFC Recovery v2.0 first." }
    Write-Host '[OK] Airplane mode ON; WFC probe found.' -ForegroundColor Green

    Write-Host ''
    Write-Host 'Checking clean boot-normal X55 power-management baseline...'
    Assert-CleanEntryEnvironment

    if (Test-WfcHealthy -ShowStatus -Tag 'initial') {
        $finalResult = 'ALREADY_HEALTHY'
        Write-Host '[OK] WFC is already healthy. Zero recovery writes executed.' -ForegroundColor Green
        throw [System.OperationCanceledException]::new('ALREADY_HEALTHY')
    }

    # STEP 4
    Write-Host ''
    Write-Host '[4/9] Preparing controlled X55 shutdown...'
    $prePon = Get-LastPonSuccess
    Write-Log ('Previous PON_SUCCESS line: ' + $prePon)

    $stop = Invoke-Root -Command 'setprop ctl.stop vendor.per_mgr' -Quiet
    if ($stop.Code -ne 0) { Fail 'Failed to request vendor.per_mgr stop.' }
    $script:PerMgrStopped = $true
    $script:EnvironmentTouched = $true
    Start-Sleep -Seconds 2

    $perMgr = (Invoke-Root -Command 'getprop init.svc.vendor.per_mgr' -Quiet).Text.Trim()
    Write-Host "PER_MGR=$perMgr"
    if ($perMgr -ne 'stopped') { Fail 'vendor.per_mgr did not stop.' }

    # STEP 5
    Write-Host ''
    Write-Host '[5/9] Verifying no stale holder remains after per_mgr stop...'

    $savedAfterStop = Get-SavedHolderPid
    if ($null -ne $savedAfterStop -and (Test-HolderPidOwnsFd -HolderPid $savedAfterStop)) {
        Fail ("Unexpected script holder PID={0} appeared before this run created one." -f $savedAfterStop)
    }

    if ($null -ne $savedAfterStop) {
        [void](Invoke-Root -Command "rm -f $HolderPidFile" -Quiet)
    }

    $unknownHolders = Get-HolderLsof
    if ($unknownHolders -match '/dev/subsys_esoc0') {
        Write-Host $unknownHolders
        Fail 'Unknown holder still owns /dev/subsys_esoc0. Script will not kill unknown processes.'
    }

    Write-Host '[OK] No holder remains; X55 may now shut down cleanly.' -ForegroundColor Green

    # STEP 6
    Write-Host ''
    Write-Host '[6/9] Waiting for true X55 OFFLINE...'
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
    Write-Host '[7/9] Starting temporary X55 holder...'
    Start-HolderWindow

    if (-not (Wait-HolderStarted -MaxSeconds 10)) {
        Fail 'Temporary X55 holder did not become active within 10 seconds.'
    }

    Write-Host ("TEMP_HOLDER_PID={0}" -f $script:HolderPidCreated)
    Write-Log ("TEMP_HOLDER_PID={0}" -f $script:HolderPidCreated)

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
    Write-Host '[OK] X55 ONLINE, CRASH_COUNT=0, temporary holder active.' -ForegroundColor Green
    Write-Host $holderLsof
    Write-Log 'X55 ONLINE; CRASH_COUNT=0; temporary holder active'

    # STEP 8
    Write-Host ''
    Write-Host '[8/9] Verifying this cycle reached a new PON_SUCCESS...'
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
    Write-Host '[9/9] Software SIM2 power cycle - single attempt...'

    $cneBefore = Get-CneSnapshot
    Write-Host ("CNE before SIM cycle: registered={0} active={1} request={2} satisfied={3}" -f $cneBefore.Registered,$cneBefore.Active,$cneBefore.Request,$cneBefore.Satisfied)
    Write-Log ("CNE_BASELINE registered={0} active={1} request={2} satisfied={3}" -f $cneBefore.Registered,$cneBefore.Active,$cneBefore.Request,$cneBefore.Satisfied)

    Invoke-SimPowerCycle -Attempt 1

    if (Wait-WfcHealthy -MaxSeconds 30 -Tag 'after_sim_cycle_1') {
        $finalResult = 'SIM_CYCLE_1_SUCCESS'
        throw [System.OperationCanceledException]::new('RECOVERY_SUCCESS')
    }

    Write-Host ''
    Write-Host '[INFO] SIM cycle 1 did not restore WFC within 30 seconds.' -ForegroundColor Yellow
    Write-Log 'SIM cycle 1 completed; WFC not healthy after wait window'

    $cneAfterSim = Get-CneSnapshot
    Write-Host ("CNE after SIM cycle: registered={0} active={1} request={2} satisfied={3}" -f $cneAfterSim.Registered,$cneAfterSim.Active,$cneAfterSim.Request,$cneAfterSim.Satisfied)
    Write-Log ("CNE_AFTER_SIM registered={0} active={1} request={2} satisfied={3}" -f $cneAfterSim.Registered,$cneAfterSim.Active,$cneAfterSim.Request,$cneAfterSim.Satisfied)

    $cneFreshness = 'UNKNOWN'
    if (($cneBefore.Request -ne 'null') -and ($cneAfterSim.Request -eq $cneBefore.Request)) {
        $cneFreshness = 'STALE_CNE_REQUEST'
    }
    elseif (($cneAfterSim.Request -ne 'null') -and ($cneAfterSim.Request -ne $cneBefore.Request)) {
        $cneFreshness = 'NEW_CNE_REQUEST'
    }
    elseif ($cneAfterSim.Request -eq 'null') {
        $cneFreshness = 'NO_CNE_REQUEST'
    }

    Write-Host ("CNE request freshness: {0}" -f $cneFreshness)
    Write-Log ("CNE_REQUEST_FRESHNESS={0} baseline={1} afterSim={2}" -f $cneFreshness,$cneBefore.Request,$cneAfterSim.Request)

    # v2.6 intentionally stops recovery here.
    # No second SIM cycle, no vendor.cnd restart, no qtidataservices restart,
    # and no physical-reinsert automation.
    $finalResult = 'AUTO_RECOVERY_FAILED'

    Write-Host ''
    Write-Host '============================================================'
    Write-Host '              AUTOMATIC RECOVERY FAILED' -ForegroundColor Red
    Write-Host '============================================================'
    Write-Host 'X55 restart succeeded.'
    Write-Host 'Exactly one SIM2 software power cycle was executed.'
    Write-Host ("CNE freshness after SIM cycle: {0}" -f $cneFreshness)
    Write-Host 'No second SIM power cycle was attempted.'
    Write-Host 'vendor.cnd was NOT restarted.'
    Write-Host '.qtidataservices was NOT restarted.'
    Write-Host 'Transactional cleanup will now restore vendor.per_mgr and remove the temporary holder.'
    Write-Host ''

    [void](Test-WfcHealthy -ShowStatus -Tag 'final_failed_before_cleanup')
    Write-Log ("FINAL_RECOVERY_RESULT=AUTO_RECOVERY_FAILED sim_freshness={0}" -f $cneFreshness)

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
    if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) {
        Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor DarkYellow
    }
    Write-Log ('ERROR: ' + $_.Exception.ToString())
    if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) {
        Write-Log ('ERROR_POSITION: ' + $_.InvocationInfo.PositionMessage)
    }
}
finally {
    # Emergency guard only. If an exception occurs after POWER OFF but before
    # the normal single POWER ON, send one emergency POWER ON so the SIM is not left off.
    # On the normal path this guard does not run.
    if ($script:SimMayBeOff) {
        try {
            Write-Host '[RECOVERY GUARD] SIM2 may be powered off. Sending one emergency POWER ON.' -ForegroundColor Yellow
            Write-Log 'Recovery guard: SIM2 may be off; sending one emergency POWER ON'
            [void](Invoke-Root -Command "service call phone $SimPowerTransaction i32 1 i32 1" -Quiet)
            $script:SimMayBeOff = $false
        }
        catch {
            Write-Log ('SIM recovery guard error: ' + $_.Exception.Message)
        }
    }

    try {
        Invoke-TransactionalCleanup
    }
    catch {
        $script:CleanupOk = $false
        $script:CleanupDetail = 'CLEANUP_EXCEPTION'
        Write-Host ('[CLEANUP ERROR] ' + $_.Exception.Message) -ForegroundColor Red
        Write-Log ('CLEANUP_EXCEPTION: ' + $_.Exception.ToString())
    }
}


$recoverySucceeded = ($finalResult -eq 'ALREADY_HEALTHY' -or $finalResult -match 'SUCCESS$')

if ($recoverySucceeded) {
    if ($finalResult -eq 'ALREADY_HEALTHY') {
        $script:PostCleanupWfc = 'HEALTHY'
    }
    elseif ($script:CleanupOk) {
        Write-Host ''
        Write-Host 'Waiting 5 seconds to verify WFC survives transactional cleanup...'
        Start-Sleep -Seconds 5

        if (Test-WfcHealthy -ShowStatus -Tag 'post_cleanup') {
            $script:PostCleanupWfc = 'HEALTHY'
        }
        else {
            $script:PostCleanupWfc = 'LOST_AFTER_CLEANUP'
        }
    }
    else {
        $script:PostCleanupWfc = 'UNKNOWN_CLEANUP_FAILED'
    }

    Write-Host ''
    Write-Host '============================================================'
    Write-Host '               VOXI WFC RECOVERY RESULT'
    Write-Host '============================================================'
    Write-Host ("RECOVERY_RESULT={0}" -f $finalResult)
    Write-Host ("CLEANUP_RESULT={0}" -f $(if ($script:CleanupOk) { $script:CleanupDetail } else { 'FAILED_' + $script:CleanupDetail }))
    Write-Host ("POST_CLEANUP_WFC={0}" -f $script:PostCleanupWfc)

    if ($script:CleanupOk -and $script:PostCleanupWfc -eq 'HEALTHY') {
        Write-Host 'IMS         : REGISTERED'
        Write-Host 'Transport   : WLAN'
        Write-Host 'VOICE/IWLAN : AVAILABLE'
        Write-Host 'WFC         : AVAILABLE'
        Write-Host 'vendor.per_mgr: restored'
        Write-Host 'Temporary holder: removed'
        Write-Host ''
        Write-Host '[OK] Recovery succeeded and the script left no holder/per_mgr residue.' -ForegroundColor Green
    }
    elseif (-not $script:CleanupOk) {
        Write-Host ''
        Write-Host '[WARN] Recovery succeeded before cleanup, but cleanup did not return to a verified clean baseline.' -ForegroundColor Yellow
        Write-Host 'Reboot before another experiment.'
    }
    else {
        Write-Host ''
        Write-Host '[WARN] WFC was healthy before cleanup but was lost after normal power-management control was restored.' -ForegroundColor Yellow
        Write-Host 'This is important evidence: the temporary X55 holder/per_mgr state is part of the successful condition.'
    }

    Write-Log ("FINAL_RESULT recovery={0} cleanup={1} postCleanupWfc={2}" -f $finalResult,$script:CleanupDetail,$script:PostCleanupWfc)
}
else {
    Write-Host ''
    Write-Host '============================================================'
    Write-Host '               VOXI WFC RECOVERY RESULT'
    Write-Host '============================================================'
    Write-Host ("RECOVERY_RESULT={0}" -f $finalResult)
    Write-Host ("CLEANUP_RESULT={0}" -f $(if ($script:CleanupOk) { $script:CleanupDetail } else { 'FAILED_' + $script:CleanupDetail }))
    Write-Host 'POST_CLEANUP_WFC=NOT_APPLICABLE'

    if ($script:CleanupOk) {
        Write-Host '[OK] Recovery failed, but the script restored the normal boot-style power-management baseline.' -ForegroundColor Green
        Write-Host 'No temporary holder should remain.'
    }
    else {
        Write-Host '[WARN] Cleanup was not verified. Reboot before another experiment.' -ForegroundColor Yellow
    }

    Write-Log ("FINAL_RESULT recovery={0} cleanup={1}" -f $finalResult,$script:CleanupDetail)
}

Write-Host ''
Write-Host '============================================================'
Write-Host ("Finished. Log: {0}" -f $script:LogFile)
Write-Host '============================================================'
Write-Host ''
Read-Host 'Press Enter to close this window'

if (-not $script:CleanupOk) { exit 30 }
if ($recoverySucceeded -and $script:PostCleanupWfc -eq 'HEALTHY') { exit 0 }
if ($recoverySucceeded -and $script:PostCleanupWfc -eq 'LOST_AFTER_CLEANUP') { exit 21 }
if ($finalResult -eq 'AUTO_RECOVERY_FAILED') { exit 20 }
exit 1
