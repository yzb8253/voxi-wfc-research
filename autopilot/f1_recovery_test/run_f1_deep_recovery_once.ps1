$ErrorActionPreference = "Stop"

$Adb = Join-Path $PSScriptRoot "..\..\..\adb.exe"
$Serial = "192.168.137.134:39581"
$ProbeJar = "/data/adb/modules/voxi_wfc_recovery/lib/wfc-probe.jar"
$FaultJar = "/data/local/tmp/phase4-uicc-helper.jar"
$RecoverJar = "/data/adb/modules/voxi_wfc_recovery/lib/wfc-recovery-helper.jar"
$WritesPath = Join-Path $PSScriptRoot "writes.txt"
$TimelinePath = Join-Path $PSScriptRoot "probe_timeline.jsonl"

function Invoke-Probe([string]$Name) {
    $raw = & $Adb -s $Serial shell su -c "CLASSPATH=$ProbeJar app_process /system/bin WfcStateProbe read-only-json" 2>&1
    $jsonLine = $raw | Where-Object { $_ -match '^\{' } | Select-Object -Last 1
    if (-not $jsonLine) { throw "Probe $Name returned no JSON: $($raw -join ' ')" }
    $jsonLine | Set-Content -LiteralPath (Join-Path $PSScriptRoot "$Name.json") -Encoding ascii
    $jsonLine | Add-Content -LiteralPath $TimelinePath -Encoding ascii
    return ($jsonLine | ConvertFrom-Json)
}

function Assert-Slot0($State, [string]$Stage) {
    if (-not $State.protectedSlot0.active -or -not $State.protectedSlot0.mappingGate `
            -or $State.protectedSlot0.subId -ne 1 -or $State.protectedSlot0.slotId -ne 0 `
            -or $State.protectedSlot0.mcc -ne 460 -or $State.protectedSlot0.mnc -ne 11) {
        throw "Protected China Telecom slot0 gate failed at $Stage"
    }
}

function Assert-InitialF1($State) {
    Assert-Slot0 $State "initial_F1"
    if (-not $State.safetyGate -or -not $State.target.mappingGate `
            -or $State.target.subId -ne 11 -or $State.target.slotId -ne 1 `
            -or $State.target.phoneId -ne 1 -or $State.target.carrierId -ne 28 `
            -or $State.target.mcc -ne 234 -or $State.target.mnc -ne 15 `
            -or -not $State.subscription.active -or -not $State.subscription.areUiccApplicationsEnabled `
            -or $State.goldenStrong -or $State.failureClass -ne "F1" `
            -or $State.ims.registrationStateRaw -ne 0 `
            -or $State.wfc.wifiCallingAvailable `
            -or $State.connectivity.imsIwlanNetworkAgent) {
        throw "Initial state is not the authorized active/enabled F1 with all safety gates PASS"
    }
}

function Capture-Dumps([string]$Name) {
    $path = Join-Path $PSScriptRoot "$Name.txt"
    "hostTime=$((Get-Date).ToString('o'))" | Set-Content -LiteralPath $path -Encoding utf8
    foreach ($service in @("isub", "telephony.registry", "phone", "connectivity", "carrier_config")) {
        "`n===== dumpsys $service =====" | Add-Content -LiteralPath $path -Encoding utf8
        & $Adb -s $Serial shell dumpsys $service 2>&1 | Out-File -LiteralPath $path -Encoding utf8 -Append
    }
}

Remove-Item -LiteralPath $TimelinePath -Force -ErrorAction SilentlyContinue
$initial = Invoke-Probe "gate_F1"
Assert-InitialF1 $initial

$dryRun = & $Adb -s $Serial shell su -c "CLASSPATH=$FaultJar app_process /system/bin Phase4UiccHelper dry-run" 2>&1
$dryRunExit = $LASTEXITCODE
@(
    "experiment=F1_ACTIVE_BROKEN_DEEP_RECOVERY_ONCE"
    "initialHostTime=$((Get-Date).ToString('o'))"
    "faultDryRunExit=$dryRunExit"
    $dryRun
) | Set-Content -LiteralPath $WritesPath -Encoding utf8
if ($dryRunExit -ne 0 -or -not ($dryRun -match "target verification all pass: PASS")) {
    throw "Fixed false-helper safety dry-run failed; no write executed"
}

$experimentStart = Get-Date
$logcatSince = $experimentStart.ToString("MM-dd HH:mm:ss.fff", [Globalization.CultureInfo]::InvariantCulture)

"falseHostStart=$((Get-Date).ToString('o'))" | Add-Content -LiteralPath $WritesPath -Encoding utf8
$falseRaw = & $Adb -s $Serial shell su -c "CLASSPATH=$FaultJar app_process /system/bin Phase4UiccHelper disable" 2>&1
$falseExit = $LASTEXITCODE
$falseRaw | Add-Content -LiteralPath $WritesPath -Encoding utf8
"falseHostEnd=$((Get-Date).ToString('o'))`nfalseHelperExit=$falseExit" | Add-Content -LiteralPath $WritesPath -Encoding utf8
if ($falseExit -ne 0) {
    Capture-Dumps "after_false_error"
    throw "The single authorized false call failed; no true or other write was attempted"
}

$faultStart = Get-Date
$f8Consecutive = 0
$f8Reached = $false
$faultState = $null
while ((New-TimeSpan -Start $faultStart -End (Get-Date)).TotalSeconds -lt 30) {
    Start-Sleep -Seconds 1
    $elapsed = [int][Math]::Floor((New-TimeSpan -Start $faultStart -End (Get-Date)).TotalSeconds)
    $faultState = Invoke-Probe ("fault_{0:D3}s" -f $elapsed)
    Assert-Slot0 $faultState "fault_${elapsed}s"
    $inactiveEvidence = (-not $faultState.subscription.active) `
        -or ($faultState.subscription.areUiccApplicationsEnabled -eq $false)
    $isF8 = $faultState.failureClass -eq "F8" -and $inactiveEvidence `
        -and $faultState.ims.registrationStateRaw -eq 0
    if ($isF8) { $f8Consecutive++ } else { $f8Consecutive = 0 }
    if ($f8Consecutive -ge 2) {
        $f8Reached = $true
        break
    }
}

Capture-Dumps "after_false_F8"
if (-not $f8Reached) {
    throw "Persistent F8/inactive was not confirmed within 30 seconds; true was not executed"
}

$recoverDryRun = & $Adb -s $Serial shell su -c "CLASSPATH=$RecoverJar app_process /system/bin Slot1UiccRecoverHelper dry-run" 2>&1
$recoverDryRunExit = $LASTEXITCODE
"recoverDryRunHostTime=$((Get-Date).ToString('o'))`nrecoverDryRunExit=$recoverDryRunExit" | Add-Content -LiteralPath $WritesPath -Encoding utf8
$recoverDryRun | Add-Content -LiteralPath $WritesPath -Encoding utf8
if ($recoverDryRunExit -ne 0 -or -not ($recoverDryRun -match "inactiveRecoveryGate=PASS")) {
    throw "Fixed true-helper inactive safety gate failed; true was not executed"
}

"trueHostStart=$((Get-Date).ToString('o'))" | Add-Content -LiteralPath $WritesPath -Encoding utf8
$trueRaw = & $Adb -s $Serial shell su -c "CLASSPATH=$RecoverJar app_process /system/bin Slot1UiccRecoverHelper recover" 2>&1
$trueExit = $LASTEXITCODE
$trueRaw | Add-Content -LiteralPath $WritesPath -Encoding utf8
"trueHostEnd=$((Get-Date).ToString('o'))`ntrueHelperExit=$trueExit" | Add-Content -LiteralPath $WritesPath -Encoding utf8
if ($trueExit -ne 0) {
    Capture-Dumps "after_true_error"
    throw "The single authorized true call failed; no other write was attempted"
}

$recoveryStart = Get-Date
$firstGoldenSeconds = $null
$goldenState = $null
while ((New-TimeSpan -Start $recoveryStart -End (Get-Date)).TotalSeconds -lt 60) {
    Start-Sleep -Seconds 1
    $elapsed = [int][Math]::Floor((New-TimeSpan -Start $recoveryStart -End (Get-Date)).TotalSeconds)
    $state = Invoke-Probe ("recover_{0:D3}s" -f $elapsed)
    Assert-Slot0 $state "recover_${elapsed}s"
    if ($state.goldenStrong) {
        $firstGoldenSeconds = $elapsed
        $goldenState = $state
        break
    }
}

if ($null -eq $firstGoldenSeconds) {
    Capture-Dumps "recovery_failed_60s"
    & $Adb -s $Serial shell "logcat -b all -v threadtime -T '$logcatSince' -d" 2>&1 |
        Select-String -Pattern "ims|iwlan|epdg|wfc|vowifi|carrierconfig|subscription|uicc|mmtel|qti.cne" -CaseSensitive:$false |
        Out-File -LiteralPath (Join-Path $PSScriptRoot "observation.txt") -Encoding utf8
    throw "F1 deep recovery did not reach GOLDEN_STRONG within 60 seconds; no other write was attempted"
}

$stableStart = Get-Date
$finalState = $goldenState
$stabilityBroken = $false
while ((New-TimeSpan -Start $stableStart -End (Get-Date)).TotalSeconds -lt 300) {
    Start-Sleep -Seconds 5
    $stableElapsed = [int][Math]::Floor((New-TimeSpan -Start $stableStart -End (Get-Date)).TotalSeconds)
    $finalState = Invoke-Probe ("stable_{0:D3}s" -f $stableElapsed)
    Assert-Slot0 $finalState "stable_${stableElapsed}s"
    if (-not $finalState.goldenStrong) {
        $stabilityBroken = $true
        break
    }
}

Capture-Dumps "final_state"
& $Adb -s $Serial shell "logcat -b all -v threadtime -T '$logcatSince' -d" 2>&1 |
    Select-String -Pattern "ims|iwlan|epdg|wfc|vowifi|carrierconfig|subscription|uicc|mmtel|qti.cne|NetworkRequest" -CaseSensitive:$false |
    Out-File -LiteralPath (Join-Path $PSScriptRoot "observation.txt") -Encoding utf8

$passed = -not $stabilityBroken -and $finalState.goldenStrong `
    -and $finalState.ims.registrationStateRaw -eq 2 `
    -and $finalState.ims.registrationTransportRaw -eq 2 `
    -and $finalState.mmtel.voiceIwlanAvailable `
    -and $finalState.wfc.wifiCallingAvailable `
    -and $finalState.connectivity.imsIwlanNetworkAgent `
    -and $finalState.protectedSlot0.mappingGate

$result = [ordered]@{
    initialFailureClass = $initial.failureClass
    falseHelperExit = $falseExit
    persistentF8Reached = $f8Reached
    trueHelperExit = $trueExit
    recoveryTimeSeconds = $firstGoldenSeconds
    stableSeconds = [int][Math]::Floor((New-TimeSpan -Start $stableStart -End (Get-Date)).TotalSeconds)
    registrationStateRaw = $finalState.ims.registrationStateRaw
    registrationStateName = $finalState.ims.registrationStateName
    registrationTransportRaw = $finalState.ims.registrationTransportRaw
    registrationTransportName = $finalState.ims.registrationTransportName
    voiceIwlanAvailable = $finalState.mmtel.voiceIwlanAvailable
    wifiCallingAvailable = $finalState.wfc.wifiCallingAvailable
    imsIwlanNetworkAgent = $finalState.connectivity.imsIwlanNetworkAgent
    imsNetworkId = $finalState.connectivity.imsNetworkId
    qtiCneRequestId = $finalState.connectivity.qtiCneRequestId
    udp4500Keepalive = $finalState.epdg.udp4500Keepalive
    mmtelFeatureState = $finalState.mmtel.featureState
    protectedSlot0 = $finalState.protectedSlot0.mappingGate
    f1DeepRecovery = if ($passed) { "PASS" } else { "FAIL" }
}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot "RESULT.json") -Encoding ascii
if (-not $passed) { throw "F1 deep recovery failed or did not remain stable; no further write is allowed" }
Write-Output ($result | ConvertTo-Json -Compress)
