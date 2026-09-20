[CmdletBinding()]
param(
    [string]$Serial,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "captures")
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-AdbPath {
    $command = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    $candidate = Join-Path $PSScriptRoot "..\..\..\..\..\adb.exe"
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return (Resolve-Path -LiteralPath $candidate).Path
    }

    throw "adb.exe was not found in PATH or the platform-tools parent directory."
}

function Invoke-AdbCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    [void]$script:Report.AppendLine("")
    [void]$script:Report.AppendLine("===== $Title =====")
    [void]$script:Report.AppendLine(("HOST_TIME={0}" -f [DateTimeOffset]::Now.ToString("o")))

    $output = & $script:AdbPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($null -ne $output) {
        foreach ($line in $output) {
            [void]$script:Report.AppendLine([string]$line)
        }
    }
    [void]$script:Report.AppendLine("ADB_EXIT_CODE=$exitCode")

    return $exitCode
}

$script:AdbPath = Resolve-AdbPath
$deviceLines = & $script:AdbPath devices
if ($LASTEXITCODE -ne 0) {
    throw "adb devices failed."
}

$onlineSerials = @(
    $deviceLines |
        ForEach-Object {
            if ($_ -match '^([^\s]+)\s+device(?:\s|$)') {
                $Matches[1]
            }
        }
)

if ([string]::IsNullOrWhiteSpace($Serial)) {
    if ($onlineSerials.Count -ne 1) {
        throw "Expected exactly one online ADB device; found $($onlineSerials.Count). Specify -Serial only after reviewing adb devices."
    }
    $Serial = $onlineSerials[0]
}
elseif ($onlineSerials -notcontains $Serial) {
    throw "Requested serial '$Serial' is not an online ADB device."
}

$rootIdentity = (& $script:AdbPath -s $Serial shell su -c id 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $rootIdentity -notmatch 'uid=0\(root\)') {
    throw "Root identity gate failed: $rootIdentity"
}

$timestamp = [DateTimeOffset]::Now.ToString("yyyyMMdd_HHmmss_fffzzz").Replace(":", "")
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputPath = Join-Path $OutputDirectory "native_qns_snapshot_$timestamp.txt"
$script:Report = [System.Text.StringBuilder]::new()

[void]$script:Report.AppendLine("VOXI NATIVE DSD/QNS SNAPSHOT")
[void]$script:Report.AppendLine("CAPTURE_VERSION=1")
[void]$script:Report.AppendLine("HOST_TIMESTAMP=$([DateTimeOffset]::Now.ToString('o'))")
[void]$script:Report.AppendLine("ADB_SERIAL=$Serial")
[void]$script:Report.AppendLine("ROOT_IDENTITY=$rootIdentity")
[void]$script:Report.AppendLine("FIXED_IIWLAN_INSTANCE=vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot2")
[void]$script:Report.AppendLine("PHONE_WRITE_OPERATIONS=0")
[void]$script:Report.AppendLine("SET_RESPONSE_FUNCTIONS_CALLED=NO")
[void]$script:Report.AppendLine("GET_ALL_QUALIFIED_NETWORKS_CALLED=NO")

[void](Invoke-AdbCapture "ADB DEVICE IDENTITY" @(
    "-s", $Serial, "shell", "sh", "-c",
    "date -Ins; getprop ro.product.manufacturer; getprop ro.product.model; getprop ro.product.device; getprop ro.build.fingerprint"
))

[void](Invoke-AdbCapture "FIXED SLOT2 IIWLAN SERVICE INVENTORY" @(
    "-s", $Serial, "shell", "su", "-c",
    "lshal list -ipc 2>/dev/null | grep -E 'data.iwlan|IIWlan'"
))

[void](Invoke-AdbCapture "FIXED SLOT2 IBASE DEBUG NATIVE CACHE" @(
    "-s", $Serial, "shell", "su", "-c",
    "lshal debug vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot2"
))

[void](Invoke-AdbCapture "DIRECT IMS WFC HEALTH" @(
    "-s", $Serial, "shell", "env",
    "CLASSPATH=/data/local/tmp/wfc-state-probe.jar",
    "app_process", "/system/bin", "WfcStateProbe", "read-only-json"
))

[void](Invoke-AdbCapture "TELEPHONY REGISTRY" @(
    "-s", $Serial, "shell", "su", "-c", "dumpsys telephony.registry"
))

[void](Invoke-AdbCapture "PHONE ANM DNC STATE" @(
    "-s", $Serial, "shell", "su", "-c", "dumpsys phone"
))

[void](Invoke-AdbCapture "TELEPHONY IMS" @(
    "-s", $Serial, "shell", "su", "-c", "dumpsys telephony_ims"
))

[void](Invoke-AdbCapture "CONNECTIVITY AND CNE REQUESTS" @(
    "-s", $Serial, "shell", "su", "-c", "dumpsys connectivity"
))

[void](Invoke-AdbCapture "NETWORK LINKS ROUTES AND RULES" @(
    "-s", $Serial, "shell", "su", "-c",
    "ip -details link show wlan0 2>&1; ip -details link show tun0 2>&1; ip route show table all; ip rule show"
))

[void](Invoke-AdbCapture "EPDG UDP4500 AND XFRM" @(
    "-s", $Serial, "shell", "su", "-c",
    "ss -H -uapn 2>/dev/null | grep -E '(:|\\])4500([[:space:]]|$)' || true; echo ---XFRM_STATE---; ip xfrm state 2>&1 || true; echo ---XFRM_POLICY---; ip xfrm policy 2>&1 || true; exit 0"
))

[void](Invoke-AdbCapture "RELEVANT PROCESS IDENTITY" @(
    "-s", $Serial, "shell", "su", "-c",
    "ps -A -o USER,PID,PPID,NAME,ARGS 2>/dev/null | grep -E 'qcrild|qtidataservices|vendor.cnd|imsdatadaemon|imsqmidaemon|org.codeaurora.ims'"
))

[void](Invoke-AdbCapture "RECENT DSD QNS ANM DNC LOGS" @(
    "-s", $Serial, "shell", "su", "-c",
    "logcat -d -b all -v threadtime -t 30000 2>/dev/null | grep -Ei 'NetworkAvailabilityHandler|DsdSystemStatus|IntentToChangeApn|qualifiedNetworks|ANM-1|AccessNetworksManager-1|DNC-1|qti.cne|IWLAN|ePDG|XFRM|4500|ImsResolver|MmTel'"
))

[void]$script:Report.AppendLine("")
[void]$script:Report.AppendLine("===== CAPTURE END =====")
[void]$script:Report.AppendLine("HOST_TIMESTAMP=$([DateTimeOffset]::Now.ToString('o'))")
[void]$script:Report.AppendLine("PHONE_WRITE_OPERATIONS=0")

[System.IO.File]::WriteAllText(
    $outputPath,
    $script:Report.ToString(),
    [System.Text.UTF8Encoding]::new($false)
)

Write-Output $outputPath
