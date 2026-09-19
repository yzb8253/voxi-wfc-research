param(
    [string]$Device = "192.168.137.134:37667",
    [int]$TargetSubId = 11,
    [int]$TargetSlotId = 1,
    [string]$TargetMccMnc = "23415",
    [int]$ObservationSeconds = 300
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 3.0

$Phase4Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PlatformTools = Split-Path -Parent (Split-Path -Parent $Phase4Dir)
$Adb = Join-Path $PlatformTools "adb.exe"
$CaptureScript = Join-Path $Phase4Dir "phase4_capture_before.ps1"
$WatchScript = Join-Path $Phase4Dir "phase4_watch.ps1"
$OutFile = Join-Path $Phase4Dir "disable_test_output.txt"
$DisableCommand = "cmd phone disable-physical-subscription $TargetSubId"

function Invoke-AdbShell {
    param([Parameter(Mandatory = $true)][string]$Command)
    $result = & $Adb -s $Device shell $Command 2>&1
    return ($result -join "`r`n")
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

Assert-TargetSubscription

Set-Content -Path $OutFile -Value "Phase 4 disable test"
Add-Content -Path $OutFile -Value ("HostStartTime={0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff zzz"))
Add-Content -Path $OutFile -Value ("Device={0}" -f $Device)
Add-Content -Path $OutFile -Value ("TargetSubId={0}" -f $TargetSubId)
Add-Content -Path $OutFile -Value ("TargetSlotId={0}" -f $TargetSlotId)
Add-Content -Path $OutFile -Value ("TargetMccMnc={0}" -f $TargetMccMnc)
Add-Content -Path $OutFile -Value "This script intentionally stops after disable and after-snapshot. It does not run enable-physical-subscription."

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CaptureScript -Device $Device -TargetSubId $TargetSubId -TargetSlotId $TargetSlotId -TargetMccMnc $TargetMccMnc -Label "before"

$watchArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $WatchScript,
    "-Device", $Device,
    "-DurationSeconds", $ObservationSeconds,
    "-IntervalSeconds", "5"
)
$watchProc = Start-Process -FilePath "powershell.exe" -ArgumentList $watchArgs -PassThru
Add-Content -Path $OutFile -Value ("Started watch process pid={0}" -f $watchProc.Id)

Start-Sleep -Seconds 3
Assert-TargetSubscription

Add-Content -Path $OutFile -Value ""
Add-Content -Path $OutFile -Value ("===== EXECUTE DISABLE: adb -s {0} shell {1} =====" -f $Device, $DisableCommand)
$disableOutput = Invoke-AdbShell $DisableCommand
Add-Content -Path $OutFile -Value $disableOutput

Start-Sleep -Seconds 90

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CaptureScript -Device $Device -TargetSubId $TargetSubId -TargetSlotId $TargetSlotId -TargetMccMnc $TargetMccMnc -Label "after_disable" -SkipSafetyGate

Wait-Process -Id $watchProc.Id

Add-Content -Path $OutFile -Value ("HostEndTime={0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff zzz"))
Add-Content -Path $OutFile -Value "Disable test complete. Recovery was not executed."
Write-Host ("Disable test output saved: {0}" -f $OutFile)
