[CmdletBinding()]
param(
  [string]$Serial='fd0ff892',
  [ValidateRange(3,20)][int]$Cycles=3,
  [ValidateRange(10,20)][int]$InterCycleSeconds=10
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Collector=Join-Path $PSScriptRoot 'capture_lightweight_state.ps1'
$Classifier=Join-Path $PSScriptRoot 'classify_lightweight_state.ps1'
$FullCapture=Join-Path (Join-Path $Repo 'experiments\wfc_repeatability_normalization') 'capture_snapshot.ps1'
$RunId=(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$LocalRoot=Join-Path (Split-Path $Repo -Parent) (Join-Path 'voxi_wfc_local_runs\lightweight_device_benchmark' $RunId)
[IO.Directory]::CreateDirectory($LocalRoot)|Out-Null

function Invoke-Light([int]$Cycle,[string]$Side) {
  $path=Join-Path $LocalRoot ("cycle_{0}_{1}.json" -f $Cycle,$Side.ToLowerInvariant())
  $timer=[Diagnostics.Stopwatch]::StartNew()
  $output=@(& $Collector -Serial $Serial -OutputPath $path 2>&1 | ForEach-Object {[string]$_})
  $timer.Stop()
  $state=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
  $classification=((& $Classifier -InputPath $path -OutputFormat Json)|ConvertFrom-Json)
  [pscustomobject][ordered]@{
    path=$path
    elapsedMs=[int64]$timer.ElapsedMilliseconds
    output=$output
    state=$state
    result=$classification
  }
}

function Get-LegacyClassification([object]$State) {
  try {
    $targetGate=($State.target.mappingGate -and $State.target.subId -eq 11 -and $State.target.slotId -eq 1 -and
      $State.target.phoneId -eq 1 -and $State.target.carrierId -eq 28 -and $State.target.mcc -eq 234 -and
      $State.target.mnc -eq 15 -and $State.subscription.active -and $State.subscription.uiccAppsEnabled)
    if(-not $targetGate){return 'UNKNOWN'}
    $ownerLines=@($State.native.ownerLines)
    $pmPid=if($null -ne $State.processes.pmService){[int64]$State.processes.pmService.pid}else{$null}
    $holderPid=if($null -ne $State.processes.holder){[int64]$State.processes.holder.pid}else{$null}
    $pmOwns=($null -ne $pmPid -and @($ownerLines|Where-Object{$_ -match ("\s{0}\s" -f $pmPid)}).Count -gt 0)
    $holderOwns=($null -ne $holderPid -and @($ownerLines|Where-Object{$_ -match ("\s{0}\s" -f $holderPid)}).Count -gt 0)
    $nativeClean=($State.native.perMgrState -eq 'running' -and $pmOwns -and -not $holderOwns -and
      $State.native.x55Online -and $null -ne $State.native.crashCount)
    $frozen=($holderOwns -and -not $pmOwns -and $State.native.x55State -eq 'ONLINE' -and
      $null -ne $State.native.crashCount -and @('stopped','running') -contains [string]$State.native.perMgrState)
    if($State.health.goldenStrong){return 'HEALTHY_FREEZE'}
    if($State.environment.airplaneMode -eq 1){if($nativeClean){return 'P0_READY'}else{return 'UNKNOWN'}}
    if($nativeClean){return 'A0_READY'}
    if($frozen){return 'FROZEN_RESIDUE'}
    'UNKNOWN'
  } catch {'UNKNOWN'}
}

function Invoke-Full([int]$Cycle) {
  $label="lightweight_benchmark_${RunId}_cycle_${Cycle}_full"
  $timer=[Diagnostics.Stopwatch]::StartNew()
  $output=@(& $FullCapture -Label $label -Serial $Serial -RunName 'latency_baseline' 2>&1 | ForEach-Object {[string]$_})
  $timer.Stop()
  $summaryPath=Join-Path (Join-Path (Join-Path (Join-Path $Repo 'experiments\wfc_repeatability_normalization') 'runs\latency_baseline') 'snapshots') ($label+'.json')
  $rawPath=Join-Path (Join-Path (Split-Path $Repo -Parent) 'voxi_wfc_local_runs\repeatability_normalization\latency_baseline') $label
  if(-not (Test-Path -LiteralPath $summaryPath) -or -not (Test-Path -LiteralPath $rawPath)){throw "Full snapshot paths missing for cycle $Cycle"}
  $state=Get-Content -LiteralPath $summaryPath -Raw|ConvertFrom-Json
  [pscustomobject][ordered]@{
    summaryPath=$summaryPath
    rawPath=$rawPath
    elapsedMs=[int64]$timer.ElapsedMilliseconds
    output=$output
    state=$state
    classification=Get-LegacyClassification $state
  }
}

function Get-LightView([object]$State) {
  [pscustomobject][ordered]@{
    airplane=$State.environment.airplaneMode;wifi=$State.environment.wifiSetting
    subId=$State.target.subId;slotId=$State.target.slotId;phoneId=$State.target.phoneId
    carrierId=$State.target.carrierId;mcc=$State.target.mcc;mnc=$State.target.mnc
    active=$State.target.subscriptionActive;uicc=$State.target.uiccApplicationsEnabled
    holderPidFile=$State.holder.pidFilePresent;holderPidFileValue=$State.holder.pidFileValue
    holderPid=$State.holder.pid;holderLive=$State.holder.processExists;holderCmdline=$State.holder.cmdline;holderFd9=$State.holder.fd9Target
    ownerCount=$State.native.ownerCount;owners=@($State.native.owners)
    perMgr=$State.native.perMgrState;pmPid=$State.native.pmService.pid;pmExe=$State.native.pmService.exe
    vendorX55=$State.native.vendorX55State;kernelX55=$State.native.kernelX55State;crashCount=$State.native.crashCount
    primaryPid=$State.qcril.primary.pid;primaryName=$State.qcril.primary.name;primaryCmd=$State.qcril.primary.cmdline
    secondaryPid=$State.qcril.secondary.pid;secondaryName=$State.qcril.secondary.name;secondaryCmd=$State.qcril.secondary.cmdline
    cneRequest=$State.cne.requestId;cneSatisfied=$State.cne.satisfiedId
    imsRaw=$State.health.imsRegistrationRaw;transportRaw=$State.health.transportRaw
    voiceIwlan=$State.health.voiceIwlanAvailable;wfc=$State.health.wfcAvailable
  }
}

function Get-CneCurrentTable([string]$RawPath) {
  $networkPath=Join-Path $RawPath 'network.txt'
  $statusPath=Join-Path $RawPath 'wfc_status.txt'
  $network=Get-Content -LiteralPath $networkPath -Raw
  $index=$network.IndexOf('mNetworkRequestInfoLogs')
  $current=if($index -ge 0){$network.Substring(0,$index)}else{$network}
  $line=@($current -split "\r?\n"|Where-Object{
    $_ -match 'activeRequest:' -and $_ -match 'com\.qualcomm\.qti\.cne' -and
    $_ -match 'Capabilities:\s*IMS' -and $_ -match 'mSubId\s*=\s*11'
  })|Select-Object -First 1
  $request=$null;$satisfied=$null
  if($line -match 'NetworkRequest \[ REQUEST id=(\d+)'){$request=[int]$Matches[1]}
  if($line -match 'activeRequest:\s*(\d+)'){$satisfied=[int]$Matches[1]}
  $statusLine=@((Get-Content -LiteralPath $statusPath) | Where-Object {$_.Trim().StartsWith('{')})|Select-Object -Last 1
  $status=$statusLine|ConvertFrom-Json
  [pscustomobject][ordered]@{
    tableLine=$line
    tableRequestId=$request
    tableSatisfiedId=$satisfied
    statusRequestId=$status.connectivity.qtiCneRequestId
    statusSatisfiedId=$status.connectivity.qtiCneSatisfiedRequestId
    matches=($request -eq $status.connectivity.qtiCneRequestId -and $satisfied -eq $status.connectivity.qtiCneSatisfiedRequestId)
  }
}

function Test-Same([object]$A,[object]$B) {
  ($A|ConvertTo-Json -Depth 10 -Compress) -ceq ($B|ConvertTo-Json -Depth 10 -Compress)
}

$results=@()
for($cycle=1;$cycle -le $Cycles;$cycle++) {
  $lightA=Invoke-Light $cycle 'A'
  $full=Invoke-Full $cycle
  $lightB=Invoke-Light $cycle 'B'
  $viewA=Get-LightView $lightA.state
  $viewB=Get-LightView $lightB.state
  $stable=Test-Same $viewA $viewB
  $cne=Get-CneCurrentTable $full.rawPath
  $result=[pscustomobject][ordered]@{
    cycle=$cycle
    lightA=[pscustomobject]@{elapsedMs=$lightA.elapsedMs;state=$lightA.state;classification=$lightA.result}
    full=[pscustomobject]@{elapsedMs=$full.elapsedMs;summaryPath=$full.summaryPath;rawPath=$full.rawPath;state=$full.state;classification=$full.classification}
    lightB=[pscustomobject]@{elapsedMs=$lightB.elapsedMs;state=$lightB.state;classification=$lightB.result}
    stable=$stable
    disposition=if($stable){'STABLE'}else{'STATE_DRIFT_INCONCLUSIVE'}
    viewA=$viewA
    viewB=$viewB
    cneCurrentCrossCheck=$cne
  }
  $results += $result
  $result|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $LocalRoot ("cycle_{0}_result.json" -f $cycle)) -Encoding UTF8
  Write-Output ("CYCLE={0} LW_A={1} FULL={2} LW_B={3} STABLE={4} CNE_MATCH={5}" -f $cycle,$lightA.result.classification,$full.classification,$lightB.result.classification,$stable,$cne.matches)
  $tooSlow=([int64]$lightA.state.capture.deviceSpanMs -gt 15000 -or [int64]$lightB.state.capture.deviceSpanMs -gt 15000)
  if(-not $stable -or $tooSlow){break}
  if($cycle -lt $Cycles){Start-Sleep -Seconds $InterCycleSeconds}
}

$aggregate=[pscustomobject][ordered]@{
  schema='voxi-wfc-readonly-device-benchmark-v1'
  runId=$RunId
  serial=$Serial
  requestedCycles=$Cycles
  completedCycles=@($results).Count
  interCycleSeconds=$InterCycleSeconds
  phoneWrites=0
  recoveryRuns=0
  cycles=$results
}
$aggregatePath=Join-Path $LocalRoot 'benchmark.json'
$aggregate|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $aggregatePath -Encoding UTF8
Write-Output "BENCHMARK=$aggregatePath"
Write-Output "PHONE_WRITES=0"
Write-Output "RECOVERY_RUNS=0"
