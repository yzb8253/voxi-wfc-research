[CmdletBinding()]
param(
  [string]$Serial='fd0ff892',
  [switch]$QuickFallback
)

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
  $info=[Diagnostics.ProcessStartInfo]::new()
  $info.FileName=$Adb; $info.UseShellExecute=$false; $info.CreateNoWindow=$true
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
function Owners {
  $text=Root 'lsof /dev/subsys_esoc0 2>/dev/null'
  @($text -split "\r?\n" | Where-Object {$_ -match '/dev/subsys_esoc0'})
}

$airplane=Root 'settings get global airplane_mode_on'
$perMgr=Root 'getprop init.svc.vendor.per_mgr'
$holderText=Root "cat $PidFile 2>/dev/null"
Require ($holderText -match '^\d+$') 'holder pidfile is missing or non-numeric'
$holderPid=[int]$holderText
$holderCmd=Root "tr '\000' ' ' </proc/$holderPid/cmdline 2>/dev/null"
$holderFd9=Root "readlink /proc/$holderPid/fd/9 2>/dev/null"
$x55=Root 'getprop vendor.peripheral.SDX55M.state'
$kernelX55=Root 'cat /sys/bus/msm_subsys/devices/subsys10/state 2>/dev/null'
$crash=Root 'cat /sys/bus/msm_subsys/devices/subsys10/crash_count 2>/dev/null'
$qcrild=Root "ps -A -o PID,PPID,NAME,ARGS | grep -E '^ *[0-9]+ +1 +qcrild +qcrild$'"
$qcrild2=Root "ps -A -o PID,PPID,NAME,ARGS | grep -E '^ *[0-9]+ +1 +qcrild +qcrild -c 2$'"
$preOwners=@(Owners)

Require ($airplane -eq '0') 'airplane mode must be OFF for A1 normalization'
Require ($perMgr -eq 'stopped' -or $perMgr -eq 'running') 'vendor.per_mgr must be stopped or in the known started-without-owner resume state'
Require ($holderCmd -match 'x55_holder\.pid' -and $holderCmd -match '/dev/subsys_esoc0') 'holder cmdline mismatch'
Require ($holderFd9 -eq '/dev/subsys_esoc0') 'holder fd9 mismatch'
Require ($preOwners.Count -eq 1 -and $preOwners[0] -match "\s$holderPid\s" -and $preOwners[0] -match '^sh\s') 'holder is not the sole esoc0 owner'
Require ($kernelX55 -eq 'ONLINE' -and $crash -match '^\d+$') 'kernel X55/crash-count readability gate failed'
if($perMgr -eq 'stopped'){Require ($x55 -eq 'ONLINE') 'pre-start vendor X55 state must be ONLINE'}

Write-Host 'ENTRY_GATE=PASS'
Write-Host "HOLDER_PID=$holderPid"
Write-Host "PRE_OWNER=$($preOwners[0])"
Write-Host "PRE_QCRILD=$qcrild"
Write-Host "PRE_QCRILD2=$qcrild2"

$startCount=0; $restartCount=0
if($perMgr -eq 'stopped') {
  [void](Root 'setprop ctl.start vendor.per_mgr')
  $startCount=1
} else {
  Write-Host 'RESUME_STATE=PER_MGR_RUNNING_WITHOUT_OWNERSHIP'
}
$pmPid=''; $dual=$false
$dualProbeCount = if($QuickFallback){3}else{20}
for($i=1;$i -le $dualProbeCount;$i++) {
  Start-Sleep -Seconds 1
  $state=Root 'getprop init.svc.vendor.per_mgr'
  $servicePid=Root 'getprop init.svc_debug_pid.vendor.per_mgr'
  $now=@(Owners)
  if($state -eq 'running' -and $servicePid -match '^\d+$' -and $now.Count -eq 2 -and ($now -join "`n") -match "\s$holderPid\s" -and ($now -join "`n") -match "\s$servicePid\s") {
    $exe=Root "readlink /proc/$servicePid/exe 2>/dev/null"
    if($exe -eq '/vendor/bin/pm-service'){$pmPid=$servicePid;$dual=$true;break}
  }
}
if(-not $dual) {
  [void](Root 'setprop ctl.restart vendor.per_mgr')
  $restartCount=1
  for($i=1;$i -le $dualProbeCount;$i++) {
    Start-Sleep -Seconds 1
    $state=Root 'getprop init.svc.vendor.per_mgr'
    $servicePid=Root 'getprop init.svc_debug_pid.vendor.per_mgr'
    $now=@(Owners)
    if($state -eq 'running' -and $servicePid -match '^\d+$' -and $now.Count -eq 2 -and ($now -join "`n") -match "\s$holderPid\s" -and ($now -join "`n") -match "\s$servicePid\s") {
      $exe=Root "readlink /proc/$servicePid/exe 2>/dev/null"
      if($exe -eq '/vendor/bin/pm-service'){$pmPid=$servicePid;$dual=$true;break}
    }
  }
}
if(-not $dual -and $QuickFallback) {
  # Repeatability runs on this ROM usually do not form dual ownership.
  # Verify the exact split fingerprint needed by the validated qcrild2
  # reacquire fallback instead of spending ~40 polling rounds proving it.
  $splitReady=$false
  for($i=1;$i -le 10;$i++) {
    $state=Root 'getprop init.svc.vendor.per_mgr'
    $servicePid=Root 'getprop init.svc_debug_pid.vendor.per_mgr'
    $exe=if($servicePid -match '^\d+$'){Root "readlink /proc/$servicePid/exe 2>/dev/null"}else{''}
    $now=@(Owners)
    $vendor=Root 'getprop vendor.peripheral.SDX55M.state'
    $kernel=Root 'cat /sys/bus/msm_subsys/devices/subsys10/state 2>/dev/null'
    $nowText=$now -join "`n"
    if($state -eq 'running' -and $servicePid -match '^\d+$' -and $exe -eq '/vendor/bin/pm-service' -and
       $now.Count -eq 1 -and $nowText -match "\s$holderPid\s" -and $nowText -notmatch "\s$servicePid\s" -and
       $vendor -eq 'OFFLINE' -and $kernel -eq 'ONLINE') {
      $splitReady=$true
      Write-Host "QUICK_FALLBACK_SPLIT=PASS PM_PID=$servicePid HOLDER_PID=$holderPid"
      break
    }
    Start-Sleep -Seconds 1
  }
  if($splitReady) {
    Write-Host 'NORMALIZATION=QUICK_FALLBACK_TO_QCRILD2'
    exit 40
  }
}
Require $dual 'pm-service did not form exact dual ownership; holder was not touched'
Write-Host "DUAL_OWNER=PASS PM_PID=$pmPid START_COUNT=$startCount RESTART_COUNT=$restartCount"

[void](Root "kill -TERM $holderPid")
Write-Host 'TERM_COUNT=1'
$gone=$false
for($i=1;$i -le 70;$i++) {
  if((Root "test -d /proc/$holderPid && echo LIVE || echo GONE") -eq 'GONE'){$gone=$true;break}
  Start-Sleep -Seconds 1
}
Require $gone 'holder did not exit after one TERM; no escalation performed'

$saved=Root "cat $PidFile 2>/dev/null"
if($saved -eq [string]$holderPid){[void](Root "rm -f $PidFile")}

Start-Sleep -Seconds 3
$postOwners=@(Owners)
$postState=Root 'getprop init.svc.vendor.per_mgr'
$postPid=Root 'getprop init.svc_debug_pid.vendor.per_mgr'
$postExe=Root "readlink /proc/$postPid/exe 2>/dev/null"
$postX55=Root 'getprop vendor.peripheral.SDX55M.state'
$postKernel=Root 'cat /sys/bus/msm_subsys/devices/subsys10/state 2>/dev/null'
$postCrash=Root 'cat /sys/bus/msm_subsys/devices/subsys10/crash_count 2>/dev/null'
$postQcrild=Root "ps -A -o PID,PPID,NAME,ARGS | grep -E '^ *[0-9]+ +1 +qcrild +qcrild$'"
$postQcrild2=Root "ps -A -o PID,PPID,NAME,ARGS | grep -E '^ *[0-9]+ +1 +qcrild +qcrild -c 2$'"

Require ($postState -eq 'running' -and $postPid -eq $pmPid -and $postExe -eq '/vendor/bin/pm-service') 'pm-service identity changed after handoff'
Require ($postOwners.Count -eq 1 -and $postOwners[0] -match "\s$pmPid\s") 'pm-service is not sole esoc0 owner'
Require ($postX55 -eq 'ONLINE' -and $postKernel -eq 'ONLINE' -and $postCrash -eq $crash) 'X55 did not remain cleanly online or crash_count changed during ownership handoff'
Require ($postQcrild -eq $qcrild -and $postQcrild2 -eq $qcrild2) 'QCRIL process identity changed'

Write-Host 'NORMALIZATION=PASS'
Write-Host "POST_PM_PID=$postPid"
Write-Host "POST_OWNER=$($postOwners[0])"
Write-Host "POST_X55=$postX55/$postKernel CRASH_COUNT=$postCrash UNCHANGED_FROM_ENTRY=PASS"
Write-Host 'QCRIL_UNCHANGED=PASS'
