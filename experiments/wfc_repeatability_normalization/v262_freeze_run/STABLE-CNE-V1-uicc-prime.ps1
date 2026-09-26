[CmdletBinding()]
param(
    [string]$Serial='fd0ff892',
    [int]$IsubTransaction=46
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'

$ExpectedDevice='cas'
$ExpectedAndroid='13'
$ExpectedBuild='V816.0.4.0.TJJCNXM'
$ExpectedFingerprint='Xiaomi/cas/cas:13/TKQ1.221114.001/V816.0.4.0.TJJCNXM:user/release-keys'

function Quote-Sh([string]$Value) {
    $single=[string][char]39; $double=[string][char]34
    $single + $Value.Replace($single,($single+$double+$single+$double+$single)) + $single
}
function Invoke-Adb([string[]]$Arguments) {
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$Adb
    $info.UseShellExecute=$false
    $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true
    $info.RedirectStandardError=$true
    $info.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){'"'+$_.Replace('"','\"')+'"'}else{$_}}) -join ' ')
    $process=[Diagnostics.Process]::new(); $process.StartInfo=$info
    if(-not $process.Start()){throw 'Unable to start adb'}
    $stdout=$process.StandardOutput.ReadToEnd()
    $stderr=$process.StandardError.ReadToEnd()
    $process.WaitForExit()
    [pscustomobject]@{ExitCode=$process.ExitCode;Text=($stdout+$stderr).Trim()}
}
function RootResult([string]$Command) {
    Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)))
}
function Root([string]$Command) {
    $r=RootResult $Command
    if($r.ExitCode -ne 0){throw "ADB/root command failed: $Command`n$($r.Text)"}
    $r.Text.Trim()
}
function Require([bool]$Condition,[string]$Message) {
    if(-not $Condition){throw "UICC_DEEP_FAIL: $Message"}
}
function Get-SubRow([int]$SubId) {
    $all=Root 'dumpsys isub'
    $pattern = ('\{{id={0}\s' -f $SubId)
    @($all -split "\r?\n" | Where-Object { $_ -match $pattern }) | Select-Object -First 1
}
function Assert-Slot0 {
    $row=Get-SubRow 1
    Require (-not [string]::IsNullOrWhiteSpace($row)) 'protected subId1 row missing'
    Require ($row -match 'simSlotIndex=0') 'protected subId1 is no longer mapped to slot0'
    Require ($row -match 'mcc=460' -and $row -match 'mnc=11') 'protected subId1 MCC/MNC changed'
    Require ($row -match 'areUiccApplicationsEnabled=true') 'protected subId1 UICC applications are not enabled'
}
function Assert-VoxiEnabledEntry {
    $row=Get-SubRow 11
    Require (-not [string]::IsNullOrWhiteSpace($row)) 'VOXI subId11 row missing'
    Require ($row -match 'simSlotIndex=1') 'VOXI subId11 is not mapped to slot1'
    Require ($row -match 'carrierId=28') 'VOXI carrierId changed'
    Require ($row -match 'mcc=234' -and $row -match 'mnc=15') 'VOXI MCC/MNC changed'
    Require ($row -match 'areUiccApplicationsEnabled=true') 'VOXI UICC applications are not enabled at entry'
}

Require (Test-Path -LiteralPath $Adb) ("adb.exe missing: {0}" -f $Adb)
$devices=Invoke-Adb @('devices')
Require ($devices.Text -match "(?m)^$([regex]::Escape($Serial))\s+device\s*$") 'ADB target offline'
Require ((Root 'id') -match 'uid=0\(root\)') 'root unavailable'

Require ((Root 'getprop ro.product.device') -eq $ExpectedDevice) 'device mismatch'
Require ((Root 'getprop ro.build.version.release') -eq $ExpectedAndroid) 'Android version mismatch'
Require ((Root 'getprop ro.build.version.incremental') -eq $ExpectedBuild) 'ROM build mismatch'
Require ((Root 'getprop ro.build.fingerprint') -eq $ExpectedFingerprint) 'ROM fingerprint mismatch'
Require ((Root 'settings get global airplane_mode_on') -eq '1') 'STABLE_CNE_V1 UICC prime must start in airplane-ON recovery state'

# Pure parser self-test: catches regex/formatting mistakes before any telephony write.
$sampleSub1 = '{id=1 iccId=x simSlotIndex=0 carrierId=2237 mcc=460 mnc=11 areUiccApplicationsEnabled=true}'
$sampleSub11 = '{id=11 iccId=x simSlotIndex=1 carrierId=28 mcc=234 mnc=15 areUiccApplicationsEnabled=true}'
$sampleDump = $sampleSub1 + [Environment]::NewLine + $sampleSub11
$pattern1 = ('\{{id={0}\s' -f 1)
$pattern11 = ('\{{id={0}\s' -f 11)
Require (@($sampleDump -split "\r?\n" | Where-Object { $_ -match $pattern1 }).Count -eq 1) 'internal subId1 parser self-test failed'
Require (@($sampleDump -split "\r?\n" | Where-Object { $_ -match $pattern11 }).Count -eq 1) 'internal subId11 parser self-test failed'
Write-Host 'UICC_PARSER_SELFTEST=PASS'

Assert-Slot0
Assert-VoxiEnabledEntry

Write-Host 'UICC_DEEP_ENTRY_GATE=PASS subId11/slot1 + protected subId1/slot0'
Write-Host ("ISUB_SET_UICC_TRANSACTION={0}" -f $IsubTransaction)

$mustReenable=$false
$writeCount=0
try {
    Write-Host 'UICC_PHONE_WRITE=UICC_APPS_FALSE_SUB11'
    $writeCount++
    $off=RootResult ("service call isub {0} i32 0 i32 11" -f $IsubTransaction)
    Require ($off.ExitCode -eq 0) ("ISub false Binder call failed: {0}" -f $off.Text)
    $mustReenable=$true
    Write-Host ("UICC_APPS_FALSE_CALL={0}" -f $off.Text)

    $f8=$false
    for($i=1;$i -le 30;$i++) {
        Start-Sleep -Seconds 1
        Assert-Slot0
        $row=Get-SubRow 11
        if($row -match 'simSlotIndex=-1' -and $row -match 'areUiccApplicationsEnabled=false') {
            $f8=$true
            Write-Host ("UICC_F8_CONFIRMED_AFTER={0}s" -f $i)
            break
        }
    }
    Require $f8 'VOXI did not reach verified apps-disabled F8 within 30s'

    Write-Host ("UICC_TRUE_HOST_EPOCH_MS={0}" -f [DateTimeOffset]::Now.ToUnixTimeMilliseconds())
    Write-Host 'UICC_PHONE_WRITE=UICC_APPS_TRUE_SUB11'
    $writeCount++
    $on=RootResult ("service call isub {0} i32 1 i32 11" -f $IsubTransaction)
    Require ($on.ExitCode -eq 0) ("ISub true Binder call failed: {0}" -f $on.Text)
    Write-Host ("UICC_APPS_TRUE_CALL={0}" -f $on.Text)

    $restored=$false
    for($i=1;$i -le 60;$i++) {
        Start-Sleep -Seconds 1
        Assert-Slot0
        $row=Get-SubRow 11
        if($row -match 'simSlotIndex=1' -and
           $row -match 'carrierId=28' -and
           $row -match 'mcc=234' -and
           $row -match 'mnc=15' -and
           $row -match 'areUiccApplicationsEnabled=true') {
            $restored=$true
            Write-Host ("UICC_REINSERT_CONFIRMED_AFTER={0}s" -f $i)
            break
        }
    }
    Require $restored 'VOXI did not return to enabled slot1 mapping within 60s'
    $mustReenable=$false

    Assert-Slot0
    Assert-VoxiEnabledEntry
    Write-Host 'UICC_DEEP_FALLBACK=PASS'
    exit 0
}
finally {
    if($mustReenable) {
        Write-Host '[UICC GUARD] Sending one emergency TRUE for VOXI subId11.' -ForegroundColor Yellow
        Write-Host 'UICC_PHONE_WRITE=UICC_APPS_TRUE_SUB11_ROLLBACK'
        $writeCount++
        [void](RootResult ("service call isub {0} i32 1 i32 11" -f $IsubTransaction))
    }
    Write-Host ("UICC_PHONE_WRITE_COUNT={0}" -f $writeCount)
}
