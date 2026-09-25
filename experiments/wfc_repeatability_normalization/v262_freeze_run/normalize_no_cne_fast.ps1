[CmdletBinding()]
param([string]$Serial='fd0ff892')

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$PidFile='/data/local/tmp/x55_holder.pid'
$Reacquire=Join-Path $PSScriptRoot 'normalize_a1_qcrild2_reacquire.ps1'

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
function Require([bool]$Condition,[string]$Message) { if(-not $Condition){throw "FAST_NO_CNE_FAIL: $Message"} }
function Owners {
  $text=Root 'lsof /dev/subsys_esoc0 2>/dev/null || true'
  @($text -split "\r?\n" | Where-Object {$_ -match '/dev/subsys_esoc0'})
}

Require (Test-Path -LiteralPath $Reacquire) 'qcrild2 reacquire script missing'
$airplane=Root 'settings get global airplane_mode_on'
Require ($airplane -eq '0') 'airplane mode must be OFF'

$holderText=Root "cat $PidFile 2>/dev/null"
Require ($holderText -match '^\d+$') 'holder pidfile missing or non-numeric'
$holderPid=[int]$holderText
$holderCmd=Root "tr '\000' ' ' </proc/$holderPid/cmdline 2>/dev/null"
$holderFd9=Root "readlink /proc/$holderPid/fd/9 2>/dev/null"
Require ($holderCmd -match 'x55_holder\.pid' -and $holderCmd -match '/dev/subsys_esoc0') 'holder cmdline mismatch'
Require ($holderFd9 -eq '/dev/subsys_esoc0') 'holder fd9 mismatch'

$owners=@(Owners)
Require ($owners.Count -eq 1 -and $owners[0] -match "\s$holderPid\s") 'holder is not sole esoc0 owner at fast-retry entry'

$perMgr=Root 'getprop init.svc.vendor.per_mgr'
if($perMgr -ne 'running') {
  [void](Root 'setprop ctl.start vendor.per_mgr')
  Write-Host 'FAST_NO_CNE_PER_MGR_START_COUNT=1'
} else {
  Write-Host 'FAST_NO_CNE_PER_MGR_START_COUNT=0'
}

function Wait-SplitFingerprint([int]$Seconds) {
  for($i=1;$i -le $Seconds;$i++) {
    Start-Sleep -Seconds 1
    $state=Root 'getprop init.svc.vendor.per_mgr'
    $pmPid=Root 'getprop init.svc_debug_pid.vendor.per_mgr'
    $pmExe=if($pmPid -match '^\d+$'){Root "readlink /proc/$pmPid/exe 2>/dev/null"}else{''}
    $now=@(Owners)
    $vendor=Root 'getprop vendor.peripheral.SDX55M.state'
    $kernel=Root 'cat /sys/bus/msm_subsys/devices/subsys10/state 2>/dev/null'
    $crash=Root 'cat /sys/bus/msm_subsys/devices/subsys10/crash_count 2>/dev/null'

    if($state -eq 'running' -and $pmPid -match '^\d+$' -and $pmExe -eq '/vendor/bin/pm-service' -and
       $now.Count -eq 1 -and $now[0] -match "\s$holderPid\s" -and $now[0] -notmatch "\s$pmPid\s" -and
       $vendor -eq 'OFFLINE' -and $kernel -eq 'ONLINE' -and $crash -match '^\d+$') {
      Write-Host "FAST_NO_CNE_SPLIT=PASS HOLDER=$holderPid PM=$pmPid CRASH_COUNT=$crash"
      return $true
    }
  }
  return $false
}

$ready=Wait-SplitFingerprint -Seconds 8
if(-not $ready) {
  Write-Host 'FAST_NO_CNE_SPLIT not ready; restarting vendor.per_mgr once.'
  [void](Root 'setprop ctl.restart vendor.per_mgr')
  $ready=Wait-SplitFingerprint -Seconds 8
}
Require $ready 'known holder/pm-service split fingerprint not reached'

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Reacquire -Serial $Serial
$rc=$LASTEXITCODE
Require ($rc -eq 0) ("qcrild2 reacquire failed with exit code {0}" -f $rc)

Write-Host 'FAST_NO_CNE_NORMALIZATION=PASS'
exit 0
