[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$SnapshotRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\runs\v262_freeze_run\snapshots')).Path
$FixtureRoot=Join-Path $PSScriptRoot 'fixtures'
[IO.Directory]::CreateDirectory($FixtureRoot)|Out-Null

function Clone-Object([object]$Object) {
  $Object|ConvertTo-Json -Depth 20|ConvertFrom-Json
}

function Convert-Process([object]$Process) {
  if($null -eq $Process){return [ordered]@{processExists=$false;pid=$null;ppid=$null;name=$null;cmdline=$null}}
  [ordered]@{processExists=$true;pid=[int]$Process.pid;ppid=[int]$Process.ppid;name=[string]$Process.name;cmdline=[string]$Process.cmdline}
}

function Convert-Snapshot([string]$Name) {
  $path=Join-Path $SnapshotRoot $Name
  $old=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
  $pm=Convert-Process $old.processes.pmService
  $holder=Convert-Process $old.processes.holder
  $owners=@()
  foreach($line in @($old.native.ownerLines|Where-Object{$_ -match '/dev/subsys_esoc0'})) {
    $parts=$line.Trim() -split '\s+'
    $owners += [ordered]@{pid=[int]$parts[1];name=[string]$parts[0];path='/dev/subsys_esoc0'}
  }
  [ordered]@{
    schema='voxi-wfc-lightweight-state-v1'
    capture=[ordered]@{observationEpoch="fixture:$Name";hostStartUtc='2026-09-25T00:00:00.0000000Z';hostEndUtc='2026-09-25T00:00:00.1000000Z';deviceStartMs=[int64]100000;deviceEndMs=[int64]100100;spanMs=[int64]100;commandCount=0;complete=$true;errors=@()}
    environment=[ordered]@{airplaneMode=[int]$old.environment.airplaneMode;wifiSetting=[string]$old.environment.wifiSetting}
    target=[ordered]@{subId=[int]$old.target.subId;slotId=[int]$old.target.slotId;phoneId=[int]$old.target.phoneId;carrierId=[int]$old.target.carrierId;mcc=[int]$old.target.mcc;mnc=[int]$old.target.mnc;mappingGate=[bool]$old.target.mappingGate;subscriptionActive=[bool]$old.subscription.active;uiccApplicationsEnabled=[bool]$old.subscription.uiccAppsEnabled}
    holder=[ordered]@{pidFilePresent=[bool]$old.residues.holderPidFile;pidFileValue=if($old.residues.holderPidFile){if($holder.processExists){$holder.pid}else{99999}}else{$null};processExists=[bool]$holder.processExists;pid=if($holder.processExists){$holder.pid}else{$null};cmdline=if($holder.processExists){$holder.cmdline}else{$null};fd9Target=if($holder.processExists){'/dev/subsys_esoc0'}else{$null}}
    native=[ordered]@{ownerCount=@($owners).Count;owners=$owners;perMgrState=[string]$old.native.perMgrState;pmService=[ordered]@{processExists=[bool]$pm.processExists;pid=if($pm.processExists){$pm.pid}else{$null};ppid=if($pm.processExists){$pm.ppid}else{$null};name=if($pm.processExists){$pm.name}else{$null};cmdline=if($pm.processExists){$pm.cmdline}else{$null};exe=if($pm.processExists){'/vendor/bin/pm-service'}else{$null};initPid=if($pm.processExists){$pm.pid}else{$null}};vendorX55State=[string]$old.native.vendorPeripheralState;kernelX55State=[string]$old.native.x55State;crashCount=$old.native.crashCount}
    qcril=[ordered]@{primary=Convert-Process $old.processes.qcrild;secondary=Convert-Process $old.processes.qcrild2}
    cne=[ordered]@{requestId=if($old.data.qtiCneRequest){[int]272}else{$null};satisfiedId=if($old.data.qtiCneRequest){[int]272}else{$null};currentEvidenceValid=$true}
    health=[ordered]@{imsRegistrationRaw=[int]$old.ims.stateRaw;transportRaw=[int]$old.ims.transportRaw;voiceIwlanAvailable=[bool]$old.ims.voiceIwlan;wfcAvailable=[bool]$old.data.wfcAvailable;goldenStrong=[bool]$old.health.goldenStrong}
  }
}

function Write-Fixture([string]$Name,[object]$State) {
  $path=Join-Path $FixtureRoot ($Name+'.json')
  [IO.File]::WriteAllText($path,($State|ConvertTo-Json -Depth 20)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
}

$a0=Convert-Snapshot 'snapshot_A0.json'
$p0=Convert-Snapshot 'snapshot_P0.json'
$frozen=Convert-Snapshot 'snapshot_A1.json'
$w0=Convert-Snapshot 'snapshot_W0.json'
$w1=Convert-Snapshot 'snapshot_W1.json'
$profileA0=Convert-Snapshot 'preflight_20260925_181323_normalized.json'
$takeover=Convert-Snapshot 'snapshot_A1_native_takeover_failed.json'

Write-Fixture '01_native_clean_a0' $a0
Write-Fixture '02_p0' $p0
Write-Fixture '03_frozen_holder_residue' $frozen
Write-Fixture '04_healthy_frozen_wfc' $w0
Write-Fixture '05_w0' $w0
Write-Fixture '06_w1' $w1
Write-Fixture '07_known_f1' $profileA0
Write-Fixture '08_no_cne_request_p0' $p0

$unknownOwner=Clone-Object $a0
$unknownOwner.native.ownerCount=2
$unknownOwner.native.owners=@($unknownOwner.native.owners)+@([pscustomobject]@{pid=55555;name='mystery';path='/dev/subsys_esoc0'})
Write-Fixture '09_unknown_owner' $unknownOwner

$stalePidfile=Clone-Object $a0
$stalePidfile.holder.pidFilePresent=$true
$stalePidfile.holder.pidFileValue=45678
Write-Fixture '10_stale_holder_pidfile' $stalePidfile

$pmNonOwner=Clone-Object $takeover
$pmNonOwner.holder.pidFilePresent=$false
$pmNonOwner.holder.pidFileValue=$null
$pmNonOwner.holder.processExists=$false
$pmNonOwner.holder.pid=$null
$pmNonOwner.holder.cmdline=$null
$pmNonOwner.holder.fd9Target=$null
$pmNonOwner.native.ownerCount=0
$pmNonOwner.native.owners=@()
$pmNonOwner.native.vendorX55State='ONLINE'
$pmNonOwner.native.kernelX55State='ONLINE'
Write-Fixture '11_pm_running_not_owner' $pmNonOwner

$x55Split=Clone-Object $a0
$x55Split.native.vendorX55State='ONLINE'
$x55Split.native.kernelX55State='OFFLINE'
Write-Fixture '12_x55_vendor_kernel_split' $x55Split

$badMapping=Clone-Object $a0
$badMapping.target.slotId=0
$badMapping.target.mappingGate=$false
Write-Fixture '13_target_mapping_error' $badMapping

$uiccDisabled=Clone-Object $a0
$uiccDisabled.target.uiccApplicationsEnabled=$false
Write-Fixture '14_uicc_disabled' $uiccDisabled

$badQcrild2=Clone-Object $a0
$badQcrild2.qcril.secondary.cmdline='qcrild -c 1'
Write-Fixture '15_qcrild2_identity_error' $badQcrild2

$missingField=Clone-Object $a0
$missingField.target.PSObject.Properties.Remove('mnc')
Write-Fixture '16_missing_target_field' $missingField

$malformed=Clone-Object $a0
$malformed.native.crashCount='zero'
Write-Fixture '17_malformed_crash_count' $malformed

Write-Output ("FIXTURES_WRITTEN={0}" -f @(Get-ChildItem $FixtureRoot -Filter '*.json').Count)
