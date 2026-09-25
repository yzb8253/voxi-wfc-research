[CmdletBinding()]
param(
  [string]$Serial='fd0ff892',
  [switch]$ApplyNormalization
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ExperimentRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Capture=Join-Path $ExperimentRoot 'capture_snapshot.ps1'
$RunName='v262_freeze_run'
$label='preflight_' + (Get-Date -Format 'yyyyMMdd_HHmmss')

function Capture([string]$Name) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $Capture -Label $Name -Serial $Serial -RunName $RunName | Out-Host
  if($LASTEXITCODE -ne 0){throw 'Preflight snapshot failed'}
  $path=Join-Path (Join-Path (Join-Path $ExperimentRoot 'runs') $RunName) ("snapshots\{0}.json" -f $Name)
  Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
}
function HolderOwns($State) {
  if($null -eq $State.processes.holder){return $false}
  $holderPid=[string]$State.processes.holder.pid
  [bool](@($State.native.ownerLines|Where-Object{$_ -match '/dev/subsys_esoc0' -and $_ -match "\s$holderPid\s"}).Count)
}
function PmOwns($State) {
  if($null -eq $State.processes.pmService){return $false}
  $pmPid=[string]$State.processes.pmService.pid
  [bool](@($State.native.ownerLines|Where-Object{$_ -match '/dev/subsys_esoc0' -and $_ -match "\s$pmPid\s"}).Count)
}
function TargetGate($State) {
  $State.target.mappingGate -and $State.target.subId -eq 11 -and $State.target.slotId -eq 1 -and
  $State.target.phoneId -eq 1 -and $State.target.carrierId -eq 28 -and
  $State.target.mcc -eq 234 -and $State.target.mnc -eq 15 -and
  $State.subscription.active -and $State.subscription.uiccAppsEnabled
}
function NativeClean($State) {
  $State.native.perMgrState -eq 'running' -and (PmOwns $State) -and -not (HolderOwns $State) -and
  $State.native.x55Online -and $null -ne $State.native.crashCount
}
function FrozenResidue($State) {
  (HolderOwns $State) -and -not (PmOwns $State) -and $State.native.x55State -eq 'ONLINE' -and
  $null -ne $State.native.crashCount -and ($State.native.perMgrState -eq 'stopped' -or $State.native.perMgrState -eq 'running')
}

$state=Capture $label
if(-not (TargetGate $state)){throw 'PREFLIGHT_FAIL: fixed VOXI identity/subscription gate failed'}

if($state.health.goldenStrong) {
  Write-Host 'PREFLIGHT_RESULT=HEALTHY_FREEZE_ZERO_WRITE'
  exit 0
}

if($state.environment.airplaneMode -eq 1) {
  if(NativeClean $state) {
    Write-Host 'PREFLIGHT_RESULT=P0_READY'
    exit 0
  }
  throw 'PREFLIGHT_FAIL: airplane-on state is not native-clean P0; normalization is only allowed while airplane is OFF'
}

if(NativeClean $state) {
  Write-Host 'PREFLIGHT_RESULT=A0_READY'
  exit 0
}

if(-not (FrozenResidue $state)) {
  throw 'PREFLIGHT_FAIL: unknown A-state fingerprint; no writes allowed'
}

if(-not $ApplyNormalization) {
  Write-Host 'PREFLIGHT_RESULT=A_RESIDUE_DETECTED_NORMALIZATION_REQUIRED'
  exit 10
}

$native=Join-Path $PSScriptRoot 'normalize_a1_native_owner.ps1'
& powershell -NoProfile -ExecutionPolicy Bypass -File $native -Serial $Serial
$nativeExit=$LASTEXITCODE
if($nativeExit -ne 0) {
  $reacquire=Join-Path $PSScriptRoot 'normalize_a1_qcrild2_reacquire.ps1'
  & powershell -NoProfile -ExecutionPolicy Bypass -File $reacquire -Serial $Serial
  if($LASTEXITCODE -ne 0){throw 'PREFLIGHT_FAIL: fingerprint-specific native reacquire failed'}
}

$after=Capture ($label+'_normalized')
if(-not (NativeClean $after)){throw 'PREFLIGHT_FAIL: normalization completed but native A0 fingerprint is not clean'}
if($after.data.qtiCneRequest){throw 'PREFLIGHT_FAIL: current qti.cne IMS request remains active'}
Write-Host 'PREFLIGHT_RESULT=A0_NORMALIZED'
