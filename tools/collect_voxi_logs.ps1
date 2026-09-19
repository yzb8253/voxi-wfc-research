param(
    [string]$Serial = $env:ANDROID_SERIAL,
    [string]$OutputDirectory = ("voxi-logs-" + (Get-Date -Format "yyyyMMdd-HHmmss")),
    [string]$Adb = "adb"
)

$ErrorActionPreference = "Stop"
$adbArgs = @()
if ($Serial) { $adbArgs += @("-s", $Serial) }

& $Adb @adbArgs get-state | Out-Null
if ($LASTEXITCODE -ne 0) { throw "ADB device is not online" }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

function Save-Adb([string]$Name, [string[]]$Arguments) {
    & $Adb @adbArgs @Arguments 2>&1 | Out-File -LiteralPath (Join-Path $OutputDirectory $Name) -Encoding utf8
}

Save-Adb "device.txt" @("shell", "getprop", "ro.product.model")
Save-Adb "getprop.txt" @("shell", "getprop")
Save-Adb "processes.txt" @("shell", "su", "-c", "ps -A -o USER,PID,PPID,NAME,CMDLINE")
foreach ($service in @("isub", "phone", "telephony.registry", "telephony_ims", "ims", "carrier_config", "connectivity")) {
    Save-Adb "dumpsys-$service.txt" @("shell", "su", "-c", "dumpsys $service")
}
Save-Adb "routes.txt" @("shell", "su", "-c", "ip link; ip route show table all; ip rule; ip xfrm state; ip xfrm policy")
Save-Adb "services.txt" @("shell", "su", "-c", "service list")
Save-Adb "logcat-full.txt" @("shell", "su", "-c", "logcat -d -v threadtime")
Save-Adb "logcat-ims-qcril.txt" @("shell", "su", "-c", "logcat -d -v threadtime | grep -Ei 'ims|iwlan|epdg|wfc|vowifi|qcril|qti.cne|cnd|DSD|QMI'")

Write-Host "Collected read-only VOXI diagnostics: $((Resolve-Path $OutputDirectory).Path)"

