[CmdletBinding()]
param(
    [string]$Serial='fd0ff892',
    [ValidateRange(300,600)][int]$HoldSeconds=300,
    [switch]$Execute
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
$Node='/dev/subsys_esoc0'
$ExpectedFingerprint='Xiaomi/cas/cas:13/TKQ1.221114.001/V816.0.4.0.TJJCNXM:user/release-keys'
$WfcCtl='/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh'

function Log([string]$Text) {
    $line='{0} {1}' -f [DateTimeOffset]::Now.ToString('o'),$Text
    Write-Host $line
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}
function Quote-Sh([string]$Value) {
    $s=[string][char]39;$d=[string][char]34
    $s+$Value.Replace($s,($s+$d+$s+$d+$s))+$s
}
function Invoke-Adb([string[]]$Arguments) {
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$Adb
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){'"'+$_.Replace('"','\"')+'"'}else{$_}})-join ' ')
    $p=[Diagnostics.Process]::new();$p.StartInfo=$info
    if(-not $p.Start()){throw 'Unable to start adb'}
    $stdout=$p.StandardOutput.ReadToEnd();$stderr=$p.StandardError.ReadToEnd();$p.WaitForExit()
    $result=[pscustomobject]@{ExitCode=$p.ExitCode;Text=($stdout+$stderr).Trim()};$p.Dispose();$result
}
function Root([string]$Command) {
    $r=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)))
    if($r.ExitCode -ne 0){throw "root command failed: $Command`n$($r.Text)"}
    $r.Text.Trim()
}
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw "GATE_FAIL: $Message"}}
function Owners {
    @((Root "lsof $Node 2>/dev/null || true") -split "\r?\n"|Where-Object{$_ -match [regex]::Escape($Node)})
}
function PidFromExactProcess([string]$Regex) {
    $rows=@((Root 'ps -A -o PID,PPID,NAME,ARGS') -split "\r?\n"|Where-Object{$_ -match $Regex})
    Require ($rows.Count -eq 1) "process identity count != 1 for $Regex"
    [int](($rows[0].Trim()-split '\s+')[0])
}
function Snapshot([string]$Label) {
    $holder=(Root 'cat /data/local/tmp/x55_holder.pid 2>/dev/null || true').Trim()
    $fast=(Root "cat $PidFile 2>/dev/null || true").Trim()
    $pm=(Root 'getprop init.svc_debug_pid.vendor.per_mgr').Trim()
    $owners=@(Owners)
    $result=[pscustomobject]@{
        label=$Label;hostTime=[DateTimeOffset]::Now.ToString('o')
        airplane=(Root 'settings get global airplane_mode_on').Trim()
        perMgr=(Root 'getprop init.svc.vendor.per_mgr').Trim();pmPid=$pm
        vendorX55=(Root 'getprop vendor.peripheral.SDX55M.state').Trim()
        kernelX55=(Root 'cat /sys/bus/msm_subsys/devices/subsys10/state').Trim()
        crashCount=(Root 'cat /sys/bus/msm_subsys/devices/subsys10/crash_count').Trim()
        oldHolderPid=$holder;fastHolderPid=$fast;owners=$owners
        qcrildPid=PidFromExactProcess '^\s*\d+\s+1\s+qcrild\s+qcrild\s*$'
        qcrild2Pid=PidFromExactProcess '^\s*\d+\s+1\s+qcrild\s+qcrild -c 2\s*$'
    }
    Log ("SNAPSHOT label={0} airplane={1} perMgr={2} pm={3} vendor={4} kernel={5} crash={6} oldHolder={7} fastHolder={8} owners={9} qcrild={10} qcrild2={11}" -f $Label,$result.airplane,$result.perMgr,$result.pmPid,$result.vendorX55,$result.kernelX55,$result.crashCount,$result.oldHolderPid,$result.fastHolderPid,$owners.Count,$result.qcrildPid,$result.qcrild2Pid)
    $result
}
function Wait-Until([scriptblock]$Predicate,[int]$TimeoutMs,[int]$PollMs=100) {
    $sw=[Diagnostics.Stopwatch]::StartNew()
    while($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        if(& $Predicate){return $sw.ElapsedMilliseconds}
        Start-Sleep -Milliseconds $PollMs
    }
    -1
}
function Start-FastHolder {
    $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$Adb
    $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $psi.Arguments="-s $Serial shell su -c `"sh $RemotePayload $PidFile $ChildFile`""
    $p=[Diagnostics.Process]::new();$p.StartInfo=$psi
    if(-not $p.Start()){throw 'Unable to start fast holder'}
    $p
}

$devices=Invoke-Adb @('devices')
Require ($devices.Text -match "(?m)^$([regex]::Escape($Serial))\s+device\s*$") 'ADB target unavailable'
Require ((Root 'id') -match 'uid=0\(root\)') 'root unavailable'
Require ((Root 'getprop ro.build.fingerprint').Trim() -ceq $ExpectedFingerprint) 'ROM fingerprint mismatch'
$statusLine=@((Root "$WfcCtl status-json") -split "\r?\n"|Where-Object{$_.Trim().StartsWith('{')})|Select-Object -Last 1
Require (-not [string]::IsNullOrWhiteSpace($statusLine)) 'status-json missing'
$status=$statusLine|ConvertFrom-Json
Require ($status.target.mappingGate -and $status.target.slotId -eq 1 -and $status.target.phoneId -eq 1 -and $status.target.subId -eq 11 -and $status.target.carrierId -eq 28 -and $status.target.mcc -eq 234 -and $status.target.mnc -eq 15) 'VOXI exact mapping failed'
Require ($status.subscription.active -and $status.subscription.areUiccApplicationsEnabled) 'VOXI/UICC inactive'

$pre=Snapshot 'PRE'
Require ($pre.oldHolderPid -match '^\d+$' -and -not $pre.fastHolderPid) 'expected exact old holder only'
$oldPid=[int]$pre.oldHolderPid
$oldCmd=(Root "tr '\000' ' ' </proc/$oldPid/cmdline").Trim()
$oldFd=(Root "readlink /proc/$oldPid/fd/9 2>/dev/null").Trim()
Require ($oldCmd -match 'x55_holder\.pid' -and $oldCmd -match [regex]::Escape($Node) -and $oldFd -ceq $Node) 'old holder identity/FD9 failed'
Require ($pre.owners.Count -eq 1 -and $pre.owners[0] -match "\s$oldPid\s") 'old holder is not sole owner'
Require ($pre.perMgr -ceq 'stopped' -and [string]::IsNullOrWhiteSpace($pre.pmPid)) 'per_mgr must be stopped with no pm-service'
Require ($pre.vendorX55 -ceq 'ONLINE' -and $pre.kernelX55 -ceq 'ONLINE' -and $pre.crashCount -match '^\d+$') 'initial X55 fingerprint failed'
Log 'ENTRY_GATE=PASS'

if(-not $Execute){Log 'DRY_RUN=PASS PHONE_WRITES=0';exit 0}

$stage=Join-Path $env:TEMP ('x55-fast-holder-'+[guid]::NewGuid().ToString('N')+'.sh')
try {
    $text=(Get-Content -LiteralPath $Payload -Raw) -replace "`r`n","`n"
    [IO.File]::WriteAllText($stage,$text,[Text.UTF8Encoding]::new($false))
    $push=Invoke-Adb @('-s',$Serial,'push',$stage,$RemotePayload)
    Require ($push.ExitCode -eq 0) 'payload push failed'
    [void](Root "chmod 700 $RemotePayload; rm -f $PidFile $ChildFile")
}
finally {Remove-Item -LiteralPath $stage -Force -ErrorAction SilentlyContinue}

Log "OLD_HOLDER_TERM pid=$oldPid"
$oldTerm=[Diagnostics.Stopwatch]::StartNew();[void](Root "kill -TERM $oldPid")
$oldGone=Wait-Until { (Root "test -d /proc/$oldPid && echo LIVE || echo GONE") -eq 'GONE' } 70000 200
Require ($oldGone -ge 0) 'old holder TERM timeout; no escalation'
Log "OLD_HOLDER_GONE_MS=$oldGone"
[void](Root "test `$(cat /data/local/tmp/x55_holder.pid 2>/dev/null) = $oldPid && rm -f /data/local/tmp/x55_holder.pid || true")
$oldOffline=Wait-Until { @(Owners).Count -eq 0 -and (Root 'getprop vendor.peripheral.SDX55M.state') -eq 'OFFLINE' -and (Root 'cat /sys/bus/msm_subsys/devices/subsys10/state') -eq 'OFFLINE' } 20000 200
Require ($oldOffline -ge 0) 'owner NONE/X55 OFFLINE not reached after old holder'
Log "OLD_OWNER_NONE_X55_OFFLINE_MS=$oldOffline"

$hostHolder=Start-FastHolder
try {
    $fastReady=Wait-Until { (Root "cat $PidFile 2>/dev/null || true") -match '^\d+$' } 5000 100
    Require ($fastReady -ge 0) 'fast holder pidfile timeout'
    $fastPid=[int](Root "cat $PidFile")
    $childPid=[int](Root "cat $ChildFile")
    $fastCmd=(Root "tr '\000' ' ' </proc/$fastPid/cmdline").Trim()
    $fastFd=(Root "readlink /proc/$fastPid/fd/9 2>/dev/null").Trim()
    $childFd=(Root "readlink /proc/$childPid/fd/9 2>/dev/null || true").Trim()
    Require ($fastCmd -match 'x55_fast_holder_exp' -and $fastFd -ceq $Node) 'fast holder identity/FD9 failed'
    Require ([string]::IsNullOrWhiteSpace($childFd)) 'fast holder child inherited FD9'
    $online=Wait-Until { $o=@(Owners);$o.Count -eq 1 -and $o[0] -match "\s$fastPid\s" -and (Root 'getprop vendor.peripheral.SDX55M.state') -eq 'ONLINE' -and (Root 'cat /sys/bus/msm_subsys/devices/subsys10/state') -eq 'ONLINE' } 20000 200
    Require ($online -ge 0) 'fast holder sole-owner/X55 ONLINE gate failed'
    $holdCrash=(Root 'cat /sys/bus/msm_subsys/devices/subsys10/crash_count').Trim()
    Require ($holdCrash -eq $pre.crashCount) 'crash_count changed during fast holder acquisition'
    Log "FAST_HOLDER_READY pid=$fastPid child=$childPid readyMs=$fastReady onlineMs=$online childFd9=NONE crash=$holdCrash"

    for($elapsed=0;$elapsed -lt $HoldSeconds;$elapsed+=30) {
        Start-Sleep -Seconds 30
        $owners=@(Owners);$v=(Root 'getprop vendor.peripheral.SDX55M.state').Trim();$k=(Root 'cat /sys/bus/msm_subsys/devices/subsys10/state').Trim();$c=(Root 'cat /sys/bus/msm_subsys/devices/subsys10/crash_count').Trim()
        $fd=(Root "readlink /proc/$fastPid/fd/9 2>/dev/null").Trim();$childNow=(Root "cat $ChildFile 2>/dev/null || true").Trim();$childFdNow=if($childNow -match '^\d+$'){(Root "readlink /proc/$childNow/fd/9 2>/dev/null || true").Trim()}else{'MISSING_CHILD'}
        Require ($owners.Count -eq 1 -and $owners[0] -match "\s$fastPid\s" -and $fd -ceq $Node -and $childFdNow -ne $Node -and $v -eq 'ONLINE' -and $k -eq 'ONLINE' -and $c -eq $holdCrash) "hold stability failed at $($elapsed+30)s"
        Log "HOLD_STABLE elapsed=$($elapsed+30)s pid=$fastPid child=$childNow childFd9=$childFdNow vendor=$v kernel=$k crash=$c"
    }

    Log "FAST_HOLDER_TERM pid=$fastPid child=$childPid"
    $term=[Diagnostics.Stopwatch]::StartNew();[void](Root "kill -TERM $fastPid")
    $mainGone=$null;$ownerNone=$null;$vendorOffline=$null;$kernelOffline=$null
    while($term.ElapsedMilliseconds -lt 5000) {
        $ms=$term.ElapsedMilliseconds
        if($null -eq $mainGone -and (Root "test -d /proc/$fastPid && echo LIVE || echo GONE") -eq 'GONE'){$mainGone=$ms}
        if($null -eq $ownerNone -and @(Owners).Count -eq 0){$ownerNone=$ms}
        if($null -eq $vendorOffline -and (Root 'getprop vendor.peripheral.SDX55M.state') -eq 'OFFLINE'){$vendorOffline=$ms}
        if($null -eq $kernelOffline -and (Root 'cat /sys/bus/msm_subsys/devices/subsys10/state') -eq 'OFFLINE'){$kernelOffline=$ms}
        if($null -ne $mainGone -and $null -ne $ownerNone -and $null -ne $vendorOffline -and $null -ne $kernelOffline){break}
        Start-Sleep -Milliseconds 100
    }
    Require ($null -ne $mainGone -and $null -ne $ownerNone -and $ownerNone -le 3000) 'fast holder release exceeded 3 seconds'
    Log "FAST_RELEASE mainGoneMs=$mainGone ownerNoneMs=$ownerNone vendorOfflineMs=$vendorOffline kernelOfflineMs=$kernelOffline"
    if((Root "test -d /proc/$childPid && echo LIVE || echo GONE") -eq 'LIVE') {[void](Root "kill -TERM $childPid") ; Log "EXACT_DUMMY_CHILD_CLEANUP_TERM pid=$childPid"}
}
finally {
    if(-not $hostHolder.HasExited){$hostHolder.WaitForExit(3000)|Out-Null}
    if(-not $hostHolder.HasExited){$hostHolder.Kill()}
    $hostHolder.Dispose()
}

Log 'RESTORE_NATIVE_PER_MGR start'
[void](Root 'setprop ctl.start vendor.per_mgr')
$native=Wait-Until {
    $pm=(Root 'getprop init.svc_debug_pid.vendor.per_mgr').Trim();$o=@(Owners)
    $pm -match '^\d+$' -and (Root 'getprop init.svc.vendor.per_mgr') -eq 'running' -and $o.Count -eq 1 -and $o[0] -match "\s$pm\s" -and (Root "readlink /proc/$pm/exe 2>/dev/null") -eq '/vendor/bin/pm-service' -and (Root 'getprop vendor.peripheral.SDX55M.state') -eq 'ONLINE' -and (Root 'cat /sys/bus/msm_subsys/devices/subsys10/state') -eq 'ONLINE'
} 30000 250
Require ($native -ge 0) 'native per_mgr restoration failed'
$final=Snapshot 'FINAL_NATIVE'
Require ($final.crashCount -eq $pre.crashCount -and $final.qcrildPid -eq $pre.qcrildPid -and $final.qcrild2Pid -eq $pre.qcrild2Pid -and $final.airplane -eq $pre.airplane) 'final invariant changed'
[void](Root "rm -f $PidFile $ChildFile $RemotePayload")
Log 'HOLDER_FAST_EXPERIMENT=PASS'
Log 'SIM_WRITES=0 QCRIL_RESTARTS=0 AIRPLANE_WRITES=0 SIGKILL=0'
Log "LOG=$LogPath"
