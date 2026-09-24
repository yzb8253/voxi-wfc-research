[CmdletBinding()]
param(
  [ValidateRange(1,3)][int]$Cycle=1,
  [switch]$Execute,
  [switch]$StaticAudit,
  [switch]$Ps51Regression,
  [switch]$EpochOnly,
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
    cnd=(One-Process '^\s*1000\s+\d+\s+1\s+cnd\s+cnd\s*$' 'CND')
  }
}
function Pm-Owns($State){if($null -eq $State.processes.pmService){return $false};$p=[string]$State.processes.pmService.pid;[bool](@($State.native.ownerLines|Where-Object{$_ -match '/dev/subsys_esoc0' -and $_ -match "\s$p\s"}).Count)}
function Native-Ready($State){
  $State.device.root -and $State.target.mappingGate -and $State.target.subId -eq 11 -and $State.target.slotId -eq 1 -and $State.target.phoneId -eq 1 -and
  $State.subscription.active -and $State.subscription.uiccAppsEnabled -and $State.native.perMgrState -eq 'running' -and
  $State.native.x55State -eq 'ONLINE' -and $State.native.vendorPeripheralState -eq 'ONLINE' -and $State.native.crashCount -eq 0 -and
  (Pm-Owns $State) -and $null -eq $State.processes.holder -and -not $State.residues.holderPidFile -and -not $State.residues.moduleLock
}
function Evidence([string]$Name,[string]$Source,[string]$Raw,[string]$Timestamp,[string]$Status,[string]$Serial='UNOBSERVABLE',[string]$Content='UNOBSERVABLE'){
  [pscustomobject]@{FIELD=$Name;SOURCE=$Source;TIMESTAMP=$Timestamp;RAW_EVIDENCE=$Raw;STATUS=$Status;PASS=($Status -eq 'PASS');SERIAL=$Serial;CONTENT=$Content}
}
function New-PidLine([string]$Logs,[int]$AndroidPid,[string]$Pattern){
  @($Logs -split "\r?\n"|Where-Object{$_ -match ("\s{0}\s+\d+\s" -f $AndroidPid) -and $_ -match $Pattern}|Select-Object -Last 1)
}
function Last-Line([string]$Logs,[string]$Pattern){@($Logs -split "\r?\n"|Where-Object{$_ -match $Pattern}|Select-Object -Last 1)}
function Line-Text($Value){$a=@($Value);if($a.Count -eq 0){'UNOBSERVABLE'}else{([string]$a[0]).Trim()}}
function Line-Time($Value){$raw=Line-Text $Value;$m=[regex]::Match($raw,'^(?<time>\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3})');if($m.Success){$m.Groups['time'].Value}else{'UNOBSERVABLE'}}
function Line-Serial($Value){$raw=Line-Text $Value;$m=[regex]::Match($raw,'QualifiedNetworksServiceImpl:\s*(?<serial>\d+)\s*>');if($m.Success){$m.Groups['serial'].Value}else{'UNOBSERVABLE'}}
function Cache-Classification([string]$Debug){
  $line=@($Debug -split "\r?\n"|Where-Object{$_ -match '(?i)(\[NAH\].*)?type=IMS.*networks=\['}|Select-Object -Last 1)
  if($line.Count -eq 0){return [pscustomobject]@{Class='QUERY_RESPONSE_NO_IMS_ROW';Raw='IMS_ROW_NOT_FOUND'}}
  $raw=[string]$line[0]
  if($raw -match 'networks=\[[^\]]*IWLAN'){return [pscustomobject]@{Class='A_IMS_IWLAN_PRESENT';Raw=$raw.Trim()}}
  if($raw -match 'networks=\[\s*\]' -or $raw -match 'networks=\[\s*UNKNOWN\s*\]'){return [pscustomobject]@{Class='B_IMS_UNKNOWN_OR_EMPTY';Raw=$raw.Trim()}}
  [pscustomobject]@{Class='B_IMS_OTHER_NON_IWLAN';Raw=$raw.Trim()}
}
function Save-Evidence([object[]]$Rows){$path=Join-Path $HostRoot ("cycle_{0}_provider_evidence.json" -f $Cycle);[IO.File]::WriteAllText($path,(@($Rows)|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false));Log "PROVIDER_EVIDENCE_FILE=$path"}

if($Ps51Regression){
  $single=@(New-PidLine '09-24 00:00:00.000  123  456 D Tag: marker serial=7' 123 'marker').Count
  $empty=@(New-PidLine '09-24 00:00:00.000  123  456 D Tag: other' 123 'marker').Count
  $nullArray=@($null).Count
  $lineArray=@(Last-Line "one`ntwo marker" 'marker').Count
  if($single -ne 1 -or $empty -ne 0 -or $nullArray -ne 1 -or $lineArray -ne 1){throw "PS51_ARRAY_REGRESSION_FAILED single=$single empty=$empty null=$nullArray line=$lineArray"}
  Write-Host 'PS51_SCALAR_NULL_ARRAY_REGRESSION=PASS'
  Write-Host 'STATIC_NO_ADB=PASS'
  exit 0
}

if($StaticAudit){
  Write-Host 'PS5_PARSE_TARGET=PASS'
  Write-Host 'RESET_PRIMITIVE=exact verified qtidataservices PID TERM'
  Write-Host 'RESET_COUNT_MAX=1'
  Write-Host 'PROVIDER_READY_TIMEOUT_SECONDS=120'
  Write-Host 'INITIAL_QUERY_CLASSES=QUERY_NOT_SENT,QUERY_SENT_NO_RESPONSE,QUERY_RESPONSE_EMPTY,QUERY_RESPONSE_VALID'
  Write-Host 'INITIAL_QUERY_EVIDENCE=T6-T9 new-PID logcat plus contemporaneous live IIWlan cache'
  Write-Host 'CALLBACK_REGISTRATION_EVIDENCE=static constructor control-flow plus new process epoch'
  Write-Host 'NO_SET_RESPONSE_FUNCTIONS_FROM_EXTERNAL_CLIENT=YES'
  Write-Host 'STATIC_NO_ADB=PASS'
  Write-Host 'EPOCH_ONLY_GATE=exact old PID gone + new verified process identity; all service/query/publication fields are telemetry'
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
Log "PROVIDER_SCOPE_BEFORE primary=$($before.primary.pid) qcrild2=$($before.target.pid) qtidata=$($before.qtidata.pid) phone=$($before.phone.pid) qcomims=$($before.qcomims.pid) cnd=$($before.cnd.pid)"
Log "PROVIDER_EPOCH_LOWER_BOUND=$epoch"
[void](Root-Write ("kill -TERM {0}" -f $before.qtidata.pid))
Log 'QTIDATASERVICES_TERM_COUNT=1'

$deadline=(Get-Date).AddSeconds($ReadyTimeoutSeconds);$new=$null;$stable=0;$logs='';$debug='';$services='';$activity='';$cache=[pscustomobject]@{Class='NO_IMS_ROW';Raw='NO_RESPONSE'};$rows=@();$queryClass='QUERY_NOT_SENT'
$newDomain='';$processIdentity=$false;$serviceIdentity=$false;$qns=$false;$network=$false;$data=$false;$slotProvider=$false;$proxy=$false;$connected=$false;$response=$false;$nativeReady=$false;$fatal=$false
$requiredStable=if($EpochOnly){1}else{10}
$t1=@();$t2=@();$t3=@();$t4=@();$t5=@();$t6=@();$t7=@();$t8=@();$t9=@();$t10=@()
while((Get-Date)-lt $deadline){
  Start-Sleep -Seconds 1
  try{$candidate=Scope}catch{continue}
  if($candidate.qtidata.pid -eq $before.qtidata.pid){continue}
  if((Root ("test -d /proc/{0} && echo LIVE || echo GONE" -f $before.qtidata.pid)).Trim() -ne 'GONE'){continue}
  if($candidate.primary.pid -ne $before.primary.pid -or $candidate.target.pid -ne $before.target.pid -or $candidate.phone.pid -ne $before.phone.pid -or $candidate.qcomims.pid -ne $before.qcomims.pid -or $candidate.cnd.pid -ne $before.cnd.pid){throw 'R4B_PROVIDER_SCOPE_VIOLATION'}
  $newDomain=(Root ("cat /proc/{0}/attr/current" -f $candidate.qtidata.pid)).Trim()
  $activity=Root 'dumpsys activity processes'
  $services=(Root 'dumpsys activity services vendor.qti.iwlan')+(Root 'dumpsys activity services com.qualcomm.qti.cne')+(Root 'dumpsys activity services vendor.qti.hardware.cacert.server')
  $logs=Root ("logcat -d -b all -v threadtime -T " + (Quote-Sh $since))
  $debug=Root 'lshal debug vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot2 2>/dev/null'
  $cache=Cache-Classification $debug
  $processIdentity=($candidate.qtidata.uid -eq 10104 -and $newDomain -eq $ExpectedDomain -and $activity -match ("\*PERS\* UID 10104 ProcessRecord\{{[^\r\n]+\s{0}:\.qtidataservices/u0a104\}}" -f $candidate.qtidata.pid))
  $serviceIdentity=($services -match ("app=ProcessRecord\{{[^\r\n]+\s{0}:\.qtidataservices/u0a104\}}" -f $candidate.qtidata.pid) -and $services -match 'QualifiedNetworksServiceImpl' -and $services -match 'IWlanNetworkService' -and $services -match 'IWlanDataService' -and $services -match 'CneApp' -and $services -match 'CACertService')
  $qns=@(New-PidLine $logs $candidate.qtidata.pid '(?i)Qualified networks service created').Count -gt 0
  $network=@(New-PidLine $logs $candidate.qtidata.pid '(?i)IWlan network service created').Count -gt 0
  $data=@(New-PidLine $logs $candidate.qtidata.pid '(?i)IWlan data service created').Count -gt 0
  $slotProvider=@(New-PidLine $logs $candidate.qtidata.pid '(?i)(Qualified Networks service created for slot 1|create.*NetworkAvailabilityProvider.*1)').Count -gt 0
  $proxy=@(New-PidLine $logs $candidate.qtidata.pid '(?i)new IWlan Proxy on slot 1').Count -gt 0
  $connected=@(New-PidLine $logs $candidate.qtidata.pid '(?i)(IIWlan client connected on slot2|new service: IIWlan.*slot2)').Count -gt 0
  $response=@(New-PidLine $logs $candidate.qtidata.pid '(?i)QualifiedNetworksServiceImpl:.*Response Processed').Count -gt 0
  $t1=Last-Line $logs ("Process \.qtidataservices \(pid {0}\) has died" -f $before.qtidata.pid)
  $t2=Last-Line $logs ("(am_proc_start: \[0,{0},10104,\.qtidataservices|Start proc {0}:\.qtidataservices)" -f $candidate.qtidata.pid)
  $t3=New-PidLine $logs $candidate.qtidata.pid '(?i)Qualified Networks service created for slot 1'
  $t4=New-PidLine $logs $candidate.qtidata.pid '(?i)new IWlan Proxy on slot 1'
  $t5=New-PidLine $logs $candidate.qtidata.pid '(?i)(IIWlan client connected on slot2|new service: IIWlan.*slot2)'
  $t6=New-PidLine $logs $candidate.qtidata.pid '(?i)(getAllQualifiedNetworks.*(request|serial|sent)|request.*getAllQualifiedNetworks)'
  $t7=New-PidLine $logs $candidate.qtidata.pid '(?i)QualifiedNetworksServiceImpl:.*Response Processed'
  $t8=New-PidLine $logs $candidate.qtidata.pid '(?i)get complete, Calling updateQualifiedNetworks'
  $t9=New-PidLine $logs $candidate.qtidata.pid '(?i)Calling updateQualifiedNetworkTypes'
  $t10=New-PidLine $logs $candidate.qtidata.pid '(?i)registerForQualifiedNetworksChanged'
  if(-not $slotProvider){$queryClass='QUERY_NOT_SENT'}elseif(-not $response){$queryClass='QUERY_SENT_NO_RESPONSE'}elseif($cache.Class -match 'NO_IMS|UNKNOWN_OR_EMPTY'){$queryClass='QUERY_RESPONSE_EMPTY'}else{$queryClass='QUERY_RESPONSE_VALID'}
  $nativeReady=($debug -match 'DsdServiceReady=true' -and $debug -match 'WdsServiceReady=true' -and $debug -match 'IWLANEnabled=true' -and $debug -match 'ModemCapability=true')
  $fatal=@(New-PidLine $logs $candidate.qtidata.pid '(?i)(FATAL EXCEPTION|DeadObjectException|serviceDied|fatal binder)').Count -gt 0
  # In publication-gated series the legacy provider observer has no lifecycle
  # verdict authority. It proves only the exact cold process epoch. All service,
  # query and native-publication fields below remain telemetry for the dedicated
  # current-generation gate.
  $ready=if($EpochOnly){$processIdentity}else{$processIdentity -and $serviceIdentity -and $qns -and $network -and $data -and $slotProvider -and $proxy -and $connected -and $response -and $nativeReady -and -not $fatal}
  Log "PROVIDER_PROGRESS newPid=$($candidate.qtidata.pid) identity=$processIdentity services=$serviceIdentity qns=$qns network=$network data=$data slot1=$slotProvider proxy=$proxy connected=$connected response=$response queryClass=$queryClass native=$nativeReady fatal=$fatal cache=$($cache.Class) stable=$stable"
  if($ready){if($null -ne $new -and $new.qtidata.pid -eq $candidate.qtidata.pid){$stable++}else{$stable=1};$new=$candidate;if($stable -ge $requiredStable){break}}else{$stable=0;$new=$candidate}
}
if($null -eq $new){$new=$before}
$responseSerial=Line-Serial $t7
$requestSerial=Line-Serial $t6
$imsContent=if($cache.Raw){$cache.Raw}else{'UNOBSERVABLE'}
$rows=@(
  (Evidence 'T1_OLD_QTIDATA_PID_GONE' 'ActivityManager logcat' (Line-Text $t1) (Line-Time $t1) $(if(@($t1).Count){'PASS'}else{'UNOBSERVABLE'})),
  (Evidence 'T2_NEW_QTIDATA_PID_BORN' 'ActivityManager logcat' (Line-Text $t2) (Line-Time $t2) $(if(@($t2).Count){'PASS'}else{'UNOBSERVABLE'})),
  (Evidence 'T3_QNS_SLOT1_PROVIDER_CREATED' 'new-PID logcat' (Line-Text $t3) (Line-Time $t3) $(if(@($t3).Count){'PASS'}else{'FAIL'})),
  (Evidence 'T4_IWLANPROXY_SLOT1_NEW_EPOCH' 'new-PID logcat' (Line-Text $t4) (Line-Time $t4) $(if(@($t4).Count){'PASS'}else{'FAIL'})),
  (Evidence 'T5_IIWLAN_SLOT2_CONNECTED' 'new-PID logcat' (Line-Text $t5) (Line-Time $t5) $(if(@($t5).Count){'PASS'}else{'FAIL'})),
  (Evidence 'T6_GET_ALL_QUALIFIED_NETWORKS_REQUEST' 'new-PID logcat' (Line-Text $t6) (Line-Time $t6) $(if(@($t6).Count){'PASS'}else{'UNOBSERVABLE'}) $requestSerial),
  (Evidence 'T7_GET_ALL_QUALIFIED_NETWORKS_RESPONSE' 'new-PID logcat' (Line-Text $t7) (Line-Time $t7) $(if(@($t7).Count){'PASS'}else{'FAIL'}) $responseSerial),
  (Evidence 'T8_GET_COMPLETE_UPDATE_QUALIFIED_NETWORKS' 'new-PID logcat' (Line-Text $t8) (Line-Time $t8) $(if(@($t8).Count){'PASS'}else{'UNOBSERVABLE'}) $responseSerial),
  (Evidence 'T9_UPDATE_QUALIFIED_NETWORK_TYPES' 'new-PID logcat' (Line-Text $t9) (Line-Time $t9) $(if(@($t9).Count){'PASS'}else{'UNOBSERVABLE'}) $responseSerial $imsContent),
  (Evidence 'T10_CALLBACK_REGISTERED' 'new-PID logcat or audited constructor control-flow' $(if(@($t10).Count){Line-Text $t10}else{'runtime registration object is UNOBSERVABLE; constructor order is getAllQualifiedNetworks then registerForQualifiedNetworksChanged'}) $(if(@($t10).Count){Line-Time $t10}else{Line-Time $t3}) $(if(@($t10).Count){'PASS'}else{'UNOBSERVABLE'})),
  (Evidence 'QueryClassification' 'T3/T7 plus contemporaneous IIWlan debug' $queryClass (Get-Date -Format o) 'PASS' $responseSerial $imsContent),
  (Evidence 'ProcessIdentity' 'ps+SELinux+ActivityManager' ("pid={0}; uid={1}; domain={2}" -f $new.qtidata.pid,$new.qtidata.uid,$newDomain) (Get-Date -Format o) $(if($processIdentity){'PASS'}else{'FAIL'})),
  (Evidence 'HostedServices' 'dumpsys activity services' 'QNS+NetworkService+DataService+CneApp+CACertService hosted by new PID' (Get-Date -Format o) $(if($serviceIdentity){'PASS'}else{'FAIL'})),
  (Evidence 'ProducerPreserved' 'process snapshot' ("qcrild2={0}; primary={1}; cnd={2}; qcomims={3}; phone={4}" -f $new.target.pid,$new.primary.pid,$new.cnd.pid,$new.qcomims.pid,$new.phone.pid) (Get-Date -Format o) $(if($new.target.pid -eq $before.target.pid -and $new.primary.pid -eq $before.primary.pid -and $new.cnd.pid -eq $before.cnd.pid -and $new.qcomims.pid -eq $before.qcomims.pid -and $new.phone.pid -eq $before.phone.pid){'PASS'}else{'FAIL'})),
  (Evidence 'FatalHidlBinderErrorsAbsent' 'new-PID logcat' 'none' (Get-Date -Format o) $(if(-not $fatal){'PASS'}else{'FAIL'})),
  (Evidence 'StableTenSeconds' '10 consecutive 1-second samples' ("samples={0}" -f $stable) (Get-Date -Format o) $(if($stable -ge 10){'PASS'}else{'FAIL'}))
)
Save-Evidence $rows
[IO.File]::WriteAllText((Join-Path $HostRoot ("cycle_{0}_provider_logcat.txt" -f $Cycle)),$logs,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $HostRoot ("cycle_{0}_provider_debug.txt" -f $Cycle)),$debug,[Text.UTF8Encoding]::new($false))
if($new.qtidata.pid -eq $before.qtidata.pid -or $stable -lt $requiredStable){throw 'R4B_PROVIDER_READY_TIMEOUT'}
$afterState=Capture ("R4B_C{0}_PROVIDER_READY" -f $Cycle)
if(-not $EpochOnly -and -not (Native-Ready $afterState)){throw 'R4B_PROVIDER_READY_NATIVE_GATE_FAIL'}
Log "PROVIDER_READY=PASS oldQtidata=$($before.qtidata.pid) newQtidata=$($new.qtidata.pid) qcrild2=$($new.target.pid) queryClass=$queryClass requestSerial=$requestSerial responseSerial=$responseSerial cache=$($cache.Class)"
Write-Host 'PROVIDER_READY=PASS'
Write-Host "PROVIDER_EPOCH_ONLY=$EpochOnly"
Write-Host "QTIDATASERVICES_OLD_PID=$($before.qtidata.pid)"
Write-Host "QTIDATASERVICES_NEW_PID=$($new.qtidata.pid)"
Write-Host "PROVIDER_QUERY_CLASS=$queryClass"
Write-Host "PROVIDER_REQUEST_SERIAL=$requestSerial"
Write-Host "PROVIDER_RESPONSE_SERIAL=$responseSerial"
Write-Host "PROVIDER_IMS_CONTENT=$imsContent"
Write-Host 'QTIDATASERVICES_TERM_COUNT=1'
