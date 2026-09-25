[CmdletBinding()]
param(
  [string]$Serial='fd0ff892',
  [ValidateRange(1,5)][int]$Cycles=5,
  [ValidateRange(30,120)][int]$BetweenCycleSettleSeconds=60
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$Stable=Join-Path $Repo 'experiments\wfc_repeatability_normalization\v262_freeze_run\X55-WFC-STABLE-v1.ps1'
$Collector=Join-Path $PSScriptRoot 'capture_lightweight_state.ps1'
$Classifier=Join-Path $PSScriptRoot 'classify_lightweight_state.ps1'
$RunId=(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$OutputRoot=Join-Path (Split-Path $Repo -Parent) (Join-Path 'voxi_wfc_local_runs\shadow_integration' $RunId)
[IO.Directory]::CreateDirectory($OutputRoot)|Out-Null
$env:VOXI_SHADOW_RUN_ID=$RunId
$phoneWrites=0
$results=@()

function Quote-Sh([string]$Value) {
  $single=[string][char]39;$double=[string][char]34
  $single+$Value.Replace($single,($single+$double+$single+$double+$single))+$single
}
function Invoke-Adb([string[]]$Arguments) {
  $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$Adb;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
  $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
  $info.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){'"'+$_.Replace('"','\"')+'"'}else{$_}})-join ' ')
  $p=[Diagnostics.Process]::new();$p.StartInfo=$info;if(-not $p.Start()){throw 'Unable to start adb'}
  $out=$p.StandardOutput.ReadToEnd()+$p.StandardError.ReadToEnd();$p.WaitForExit();$rc=$p.ExitCode;$p.Dispose()
  [pscustomobject]@{ExitCode=$rc;Text=$out.Trim()}
}
function Root-Read([string]$Command) {
  $r=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)))
  if($r.ExitCode -ne 0){throw "Root read failed: $Command"};$r.Text
}
function Root-Write([string]$Command) {
  $r=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)))
  if($r.ExitCode -ne 0){throw "Root write failed: $Command"};$script:phoneWrites++;$r.Text
}
function Capture-PostHealth([int]$Cycle) {
  Start-Sleep -Seconds 30
  $path=Join-Path $OutputRoot ("cycle_{0}_post30_light.json" -f $Cycle)
  $timer=[Diagnostics.Stopwatch]::StartNew();& $Collector -Serial $Serial -OutputPath $path|Out-Host;$timer.Stop()
  $state=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
  $classification=((& $Classifier -InputPath $path -OutputFormat Json)|ConvertFrom-Json)
  $network=Root-Read 'dumpsys connectivity'
  $index=$network.IndexOf('mNetworkRequestInfoLogs');$current=if($index -ge 0){$network.Substring(0,$index)}else{$network}
  $line=@($current -split "\r?\n"|Where-Object{$_ -match 'activeRequest:' -and $_ -match 'com\.qualcomm\.qti\.cne' -and $_ -match 'Capabilities:\s*IMS' -and $_ -match 'mSubId\s*=\s*11'})|Select-Object -First 1
  $request=$null;$satisfied=$null
  if($line -match 'NetworkRequest \[ REQUEST id=(\d+)'){$request=[int]$Matches[1]}
  if($line -match 'activeRequest:\s*(\d+)'){$satisfied=[int]$Matches[1]}
  $match=($request -eq $state.cne.requestId -and $satisfied -eq $state.cne.satisfiedId)
  $record=[pscustomobject][ordered]@{cycle=$Cycle;postDelaySeconds=30;elapsedMs=$timer.ElapsedMilliseconds;classification=$classification;state=$state;oldCurrentRequestId=$request;oldSatisfiedId=$satisfied;cneIdsMatch=$match}
  $record|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $OutputRoot ("cycle_{0}_post30.json" -f $Cycle)) -Encoding UTF8
  if(@($classification.errors).Count -ne 0){throw "POST30_LIGHTWEIGHT_ERROR cycle=$Cycle"}
  if($classification.classification -ne 'HEALTHY_FREEZE'){throw "POST30_HEALTH_NOT_STABLE cycle=$Cycle result=$($classification.classification)"}
  if(-not $match){throw "POST30_CNE_ID_MISMATCH cycle=$Cycle"}
  $record
}

$devices=Invoke-Adb @('devices')
if($devices.Text -notmatch "(?m)^$([regex]::Escape($Serial))\s+device\s*$"){throw "ADB target not online: $Serial"}
if((Root-Read 'id') -notmatch 'uid=0\(root\)'){throw 'Root unavailable'}
if((Root-Read 'settings get global airplane_mode_on').Trim() -ne '0'){throw 'Initial airplane mode must be OFF'}

for($cycle=1;$cycle -le $Cycles;$cycle++) {
  $env:VOXI_SHADOW_CYCLE=[string]$cycle
  $stdout=Join-Path $OutputRoot ("cycle_{0}_wrapper_stdout.log" -f $cycle)
  $stderr=Join-Path $OutputRoot ("cycle_{0}_wrapper_stderr.log" -f $cycle)
  $timer=[Diagnostics.Stopwatch]::StartNew()
  $args='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$Stable+'" -Serial '+$Serial
  $process=Start-Process -FilePath 'powershell.exe' -ArgumentList $args -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  while(-not $process.HasExited){Start-Sleep -Seconds 1;$process.Refresh()}
  $process.WaitForExit()
  $timer.Stop()
  $text=(Get-Content -LiteralPath $stdout -Raw)+(Get-Content -LiteralPath $stderr -Raw)
  if($process.ExitCode -ne 0){throw "SHADOW_RECOVERY_FAILED cycle=$cycle exit=$($process.ExitCode)"}
  if($text -notmatch 'FINAL=WFC_HEALTHY_FREEZE'){throw "SHADOW_RECOVERY_NO_HEALTHY_MARKER cycle=$cycle"}
  $post=Capture-PostHealth $cycle
  $offCount=@([regex]::Matches($text,'SIM cycle 1: POWER OFF accepted')).Count
  $onCount=@([regex]::Matches($text,'SIM cycle 1: single POWER ON sent')).Count
  $attempt=if($text -match 'ATTEMPT=(\d+) SUCCESS'){[int]$Matches[1]}elseif($text -match 'DEEP_FALLBACK=SUCCESS'){'DEEP'}else{'PRE_CORE'}
  $results += [pscustomobject][ordered]@{cycle=$cycle;wrapperExit=$process.ExitCode;recoveryElapsedMs=$timer.ElapsedMilliseconds;attempt=$attempt;simOffCount=$offCount;simOnCount=$onCount;post30Classification=$post.classification.classification;post30CneMatch=$post.cneIdsMatch}
  $results|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $OutputRoot 'cycle_results.json') -Encoding UTF8
  if($cycle -lt $Cycles) {
    [void](Root-Write 'cmd connectivity airplane-mode disable')
    Start-Sleep -Seconds $BetweenCycleSettleSeconds
    if((Root-Read 'settings get global airplane_mode_on').Trim() -ne '0'){throw "NEXT_CYCLE_AIRPLANE_OFF_FAILED after=$cycle"}
  }
}

$summary=[pscustomobject][ordered]@{schema='voxi-wfc-phase18-shadow-run-v1';runId=$RunId;cyclesRequested=$Cycles;cyclesCompleted=@($results).Count;phoneWritesByDriver=$phoneWrites;results=$results}
$summaryPath=Join-Path $OutputRoot 'run_summary.json'
$summary|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Output "SHADOW_RUN=$RunId"
Write-Output "SUMMARY=$summaryPath"
Write-Output "CYCLES_COMPLETED=$(@($results).Count)"
Write-Output "DRIVER_PHONE_WRITES=$phoneWrites"
