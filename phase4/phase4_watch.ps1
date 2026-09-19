param(
    [string]$Device = "192.168.137.134:37667",
    [int]$DurationSeconds = 300,
    [int]$IntervalSeconds = 5
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 3.0

$Phase4Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PlatformTools = Split-Path -Parent (Split-Path -Parent $Phase4Dir)
$Adb = Join-Path $PlatformTools "adb.exe"
$OutFile = Join-Path $Phase4Dir "disable_observation.txt"
$KeywordRegex = "subId|sub id|slot 1|slotId=1|phoneId=1|phoneId 1|23415|234 15|VOXI|ABSENT|CLEAR_CONFIG|NO_SIM|NO SIM|ESSENTIAL_LOADED|LOADED|ImsResolver|MMTEL|RCS|IWLAN|WLAN|UICC|Subscription|subscription|CarrierConfig|carrier_config|registered|registration|UNAVAILABLE|AVAILABLE|HOME|ePDG|EPDG|Epdg"
$LogcatSince = Get-Date -Format "MM-dd HH:mm:ss.fff"

function Invoke-AdbShell {
    param([Parameter(Mandatory = $true)][string]$Command)
    $result = & $Adb -s $Device shell $Command 2>&1
    return ($result -join "`r`n")
}

function Add-FilteredBlock {
    param([string]$Title, [string]$Text)
    Add-Content -Path $OutFile -Value ""
    Add-Content -Path $OutFile -Value ("===== {0} =====" -f $Title)
    $filteredText = (($Text -split "\r?\n") | Select-String -Pattern $KeywordRegex -Context 1, 3 | Out-String)
    if ([string]::IsNullOrWhiteSpace($filteredText)) {
        Add-Content -Path $OutFile -Value "[no matching lines]"
    } else {
        Add-Content -Path $OutFile -Value $filteredText
    }
}

if (-not (Test-Path $Adb)) {
    throw "adb.exe not found at $Adb"
}

Set-Content -Path $OutFile -Value "Phase 4 disable observation"
Add-Content -Path $OutFile -Value ("HostStartTime={0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff zzz"))
Add-Content -Path $OutFile -Value ("LogcatSince={0}" -f $LogcatSince)
Add-Content -Path $OutFile -Value ("Device={0}" -f $Device)
Add-Content -Path $OutFile -Value ("DurationSeconds={0}" -f $DurationSeconds)
Add-Content -Path $OutFile -Value ("IntervalSeconds={0}" -f $IntervalSeconds)

$deadline = (Get-Date).AddSeconds($DurationSeconds)
$iteration = 0
while ((Get-Date) -lt $deadline) {
    $iteration++
    Add-Content -Path $OutFile -Value ""
    Add-Content -Path $OutFile -Value ("##### ITERATION {0} HOST {1} #####" -f $iteration, (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff zzz"))

    Add-FilteredBlock "dumpsys isub" (Invoke-AdbShell "dumpsys isub")
    Add-FilteredBlock "dumpsys carrier_config" (Invoke-AdbShell "dumpsys carrier_config")
    Add-FilteredBlock "dumpsys phone" (Invoke-AdbShell "dumpsys phone")
    Add-FilteredBlock "dumpsys telephony.registry" (Invoke-AdbShell "dumpsys telephony.registry")
    Add-FilteredBlock "dumpsys telephony_ims" (Invoke-AdbShell "dumpsys telephony_ims")
    Add-FilteredBlock "dumpsys connectivity" (Invoke-AdbShell "dumpsys connectivity")

    Add-Content -Path $OutFile -Value ""
    Add-Content -Path $OutFile -Value "===== logcat filtered since watch start ====="
    $logcat = & $Adb -s $Device logcat -d -v threadtime -T $LogcatSince 2>&1
    $filteredLogcat = (($logcat -join "`r`n") -split "\r?\n") | Select-String -Pattern $KeywordRegex | Out-String
    if ([string]::IsNullOrWhiteSpace($filteredLogcat)) {
        Add-Content -Path $OutFile -Value "[no matching logcat lines]"
    } else {
        Add-Content -Path $OutFile -Value $filteredLogcat
    }

    Start-Sleep -Seconds $IntervalSeconds
}

Add-Content -Path $OutFile -Value ("HostEndTime={0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff zzz"))
Write-Host ("Observation saved: {0}" -f $OutFile)
