[CmdletBinding()]
param(
  [ValidateRange(1,3)][int]$Cycle=1,
  [switch]$StaticAudit,
  [string]$RunName='r4b_3cycle_v3'
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Serial='fd0ff892'
$ReadyTimeoutSeconds=120
$StableSamplesRequired=10
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$HostRoot=Join-Path (Split-Path $Repo -Parent) ("voxi_wfc_local_runs\reset_boundary_r4b\{0}" -f $RunName)
$ProviderLog=Join-Path $HostRoot ("cycle_{0}_provider.log" -f $Cycle)
$MetadataPath=Join-Path $HostRoot ("cycle_{0}_native_publication_ready.json" -f $Cycle)
$Timeline=Join-Path $HostRoot ("cycle_{0}_native_publication.log" -f $Cycle)
[IO.Directory]::CreateDirectory($HostRoot)|Out-Null

function Log([string]$Message){$line='{0} {1}' -f (Get-Date -Format o),$Message;Add-Content -LiteralPath $Timeline -Value $line -Encoding UTF8;Write-Host $line}
function Quote-Sh([string]$Value){$s=[string][char]39;$d=[string][char]34;$s+$Value.Replace($s,($s+$d+$s+$d+$s))+$s}
function Invoke-Adb([string[]]$Arguments){$i=[Diagnostics.ProcessStartInfo]::new();$i.FileName=$Adb;$i.UseShellExecute=$false;$i.CreateNoWindow=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true;$i.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){ '"'+$_.Replace('"','\"')+'"' }else{$_}})-join ' ');$p=[Diagnostics.Process]::new();$p.StartInfo=$i;if(-not $p.Start()){throw 'ADB_START_FAILED'};$o=$p.StandardOutput.ReadToEnd();$e=$p.StandardError.ReadToEnd();$p.WaitForExit();[pscustomobject]@{ExitCode=$p.ExitCode;Text=$o+$e}}
function Root([string]$Command){$r=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)));if($r.ExitCode -ne 0){throw "ROOT_READ_FAILED=$Command`n$($r.Text)"};$r.Text}
function One-Pid([string]$Pattern,[string]$Label){$rows=@((Root 'ps -A -o UID,PID,PPID,NAME,ARGS') -split "\r?\n"|Where-Object{$_ -match $Pattern});if($rows.Count -ne 1){throw "${Label}_IDENTITY_COUNT=$($rows.Count)"};[int](($rows[0].Trim() -split '\s+',5)[1])}
function Current-Nah([string]$Debug){$m=[regex]::Match($Debug,'(?ms)^NetworkAvailabilityHandler:\s*(?<body>.*?)^NetworkServiceHandler:');if(-not $m.Success){return ''};$m.Groups['body'].Value}
function Latest-Constructor([string]$Debug){$rows=@($Debug -split "\r?\n"|Where-Object{$_ -match '^\s*(?<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}) \[NAH\]constructor\s*$'});if($rows.Count -eq 0){return $null};$raw=$rows[-1].Trim();$m=[regex]::Match($raw,'^(?<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})');[pscustomobject]@{Raw=$raw;Timestamp=$m.Groups['ts'].Value}}
function Working-Ims([string]$Body){[regex]::Match($Body,'(?ms)apn=ims\s+hasPendingIntent=(?<pending>\S+).*?apn types=\[(?<types>[^\]]*IMS[^\]]*)\]\s+networks=\[(?<networks>[^\]]+)\]')}
function Reported-Ims([string]$Body){[regex]::Match($Body,'(?m)^\s*apnType=IMS\s+prefNw=(?<network>\S+)\s*$')}
function Native-Clean {
  $text=Root "getprop init.svc.vendor.per_mgr; getprop vendor.peripheral.SDX55M.state; cat /sys/bus/msm_subsys/devices/subsys10/state; cat /sys/bus/msm_subsys/devices/subsys10/crash_count; pidof pm-service; lsof /dev/subsys_esoc0 2>/dev/null || true"
  $lines=@($text -split "\r?\n"|Where-Object{$_.Trim().Length})
  if($lines.Count -lt 5){return $false}
  $pm=[string]$lines[4].Trim()
  if($pm -notmatch '^\d+$'){return $false}
  $owners=@($lines|Where-Object{$_ -match '/dev/subsys_esoc0'})
  $lines[0].Trim() -eq 'running' -and $lines[1].Trim() -eq 'ONLINE' -and $lines[2].Trim() -eq 'ONLINE' -and $lines[3].Trim() -eq '0' -and $owners.Count -eq 1 -and $owners[0] -match ("^pm-service\s+{0}\s" -f $pm)
}

if($StaticAudit){
  Write-Host 'NATIVE_PUBLICATION_TIMEOUT_SECONDS=120'
  Write-Host 'STABLE_SAMPLES=10'
  Write-Host 'ACTIVE_GET_INJECTION=NO'
  Write-Host 'CURRENT_NAH_SECTION_ONLY=YES'
  Write-Host 'STALE_LOCAL_LOG_REJECTED=YES'
  Write-Host 'STATIC_NO_ADB=PASS'
  Write-Host 'PHONE_WRITES=0'
  exit 0
}

if(-not (Test-Path -LiteralPath $ProviderLog)){throw 'PROVIDER_LOG_MISSING'}
$providerText=Get-Content -LiteralPath $ProviderLog -Raw
$epochMatch=[regex]::Match($providerText,'PROVIDER_EPOCH_LOWER_BOUND=(?<time>\d{2}:\d{2}:\d{2}\.\d{3})')
$readyMatch=[regex]::Match($providerText,'PROVIDER_READY=PASS oldQtidata=(?<old>\d+) newQtidata=(?<new>\d+) qcrild2=(?<qcrild2>\d+)')
if(-not $epochMatch.Success -or -not $readyMatch.Success){throw 'PROVIDER_EPOCH_METADATA_MISSING'}
$expectedQtidata=[int]$readyMatch.Groups['new'].Value
$expectedQcrild2=[int]$readyMatch.Groups['qcrild2'].Value
$epochTime=[TimeSpan]::Parse($epochMatch.Groups['time'].Value)
$deadline=(Get-Date).AddSeconds($ReadyTimeoutSeconds)
$stable=0;$accepted=$null;$lastDebug='';$lastBody='';$lastWorking=$null;$lastReported=$null
while((Get-Date)-lt $deadline){
  Start-Sleep -Seconds 1
  $qtidata=One-Pid '^\s*10104\s+\d+\s+\d+\s+\.qtidataservices\s+\.qtidataservices\s*$' 'QTIDATA'
  $qcrild2=One-Pid '^\s*1001\s+\d+\s+1\s+qcrild\s+qcrild -c 2\s*$' 'QCRILD2'
  if($qtidata -ne $expectedQtidata -or $qcrild2 -ne $expectedQcrild2){throw "NATIVE_PUBLICATION_SCOPE_CHANGED qtidata=$qtidata qcrild2=$qcrild2"}
  $debug=Root 'lshal debug vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot2 2>/dev/null'
  $constructor=Latest-Constructor $debug
  $body=Current-Nah $debug
  $working=Working-Ims $body
  $reported=Reported-Ims $body
  $fresh=$false
  if($null -ne $constructor){$constructorTime=[DateTime]::ParseExact($constructor.Timestamp,'yyyy-MM-dd HH:mm:ss.fff',[Globalization.CultureInfo]::InvariantCulture);$fresh=($constructorTime.TimeOfDay -ge $epochTime)}
  $workingReady=($working.Success -and $working.Groups['networks'].Value -match 'EUTRAN')
  $reportedReady=($reported.Success -and $reported.Groups['network'].Value -eq 'EUTRAN')
  $clean=Native-Clean
  $ready=$fresh -and $workingReady -and $reportedReady -and $clean
  Log "NATIVE_PUBLICATION_PROGRESS generation=$(if($constructor){$constructor.Timestamp}else{'NONE'}) fresh=$fresh working=$workingReady reported=$reportedReady nativeClean=$clean qcrild2=$qcrild2 qtidata=$qtidata stable=$stable"
  if($ready){
    if($null -ne $accepted -and $accepted.Timestamp -eq $constructor.Timestamp){$stable++}else{$stable=1}
    $accepted=$constructor;$lastDebug=$debug;$lastBody=$body;$lastWorking=$working;$lastReported=$reported
    if($stable -ge $StableSamplesRequired){break}
  }else{$stable=0;$accepted=$null}
}
if($stable -lt $StableSamplesRequired -or $null -eq $accepted){
  Log 'NATIVE_PUBLICATION_NOT_READY'
  throw 'NATIVE_PUBLICATION_NOT_READY'
}
$metadata=[ordered]@{
  cycle=$Cycle;runName=$RunName;generationId=$accepted.Timestamp;constructorRaw=$accepted.Raw
  publicationReadyAt=(Get-Date -Format o);stableSamples=$stable
  qcrild2Pid=$expectedQcrild2;qtidataservicesPid=$expectedQtidata
  workingImsNetworks=$lastWorking.Groups['networks'].Value
  workingImsTypes=$lastWorking.Groups['types'].Value
  workingHasPendingIntent=$lastWorking.Groups['pending'].Value
  lastReportedIms=$lastReported.Groups['network'].Value
  activeGetInjected=$false
}
[IO.File]::WriteAllText($MetadataPath,($metadata|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $HostRoot ("cycle_{0}_native_publication_debug.txt" -f $Cycle)),$lastDebug,[Text.UTF8Encoding]::new($false))
Log "NATIVE_PUBLICATION_READY generation=$($accepted.Timestamp) working=$($metadata.workingImsNetworks) lastReported=$($metadata.lastReportedIms) qcrild2=$expectedQcrild2 qtidata=$expectedQtidata"
Write-Host 'NATIVE_PUBLICATION_READY=PASS'
Write-Host "NAH_GENERATION=$($accepted.Timestamp)"
Write-Host "WORKING_IMS_NETWORKS=$($metadata.workingImsNetworks)"
Write-Host "LAST_REPORTED_IMS=$($metadata.lastReportedIms)"
Write-Host 'ACTIVE_GET_INJECTION=NO'
Write-Host 'PHONE_WRITES=0'
