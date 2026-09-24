[CmdletBinding()]
param(
  [ValidateRange(1,3)][int]$Cycle=1,
  [switch]$Execute,
  [switch]$StaticAudit,
  [string]$RunName='r4a_3cycle_v1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Serial='fd0ff892'
$ReadyTimeoutSeconds=120
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$CaptureScript=Join-Path $Repo 'experiments\wfc_repeatability_normalization\capture_snapshot.ps1'
$SummaryRoot=Join-Path $PSScriptRoot ("runs\{0}\snapshots" -f $RunName)
$HostRoot=Join-Path (Split-Path $Repo -Parent) ("voxi_wfc_local_runs\reset_boundary_r4a\{0}" -f $RunName)
$Timeline=Join-Path $HostRoot ("cycle_{0}_producer.log" -f $Cycle)
[IO.Directory]::CreateDirectory($SummaryRoot)|Out-Null
[IO.Directory]::CreateDirectory($HostRoot)|Out-Null

function Log([string]$Message){$line='{0} {1}' -f (Get-Date -Format o),$Message;Add-Content -LiteralPath $Timeline -Value $line -Encoding UTF8;Write-Host $line}
function Quote-Sh([string]$Value){$s=[string][char]39;$d=[string][char]34;$s+$Value.Replace($s,($s+$d+$s+$d+$s))+$s}
function Invoke-Adb([string[]]$Arguments){
  $i=[Diagnostics.ProcessStartInfo]::new();$i.FileName=$Adb;$i.UseShellExecute=$false;$i.CreateNoWindow=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true
  $i.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){ '"'+$_.Replace('"','\"')+'"' }else{$_}})-join ' ')
  $p=[Diagnostics.Process]::new();$p.StartInfo=$i;if(-not $p.Start()){throw 'ADB_START_FAILED'}
  $o=$p.StandardOutput.ReadToEnd();$e=$p.StandardError.ReadToEnd();$p.WaitForExit();[pscustomobject]@{ExitCode=$p.ExitCode;Text=$o+$e}
}
function Root([string]$Command){$r=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)));if($r.ExitCode -ne 0){throw "ROOT_READ_FAILED=$Command`n$($r.Text)"};$r.Text}
function Root-Write([string]$Command){if(-not $Execute){throw "DRY_RUN_BLOCKED_WRITE=$Command"};Log "PHONE_WRITE=$Command";$r=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)));if($r.ExitCode -ne 0){throw "PHONE_WRITE_FAILED=$Command`n$($r.Text)"};$r.Text}
function Child([string]$Path,[string[]]$Arguments){$old=$ErrorActionPreference;try{$ErrorActionPreference='Continue';$o=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments 2>&1);$rc=$LASTEXITCODE}finally{$ErrorActionPreference=$old};[pscustomobject]@{ExitCode=$rc;Output=$o}}
function Capture([string]$Label){
  $r=Child $CaptureScript @('-Label',$Label,'-Serial',$Serial,'-RunName',$RunName);$r.Output|ForEach-Object{Log "CAPTURE=$_"};if($r.ExitCode -ne 0){throw "CAPTURE_FAILED=$Label"}
  $generated=Join-Path $Repo ("experiments\wfc_repeatability_normalization\runs\{0}\snapshots\{1}.json" -f $RunName,$Label)
  $json=Get-Content -LiteralPath $generated -Raw
  [IO.File]::WriteAllText((Join-Path $SummaryRoot ($Label+'.json')),$json,[Text.UTF8Encoding]::new($false))
  $json|ConvertFrom-Json
}
function One-Process([string]$Pattern,[string]$Label){
  $rows=@((Root 'ps -A -o UID,PID,PPID,NAME,ARGS') -split "\r?\n"|Where-Object{$_ -match $Pattern})
  if($rows.Count -ne 1){throw "${Label}_IDENTITY_COUNT=$($rows.Count)"}
  $p=$rows[0].Trim() -split '\s+',5
  [pscustomobject]@{uid=[int]$p[0];pid=[int]$p[1];ppid=[int]$p[2];name=$p[3];args=$p[4]}
}
function Scope {
  [pscustomobject]@{
    primary=(One-Process '^\s*1001\s+\d+\s+1\s+qcrild\s+qcrild\s*$' 'QCRILD')
    target=(One-Process '^\s*1001\s+\d+\s+1\s+qcrild\s+qcrild -c 2\s*$' 'QCRILD2')
    qtidata=(One-Process '^\s*10104\s+\d+\s+\d+\s+\.qtidataservices\s+\.qtidataservices\s*$' 'QTIDATA')
    phone=(One-Process '^\s*1001\s+\d+\s+\d+\s+com\.android\.phone\s+com\.android\.phone\s*$' 'PHONE')
  }
}
function Pm-Owns($State){if($null -eq $State.processes.pmService){return $false};$p=[string]$State.processes.pmService.pid;[bool](@($State.native.ownerLines|Where-Object{$_ -match '/dev/subsys_esoc0' -and $_ -match "\s$p\s"}).Count)}
function Native-Ready($State){
  $State.device.root -and $State.target.mappingGate -and $State.target.subId -eq 11 -and $State.target.slotId -eq 1 -and $State.target.phoneId -eq 1 -and
  $State.subscription.active -and $State.subscription.uiccAppsEnabled -and $State.native.perMgrState -eq 'running' -and
  $State.native.x55State -eq 'ONLINE' -and $State.native.vendorPeripheralState -eq 'ONLINE' -and $State.native.crashCount -eq 0 -and
  (Pm-Owns $State) -and $null -eq $State.processes.holder -and -not $State.residues.holderPidFile -and -not $State.residues.moduleLock
}

if($StaticAudit){
  Write-Host 'PS5_PARSE_TARGET=PASS'
  Write-Host 'RESET_PRIMITIVE=setprop ctl.restart vendor.qcrild2'
  Write-Host 'RESET_COUNT_MAX=1'
  Write-Host 'PRODUCER_READY_TIMEOUT_SECONDS=120'
  Write-Host 'PRODUCER_ORDER=NATIVE_BEFORE_FRAMEWORK'
  Write-Host 'STATIC_NO_ADB=PASS'
  exit 0
}

$devices=Invoke-Adb @('devices');if($devices.Text -notmatch "(?m)^$Serial\s+device\s*$"){throw 'TARGET_NOT_ONLINE'}
$beforeState=Capture ("R4A_C{0}_PRODUCER_BEFORE" -f $Cycle)
if($beforeState.environment.airplaneMode -ne 0){throw 'PRODUCER_ENTRY_REQUIRES_AIRPLANE_OFF'}
if(-not (Native-Ready $beforeState)){throw 'PRODUCER_ENTRY_NATIVE_NOT_READY'}
$before=Scope
$since=(Root "date '+%m-%d %H:%M:%S.000'").Trim()
Log "PRODUCER_SCOPE_BEFORE primary=$($before.primary.pid) qcrild2=$($before.target.pid) qtidata=$($before.qtidata.pid) phone=$($before.phone.pid)"
[void](Root-Write 'setprop ctl.restart vendor.qcrild2')
Log 'QCRILD2_RESTART_COUNT=1'

$deadline=(Get-Date).AddSeconds($ReadyTimeoutSeconds)
$new=$null;$debug='';$logs='';$services='';$stable=0
while((Get-Date)-lt $deadline){
  Start-Sleep -Seconds 2
  try{$candidate=Scope}catch{continue}
  if($candidate.target.pid -eq $before.target.pid){continue}
  if((Root ("test -d /proc/{0} && echo LIVE || echo GONE" -f $before.target.pid)).Trim() -ne 'GONE'){continue}
  if($candidate.primary.pid -ne $before.primary.pid -or $candidate.qtidata.pid -ne $before.qtidata.pid -or $candidate.phone.pid -ne $before.phone.pid){throw 'R4A_PRODUCER_SCOPE_VIOLATION'}
  $inventory=Root "lshal 2>/dev/null | grep -F 'vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot2' || true"
  if($inventory -notmatch 'IIWlan/slot2'){continue}
  $debug=Root 'lshal debug vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot2 2>/dev/null'
  $logs=Root ("logcat -d -b all -v threadtime -T " + (Quote-Sh $since))
  $services=Root "dumpsys activity services vendor.qti.iwlan | grep -E 'QualifiedNetworksServiceImpl|IWlanNetworkService|IWlanDataService' || true"
  $coldInit=($logs -match 'performDataModuleInitialization')
  $nah=($logs -match '(NetworkAvailabilityHandler|\[NAH\]constructor)')
  $endpoints=($debug -match 'DsdServiceReady=true' -and $debug -match 'WdsServiceReady=true')
  $capability=($debug -match 'ModemCapability=true')
  $iwlan=($debug -match 'IWLANEnabled=true')
  $provider=($services -match 'QualifiedNetworksServiceImpl' -and $services -match 'IWlanNetworkService' -and $services -match 'IWlanDataService')
  Log "PRODUCER_PROGRESS newPid=$($candidate.target.pid) coldInit=$coldInit nah=$nah endpoints=$endpoints capability=$capability iwlan=$iwlan provider=$provider stable=$stable"
  if($coldInit -and $nah -and $endpoints -and $capability -and $iwlan -and $provider){
    if($null -ne $new -and $new.target.pid -eq $candidate.target.pid){$stable++}else{$stable=1}
    $new=$candidate
    if($stable -ge 5){break}
  }else{$stable=0;$new=$candidate}
}
if($null -eq $new -or $new.target.pid -eq $before.target.pid -or $stable -lt 5){throw 'R4A_PRODUCER_READY_TIMEOUT'}
$afterState=Capture ("R4A_C{0}_PRODUCER_READY" -f $Cycle)
if(-not (Native-Ready $afterState)){throw 'R4A_PRODUCER_READY_NATIVE_GATE_FAIL'}
[IO.File]::WriteAllText((Join-Path $HostRoot ("cycle_{0}_producer_logcat.txt" -f $Cycle)),$logs,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $HostRoot ("cycle_{0}_producer_debug.txt" -f $Cycle)),$debug,[Text.UTF8Encoding]::new($false))
Log "PRODUCER_READY=PASS oldQcrild2=$($before.target.pid) newQcrild2=$($new.target.pid) qtidataUnchanged=$($new.qtidata.pid)"
Write-Host 'PRODUCER_READY=PASS'
Write-Host "QCRILD2_OLD_PID=$($before.target.pid)"
Write-Host "QCRILD2_NEW_PID=$($new.target.pid)"
Write-Host "QTIDATASERVICES_PID_UNCHANGED=$($new.qtidata.pid)"
Write-Host 'QCRILD2_RESTART_COUNT=1'

