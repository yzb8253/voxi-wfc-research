$ErrorActionPreference = "Stop"

$Adb = Join-Path $PSScriptRoot "..\..\adb.exe"
$Jar = "/data/local/tmp/wfc-state-probe.jar"

$deviceLines = & $Adb devices
$serials = @($deviceLines | ForEach-Object {
    if ($_ -match '^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+)\s+device$') { $Matches[1] }
})

if ($serials.Count -ne 1) {
    throw "Expected exactly one concrete TCP ADB device, found $($serials.Count): $($serials -join ', ')"
}

$serial = $serials[0]
& $Adb -s $serial shell su -c "CLASSPATH=$Jar app_process /system/bin WfcStateProbe read-only-json"
