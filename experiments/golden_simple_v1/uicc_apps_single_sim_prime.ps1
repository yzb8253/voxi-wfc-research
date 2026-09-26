[CmdletBinding()]
param([string]$Serial='fd0ff892',[int]$IsubTransaction=46)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$ExpectedDevice='cas'
$ExpectedAndroid='13'
$ExpectedBuild='V816.0.4.0.TJJCNXM'
$ExpectedFingerprint='Xiaomi/cas/cas:13/TKQ1.221114.001/V816.0.4.0.TJJCNXM:user/release-keys'

function Quote-Sh([string]$Value){$s=[string][char]39;$d=[string][char]34;$s+$Value.Replace($s,($s+$d+$s+$d+$s))+$s}
function Invoke-Adb([string[]]$Arguments){
    $i=[Diagnostics.ProcessStartInfo]::new();$i.FileName=$Adb;$i.UseShellExecute=$false;$i.CreateNoWindow=$true
    $i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true
    $i.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){'"'+$_.Replace('"','\"')+'"'}else{$_}})-join ' ')
    $p=[Diagnostics.Process]::new();$p.StartInfo=$i;if(-not $p.Start()){throw 'Unable to start adb'}
    $o=$p.StandardOutput.ReadToEnd();$e=$p.StandardError.ReadToEnd();$p.WaitForExit()
    [pscustomobject]@{ExitCode=$p.ExitCode;Text=($o+$e).Trim()}
}
function RootResult([string]$Command){Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)))}
function Root([string]$Command){$r=RootResult $Command;if($r.ExitCode -ne 0){throw "ADB/root command failed: $Command`n$($r.Text)"};$r.Text.Trim()}
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw "UICC_SINGLE_SIM_FAIL: $Message"}}
function Get-SubRow([int]$SubId){$all=Root 'dumpsys isub';$pattern=('\{{id={0}\s' -f $SubId);@($all -split "\r?\n"|Where-Object{$_ -match $pattern})|Select-Object -First 1}
function Assert-Slot0Absent {
    $states=@((Root 'getprop gsm.sim.state').Split(',')|ForEach-Object{$_.Trim().ToUpperInvariant()})
    Require ($states.Count -ge 2 -and $states[0] -eq 'ABSENT') 'physical slot0 is not ABSENT'
    $mapped=@((Root 'dumpsys isub') -split "\r?\n"|Where-Object{$_ -match 'simSlotIndex=0(?:\s|\})'})
    Require ($mapped.Count -eq 0) 'a subscription is unexpectedly mapped to slot0'
}
function Assert-VoxiEnabledEntry {
    $row=Get-SubRow 11
    Require (-not [string]::IsNullOrWhiteSpace($row)) 'VOXI subId11 row missing'
    Require ($row -match 'simSlotIndex=1') 'VOXI subId11 is not mapped to slot1'
    Require ($row -match 'carrierId=28') 'VOXI carrierId changed'
    Require ($row -match 'mcc=234' -and $row -match 'mnc=15') 'VOXI MCC/MNC changed'
    Require ($row -match 'areUiccApplicationsEnabled=true') 'VOXI UICC applications are not enabled at entry'
}

Require (Test-Path -LiteralPath $Adb) "adb.exe missing: $Adb"
$devices=Invoke-Adb @('devices');Require ($devices.Text -match "(?m)^$([regex]::Escape($Serial))\s+device\s*$") 'ADB target offline'
Require ((Root 'id') -match 'uid=0\(root\)') 'root unavailable'
Require ((Root 'getprop ro.product.device') -eq $ExpectedDevice) 'device mismatch'
Require ((Root 'getprop ro.build.version.release') -eq $ExpectedAndroid) 'Android version mismatch'
Require ((Root 'getprop ro.build.version.incremental') -eq $ExpectedBuild) 'ROM build mismatch'
Require ((Root 'getprop ro.build.fingerprint') -eq $ExpectedFingerprint) 'ROM fingerprint mismatch'
Require ((Root 'settings get global airplane_mode_on') -eq '0') 'single-SIM UICC prime must start in airplane-OFF A0'

$sample="{id=1 simSlotIndex=-1 areUiccApplicationsEnabled=true}`n{id=11 simSlotIndex=1 carrierId=28 mcc=234 mnc=15 areUiccApplicationsEnabled=true}"
$pattern11=('\{{id={0}\s' -f 11)
Require (@($sample -split "\r?\n"|Where-Object{$_ -match $pattern11}).Count -eq 1) 'internal subId11 parser self-test failed'
Write-Host 'UICC_SINGLE_SIM_PARSER_SELFTEST=PASS'

Assert-Slot0Absent
Assert-VoxiEnabledEntry
Write-Host 'UICC_SINGLE_SIM_ENTRY_GATE=PASS slot0=ABSENT subId11/slot1/23415/apps=true'
Write-Host ("ISUB_SET_UICC_TRANSACTION={0}" -f $IsubTransaction)

$mustReenable=$false
try {
    $off=RootResult ("service call isub {0} i32 0 i32 11" -f $IsubTransaction)
    Require ($off.ExitCode -eq 0) ("ISub false Binder call failed: {0}" -f $off.Text)
    $mustReenable=$true
    Write-Host ("UICC_APPS_FALSE_CALL={0}" -f $off.Text)

    $f8=$false
    for($i=1;$i -le 30;$i++){
        Start-Sleep -Seconds 1
        Assert-Slot0Absent
        $row=Get-SubRow 11
        if($row -match 'simSlotIndex=-1' -and $row -match 'areUiccApplicationsEnabled=false'){$f8=$true;Write-Host ("UICC_F8_CONFIRMED_AFTER={0}s" -f $i);break}
    }
    Require $f8 'VOXI did not reach verified apps-disabled F8 within 30s'

    $on=RootResult ("service call isub {0} i32 1 i32 11" -f $IsubTransaction)
    Require ($on.ExitCode -eq 0) ("ISub true Binder call failed: {0}" -f $on.Text)
    Write-Host ("UICC_APPS_TRUE_CALL={0}" -f $on.Text)

    $restored=$false
    for($i=1;$i -le 60;$i++){
        Start-Sleep -Seconds 1
        Assert-Slot0Absent
        $row=Get-SubRow 11
        if($row -match 'simSlotIndex=1' -and $row -match 'carrierId=28' -and $row -match 'mcc=234' -and $row -match 'mnc=15' -and $row -match 'areUiccApplicationsEnabled=true'){$restored=$true;Write-Host ("UICC_REINSERT_CONFIRMED_AFTER={0}s" -f $i);break}
    }
    Require $restored 'VOXI did not return to enabled slot1 mapping within 60s'
    $mustReenable=$false
    Assert-Slot0Absent
    Assert-VoxiEnabledEntry
    Write-Host 'UICC_SINGLE_SIM_PRIME=PASS'
    exit 0
}
finally {
    if($mustReenable){
        Write-Host '[UICC GUARD] Sending one emergency TRUE for VOXI subId11.' -ForegroundColor Yellow
        [void](RootResult ("service call isub {0} i32 1 i32 11" -f $IsubTransaction))
    }
}
