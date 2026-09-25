[CmdletBinding()]
param(
    [string]$Serial='fd0ff892',
    [ValidateRange(300,600)][int]$HoldSeconds=300,
    [switch]$Execute,
    [switch]$StaticOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$Payload=Join-Path $PSScriptRoot 'payloads\fast_esoc_holder.sh'
$RunId=Get-Date -Format 'yyyyMMdd_HHmmss'
$OutputRoot=Join-Path (Split-Path $Repo -Parent) ("voxi_wfc_local_runs\holder_fast_esoc\{0}" -f $RunId)
[IO.Directory]::CreateDirectory($OutputRoot)|Out-Null
$LogPath=Join-Path $OutputRoot 'experiment.log'
$PidFile='/data/local/tmp/x55_fast_holder_exp.pid'
$ChildFile='/data/local/tmp/x55_fast_holder_exp.child'
$RemotePayload='/data/local/tmp/x55_fast_holder_exp.sh'
$OldPidFile='/data/local/tmp/x55_holder.pid'
$Node='/dev/subsys_esoc0'
$ExpectedFingerprint='Xiaomi/cas/cas:13/TKQ1.221114.001/V816.0.4.0.TJJCNXM:user/release-keys'
$WfcCtl='/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh'
$script:FastPid=$null
$script:ChildPid=$null
$script:HostHolder=$null
$script:MutationStarted=$false
$script:Restored=$false
$script:Qcrild2Restarts=0

function Log([string]$Text) {
    $line='{0} {1}' -f [DateTimeOffset]::Now.ToString('o'),$Text
    Write-Host $line;Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}
function Quote-Sh([string]$Value) {$s=[string][char]39;$d=[string][char]34;$s+$Value.Replace($s,($s+$d+$s+$d+$s))+$s}
function Invoke-Adb([string[]]$Arguments) {
    $i=New-Object Diagnostics.ProcessStartInfo;$i.FileName=$Adb;$i.UseShellExecute=$false;$i.CreateNoWindow=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true
    $i.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){ '"'+$_.Replace('"','\"')+'"' }else{$_}})-join ' ')
    $p=New-Object Diagnostics.Process;$p.StartInfo=$i;if(-not $p.Start()){throw 'Unable to start adb'}
    $o=$p.StandardOutput.ReadToEnd();$e=$p.StandardError.ReadToEnd();$p.WaitForExit();$r=[pscustomobject]@{ExitCode=$p.ExitCode;Text=($o+$e).Trim()};$p.Dispose();$r
}
function Root([string]$Command) {$r=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)));if($r.ExitCode -ne 0){throw "root command failed: $Command`n$($r.Text)"};$r.Text.Trim()}
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw "GATE_FAIL: $Message"}}
function Owners {@((Root "lsof $Node 2>/dev/null || true") -split "\r?\n"|Where-Object{$_ -match [regex]::Escape($Node)})}
function ExactPid([string]$Regex) {$rows=@((Root 'ps -A -o PID,PPID,NAME,ARGS') -split "\r?\n"|Where-Object{$_ -match $Regex});Require ($rows.Count -eq 1) "process identity count != 1 for $Regex";[int](($rows[0].Trim()-split '\s+')[0])}
function Wait-Until([scriptblock]$Predicate,[int]$TimeoutMs,[int]$PollMs=100) {$sw=[Diagnostics.Stopwatch]::StartNew();while($sw.ElapsedMilliseconds -lt $TimeoutMs){if(& $Predicate){return $sw.ElapsedMilliseconds};Start-Sleep -Milliseconds $PollMs};-1}
function Snapshot([string]$Label) {
    $pm=(Root 'getprop init.svc_debug_pid.vendor.per_mgr').Trim();$owners=@(Owners)
    $r=[pscustomobject]@{label=$Label;airplane=(Root 'settings get global airplane_mode_on').Trim();perMgr=(Root 'getprop init.svc.vendor.per_mgr').Trim();pmPid=$pm;vendorX55=(Root 'getprop vendor.peripheral.SDX55M.state').Trim();kernelX55=(Root 'cat /sys/bus/msm_subsys/devices/subsys10/state').Trim();crash=(Root 'cat /sys/bus/msm_subsys/devices/subsys10/crash_count').Trim();oldHolder=(Root "cat $OldPidFile 2>/dev/null || true").Trim();fastHolder=(Root "cat $PidFile 2>/dev/null || true").Trim();owners=$owners;qcrild=ExactPid '^\s*\d+\s+1\s+qcrild\s+qcrild\s*$';qcrild2=ExactPid '^\s*\d+\s+1\s+qcrild\s+qcrild -c 2\s*$'}
    Log ("SNAPSHOT label={0} airplane={1} perMgr={2} pm={3} vendor={4} kernel={5} crash={6} oldHolder={7} fastHolder={8} owners={9} qcrild={10} qcrild2={11}" -f $Label,$r.airplane,$r.perMgr,$r.pmPid,$r.vendorX55,$r.kernelX55,$r.crash,$r.oldHolder,$r.fastHolder,$owners.Count,$r.qcrild,$r.qcrild2);$r
}
function Start-FastHolder {
    $i=New-Object Diagnostics.ProcessStartInfo;$i.FileName=$Adb;$i.UseShellExecute=$false;$i.CreateNoWindow=$true;$i.Arguments="-s $Serial shell su -c `"sh $RemotePayload $PidFile $ChildFile`""
    $p=New-Object Diagnostics.Process;$p.StartInfo=$i;if(-not $p.Start()){throw 'Unable to start fast holder'};$p
}
function Stop-Fast {
    if($null -eq $script:FastPid){return};$p=[int]$script:FastPid
    if((Root "test -d /proc/$p && echo LIVE || echo GONE") -ne 'LIVE'){return}
    $cmd=(Root "tr '\000' ' ' </proc/$p/cmdline").Trim();$fd=(Root "readlink /proc/$p/fd/9 2>/dev/null || true").Trim();Require ($cmd -match 'x55_fast_holder_exp' -and $fd -eq $Node) 'refusing TERM: fast holder identity changed'
    [void](Root "kill -TERM $p");$gone=Wait-Until {(Root "test -d /proc/$p && echo LIVE || echo GONE") -eq 'GONE'} 5000 100;Require ($gone -ge 0) 'fast holder TERM timeout';Log "FAILSAFE_FAST_TERM pid=$p goneMs=$gone"
    if($null -ne $script:ChildPid){$c=[int]$script:ChildPid;if((Root "test -d /proc/$c && echo LIVE || echo GONE") -eq 'LIVE'){Require ((Root "readlink /proc/$c/fd/9 2>/dev/null || true") -ne $Node) 'child owns FD9';[void](Root "kill -TERM $c");Log "EXACT_CHILD_TERM pid=$c"}}
}
function Native-Ready {
    $pm=(Root 'getprop init.svc_debug_pid.vendor.per_mgr').Trim();$o=@(Owners)
    $pm -match '^\d+$' -and (Root 'getprop init.svc.vendor.per_mgr') -eq 'running' -and $o.Count -eq 1 -and $o[0] -match "\s$pm\s" -and (Root "readlink /proc/$pm/exe 2>/dev/null") -eq '/vendor/bin/pm-service' -and (Root 'cat /sys/bus/msm_subsys/devices/subsys10/state') -eq 'ONLINE'
}
function Restore-Native([object]$Pre) {
    if($script:Restored){return};Stop-Fast;[void](Root "rm -f $PidFile $ChildFile $RemotePayload");[void](Root 'setprop ctl.start vendor.per_mgr');Log 'FAILSAFE_START_PER_MGR'
    $ok=Wait-Until {Native-Ready} 15000 250
    if($ok -lt 0){Require ((ExactPid '^\s*\d+\s+1\s+qcrild\s+qcrild\s*$') -eq $Pre.qcrild) 'primary qcrild changed';Require ($script:Qcrild2Restarts -eq 0) 'qcrild2 fallback already used';$old=ExactPid '^\s*\d+\s+1\s+qcrild\s+qcrild -c 2\s*$';Log "FAILSAFE_QCRILD2_RESTART old=$old";[void](Root 'setprop ctl.restart vendor.qcrild2');$script:Qcrild2Restarts++;$ok=Wait-Until {Native-Ready} 30000 250}
    Require ($ok -ge 0) 'native restoration failed';$final=Snapshot 'FINAL_NATIVE';Require ($final.crash -eq $Pre.crash -and $final.qcrild -eq $Pre.qcrild -and $final.airplane -eq $Pre.airplane) 'final invariant changed';$script:Restored=$true;Log "NATIVE_RESTORE=PASS qcrild2Restarts=$script:Qcrild2Restarts"
}

if($StaticOnly){$t=Get-Content -LiteralPath $Payload -Raw;Require ($t -match 'trap cleanup TERM INT HUP') 'trap missing';Require ($t -match 'exec 9</dev/subsys_esoc0') 'FD9 open missing';Require ($t -match 'sleep 3600 9<&- &') 'child FD close missing';Require ($t -notmatch '(?im)kill\s+-9|pkill|killall') 'forbidden kill';Log 'STATIC_AUDIT=PASS PHONE_WRITES=0';exit 0}

$devices=Invoke-Adb @('devices');Require ($devices.Text -match "(?m)^$([regex]::Escape($Serial))\s+device\s*$") 'ADB target unavailable';Require ((Root 'id') -match 'uid=0\(root\)') 'root unavailable';Require ((Root 'getprop ro.build.fingerprint').Trim() -ceq $ExpectedFingerprint) 'ROM mismatch'
$statusLine=@((Root "$WfcCtl status-json") -split "\r?\n"|Where-Object{$_.Trim().StartsWith('{')})|Select-Object -Last 1;Require (-not [string]::IsNullOrWhiteSpace($statusLine)) 'status-json missing';$status=$statusLine|ConvertFrom-Json
Require ($status.target.mappingGate -and $status.target.slotId -eq 1 -and $status.target.phoneId -eq 1 -and $status.target.subId -eq 11 -and $status.target.carrierId -eq 28 -and $status.target.mcc -eq 234 -and $status.target.mnc -eq 15) 'VOXI mapping failed';Require ($status.subscription.active -and $status.subscription.areUiccApplicationsEnabled) 'VOXI/UICC inactive'
$pre=Snapshot 'PRE';Require (-not $pre.fastHolder -and $pre.airplane -eq '1' -and $pre.vendorX55 -eq 'ONLINE' -and $pre.kernelX55 -eq 'ONLINE' -and $pre.crash -match '^\d+$') 'initial gate failed'
if($pre.oldHolder -match '^\d+$'){$oldPid=[int]$pre.oldHolder;$cmd=(Root "tr '\000' ' ' </proc/$oldPid/cmdline").Trim();$fd=(Root "readlink /proc/$oldPid/fd/9 2>/dev/null").Trim();Require ($cmd -match 'x55_holder\.pid' -and $fd -eq $Node -and $pre.owners.Count -eq 1 -and $pre.owners[0] -match "\s$oldPid\s" -and $pre.perMgr -eq 'stopped') 'old-holder gate failed';$mode='OLD_HOLDER'}else{Require ($pre.perMgr -eq 'running' -and $pre.pmPid -match '^\d+$' -and $pre.owners.Count -eq 1 -and $pre.owners[0] -match "\s$($pre.pmPid)\s" -and (Root "readlink /proc/$($pre.pmPid)/exe") -eq '/vendor/bin/pm-service') 'native-owner gate failed';$mode='NATIVE_OWNER'}
Log "ENTRY_GATE=PASS mode=$mode";if(-not $Execute){Log 'DRY_RUN=PASS PHONE_WRITES=0';exit 0}

try {
    $stage=Join-Path $env:TEMP ('x55-fast-'+[guid]::NewGuid().ToString('N')+'.sh');try{$text=(Get-Content $Payload -Raw)-replace "`r`n","`n";[IO.File]::WriteAllText($stage,$text,(New-Object Text.UTF8Encoding($false)));$push=Invoke-Adb @('-s',$Serial,'push',$stage,$RemotePayload);Require ($push.ExitCode -eq 0) 'push failed';[void](Root "chmod 700 $RemotePayload; rm -f $PidFile $ChildFile")}finally{Remove-Item $stage -Force -ErrorAction SilentlyContinue}
    $script:MutationStarted=$true
    if($mode -eq 'OLD_HOLDER'){Log "OLD_HOLDER_TERM pid=$oldPid";[void](Root "kill -TERM $oldPid");$gone=Wait-Until {(Root "test -d /proc/$oldPid && echo LIVE || echo GONE") -eq 'GONE'} 70000 200;Require ($gone -ge 0) 'old holder timeout';Log "OLD_HOLDER_GONE_MS=$gone";[void](Root "test `$(cat $OldPidFile 2>/dev/null) = $oldPid && rm -f $OldPidFile || true")}else{Log 'NATIVE_PER_MGR_STOP';[void](Root 'setprop ctl.stop vendor.per_mgr')}
    $released=Wait-Until {@(Owners).Count -eq 0 -and (Root 'cat /sys/bus/msm_subsys/devices/subsys10/state') -eq 'OFFLINE'} 20000 200;Require ($released -ge 0) 'owner NONE/kernel OFFLINE not reached';Require ((Root 'cat /sys/bus/msm_subsys/devices/subsys10/crash_count').Trim() -eq $pre.crash) 'crash changed';Log "PRE_FAST_RELEASE=PASS ms=$released vendorDiagnostic=$((Root 'getprop vendor.peripheral.SDX55M.state').Trim())"
    $script:HostHolder=Start-FastHolder;$ready=Wait-Until {(Root "cat $PidFile 2>/dev/null || true") -match '^\d+$'} 5000 100;Require ($ready -ge 0) 'fast pidfile timeout';$script:FastPid=[int](Root "cat $PidFile");$script:ChildPid=[int](Root "cat $ChildFile");$p=[int]$script:FastPid;$c=[int]$script:ChildPid
    Require ((Root "tr '\000' ' ' </proc/$p/cmdline") -match 'x55_fast_holder_exp' -and (Root "readlink /proc/$p/fd/9") -eq $Node -and [string]::IsNullOrWhiteSpace((Root "readlink /proc/$c/fd/9 2>/dev/null || true"))) 'fast identity/FD gate failed'
    $online=Wait-Until {$o=@(Owners);$o.Count -eq 1 -and $o[0] -match "\s$p\s" -and (Root 'cat /sys/bus/msm_subsys/devices/subsys10/state') -eq 'ONLINE'} 20000 200;Require ($online -ge 0 -and (Root 'cat /sys/bus/msm_subsys/devices/subsys10/crash_count').Trim() -eq $pre.crash) 'fast online gate failed';Log "FAST_READY pid=$p child=$c readyMs=$ready onlineMs=$online childFd9=NONE"
    for($e=0;$e -lt $HoldSeconds;$e+=30){Start-Sleep 30;$o=@(Owners);$child=(Root "cat $ChildFile 2>/dev/null || true").Trim();$childFd=if($child -match '^\d+$'){(Root "readlink /proc/$child/fd/9 2>/dev/null || true").Trim()}else{'MISSING'};Require ($o.Count -eq 1 -and $o[0] -match "\s$p\s" -and (Root "readlink /proc/$p/fd/9") -eq $Node -and $childFd -ne $Node -and (Root 'cat /sys/bus/msm_subsys/devices/subsys10/state') -eq 'ONLINE' -and (Root 'cat /sys/bus/msm_subsys/devices/subsys10/crash_count').Trim() -eq $pre.crash) "stability failed at $($e+30)s";Log "HOLD_STABLE elapsed=$($e+30)s pid=$p child=$child childFd9=$childFd"}
    Log "FAST_TERM pid=$p child=$c";$sw=[Diagnostics.Stopwatch]::StartNew();[void](Root "kill -TERM $p");$main=$null;$owner=$null;$vendor=$null;$kernel=$null
    while($sw.ElapsedMilliseconds -lt 5000){$ms=$sw.ElapsedMilliseconds;if($null -eq $main -and (Root "test -d /proc/$p && echo LIVE || echo GONE") -eq 'GONE'){$main=$ms};if($null -eq $owner -and @(Owners).Count -eq 0){$owner=$ms};if($null -eq $vendor -and (Root 'getprop vendor.peripheral.SDX55M.state') -eq 'OFFLINE'){$vendor=$ms};if($null -eq $kernel -and (Root 'cat /sys/bus/msm_subsys/devices/subsys10/state') -eq 'OFFLINE'){$kernel=$ms};if($null -ne $main -and $null -ne $owner -and $null -ne $kernel){break};Start-Sleep -Milliseconds 100}
    Require ($null -ne $main -and $null -ne $owner -and $null -ne $kernel -and $owner -le 3000) 'release >3s or kernel stayed online';Log "FAST_RELEASE mainGoneMs=$main ownerNoneMs=$owner vendorOfflineMs=$vendor kernelOfflineMs=$kernel"
    if((Root "test -d /proc/$c && echo LIVE || echo GONE") -eq 'LIVE'){Require ((Root "readlink /proc/$c/fd/9 2>/dev/null || true") -ne $Node) 'child owns FD9';[void](Root "kill -TERM $c");Log "EXACT_CHILD_TERM pid=$c"};$script:FastPid=$null;$script:ChildPid=$null
    Restore-Native $pre;Log 'HOLDER_FAST_EXPERIMENT=PASS';Log "SIM_WRITES=0 QCRIL2_RESTARTS=$script:Qcrild2Restarts AIRPLANE_WRITES=0 SIGKILL=0";Log "LOG=$LogPath"
} catch {Log ("EXPERIMENT_ERROR="+$_.Exception.Message);if($script:MutationStarted){try{Restore-Native $pre}catch{Log ("FAILSAFE_RESTORE_ERROR="+$_.Exception.Message)}};throw} finally {if($null -ne $script:HostHolder){if(-not $script:HostHolder.HasExited){$script:HostHolder.WaitForExit(3000)|Out-Null};if(-not $script:HostHolder.HasExited){$script:HostHolder.Kill()};$script:HostHolder.Dispose()}}
