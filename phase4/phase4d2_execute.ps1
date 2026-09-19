$ErrorActionPreference = "Stop"

$Adb = ".\adb.exe"
$Serial = "192.168.137.134:37667"
$OutDir = "voxi_wfc_research\phase4"

$Before = Join-Path $OutDir "phase4d2_before.txt"
$After90 = Join-Path $OutDir "phase4d2_after_90s.txt"
$After300 = Join-Path $OutDir "phase4d2_after_300s.txt"
$Observation = Join-Path $OutDir "phase4d2_observation.txt"
$HelperOut = Join-Path $OutDir "phase4d2_helper_output.txt"

function Add-Section {
    param([string]$Path, [string]$Title)
    Add-Content -Path $Path -Encoding UTF8 -Value ""
    Add-Content -Path $Path -Encoding UTF8 -Value "===== $Title ====="
    Add-Content -Path $Path -Encoding UTF8 -Value ("host_time=" + (Get-Date).ToString("o"))
}

function Add-AdbShell {
    param([string]$Path, [string]$Title, [string]$ShellCommand)
    Add-Section -Path $Path -Title $Title
    Add-Content -Path $Path -Encoding UTF8 -Value ("> adb -s $Serial shell $ShellCommand")
    & $Adb -s $Serial shell $ShellCommand 2>&1 | Out-File -FilePath $Path -Encoding UTF8 -Append
}

function Capture-State {
    param([string]$Path, [string]$Label)
    Set-Content -Path $Path -Encoding UTF8 -Value ("PHASE 4D-2 SNAPSHOT: $Label")
    Add-Content -Path $Path -Encoding UTF8 -Value ("host_time=" + (Get-Date).ToString("o"))
    Add-AdbShell -Path $Path -Title "dumpsys isub" -ShellCommand "dumpsys isub"
    Add-AdbShell -Path $Path -Title "dumpsys telephony.registry" -ShellCommand "dumpsys telephony.registry"
    Add-AdbShell -Path $Path -Title "dumpsys phone" -ShellCommand "dumpsys phone"
    Add-AdbShell -Path $Path -Title "dumpsys carrier_config" -ShellCommand "dumpsys carrier_config"
    Add-AdbShell -Path $Path -Title "dumpsys telephony_ims" -ShellCommand "dumpsys telephony_ims"
    Add-AdbShell -Path $Path -Title "dumpsys connectivity" -ShellCommand "dumpsys connectivity"
    Add-AdbShell -Path $Path -Title "related getprop" -ShellCommand "getprop | grep -iE 'gsm|ril|ims|iwlan|radio|sim|carrier|telephony'"
}

Capture-State -Path $Before -Label "BEFORE DISABLE"

$Start = Get-Date
$LogcatSince = $Start.ToString("MM-dd HH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
Set-Content -Path $Observation -Encoding UTF8 -Value "PHASE 4D-2 OBSERVATION"
Add-Content -Path $Observation -Encoding UTF8 -Value ("host_observation_start=" + $Start.ToString("o"))
Add-Content -Path $Observation -Encoding UTF8 -Value ("logcat_since=" + $LogcatSince)

Set-Content -Path $HelperOut -Encoding UTF8 -Value "PHASE 4D-2 HELPER OUTPUT"
Add-Content -Path $HelperOut -Encoding UTF8 -Value ("host_call_start=" + (Get-Date).ToString("o"))
& $Adb -s $Serial shell su -c "CLASSPATH=/data/local/tmp/phase4-uicc-helper.jar app_process /system/bin Phase4UiccHelper disable" 2>&1 |
    Tee-Object -FilePath $HelperOut -Append
Add-Content -Path $HelperOut -Encoding UTF8 -Value ("host_call_end=" + (Get-Date).ToString("o"))

Start-Sleep -Seconds 90
Capture-State -Path $After90 -Label "AFTER 90S"

$Elapsed = (New-TimeSpan -Start $Start -End (Get-Date)).TotalSeconds
$Remaining = [Math]::Max(0, 300 - [int][Math]::Floor($Elapsed))
if ($Remaining -gt 0) {
    Start-Sleep -Seconds $Remaining
}

Capture-State -Path $After300 -Label "AFTER 300S"

Add-Section -Path $Observation -Title "filtered logcat from Phase 4D-2 start"
$Pattern = "QtiSubscriptionController|SubscriptionController|QtiUiccCardProvisioner|UiccController|UiccProfile|SubscriptionInfoUpdater|CarrierConfigLoader|ImsResolver|ImsServiceController|ImsPhone|IWLAN|Iwlan|ePDG|Epdg|MMTEL|MmTel|RCS|UICC|ABSENT|NOT_READY|CLEAR_CONFIG|NO_SIM|LOADED|UNAVAILABLE|unregister|deactivate|activate|subId|slot 1|phoneId 1"
& $Adb -s $Serial shell "logcat -v threadtime -T '$LogcatSince' -d | grep -iE '$Pattern'" 2>&1 |
    Out-File -FilePath $Observation -Encoding UTF8 -Append

Add-Content -Path $Observation -Encoding UTF8 -Value ""
Add-Content -Path $Observation -Encoding UTF8 -Value ("host_observation_end=" + (Get-Date).ToString("o"))
