[CmdletBinding()]
param(
  [ValidateRange(2,5)][int]$Cycle,
  [ValidateSet('Minimal','UpperBound')][string]$Mode,
  [switch]$Execute,
  [switch]$StaticAudit,
  [string]$RunName='r_big_v1_1_5cycle'
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Serial='fd0ff892'
$ReadyTimeoutSeconds=120
$StableSamplesRequired=10
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$CaptureScript=Join-Path $Repo 'experiments\wfc_repeatability_normalization\capture_snapshot.ps1'
$PhoneRebuild=Join-Path $Repo 'experiment\reset-boundary-r3\Prepare-R3Cycle.ps1'
$SummaryRoot=Join-Path $PSScriptRoot "runs\$RunName"
$SnapshotRoot=Join-Path $SummaryRoot 'snapshots'
$HostRoot=Join-Path (Split-Path $Repo -Parent) "voxi_wfc_local_runs\destructive_upper_bound\$RunName"
$Timeline=Join-Path $HostRoot ("cycle_{0}_prepare.log" -f $Cycle)
$NativeMetadata=Join-Path $HostRoot ("cycle_{0}_native_ready.json" -f $Cycle)
[IO.Directory]::CreateDirectory($SnapshotRoot)|Out-Null
[IO.Directory]::CreateDirectory($HostRoot)|Out-Null

function Log([string]$Message){$line='{0} {1}' -f (Get-Date -Format o),$Message;Add-Content -LiteralPath $Timeline -Value $line -Encoding UTF8;Write-Host $line}
function Quote-Sh([string]$Value){$s=[string][char]39;$d=[string][char]34;$s+$Value.Replace($s,($s+$d+$s+$d+$s))+$s}
function Invoke-Adb([string[]]$Arguments){
  $i=[Diagnostics.ProcessStartInfo]::new();$i.FileName=$Adb;$i.UseShellExecute=$false;$i.CreateNoWindow=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true
  $i.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){ '"'+$_.Replace('"','\"')+'"' }else{$_}})-join ' ')
  $p=[Diagnostics.Process]::new();$p.StartInfo=$i;if(-not $p.Start()){throw 'ADB_START_FAILED'};$o=$p.StandardOutput.ReadToEnd();$e=$p.StandardError.ReadToEnd();$p.WaitForExit();[pscustomobject]@{ExitCode=$p.ExitCode;Text=$o+$e}
}
function Root([string]$Command){$r=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)));if($r.ExitCode -ne 0){throw "ROOT_READ_FAILED=$Command`n$($r.Text)"};$r.Text.Trim()}
function Root-Write([string]$Command){if(-not $Execute){throw "DRY_RUN_BLOCKED_WRITE=$Command"};Log "PHONE_WRITE=$Command";$r=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)));if($r.ExitCode -ne 0){throw "PHONE_WRITE_FAILED=$Command`n$($r.Text)"};$r.Text.Trim()}
function Child([string]$Path,[string[]]$Arguments){$old=$ErrorActionPreference;try{$ErrorActionPreference='Continue';$o=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments 2>&1);$rc=$LASTEXITCODE}finally{$ErrorActionPreference=$old};[pscustomobject]@{ExitCode=$rc;Output=$o}}
function Capture([string]$Label){
  $r=Child $CaptureScript @('-Label',$Label,'-Serial',$Serial,'-RunName',$RunName);$r.Output|ForEach-Object{Log "CAPTURE=$_"};if($r.ExitCode -ne 0){throw "CAPTURE_FAILED=$Label"}
  $generated=Join-Path $Repo "experiments\wfc_repeatability_normalization\runs\$RunName\snapshots\$Label.json"
  $json=Get-Content -LiteralPath $generated -Raw;$dest=Join-Path $SnapshotRoot ($Label+'.json');[IO.File]::WriteAllText($dest,$json,[Text.UTF8Encoding]::new($false));Remove-Item -LiteralPath $generated -Force
  $json|ConvertFrom-Json
}
function One-Process([string]$Pattern,[string]$Label){$rows=@((Root 'ps -A -o UID,PID,PPID,NAME,ARGS') -split "\r?\n"|Where-Object{$_ -match $Pattern});if($rows.Count -ne 1){throw "${Label}_IDENTITY_COUNT=$($rows.Count)"};$p=$rows[0].Trim() -split '\s+',5;[pscustomobject]@{uid=[int]$p[0];pid=[int]$p[1];ppid=[int]$p[2];name=$p[3];args=$p[4]}}
function Scope {[pscustomobject]@{
  qcrild=(One-Process '^\s*1001\s+\d+\s+1\s+qcrild\s+qcrild\s*$' 'QCRILD')
  qcrild2=(One-Process '^\s*1001\s+\d+\s+1\s+qcrild\s+qcrild -c 2\s*$' 'QCRILD2')
  qtidata=(One-Process '^\s*10104\s+\d+\s+\d+\s+\.qtidataservices\s+\.qtidataservices\s*$' 'QTIDATA')
  phone=(One-Process '^\s*1001\s+\d+\s+\d+\s+com\.android\.phone\s+com\.android\.phone\s*$' 'PHONE')
}}
function Owners {@((Root 'lsof /dev/subsys_esoc0 2>/dev/null || true') -split "\r?\n"|Where-Object{$_ -match '/dev/subsys_esoc0'})}
function Native-State {
  $pm=(Root 'getprop init.svc_debug_pid.vendor.per_mgr');$pmExe=if($pm -match '^\d+$'){Root "readlink /proc/$pm/exe 2>/dev/null"}else{''}
  [pscustomobject]@{perMgr=(Root 'getprop init.svc.vendor.per_mgr');pmPid=$pm;pmExe=$pmExe;vendorX55=(Root 'getprop vendor.peripheral.SDX55M.state');kernelX55=(Root 'cat /sys/bus/msm_subsys/devices/subsys10/state');crash=(Root 'cat /sys/bus/msm_subsys/devices/subsys10/crash_count');owners=@(Owners)}
}
function Dsd-Wds-Ready {$d=Root 'lshal debug vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot2 2>/dev/null';($d -match 'DsdServiceReady=true' -and $d -match 'WdsServiceReady=true')}
function Assert-Target($State){if(-not ($State.device.root -and $State.device.product -eq 'cas' -and $State.target.mappingGate -and $State.target.subId -eq 11 -and $State.target.slotId -eq 1 -and $State.target.phoneId -eq 1 -and $State.target.carrierId -eq 28 -and $State.target.mcc -eq 234 -and $State.target.mnc -eq 15 -and $State.subscription.active -and $State.subscription.uiccAppsEnabled)){throw 'TARGET_GATE_FAIL'}}
function Release-Holder {
  $saved=Root 'cat /data/local/tmp/x55_holder.pid 2>/dev/null || true';if($saved -notmatch '^\d+$'){throw 'HOLDER_PIDFILE_MISSING'};$holder=[int]$saved
  $cmd=Root "tr '\000' ' ' </proc/$holder/cmdline 2>/dev/null";$fd=Root "readlink /proc/$holder/fd/9 2>/dev/null";$owners=@(Owners)
  if($cmd -notmatch 'x55_holder\.pid' -or $cmd -notmatch '/dev/subsys_esoc0' -or $fd -ne '/dev/subsys_esoc0' -or $owners.Count -ne 1 -or $owners[0] -notmatch "\s$holder\s"){throw 'HOLDER_IDENTITY_FAIL'}
  [void](Root-Write "kill -TERM $holder")
  $gone=$false;for($i=0;$i -lt 70;$i++){if((Root "test -d /proc/$holder && echo LIVE || echo GONE") -eq 'GONE'){$gone=$true;break};Start-Sleep 1};if(-not $gone){throw 'HOLDER_TERM_TIMEOUT'}
  if((Root 'cat /data/local/tmp/x55_holder.pid 2>/dev/null || true') -eq [string]$holder){[void](Root-Write 'rm -f /data/local/tmp/x55_holder.pid')}
  $offline=$false;for($i=0;$i -lt 20;$i++){$n=Native-State;if($n.owners.Count -eq 0 -and $n.kernelX55 -eq 'OFFLINE' -and $n.crash -eq '0'){$offline=$true;break};Start-Sleep 1};if(-not $offline){throw 'HOLDER_RELEASE_READY_FAIL'}
  Log "HOLDER_RELEASE_READY=PASS pid=$holder ownerCount=$($n.owners.Count) kernelX55=$($n.kernelX55) crashCount=$($n.crash) vendorPeripheral=$($n.vendorX55) vendorPeripheralRole=TELEMETRY_ONLY";return $holder
}
function Ensure-PerMgrRunningNonOwner {
  $n=Native-State;if($n.perMgr -eq 'stopped'){[void](Root-Write 'setprop ctl.start vendor.per_mgr')}
  $ok=$false;for($i=0;$i -lt 20;$i++){$n=Native-State;if($n.perMgr -eq 'running' -and $n.pmPid -match '^\d+$' -and $n.pmExe -eq '/vendor/bin/pm-service' -and $n.owners.Count -eq 0 -and $n.crash -eq '0'){$ok=$true;break};Start-Sleep 1};if(-not $ok){throw 'PER_MGR_RUNNING_NONOWNER_FAIL'}
  Log "PER_MGR_NONOWNER=PASS pid=$($n.pmPid)"
}
function Restart-Qcrild2([string]$Generation){
  $before=Scope;$primary=$before.qcrild.pid;$old=$before.qcrild2.pid;$qtidata=$before.qtidata.pid;$phone=$before.phone.pid
  [void](Root-Write 'setprop ctl.restart vendor.qcrild2')
  $new=$null;for($i=0;$i -lt $ReadyTimeoutSeconds;$i++){Start-Sleep 1;try{$s=Scope;$n=Native-State}catch{continue};if($s.qcrild2.pid -ne $old -and $s.qcrild.pid -eq $primary -and $s.qtidata.pid -eq $qtidata -and $s.phone.pid -eq $phone -and $n.perMgr -eq 'running' -and $n.pmExe -eq '/vendor/bin/pm-service' -and $n.owners.Count -eq 1 -and $n.owners[0] -match "\s$($n.pmPid)\s" -and $n.vendorX55 -eq 'ONLINE' -and $n.kernelX55 -eq 'ONLINE' -and $n.crash -eq '0' -and (Dsd-Wds-Ready)){$new=$s;break}}
  if($null -eq $new){throw "QCRILD2_${Generation}_READY_FAIL"};$post=Native-State;Log "QCRILD2_GEN_${Generation}=PASS old=$old new=$($new.qcrild2.pid) ownerCount=$($post.owners.Count) pmService=$($post.pmPid) kernelX55=$($post.kernelX55) crashCount=$($post.crash) vendorPeripheral=$($post.vendorX55)";return $new.qcrild2.pid
}
function Restart-QtiDataServices([int]$ExpectedQcrild2){
  $before=Scope;if($before.qcrild2.pid -ne $ExpectedQcrild2){throw 'QTIDATA_PRE_QCRILD2_MISMATCH'}
  $domain=Root "cat /proc/$($before.qtidata.pid)/attr/current";$activity=Root 'dumpsys activity processes .qtidataservices'
  if($before.qtidata.uid -ne 10104 -or $domain -notmatch '^u:r:vendor_qtidataservices_app:s0' -or $activity -notmatch "\*PERS\* UID 10104 ProcessRecord\{[^\r\n]+\s$($before.qtidata.pid):\.qtidataservices/u0a104\}"){throw 'QTIDATASERVICES_IDENTITY_FAIL'}
  [void](Root-Write "kill -TERM $($before.qtidata.pid)")
  $new=$null;for($i=0;$i -lt $ReadyTimeoutSeconds;$i++){Start-Sleep 1;try{$s=Scope}catch{continue};if($s.qtidata.pid -ne $before.qtidata.pid -and $s.qcrild2.pid -eq $ExpectedQcrild2 -and $s.qcrild.pid -eq $before.qcrild.pid -and $s.phone.pid -eq $before.phone.pid){$new=$s.qtidata.pid;break}}
  if($null -eq $new){throw 'QTIDATASERVICES_RESTART_FAIL'};Log "QTIDATASERVICES_GEN_NEW=PASS old=$($before.qtidata.pid) new=$new";return $new
}
function Current-Nah([string]$Debug){$m=[regex]::Match($Debug,'(?ms)^NetworkAvailabilityHandler:\s*(?<body>.*?)^NetworkServiceHandler:');if($m.Success){$m.Groups['body'].Value}else{''}}
function Latest-Constructor([string]$Debug){$rows=@($Debug -split "\r?\n"|Where-Object{$_ -match '^\s*(?<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}) \[NAH\]constructor\s*$'});if($rows.Count -eq 0){return $null};$m=[regex]::Match($rows[-1].Trim(),'^(?<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})');$m.Groups['ts'].Value}
function Wait-NativeReady([int]$ExpectedQcrild2,[int]$ExpectedQtidata,[datetime]$LowerBound){
  $deadline=(Get-Date).AddSeconds($ReadyTimeoutSeconds);$stable=0;$generation='';$last=$null
  while((Get-Date)-lt $deadline){Start-Sleep 1;$s=Scope;if($s.qcrild2.pid -ne $ExpectedQcrild2 -or $s.qtidata.pid -ne $ExpectedQtidata){throw 'NATIVE_READY_SCOPE_CHANGED'};$debug=Root 'lshal debug vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot2 2>/dev/null';$g=Latest-Constructor $debug;$body=Current-Nah $debug;$work=[regex]::Match($body,'(?ms)apn=ims\s+hasPendingIntent=(?<pending>\S+).*?apn types=\[(?<types>[^\]]*IMS[^\]]*)\]\s+networks=\[(?<networks>[^\]]+)\]');$reported=[regex]::Match($body,'(?m)^\s*apnType=IMS\s+prefNw=(?<network>\S+)\s*$');$gp=[regex]::Match($body,'(?m)^\s*globalPrefSys=\s*(?<value>\S+)\s*$');$fresh=$false;if($g){$fresh=([datetime]::ParseExact($g,'yyyy-MM-dd HH:mm:ss.fff',[Globalization.CultureInfo]::InvariantCulture) -ge $LowerBound)};$n=Native-State;$clean=($n.owners.Count -eq 1 -and $n.owners[0] -match "\s$($n.pmPid)\s" -and $n.vendorX55 -eq 'ONLINE' -and $n.kernelX55 -eq 'ONLINE' -and $n.crash -eq '0');$ready=($fresh -and $gp.Success -and $gp.Groups['value'].Value -ne 'UNKNOWN' -and $work.Success -and $work.Groups['networks'].Value -match 'EUTRAN' -and $reported.Success -and $reported.Groups['network'].Value -match 'EUTRAN' -and $debug -match 'DsdServiceReady=true' -and $debug -match 'WdsServiceReady=true' -and $clean);Log "NATIVE_READY_PROGRESS G=$g fresh=$fresh global=$(if($gp.Success){$gp.Groups['value'].Value}else{'NONE'}) working=$(if($work.Success){$work.Groups['networks'].Value}else{'NONE'}) reported=$(if($reported.Success){$reported.Groups['network'].Value}else{'NONE'}) stable=$stable";if($ready){if($generation -eq $g){$stable++}else{$generation=$g;$stable=1};$last=[ordered]@{generation=$g;globalPrefSys=$gp.Groups['value'].Value;workingIms=$work.Groups['networks'].Value;lastReportedIms=$reported.Groups['network'].Value;qcrild2=$ExpectedQcrild2;qtidataservices=$ExpectedQtidata}}else{$stable=0;$generation=''};if($stable -ge $StableSamplesRequired){break}}
  if($stable -lt $StableSamplesRequired){throw 'R_BIG_V1_1_NATIVE_REPAIR_FAILED'};[IO.File]::WriteAllText($NativeMetadata,($last|ConvertTo-Json),[Text.UTF8Encoding]::new($false));Log "NATIVE_READY=PASS G=$generation";return $last
}
function Rebuild-Phone([int]$ExpectedQcrild2,[int]$ExpectedQtidata,[string]$ExpectedGeneration){
  $host=Join-Path $HostRoot ("phone_c{0}" -f $Cycle);$summary=Join-Path $SummaryRoot ("phone_c{0}" -f $Cycle);$r=Child $PhoneRebuild @('-Cycle','1','-RunName',("r_big_phone_c{0}" -f $Cycle),'-HostRootOverride',$host,'-SummaryRootOverride',$summary,'-LabelPrefix',("RBIG_C{0}" -f $Cycle),'-Execute');$r.Output|ForEach-Object{Log "PHONE=$_"};if($r.ExitCode -ne 0){throw 'PHONE_REBUILD_FAIL'}
  $s=Scope;if($s.qcrild2.pid -ne $ExpectedQcrild2 -or $s.qtidata.pid -ne $ExpectedQtidata){throw 'A_READY_VENDOR_GENERATION_CHANGED'};$debug=Root 'lshal debug vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot2 2>/dev/null';if((Latest-Constructor $debug) -ne $ExpectedGeneration){throw 'A_READY_NAH_GENERATION_CHANGED'};$body=Current-Nah $debug;if($body -notmatch '(?ms)apn=ims.*?networks=\[[^\]]*EUTRAN' -or $body -notmatch '(?m)^\s*apnType=IMS\s+prefNw=EUTRAN'){throw 'A_READY_NATIVE_PUBLICATION_LOST'};Log 'A_READY_BIG=PASS'
}

if($StaticAudit){Write-Host 'STATIC_NO_ADB=PASS';Write-Host 'HOLDER_TERM_MAX=1';Write-Host ("QCRILD2_RESTARTS={0}" -f $(if($Mode -eq 'UpperBound'){2}else{1}));Write-Host ("QTIDATASERVICES_TERMS={0}" -f $(if($Mode -eq 'UpperBound'){1}else{0}));Write-Host ("PHONE_TERMS={0}" -f $(if($Mode -eq 'UpperBound'){1}else{0}));Write-Host 'NATIVE_READY_TIMEOUT=120';Write-Host 'NATIVE_READY_STABLE_SAMPLES=10';exit 0}
if(-not $Execute){throw 'EXECUTE_REQUIRED'}
$before=Capture ("C{0}_{1}_BEFORE" -f $Cycle,$Mode.ToUpper());Assert-Target $before;if($before.environment.airplaneMode -ne 0){throw 'PREPARE_REQUIRES_AIRPLANE_OFF'}
$primary=(Scope).qcrild.pid;[void](Release-Holder);Ensure-PerMgrRunningNonOwner;$genA=Restart-Qcrild2 'A';if((Scope).qcrild.pid -ne $primary){throw 'PRIMARY_QCRILD_CHANGED'}
if($Mode -eq 'Minimal'){Write-Host "QCRILD2_GEN_A=$genA";Write-Host 'MINIMAL_NORMALIZATION=PASS';exit 0}
$qtidata=Restart-QtiDataServices $genA;$lowerBound=Get-Date;$genB=Restart-Qcrild2 'B';if($genB -eq $genA){throw 'QCRILD2_GEN_B_EQUALS_A'};$native=Wait-NativeReady $genB $qtidata $lowerBound;Rebuild-Phone $genB $qtidata $native.generation
$after=Capture ("C{0}_A_READY_BIG" -f $Cycle);Assert-Target $after
Write-Host "QCRILD2_GEN_A=$genA";Write-Host "QTIDATASERVICES_NEW_PID=$qtidata";Write-Host "QCRILD2_GEN_B=$genB";Write-Host "NAH_GENERATION=$($native.generation)";Write-Host 'R_BIG_V1_1=PASS'
