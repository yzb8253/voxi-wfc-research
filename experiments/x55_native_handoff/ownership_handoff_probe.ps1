[CmdletBinding()]
param(
  [switch]$Execute,
  [string]$Adb = 'C:\Users\ZJH\Desktop\platform-tools\adb.exe',
  [string]$Serial = 'fd0ff892'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExperimentId = 'X55-OWNERSHIP-HANDOFF-001'
$PidFile = '/data/local/tmp/x55_handoff_test.pid'
$DeviceNode = '/dev/subsys_esoc0'
$StatePath = '/sys/bus/msm_subsys/devices/subsys10/state'
$CrashPath = '/sys/bus/msm_subsys/devices/subsys10/crash_count'
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogDir = Join-Path $PSScriptRoot "logs\$Stamp"
[IO.Directory]::CreateDirectory($LogDir) | Out-Null
$Transcript = Join-Path $LogDir 'experiment.log'
$PhoneWrites = 0
$HolderProcess = $null
$HolderAndroidPid = $null
$HolderTermSent = $false
$PerMgrStopped = $false
$ExperimentExecuted = $false
$FinalResult = 'BLOCKED_PRE_WRITE'

function Write-Log([string]$Message) {
  $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffK'), $Message
  [IO.File]::AppendAllText($Transcript,$line + [Environment]::NewLine,[Text.UTF8Encoding]::new($false))
  Write-Host $line
}

function Invoke-ProcessCapture {
  param([string]$FileName, [string[]]$Arguments, [int]$TimeoutMs = 30000)
  $psi = [Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $FileName
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  foreach ($arg in $Arguments) { [void]$psi.ArgumentList.Add($arg) }
  $p = [Diagnostics.Process]::new(); $p.StartInfo = $psi
  if (-not $p.Start()) { throw "Unable to start $FileName" }
  $outTask = $p.StandardOutput.ReadToEndAsync(); $errTask = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($TimeoutMs)) {
    try { $p.Kill($true) } catch {}
    throw "Host command timeout: $FileName $($Arguments -join ' ')"
  }
  [pscustomobject]@{ ExitCode=$p.ExitCode; StdOut=$outTask.GetAwaiter().GetResult(); StdErr=$errTask.GetAwaiter().GetResult() }
}

function Invoke-Adb([string[]]$Arguments, [int]$TimeoutMs = 30000) {
  Invoke-ProcessCapture -FileName $Adb -Arguments (@('-s',$Serial) + $Arguments) -TimeoutMs $TimeoutMs
}

function ConvertTo-ShSingleQuoted([string]$Value) {
  $sq=[string][char]39; $dq=[string][char]34
  $escape=$sq+$dq+$sq+$dq+$sq
  $sq + $Value.Replace($sq,$escape) + $sq
}

function Invoke-Root([string]$Command, [int]$TimeoutMs = 30000) {
  $remote='su -c ' + (ConvertTo-ShSingleQuoted $Command)
  Invoke-Adb -Arguments @('shell',$remote) -TimeoutMs $TimeoutMs
}

function Save-Result($Result, [string]$Name) {
  $text = "EXIT=$($Result.ExitCode)`n--- STDOUT ---`n$($Result.StdOut)`n--- STDERR ---`n$($Result.StdErr)"
  [IO.File]::WriteAllText((Join-Path $LogDir $Name),$text,[Text.UTF8Encoding]::new($false))
  Write-Log "$Name exit=$($Result.ExitCode)"
}

function Get-Section([string]$Text,[string]$Name) {
  $m=[regex]::Match($Text,"(?ms)^====$([regex]::Escape($Name))====\r?\n(.*?)(?=^====|\z)")
  if($m.Success){$m.Groups[1].Value.Trim()}else{''}
}

function Resolve-ExactPid([string]$ArgsPattern) {
  $r=Invoke-Root "ps -A -o PID,PPID,NAME,ARGS | grep -F '$ArgsPattern' | grep -v grep"
  $lines=@($r.StdOut -split "`r?`n" | Where-Object { $_.Trim() })
  if($lines.Count -ne 1){return $null}
  $parts=$lines[0].Trim() -split '\s+',4
  [pscustomobject]@{Pid=[int]$parts[0];Ppid=[int]$parts[1];Name=$parts[2];Args=$parts[3];Line=$lines[0]}
}

function Capture-State([string]$Label) {
  $cmd=@"
echo ====ROOT====
id
echo ====SELINUX====
getenforce
echo ====PER_MGR====
getprop init.svc.vendor.per_mgr
getprop init.svc_debug_pid.vendor.per_mgr
pidof pm-service
echo ====PER_PROXY====
getprop init.svc.vendor.per_proxy
getprop init.svc_debug_pid.vendor.per_proxy
pidof pm-proxy
echo ====QCRILD====
getprop init.svc.vendor.qcrild
getprop init.svc_debug_pid.vendor.qcrild
ps -A -o PID,PPID,NAME,ARGS | grep '/vendor/bin/hw/qcrild$' | grep -v grep
echo ====QCRILD2====
getprop init.svc.vendor.qcrild2
getprop init.svc_debug_pid.vendor.qcrild2
ps -A -o PID,PPID,NAME,ARGS | grep -F '/vendor/bin/hw/qcrild -c 2' | grep -v grep
echo ====MDM_HELPER====
getprop init.svc.vendor.mdm_helper
getprop init.svc_debug_pid.vendor.mdm_helper
pidof mdm_helper
echo ====OWNER====
lsof $DeviceNode 2>&1
echo ====X55====
cat $StatePath 2>&1
echo ====CRASH_COUNT====
cat $CrashPath 2>&1
echo ====HOLDER_FILES====
test -e /data/local/tmp/x55_holder.pid && echo PRESENT:/data/local/tmp/x55_holder.pid || echo ABSENT:/data/local/tmp/x55_holder.pid
test -e $PidFile && echo PRESENT:$PidFile || echo ABSENT:$PidFile
echo ====BOOT_ID====
cat /proc/sys/kernel/random/boot_id
"@
  $r=Invoke-Root $cmd
  Save-Result $r "state_$Label.txt"
  $r
}

function Test-EntryGate($State) {
  $t=$State.StdOut
  $root=Get-Section $t 'ROOT'; $selinux=Get-Section $t 'SELINUX'; $per=Get-Section $t 'PER_MGR'
  $owner=Get-Section $t 'OWNER'; $x55=Get-Section $t 'X55'; $crash=Get-Section $t 'CRASH_COUNT'; $holders=Get-Section $t 'HOLDER_FILES'
  $pm=Resolve-ExactPid 'pm-service'
  $q2=Resolve-ExactPid 'qcrild -c 2'
  $denied=($t -match '(?i)permission denied|operation not permitted')
  $rootOk=$root -match 'uid=0\(root\)'
  $running=@($per -split "`r?`n" | Where-Object {$_ -eq 'running'}).Count -ge 1
  $ownerLines=@($owner -split "`r?`n" | Where-Object {$_ -match [regex]::Escape($DeviceNode)})
  $ownerOk=$null -ne $pm -and $ownerLines.Count -eq 1 -and $ownerLines[0] -match 'pm-service' -and $ownerLines[0] -match "(^|\s)$($pm.Pid)(\s|$)"
  $x55Ok=$x55.Trim().ToUpperInvariant() -eq 'ONLINE'
  $crashOk=$crash.Trim() -eq '0'
  $holderOk=$holders -notmatch '(?m)^PRESENT:'
  $q2Ok=$null -ne $q2 -and $q2.Ppid -eq 1
  Write-Log "ENTRY root=$rootOk per_mgr_running=$running owner=$ownerOk x55=$x55Ok crash0=$crashOk no_holder=$holderOk qcrild2=$q2Ok denied=$denied"
  [pscustomobject]@{Pass=($rootOk -and $running -and $ownerOk -and $x55Ok -and $crashOk -and $holderOk -and $q2Ok -and -not $denied);Pm=$pm;Q2=$q2;Denied=$denied;Owner=$owner;X55=$x55;Crash=$crash}
}

function Wait-Until([scriptblock]$Condition,[int]$Seconds,[string]$What) {
  $end=(Get-Date).AddSeconds($Seconds)
  do { if(& $Condition){Write-Log "WAIT PASS $What";return $true}; Start-Sleep -Milliseconds 500 } while((Get-Date) -lt $end)
  Write-Log "WAIT FAIL $What"; $false
}

function Start-Holder {
  $holderCmd=('echo $$ > {0}; trap ''rm -f {0}'' EXIT; exec 9<{1} || exit 71; echo HOLDER_READY pid=$$ fd=9; trap ''exit 0'' TERM INT HUP; while :; do sleep 60; done' -f $PidFile,$DeviceNode)
  $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$Adb;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  $holderRemote='su -c ' + (ConvertTo-ShSingleQuoted $holderCmd)
  foreach($a in @('-s',$Serial,'shell',$holderRemote)){[void]$psi.ArgumentList.Add($a)}
  $p=[Diagnostics.Process]::new();$p.StartInfo=$psi;if(-not $p.Start()){throw 'holder adb start failed'}
  Write-Log "HOLDER host_pid=$($p.Id) started"
  $p
}

function Get-HolderPid {
  $r=Invoke-Root "cat $PidFile 2>/dev/null"
  $v=$r.StdOut.Trim();if($v -match '^\d+$'){[int]$v}else{$null}
}

function Test-OwnedHolder([int]$ProcessId) {
  if($null -eq $HolderProcess -or $HolderProcess.HasExited){return $false}
  $r=Invoke-Root "test -d /proc/$ProcessId && test \"`$(cat $PidFile 2>/dev/null)\" = \"$ProcessId\" && lsof $DeviceNode 2>&1"
  $lines=@($r.StdOut -split "`r?`n" | Where-Object {$_ -match [regex]::Escape($DeviceNode)})
  $r.ExitCode -eq 0 -and $lines.Count -eq 1 -and $lines[0] -match "(^|\s)$ProcessId(\s|$)"
}

function Stop-OwnedHolder {
  if($null -eq $HolderAndroidPid){return}
  if(-not (Test-OwnedHolder $HolderAndroidPid)){Write-Log 'REFUSE TERM: holder identity mismatch';return}
  if(-not $HolderTermSent){$script:HolderTermSent=$true;$r=Invoke-Root "kill -TERM $HolderAndroidPid";$script:PhoneWrites++;Save-Result $r 'holder_term.txt'}
  [void](Wait-Until { -not (Test-OwnedHolder $HolderAndroidPid) } 10 'holder PID exit')
  $rm=Invoke-Root "rm -f $PidFile";$script:PhoneWrites++;Save-Result $rm 'holder_pidfile_cleanup.txt'
}

function Ensure-PerMgrRunning {
  $s=Invoke-Root 'getprop init.svc.vendor.per_mgr'
  if($s.StdOut.Trim() -ne 'running'){$r=Invoke-Root 'setprop ctl.start vendor.per_mgr';$script:PhoneWrites++;Save-Result $r 'failsafe_per_mgr_start.txt'}
}

Write-Log "EXPERIMENT=$ExperimentId execute=$Execute serial=$Serial"
try {
  $devices=Invoke-ProcessCapture $Adb @('devices')
  Save-Result $devices 'adb_devices.txt'
  if($devices.StdOut -notmatch "(?m)^$([regex]::Escape($Serial))\s+device\s*$"){throw 'target ADB device not online'}

  $entry=Capture-State 'entry'
  $wfc=Invoke-Root '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh status'
  Save-Result $wfc 'wfc_status_entry.txt'
  $gate=Test-EntryGate $entry
  if(-not $gate.Pass){$FinalResult='BLOCKED_PRE_WRITE';Write-Log "RESULT=$FinalResult phone_writes=$PhoneWrites";return}
  if(-not $Execute){$FinalResult='ENTRY_GATE_PASS_DRY_RUN';Write-Log "RESULT=$FinalResult phone_writes=$PhoneWrites";return}

  $ExperimentExecuted=$true
  $lc=Invoke-Adb @('logcat','-b','all','-c');$PhoneWrites++;Save-Result $lc 'logcat_clear.txt'
  $oldPm=$gate.Pm.Pid; $oldQ2=$gate.Q2.Pid
  $stop=Invoke-Root 'setprop ctl.stop vendor.per_mgr';$PhoneWrites++;$PerMgrStopped=$true;Save-Result $stop 'per_mgr_stop.txt'
  if(-not (Wait-Until { (Invoke-Root 'getprop init.svc.vendor.per_mgr').StdOut.Trim() -eq 'stopped' } 15 'per_mgr stopped')){throw 'per_mgr did not stop'}
  $stopped=Capture-State 'after_per_mgr_stop'
  if((Get-Section $stopped.StdOut 'OWNER') -match 'pm-service'){throw 'pm-service still owns node after stop'}
  if((Get-Section $stopped.StdOut 'CRASH_COUNT').Trim() -ne '0'){throw 'crash_count changed after stop'}

  $HolderProcess=Start-Holder
  if(-not (Wait-Until { $script:HolderAndroidPid=Get-HolderPid; $null -ne $script:HolderAndroidPid -and (Test-OwnedHolder $script:HolderAndroidPid) } 15 'holder ready')){throw 'holder did not become ready'}
  $PhoneWrites++
  $holderState=Capture-State 'holder_only'
  $ho=Get-Section $holderState.StdOut 'OWNER';if($ho -notmatch "(^|\s)$HolderAndroidPid(\s|$)" -or ($ho -split "`r?`n" | Where-Object {$_ -match [regex]::Escape($DeviceNode)}).Count -ne 1){throw 'holder is not unique owner'}
  if((Get-Section $holderState.StdOut 'X55').Trim().ToUpperInvariant() -ne 'ONLINE' -or (Get-Section $holderState.StdOut 'CRASH_COUNT').Trim() -ne '0'){throw 'holder phase X55/crash gate failed'}

  $start=Invoke-Root 'setprop ctl.start vendor.per_mgr';$PhoneWrites++;Save-Result $start 'per_mgr_start_contended.txt'
  if(-not (Wait-Until { (Invoke-Root 'getprop init.svc.vendor.per_mgr').StdOut.Trim() -eq 'running' } 15 'per_mgr running')){throw 'per_mgr did not restart'}
  $PerMgrStopped=$false;Start-Sleep -Seconds 7
  $contended=Capture-State 'holder_plus_per_mgr';$newPm=Resolve-ExactPid 'pm-service';if($null -eq $newPm){throw 'pm-service missing after start'}
  $co=Get-Section $contended.StdOut 'OWNER';$ownerLines=@($co -split "`r?`n" | Where-Object {$_ -match [regex]::Escape($DeviceNode)})
  if($ownerLines.Count -ne 1 -or $ownerLines[0] -notmatch "(^|\s)$HolderAndroidPid(\s|$)"){$FinalResult='INCONCLUSIVE_BEHAVIOR_CHANGED';throw 'holder not unique owner in contended phase'}
  if((Get-Section $contended.StdOut 'X55').Trim().ToUpperInvariant() -ne 'ONLINE' -or (Get-Section $contended.StdOut 'CRASH_COUNT').Trim() -ne '0'){throw 'contended phase X55/crash gate failed'}

  Write-Log "T1 holder=$HolderAndroidPid pm=$($newPm.Pid) old_qcrild2=$oldQ2"
  Stop-OwnedHolder
  $released=Capture-State 'holder_released';$ro=Get-Section $released.StdOut 'OWNER';if($ro -match [regex]::Escape($DeviceNode)){throw 'owner not empty after holder release'}
  $restart=Invoke-Root 'setprop ctl.restart vendor.qcrild2';$PhoneWrites++;Save-Result $restart 'qcrild2_restart.txt'
  $newQ2=$null
  if(-not (Wait-Until { $script:newQ2=Resolve-ExactPid 'qcrild -c 2'; $null -ne $script:newQ2 -and $script:newQ2.Pid -ne $oldQ2 } 15 'new qcrild2 PID')){throw 'qcrild2 did not restart'}
  Start-Sleep -Seconds 5
  $final=Capture-State 'final'
  $full=Invoke-Adb @('logcat','-d','-b','all','-v','threadtime') 60000;Save-Result $full 'logcat_all.txt'
  $filtered=($full.StdOut -split "`r?`n" | Where-Object {$_ -match 'PerMgrSrv|PerMgrLib|QCRIL|qcrild|modem|vote|PeripheralManager|RILQ|RADIO_NOT_AVAILABLE'}) -join "`n"
  [IO.File]::WriteAllText((Join-Path $LogDir 'logcat_filtered.txt'),$filtered,[Text.UTF8Encoding]::new($false))
  $esoc=Invoke-Root 'cat /sys/kernel/debug/ipc_logging/esoc-mdm/log 2>&1' 30000;Save-Result $esoc 'esoc_mdm_log.txt'
  $voteOk=$filtered -match 'QCRIL successfully registered for SDX55M' -and $filtered -match 'QCRIL voting for SDX55M'
  $fo=Get-Section $final.StdOut 'OWNER';$ownerOk=$fo -match 'pm-service' -and $fo -match "(^|\s)$($newPm.Pid)(\s|$)"
  $xOk=(Get-Section $final.StdOut 'X55').Trim().ToUpperInvariant() -eq 'ONLINE';$cOk=(Get-Section $final.StdOut 'CRASH_COUNT').Trim() -eq '0'
  if($voteOk -and $ownerOk -and $xOk -and $cOk){$FinalResult='VERIFIED_NATIVE_HANDOFF_SUCCESS'}elseif($voteOk -and -not $ownerOk){$FinalResult='VERIFIED_REVOTE_NO_NATIVE_REACQUIRE'}elseif(-not $voteOk){$FinalResult='QCRILD2_CLIENT_REBUILD_NO_VOTE'}else{$FinalResult='INCONCLUSIVE'}
} catch {
  Write-Log "ERROR=$($_.Exception.Message) STACK=$($_.ScriptStackTrace)"
  if($FinalResult -eq 'BLOCKED_PRE_WRITE' -and $ExperimentExecuted){$FinalResult='FAILED_FAIL_SAFE'}
} finally {
  if($null -eq $HolderAndroidPid -and $null -ne $HolderProcess){$HolderAndroidPid=Get-HolderPid}
  if($null -ne $HolderAndroidPid){Stop-OwnedHolder}
  if($null -ne $HolderProcess -and -not $HolderProcess.HasExited){
    Write-Log 'Host adb holder process still alive after normal cleanup; stopping only this host process.'
    try{$HolderProcess.Kill($true);$HolderProcess.WaitForExit(5000)|Out-Null}catch{Write-Log "Host holder cleanup error: $($_.Exception.Message)"}
  }
  if($PerMgrStopped){Ensure-PerMgrRunning}
  Write-Log "FINAL_RESULT=$FinalResult PHONE_WRITES=$PhoneWrites LOG_DIR=$LogDir"
}
