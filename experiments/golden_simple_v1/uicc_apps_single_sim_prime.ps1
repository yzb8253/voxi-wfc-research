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
. (Join-Path $PSScriptRoot 'uicc_isub_section_observer.ps1')

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
function Get-LiveObserver {
    $isub=Root 'dumpsys isub'
    $simState=Root 'getprop gsm.sim.state'
    Get-IsubSectionObserver -IsubText $isub -SimState $simState -SubId 11
}
function Assert-SafeObserver([object]$Observer,[string]$ExpectedState) {
    Require ([bool]$Observer.Valid) ("isub section observer invalid: {0}" -f $Observer.Reason)
    Require ([bool]$Observer.Slot0Absent -and -not [bool]$Observer.Slot0Mapped) 'physical slot0 is not safely ABSENT/unmapped'
    $state=Get-IsubObserverState $Observer
    if($state -eq 'CONFLICT'){throw 'UICC_SINGLE_SIM_FAIL: F8_OBSERVER_CONFLICT DB and AllSubInfoList disagree'}
    Require ($state -eq $ExpectedState) ("observer expected {0}, got {1}: {2}" -f $ExpectedState,$state,(Format-IsubObserver $Observer))
}

Require (Test-Path -LiteralPath $Adb) "adb.exe missing: $Adb"
$devices=Invoke-Adb @('devices');Require ($devices.Text -match "(?m)^$([regex]::Escape($Serial))\s+device\s*$") 'ADB target offline'
Require ((Root 'id') -match 'uid=0\(root\)') 'root unavailable'
Require ((Root 'getprop ro.product.device') -eq $ExpectedDevice) 'device mismatch'
Require ((Root 'getprop ro.build.version.release') -eq $ExpectedAndroid) 'Android version mismatch'
Require ((Root 'getprop ro.build.version.incremental') -eq $ExpectedBuild) 'ROM build mismatch'
Require ((Root 'getprop ro.build.fingerprint') -eq $ExpectedFingerprint) 'ROM fingerprint mismatch'
Require ((Root 'settings get global airplane_mode_on') -eq '0') 'single-SIM UICC prime must start in airplane-OFF A0'

$entryObserver=Get-LiveObserver
Assert-SafeObserver $entryObserver 'RESTORED'
Write-Host 'UICC_SINGLE_SIM_ENTRY_GATE=PASS slot0=ABSENT subId11/slot1/23415/apps=true'
Write-Host ("ISUB_SET_UICC_TRANSACTION={0}" -f $IsubTransaction)

$mustReenable=$false
try {
    $off=RootResult ("service call isub {0} i32 0 i32 11" -f $IsubTransaction)
    Require ($off.ExitCode -eq 0) ("ISub false Binder call failed: {0}" -f $off.Text)
    $mustReenable=$true
    Write-Host ("UICC_APPS_FALSE_CALL={0}" -f $off.Text)

    $f8=$false;$poll=0;$last='';$heartbeat=-1;$deadline=[Diagnostics.Stopwatch]::StartNew()
    while($deadline.Elapsed.TotalSeconds -lt 30){
        $poll++;$observer=Get-LiveObserver
        Require ([bool]$observer.Valid) ("isub section observer invalid: {0}" -f $observer.Reason)
        Require ([bool]$observer.Slot0Absent -and -not [bool]$observer.Slot0Mapped) 'physical slot0 is not safely ABSENT/unmapped'
        $state=Get-IsubObserverState $observer;$formatted=Format-IsubObserver $observer;$beat=[int][Math]::Floor($deadline.Elapsed.TotalSeconds/5)
        if($formatted -cne $last -or $beat -gt $heartbeat){Write-Host ("F8_POLL={0} elapsed_ms={1} {2}" -f $poll,$deadline.ElapsedMilliseconds,$formatted);$last=$formatted;$heartbeat=$beat}
        if($state -eq 'CONFLICT'){Write-Host 'F8_OBSERVER_CONFLICT';throw 'UICC_SINGLE_SIM_FAIL: F8_OBSERVER_CONFLICT DB and AllSubInfoList disagree'}
        if($state -eq 'F8'){$f8=$true;Write-Host ("UICC_F8_CONFIRMED_AFTER_MS={0}" -f $deadline.ElapsedMilliseconds);Write-Host ("UICC_F8_CONFIRMED_AFTER={0}s" -f [Math]::Round($deadline.Elapsed.TotalSeconds,3));break}
        Start-Sleep -Milliseconds 500
    }
    Require $f8 'VOXI did not reach verified apps-disabled F8 within 30s'

    $on=RootResult ("service call isub {0} i32 1 i32 11" -f $IsubTransaction)
    Require ($on.ExitCode -eq 0) ("ISub true Binder call failed: {0}" -f $on.Text)
    Write-Host ("UICC_APPS_TRUE_CALL={0}" -f $on.Text)

    $restored=$false;$poll=0;$last='';$heartbeat=-1;$deadline=[Diagnostics.Stopwatch]::StartNew()
    while($deadline.Elapsed.TotalSeconds -lt 60){
        $poll++;$observer=Get-LiveObserver
        Require ([bool]$observer.Valid) ("isub section observer invalid: {0}" -f $observer.Reason)
        Require ([bool]$observer.Slot0Absent -and -not [bool]$observer.Slot0Mapped) 'physical slot0 is not safely ABSENT/unmapped'
        $state=Get-IsubObserverState $observer;$formatted=Format-IsubObserver $observer;$beat=[int][Math]::Floor($deadline.Elapsed.TotalSeconds/5)
        if($formatted -cne $last -or $beat -gt $heartbeat){Write-Host ("RESTORE_POLL={0} elapsed_ms={1} {2}" -f $poll,$deadline.ElapsedMilliseconds,$formatted);$last=$formatted;$heartbeat=$beat}
        if($state -eq 'CONFLICT'){Write-Host 'RESTORE_OBSERVER_CONFLICT';throw 'UICC_SINGLE_SIM_FAIL: RESTORE_OBSERVER_CONFLICT DB and AllSubInfoList disagree'}
        if($state -eq 'RESTORED'){$restored=$true;Write-Host ("UICC_REINSERT_CONFIRMED_AFTER_MS={0}" -f $deadline.ElapsedMilliseconds);Write-Host ("UICC_REINSERT_CONFIRMED_AFTER={0}s" -f [Math]::Round($deadline.Elapsed.TotalSeconds,3));break}
        Start-Sleep -Milliseconds 500
    }
    Require $restored 'VOXI did not return to enabled slot1 mapping within 60s'
    $mustReenable=$false
    Assert-SafeObserver (Get-LiveObserver) 'RESTORED'
    Write-Host 'UICC_SINGLE_SIM_PRIME=PASS'
    exit 0
}
finally {
    if($mustReenable){
        Write-Host '[UICC GUARD] Sending one emergency TRUE for VOXI subId11.' -ForegroundColor Yellow
        [void](RootResult ("service call isub {0} i32 1 i32 11" -f $IsubTransaction))
    }
}
