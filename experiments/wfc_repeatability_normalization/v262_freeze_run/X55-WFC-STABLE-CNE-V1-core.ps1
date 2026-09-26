param(
    [switch]$Holder,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Adb = Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$Serial = 'fd0ff892'
$WfcCtl = '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh'
$HolderPidFile = '/data/local/tmp/x55_holder.pid'
$SubsysPath = '/sys/bus/msm_subsys/devices/subsys10'
$EsocLog = '/sys/kernel/debug/ipc_logging/esoc-mdm/log'
$CurrentCneProjection = Join-Path $Repo 'experiments\wfc_repeatability_normalization\lightweight_profiling\current_cne_projection_v12h_r2.ps1'
$StableCneContract = Join-Path $PSScriptRoot 'STABLE-CNE-V1-contract.ps1'
$UiccPrime = Join-Path $PSScriptRoot 'STABLE-CNE-V1-uicc-prime.ps1'
. $CurrentCneProjection
. $StableCneContract

# IMPORTANT: Binder transaction 182 is validated only on this exact ROM/build.
$ExpectedDevice = 'cas'
$ExpectedAndroid = '13'
$ExpectedBuild = 'V816.0.4.0.TJJCNXM'
$ExpectedFingerprint = 'Xiaomi/cas/cas:13/TKQ1.221114.001/V816.0.4.0.TJJCNXM:user/release-keys'
$SimPowerTransaction = 182
$PostPonSettleSeconds = 10
$SimPowerOffHoldSeconds = 3
$ScriptVersion = 'STABLE_CNE_V1'

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

function Write-Timing {
    param([string]$Name,[Diagnostics.Stopwatch]$Stopwatch)
    $Stopwatch.Stop()
    $line = "TIMING name={0} ms={1}" -f $Name,$Stopwatch.ElapsedMilliseconds
    Write-Host $line
    Write-Log $line
}

function Write-CoreTotalTiming {
    if($null -ne $script:CoreTotal -and $script:CoreTotal.IsRunning) {
        Write-Timing -Name 'core_total' -Stopwatch $script:CoreTotal
    }
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
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $r = Invoke-Root -Command "$WfcCtl status" -Quiet
    $text = $r.Text
    if ($ShowStatus -and $text) { Write-Host $text }

    $ims = $text -match '(?m)^IMS:\s+REGISTERED\s+\(raw 2\)\s*$'
    $transport = $text -match '(?m)^Transport:\s+WLAN\s+\(raw 2\)\s*$'
    $voiceIwlan = $text -match '(?m)^VOICE/IWLAN:\s+AVAILABLE\s*$'
    $wfc = $text -match '(?m)^WFC:\s+AVAILABLE\s*$'
    $healthy = $ims -and $transport -and $voiceIwlan -and $wfc

    Write-Log ("HEALTH {0}: ims={1} transportWlan={2} voiceIwlan={3} wfc={4}" -f $Tag,$ims,$transport,$voiceIwlan,$wfc)
    Write-Timing -Name ("core_wfc_health_{0}" -f $Tag) -Stopwatch $timer
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
    $offTimer = [Diagnostics.Stopwatch]::StartNew()
    $off = Invoke-Root -Command "service call phone $SimPowerTransaction i32 1 i32 0"
    if($off.Code -eq 0){Record-PhoneWrite 'SIM2_POWER_OFF'}
    if ($off.Code -ne 0) {
        throw "SIM2 POWER OFF ADB/service-call error on attempt $Attempt."
    }

    $script:SimMayBeOff = $true
    Write-Timing -Name 'core_sim2_power_off_request' -Stopwatch $offTimer
    Write-Host ("SIM2 POWER OFF accepted. Holding OFF for {0} seconds..." -f $SimPowerOffHoldSeconds)
    Write-Log ("SIM cycle {0}: POWER OFF accepted" -f $Attempt)

    $holdTimer = [Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Seconds 1
    try { Get-Sim2LifecycleSnapshot -Tag ("after_power_off_{0}" -f $Attempt) } catch { Write-Log ("SNAPSHOT_NONFATAL after POWER OFF cycle {0}: {1}" -f $Attempt,$_.Exception.Message) }

    $remainingOff = [Math]::Max(0, $SimPowerOffHoldSeconds - 1)
    if ($remainingOff -gt 0) { Start-Sleep -Seconds $remainingOff }
    Write-Timing -Name 'core_sim2_off_hold' -Stopwatch $holdTimer

    # 2) Single POWER ON.
    $onTimer = [Diagnostics.Stopwatch]::StartNew()
    $script:SimPowerOnToHealthTimer = [Diagnostics.Stopwatch]::StartNew()
    $on1 = Invoke-Root -Command "service call phone $SimPowerTransaction i32 1 i32 1"
    if($on1.Code -eq 0){Record-PhoneWrite 'SIM2_POWER_ON'}
    if ($on1.Code -ne 0) {
        throw "SIM2 POWER ON failed on attempt $Attempt."
    }

    $script:SimMayBeOff = $false
    Write-Timing -Name 'core_sim2_power_on_request' -Stopwatch $onTimer
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

function Record-PhoneWrite([string]$Action) {
    $script:PhoneWriteCount++
    $script:PhoneWriteActions.Add($Action) | Out-Null
    Write-Log ("PHONE_WRITE={0}" -f $Action)
}

function Get-AuthoritativeCurrentCne {
    $connectivity = Invoke-Root -Command 'dumpsys connectivity' -Quiet
    if($connectivity.Code -ne 0 -or [string]::IsNullOrWhiteSpace($connectivity.Text)) {
        throw 'CURRENT CNE connectivity dump unavailable.'
    }
    $projection = Get-CurrentCneProjection -ConnectivityText $connectivity.Text -SubId 11
    if(-not $projection.valid) { throw ("CURRENT CNE projection invalid: {0}" -f $projection.reason) }

    $registered='UNKNOWN'; $active='UNKNOWN'
    $probe = Invoke-Root -Command "$WfcCtl status" -Quiet
    if($probe.Text -match 'qti\.cne:\s+registered=([A-Z]+)\s+active=([A-Z]+)') {
        $registered=$Matches[1]; $active=$Matches[2]
    }
    $request = if($null -eq $projection.requestId){'null'}else{[string]$projection.requestId}
    $satisfied = if($null -eq $projection.satisfiedId){'null'}else{[string]$projection.satisfiedId}
    [pscustomobject]@{Registered=$registered;Active=$active;Request=$request;Satisfied=$satisfied;Source='CONNECTIVITY_CURRENT_TABLE_ONLY'}
}

function Invoke-StableCnePrime {
    Write-Host '[5/7] Priming CNE: UICC false -> F8 -> true' -ForegroundColor Cyan
    Write-Log 'STABLE_CNE_PRIME=START implementation=golden_uicc_false_F8_true'
    $lines = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $UiccPrime -Serial $Serial 2>&1 | ForEach-Object {[string]$_})
    $rc = $LASTEXITCODE
    foreach($line in $lines) {
        Write-Host $line
        Write-Log ("UICC_PRIME: {0}" -f $line)
        if($line -match '^UICC_F8_CONFIRMED_AFTER='){$script:F8Confirmed=$true}
        if($line -match '^UICC_TRUE_HOST_EPOCH_MS=(\d+)$'){$script:UiccTrueEpochMs=[long]$Matches[1]}
        if($line -match '^UICC_PHONE_WRITE=(.+)$'){Record-PhoneWrite $Matches[1]}
    }
    if($rc -ne 0 -or -not $script:F8Confirmed -or $script:UiccTrueEpochMs -le 0) {
        $script:CnePrimeResult='FAIL'
        Write-Log ("STABLE_CNE_PRIME=FAIL exit={0} f8={1} trueEpoch={2}" -f $rc,$script:F8Confirmed,$script:UiccTrueEpochMs)
        return $false
    }
    $script:CnePrimeResult='PASS'
    Write-Log 'STABLE_CNE_PRIME=PASS'
    return $true
}

function Wait-FreshCne([string]$BaselineRequest,[int]$MaxSeconds=45) {
    Write-Host ("[6/7] Waiting for fresh CNE request... 0s / {0}s" -f $MaxSeconds) -ForegroundColor Cyan
    $deadline=[DateTimeOffset]::Now.ToUnixTimeMilliseconds()+($MaxSeconds*1000)
    do {
        $snapshot=Get-AuthoritativeCurrentCne
        $now=[DateTimeOffset]::Now.ToUnixTimeMilliseconds()
        $elapsed=[Math]::Max(0,$now-$script:UiccTrueEpochMs)
        $sec=[Math]::Floor($elapsed/1000)
        Write-Host ("CNE_WAIT elapsed={0}s registered={1} active={2} request={3} satisfied={4}" -f $sec,$snapshot.Registered,$snapshot.Active,$snapshot.Request,$snapshot.Satisfied)
        Write-Log ("CNE_WAIT elapsedMs={0} registered={1} active={2} request={3} satisfied={4}" -f $elapsed,$snapshot.Registered,$snapshot.Active,$snapshot.Request,$snapshot.Satisfied)
        $fresh = Test-StableCneFresh -BaselineRequest $BaselineRequest -CurrentRequest $snapshot.Request
        if($fresh) {
            $script:FreshCneRequest=$snapshot.Request
            $script:CneTriggerLatencyMs=$elapsed
            Write-Host ("[OK] Fresh CNE request {0} detected" -f $snapshot.Request) -ForegroundColor Green
            Write-Host 'CNE=READY' -ForegroundColor Green
            Write-Log ("FRESH_CNE_REQUEST={0} CNE_TRIGGER_LATENCY_MS={1}" -f $snapshot.Request,$elapsed)
            return $true
        }
        if($now -ge $deadline){break}
        Start-Sleep -Seconds 1
    }while($true)
    Write-Log ("FRESH_CNE_TIMEOUT baseline={0} maxSeconds={1}" -f $BaselineRequest,$MaxSeconds)
    return $false
}

function Wait-StableCneWfc([int]$MaxSeconds=30) {
    Write-Host '[7/7] Waiting for IMS / WFC' -ForegroundColor Cyan
    Write-Host 'WAITING_FOR_IMS'
    $timer=[Diagnostics.Stopwatch]::StartNew(); $imsShown=$false
    do {
        $r=Invoke-Root -Command "$WfcCtl status" -Quiet
        if([string]::IsNullOrWhiteSpace($r.Text)){throw 'WFC status probe returned no output.'}
        $ims=$r.Text -match '(?m)^IMS:\s+REGISTERED\s+\(raw 2\)\s*$'
        $transport=$r.Text -match '(?m)^Transport:\s+WLAN\s+\(raw 2\)\s*$'
        $voice=$r.Text -match '(?m)^VOICE/IWLAN:\s+AVAILABLE\s*$'
        $wfc=$r.Text -match '(?m)^WFC:\s+AVAILABLE\s*$'
        if($ims -and -not $imsShown){$imsShown=$true;$script:ImsRegistered=$true;Write-Host 'IMS=REGISTERED' -ForegroundColor Green;Write-Host 'WAITING_FOR_WFC'}
        Write-Log ("IMS_WFC_WAIT elapsedMs={0} ims={1} transportWlan={2} voiceIwlan={3} wfc={4}" -f $timer.ElapsedMilliseconds,$ims,$transport,$voice,$wfc)
        if($ims -and $transport -and $voice -and $wfc){$script:WfcHealthy=$true;Write-Host 'WFC=AVAILABLE' -ForegroundColor Green;return $true}
        if($timer.Elapsed.TotalSeconds -ge $MaxSeconds){return $false}
        Start-Sleep -Seconds 1
    }while($true)
}
function Get-PerMgrState {
    $r = Invoke-Root -Command 'getprop init.svc.vendor.per_mgr' -Quiet
    return $r.Text.Trim()
}

function Get-PerMgrPid {
    $r = Invoke-Root -Command 'getprop init.svc_debug_pid.vendor.per_mgr' -Quiet
    $pidText = $r.Text.Trim()

    if ($pidText -match '^\d+$') {
        return [int]$pidText
    }

    return $null
}

function Get-PerMgrExe {
    $perMgrPid = Get-PerMgrPid
    if ($null -eq $perMgrPid) { return '' }

    $r = Invoke-Root -Command ("readlink /proc/{0}/exe 2>/dev/null" -f $perMgrPid) -Quiet
    return $r.Text.Trim()
}

function Get-PerMgrEsocOwnerLine {
    $perMgrPid = Get-PerMgrPid
    if ($null -eq $perMgrPid) { return '' }

    $r = Invoke-Root -Command ("ls -l /proc/{0}/fd 2>/dev/null | grep '/dev/subsys_esoc0' | head -n 1" -f $perMgrPid) -Quiet
    return $r.Text.Trim()
}

function Test-PerMgrOwnsEsoc {
    $perMgrPid = Get-PerMgrPid
    if ($null -eq $perMgrPid) { return $false }

    $exe = Get-PerMgrExe
    if ($exe -ne '/vendor/bin/pm-service') { return $false }

    $ownerLine = Get-PerMgrEsocOwnerLine
    return (-not [string]::IsNullOrWhiteSpace($ownerLine))
}

function Wait-PerMgrOwnsEsoc {
    param([int]$MaxSeconds = 20)

    for ($i=1; $i -le $MaxSeconds; $i++) {
        $state = Get-PerMgrState
        $perMgrPid = Get-PerMgrPid
        $exe = Get-PerMgrExe
        $owns = Test-PerMgrOwnsEsoc
        $x55 = Get-X55State

        Write-Host ("Native takeover {0}/{1}: state={2} pid={3} exe={4} owns_esoc={5} X55={6}" -f
            $i,$MaxSeconds,$state,$perMgrPid,$exe,$owns,$x55)

        if ($state -eq 'running' -and
            $null -ne $perMgrPid -and
            $exe -eq '/vendor/bin/pm-service' -and
            $owns -and
            $x55 -eq 'ONLINE') {
            return $true
        }

        Start-Sleep -Seconds 1
    }

    return $false
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
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Hidden | Out-Null
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
    $perMgrPid = Get-PerMgrPid
    $perMgrExe = Get-PerMgrExe
    $perMgrOwns = Test-PerMgrOwnsEsoc
    $ownerLine = Get-PerMgrEsocOwnerLine
    $x55 = Get-X55State

    Write-Host ("PRE_PER_MGR={0}" -f $script:PrePerMgrState)
    Write-Host ("PRE_PER_MGR_PID={0}" -f $(if ($null -eq $perMgrPid) { 'NONE' } else { $perMgrPid }))
    Write-Host ("PRE_PER_MGR_EXE={0}" -f $(if ($perMgrExe) { $perMgrExe } else { 'NONE' }))
    Write-Host ("PRE_PER_MGR_OWNS_ESOC={0}" -f $perMgrOwns)
    Write-Host ("PRE_X55={0}" -f $x55)
    Write-Host ("PRE_SAVED_HOLDER={0}" -f $holderText)

    if ($ownerLine) {
        Write-Host ("PRE_NATIVE_OWNER={0}" -f $ownerLine)
    }

    Write-Log ("ENTRY_BASELINE per_mgr={0} pid={1} exe={2} ownsEsoc={3} x55={4} savedHolder={5}" -f
        $script:PrePerMgrState,$perMgrPid,$perMgrExe,$perMgrOwns,$x55,$holderText)

    if ($null -ne $savedHolder) {
        if (Test-HolderPidOwnsFd -HolderPid $savedHolder) {
            Fail ("Old script-owned X55 holder PID={0} is still active. Reboot once before another v2.6.2 test." -f $savedHolder)
        }

        # Dead/stale PID file only: safe to remove.
        [void](Invoke-Root -Command "rm -f $HolderPidFile" -Quiet)
        Write-Log ("Removed stale dead holder pid file PID={0}" -f $savedHolder)
    }

    if ($script:PrePerMgrState -ne 'running') {
        Fail ("vendor.per_mgr entry state is '{0}', expected running." -f $script:PrePerMgrState)
    }

    if ($null -eq $perMgrPid) {
        Fail 'vendor.per_mgr has no init.svc_debug_pid; native pm-service owner is missing.'
    }

    if ($perMgrExe -ne '/vendor/bin/pm-service') {
        Fail ("vendor.per_mgr PID {0} exe is '{1}', expected /vendor/bin/pm-service." -f $perMgrPid,$perMgrExe)
    }

    if (-not $perMgrOwns) {
        Fail ("vendor.per_mgr PID {0} is running but does NOT own /dev/subsys_esoc0. This is not the clean post-boot baseline." -f $perMgrPid)
    }

    if ($x55 -ne 'ONLINE') {
        Fail ("X55 entry state is '{0}', expected ONLINE." -f $x55)
    }

    Write-Host '[OK] Exact clean native baseline confirmed: pm-service owns esoc0, X55 ONLINE, no script holder.' -ForegroundColor Green
    Write-Log 'ENTRY_BASELINE PASS: native pm-service owner present, X55=ONLINE, no active script holder'
}

function Invoke-TransactionalCleanup {
    Write-Host ''
    Write-Host '============================================================'
    Write-Host '   TRANSACTIONAL CLEANUP / NATIVE pm-service RESTORE'
    Write-Host '============================================================'
    Write-Log 'CLEANUP_START'

    if (-not $script:EnvironmentTouched) {
        $script:CleanupOk = $true
        $script:CleanupDetail = 'NOT_NEEDED'
        Write-Host '[CLEANUP] No X55 power-management changes were made.'
        Write-Log 'CLEANUP_RESULT=NOT_NEEDED'
        return
    }

    # IMPORTANT:
    # Keep the temporary holder alive until vendor.per_mgr's real process
    # (/vendor/bin/pm-service) itself owns /dev/subsys_esoc0 AND X55 is ONLINE.
    $perMgr = Get-PerMgrState

    if ($perMgr -ne 'running') {
        Write-Host '[CLEANUP] Starting vendor.per_mgr while temporary holder remains active...'
        Write-Log ("CLEANUP: ctl.start vendor.per_mgr from state={0}" -f $perMgr)

        $start = Invoke-Root -Command 'setprop ctl.start vendor.per_mgr' -Quiet
        if ($start.Code -ne 0) {
            $script:CleanupOk = $false
            $script:CleanupDetail = 'PER_MGR_START_COMMAND_FAILED'
            Write-Host '[CLEANUP FAIL] vendor.per_mgr start command failed. Temporary holder is intentionally kept.' -ForegroundColor Red
            Write-Log 'CLEANUP_RESULT=FAIL reason=PER_MGR_START_COMMAND_FAILED'
            return
        }
    }

    # Do not trust init.svc=running alone. Wait for the real native owner.
    $nativeReady = Wait-PerMgrOwnsEsoc -MaxSeconds 20

    if (-not $nativeReady) {
        Write-Host '[CLEANUP] Native pm-service did not take esoc0 yet. Restarting vendor.per_mgr once while holder is still active...' -ForegroundColor Yellow
        Write-Log 'CLEANUP: native owner missing; one ctl.restart vendor.per_mgr while temporary holder remains active'

        [void](Invoke-Root -Command 'setprop ctl.restart vendor.per_mgr' -Quiet)
        Start-Sleep -Seconds 2
        $nativeReady = Wait-PerMgrOwnsEsoc -MaxSeconds 20
    }

    if (-not $nativeReady) {
        $script:CleanupOk = $false
        $script:CleanupDetail = 'NATIVE_PM_SERVICE_DID_NOT_OWN_ESOC'
        Write-Host '[CLEANUP FAIL] vendor.per_mgr is not confirmed as the native esoc0 owner. Temporary holder is intentionally kept for X55 safety.' -ForegroundColor Red
        Write-Log 'CLEANUP_RESULT=FAIL reason=NATIVE_PM_SERVICE_DID_NOT_OWN_ESOC'
        return
    }

    $script:PerMgrStopped = $false
    $nativePid = Get-PerMgrPid
    $nativeOwner = Get-PerMgrEsocOwnerLine

    Write-Host ("[CLEANUP] Native takeover confirmed: PID={0}" -f $nativePid) -ForegroundColor Green
    if ($nativeOwner) {
        Write-Host ("[CLEANUP] Native owner line: {0}" -f $nativeOwner)
    }
    Write-Log ("CLEANUP_NATIVE_READY pid={0} owner={1}" -f $nativePid,$nativeOwner)

    # Native pm-service is now holding esoc0. Only now may we release our temporary holder.
    if ($script:HolderPidCreated) {
        if (-not (Stop-ExactHolder -HolderPid ([int]$script:HolderPidCreated) -Reason 'native_pm_service_takeover_confirmed')) {
            $script:CleanupOk = $false
            $script:CleanupDetail = 'TEMP_HOLDER_STOP_FAILED'
            Write-Host '[CLEANUP FAIL] Temporary holder could not be stopped.' -ForegroundColor Red
            Write-Log 'CLEANUP_RESULT=FAIL reason=TEMP_HOLDER_STOP_FAILED'
            return
        }
    }
    else {
        [void](Invoke-Root -Command "rm -f $HolderPidFile" -Quiet)
    }

    Write-Host '[CLEANUP] Temporary holder released. Verifying exact post-boot native fingerprint...'
    Start-Sleep -Seconds 3

    $perMgrAfter = Get-PerMgrState
    $nativePidAfter = Get-PerMgrPid
    $nativeExeAfter = Get-PerMgrExe
    $nativeOwnsAfter = Test-PerMgrOwnsEsoc
    $nativeOwnerAfter = Get-PerMgrEsocOwnerLine
    $x55After = Get-X55State
    $savedAfter = Get-SavedHolderPid
    $savedAfterText = if ($null -eq $savedAfter) { 'NONE' } else { [string]$savedAfter }

    Write-Host ("[CLEANUP VERIFY] PER_MGR={0}" -f $perMgrAfter)
    Write-Host ("[CLEANUP VERIFY] PID={0}" -f $(if ($null -eq $nativePidAfter) { 'NONE' } else { $nativePidAfter }))
    Write-Host ("[CLEANUP VERIFY] EXE={0}" -f $(if ($nativeExeAfter) { $nativeExeAfter } else { 'NONE' }))
    Write-Host ("[CLEANUP VERIFY] NATIVE_OWNS_ESOC={0}" -f $nativeOwnsAfter)
    Write-Host ("[CLEANUP VERIFY] X55={0}" -f $x55After)
    Write-Host ("[CLEANUP VERIFY] SCRIPT_HOLDER={0}" -f $savedAfterText)

    if ($nativeOwnerAfter) {
        Write-Host ("[CLEANUP VERIFY] OWNER={0}" -f $nativeOwnerAfter)
    }

    Write-Log ("CLEANUP_VERIFY per_mgr={0} pid={1} exe={2} ownsEsoc={3} x55={4} savedHolder={5} owner={6}" -f
        $perMgrAfter,$nativePidAfter,$nativeExeAfter,$nativeOwnsAfter,$x55After,$savedAfterText,$nativeOwnerAfter)

    if ($perMgrAfter -eq 'running' -and
        $null -ne $nativePidAfter -and
        $nativeExeAfter -eq '/vendor/bin/pm-service' -and
        $nativeOwnsAfter -and
        $x55After -eq 'ONLINE' -and
        $null -eq $savedAfter) {

        $script:CleanupOk = $true
        $script:CleanupDetail = 'CLEAN_NATIVE_BASELINE'
        Write-Host '[CLEANUP OK] Exact native baseline restored: pm-service owns esoc0, X55 ONLINE, no script holder.' -ForegroundColor Green
        Write-Log 'CLEANUP_RESULT=CLEAN_NATIVE_BASELINE'
        return
    }

    # Safety fallback. If releasing our holder caused X55/native ownership to disappear,
    # re-open an emergency holder rather than intentionally leaving the modem down.
    if ($x55After -ne 'ONLINE' -or -not $nativeOwnsAfter) {
        Write-Host '[CLEANUP SAFETY] Native baseline did not survive temporary-holder release. Re-opening emergency holder; reboot before another experiment.' -ForegroundColor Yellow
        Write-Log 'CLEANUP_SAFETY: native baseline failed after holder release; starting emergency holder'

        try {
            Start-HolderWindow
            Start-Sleep -Seconds 3
        }
        catch {
            Write-Log ('CLEANUP_SAFETY holder start error: ' + $_.Exception.Message)
        }
    }

    $script:CleanupOk = $false
    $script:CleanupDetail = ("VERIFY_FAILED_perMgr={0}_pid={1}_owns={2}_x55={3}_holder={4}" -f
        $perMgrAfter,$nativePidAfter,$nativeOwnsAfter,$x55After,$savedAfterText)

    Write-Host '[CLEANUP FAIL] Exact native baseline was not restored. Reboot before another experiment.' -ForegroundColor Red
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
$script:FreezeOnHealthy = $false
$script:CnePrimeResult='NOT_RUN'
$script:F8Confirmed=$false
$script:CneBaselineRequest='null'
$script:FreshCneRequest='null'
$script:CneTriggerLatencyMs=-1
$script:UiccTrueEpochMs=0
$script:ImsRegistered=$false
$script:WfcHealthy=$false
$script:PhoneWriteCount=0
$script:PhoneWriteActions=New-Object 'Collections.Generic.List[string]'
$script:PreShutdownCrashCount = $null
$script:OfflineCrashCount = $null
$script:SimPowerOnToHealthTimer = $null
$finalResult = 'NOT_COMPLETED'
$script:CoreTotal = [Diagnostics.Stopwatch]::StartNew()

Write-Log '============================================================'
Write-Log ('X55 + VOXI WFC one-click recovery started ' + $ScriptVersion)
Write-Log "Serial=$Serial"
Write-Log '============================================================'

try {
    $preconditionsTimer = [Diagnostics.Stopwatch]::StartNew()
    $Host.UI.RawUI.WindowTitle = 'X55 + VOXI WFC v2.6 Clean Transactional Recovery'

    Write-Host ''
    Write-Host '============================================================'
    Write-Host '      X55 + VOXI WFC v2.6.2 NATIVE OWNER RESTORE'
    Write-Host '============================================================'
    Write-Host ''
    Write-Host 'Preconditions:'
    Write-Host '  1. Reproduce polluted state: airplane mode OFF -> ON.'
    Write-Host '  2. Airplane mode must now remain ON.'
    Write-Host '  3. Keep Wi-Fi, proxy and location unchanged.'
    Write-Host '  4. USB debugging and Magisk root must be available.'
    Write-Host '  5. First v2.6.2 test should start after a full reboot; clean baseline requires native pm-service ownership of /dev/subsys_esoc0.'
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

    $initialHealthy = Test-WfcHealthy -ShowStatus -Tag 'initial'
    Write-Timing -Name 'core_preconditions' -Stopwatch $preconditionsTimer
    if ($initialHealthy) {
        $finalResult = 'ALREADY_HEALTHY'
        Write-Host '[OK] WFC is already healthy. Zero recovery writes executed.' -ForegroundColor Green
        throw [System.OperationCanceledException]::new('ALREADY_HEALTHY')
    }

    # STEP 4
    Write-Host ''
    Write-Host '[4/9] Preparing controlled X55 shutdown...'
    $prePon = Get-LastPonSuccess
    Write-Log ('Previous PON_SUCCESS line: ' + $prePon)
    $script:PreShutdownCrashCount = Get-CrashCount
    if ($null -eq $script:PreShutdownCrashCount) { Fail 'Unable to read X55 crash_count before controlled shutdown.' }
    Write-Host ("PRE_SHUTDOWN_CRASH_COUNT={0}" -f $script:PreShutdownCrashCount)
    Write-Log ("PRE_SHUTDOWN_CRASH_COUNT={0}" -f $script:PreShutdownCrashCount)

    $offlineTimer = [Diagnostics.Stopwatch]::StartNew()
    $stop = Invoke-Root -Command 'setprop ctl.stop vendor.per_mgr' -Quiet
    if($stop.Code -eq 0){Record-PhoneWrite 'CTL_STOP_VENDOR_PER_MGR'}
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
    if ($null -eq $crash) { Fail 'Unable to read crash_count after controlled shutdown.' }
    if ($crash -lt $script:PreShutdownCrashCount) {
        Fail ("CRASH_COUNT moved backwards from {0} to {1}." -f $script:PreShutdownCrashCount,$crash)
    }
    $script:OfflineCrashCount = $crash
    $delta = $script:OfflineCrashCount - $script:PreShutdownCrashCount
    Write-Host ("CRASH_COUNT_DELTA_DURING_CONTROLLED_SHUTDOWN={0}" -f $delta)
    Write-Host '[OK] Clean X55 shutdown confirmed; cumulative crash_count recorded.' -ForegroundColor Green
    Write-Log ("X55 OFFLINE; CRASH_COUNT before={0} after={1} delta={2}" -f $script:PreShutdownCrashCount,$script:OfflineCrashCount,$delta)
    Write-Timing -Name 'core_x55_offline' -Stopwatch $offlineTimer

    # STEP 7
    Write-Host ''
    Write-Host '[2/7] Restarting X55 / starting temporary holder...'
    $holderOnlineTimer = [Diagnostics.Stopwatch]::StartNew()
    Start-HolderWindow
    Record-PhoneWrite 'START_TEMP_X55_HOLDER'

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
    if ($null -eq $crash) { Fail 'Unable to read crash_count after X55 returned ONLINE.' }
    if ($null -eq $script:OfflineCrashCount -or $crash -ne $script:OfflineCrashCount) {
        Fail ("X55 returned ONLINE but crash_count changed again: offline={0} online={1}." -f $script:OfflineCrashCount,$crash)
    }
    Write-Host ("CRASH_COUNT_STABLE_AFTER_POWERUP={0}" -f $crash)

    $holderLsof = Get-HolderLsof
    if ($holderLsof -notmatch '/dev/subsys_esoc0') { Fail 'X55 is ONLINE but the holder is missing.' }
    Write-Host ("[OK] X55 ONLINE, crash_count stable at {0}, temporary holder active." -f $crash) -ForegroundColor Green
    Write-Host $holderLsof
    Write-Log ("X55 ONLINE; CRASH_COUNT={0} stable_from_offline=PASS; temporary holder active" -f $crash)
    Write-Timing -Name 'core_holder_start_to_x55_online' -Stopwatch $holderOnlineTimer

    # STEP 8
    Write-Host ''
    Write-Host '[8/9] Verifying this cycle reached a new PON_SUCCESS...'
    $ponTimer = [Diagnostics.Stopwatch]::StartNew()
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
    Write-Host '[3/7] X55 ONLINE / PON_SUCCESS' -ForegroundColor Green
    Write-Log ('New PON_SUCCESS: ' + $postPon)
    Write-Timing -Name 'core_pon_success' -Stopwatch $ponTimer
    [void](Invoke-Root -Command "cat $EsocLog 2>/dev/null | tail -n 50")

    Write-Host ''
    Write-Host 'Allowing X55 / qcrild / UICC stack to settle for 10 seconds...'
    Write-Log ("Post-PON stabilization wait: {0}s" -f $PostPonSettleSeconds)
    $settleTimer = [Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Seconds $PostPonSettleSeconds
    Write-Timing -Name 'core_post_pon_settle' -Stopwatch $settleTimer

    Write-Host ''
    Write-Host 'Checking whether X55 restart alone already restored WFC...'
    $x55OnlyTimer = [Diagnostics.Stopwatch]::StartNew()
    $x55OnlyHealthy = Wait-WfcHealthy -MaxSeconds 5 -Tag 'after_x55_only'
    Write-Timing -Name 'core_x55_only_health_checks' -Stopwatch $x55OnlyTimer
    if ($x55OnlyHealthy) {
        $finalResult = 'X55_ONLY_SUCCESS'
        $script:FreezeOnHealthy = $true
        Write-Log 'FREEZE_ON_HEALTHY=TRUE reason=X55_ONLY_SUCCESS'
        throw [System.OperationCanceledException]::new('RECOVERY_SUCCESS')
    }

    # STEP 9
    Write-Host ''
    Write-Host '[4/7] Cycling SIM2' -ForegroundColor Cyan

    Invoke-SimPowerCycle -Attempt 1

    $baseline=Get-AuthoritativeCurrentCne
    $script:CneBaselineRequest=$baseline.Request
    Write-Host ("CNE_BASELINE_REQUEST={0}" -f $baseline.Request)
    Write-Log ("CNE_BASELINE source={0} registered={1} active={2} request={3} satisfied={4}" -f $baseline.Source,$baseline.Registered,$baseline.Active,$baseline.Request,$baseline.Satisfied)

    if(-not (Invoke-StableCnePrime)){Fail 'STABLE_CNE_PRIME failed; golden rollback guard has run if UICC false was sent.'}
    if(-not (Wait-FreshCne -BaselineRequest $script:CneBaselineRequest -MaxSeconds 45)){
        $finalResult='NO_FRESH_CNE_AFTER_PRIME'
        throw [System.InvalidOperationException]::new('No fresh current-table CNE request appeared within 45 seconds.')
    }
    if(-not (Wait-StableCneWfc -MaxSeconds 30)){
        $finalResult='FRESH_CNE_BUT_WFC_TIMEOUT'
        throw [System.InvalidOperationException]::new('Fresh CNE appeared, but strict IMS/WLAN/VOICE-IWLAN/WFC health did not complete.')
    }
    if($null -ne $script:SimPowerOnToHealthTimer -and $script:SimPowerOnToHealthTimer.IsRunning){Write-Timing -Name 'core_sim_on_to_health_result' -Stopwatch $script:SimPowerOnToHealthTimer}
    $finalResult='STABLE_CNE_SUCCESS'
    $script:FreezeOnHealthy=$true
    Write-Log 'FREEZE_ON_HEALTHY=TRUE reason=STABLE_CNE_SUCCESS'
    throw [System.OperationCanceledException]::new('RECOVERY_SUCCESS')
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
            Record-PhoneWrite 'SIM2_POWER_ON_ROLLBACK'
            $script:SimMayBeOff = $false
        }
        catch {
            Write-Log ('SIM recovery guard error: ' + $_.Exception.Message)
        }
    }

    if ($script:FreezeOnHealthy) {
        $script:CleanupOk = $true
        $script:CleanupDetail = 'SKIPPED_FREEZE_ON_HEALTHY'
        $script:PostCleanupWfc = 'HEALTHY'
        Write-Host '[FREEZE] WFC is healthy. Transactional cleanup is intentionally skipped.' -ForegroundColor Green
        Write-Log 'CLEANUP_RESULT=SKIPPED_FREEZE_ON_HEALTHY'
    }
    else {
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
}


$recoverySucceeded = ($finalResult -eq 'ALREADY_HEALTHY' -or $finalResult -match 'SUCCESS$')

if ($recoverySucceeded) {
    if ($script:FreezeOnHealthy) {
        $script:PostCleanupWfc = 'HEALTHY'
    }
    elseif ($finalResult -eq 'ALREADY_HEALTHY') {
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

    if ($script:FreezeOnHealthy) {
        Write-Host 'IMS         : REGISTERED'
        Write-Host 'Transport   : WLAN'
        Write-Host 'VOICE/IWLAN : AVAILABLE'
        Write-Host 'WFC         : AVAILABLE'
        Write-Host 'vendor.per_mgr / temporary holder: FROZEN AT HEALTHY STATE'
        Write-Host ''
        Write-Host '[OK] Recovery succeeded. No post-success telephony/native cleanup was executed.' -ForegroundColor Green
    }
    elseif ($script:CleanupOk -and $script:PostCleanupWfc -eq 'HEALTHY') {
        Write-Host 'IMS         : REGISTERED'
        Write-Host 'Transport   : WLAN'
        Write-Host 'VOICE/IWLAN : AVAILABLE'
        Write-Host 'WFC         : AVAILABLE'
        Write-Host 'vendor.per_mgr / pm-service: native owner restored'
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
        Write-Host '[OK] Recovery failed, but the script restored the verified native pm-service/X55 baseline.' -ForegroundColor Green
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
if (-not $NoPause) {
    Read-Host 'Press Enter to close this window'
}

Write-Host ''
Write-Host '=== STABLE_CNE_V1 SUMMARY ==='
Write-Host ("CNE_PRIME={0}" -f $script:CnePrimeResult)
Write-Host ("F8_CONFIRMED={0}" -f $(if($script:F8Confirmed){'YES'}else{'NO'}))
Write-Host ("CNE_BASELINE_REQUEST={0}" -f $script:CneBaselineRequest)
Write-Host ("FRESH_CNE_REQUEST={0}" -f $script:FreshCneRequest)
Write-Host ("CNE_TRIGGER_LATENCY_MS={0}" -f $script:CneTriggerLatencyMs)
Write-Host ("IMS_REGISTERED={0}" -f $(if($script:ImsRegistered){'YES'}else{'NO'}))
Write-Host ("WFC_HEALTHY={0}" -f $(if($script:WfcHealthy -or $script:PostCleanupWfc -eq 'HEALTHY'){'YES'}else{'NO'}))
Write-Host ("TOTAL_END_TO_END_MS={0}" -f $script:CoreTotal.ElapsedMilliseconds)
Write-Host ("FINAL_RESULT={0}" -f $finalResult)
Write-Host ("PHONE_WRITE_COUNT={0}" -f $script:PhoneWriteCount)
foreach($action in $script:PhoneWriteActions){Write-Host ("PHONE_WRITE={0}" -f $action)}
Write-Log ("STABLE_CNE_SUMMARY prime={0} f8={1} baseline={2} fresh={3} cneMs={4} ims={5} wfc={6} final={7} writes={8}" -f $script:CnePrimeResult,$script:F8Confirmed,$script:CneBaselineRequest,$script:FreshCneRequest,$script:CneTriggerLatencyMs,$script:ImsRegistered,$script:WfcHealthy,$finalResult,$script:PhoneWriteCount)
Write-CoreTotalTiming
if (-not $script:CleanupOk) { exit 30 }
if ($recoverySucceeded -and $script:PostCleanupWfc -eq 'HEALTHY') { exit 0 }
if ($recoverySucceeded -and $script:PostCleanupWfc -eq 'LOST_AFTER_CLEANUP') { exit 21 }
if ($finalResult -eq 'AUTO_RECOVERY_FAILED') { exit 20 }
exit 1
