[CmdletBinding()]
param(
    [string]$Serial='fd0ff892',
    [int[]]$PhasesSeconds=@(2,15,30,50,58)
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$PayloadRoot=Join-Path $PSScriptRoot 'payloads'
$RunId=(Get-Date -Format 'yyyyMMdd_HHmmss')
$OutputRoot=Join-Path (Split-Path $Repo -Parent) ("voxi_wfc_local_runs\holder_fast_dummy\{0}" -f $RunId)
[IO.Directory]::CreateDirectory($OutputRoot)|Out-Null
$CsvPath=Join-Path $OutputRoot 'samples.csv'
$records=New-Object 'System.Collections.Generic.List[object]'

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
    $r.Text
}
function Wait-FilePid([string]$Path,[int]$TimeoutMs=5000) {
    $sw=[Diagnostics.Stopwatch]::StartNew()
    while($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        $text=(Root "cat $Path 2>/dev/null || true").Trim()
        if($text -match '^\d+$'){return [int]$text}
        Start-Sleep -Milliseconds 100
    }
    throw "PID file timeout: $Path"
}
function Get-ChildPid([int]$HolderPid) {
    $line=@((Root 'ps -A -o PID,PPID,NAME,ARGS') -split "\r?\n"|Where-Object{$_ -match ("^\s*\d+\s+{0}\s+" -f $HolderPid)})|Select-Object -First 1
    if($line -match '^\s*(\d+)\s+'){return [int]$Matches[1]}
    0
}
function Get-State([int]$HolderPid,[int]$ChildPid) {
    $raw=Root ("for x in {0} {1}; do if test -d /proc/`$x; then echo PID=`$x,ALIVE=1,FD9=`$(readlink /proc/`$x/fd/9 2>/dev/null); else echo PID=`$x,ALIVE=0,FD9=; fi; done" -f $HolderPid,$ChildPid)
    $items=@{}
    foreach($line in @($raw -split "\r?\n")) {
        if($line -match '^PID=(\d+),ALIVE=([01]),FD9=(.*)$') {
            $items[[int]$Matches[1]]=[pscustomobject]@{Alive=($Matches[2]-eq '1');Fd9=$Matches[3]}
        }
    }
    $items
}
function Get-Identity([int]$ProcessId) {
    $line=@((Root "ps -p $ProcessId -o PID,PPID,NAME,ARGS") -split "\r?\n"|Where-Object{$_ -match "^\s*$ProcessId\s+"})|Select-Object -First 1
    if($line -notmatch '^\s*(\d+)\s+(\d+)\s+(\S+)\s+(.*)$'){throw "identity unavailable for $ProcessId"}
    [pscustomobject]@{Pid=[int]$Matches[1];Ppid=[int]$Matches[2];Name=$Matches[3];Cmd=$Matches[4]}
}
function Start-RemoteHolder([string]$RemoteScript,[string]$PidFile,[string]$ChildFile) {
    $args="sh $RemoteScript $PidFile"
    if($ChildFile){$args+=" $ChildFile"}
    $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$Adb
    $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $psi.Arguments="-s $Serial shell su -c `"$args`""
    $p=[Diagnostics.Process]::new();$p.StartInfo=$psi
    if(-not $p.Start()){throw 'Unable to start remote holder'}
    $p
}

if(-not (Test-Path -LiteralPath $Adb)){throw "adb missing: $Adb"}
$devices=Invoke-Adb @('devices')
if($devices.Text -notmatch "(?m)^$([regex]::Escape($Serial))\s+device\s*$"){throw 'ADB target not online'}
if((Root 'id') -notmatch 'uid=0\(root\)'){throw 'root unavailable'}

$remoteRoot='/data/local/tmp/voxi_holder_fast_dummy'
[void](Root "rm -rf $remoteRoot; mkdir -p $remoteRoot")
foreach($name in @('old_dummy_holder.sh','fast_dummy_holder.sh')) {
    $stage="/data/local/tmp/voxi_$name"
    $push=Invoke-Adb @('-s',$Serial,'push',(Join-Path $PayloadRoot $name),$stage)
    if($push.ExitCode -ne 0){throw "push failed: $name $($push.Text)"}
    [void](Root "cp $stage $remoteRoot/$name; chmod 700 $remoteRoot/$name; rm -f $stage")
}

foreach($impl in @('OLD','FAST')) {
    foreach($phase in $PhasesSeconds) {
        $tag=("{0}_{1}" -f $impl,$phase)
        $pidfile="$remoteRoot/$tag.pid"
        $childfile="$remoteRoot/$tag.child"
        $script=if($impl -eq 'OLD'){"$remoteRoot/old_dummy_holder.sh"}else{"$remoteRoot/fast_dummy_holder.sh"}
        [void](Root "rm -f $pidfile $childfile")
        $hostProcess=Start-RemoteHolder $script $pidfile $(if($impl -eq 'FAST'){$childfile}else{''})
        try {
            $holderPid=Wait-FilePid $pidfile
            Start-Sleep -Milliseconds 300
            $childPid=if($impl -eq 'FAST'){Wait-FilePid $childfile}else{Get-ChildPid $holderPid}
            if($childPid -le 1){throw "$tag child PID missing"}
            $initial=Get-State $holderPid $childPid
            if(-not $initial[$holderPid].Alive -or $initial[$holderPid].Fd9 -ne '/dev/null'){throw "$tag holder FD9 gate failed"}
            if($initial[$childPid].Fd9 -eq '/dev/null') {
                $childInherited=$true
            } else {$childInherited=$false}

            Start-Sleep -Seconds $phase
            $pre=Get-State $holderPid $childPid
            $holderIdentity=Get-Identity $holderPid
            $childIdentity=Get-Identity $childPid
            $termAt=[DateTimeOffset]::Now
            $sw=[Diagnostics.Stopwatch]::StartNew()
            [void](Root "kill -TERM $holderPid")
            $mainGoneMs=$null;$childGoneMs=$null;$fdOwnerNoneMs=$null
            $deadline=if($impl -eq 'OLD'){70000}else{5000}
            while($sw.ElapsedMilliseconds -lt $deadline) {
                $state=Get-State $holderPid $childPid
                if($null -eq $mainGoneMs -and -not $state[$holderPid].Alive){$mainGoneMs=$sw.ElapsedMilliseconds}
                if($null -eq $childGoneMs -and -not $state[$childPid].Alive){$childGoneMs=$sw.ElapsedMilliseconds}
                $fdHeld=(($state[$holderPid].Alive -and $state[$holderPid].Fd9 -eq '/dev/null') -or ($state[$childPid].Alive -and $state[$childPid].Fd9 -eq '/dev/null'))
                if($null -eq $fdOwnerNoneMs -and -not $fdHeld){$fdOwnerNoneMs=$sw.ElapsedMilliseconds}
                if($null -ne $mainGoneMs -and $null -ne $fdOwnerNoneMs){break}
                Start-Sleep -Milliseconds 100
            }
            if($null -eq $mainGoneMs){$mainGoneMs=-1}
            if($null -eq $childGoneMs){$childGoneMs=-1}
            if($null -eq $fdOwnerNoneMs){$fdOwnerNoneMs=-1}
            $post=Get-State $holderPid $childPid
            $records.Add([pscustomobject]@{
                holder_impl=$impl;term_phase_s=$phase;term_host_time=$termAt.ToString('o')
                holder_pid=$holderPid;holder_ppid=$holderIdentity.Ppid;holder_cmdline=$holderIdentity.Cmd
                child_pid=$childPid;child_ppid=$childIdentity.Ppid;child_cmdline=$childIdentity.Cmd
                holder_fd9_before=$pre[$holderPid].Fd9;child_fd9_before=$pre[$childPid].Fd9;child_inherited_fd9=$childInherited
                term_to_main_gone_ms=$mainGoneMs;term_to_child_gone_ms=$childGoneMs;term_to_fd_owner_none_ms=$fdOwnerNoneMs
                child_alive_after_measurement=$post[$childPid].Alive
            })
            Write-Host ("SAMPLE impl={0} phase={1}s main={2}ms child={3}ms fdNone={4}ms childInheritedFd9={5}" -f $impl,$phase,$mainGoneMs,$childGoneMs,$fdOwnerNoneMs,$childInherited)
            if($post[$childPid].Alive){[void](Root "kill -TERM $childPid 2>/dev/null || true")}
        }
        finally {
            if(-not $hostProcess.HasExited){$hostProcess.WaitForExit(3000)|Out-Null}
            if(-not $hostProcess.HasExited){$hostProcess.Kill()}
            $hostProcess.Dispose()
            [void](Root "rm -f $pidfile $childfile")
        }
    }
}

$records|Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
foreach($impl in @('OLD','FAST')) {
    $values=@($records|Where-Object holder_impl -eq $impl|ForEach-Object{[int64]$_.term_to_fd_owner_none_ms}|Sort-Object)
    $median=$values[[int][Math]::Floor(($values.Count-1)/2)]
    $max=$values[-1]
    $p95=$values[[int][Math]::Ceiling(0.95*$values.Count)-1]
    Write-Host ("SUMMARY impl={0} n={1} min={2} median={3} p95={4} max={5}" -f $impl,$values.Count,$values[0],$median,$p95,$max)
}
Write-Host "RESULTS=$CsvPath"
Write-Host 'ESOC_TOUCHED=NO'
