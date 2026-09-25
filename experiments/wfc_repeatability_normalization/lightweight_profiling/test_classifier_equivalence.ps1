[CmdletBinding()]
param(
  [string]$ResultsPath=''
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($ResultsPath)){$ResultsPath=Join-Path $PSScriptRoot 'classifier_equivalence_results.csv'}
$Classifier=Join-Path $PSScriptRoot 'classify_lightweight_state.ps1'
$Manifest=Join-Path $PSScriptRoot 'fixture_manifest.csv'
$FixtureRoot=Join-Path $PSScriptRoot 'fixtures'

function Get-LegacyClassification([object]$State) {
  try {
    $targetGate=($State.target.mappingGate -and $State.target.subId -eq 11 -and $State.target.slotId -eq 1 -and
      $State.target.phoneId -eq 1 -and $State.target.carrierId -eq 28 -and $State.target.mcc -eq 234 -and
      $State.target.mnc -eq 15 -and $State.target.subscriptionActive -and $State.target.uiccApplicationsEnabled)
    if(-not $targetGate){return 'UNKNOWN'}
    $ownerPids=@($State.native.owners|ForEach-Object{[int64]$_.pid})
    $pmOwns=($State.native.pmService.processExists -and $null -ne $State.native.pmService.pid -and
      @($ownerPids|Where-Object{$_ -eq [int64]$State.native.pmService.pid}).Count -gt 0)
    $holderOwns=($State.holder.processExists -and $null -ne $State.holder.pid -and
      @($ownerPids|Where-Object{$_ -eq [int64]$State.holder.pid}).Count -gt 0)
    $nativeClean=($State.native.perMgrState -eq 'running' -and $pmOwns -and -not $holderOwns -and
      $State.native.vendorX55State -eq 'ONLINE' -and $State.native.kernelX55State -eq 'ONLINE' -and
      $null -ne $State.native.crashCount)
    $frozen=($holderOwns -and -not $pmOwns -and $State.native.kernelX55State -eq 'ONLINE' -and
      $null -ne $State.native.crashCount -and @('stopped','running') -contains [string]$State.native.perMgrState)
    if($State.health.goldenStrong){return 'HEALTHY_FREEZE'}
    if($State.environment.airplaneMode -eq 1){if($nativeClean){return 'P0_READY'}else{return 'UNKNOWN'}}
    if($nativeClean){return 'A0_READY'}
    if($frozen){return 'FROZEN_RESIDUE'}
    'UNKNOWN'
  } catch {
    'UNKNOWN'
  }
}

& (Join-Path $PSScriptRoot 'build_offline_fixtures.ps1')|Out-Host
$rows=@()
$unsafePromotions=0
$mismatches=0
foreach($case in @(Import-Csv -LiteralPath $Manifest)) {
  $fixturePath=Join-Path $FixtureRoot ($case.fixture+'.json')
  $fixtureState=Get-Content -LiteralPath $fixturePath -Raw|ConvertFrom-Json
  $oldResult=Get-LegacyClassification $fixtureState
  $raw=& $Classifier -InputPath $fixturePath -OutputFormat Json
  $result=$raw|ConvertFrom-Json
  $oldEligible=@('A0_READY','P0_READY','FROZEN_RESIDUE') -contains $oldResult
  $expectedEligible=[bool]::Parse($case.expected_new_write_eligible)
  $actualEligible=[bool]$result.writeEligible
  $matches=($oldResult -ceq $case.old_classifier_result -and $result.classification -ceq $case.expected_new_result -and $actualEligible -eq $expectedEligible)
  $unsafePromotion=(-not $oldEligible -and $actualEligible)
  if(-not $matches){$mismatches++}
  if($unsafePromotion){$unsafePromotions++}
  $rows += [pscustomobject][ordered]@{
    fixture=$case.fixture
    source=$case.source
    old_classifier_result=$oldResult
    new_classifier_result=$result.classification
    old_write_eligible=$oldEligible
    new_write_eligible=$actualEligible
    expected_new_result=$case.expected_new_result
    equivalence=if($matches){if($oldResult -ceq $result.classification){'EQUIVALENT'}else{'MORE_CONSERVATIVE'}}else{'MISMATCH'}
    unsafe_old_fail_to_new_pass=$unsafePromotion
    error_count=@($result.errors).Count
    reason=$case.reason
  }
}

$rows|Export-Csv -LiteralPath $ResultsPath -NoTypeInformation -Encoding UTF8
Write-Output ("FIXTURE_COUNT={0}" -f $rows.Count)
Write-Output ("MISMATCH_COUNT={0}" -f $mismatches)
Write-Output ("UNSAFE_PROMOTION_COUNT={0}" -f $unsafePromotions)
Write-Output ("RESULTS={0}" -f (Resolve-Path -LiteralPath $ResultsPath).Path)
if($mismatches -ne 0 -or $unsafePromotions -ne 0){exit 1}
