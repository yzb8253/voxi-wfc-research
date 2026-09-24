[CmdletBinding()]
param(
  [ValidateRange(1,3)][int]$Cycle = 1,
  [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Serial = 'fd0ff892'
$RunName = 'v263_state_machine_3cycle'
$SettleSeconds = 60
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Repo = (Resolve-Path (Join-Path $Root '..\..')).Path
$Adb = Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$CaptureScript = Join-Path $Root 'capture_snapshot.ps1'
$KnownGoodRecovery = Join-Path $Root 'v262_freeze_run\X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1'
$NativeNormalize = Join-Path $Root 'v262_freeze_run\normalize_a1_native_owner.ps1'
$QcrildNormalize = Join-Path $Root 'v262_freeze_run\normalize_a1_qcrild2_reacquire.ps1'
$ExpectedNonzeroProbe = Join-Path $PSScriptRoot 'expected-nonzero-probe.ps1'
$RunRoot = Join-Path (Join-Path $Root 'runs') $RunName
$SnapshotRoot = Join-Path $RunRoot 'snapshots'
$HostLogRoot = Join-Path (Split-Path $Repo -Parent) "voxi_wfc_local_runs\repeatability_normalization\$RunName"
$Timeline = Join-Path $HostLogRoot ("V{0}_timeline.log" -f $Cycle)

[IO.Directory]::CreateDirectory($SnapshotRoot) | Out-Null
[IO.Directory]::CreateDirectory($HostLogRoot) | Out-Null

function Log([string]$Message) {
  $line = '{0} {1}' -f (Get-Date -Format o), $Message
  Add-Content -LiteralPath $Timeline -Value $line -Encoding UTF8
  Write-Host $line
}

function Quote-Sh([string]$Value) {
  $single=[string][char]39; $double=[string][char]34
  $single + $Value.Replace($single,($single+$double+$single+$double+$single)) + $single
}

function Invoke-Adb([string[]]$Arguments) {
  $info=[Diagnostics.ProcessStartInfo]::new()
  $info.FileName=$Adb; $info.UseShellExecute=$false; $info.CreateNoWindow=$true
  $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
  $info.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){ '"'+$_.Replace('"','\"')+'"' }else{$_}}) -join ' ')
  $process=[Diagnostics.Process]::new(); $process.StartInfo=$info
  if(-not $process.Start()){throw 'Unable to start adb'}
  $stdout=$process.StandardOutput.ReadToEnd(); $stderr=$process.StandardError.ReadToEnd(); $process.WaitForExit()
  [pscustomobject]@{ExitCode=$process.ExitCode;Text=$stdout+$stderr}
}

function Root-Write([string]$Command) {
  if(-not $Execute){throw "DRY_RUN_BLOCKED_WRITE: $Command"}
  Log "PHONE_WRITE=$Command"
  $result=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)))
  if($result.ExitCode -ne 0){throw "PHONE_WRITE_FAILED: $Command`n$($result.Text)"}
  $result.Text.Trim()
}

function Invoke-ChildScript([string]$Path,[string[]]$Arguments=@()) {
  # A fail-closed helper may intentionally return nonzero and write to stderr.
  # Capture that result without allowing the host's Stop preference to bypass
  # the caller's explicit exit-code state transition.
  $previousPreference=$ErrorActionPreference
  try {
    $ErrorActionPreference='Continue'
    $output=@(& powershell -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments 2>&1)
    $exitCode=$LASTEXITCODE
  }
  finally {
    $ErrorActionPreference=$previousPreference
  }
  [pscustomobject]@{ExitCode=$exitCode;Output=$output}
}

function Capture([string]$Label) {
  Log "CAPTURE_BEGIN=$Label"
  $captureResult=Invoke-ChildScript $CaptureScript @('-Label',$Label,'-Serial',$Serial,'-RunName',$RunName)
  foreach($line in $captureResult.Output){Log "CAPTURE_OUTPUT=$line"}
  if($captureResult.ExitCode -ne 0){throw "SNAPSHOT_FAILED=$Label"}
  $path=Join-Path $SnapshotRoot ($Label+'.json')
  $state=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  Log "CAPTURE_END=$Label HEALTH=$($state.health.goldenStrong)"
  $state
}

function Holder-Owns($State) {
  if($null -eq $State.processes.holder){return $false}
  $holderPid=[string]$State.processes.holder.pid
  [bool](@($State.native.ownerLines|Where-Object{$_ -match '/dev/subsys_esoc0' -and $_ -match "\s$holderPid\s"}).Count)
}

function Pm-Owns($State) {
  if($null -eq $State.processes.pmService){return $false}
  $pmPid=[string]$State.processes.pmService.pid
  [bool](@($State.native.ownerLines|Where-Object{$_ -match '/dev/subsys_esoc0' -and $_ -match "\s$pmPid\s"}).Count)
}

function Target-Gate($State) {
  $State.device.root -and $State.device.product -eq 'cas' -and
  $State.target.mappingGate -and $State.target.subId -eq 11 -and $State.target.slotId -eq 1 -and
  $State.target.phoneId -eq 1 -and $State.target.carrierId -eq 28 -and
  $State.target.mcc -eq 234 -and $State.target.mnc -eq 15 -and
  $State.subscription.active -and $State.subscription.uiccAppsEnabled
}

function Process-Gate($State) {
  $null -ne $State.processes.qcrild -and $State.processes.qcrild.ppid -eq 1 -and
  $State.processes.qcrild.cmdline -eq 'qcrild' -and
  $null -ne $State.processes.qcrild2 -and $State.processes.qcrild2.ppid -eq 1 -and
  $State.processes.qcrild2.cmdline -eq 'qcrild -c 2' -and
  $null -ne $State.processes.pmProxy -and $null -ne $State.processes.mdmHelper
}

function Native-Clean($State) {
  $State.native.perMgrState -eq 'running' -and $null -ne $State.processes.pmService -and
  $State.processes.pmService.ppid -eq 1 -and $State.processes.pmService.cmdline -eq 'pm-service' -and
  (Pm-Owns $State) -and -not (Holder-Owns $State) -and
  $State.native.vendorPeripheralState -eq 'ONLINE' -and $State.native.x55State -eq 'ONLINE' -and
  $State.native.crashCount -eq 0
}

function Frozen-Residue($State) {
  $State.environment.airplaneMode -eq 0 -and $State.native.perMgrState -eq 'stopped' -and
  $null -eq $State.processes.pmService -and (Holder-Owns $State) -and
  $State.native.vendorPeripheralState -eq 'ONLINE' -and $State.native.x55State -eq 'ONLINE' -and
  $State.native.crashCount -eq 0
}

function Qcrild-Fallback-Precondition($State) {
  $State.environment.airplaneMode -eq 0 -and $State.native.perMgrState -eq 'running' -and
  $null -ne $State.processes.pmService -and -not (Pm-Owns $State) -and (Holder-Owns $State) -and
  $State.native.vendorPeripheralState -eq 'OFFLINE' -and $State.native.x55State -eq 'ONLINE' -and
  $State.native.crashCount -eq 0
}

function A-Canonical($State) {
  (Target-Gate $State) -and (Process-Gate $State) -and (Native-Clean $State) -and
  $State.environment.airplaneMode -eq 0 -and $State.environment.wlan0Up -and $State.environment.vpnNetwork -and
  $State.iwlan.rilTechnology -eq 'LTE' -and -not $State.iwlan.preferred -and
  -not $State.data.qtiCneRequest -and -not $State.residues.moduleLock
}

function P-Canonical($State) {
  (Target-Gate $State) -and (Process-Gate $State) -and (Native-Clean $State) -and
  $State.environment.airplaneMode -eq 1 -and $State.environment.wlan0Up -and $State.environment.vpnNetwork -and
  $State.iwlan.rilTechnology -eq 'IWLAN' -and $State.iwlan.psWlan -eq 'HOME' -and
  $State.iwlan.accessNetwork -eq 'IWLAN' -and $State.iwlan.preferred -and
  -not $State.data.qtiCneRequest -and -not $State.residues.moduleLock
}

function W-Healthy($State) {
  (Target-Gate $State) -and $State.ims.stateRaw -eq 2 -and $State.ims.transportRaw -eq 2 -and
  $State.ims.voiceIwlan -and $State.data.wfcAvailable -and $State.health.goldenStrong
}

function Normalize-A([int]$Number,$State) {
  if(A-Canonical $State){Log "V${Number}_A_RESULT=A_PASS_NO_WRITE";return $State}
  $initialResidue=Frozen-Residue $State
  $fallbackReady=Qcrild-Fallback-Precondition $State
  if(-not $initialResidue -and -not $fallbackReady){throw "UNKNOWN_A_FINGERPRINT V$Number"}
  if(-not $Execute){throw "V${Number}_A_RESIDUE_DETECTED_EXECUTE_REQUIRED"}

  if($fallbackReady) {
    Log "V${Number}_A_RESIDUE=QCRILD2_FALLBACK_PRECONDITION_RESUME"
    $qcrildResult=Invoke-ChildScript $QcrildNormalize @('-Serial',$Serial)
    foreach($line in $qcrildResult.Output){Log "QCRILD_NORMALIZER_OUTPUT=$line"}
    if($qcrildResult.ExitCode -ne 0){throw "V${Number}_QCRILD2_REACQUIRE_FAILED"}
    Log "V${Number}_QCRILD2_REACQUIRE=PASS"
  }
  else {
    Log "V${Number}_A_RESIDUE=FROZEN_WFC_RESIDUE"
    $nativeResult=Invoke-ChildScript $NativeNormalize @('-Serial',$Serial)
    foreach($line in $nativeResult.Output){Log "NATIVE_NORMALIZER_OUTPUT=$line"}
    $nativeExit=$nativeResult.ExitCode
    Log "V${Number}_NATIVE_NORMALIZER_EXIT=$nativeExit"
    if($nativeExit -ne 0) {
      $qcrildResult=Invoke-ChildScript $QcrildNormalize @('-Serial',$Serial)
      foreach($line in $qcrildResult.Output){Log "QCRILD_NORMALIZER_OUTPUT=$line"}
      if($qcrildResult.ExitCode -ne 0){throw "V${Number}_QCRILD2_REACQUIRE_FAILED"}
      Log "V${Number}_QCRILD2_REACQUIRE=PASS"
    }
  }
  Start-Sleep -Seconds 60
  $normalized=Capture ("V{0}_A_NORMALIZED" -f $Number)
  if(-not (A-Canonical $normalized)){throw "V${Number}_A_NORMALIZED_NOT_CANONICAL"}
  Log "V${Number}_A_RESULT=A_NORMALIZED_PASS"
  $normalized
}

Log "STATE_MACHINE_BEGIN cycle=$Cycle execute=$Execute base_commit=89f2c86d48c91a974988d9bf67415f592da6f50d"
if(-not (Test-Path $KnownGoodRecovery)){throw 'Verified v2.6.2 freeze-on-success script missing'}
$knownHash=(Get-FileHash $KnownGoodRecovery -Algorithm SHA256).Hash
if($knownHash -ne '445752BB49FB487850D0B1A1EFF4F0AA29D58C363C3A86E75BAA841E4CC08F75'){throw "Known-good recovery hash mismatch: $knownHash"}
$exitProbe=Invoke-ChildScript $ExpectedNonzeroProbe
if($exitProbe.ExitCode -ne 23){throw "EXPECTED_NONZERO_CAPTURE_SELFTEST_FAILED exit=$($exitProbe.ExitCode)"}
Log 'EXPECTED_NONZERO_CAPTURE_SELFTEST=PASS exit=23'

$aRaw=Capture ("V{0}_A_RAW" -f $Cycle)
if($aRaw.environment.airplaneMode -ne 0){throw "V${Cycle}_ENTRY_REQUIRES_AIRPLANE_OFF"}
$a=Normalize-A $Cycle $aRaw

Root-Write 'cmd connectivity airplane-mode enable' | Out-Null
Start-Sleep -Seconds 3
Root-Write 'svc wifi enable' | Out-Null
Log "V${Cycle}_P_SETTLE_SECONDS=$SettleSeconds"
Start-Sleep -Seconds $SettleSeconds

$p=Capture ("V{0}_P_RAW" -f $Cycle)
if(-not (P-Canonical $p)){throw "UNKNOWN_P_FINGERPRINT V$Cycle"}
Log "V${Cycle}_P_RESULT=P_PASS"

if(-not $Execute){throw 'DRY_RUN_COMPLETE_BEFORE_RECOVERY'}
Log "V${Cycle}_RECOVERY_BEGIN=VERIFIED_V262_FREEZE"
$recoveryResult=Invoke-ChildScript $KnownGoodRecovery
foreach($line in $recoveryResult.Output){Log "RECOVERY_OUTPUT=$line"}
$recoveryExit=$recoveryResult.ExitCode
Log "V${Cycle}_RECOVERY_EXIT=$recoveryExit"
if($recoveryExit -ne 0){
  [void](Capture ("V{0}_FAILURE" -f $Cycle))
  throw "V${Cycle}_RECOVERY_FAILED"
}

$w=Capture ("V{0}_W_HEALTHY" -f $Cycle)
if(-not (W-Healthy $w)){throw "V${Cycle}_POST_RECOVERY_HEALTH_FAILED"}
Log "V${Cycle}_RESULT=PASS FREEZE_ON_HEALTHY=TRUE"
Write-Host "VALIDATION_CYCLE=$Cycle"
Write-Host 'RESULT=PASS'
Write-Host 'FREEZE_ON_HEALTHY=TRUE'
