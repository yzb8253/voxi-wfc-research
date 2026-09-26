[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceCore = Join-Path $PSScriptRoot 'X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1'
$targetCore = Join-Path $PSScriptRoot 'X55-WFC-STABLE-CNE-V1-core.ps1'
$sourceUicc = Join-Path $PSScriptRoot 'uicc_apps_deep_fallback.ps1'
$targetUicc = Join-Path $PSScriptRoot 'STABLE-CNE-V1-uicc-prime.ps1'

function Replace-ExactOnce {
    param([string]$Text,[string]$Old,[string]$New,[string]$Label)
    $first = $Text.IndexOf($Old,[StringComparison]::Ordinal)
    if($first -lt 0){ throw "Missing build anchor: $Label" }
    if($Text.IndexOf($Old,$first+$Old.Length,[StringComparison]::Ordinal) -ge 0){ throw "Non-unique build anchor: $Label" }
    return $Text.Substring(0,$first)+$New+$Text.Substring($first+$Old.Length)
}

$uicc = [IO.File]::ReadAllText($sourceUicc)
$uicc = Replace-ExactOnce $uicc "    [int]`$IsubTransaction=46" "    [int]`$IsubTransaction=46" 'uicc params unchanged'
$uicc = Replace-ExactOnce $uicc "Require ((Root 'settings get global airplane_mode_on') -eq '0') 'UICC deep fallback must start in airplane-OFF A0'" "Require ((Root 'settings get global airplane_mode_on') -eq '1') 'STABLE_CNE_V1 UICC prime must start in airplane-ON recovery state'" 'airplane gate'
$uicc = Replace-ExactOnce $uicc "`$mustReenable=`$false`ntry {" "`$mustReenable=`$false`n`$writeCount=0`ntry {" 'uicc write count init'
$uicc = Replace-ExactOnce $uicc "    `$off=RootResult" "    Write-Host 'UICC_PHONE_WRITE=UICC_APPS_FALSE_SUB11'`n    `$writeCount++`n    `$off=RootResult" 'uicc false instrumentation'
$uicc = Replace-ExactOnce $uicc "    `$on=RootResult" "    Write-Host (`"UICC_TRUE_HOST_EPOCH_MS={0}`" -f [DateTimeOffset]::Now.ToUnixTimeMilliseconds())`n    Write-Host 'UICC_PHONE_WRITE=UICC_APPS_TRUE_SUB11'`n    `$writeCount++`n    `$on=RootResult" 'uicc true instrumentation'
$uicc = Replace-ExactOnce $uicc "        Write-Host '[UICC GUARD] Sending one emergency TRUE for VOXI subId11.' -ForegroundColor Yellow" "        Write-Host '[UICC GUARD] Sending one emergency TRUE for VOXI subId11.' -ForegroundColor Yellow`n        Write-Host 'UICC_PHONE_WRITE=UICC_APPS_TRUE_SUB11_ROLLBACK'`n        `$writeCount++" 'uicc rollback instrumentation'
$uicc = Replace-ExactOnce $uicc "        [void](RootResult (`"service call isub {0} i32 1 i32 11`" -f `$IsubTransaction))`n    }`n}" "        [void](RootResult (`"service call isub {0} i32 1 i32 11`" -f `$IsubTransaction))`n    }`n    Write-Host (`"UICC_PHONE_WRITE_COUNT={0}`" -f `$writeCount)`n}" 'uicc final write count'
[IO.File]::WriteAllText($targetUicc,$uicc,(New-Object Text.UTF8Encoding($false)))

$core = [IO.File]::ReadAllText($sourceCore)
$core = Replace-ExactOnce $core "`$EsocLog = '/sys/kernel/debug/ipc_logging/esoc-mdm/log'" "`$EsocLog = '/sys/kernel/debug/ipc_logging/esoc-mdm/log'`n`$CurrentCneProjection = Join-Path `$Repo 'experiments\wfc_repeatability_normalization\lightweight_profiling\current_cne_projection_v12h_r2.ps1'`n`$StableCneContract = Join-Path `$PSScriptRoot 'STABLE-CNE-V1-contract.ps1'`n`$UiccPrime = Join-Path `$PSScriptRoot 'STABLE-CNE-V1-uicc-prime.ps1'`n. `$CurrentCneProjection`n. `$StableCneContract" 'core dependencies'
$core = Replace-ExactOnce $core "`$ScriptVersion = 'v2.6.2-freeze-on-success'" "`$ScriptVersion = 'STABLE_CNE_V1'" 'version'

$functions = @'
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

'@
$core = Replace-ExactOnce $core 'function Get-PerMgrState {' ($functions+'function Get-PerMgrState {') 'stable cne functions'

$state = @'
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
'@
$core = Replace-ExactOnce $core '$script:FreezeOnHealthy = $false' ('$script:FreezeOnHealthy = $false'+"`n"+$state.TrimEnd()) 'stable cne state'

$core = Replace-ExactOnce $core "    `$stop = Invoke-Root -Command 'setprop ctl.stop vendor.per_mgr' -Quiet" "    `$stop = Invoke-Root -Command 'setprop ctl.stop vendor.per_mgr' -Quiet`n    if(`$stop.Code -eq 0){Record-PhoneWrite 'CTL_STOP_VENDOR_PER_MGR'}" 'per mgr stop count'
$core = Replace-ExactOnce $core "    Start-HolderWindow`n`n    if (-not (Wait-HolderStarted" "    Start-HolderWindow`n    Record-PhoneWrite 'START_TEMP_X55_HOLDER'`n`n    if (-not (Wait-HolderStarted" 'holder count'
$core = Replace-ExactOnce $core "    `$off = Invoke-Root -Command `"service call phone `$SimPowerTransaction i32 1 i32 0`"" "    `$off = Invoke-Root -Command `"service call phone `$SimPowerTransaction i32 1 i32 0`"`n    if(`$off.Code -eq 0){Record-PhoneWrite 'SIM2_POWER_OFF'}" 'sim off count'
$core = Replace-ExactOnce $core "    `$on1 = Invoke-Root -Command `"service call phone `$SimPowerTransaction i32 1 i32 1`"" "    `$on1 = Invoke-Root -Command `"service call phone `$SimPowerTransaction i32 1 i32 1`"`n    if(`$on1.Code -eq 0){Record-PhoneWrite 'SIM2_POWER_ON'}" 'sim on count'
$core = Replace-ExactOnce $core "            [void](Invoke-Root -Command `"service call phone `$SimPowerTransaction i32 1 i32 1`" -Quiet)" "            [void](Invoke-Root -Command `"service call phone `$SimPowerTransaction i32 1 i32 1`" -Quiet)`n            Record-PhoneWrite 'SIM2_POWER_ON_ROLLBACK'" 'sim guard count'

$start = $core.IndexOf('    $cneBefore = Get-CneSnapshot',[StringComparison]::Ordinal)
$endMarker = "}`ncatch [System.OperationCanceledException] {"
$end = $core.IndexOf($endMarker,$start,[StringComparison]::Ordinal)
if($start -lt 0 -or $end -lt 0){throw 'Missing post-SIM replacement anchors'}
$newFlow = @'
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

'@
$core = $core.Substring(0,$start)+$newFlow+$core.Substring($end)

$summary = @'
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

'@
$core = Replace-ExactOnce $core "Write-CoreTotalTiming`nif (-not `$script:CleanupOk)" ($summary+"Write-CoreTotalTiming`nif (-not `$script:CleanupOk)") 'final summary'
$core = $core.Replace("Write-Host '[7/9] Starting temporary X55 holder...'","Write-Host '[2/7] Restarting X55 / starting temporary holder...'")
$core = $core.Replace("Write-Host '[OK] New PON_SUCCESS confirmed.'","Write-Host '[3/7] X55 ONLINE / PON_SUCCESS'")
$core = $core.Replace("Write-Host '[9/9] Software SIM2 power cycle - single attempt...'","Write-Host '[4/7] Cycling SIM2' -ForegroundColor Cyan")
[IO.File]::WriteAllText($targetCore,$core,(New-Object Text.UTF8Encoding($false)))

Write-Host "BUILT=$targetCore"
Write-Host "BUILT=$targetUicc"
