[CmdletBinding()]
param([string]$Serial='fd0ff892')

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$PidFile='/data/local/tmp/x55_holder.pid'

function Quote-Sh([string]$Value) {
  $single=[string][char]39; $double=[string][char]34
  $single + $Value.Replace($single,($single+$double+$single+$double+$single)) + $single
}
function Invoke-Adb([string[]]$Arguments) {
  $info=[Diagnostics.ProcessStartInfo]::new(); $info.FileName=$Adb
  $info.UseShellExecute=$false; $info.CreateNoWindow=$true
  $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
  $info.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){'"'+$_.Replace('"','\"')+'"'}else{$_}}) -join ' ')
  $process=[Diagnostics.Process]::new(); $process.StartInfo=$info
  if(-not $process.Start()){throw 'Unable to start adb'}
  $stdout=$process.StandardOutput.ReadToEnd(); $stderr=$process.StandardError.ReadToEnd(); $process.WaitForExit()
  [pscustomobject]@{ExitCode=$process.ExitCode;Text=$stdout+$stderr}
}
function Root([string]$Command) {
  $result=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)))
  if($result.ExitCode -ne 0){throw "ADB/root command failed: $Command`n$($result.Text)"}
  $result.Text.Trim()
}
function Require([bool]$Condition,[string]$Message) { if(-not $Condition){throw "GATE_FAIL: $Message"} }
function Write-Timing([string]$Name,[Diagnostics.Stopwatch]$Stopwatch) {
  $Stopwatch.Stop()
  Write-Host ("TIMING name={0} ms={1}" -f $Name,$Stopwatch.ElapsedMilliseconds)
}
function Owners {
  $text=Root 'lsof /dev/subsys_esoc0 2>/dev/null || true'
  @($text -split "\r?\n" | Where-Object {$_ -match '/dev/subsys_esoc0'})
}
function QcrildPrimary { Root "ps -A -o PID,PPID,NAME,ARGS | grep -E '^ *[0-9]+ +1 +qcrild +qcrild$'" }
function QcrildSlot2 { Root "ps -A -o PID,PPID,NAME,ARGS | grep -E '^ *[0-9]+ +1 +qcrild +qcrild -c 2$'" }
function FirstPid([string]$Line) { [int](($Line.Trim() -split '\s+')[0]) }

$airplane=Root 'settings get global airplane_mode_on'
$perMgr=Root 'getprop init.svc.vendor.per_mgr'
$pmPid=Root 'getprop init.svc_debug_pid.vendor.per_mgr'
$pmExe=Root "readlink /proc/$pmPid/exe 2>/dev/null"
$holderText=Root "cat $PidFile 2>/dev/null"
Require ($holderText -match '^\d+$') 'holder pidfile missing or non-numeric'
$holderPid=[int]$holderText
$holderCmd=Root "tr '\000' ' ' </proc/$holderPid/cmdline 2>/dev/null"
$holderFd9=Root "readlink /proc/$holderPid/fd/9 2>/dev/null"
$owners=@(Owners)
$vendorX55=Root 'getprop vendor.peripheral.SDX55M.state'
$kernelX55=Root 'cat /sys/bus/msm_subsys/devices/subsys10/state 2>/dev/null'
$crash=Root 'cat /sys/bus/msm_subsys/devices/subsys10/crash_count 2>/dev/null'
$primaryBefore=QcrildPrimary; $slot2Before=QcrildSlot2; $slot2OldPid=FirstPid $slot2Before

Require ($airplane -eq '0') 'airplane mode must remain OFF'
Require ($perMgr -eq 'running' -and $pmPid -match '^\d+$' -and $pmExe -eq '/vendor/bin/pm-service') 'pm-service identity gate failed'
Require ($holderCmd -match 'x55_holder\.pid' -and $holderCmd -match '/dev/subsys_esoc0' -and $holderFd9 -eq '/dev/subsys_esoc0') 'holder identity gate failed'
Require ($owners.Count -eq 1 -and $owners[0] -match "\s$holderPid\s" -and $owners[0] -notmatch "\s$pmPid\s") 'holder must be sole esoc0 owner before release'
Require ($vendorX55 -eq 'OFFLINE' -and $kernelX55 -eq 'ONLINE' -and $crash -match '^\d+$') 'expected pre-release X55 split state missing or crash_count unreadable'

Write-Host "ENTRY_GATE=PASS HOLDER=$holderPid PM=$pmPid QCRILD2=$slot2OldPid"
$holderTermTimer=[Diagnostics.Stopwatch]::StartNew()
[void](Root "kill -TERM $holderPid")
Write-Host 'HOLDER_TERM_COUNT=1'
$gone=$false
for($i=1;$i -le 70;$i++) {
  if((Root "test -d /proc/$holderPid && echo LIVE || echo GONE") -eq 'GONE'){$gone=$true;break}
  Start-Sleep -Seconds 1
}
Require $gone 'holder did not exit after one TERM; no escalation performed'
Write-Timing qcrild2_holder_term_latency $holderTermTimer
$saved=Root "cat $PidFile 2>/dev/null"
if($saved -eq [string]$holderPid){[void](Root "rm -f $PidFile")}

$ownerNoneTimer=[Diagnostics.Stopwatch]::StartNew()
$none=$false; $offlineCrash=$null
for($i=1;$i -le 15;$i++) {
  $now=@(Owners)
  $v=Root 'getprop vendor.peripheral.SDX55M.state'
  $k=Root 'cat /sys/bus/msm_subsys/devices/subsys10/state 2>/dev/null'
  $c=Root 'cat /sys/bus/msm_subsys/devices/subsys10/crash_count 2>/dev/null'
  if($now.Count -eq 0 -and $v -eq 'OFFLINE' -and $k -eq 'OFFLINE' -and $c -match '^\d+$' -and [int]$c -ge [int]$crash){$offlineCrash=[int]$c;$none=$true;break}
  Start-Sleep -Seconds 1
}
Require $none 'post-holder-release owner-NONE/X55-OFFLINE fingerprint not reached; qcrild2 was not restarted'
Write-Timing qcrild2_owner_none_x55_offline_latency $ownerNoneTimer
Require ((QcrildPrimary) -eq $primaryBefore -and (FirstPid (QcrildSlot2)) -eq $slot2OldPid) 'QCRIL identity changed before targeted restart'
Write-Host 'PRE_REACQUIRE_FINGERPRINT=PASS'

$restartTimer=[Diagnostics.Stopwatch]::StartNew()
$script:Qcrild2PidTimingWritten=$false
[void](Root 'setprop ctl.restart vendor.qcrild2')
Write-Host 'QCRILD2_RESTART_COUNT=1'
$reacquired=$false; $slot2NewPid=0
for($i=1;$i -le 15;$i++) {
  Start-Sleep -Seconds 1
  $slot2Now=QcrildSlot2; $slot2NewPid=FirstPid $slot2Now
  if($slot2NewPid -ne $slot2OldPid -and -not $script:Qcrild2PidTimingWritten) {
    Write-Timing qcrild2_restart_pid_change_latency $restartTimer
    $script:Qcrild2PidTimingWritten=$true
    $restartTimer=[Diagnostics.Stopwatch]::StartNew()
  }
  $postOwners=@(Owners)
  $postPm=Root 'getprop init.svc_debug_pid.vendor.per_mgr'
  $postExe=Root "readlink /proc/$postPm/exe 2>/dev/null"
  $postV=Root 'getprop vendor.peripheral.SDX55M.state'
  $postK=Root 'cat /sys/bus/msm_subsys/devices/subsys10/state 2>/dev/null'
  $postC=Root 'cat /sys/bus/msm_subsys/devices/subsys10/crash_count 2>/dev/null'
  if($slot2NewPid -ne $slot2OldPid -and $postOwners.Count -eq 1 -and $postOwners[0] -match "\s$postPm\s" -and $postExe -eq '/vendor/bin/pm-service' -and $postV -eq 'ONLINE' -and $postK -eq 'ONLINE' -and $postC -match '^\d+$' -and $null -ne $offlineCrash -and [int]$postC -eq [int]$offlineCrash){$reacquired=$true;break}
}
Require $reacquired 'qcrild2 restarted but native pm-service did not reacquire cleanly'
if(-not $script:Qcrild2PidTimingWritten) { Write-Timing qcrild2_restart_pid_change_latency $restartTimer }
else { Write-Timing qcrild2_pm_reacquire_x55_online_latency $restartTimer }
Require ((QcrildPrimary) -eq $primaryBefore) 'primary qcrild changed'

Write-Host 'NORMALIZATION=PASS'
Write-Host "QCRILD2_OLD_PID=$slot2OldPid"
Write-Host "QCRILD2_NEW_PID=$slot2NewPid"
Write-Host "PM_SERVICE_PID=$postPm"
Write-Host "POST_OWNER=$($postOwners[0])"
Write-Host "X55=ONLINE CRASH_COUNT=$postC STABLE_FROM_OFFLINE=PASS"
