param([string]$Serial)
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..')).Path
$Adb = Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$HelperLocal = Join-Path $PSScriptRoot '..\build\slot1-sim-power-helper.jar'
$DeviceDir = '/data/local/tmp/voxi-l1_5-executor'
$Helper = "$DeviceDir/slot1-sim-power-helper.jar"
$Probe = '/data/adb/modules/voxi_wfc_recovery/lib/wfc-probe.jar'
$ExpectedHash = 'be877b6e9694b4100f2487dc892803de6399c89588f194a1e54d4c3ae3173a31'
$RunRoot = Join-Path (Split-Path $Repo -Parent) 'voxi_wfc_local_runs'
$RunDir = Join-Path $RunRoot ('stabilized_absent_second_reinsert_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
$Timeline = Join-Path $RunDir 'probe_timeline.jsonl'
$WriteAudit = Join-Path $RunDir 'write_audit.txt'
$script:PowerDownCount = 0
$script:NormalPowerUpCount = 0

function ADB([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args) { & $Adb -s $Serial @Args }
function Discover-Serial {
    $rows = & $Adb devices | Select-String '^\S+\s+device$' | ForEach-Object { ($_ -split '\s+')[0] }
    if ($Serial) { if ($rows -notcontains $Serial) { throw "Requested device $Serial is not online" }; return $Serial }
    $numeric = @($rows | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+:\d+$' })
    if ($numeric.Count -eq 1) { return $numeric[0] }
    if ($rows.Count -eq 1) { return $rows[0] }
    throw "Cannot uniquely resolve online ADB device: $($rows -join ', ')"
}
function Wait-Adb([int]$Seconds = 60) {
    $end = (Get-Date).AddSeconds($Seconds)
    do {
        $state = & $Adb -s $Serial get-state 2>$null
        if ($LASTEXITCODE -eq 0 -and $state -match 'device') { return }
        & $Adb reconnect offline 2>$null | Out-Null
        Start-Sleep 2
    } while ((Get-Date) -lt $end)
    throw 'ADB did not return before timeout; device watchdog remains authoritative'
}
function Root([string]$Command) { ADB shell su -c $Command }
function Helper([string]$Command) { Root "LAB_MODE=1 LAB_EXECUTE=YES CLASSPATH=$Helper app_process /system/bin Slot1SimPowerHelper $Command" }
function Probe([string]$Label) {
    Wait-Adb 45
    $raw = Root "CLASSPATH=$Probe app_process /system/bin WfcStateProbe read-only-json" 2>&1
    $json = $raw | Where-Object { $_ -match '^\{' } | Select-Object -Last 1
    if (-not $json) { throw "Probe $Label returned no JSON" }
    $json | Set-Content -LiteralPath (Join-Path $RunDir "$Label.json") -Encoding ascii
    $json | Add-Content -LiteralPath $Timeline -Encoding ascii
    return ($json | ConvertFrom-Json)
}
function Assert-Slot0($S,[string]$At) {
    if (-not $S.protectedSlot0.active -or -not $S.protectedSlot0.mappingGate -or $S.protectedSlot0.subId -ne 1 -or $S.protectedSlot0.slotId -ne 0 -or $S.protectedSlot0.carrierId -ne 2237 -or $S.protectedSlot0.mcc -ne 460 -or $S.protectedSlot0.mnc -ne 11) { throw "slot0 gate failed at $At" }
}
function Assert-InitialF1($S) {
    Assert-Slot0 $S 'initial'
    if (-not $S.safetyGate -or -not $S.target.mappingGate -or $S.target.subId -ne 11 -or $S.target.slotId -ne 1 -or $S.target.phoneId -ne 1 -or $S.target.carrierId -ne 28 -or $S.target.mcc -ne 234 -or $S.target.mnc -ne 15 -or -not $S.subscription.active -or -not $S.subscription.areUiccApplicationsEnabled -or $S.goldenStrong -or $S.failureClass -ne 'F1' -or $S.ims.registrationStateRaw -ne 0 -or $S.wfc.wifiCallingAvailable) { throw 'Current state is not authorized ACTIVE+ENABLED strict F1' }
}
function DirectHealthy($S) { return $S.ims.registrationStateRaw -eq 2 -and $S.ims.registrationTransportRaw -eq 2 -and $S.mmtel.voiceIwlanAvailable -and $S.wfc.wifiCallingAvailable }
function StrictF1($S) { return $S.safetyGate -and $S.target.mappingGate -and $S.subscription.active -and $S.subscription.areUiccApplicationsEnabled -and $S.failureClass -eq 'F1' -and $S.ims.registrationStateRaw -eq 0 -and -not $S.wfc.wifiCallingAvailable }
function NetworkGate { $x = Root "ip addr show wlan0; ip addr show tun0" 2>&1; return ($LASTEXITCODE -eq 0 -and ($x -join "`n") -match 'wlan0.*UP' -and ($x -join "`n") -match 'tun0.*UP') }
function Deploy([string]$Local,[string]$Name) {
    $stage = "/data/local/tmp/$Name.stage"
    ADB push $Local $stage | Out-Null
    Root "cp $stage $DeviceDir/$Name && chmod 0700 $DeviceDir/$Name && rm -f $stage"
    if ($LASTEXITCODE -ne 0) { throw "Deploy failed: $Name" }
}
function Arm-Watchdog([int]$Cycle) {
    $arm = Helper ARM_ROLLBACK 2>&1
    if ($LASTEXITCODE -ne 0 -or ($arm -join "`n") -notmatch 'result=ROLLBACK_ARMED') { throw "Cycle $Cycle rollback arm failed" }
    Root "rm -f $DeviceDir/stabilized-watchdog-cycle$Cycle.ready $DeviceDir/stabilized-watchdog-cycle$Cycle.log; ABSENT_LAB_MODE=1 ABSENT_EXECUTE=YES $DeviceDir/stabilized_watchdog_cycle$Cycle.sh >/dev/null 2>&1 &"
    $end=(Get-Date).AddSeconds(20)
    do { Start-Sleep 1; $ready=Root "test -f $DeviceDir/stabilized-watchdog-cycle$Cycle.ready -a -f $DeviceDir/watchdog.ready; echo `$?" 2>$null; if (($ready | Select-Object -Last 1) -eq '0') { return } } while ((Get-Date) -lt $end)
    throw "Cycle $Cycle watchdog did not become ready"
}
function Sample-Schedule([string]$Prefix,[datetime]$Start,[int[]]$Points) {
    $last=$null
    foreach ($p in $Points) {
        $wait = $p - [int][Math]::Floor(((Get-Date)-$Start).TotalSeconds)
        if ($wait -gt 0) { Start-Sleep $wait }
        $last=Probe ("{0}_{1:D3}s" -f $Prefix,$p)
        Assert-Slot0 $last "${Prefix}_${p}s"
        if (DirectHealthy $last) { return [pscustomobject]@{State=$last;At=$p;Healthy=$true} }
    }
    return [pscustomobject]@{State=$last;At=$Points[-1];Healthy=$false}
}
function Confirm-Absent([int]$MaxSeconds,[string]$Prefix) {
    $end=(Get-Date).AddSeconds($MaxSeconds)
    do {
        $raw=Helper DRY_RUN 2>&1
        $text=$raw -join "`n"
        if ($text -match 'before\.target=.*active=false.*uiccEnabled=false.*simState=1.*mappingGate=false' -and $text -match 'before\.slot0=.*active=true.*simState=5.*mappingGate=true') { return $true }
        Start-Sleep 1
    } while ((Get-Date) -lt $end)
    return $false
}

$Serial = Discover-Serial
"serial=$Serial`nrunDir=$RunDir" | Set-Content $WriteAudit
if ((ADB shell getprop ro.product.model) -notmatch '23116PN5BC') { throw 'Unexpected device model' }
if ((Root 'id') -notmatch 'uid=0') { throw 'Root unavailable' }
if ((Get-FileHash $HelperLocal -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedHash) { throw 'Helper hash mismatch' }
$before=Probe 'before_F1'
Assert-InitialF1 $before
if (-not (NetworkGate)) { throw 'wlan0/tun0 gate failed' }

Deploy (Join-Path $PSScriptRoot 'device\stabilized_watchdog_cycle1.sh') 'stabilized_watchdog_cycle1.sh'
Deploy (Join-Path $PSScriptRoot 'device\stabilized_watchdog_cycle2.sh') 'stabilized_watchdog_cycle2.sh'
Deploy (Join-Path $PSScriptRoot 'device\stabilized_cycle1_orchestrator.sh') 'stabilized_cycle1_orchestrator.sh'
Arm-Watchdog 1
"cycle1WatchdogReady=$((Get-Date).ToString('o'))" | Add-Content $WriteAudit
$cycle1Start=Get-Date
$script:PowerDownCount++
$script:NormalPowerUpCount++
"T0_cycle1_orchestrator_start=$($cycle1Start.ToString('o')); plannedDownCount=$script:PowerDownCount; plannedNormalUpCount=$script:NormalPowerUpCount" | Add-Content $WriteAudit
$orchestrator=Root "ABSENT_LAB_MODE=1 ABSENT_EXECUTE=YES $DeviceDir/stabilized_cycle1_orchestrator.sh" 2>&1
$orchestrator | Set-Content (Join-Path $RunDir 'cycle1_orchestrator_stdout.txt')
$orchestratorExit=$LASTEXITCODE
Wait-Adb 90
Root "cat $DeviceDir/stabilized-cycle1-orchestrator.log; echo =====WATCHDOG=====; cat $DeviceDir/stabilized-watchdog-cycle1.log" | Set-Content (Join-Path $RunDir 'cycle1_device_logs.txt')
if ($orchestratorExit -ne 0) { throw "Cycle1 orchestrator failed rc=$orchestratorExit; watchdog is authoritative and no second cycle is allowed" }
$cycle1Up=Get-Date
$r1=Sample-Schedule 'cycle1_recover' $cycle1Up @(5,10,15,20,30,45,60,90)
if ($r1.Healthy) {
    $out=[ordered]@{Result='PASS_FIRST_REINSERT';FirstHealthySeconds=$r1.At;PowerDownCount=$script:PowerDownCount;NormalPowerUpCount=$script:NormalPowerUpCount;SecondCycleExecuted=$false;Final=$r1.State}
    $out | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $RunDir 'RESULT.json')
    Write-Output ($out | ConvertTo-Json -Compress -Depth 8); exit 0
}
if (-not (StrictF1 $r1.State)) { throw 'First reinsert did not end in strict F1; second cycle forbidden' }
if (-not (NetworkGate)) { throw 'Network gate failed before second cycle' }
Assert-Slot0 $r1.State 'before_cycle2'

Arm-Watchdog 2
"cycle2WatchdogReady=$((Get-Date).ToString('o'))" | Add-Content $WriteAudit
if ($script:PowerDownCount -ge 2) { throw 'POWER_DOWN budget exhausted before cycle2' }
$script:PowerDownCount++
"T12_second_POWER_DOWN_start=$((Get-Date).ToString('o')); downCount=$script:PowerDownCount" | Add-Content $WriteAudit
$down2=Helper POWER_DOWN 2>&1
$down2 | Add-Content $WriteAudit
if ($LASTEXITCODE -ne 0) { throw 'Second and final POWER_DOWN failed; watchdog remains armed' }
if (-not (Confirm-Absent 30 'cycle2')) { throw 'Second true absent not confirmed; watchdog remains armed' }
"T13_second_absent=$((Get-Date).ToString('o'))" | Add-Content $WriteAudit
Start-Sleep 10
if ($script:NormalPowerUpCount -ge 2) { throw 'Normal POWER_UP budget exhausted before cycle2' }
$script:NormalPowerUpCount++
"T14_second_POWER_UP_start=$((Get-Date).ToString('o')); normalUpCount=$script:NormalPowerUpCount" | Add-Content $WriteAudit
$up2=Helper POWER_UP 2>&1
$up2 | Add-Content $WriteAudit
if ($LASTEXITCODE -ne 0 -or ($up2 -join "`n") -notmatch 'result=COMMAND_COMPLETED') { throw 'Second normal POWER_UP failed; watchdog remains authoritative' }
$cycle2Up=Get-Date
$r2=Sample-Schedule 'cycle2_recover' $cycle2Up @(5,10,15,20,30,45,60,90,120,180)
$result=if ($r2.Healthy) {'PASS_SECOND_REINSERT'} else {'FAIL_AFTER_SECOND_REINSERT'}
$out=[ordered]@{Result=$result;FirstCycleFinalFailureClass=$r1.State.failureClass;SecondHealthySeconds=if($r2.Healthy){$r2.At}else{$null};PowerDownCount=$script:PowerDownCount;NormalPowerUpCount=$script:NormalPowerUpCount;SecondCycleExecuted=$true;Final=$r2.State}
$out | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $RunDir 'RESULT.json')
Write-Output ($out | ConvertTo-Json -Compress -Depth 8)
if (-not $r2.Healthy) { exit 2 }