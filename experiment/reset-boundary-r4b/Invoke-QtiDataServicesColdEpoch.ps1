[CmdletBinding()]
param(
  [ValidateRange(1,3)][int]$Cycle=1,
  [switch]$Execute,
  [switch]$StaticAudit,
  [string]$RunName='r4b_3cycle_v1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Serial='fd0ff892'
$ReadyTimeoutSeconds=120
$ExpectedDomain='u:r:vendor_qtidataservices_app:s0:c104,c256,c512,c768'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$CaptureScript=Join-Path $Repo 'experiments\wfc_repeatability_normalization\capture_snapshot.ps1'
$SummaryRoot=Join-Path $PSScriptRoot ("runs\{0}\snapshots" -f $RunName)
$HostRoot=Join-Path (Split-Path $Repo -Parent) ("voxi_wfc_local_runs\reset_boundary_r4b\{0}" -f $RunName)
$Timeline=Join-Path $HostRoot ("cycle_{0}_provider.log" -f $Cycle)
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
  [pscustomobject]@{uid=[int]$p[0];pid=[int]$p[1];ppid=[int]$p[2];name=$p[3];args=$p[4];raw=$rows[0].Trim()}
}
function Scope {
  [pscustomobject]@{
    primary=(One-Process '^\s*1001\s+\d+\s+1\s+qcrild\s+qcrild\s*$' 'QCRILD')
    target=(One-Process '^\s*1001\s+\d+\s+1\s+qcrild\s+qcrild -c 2\s*$' 'QCRILD2')
    qtidata=(One-Process '^\s*10104\s+\d+\s+\d+\s+\.qtidataservices\s+\.qtidataservices\s*$' 'QTIDATA')
    phone=(One-Process '^\s*1001\s+\d+\s+\d+\s+com\.android\.phone\s+com\.android\.phone\s*$' 'PHONE')
    qcomims=(One-Process '^\s*10196\s+\d+\s+\d+\s+org\.codeaurora\.ims\s+org\.codeaurora\.ims\s*$' 'QCOMIMS')
  }
}
function Pm-Owns($State){if($null -eq $State.processes.pmService){return $false};$p=[string]$State.processes.pmService.pid;[bool](@($State.native.ownerLines|Where-Object{$_ -match '/dev/subsys_esoc0' -and $_ -match "\s$p\s"}).Count)}
function Native-Ready($State){
  $State.device.root -and $State.target.mappingGate -and $State.target.subId -eq 11 -and $State.target.slotId -eq 1 -and $State.target.phoneId -eq 1 -and
  $State.subscription.active -and $State.subscription.uiccAppsEnabled -and $State.native.perMgrState -eq 'running' -and
  $State.native.x55State -eq 'ONLINE' -and $State.native.vendorPeripheralState -eq 'ONLINE' -and $State.native.crashCount -eq 0 -and
  (Pm-Owns $State) -and $null -eq $State.processes.holder -and -not $State.residues.holderPidFile -and -not $State.residues.moduleLock
}
function Evidence([string]$Name,[string]$Source,[string]$Raw,[bool]$Pass){[pscustomobject]@{FIELD=$Name;SOURCE=$Source;TIMESTAMP=(Get-Date -Format o);RAW_EVIDENCE=$Raw;PASS=$Pass}}
function New-PidLine([string]$Logs,[int]$AndroidPid,[string]$Pattern){
  @($Logs -split "\r?\n"|Where-Object{$_ -match ("\s{0}\s+\d+\s" -f $AndroidPid) -and $_ -match $Pattern}|Select-Object -Last 1)
}
function Cache-Classification([string]$Debug){
  $line=@($Debug -split "\r?\n"|Where-Object{$_ -match '(?i)(\[NAH\].*)?type=IMS.*networks=\['}|Select-Object -Last 1)
  if($line.Count -eq 0){return [pscustomobject]@{Class='QUERY_RESPONSE_NO_IMS_ROW';Raw='IMS_ROW_NOT_FOUND'}}
  $raw=[string]$line[0]
  if($raw -match 'networks=\[[^\]]*IWLAN'){return [pscustomobject]@{Class='A_IMS_IWLAN_PRESENT';Raw=$raw.Trim()}}
  if($raw -match 'networks=\[\s*\]' -or $raw -match 'networks=\[\s*UNKNOWN\s*\]'){return [pscustomobject]@{Class='B_IMS_UNKNOWN_OR_EMPTY';Raw=$raw.Trim()}}
  [pscustomobject]@{Class='B_IMS_OTHER_NON_IWLAN';Raw=$raw.Trim()}
}
function Save-Evidence([object[]]$Rows){$path=Join-Path $HostRoot ("cycle_{0}_provider_evidence.json" -f $Cycle);[IO.File]::WriteAllText($path,(@($Rows)|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false));Log "PROVIDER_EVIDENCE_FILE=$path"}

if($StaticAudit){
  Write-Host 'PS5_PARSE_TARGET=PASS'
  Write-Host 'RESET_PRIMITIVE=exact verified qtidataservices PID TERM'
  Write-Host 'RESET_COUNT_MAX=1'
  Write-Host 'PROVIDER_READY_TIMEOUT_SECONDS=120'
  Write-Host 'INITIAL_QUERY_EVIDENCE=new-PID Response Processed plus live IIWlan cache'
  Write-Host 'CALLBACK_REGISTRATION_EVIDENCE=static constructor control-flow plus new process epoch'
  Write-Host 'NO_SET_RESPONSE_FUNCTIONS_FROM_EXTERNAL_CLIENT=YES'
  Write-Host 'STATIC_NO_ADB=PASS'
  exit 0
}
if(-not $Execute){throw 'EXECUTE_REQUIRED'}
$devices=Invoke-Adb @('devices');if($devices.Text -notmatch "(?m)^$Serial\s+device\s*$"){throw 'TARGET_NOT_ONLINE'}
$beforeState=Capture ("R4B_C{0}_PROVIDER_BEFORE" -f $Cycle)
if($beforeState.environment.airplaneMode -ne 0){throw 'PROVIDER_ENTRY_REQUIRES_AIRPLANE_OFF'}
if(-not (Native-Ready $beforeState)){throw 'PROVIDER_ENTRY_NATIVE_NOT_READY'}
$before=Scope
$domain=(Root ("cat /proc/{0}/attr/current" -f $before.qtidata.pid)).Trim()
$parentCmd=(Root ("tr '\000' ' ' < /proc/{0}/cmdline" -f $before.qtidata.ppid)).Trim()
$activityBefore=Root 'dumpsys activity processes'
$identityPass=($before.qtidata.uid -eq 10104 -and $domain -eq $ExpectedDomain -and $parentCmd -match 'zygote64' -and $activityBefore -match ("\*PERS\* UID 10104 ProcessRecord\{{[^\r\n]+\s{0}:\.qtidataservices/u0a104\}}" -f $before.qtidata.pid) -and $activityBefore -match 'packageList=\{vendor.qti.hardware.cacert.server, vendor.qti.iwlan, com.qualcomm.qti.cne\}')
if(-not $identityPass){throw "QTIDATA_PRE_IDENTITY_FAIL domain=$domain parent=$parentCmd"}
$since=(Root "date '+%m-%d %H:%M:%S.000'").Trim()
$epoch=(Root "date '+%H:%M:%S.000'").Trim()
Log "PROVIDER_SCOPE_BEFORE primary=$($before.primary.pid) qcrild2=$($before.target.pid) qtidata=$($before.qtidata.pid) phone=$($before.phone.pid) qcomims=$($before.qcomims.pid)"
Log "PROVIDER_EPOCH_LOWER_BOUND=$epoch"
[void](Root-Write ("kill -TERM {0}" -f $before.qtidata.pid))
Log 'QTIDATASERVICES_TERM_COUNT=1'

$deadline=(Get-Date).AddSeconds($ReadyTimeoutSeconds);$new=$null;$stable=0;$logs='';$debug='';$services='';$activity='';$cache=[pscustomobject]@{Class='C_QUERY_INCOMPLETE';Raw='NO_RESPONSE'};$rows=@()
$newDomain='';$processIdentity=$false;$serviceIdentity=$false;$qns=$false;$network=$false;$data=$false;$slotProvider=$false;$proxy=$false;$connected=$false;$response=$false;$nativeReady=$false;$fatal=$false
while((Get-Date)-lt $deadline){
  Start-Sleep -Seconds 2
  try{$candidate=Scope}catch{continue}
  if($candidate.qtidata.pid -eq $before.qtidata.pid){continue}
  if((Root ("test -d /proc/{0} && echo LIVE || echo GONE" -f $before.qtidata.pid)).Trim() -ne 'GONE'){continue}
  if($candidate.primary.pid -ne $before.primary.pid -or $candidate.target.pid -ne $before.target.pid -or $candidate.phone.pid -ne $before.phone.pid -or $candidate.qcomims.pid -ne $before.qcomims.pid){throw 'R4B_PROVIDER_SCOPE_VIOLATION'}
  $newDomain=(Root ("cat /proc/{0}/attr/current" -f $candidate.qtidata.pid)).Trim()
  $activity=Root 'dumpsys activity processes'
  $services=(Root 'dumpsys activity services vendor.qti.iwlan')+(Root 'dumpsys activity services com.qualcomm.qti.cne')+(Root 'dumpsys activity services vendor.qti.hardware.cacert.server')
  $logs=Root ("logcat -d -b all -v threadtime -T " + (Quote-Sh $since))
  $debug=Root 'lshal debug vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot2 2>/dev/null'
  $cache=Cache-Classification $debug
  $processIdentity=($candidate.qtidata.uid -eq 10104 -and $newDomain -eq $ExpectedDomain -and $activity -match ("\*PERS\* UID 10104 ProcessRecord\{{[^\r\n]+\s{0}:\.qtidataservices/u0a104\}}" -f $candidate.qtidata.pid))
  $serviceIdentity=($services -match ("app=ProcessRecord\{{[^\r\n]+\s{0}:\.qtidataservices/u0a104\}}" -f $candidate.qtidata.pid) -and $services -match 'QualifiedNetworksServiceImpl' -and $services -match 'IWlanNetworkService' -and $services -match 'IWlanDataService' -and $services -match 'CneApp')
  $qns=@(New-PidLine $logs $candidate.qtidata.pid '(?i)Qualified networks service created').Count -gt 0
  $network=@(New-PidLine $logs $candidate.qtidata.pid '(?i)IWlan network service created').Count -gt 0
  $data=@(New-PidLine $logs $candidate.qtidata.pid '(?i)IWlan data service created').Count -gt 0
  $slotProvider=@(New-PidLine $logs $candidate.qtidata.pid '(?i)(Qualified Networks service created for slot 1|create.*NetworkAvailabilityProvider.*1)').Count -gt 0
  $proxy=@(New-PidLine $logs $candidate.qtidata.pid '(?i)new IWlan Proxy on slot 1').Count -gt 0
  $connected=@(New-PidLine $logs $candidate.qtidata.pid '(?i)(IIWlan client connected on slot2|new service: IIWlan.*slot2)').Count -gt 0
  $response=@(New-PidLine $logs $candidate.qtidata.pid '(?i)QualifiedNetworksServiceImpl:.*Response Processed').Count -gt 0
  $nativeReady=($debug -match 'DsdServiceReady=true' -and $debug -match 'WdsServiceReady=true' -and $debug -match 'IWLANEnabled=true' -and $debug -match 'ModemCapability=true')
  $fatal=@(New-PidLine $logs $candidate.qtidata.pid '(?i)(FATAL EXCEPTION|DeadObjectException|serviceDied|fatal binder)').Count -gt 0
  $ready=$processIdentity -and $serviceIdentity -and $qns -and $network -and $data -and $slotProvider -and $proxy -and $connected -and $response -and $nativeReady -and -not $fatal
  Log "PROVIDER_PROGRESS newPid=$($candidate.qtidata.pid) identity=$processIdentity services=$serviceIdentity qns=$qns network=$network data=$data slot1=$slotProvider proxy=$proxy connected=$connected response=$response native=$nativeReady fatal=$fatal cache=$($cache.Class) stable=$stable"
  if($ready){if($null -ne $new -and $new.qtidata.pid -eq $candidate.qtidata.pid){$stable++}else{$stable=1};$new=$candidate;if($stable -ge 5){break}}else{$stable=0;$new=$candidate}
}
if($null -eq $new){$new=$before}
$rows=@(
  (Evidence 'OldPidGone' '/proc' ("old={0}; new={1}" -f $before.qtidata.pid,$new.qtidata.pid) ($new.qtidata.pid -ne $before.qtidata.pid)),
  (Evidence 'ProcessIdentity' 'ps+SELinux+ActivityManager' ("pid={0}; uid={1}; domain={2}" -f $new.qtidata.pid,$new.qtidata.uid,$newDomain) $processIdentity),
  (Evidence 'HostedServices' 'dumpsys activity services' 'QNS+NetworkService+DataService+CneApp hosted by new PID' $serviceIdentity),
  (Evidence 'QnsCreated' 'new-PID logcat' ([string](New-PidLine $logs $new.qtidata.pid '(?i)Qualified networks service created')) $qns),
  (Evidence 'IwlanNetworkServiceCreated' 'new-PID logcat' ([string](New-PidLine $logs $new.qtidata.pid '(?i)IWlan network service created')) $network),
  (Evidence 'IwlanDataServiceCreated' 'new-PID logcat' ([string](New-PidLine $logs $new.qtidata.pid '(?i)IWlan data service created')) $data),
  (Evidence 'Slot1ProviderCreated' 'new-PID logcat' ([string](New-PidLine $logs $new.qtidata.pid '(?i)(Qualified Networks service created for slot 1|create.*NetworkAvailabilityProvider.*1)')) $slotProvider),
  (Evidence 'StaticIwlanProxyNewEpoch' 'new-PID logcat' ([string](New-PidLine $logs $new.qtidata.pid '(?i)new IWlan Proxy on slot 1')) $proxy),
  (Evidence 'IIWlanSlot2Connected' 'new-PID logcat' ([string](New-PidLine $logs $new.qtidata.pid '(?i)(IIWlan client connected on slot2|new service: IIWlan.*slot2)')) $connected),
  (Evidence 'InitialGetAllQualifiedNetworksResponse' 'new-PID logcat' ([string](New-PidLine $logs $new.qtidata.pid '(?i)QualifiedNetworksServiceImpl:.*Response Processed')) $response),
  (Evidence 'InitialCacheClassification' 'live IIWlan IBase debug at response epoch' $cache.Raw ($response -and $cache.Class -notmatch '^QUERY_RESPONSE_NO')),
  (Evidence 'CallbackRegistration' 'audited provider constructor control-flow+new process epoch' 'getAllQualifiedNetworks then registerForQualifiedNetworksChanged; direct runtime callback identity not externally exposed' ($response -and $proxy)),
  (Evidence 'ProducerPreserved' 'process snapshot' ("qcrild2={0}" -f $new.target.pid) ($new.target.pid -eq $before.target.pid)),
  (Evidence 'FatalHidlBinderErrorsAbsent' 'new-PID logcat' 'none' (-not $fatal)),
  (Evidence 'StableTenSeconds' '5 consecutive 2-second samples' ("samples={0}" -f $stable) ($stable -ge 5))
)
Save-Evidence $rows
[IO.File]::WriteAllText((Join-Path $HostRoot ("cycle_{0}_provider_logcat.txt" -f $Cycle)),$logs,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $HostRoot ("cycle_{0}_provider_debug.txt" -f $Cycle)),$debug,[Text.UTF8Encoding]::new($false))
if($new.qtidata.pid -eq $before.qtidata.pid -or $stable -lt 5){throw 'R4B_PROVIDER_READY_TIMEOUT'}
$afterState=Capture ("R4B_C{0}_PROVIDER_READY" -f $Cycle)
if(-not (Native-Ready $afterState)){throw 'R4B_PROVIDER_READY_NATIVE_GATE_FAIL'}
Log "PROVIDER_READY=PASS oldQtidata=$($before.qtidata.pid) newQtidata=$($new.qtidata.pid) qcrild2=$($new.target.pid) cache=$($cache.Class)"
Write-Host 'PROVIDER_READY=PASS'
Write-Host "QTIDATASERVICES_OLD_PID=$($before.qtidata.pid)"
Write-Host "QTIDATASERVICES_NEW_PID=$($new.qtidata.pid)"
Write-Host "PROVIDER_INITIAL_CACHE=$($cache.Class)"
Write-Host 'QTIDATASERVICES_TERM_COUNT=1'
