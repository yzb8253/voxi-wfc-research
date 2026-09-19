$ErrorActionPreference = "Stop"

$Adb = Join-Path $PSScriptRoot "..\..\adb.exe"
$Serial = "192.168.137.134:39247"
$OutDir = Join-Path $PSScriptRoot "experiments\cycle1_uicc_true"
$ProbeJar = "/data/local/tmp/wfc-state-probe.jar"
$RecoverJar = "/data/local/tmp/slot1-uicc-recover.jar"
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

$before = Invoke-Probe "t_before_true"
if ($before.subscription.active -or $before.target.mappingGate -or $before.protectedSlot0.mappingGate -ne $true) {
    throw "Expected persistent inactive F8 with protected slot0; true recovery was not executed"
}

Capture-Dumps "dumps_before_true"
$start = Get-Date
$logcatSince = $start.ToString("MM-dd HH:mm:ss.fff", [Globalization.CultureInfo]::InvariantCulture)
"hostWriteStart=$($start.ToString('o'))" | Set-Content -LiteralPath (Join-Path $OutDir "true_write.txt") -Encoding utf8
& $Adb -s $Serial shell su -c "CLASSPATH=$RecoverJar app_process /system/bin Slot1UiccRecoverHelper recover" 2>&1 |
    Out-File -LiteralPath (Join-Path $OutDir "true_write.txt") -Encoding utf8 -Append
"hostWriteEnd=$((Get-Date).ToString('o'))" | Add-Content -LiteralPath (Join-Path $OutDir "true_write.txt") -Encoding utf8

$last = 0
foreach ($target in @(1, 2, 5, 10, 15, 30, 60, 90, 120, 180, 300)) {
    Start-Sleep -Seconds ($target - $last)
    Invoke-Probe ("t_{0:D3}s" -f $target) | Out-Null
    if ($target -in @(15, 60, 120, 300)) { Capture-Dumps ("dumps_{0:D3}s" -f $target) }
    $last = $target
}

$pattern = "QCNEJ|qti.cne|DataCallAgent|NativeHalServerCallback|NetworkRequest|DNC-1|DN-[0-9]+-I|ImsResolver|ImsService|ImsPhone|MMTEL|RCS|IWLAN|Epdg|CarrierConfig|CLEAR_CONFIG|NO_SIM|ESSENTIAL_LOADED|LOADED|Subscription|Uicc|setImsRegistrationState|requestRegistrationChange"
& $Adb -s $Serial shell "logcat -b all -v threadtime -T '$logcatSince' -d | grep -iE '$pattern'" 2>&1 |
    Out-File -LiteralPath (Join-Path $OutDir "observation.txt") -Encoding utf8

"TRUE RECOVERY OBSERVATION COMPLETE. No resetIms was executed." |
    Set-Content -LiteralPath (Join-Path $OutDir "COMPLETE.txt") -Encoding ascii
