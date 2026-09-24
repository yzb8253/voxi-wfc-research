[CmdletBinding()]
param(
  [ValidateRange(1,3)][int]$Cycle=1,
  [switch]$StaticAudit,
  [string]$RunName='r4b_3cycle_v3'
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Serial='fd0ff892'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$HostRoot=Join-Path (Split-Path $Repo -Parent) ("voxi_wfc_local_runs\reset_boundary_r4b\{0}" -f $RunName)
$MetadataPath=Join-Path $HostRoot ("cycle_{0}_native_publication_ready.json" -f $Cycle)
$R3Log=Join-Path $HostRoot ("cycle_{0}_r3.log" -f $Cycle)
$OutputPath=Join-Path $HostRoot ("cycle_{0}_post_r3_natural_query.json" -f $Cycle)
function Quote-Sh([string]$Value){$s=[string][char]39;$d=[string][char]34;$s+$Value.Replace($s,($s+$d+$s+$d+$s))+$s}
function Invoke-Adb([string[]]$Arguments){$i=[Diagnostics.ProcessStartInfo]::new();$i.FileName=$Adb;$i.UseShellExecute=$false;$i.CreateNoWindow=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true;$i.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){ '"'+$_.Replace('"','\"')+'"' }else{$_}})-join ' ');$p=[Diagnostics.Process]::new();$p.StartInfo=$i;if(-not $p.Start()){throw 'ADB_START_FAILED'};$o=$p.StandardOutput.ReadToEnd();$e=$p.StandardError.ReadToEnd();$p.WaitForExit();[pscustomobject]@{ExitCode=$p.ExitCode;Text=$o+$e}}
function Root([string]$Command){$r=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)));if($r.ExitCode -ne 0){throw "ROOT_READ_FAILED=$Command`n$($r.Text)"};$r.Text}
function Latest-Constructor([string]$Debug){$rows=@($Debug -split "\r?\n"|Where-Object{$_ -match '^\s*(?<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}) \[NAH\]constructor\s*$'});if($rows.Count -eq 0){return ''};$m=[regex]::Match($rows[-1].Trim(),'^(?<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})');$m.Groups['ts'].Value}

if($StaticAudit){
  Write-Host 'ACTIVE_GET_INJECTION=NO'
  Write-Host 'GENERATION_INVARIANT=HARD_GATE'
  Write-Host 'NATURAL_QUERY_NONEMPTY_IMS=HARD_GATE'
  Write-Host 'STALE_SERIAL_REJECTED=YES'
  Write-Host 'STATIC_NO_ADB=PASS'
  Write-Host 'PHONE_WRITES=0'
  exit 0
}
if(-not (Test-Path $MetadataPath) -or -not (Test-Path $R3Log)){throw 'POST_R3_REQUIRED_METADATA_MISSING'}
$pre=Get-Content -LiteralPath $MetadataPath -Raw|ConvertFrom-Json
$r3=Get-Content -LiteralPath $R3Log -Raw
$scope=[regex]::Match($r3,'R3_SCOPE_BEFORE phone=(?<old>\d+).*qcrild2=(?<qcrild2>\d+) qtidata=(?<qtidata>\d+)')
$ready=[regex]::Match($r3,'R3_READY=PASS oldPhone=(?<old>\d+) newPhone=(?<new>\d+)')
$write=[regex]::Match($r3,'(?m)^(?<host>\d{4}-\d{2}-\d{2}T[^ ]+) PHONE_WRITE=kill -TERM (?<old>\d+)')
if(-not $scope.Success -or -not $ready.Success -or -not $write.Success){throw 'POST_R3_TIMELINE_METADATA_MISSING'}
if([int]$scope.Groups['qcrild2'].Value -ne [int]$pre.qcrild2Pid -or [int]$scope.Groups['qtidata'].Value -ne [int]$pre.qtidataservicesPid){throw 'POST_R3_VENDOR_SCOPE_MISMATCH'}
$debug=Root 'lshal debug vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot2 2>/dev/null'
$postGeneration=Latest-Constructor $debug
if($postGeneration -ne [string]$pre.generationId){
  $result=[ordered]@{cycle=$Cycle;preGeneration=$pre.generationId;postGeneration=$postGeneration;result='NAH_GENERATION_CHANGED_DURING_R3';phoneOld=[int]$ready.Groups['old'].Value;phoneNew=[int]$ready.Groups['new'].Value}
  [IO.File]::WriteAllText($OutputPath,($result|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
  throw 'NAH_GENERATION_CHANGED_DURING_R3'
}
$hostWrite=[DateTimeOffset]::Parse($write.Groups['host'].Value,[Globalization.CultureInfo]::InvariantCulture)
$deviceSince=$hostWrite.ToString('MM-dd HH:mm:ss.000',[Globalization.CultureInfo]::InvariantCulture)
$logs=Root ("logcat -d -b all -v threadtime -T " + (Quote-Sh $deviceSince))
$serviceDump=Root 'dumpsys activity service all'
[IO.File]::WriteAllText((Join-Path $HostRoot ("cycle_{0}_post_r3_service_dump.txt" -f $Cycle)),$serviceDump,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $HostRoot ("cycle_{0}_post_r3_query_logcat.txt" -f $Cycle)),$logs,[Text.UTF8Encoding]::new($false))
$requests=@([regex]::Matches($serviceDump,'(?m)^(?<ts>\d{4}-\d{2}-\d{2}T\S+)\s+(?<serial>\d+) > REQUEST_GET_QUALIFIED_NETWORKS\s*$'))
if($requests.Count -eq 0){throw 'POST_R3_NATURAL_QUERY_UNOBSERVABLE'}
$request=$requests[-1]
$serial=$request.Groups['serial'].Value
$requestTime=[DateTimeOffset]::Parse($request.Groups['ts'].Value,[Globalization.CultureInfo]::InvariantCulture)
if($requestTime -le $hostWrite){throw "POST_R3_STALE_QUERY_SERIAL serial=$serial request=$requestTime r3=$hostWrite"}
$tail=$serviceDump.Substring($request.Index)
$next=[regex]::Match($tail,("(?ms)^\d{{4}}-\d{{2}}-\d{{2}}T\S+ getAllQualifiedNetworksResponse:(?<payload>.*?)^\d{{4}}-\d{{2}}-\d{{2}}T\S+ {0} > Response Processed\s*$" -f [regex]::Escape($serial)))
if(-not $next.Success){throw "POST_R3_QUERY_SENT_NO_MATCHED_RESPONSE serial=$serial"}
$payload=$next.Groups['payload'].Value.Trim()
$hasIms=($payload -match '(?i)IMS')
$hasNetwork=($payload -match '(?i)EUTRAN|IWLAN')
$processed=($tail -match ("(?m)^\d{{4}}-\d{{2}}-\d{{2}}T\S+ {0} > Response Processed\s*$" -f [regex]::Escape($serial)))
$updated=($tail -match '(?m)^\d{4}-\d{2}-\d{2}T\S+ get complete, Calling updateQualifiedNetworks')
$updateTypes=($tail -match '(?m)^\d{4}-\d{2}-\d{2}T\S+ Calling updateQualifiedNetworkTypes')
$result=[ordered]@{
  cycle=$Cycle;preGeneration=$pre.generationId;postGeneration=$postGeneration;generationInvariant=$true
  phoneOld=[int]$ready.Groups['old'].Value;phoneNew=[int]$ready.Groups['new'].Value
  qcrild2Pid=[int]$pre.qcrild2Pid;qtidataservicesPid=[int]$pre.qtidataservicesPid
  requestSerial=[int]$serial;requestTimestamp=$request.Groups['ts'].Value
  responsePayload=$payload;responseNonEmpty=([bool]$payload);responseHasIms=$hasIms;responseHasNetwork=$hasNetwork
  responseProcessed=$processed;updateQualifiedNetworks=$updated;updateQualifiedNetworkTypes=$updateTypes;activeGetInjected=$false
}
[IO.File]::WriteAllText($OutputPath,($result|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
if(-not $payload -or -not $hasIms -or -not $hasNetwork){throw 'CURRENT_GENERATION_QUERY_CONTRADICTION'}
if(-not $processed -or -not $updated){throw 'POST_R3_QUERY_PROCESSING_INCOMPLETE'}
Write-Host 'POST_R3_QUERY_READY=PASS'
Write-Host "G_PRE_R3=$($pre.generationId)"
Write-Host "G_POST_R3=$postGeneration"
Write-Host "SERIAL_POST_R3=$serial"
Write-Host "GET_RESPONSE_CONTENT=$payload"
Write-Host "QNS_UPDATE_QUALIFIED_NETWORKS=$updated"
Write-Host "QNS_UPDATE_QUALIFIED_NETWORK_TYPES=$updateTypes"
Write-Host 'ACTIVE_GET_INJECTION=NO'
Write-Host 'PHONE_WRITES=0'
