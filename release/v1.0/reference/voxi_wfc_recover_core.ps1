$ErrorActionPreference = "Stop"

$Adb = Join-Path $PSScriptRoot "..\..\adb.exe"
$Serial = "192.168.137.134:39247"
$ProbeJar = "/data/local/tmp/wfc-state-probe.jar"
$RecoverJar = "/data/local/tmp/slot1-uicc-recover.jar"

function Probe {
    $raw = & $Adb -s $Serial shell su -c "CLASSPATH=$ProbeJar app_process /system/bin WfcStateProbe read-only-json" 2>&1
    $line = $raw | Where-Object { $_ -match '^\{' } | Select-Object -Last 1
    if (-not $line) { throw "WfcStateProbe did not return JSON" }
    Write-Output $line
}

$beforeLine = Probe
$before = $beforeLine | ConvertFrom-Json
if ($before.goldenStrong) {
    Write-Output $beforeLine
    Write-Output "FAILURE_CLASS: $($before.failureClass)"
    Write-Output "Already GOLDEN_STRONG; no write executed."
    exit 0
}

if ($before.subscription.active -or $before.target.mappingGate) {
    Write-Output $beforeLine
    Write-Output "FAILURE_CLASS: $($before.failureClass)"
    throw "Active-subscription failure is not yet experimentally validated for automatic recovery; no write executed."
}
if (-not $before.protectedSlot0.mappingGate) {
    throw "Protected slot0 gate failed; no write executed."
}

& $Adb -s $Serial shell su -c "CLASSPATH=$RecoverJar app_process /system/bin Slot1UiccRecoverHelper dry-run"
if ($LASTEXITCODE -ne 0) { throw "Inactive recovery dry-run failed; no write executed." }
& $Adb -s $Serial shell su -c "CLASSPATH=$RecoverJar app_process /system/bin Slot1UiccRecoverHelper recover"
if ($LASTEXITCODE -ne 0) { throw "Symmetric true recovery call failed." }

$goldenSince = $null
for ($elapsed = 5; $elapsed -le 180; $elapsed += 5) {
    Start-Sleep -Seconds 5
    $line = Probe
    $state = $line | ConvertFrom-Json
    Write-Output $line
    if (-not $state.protectedSlot0.mappingGate) { throw "Protected slot0 gate failed after recovery." }
    if ($state.goldenStrong) {
        if ($null -eq $goldenSince) { $goldenSince = $elapsed }
        if (($elapsed - $goldenSince) -ge 60) {
            Write-Output "GOLDEN_STRONG stable for at least 60 seconds."
            exit 0
        }
    } else {
        $goldenSince = $null
    }
}
throw "Recovery did not maintain GOLDEN_STRONG for 60 seconds. No additional write was attempted."
