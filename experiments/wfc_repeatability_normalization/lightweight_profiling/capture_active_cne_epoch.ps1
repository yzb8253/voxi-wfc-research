[CmdletBinding()]
param(
  [string]$Serial='fd0ff892',
  [string]$OutputRoot=''
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$adb=Join-Path (Split-Path $repo -Parent) 'adb.exe'
$collector=Join-Path $PSScriptRoot 'capture_lightweight_state.ps1'
$epoch=[guid]::NewGuid().ToString()
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff'
if([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot=Join-Path (Split-Path $repo -Parent) ("voxi_wfc_local_runs\active_cne_semantics\{0}" -f $stamp)
}
[IO.Directory]::CreateDirectory($OutputRoot)|Out-Null

function Quote-Sh([string]$Value) {
  $single=[string][char]39;$double=[string][char]34
  $single+$Value.Replace($single,($single+$double+$single+$double+$single))+$single
}
function Invoke-Adb([string[]]$Arguments) {
  $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$adb
  $info.UseShellExecute=$false;$info.CreateNoWindow=$true
  $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
  $info.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){ '"'+$_.Replace('"','\"')+'"' }else{$_}})-join ' ')
  $process=[Diagnostics.Process]::new();$process.StartInfo=$info
  if(-not $process.Start()){throw 'Unable to start adb'}
  $stdout=$process.StandardOutput.ReadToEnd();$stderr=$process.StandardError.ReadToEnd();$process.WaitForExit()
  [pscustomobject]@{ExitCode=$process.ExitCode;Text=$stdout+$stderr}
}
function Read-Light([string]$Name) {
  $path=Join-Path $OutputRoot ($Name+'.json')
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $collector -Serial $Serial -OutputPath $path|Out-Host
  if($LASTEXITCODE -ne 0){throw "$Name capture failed"}
  Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
}
function Nullable-IntFromMatch([string]$Text,[string]$Pattern) {
  $m=[regex]::Match($Text,$Pattern)
  if($m.Success){return [int64]$m.Groups[1].Value}
  $null
}
function Find-CneImsRows([string]$Text) {
  @($Text -split "\r?\n"|Where-Object{
    $_ -match 'com\.qualcomm\.qti\.cne' -and $_ -match 'Capabilities:\s*IMS' -and $_ -match 'mSubId\s*=\s*11'
  })
}

$total=[Diagnostics.Stopwatch]::StartNew()
$hostStart=[DateTimeOffset]::Now
$lightA=Read-Light 'LIGHT_A'
$rawHostStart=[DateTimeOffset]::Now
$command='echo DEVICE_START_MS=$(date +%s%3N); echo QCRILD2_BEGIN; ps -A -o PID,PPID,NAME,ARGS | grep -E ''^ *[0-9]+ +1 +qcrild +qcrild -c 2$''; echo CONNECTIVITY_BEGIN; dumpsys connectivity; echo CONNECTIVITY_END; echo QCRILD2_END; ps -A -o PID,PPID,NAME,ARGS | grep -E ''^ *[0-9]+ +1 +qcrild +qcrild -c 2$''; echo DEVICE_END_MS=$(date +%s%3N)'
$raw=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $command)))
$rawHostEnd=[DateTimeOffset]::Now
if($raw.ExitCode -ne 0){throw "raw connectivity capture failed: $($raw.Text)"}
$rawPath=Join-Path $OutputRoot 'RAW_CONNECTIVITY.txt'
[IO.File]::WriteAllText($rawPath,$raw.Text,[Text.UTF8Encoding]::new($false))
$lightB=Read-Light 'LIGHT_B'
$hostEnd=[DateTimeOffset]::Now
$total.Stop()

$begin=$raw.Text.IndexOf('CONNECTIVITY_BEGIN')
$end=$raw.Text.IndexOf('CONNECTIVITY_END')
if($begin -lt 0 -or $end -le $begin){throw 'connectivity markers missing'}
$connectivity=$raw.Text.Substring($begin+20,$end-($begin+20))
$historyAt=$connectivity.IndexOf('mNetworkRequestInfoLogs')
$current=if($historyAt -ge 0){$connectivity.Substring(0,$historyAt)}else{$connectivity}
$history=if($historyAt -ge 0){$connectivity.Substring($historyAt)}else{''}
$currentRows=Find-CneImsRows $current
$historyRows=Find-CneImsRows $history
$currentRow=@($currentRows|Where-Object{$_ -match 'activeRequest:\s*\d+'})|Select-Object -First 1
$historyRow=@($historyRows|Where-Object{$_ -match 'activeRequest:\s*\d+'})|Select-Object -First 1
$currentRequest=if($currentRow){Nullable-IntFromMatch $currentRow 'NetworkRequest \[ REQUEST id=(\d+)'}else{$null}
$currentSatisfied=if($currentRow){Nullable-IntFromMatch $currentRow 'activeRequest:\s*(\d+)'}else{$null}
$historyRequest=if($historyRow){Nullable-IntFromMatch $historyRow 'NetworkRequest \[ REQUEST id=(\d+)'}else{$null}
$historySatisfied=if($historyRow){Nullable-IntFromMatch $historyRow 'activeRequest:\s*(\d+)'}else{$null}
$deviceStart=Nullable-IntFromMatch $raw.Text 'DEVICE_START_MS=(\d+)'
$deviceEnd=Nullable-IntFromMatch $raw.Text 'DEVICE_END_MS=(\d+)'
$rawQcrild2=@($raw.Text -split "\r?\n"|Where-Object{$_ -match '^\s*\d+\s+1\s+qcrild\s+qcrild -c 2\s*$'}|ForEach-Object{[int](($_.Trim()-split '\s+')[0])}|Select-Object -Unique)

$result=[ordered]@{
  schema='voxi-active-cne-semantics-v1'
  observationEpoch=$epoch
  hostStart=$hostStart.ToString('o');hostEnd=$hostEnd.ToString('o');elapsedMs=$total.ElapsedMilliseconds
  lightA=[ordered]@{hostStart=$lightA.capture.hostStartUtc;deviceStartMs=$lightA.capture.deviceStartMs;deviceEndMs=$lightA.capture.deviceEndMs;qcrild2Pid=$lightA.qcril.secondary.pid;requestId=$lightA.cne.requestId;satisfiedId=$lightA.cne.satisfiedId}
  raw=[ordered]@{hostStart=$rawHostStart.ToString('o');hostEnd=$rawHostEnd.ToString('o');deviceStartMs=$deviceStart;deviceEndMs=$deviceEnd;qcrild2Pids=$rawQcrild2;currentRows=@($currentRows);currentRequestId=$currentRequest;currentSatisfiedId=$currentSatisfied;historicalRows=@($historyRows);historicalRequestId=$historyRequest;historicalSatisfiedId=$historySatisfied;rawPath=$rawPath}
  lightB=[ordered]@{hostStart=$lightB.capture.hostStartUtc;deviceStartMs=$lightB.capture.deviceStartMs;deviceEndMs=$lightB.capture.deviceEndMs;qcrild2Pid=$lightB.qcril.secondary.pid;requestId=$lightB.cne.requestId;satisfiedId=$lightB.cne.satisfiedId}
}
$resultPath=Join-Path $OutputRoot 'RESULT.json'
[IO.File]::WriteAllText($resultPath,(($result|ConvertTo-Json -Depth 10)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
Write-Output "OBSERVATION_EPOCH=$epoch"
Write-Output "TOTAL_MS=$($total.ElapsedMilliseconds)"
Write-Output "LIGHT_A_REQUEST=$($lightA.cne.requestId) LIGHT_A_SATISFIED=$($lightA.cne.satisfiedId)"
Write-Output "RAW_CURRENT_REQUEST=$currentRequest RAW_CURRENT_SATISFIED=$currentSatisfied"
Write-Output "RAW_HISTORY_REQUEST=$historyRequest RAW_HISTORY_SATISFIED=$historySatisfied"
Write-Output "LIGHT_B_REQUEST=$($lightB.cne.requestId) LIGHT_B_SATISFIED=$($lightB.cne.satisfiedId)"
Write-Output "RESULT=$resultPath"
Write-Output 'PHONE_WRITES=0'
