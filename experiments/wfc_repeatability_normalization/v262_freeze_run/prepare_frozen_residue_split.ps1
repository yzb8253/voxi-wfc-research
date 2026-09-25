[CmdletBinding()]
param(
    [string]$Serial='fd0ff892',
    [Parameter(Mandatory=$true)][string]$ObservationPath,
    [ValidateRange(10,15)][int]$TimeoutSeconds=15
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$Classifier=Join-Path $Repo 'experiments\wfc_repeatability_normalization\lightweight_profiling\classify_lightweight_state.ps1'
$Node='/dev/subsys_esoc0'
$PidFile='/data/local/tmp/x55_holder.pid'

function Quote-Sh([string]$Value){$s=[string][char]39;$d=[string][char]34;$s+$Value.Replace($s,($s+$d+$s+$d+$s))+$s}
function Invoke-Adb([string[]]$Arguments){
    $i=New-Object Diagnostics.ProcessStartInfo;$i.FileName=$Adb;$i.UseShellExecute=$false;$i.CreateNoWindow=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true
    $i.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){'"'+$_.Replace('"','\"')+'"'}else{$_}})-join ' ')
    $p=New-Object Diagnostics.Process;$p.StartInfo=$i;if(-not $p.Start()){throw 'Unable to start adb'};$o=$p.StandardOutput.ReadToEnd();$e=$p.StandardError.ReadToEnd();$p.WaitForExit();$r=[pscustomobject]@{ExitCode=$p.ExitCode;Text=($o+$e).Trim()};$p.Dispose();$r
}
function Root([string]$Command){$r=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)));if($r.ExitCode -ne 0){throw "ADB/root failed: $Command`n$($r.Text)"};$r.Text.Trim()}
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw "GATE_FAIL: $Message"}}
function Owners{@((Root "lsof $Node 2>/dev/null || true")-split "\r?\n"|Where-Object{$_ -match [regex]::Escape($Node)})}
function ExactProcess([string]$Regex){$rows=@((Root 'ps -A -o PID,PPID,NAME,ARGS')-split "\r?\n"|Where-Object{$_ -match $Regex});Require ($rows.Count -eq 1) "process identity count != 1: $Regex";$rows[0].Trim()}
function FirstPid([string]$Line){[int](($Line.Trim()-split '\s+')[0])}

try {
    Require (Test-Path -LiteralPath $ObservationPath) 'lightweight observation missing'
    $state=Get-Content -LiteralPath $ObservationPath -Raw|ConvertFrom-Json
    $classified=((& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Classifier -InputPath $ObservationPath -OutputFormat Json)|ConvertFrom-Json)
    Require ($classified.classification -eq 'FROZEN_RESIDUE' -and $classified.writeEligible -and -not $classified.failClosed -and @($classified.errors).Count -eq 0) 'observation is not exact FROZEN_RESIDUE'
    Require ($state.environment.airplaneMode -eq 0 -and $state.native.perMgrState -eq 'stopped' -and -not $state.native.pmService.processExists) 'ordinary residue environment/per_mgr/pm mismatch'
    Require ($state.native.vendorX55State -ceq 'ONLINE' -and $state.native.kernelX55State -ceq 'ONLINE') 'ordinary residue X55 mismatch'
    Require ($state.native.ownerCount -eq 1 -and $state.holder.processExists -and $state.holder.pidFilePresent -and $state.holder.pid -eq $state.holder.pidFileValue -and $state.holder.fd9Target -ceq $Node) 'ordinary residue holder/owner mismatch'
    Require ($null -eq $state.cne.requestId -and $null -eq $state.cne.satisfiedId -and $state.cne.currentEvidenceValid) 'current-table CNE must be valid null/null'

    $holderPid=[int]$state.holder.pid;$holderCmd=(Root "tr '\000' ' ' </proc/$holderPid/cmdline 2>/dev/null").Trim();$holderFd=(Root "readlink /proc/$holderPid/fd/9 2>/dev/null").Trim();$owners=@(Owners)
    $airplane=(Root 'settings get global airplane_mode_on').Trim();$perMgr=(Root 'getprop init.svc.vendor.per_mgr').Trim();$pmPid=(Root 'getprop init.svc_debug_pid.vendor.per_mgr').Trim();$vendor=(Root 'getprop vendor.peripheral.SDX55M.state').Trim();$kernel=(Root 'cat /sys/bus/msm_subsys/devices/subsys10/state').Trim();$crash=(Root 'cat /sys/bus/msm_subsys/devices/subsys10/crash_count').Trim()
    $primary=ExactProcess '^\s*\d+\s+1\s+qcrild\s+qcrild\s*$';$secondary=ExactProcess '^\s*\d+\s+1\s+qcrild\s+qcrild -c 2\s*$'
    Require ($airplane -eq '0' -and $perMgr -eq 'stopped' -and [string]::IsNullOrWhiteSpace($pmPid)) 'live ordinary residue environment/per_mgr/pm mismatch'
    Require ($holderCmd -ceq [string]$state.holder.cmdline -and $holderCmd -match 'x55_holder\.pid' -and $holderCmd -match [regex]::Escape($Node) -and $holderFd -ceq $Node) 'live holder identity mismatch'
    Require ($owners.Count -eq 1 -and $owners[0] -match "\s$holderPid\s") 'holder is not sole live owner'
    Require ($vendor -ceq 'ONLINE' -and $kernel -ceq 'ONLINE' -and $crash -match '^\d+$' -and [int64]$crash -eq [int64]$state.native.crashCount) 'live X55/crash mismatch'
    Require ((FirstPid $primary) -eq [int]$state.qcril.primary.pid -and (FirstPid $secondary) -eq [int]$state.qcril.secondary.pid) 'live qcrild identity/epoch mismatch'
}
catch {
    Write-Host ("SPLIT_GATE_RESULT=PRECHECK_FAIL detail={0}" -f $_.Exception.Message)
    Write-Host 'PER_MGR_START_COUNT=0'
    exit 40
}

$timer=[Diagnostics.Stopwatch]::StartNew()
[void](Root 'setprop ctl.start vendor.per_mgr')
Write-Host 'PER_MGR_START_COUNT=1'
$split=$false
while($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds){
    Start-Sleep -Milliseconds 500
    try {
        $stateNow=(Root 'getprop init.svc.vendor.per_mgr').Trim();$pmNow=(Root 'getprop init.svc_debug_pid.vendor.per_mgr').Trim();$exe=if($pmNow -match '^\d+$'){(Root "readlink /proc/$pmNow/exe 2>/dev/null").Trim()}else{''};$o=@(Owners);$v=(Root 'getprop vendor.peripheral.SDX55M.state').Trim();$k=(Root 'cat /sys/bus/msm_subsys/devices/subsys10/state').Trim();$c=(Root 'cat /sys/bus/msm_subsys/devices/subsys10/crash_count').Trim();$pNow=ExactProcess '^\s*\d+\s+1\s+qcrild\s+qcrild\s*$';$sNow=ExactProcess '^\s*\d+\s+1\s+qcrild\s+qcrild -c 2\s*$'
        $split=($stateNow -eq 'running' -and $pmNow -match '^\d+$' -and $exe -ceq '/vendor/bin/pm-service' -and $o.Count -eq 1 -and $o[0] -match "\s$holderPid\s" -and $o[0] -notmatch "\s$pmNow\s" -and $v -ceq 'OFFLINE' -and $k -ceq 'ONLINE' -and $c -match '^\d+$' -and [int64]$c -eq [int64]$crash -and $pNow -ceq $primary -and $sNow -ceq $secondary -and (Root "readlink /proc/$holderPid/fd/9 2>/dev/null").Trim() -ceq $Node)
        if($split){break}
    } catch {$split=$false}
}
$timer.Stop()
Write-Host ("PER_MGR_START_TO_SPLIT_MS={0}" -f $timer.ElapsedMilliseconds)
if(-not $split){Write-Host 'SPLIT_GATE_RESULT=TIMEOUT_FAIL_CLOSED';exit 41}
Write-Host 'SPLIT_GATE_RESULT=FROZEN_SPLIT_READY'
exit 0
