[CmdletBinding()]
param(
  [string]$Serial='fd0ff892',
  [Parameter(Mandatory=$true)][string]$Label,
  [Parameter(Mandatory=$true)][ValidateSet('A0_READY','P0_READY','FROZEN_RESIDUE','HEALTHY_FREEZE','UNKNOWN')][string]$OldResult,
  [Parameter(Mandatory=$true)][string]$FullSummaryPath,
  [Parameter(Mandatory=$true)][string]$FullRawPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Collector=Join-Path $PSScriptRoot 'capture_lightweight_state.ps1'
$Classifier=Join-Path $PSScriptRoot 'classify_lightweight_state.ps1'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$runId=if([string]::IsNullOrWhiteSpace($env:VOXI_SHADOW_RUN_ID)){(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')}else{$env:VOXI_SHADOW_RUN_ID}
$cycle=if([string]::IsNullOrWhiteSpace($env:VOXI_SHADOW_CYCLE)){'standalone'}else{$env:VOXI_SHADOW_CYCLE}
$OutputRoot=Join-Path (Split-Path $Repo -Parent) (Join-Path 'voxi_wfc_local_runs\shadow_integration' $runId)
[IO.Directory]::CreateDirectory($OutputRoot)|Out-Null
$safeLabel=($Label -replace '[^A-Za-z0-9_.-]','_')
$lightPath=Join-Path $OutputRoot ("cycle_{0}_{1}_light.json" -f $cycle,$safeLabel)

if(-not (Test-Path -LiteralPath $FullSummaryPath)){throw "Full summary missing: $FullSummaryPath"}
if(-not (Test-Path -LiteralPath $FullRawPath)){throw "Full raw directory missing: $FullRawPath"}

$timer=[Diagnostics.Stopwatch]::StartNew()
& $Collector -Serial $Serial -OutputPath $lightPath|Out-Host
$timer.Stop()
$light=Get-Content -LiteralPath $lightPath -Raw|ConvertFrom-Json
$new=((& $Classifier -InputPath $lightPath -OutputFormat Json)|ConvertFrom-Json)

$network=Get-Content -LiteralPath (Join-Path $FullRawPath 'network.txt') -Raw
$historyIndex=$network.IndexOf('mNetworkRequestInfoLogs')
$current=if($historyIndex -ge 0){$network.Substring(0,$historyIndex)}else{$network}
$currentLine=@($current -split "\r?\n"|Where-Object{
  $_ -match 'activeRequest:' -and $_ -match 'com\.qualcomm\.qti\.cne' -and
  $_ -match 'Capabilities:\s*IMS' -and $_ -match 'mSubId\s*=\s*11'
})|Select-Object -First 1
$oldRequest=$null;$oldSatisfied=$null
if($currentLine -match 'NetworkRequest \[ REQUEST id=(\d+)'){$oldRequest=[int]$Matches[1]}
if($currentLine -match 'activeRequest:\s*(\d+)'){$oldSatisfied=[int]$Matches[1]}
$newRequest=$light.cne.requestId
$newSatisfied=$light.cne.satisfiedId
$cneMatch=($oldRequest -eq $newRequest -and $oldSatisfied -eq $newSatisfied)

$oldWriteEligible=@('A0_READY','P0_READY','FROZEN_RESIDUE') -contains $OldResult
$equivalent=($OldResult -ceq [string]$new.classification)
$moreConservative=($new.classification -ceq 'UNKNOWN' -and $OldResult -cne 'UNKNOWN')
$unsafePromotion=(-not $oldWriteEligible -and [bool]$new.writeEligible)
$structuralErrors=@($new.errors|Where-Object{$_ -match '^(missing:|schema:|capture:)'})
$runtimeOrStructuralError=(-not [bool]$light.capture.complete -or @($light.capture.errors).Count -ne 0 -or $structuralErrors.Count -ne 0)
$record=[pscustomobject][ordered]@{
  schema='voxi-wfc-shadow-comparison-v1'
  timestampUtc=[DateTimeOffset]::UtcNow.ToString('o')
  runId=$runId
  cycle=$cycle
  label=$Label
  observationEpoch=$light.capture.observationEpoch
  oldResult=$OldResult
  newResult=$new.classification
  equivalent=$equivalent
  moreConservative=$moreConservative
  unsafePromotion=$unsafePromotion
  newWriteEligible=$new.writeEligible
  newErrors=@($new.errors)
  structuralErrors=$structuralErrors
  runtimeOrStructuralError=$runtimeOrStructuralError
  shadowElapsedMs=[int64]$timer.ElapsedMilliseconds
  deviceSpanMs=$light.capture.deviceSpanMs
  commandCount=$light.capture.commandCount
  oldCurrentRequestId=$oldRequest
  newCurrentRequestId=$newRequest
  oldSatisfiedId=$oldSatisfied
  newSatisfiedId=$newSatisfied
  cneIdsMatch=$cneMatch
  qcrildPid=$light.qcril.primary.pid
  qcrild2Pid=$light.qcril.secondary.pid
  pmServicePid=$light.native.pmService.pid
  holderPid=$light.holder.pid
  crashCount=$light.native.crashCount
  fullSummaryPath=$FullSummaryPath
  fullRawPath=$FullRawPath
}
$recordPath=Join-Path $OutputRoot ("cycle_{0}_{1}_comparison.json" -f $cycle,$safeLabel)
[IO.File]::WriteAllText($recordPath,($record|ConvertTo-Json -Depth 10)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))

Write-Output ("TIMING_SHADOW_LIGHT ms={0}" -f $timer.ElapsedMilliseconds)
Write-Output ("SHADOW old={0} new={1} equivalent={2} moreConservative={3} unsafePromotion={4}" -f $OldResult,$new.classification,$equivalent,$moreConservative,$unsafePromotion)
Write-Output ("SHADOW_CNE oldRequest={0} newRequest={1} oldSatisfied={2} newSatisfied={3} match={4} epoch={5}" -f $oldRequest,$newRequest,$oldSatisfied,$newSatisfied,$cneMatch,$light.capture.observationEpoch)
Write-Output ("SHADOW_RECORD={0}" -f $recordPath)

if($runtimeOrStructuralError){exit 82}
if($unsafePromotion){exit 80}
if(-not $cneMatch){exit 81}
