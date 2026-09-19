param(
    [string]$Serial = "192.168.1.25:42319",
    [string]$Adb = "adb",
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "capture")
)

$ErrorActionPreference = "Stop"
$adbArgs = @("-s", $Serial)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

function Invoke-Root([string]$Command) {
    $escaped = $Command.Replace("'", "'\''")
    $result = & $Adb @adbArgs shell "su -c '$escaped'" 2>&1
    return ($result -join "`n")
}

function Protect-Identifiers([string]$Text) {
    $value = $Text
    $value = [regex]::Replace($value, '(?i)(iccId|cardString|mIccId)(\s*[=:]\s*)(?:\[[^\]]*\]|[^,\s}\]]+)', '$1$2[REDACTED]')
    $value = [regex]::Replace($value, '(?i)(mNumber\s*=\s*)(?:\[[^\]]*\]|[^,\s}\]]+)', '$1[REDACTED]')
    $value = [regex]::Replace($value, '(?i)(displayName\s*=\s*)\d{7,15}\b', '$1[REDACTED]')
    $value = [regex]::Replace($value, '(?i)(imei\d*\s*[=:]\s*)[^,\s}\]]+', '$1[REDACTED]')
    $value = [regex]::Replace($value, '(?i)(meid\s*[=:]\s*)[^,\s}\]]+', '$1[REDACTED]')
    $value = [regex]::Replace($value, '\b\d{12,22}\b', '[REDACTED_LONG_NUMBER]')
    $value = [regex]::Replace($value, '(?m)^(<{7}|={7}|>{7})', '[DUMP] $1')
    $value = [regex]::Replace($value, '(?m)[ \t]+$', '')
    return $value
}

function Save-Protected([string]$Name, [string]$Text) {
    Protect-Identifiers $Text | Set-Content -LiteralPath (Join-Path $OutputDirectory $Name) -Encoding utf8
}

function Get-ActiveMapping([string]$Dump, [int]$Mcc, [int]$Mnc) {
    $insideActive = $false
    foreach ($line in ($Dump -split "`r?`n")) {
        if ($line.Trim() -eq "ActiveSubInfoList:") { $insideActive = $true; continue }
        if ($line.Trim() -eq "ActiveSubInfoList in the DB:") { break }
        if (-not $insideActive -or $line -notmatch " mcc=$Mcc mnc=$Mnc ") { continue }
        $match = [regex]::Match($line, '^\s*\{id=([0-9]+) iccId=([^ ]+) simSlotIndex=(-?[0-9]+) carrierId=([0-9]+) displayName=([^ ]+) carrierName=([^ ]+) ')
        if (-not $match.Success) { throw "Unable to parse active mapping for MCC/MNC $Mcc/$Mnc" }
        return [pscustomobject]@{
            SubId = [int]$match.Groups[1].Value
            Iccid = $match.Groups[2].Value
            SlotIndex = [int]$match.Groups[3].Value
            PhoneId = [int]$match.Groups[3].Value
            CarrierId = [int]$match.Groups[4].Value
            DisplayName = $match.Groups[5].Value
            CarrierName = $match.Groups[6].Value
            Mcc = $Mcc
            Mnc = $Mnc
        }
    }
    throw "No active subscription found for MCC/MNC $Mcc/$Mnc"
}

function Get-StringHash([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([Convert]::ToHexString($sha.ComputeHash($bytes))).ToLowerInvariant() }
    finally { $sha.Dispose() }
}

if ((& $Adb @adbArgs get-state) -ne "device") { throw "ADB target is not online: $Serial" }
if ((Invoke-Root "id -u").Trim() -ne "0") { throw "su/root is unavailable" }

$isub = Invoke-Root "dumpsys isub"
$voxi = Get-ActiveMapping $isub 234 15
$ct = Get-ActiveMapping $isub 460 11
$voxiHash = Get-StringHash $voxi.Iccid
$ctHash = Get-StringHash $ct.Iccid

Save-Protected "dumpsys-subscription-isub.txt" $isub
Save-Protected "dumpsys-subscription-service.txt" (Invoke-Root "dumpsys subscription")
Save-Protected "dumpsys-telephony.registry.txt" (Invoke-Root "dumpsys telephony.registry")
Save-Protected "dumpsys-phone.txt" (Invoke-Root "dumpsys phone")
Save-Protected "getprop-radio.txt" (Invoke-Root "getprop | grep -i radio")
Save-Protected "getprop-operator.txt" (Invoke-Root "getprop | grep -Ei 'gsm\.operator|gsm\.sim\.operator|multisim|stack_id|msim\.stackid'")
Save-Protected "service-uim.txt" (Invoke-Root "service list | grep -i uim")
Save-Protected "lshal-radio-uim.txt" (Invoke-Root "lshal 2>/dev/null | grep -Ei 'radio|uim|sim'")
Save-Protected "process-radio-uim.txt" (Invoke-Root "ps -AZ | grep -Ei 'qcril|radio|uim|qmi'")
$qcrildProperties = Invoke-Root "getprop | grep -Ei 'init\.svc.*qcrild|init\.svc_debug_pid.*qcrild'"
Save-Protected "qcrild-init-properties.txt" $qcrildProperties
$primaryPid = [regex]::Match($qcrildProperties, '(?m)^\[init\.svc_debug_pid\.vendor\.qcrild\]: \[([0-9]+)\]$').Groups[1].Value
$targetPid = [regex]::Match($qcrildProperties, '(?m)^\[init\.svc_debug_pid\.vendor\.qcrild2\]: \[([0-9]+)\]$').Groups[1].Value
$qcrildEvidence = @()
foreach ($item in @(@("primary", $primaryPid), @("target", $targetPid))) {
    $role = $item[0]; $pidValue = $item[1]
    if ($pidValue -notmatch '^[0-9]+$') { throw "Unable to resolve $role qcrild PID" }
    $qcrildEvidence += "===role=$role pid=$pidValue==="
    $qcrildEvidence += Invoke-Root "tr '\000' ' ' < /proc/$pidValue/cmdline"
    $qcrildEvidence += Invoke-Root "grep -Ei 'qmi|uim|radio' /proc/$pidValue/maps | sort -u"
    $qcrildEvidence += Invoke-Root "ls -l /proc/$pidValue/fd 2>/dev/null | grep -Ei 'qmi|qrtr|smd|radio|uim|socket'"
}
Save-Protected "qcrild-qmi-channels.txt" ($qcrildEvidence -join "`n")
Save-Protected "logcat-slot-mapping.txt" (Invoke-Root "logcat -d -v threadtime | grep -Ei 'SIM_STATE_CHANGED|SubscriptionInfo|UiccController|UiccSlot|RadioConfig|QMI'")
Save-Protected "wfc-probe.json" (Invoke-Root "CLASSPATH=/data/adb/modules/voxi_wfc_recovery/lib/wfc-probe.jar app_process /system/bin WfcStateProbe read-only-json")

@(
    "captured_at=$((Get-Date).ToString('o'))"
    "serial=$Serial"
    "voxi_subId=$($voxi.SubId)"
    "voxi_slotIndex=$($voxi.SlotIndex)"
    "voxi_phoneId=$($voxi.PhoneId)"
    "voxi_carrierId=$($voxi.CarrierId)"
    "voxi_mccmnc=$($voxi.Mcc)$($voxi.Mnc)"
    "voxi_displayName=$($voxi.DisplayName)"
    "voxi_iccid_sha256=$voxiHash"
    "voxi_radio_hal_instance=IRadio/slot$($voxi.SlotIndex + 1)"
    "voxi_uim_instance=IUim/Uim$($voxi.SlotIndex)"
    "voxi_qmi_stack=$($voxi.SlotIndex)"
    "china_telecom_subId=$($ct.SubId)"
    "china_telecom_slotIndex=$($ct.SlotIndex)"
    "china_telecom_phoneId=$($ct.PhoneId)"
    "china_telecom_carrierId=$($ct.CarrierId)"
    "china_telecom_mccmnc=$($ct.Mcc)$($ct.Mnc)"
    "china_telecom_displayName=$($ct.DisplayName)"
    "china_telecom_iccid_sha256=$ctHash"
    "china_telecom_radio_hal_instance=IRadio/slot$($ct.SlotIndex + 1)"
    "china_telecom_uim_instance=IUim/Uim$($ct.SlotIndex)"
    "china_telecom_qmi_stack=$($ct.SlotIndex)"
    "privacy=raw ICCIDs were held only in process memory and were never written"
) | Set-Content -LiteralPath (Join-Path $OutputDirectory "metadata.txt") -Encoding utf8

Write-Host "Read-only slot mapping captured at $OutputDirectory"
Write-Host "VOXI ICCID SHA-256: $voxiHash"
Write-Host "China Telecom ICCID SHA-256: $ctHash"
