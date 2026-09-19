param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(2, 3)]
    [int]$CycleNumber
)

$ErrorActionPreference = "Stop"
$Adb = Join-Path $PSScriptRoot "..\..\adb.exe"
$Serial = "192.168.137.134:39247"
$ProbeJar = "/data/local/tmp/wfc-state-probe.jar"
$FaultJar = "/data/local/tmp/phase4-uicc-helper.jar"
$RecoverJar = "/data/local/tmp/slot1-uicc-recover.jar"
$OutDir = Join-Path $PSScriptRoot "experiments\cycle${CycleNumber}_validation"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Invoke-Probe([string]$Name) {
    $raw = & $Adb -s $Serial shell su -c "CLASSPATH=$ProbeJar app_process /system/bin WfcStateProbe read-only-json" 2>&1
    $raw | Out-File -LiteralPath (Join-Path $OutDir "$Name.txt") -Encoding utf8
    $jsonLine = $raw | Where-Object { $_ -match '^\{' } | Select-Object -Last 1
    if (-not $jsonLine) { throw "Probe $Name did not return JSON" }
    $jsonLine | Out-File -LiteralPath (Join-Path $OutDir "$Name.json") -Encoding ascii
    return ($jsonLine | ConvertFrom-Json)
}

function Capture-Dumps([string]$Name) {
    $path = Join-Path $OutDir "$Name.txt"
    "hostTime=$((Get-Date).ToString('o'))" | Set-Content -LiteralPath $path -Encoding utf8
    foreach ($service in @("isub", "telephony.registry", "phone", "carrier_config", "connectivity")) {
        "`n===== dumpsys $service =====" | Add-Content -LiteralPath $path -Encoding utf8
        & $Adb -s $Serial shell dumpsys $service 2>&1 | Out-File -LiteralPath $path -Encoding utf8 -Append
    }
}

function Assert-ProtectedSlot0($State, [string]$Stage) {
    if (-not $State.protectedSlot0.mappingGate -or -not $State.protectedSlot0.active) {
        throw "Protected slot0 failed at $Stage"
    }
}

$before = Invoke-Probe "pre_golden"
Assert-ProtectedSlot0 $before "pre_golden"
if (-not $before.safetyGate -or -not $before.goldenStrong -or -not $before.subscription.areUiccApplicationsEnabled) {
    throw "Cycle $CycleNumber pre-write GOLDEN_STRONG/safety gate failed"
}
Capture-Dumps "dumps_pre_golden"

$cycleStart = Get-Date
$logcatSince = $cycleStart.ToString("MM-dd HH:mm:ss.fff", [Globalization.CultureInfo]::InvariantCulture)
"cycle=$CycleNumber`nhostFalseStart=$($cycleStart.ToString('o'))" |
    Set-Content -LiteralPath (Join-Path $OutDir "writes.txt") -Encoding utf8
& $Adb -s $Serial shell su -c "CLASSPATH=$FaultJar app_process /system/bin Phase4UiccHelper disable" 2>&1 |
    Out-File -LiteralPath (Join-Path $OutDir "writes.txt") -Encoding utf8 -Append
"hostFalseEnd=$((Get-Date).ToString('o'))" | Add-Content -LiteralPath (Join-Path $OutDir "writes.txt") -Encoding utf8

$last = 0
$faultStates = @()
foreach ($target in @(2, 5, 10)) {
    Start-Sleep -Seconds ($target - $last)
    $state = Invoke-Probe ("fault_{0:D3}s" -f $target)
    Assert-ProtectedSlot0 $state "fault_${target}s"
    $faultStates += $state
    $last = $target
}

$fault5 = $faultStates[1]
$fault10 = $faultStates[2]
$persistentF8 = $fault5.failureClass -eq "F8" -and $fault10.failureClass -eq "F8" `
        -and -not $fault5.subscription.active -and -not $fault10.subscription.active `
        -and -not $fault5.target.mappingGate -and -not $fault10.target.mappingGate
if (-not $persistentF8) {
    Capture-Dumps "dumps_fault_unexpected"
    throw "Cycle $CycleNumber did not reach persistent inactive F8; true/reset were not executed"
}
Capture-Dumps "dumps_fault_f8"

& $Adb -s $Serial shell su -c "CLASSPATH=$RecoverJar app_process /system/bin Slot1UiccRecoverHelper dry-run" 2>&1 |
    Out-File -LiteralPath (Join-Path $OutDir "writes.txt") -Encoding utf8 -Append
if ($LASTEXITCODE -ne 0) { throw "Cycle $CycleNumber inactive true-recovery gate failed" }

"hostTrueStart=$((Get-Date).ToString('o'))" | Add-Content -LiteralPath (Join-Path $OutDir "writes.txt") -Encoding utf8
& $Adb -s $Serial shell su -c "CLASSPATH=$RecoverJar app_process /system/bin Slot1UiccRecoverHelper recover" 2>&1 |
    Out-File -LiteralPath (Join-Path $OutDir "writes.txt") -Encoding utf8 -Append
if ($LASTEXITCODE -ne 0) { throw "Cycle $CycleNumber true call failed" }
"hostTrueEnd=$((Get-Date).ToString('o'))" | Add-Content -LiteralPath (Join-Path $OutDir "writes.txt") -Encoding utf8

$recoveryStart = Get-Date
$elapsed = 0
$goldenStart = $null
$finalState = $null
while ($elapsed -lt 420) {
    Start-Sleep -Seconds 5
    $elapsed = [int][Math]::Floor((New-TimeSpan -Start $recoveryStart -End (Get-Date)).TotalSeconds)
    $finalState = Invoke-Probe ("recover_{0:D3}s" -f $elapsed)
    Assert-ProtectedSlot0 $finalState "recover_${elapsed}s"

    if ($elapsed -in @(15, 60, 120)) { Capture-Dumps ("dumps_recover_{0:D3}s" -f $elapsed) }

    if ($finalState.goldenStrong) {
        if ($null -eq $goldenStart) { $goldenStart = $elapsed }
        if (($elapsed - $goldenStart) -ge 300) { break }
    } else {
        $goldenStart = $null
    }
}

$passed = $null -ne $goldenStart -and ($elapsed - $goldenStart) -ge 300 `
        -and $finalState.ims.registrationStateRaw -eq 2 `
        -and $finalState.ims.registrationTransportRaw -eq 2 `
        -and $finalState.mmtel.voiceIwlanAvailable `
        -and $finalState.wfc.wifiCallingAvailable `
        -and $finalState.connectivity.imsIwlanNetworkAgent `
        -and $finalState.protectedSlot0.mappingGate

Capture-Dumps "dumps_final"
$pattern = "QCNEJ|qti.cne|DataCallAgent|NativeHalServerCallback|NetworkRequest|DNC-1|DN-[0-9]+-I|ImsResolver|ImsService|ImsPhone|MMTEL|RCS|IWLAN|Epdg|CarrierConfig|CLEAR_CONFIG|NO_SIM|ESSENTIAL_LOADED|LOADED|Subscription|Uicc|setImsRegistrationState"
& $Adb -s $Serial shell "logcat -b all -v threadtime -T '$logcatSince' -d | grep -iE '$pattern'" 2>&1 |
    Out-File -LiteralPath (Join-Path $OutDir "observation.txt") -Encoding utf8

$result = [ordered]@{
    cycle = $CycleNumber
    persistentF8 = $persistentF8
    goldenStrongFirstSeenAtSeconds = $goldenStart
    continuousGoldenSeconds = if ($null -eq $goldenStart) { 0 } else { $elapsed - $goldenStart }
    finalGoldenStrong = $finalState.goldenStrong
    protectedSlot0 = $finalState.protectedSlot0.mappingGate
    registrationStateRaw = $finalState.ims.registrationStateRaw
    registrationTransportRaw = $finalState.ims.registrationTransportRaw
    voiceIwlanAvailable = $finalState.mmtel.voiceIwlanAvailable
    wifiCallingAvailable = $finalState.wfc.wifiCallingAvailable
    imsIwlanNetworkAgent = $finalState.connectivity.imsIwlanNetworkAgent
    passed = $passed
}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutDir "RESULT.json") -Encoding ascii
if (-not $passed) { throw "Cycle $CycleNumber failed validation; no further fault cycle is allowed" }
Write-Output ($result | ConvertTo-Json -Compress)
