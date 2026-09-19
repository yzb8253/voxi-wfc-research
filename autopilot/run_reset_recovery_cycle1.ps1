$ErrorActionPreference = "Stop"

$Adb = Join-Path $PSScriptRoot "..\..\adb.exe"
$Serial = "192.168.137.134:39247"
$OutDir = Join-Path $PSScriptRoot "experiments\cycle1_reset_recovery"
$ProbeJar = "/data/local/tmp/wfc-state-probe.jar"
$ResetJar = "/data/local/tmp/slot1-ims-reset.jar"
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

$before = Invoke-Probe "t_before_reset"
if (-not $before.safetyGate -or -not $before.protectedSlot0.mappingGate) {
    throw "Reset safety gate failed"
}
if ($before.goldenStrong) {
    throw "Device is already strong Golden; reset is unnecessary and was not executed"
}

Capture-Dumps "dumps_before_reset"
$start = Get-Date
$logcatSince = $start.ToString("MM-dd HH:mm:ss.fff", [Globalization.CultureInfo]::InvariantCulture)

"hostWriteStart=$($start.ToString('o'))" | Set-Content -LiteralPath (Join-Path $OutDir "reset_write.txt") -Encoding utf8
& $Adb -s $Serial shell su -c "CLASSPATH=$ResetJar app_process /system/bin Slot1ImsResetHelper reset-slot1" 2>&1 |
    Out-File -LiteralPath (Join-Path $OutDir "reset_write.txt") -Encoding utf8 -Append
"hostWriteEnd=$((Get-Date).ToString('o'))" | Add-Content -LiteralPath (Join-Path $OutDir "reset_write.txt") -Encoding utf8

$last = 0
foreach ($target in @(2, 5, 15, 30, 60, 90, 120)) {
    Start-Sleep -Seconds ($target - $last)
    Invoke-Probe ("t_{0:D3}s" -f $target) | Out-Null
    if ($target -in @(15, 60, 120)) { Capture-Dumps ("dumps_{0:D3}s" -f $target) }
    $last = $target
}

$pattern = "QCNEJ|qti.cne|DataCallAgent|NativeHalServerCallback|NetworkRequest|DNC-1|DN-[0-9]+-I|ImsResolver|ImsService|ImsPhone|MMTEL|RCS|IWLAN|Epdg|setImsRegistrationState|requestRegistrationChange"
& $Adb -s $Serial shell "logcat -b all -v threadtime -T '$logcatSince' -d | grep -iE '$pattern'" 2>&1 |
    Out-File -LiteralPath (Join-Path $OutDir "observation.txt") -Encoding utf8

"RESET RECOVERY CYCLE COMPLETE. Exactly one ITelephony.resetIms(1) was attempted." |
    Set-Content -LiteralPath (Join-Path $OutDir "COMPLETE.txt") -Encoding ascii
