param(
    [string]$Device = "192.168.137.134:37667",
    [int]$TargetSubId = 11,
    [int]$TargetSlotId = 1,
    [string]$TargetMccMnc = "23415"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 3.0

$Phase4Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PlatformTools = Split-Path -Parent (Split-Path -Parent $Phase4Dir)
$Adb = Join-Path $PlatformTools "adb.exe"
$BeforeFile = Join-Path $Phase4Dir "before_snapshot.txt"
$OutFile = Join-Path $Phase4Dir "recover_output.txt"
$RecoverCommand = "cmd phone enable-physical-subscription $TargetSubId"

function Invoke-AdbShell {
    param([Parameter(Mandatory = $true)][string]$Command)
    $result = & $Adb -s $Device shell $Command 2>&1
    return ($result -join "`r`n")
}

function Assert-BeforeSnapshot {
    if (-not (Test-Path $BeforeFile)) {
        throw "Safety gate failed: before_snapshot.txt is missing. Run phase4_capture_before.ps1 before recovery."
    }
    $before = Get-Content -Path $BeforeFile -Raw
    if ($before -notmatch "TargetSubId=$TargetSubId" -or
        $before -notmatch "TargetSlotId=$TargetSlotId" -or
        $before -notmatch "TargetMccMnc=$TargetMccMnc") {
        throw "Safety gate failed: before snapshot does not match target subId/slot/MCCMNC."
    }
    if ($before -notmatch "id=$TargetSubId" -or
        $before -notmatch "simSlotIndex=$TargetSlotId" -or
        $before -notmatch "carrierId=28" -or
        $before -notmatch "mcc=234" -or
        $before -notmatch "mnc=15") {
        throw "Safety gate failed: before snapshot does not contain the verified VOXI isub evidence."
    }
}

if (-not (Test-Path $Adb)) {
    throw "adb.exe not found at $Adb"
}

Assert-BeforeSnapshot

Set-Content -Path $OutFile -Value "Phase 4 recovery"
Add-Content -Path $OutFile -Value ("HostStartTime={0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff zzz"))
Add-Content -Path $OutFile -Value ("Device={0}" -f $Device)
Add-Content -Path $OutFile -Value ("TargetSubId={0}" -f $TargetSubId)
Add-Content -Path $OutFile -Value ("RecoverCommand={0}" -f $RecoverCommand)

Add-Content -Path $OutFile -Value ""
Add-Content -Path $OutFile -Value ("===== EXECUTE RECOVERY: adb -s {0} shell {1} =====" -f $Device, $RecoverCommand)
$recoverOutput = Invoke-AdbShell $RecoverCommand
Add-Content -Path $OutFile -Value $recoverOutput

Start-Sleep -Seconds 45

Add-Content -Path $OutFile -Value ""
Add-Content -Path $OutFile -Value "===== post-recovery isub ====="
Add-Content -Path $OutFile -Value (Invoke-AdbShell "dumpsys isub")
Add-Content -Path $OutFile -Value ""
Add-Content -Path $OutFile -Value "===== post-recovery carrier_config filtered ====="
$carrier = Invoke-AdbShell "dumpsys carrier_config"
Add-Content -Path $OutFile -Value ((($carrier -split "\r?\n") | Select-String -Pattern "subId|phoneId=1|slot 1|ESSENTIAL_LOADED|LOADED|ABSENT|CLEAR_CONFIG|VOXI|23415" -Context 2, 4 | Out-String))
Add-Content -Path $OutFile -Value ""
Add-Content -Path $OutFile -Value "===== post-recovery phone/IMS filtered ====="
$phone = Invoke-AdbShell "dumpsys phone"
Add-Content -Path $OutFile -Value ((($phone -split "\r?\n") | Select-String -Pattern "subId|phoneId=1|slot 1|ImsResolver|MMTEL|RCS|IWLAN|registered|registration|AVAILABLE|HOME" -Context 2, 4 | Out-String))

Add-Content -Path $OutFile -Value ("HostEndTime={0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff zzz"))
Write-Host ("Recovery output saved: {0}" -f $OutFile)
