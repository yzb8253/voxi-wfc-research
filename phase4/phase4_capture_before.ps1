param(
    [string]$Device = "192.168.137.134:37667",
    [int]$TargetSubId = 11,
    [int]$TargetSlotId = 1,
    [string]$TargetMccMnc = "23415",
    [string]$Label = "before",
    [switch]$SkipSafetyGate
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 3.0

$Phase4Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PlatformTools = Split-Path -Parent (Split-Path -Parent $Phase4Dir)
$Adb = Join-Path $PlatformTools "adb.exe"
$OutFile = Join-Path $Phase4Dir ("{0}_snapshot.txt" -f $Label)
$KeywordRegex = "subId|sub id|slot 1|slotId=1|phoneId=1|phoneId 1|23415|234 15|VOXI|ABSENT|CLEAR_CONFIG|NO_SIM|NO SIM|ESSENTIAL_LOADED|LOADED|ImsResolver|MMTEL|RCS|IWLAN|WLAN|UICC|Subscription|carrier_config|CarrierConfig|registered|registration|UNAVAILABLE|AVAILABLE|HOME"

function Invoke-AdbShell {
    param([Parameter(Mandatory = $true)][string]$Command)
    $result = & $Adb -s $Device shell $Command 2>&1
    return ($result -join "`r`n")
}

function Write-Section {
    param([string]$Title)
    Add-Content -Path $OutFile -Value ""
    Add-Content -Path $OutFile -Value ("===== {0} =====" -f $Title)
}

function Add-AdbCapture {
    param(
        [string]$Title,
        [string]$Command,
        [switch]$Filtered
    )
    Write-Section $Title
    Add-Content -Path $OutFile -Value ("> adb -s {0} shell {1}" -f $Device, $Command)
    $text = Invoke-AdbShell $Command
    if ($Filtered) {
        $filteredText = (($text -split "\r?\n") | Select-String -Pattern $KeywordRegex -Context 2, 4 | Out-String)
        if ([string]::IsNullOrWhiteSpace($filteredText)) {
            Add-Content -Path $OutFile -Value "[no matching lines]"
        } else {
            Add-Content -Path $OutFile -Value $filteredText
        }
    } else {
        Add-Content -Path $OutFile -Value $text
    }
}

function Assert-TargetSubscription {
    Write-Host "Checking target subscription safety gate..."
    $isub = Invoke-AdbShell "dumpsys isub"
    $registry = Invoke-AdbShell "dumpsys telephony.registry"
    $phone = Invoke-AdbShell "dumpsys phone"
    $simNumeric = Invoke-AdbShell "getprop gsm.sim.operator.numeric"
    $operatorNumeric = Invoke-AdbShell "getprop gsm.operator.numeric"

    $mcc = $TargetMccMnc.Substring(0, 3)
    $mnc = $TargetMccMnc.Substring(3)
    $targetCarrierId = 28
    $activeSectionMatch = [regex]::Match($isub, "(?s)ActiveSubInfoList:\s*(.*?)ActiveSubInfoList in the DB:")
    $activeSection = if ($activeSectionMatch.Success) { $activeSectionMatch.Groups[1].Value } else { "" }
    $activeEntries = [regex]::Matches($activeSection, "\{[^}]*\}") | ForEach-Object { $_.Value }
    $targetActive = $activeEntries | Where-Object { $_ -match "\bid=$TargetSubId\b" } | Select-Object -First 1
    $slotMapPattern = "sSlotIndexToSubId\[$TargetSlotId\]:\s*subIds=.*\[$TargetSubId\]"
    $slotZeroWrongPattern = "sSlotIndexToSubId\[0\]:\s*subIds=.*\[$TargetSubId\]"

    $subIdPass = [bool]$targetActive
    $slotPass = [bool]($targetActive -and ($targetActive -match "\bsimSlotIndex=$TargetSlotId\b")) -or ($isub -match $slotMapPattern)
    $phonePass = ($registry -match "mDefaultPhoneId=$TargetSlotId" -and $registry -match "mDefaultSubId=$TargetSubId") -or
                 ($registry -match "subId=$TargetSubId\s+phoneId=$TargetSlotId") -or
                 ($phone -match "Listener=\{slotId=$TargetSlotId,\s*subId=$TargetSubId,")
    $carrierIdPass = [bool]($targetActive -and ($targetActive -match "\bcarrierId=$targetCarrierId\b"))
    $mccPass = [bool]($targetActive -and ($targetActive -match "\bmcc=$mcc\b"))
    $mncPass = [bool]($targetActive -and ($targetActive -match "\bmnc=$mnc\b"))
    $mccMncPass = $mccPass -and $mncPass
    if (-not $mccMncPass) {
        $mccMncPass = ($simNumeric -match "(^|,)$TargetMccMnc(,|$)") -or ($operatorNumeric -match "(^|,)$TargetMccMnc(,|$)")
    }
    $slot0Safe = -not (($activeEntries | Where-Object { ($_ -match "\bid=$TargetSubId\b") -and ($_ -match "\bsimSlotIndex=0\b") }) -or ($isub -match $slotZeroWrongPattern))

    Write-Host "=== TARGET VERIFICATION ==="
    Write-Host ("subId 11: {0} evidence=isub ActiveSubInfoList" -f $(if ($subIdPass) { "PASS" } else { "FAIL" }))
    Write-Host ("slot 1: {0} evidence=isub simSlotIndex / sSlotIndexToSubId" -f $(if ($slotPass) { "PASS" } else { "FAIL" }))
    Write-Host ("phoneId 1: {0} evidence=telephony.registry / phone ImsStateCallbackController" -f $(if ($phonePass) { "PASS" } else { "FAIL" }))
    Write-Host ("carrierId 28: {0} evidence=isub ActiveSubInfoList" -f $(if ($carrierIdPass) { "PASS" } else { "FAIL" }))
    Write-Host ("MCC 234: {0} evidence=isub ActiveSubInfoList" -f $(if ($mccPass) { "PASS" } else { "FAIL" }))
    Write-Host ("MNC 15: {0} evidence=isub ActiveSubInfoList" -f $(if ($mncPass) { "PASS" } else { "FAIL" }))
    Write-Host ("slot0 != subId11: {0} evidence=isub ActiveSubInfoList / sSlotIndexToSubId" -f $(if ($slot0Safe) { "PASS" } else { "FAIL" }))

    if (-not ($subIdPass -and $slotPass -and $phonePass -and $carrierIdPass -and $mccPass -and $mncPass -and $mccMncPass -and $slot0Safe)) {
        throw "Safety gate failed: target verification did not pass all required checks."
    }
    Write-Host "Safety gate passed: target is locked to VOXI subId 11 on slot/phone 1."
}

if (-not (Test-Path $Adb)) {
    throw "adb.exe not found at $Adb"
}

if ($SkipSafetyGate) {
    Write-Host "Safety gate skipped for read-only post-event capture."
} else {
    Assert-TargetSubscription
}

Set-Content -Path $OutFile -Value ("Phase 4 {0} snapshot" -f $Label)
Add-Content -Path $OutFile -Value ("HostStartTime={0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff zzz"))
Add-Content -Path $OutFile -Value ("Device={0}" -f $Device)
Add-Content -Path $OutFile -Value ("TargetSubId={0}" -f $TargetSubId)
Add-Content -Path $OutFile -Value ("TargetSlotId={0}" -f $TargetSlotId)
Add-Content -Path $OutFile -Value ("TargetMccMnc={0}" -f $TargetMccMnc)

Add-AdbCapture "device time" "date '+%Y-%m-%d %H:%M:%S %Z'"
Add-AdbCapture "active subscription / isub" "dumpsys isub"
Add-AdbCapture "telephony.registry filtered" "dumpsys telephony.registry" -Filtered
Add-AdbCapture "carrier_config filtered" "dumpsys carrier_config" -Filtered
Add-AdbCapture "phone / ImsResolver / MMTEL filtered" "dumpsys phone" -Filtered
Add-AdbCapture "telephony_ims filtered" "dumpsys telephony_ims" -Filtered
Add-AdbCapture "ims filtered" "dumpsys ims" -Filtered
Add-AdbCapture "connectivity IWLAN/IMS filtered" "dumpsys connectivity" -Filtered
Add-AdbCapture "gsm.sim.state" "getprop gsm.sim.state"
Add-AdbCapture "gsm.operator.numeric" "getprop gsm.operator.numeric"
Add-AdbCapture "gsm.sim.operator.numeric" "getprop gsm.sim.operator.numeric"
Add-AdbCapture "gsm.operator.alpha" "getprop gsm.operator.alpha"
Add-AdbCapture "gsm.sim.operator.alpha" "getprop gsm.sim.operator.alpha"

Write-Host ("Snapshot saved: {0}" -f $OutFile)
