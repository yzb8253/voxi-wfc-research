[CmdletBinding()]
param([ValidateRange(1,3)][int]$Cycle=1,[ValidateSet('POST_R3','POST_PIPELINE')][string]$Phase='POST_R3',[string]$RunName='r4b_3cycle_v2')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Serial='fd0ff892'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$HostRoot=Join-Path (Split-Path $Repo -Parent) ("voxi_wfc_local_runs\reset_boundary_r4b\{0}" -f $RunName)
$ProviderEvidence=Join-Path $HostRoot ("cycle_{0}_provider_evidence.json" -f $Cycle)
$R3Log=Join-Path $HostRoot ("cycle_{0}_r3.log" -f $Cycle)
function Invoke-Adb([string[]]$Arguments){$i=[Diagnostics.ProcessStartInfo]::new();$i.FileName=$Adb;$i.UseShellExecute=$false;$i.CreateNoWindow=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true;$i.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){'"'+$_.Replace('"','\"')+'"'}else{$_}})-join ' ');$p=[Diagnostics.Process]::new();$p.StartInfo=$i;if(-not $p.Start()){throw 'ADB_START_FAILED'};$o=$p.StandardOutput.ReadToEnd();$e=$p.StandardError.ReadToEnd();$p.WaitForExit();if($p.ExitCode -ne 0){throw $e};$o}
function Last([string]$Text,[string]$Pattern){@($Text -split "\r?\n"|Where-Object{$_ -match $Pattern}|Select-Object -Last 1)}
function Text($Value){$a=@($Value|Where-Object{$null -ne $_ -and ([string]$_).Length -gt 0});if($a.Count){([string]$a[0]).Trim()}else{'UNOBSERVABLE'}}
function Time($Value){$raw=Text $Value;$m=[regex]::Match($raw,'^(?<time>\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3}|\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}:\d{2})?)');if($m.Success){$m.Groups['time'].Value}else{'UNOBSERVABLE'}}
function Row([string]$Name,[string]$Source,$Value){$raw=Text $Value;[pscustomobject]@{FIELD=$Name;SOURCE=$Source;TIMESTAMP=(Time $Value);RAW_EVIDENCE=$raw;STATUS=$(if($raw -eq 'UNOBSERVABLE'){'UNOBSERVABLE'}else{'PASS'})}}
if(-not (Test-Path $ProviderEvidence)){throw 'PROVIDER_EVIDENCE_MISSING'}
$provider=@(Get-Content -Raw $ProviderEvidence|ConvertFrom-Json)
$t1=@($provider|Where-Object{$_.FIELD -eq 'T1_OLD_QTIDATA_PID_GONE'}|Select-Object -First 1)
$since=if($t1.Count -and $t1[0].TIMESTAMP -match '^\d{2}-\d{2}\s'){$t1[0].TIMESTAMP}else{throw 'PROVIDER_DEVICE_LOWER_BOUND_UNAVAILABLE'}
$logs=Invoke-Adb @('-s',$Serial,'logcat','-d','-b','all','-v','threadtime','-T',$since)
$r3=if(Test-Path $R3Log){Get-Content -Raw $R3Log}else{''}
$oldMatch=[regex]::Match($r3,'R3_SCOPE_BEFORE phone=(?<pid>\d+)')
$newMatch=[regex]::Match($r3,'R3_READY=PASS oldPhone=\d+ newPhone=(?<pid>\d+)')
$oldPid=if($oldMatch.Success){$oldMatch.Groups['pid'].Value}else{''}
$newPid=if($newMatch.Success){$newMatch.Groups['pid'].Value}else{''}
$t11=if($oldPid){$deviceDeath=Last $logs ("Process com\.android\.phone \(pid {0}\) has died" -f $oldPid);if(@($deviceDeath).Count){$deviceDeath}else{Last $r3 ("PHONE_WRITE=kill -TERM {0}" -f $oldPid)}}else{@()}
$t12=if($newPid){Last $logs ("(am_proc_start: \[0,{0},1001,com.android.phone|Start proc {0}:com.android.phone)" -f $newPid)}else{@()}
$t13=if($newPid){Last $logs ("\s{0}\s+\d+\s+.*ANM-1\s*: bind to vendor\.qti\.iwlan" -f $newPid)}else{@()}
$t14=if($newPid){Last $logs ("\s{0}\s+\d+\s+.*ANM-1\s*: onQualifiedNetworkTypesChanged:.*apnTypes.*ims.*networks.*IWLAN" -f $newPid)}else{@()}
$rows=@((Row 'T11_OLD_PHONE_TERM' 'R3 host timeline' $t11),(Row 'T12_NEW_PHONE_PID_BORN' 'ActivityManager logcat' $t12),(Row 'T13_FRAMEWORK_QNS_ANM_BIND' 'new-phone logcat' $t13),(Row 'T14_M1_ANM_IMS_IWLAN' 'new-phone logcat' $t14))
$out=Join-Path $HostRoot ("cycle_{0}_{1}_consumer_timeline.json" -f $Cycle,$Phase.ToLowerInvariant())
[IO.File]::WriteAllText($out,($rows|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $HostRoot ("cycle_{0}_{1}_bounded_logcat.txt" -f $Cycle,$Phase.ToLowerInvariant())),$logs,[Text.UTF8Encoding]::new($false))
Write-Host "R4B_TIMELINE_PHASE=$Phase"
$rows|ForEach-Object{Write-Host ("{0}={1} TIME={2}" -f $_.FIELD,$_.STATUS,$_.TIMESTAMP)}
