[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$InputPath,
  [ValidateSet('Json','Text')][string]$OutputFormat='Json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-Field {
  param([object]$Object,[string]$Name,[System.Collections.Generic.List[string]]$Errors,[string]$Path)
  if($null -eq $Object) {
    $Errors.Add("missing:$Path")
    return $null
  }
  $property=$Object.PSObject.Properties[$Name]
  if($null -eq $property) {
    $Errors.Add("missing:$Path.$Name")
    return $null
  }
  $property.Value
}

function Test-Integer {
  param([object]$Value)
  $Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or
  $Value -is [uint16] -or $Value -is [uint32] -or $Value -is [uint64]
}

function Test-Bool {
  param([object]$Value)
  $Value -is [bool]
}

function Add-ErrorIf {
  param([bool]$Condition,[System.Collections.Generic.List[string]]$Errors,[string]$Message)
  if($Condition){$Errors.Add($Message)}
}

function Test-ProcessIdentity {
  param(
    [object]$Process,
    [string]$ExpectedName,
    [string]$ExpectedCmdline,
    [System.Collections.Generic.List[string]]$Errors,
    [string]$Path
  )
  $exists=Get-Field $Process 'processExists' $Errors $Path
  $processId=Get-Field $Process 'pid' $Errors $Path
  $ppid=Get-Field $Process 'ppid' $Errors $Path
  $name=Get-Field $Process 'name' $Errors $Path
  $cmdline=Get-Field $Process 'cmdline' $Errors $Path
  Add-ErrorIf (-not (Test-Bool $exists) -or -not $exists) $Errors "identity:$Path.not_running"
  Add-ErrorIf (-not (Test-Integer $processId) -or [int64]$processId -le 1) $Errors "identity:$Path.pid"
  Add-ErrorIf (-not (Test-Integer $ppid) -or [int64]$ppid -ne 1) $Errors "identity:$Path.ppid"
  Add-ErrorIf ([string]$name -cne $ExpectedName) $Errors "identity:$Path.name"
  Add-ErrorIf ([string]$cmdline -cne $ExpectedCmdline) $Errors "identity:$Path.cmdline"
  $Errors.Count -eq 0
}

function Get-OwnerPidSet {
  param([object[]]$Owners,[System.Collections.Generic.List[string]]$Errors)
  $result=New-Object 'System.Collections.Generic.List[long]'
  foreach($owner in @($Owners)) {
    $ownerPid=Get-Field $owner 'pid' $Errors 'native.owners[]'
    $ownerName=Get-Field $owner 'name' $Errors 'native.owners[]'
    $ownerPath=Get-Field $owner 'path' $Errors 'native.owners[]'
    Add-ErrorIf (-not (Test-Integer $ownerPid) -or [int64]$ownerPid -le 1) $Errors 'identity:native.owner.pid'
    Add-ErrorIf ([string]::IsNullOrWhiteSpace([string]$ownerName)) $Errors 'identity:native.owner.name'
    Add-ErrorIf ([string]$ownerPath -cne '/dev/subsys_esoc0') $Errors 'identity:native.owner.path'
    if(Test-Integer $ownerPid){$result.Add([int64]$ownerPid)}
  }
  $result
}

function Classify-LightweightState {
  param([object]$State)
  $errors=New-Object 'System.Collections.Generic.List[string]'

  $schema=Get-Field $State 'schema' $errors 'root'
  Add-ErrorIf ([string]$schema -cne 'voxi-wfc-lightweight-state-v1') $errors 'schema:unsupported'

  $capture=Get-Field $State 'capture' $errors 'root'
  $hostStart=Get-Field $capture 'hostStartUtc' $errors 'capture'
  $hostEnd=Get-Field $capture 'hostEndUtc' $errors 'capture'
  $deviceStart=Get-Field $capture 'deviceStartMs' $errors 'capture'
  $deviceEnd=Get-Field $capture 'deviceEndMs' $errors 'capture'
  $deviceSpan=Get-Field $capture 'deviceSpanMs' $errors 'capture'
  $span=Get-Field $capture 'spanMs' $errors 'capture'
  $complete=Get-Field $capture 'complete' $errors 'capture'
  $captureErrors=Get-Field $capture 'errors' $errors 'capture'
  $observationEpoch=Get-Field $capture 'observationEpoch' $errors 'capture'
  Add-ErrorIf ([string]::IsNullOrWhiteSpace([string]$hostStart) -or [string]::IsNullOrWhiteSpace([string]$hostEnd)) $errors 'capture:host_timestamp'
  Add-ErrorIf ([string]::IsNullOrWhiteSpace([string]$observationEpoch)) $errors 'capture:observation_epoch'
  Add-ErrorIf (-not (Test-Integer $deviceStart) -or -not (Test-Integer $deviceEnd) -or [int64]$deviceEnd -lt [int64]$deviceStart) $errors 'capture:device_timestamp'
  Add-ErrorIf (-not (Test-Integer $deviceSpan) -or [int64]$deviceSpan -lt 0 -or [int64]$deviceSpan -gt 15000) $errors 'capture:device_span_exceeded_or_invalid'
  Add-ErrorIf (-not (Test-Integer $span) -or [int64]$span -lt 0 -or [int64]$span -gt 15000) $errors 'capture:span_exceeded_or_invalid'
  Add-ErrorIf (-not (Test-Bool $complete) -or -not $complete) $errors 'capture:incomplete'
  Add-ErrorIf (@($captureErrors).Count -ne 0) $errors 'capture:collector_errors'

  $environment=Get-Field $State 'environment' $errors 'root'
  $airplaneMode=Get-Field $environment 'airplaneMode' $errors 'environment'
  $wifiSetting=Get-Field $environment 'wifiSetting' $errors 'environment'
  Add-ErrorIf (-not (Test-Integer $airplaneMode) -or @([int64]0,[int64]1) -notcontains [int64]$airplaneMode) $errors 'environment:airplane_mode'
  Add-ErrorIf ([string]$wifiSetting -notmatch '^[012]$') $errors 'environment:wifi_setting'

  $target=Get-Field $State 'target' $errors 'root'
  $targetChecks=[ordered]@{subId=11;slotId=1;phoneId=1;carrierId=28;mcc=234;mnc=15}
  foreach($key in $targetChecks.Keys) {
    $actual=Get-Field $target $key $errors 'target'
    Add-ErrorIf (-not (Test-Integer $actual) -or [int64]$actual -ne [int64]$targetChecks[$key]) $errors "target:$key"
  }
  $mappingGate=Get-Field $target 'mappingGate' $errors 'target'
  $active=Get-Field $target 'subscriptionActive' $errors 'target'
  $uicc=Get-Field $target 'uiccApplicationsEnabled' $errors 'target'
  Add-ErrorIf (-not (Test-Bool $mappingGate) -or -not $mappingGate) $errors 'target:mapping_gate'
  Add-ErrorIf (-not (Test-Bool $active) -or -not $active) $errors 'target:inactive'
  Add-ErrorIf (-not (Test-Bool $uicc) -or -not $uicc) $errors 'target:uicc_disabled'

  $qcril=Get-Field $State 'qcril' $errors 'root'
  $primary=Get-Field $qcril 'primary' $errors 'qcril'
  $secondary=Get-Field $qcril 'secondary' $errors 'qcril'
  $beforeQcrilErrors=$errors.Count
  [void](Test-ProcessIdentity $primary 'qcrild' 'qcrild' $errors 'qcril.primary')
  [void](Test-ProcessIdentity $secondary 'qcrild' 'qcrild -c 2' $errors 'qcril.secondary')
  $qcrilValid=($errors.Count -eq $beforeQcrilErrors)

  $holder=Get-Field $State 'holder' $errors 'root'
  $pidFilePresent=Get-Field $holder 'pidFilePresent' $errors 'holder'
  $pidFileValue=Get-Field $holder 'pidFileValue' $errors 'holder'
  $holderExists=Get-Field $holder 'processExists' $errors 'holder'
  $holderPid=Get-Field $holder 'pid' $errors 'holder'
  $holderCmd=Get-Field $holder 'cmdline' $errors 'holder'
  $holderFd9=Get-Field $holder 'fd9Target' $errors 'holder'
  Add-ErrorIf (-not (Test-Bool $pidFilePresent) -or -not (Test-Bool $holderExists)) $errors 'holder:boolean_fields'
  $holderLive=$false
  if($holderExists -is [bool] -and $holderExists) {
    $holderLive=$true
    Add-ErrorIf (-not $pidFilePresent) $errors 'holder:live_without_pidfile'
    Add-ErrorIf (-not (Test-Integer $holderPid) -or -not (Test-Integer $pidFileValue) -or [int64]$holderPid -ne [int64]$pidFileValue) $errors 'holder:pid_mismatch'
    Add-ErrorIf ([string]$holderCmd -notmatch 'x55_holder\.pid' -or [string]$holderCmd -notmatch '/dev/subsys_esoc0') $errors 'holder:cmdline'
    Add-ErrorIf ([string]$holderFd9 -cne '/dev/subsys_esoc0') $errors 'holder:fd9'
  } else {
    Add-ErrorIf ($null -ne $holderPid -or $null -ne $holderCmd -or $null -ne $holderFd9) $errors 'holder:dead_process_has_identity'
    Add-ErrorIf ($pidFilePresent -and -not (Test-Integer $pidFileValue)) $errors 'holder:stale_pidfile_value'
    Add-ErrorIf (-not $pidFilePresent -and $null -ne $pidFileValue) $errors 'holder:pidfile_value_without_file'
  }

  $native=Get-Field $State 'native' $errors 'root'
  $owners=Get-Field $native 'owners' $errors 'native'
  $ownerCount=Get-Field $native 'ownerCount' $errors 'native'
  $perMgrState=Get-Field $native 'perMgrState' $errors 'native'
  $pm=Get-Field $native 'pmService' $errors 'native'
  $vendorX55=Get-Field $native 'vendorX55State' $errors 'native'
  $kernelX55=Get-Field $native 'kernelX55State' $errors 'native'
  $crashCount=Get-Field $native 'crashCount' $errors 'native'
  Add-ErrorIf (-not (Test-Integer $ownerCount) -or [int64]$ownerCount -ne @($owners).Count) $errors 'native:owner_count'
  Add-ErrorIf ([string]$perMgrState -notmatch '^(running|stopped)$') $errors 'native:per_mgr_state'
  $x55Online=([string]$vendorX55 -ceq 'ONLINE' -and [string]$kernelX55 -ceq 'ONLINE')
  $x55FrozenSplit=([string]$vendorX55 -ceq 'OFFLINE' -and [string]$kernelX55 -ceq 'ONLINE')
  Add-ErrorIf (-not $x55Online -and -not $x55FrozenSplit) $errors 'native:x55_unknown_combination'
  Add-ErrorIf (-not (Test-Integer $crashCount) -or [int64]$crashCount -lt 0) $errors 'native:crash_count'
  $ownerPids=Get-OwnerPidSet @($owners) $errors

  $pmExists=Get-Field $pm 'processExists' $errors 'native.pmService'
  $pmPid=Get-Field $pm 'pid' $errors 'native.pmService'
  $pmPpid=Get-Field $pm 'ppid' $errors 'native.pmService'
  $pmName=Get-Field $pm 'name' $errors 'native.pmService'
  $pmCmd=Get-Field $pm 'cmdline' $errors 'native.pmService'
  $pmExe=Get-Field $pm 'exe' $errors 'native.pmService'
  $pmInitPid=Get-Field $pm 'initPid' $errors 'native.pmService'
  Add-ErrorIf (-not (Test-Bool $pmExists)) $errors 'native:pm_exists_type'
  if($pmExists -is [bool] -and $pmExists) {
    Add-ErrorIf (-not (Test-Integer $pmPid) -or [int64]$pmPid -le 1) $errors 'native:pm_pid'
    Add-ErrorIf (-not (Test-Integer $pmPpid) -or [int64]$pmPpid -ne 1) $errors 'native:pm_ppid'
    Add-ErrorIf (-not (Test-Integer $pmInitPid) -or [int64]$pmInitPid -ne [int64]$pmPid) $errors 'native:pm_init_pid_mismatch'
    Add-ErrorIf ([string]$pmName -cne 'pm-service' -or [string]$pmCmd -cne 'pm-service' -or [string]$pmExe -cne '/vendor/bin/pm-service') $errors 'native:pm_identity'
  } else {
    Add-ErrorIf ($null -ne $pmPid -or $null -ne $pmPpid -or $null -ne $pmName -or $null -ne $pmCmd -or $null -ne $pmExe -or $null -ne $pmInitPid) $errors 'native:absent_pm_has_identity'
  }

  $pmOwns=($pmExists -is [bool] -and $pmExists -and (Test-Integer $pmPid) -and @($ownerPids | Where-Object {$_ -eq [int64]$pmPid}).Count -eq 1)
  $holderOwns=($holderLive -and (Test-Integer $holderPid) -and @($ownerPids | Where-Object {$_ -eq [int64]$holderPid}).Count -eq 1)
  $knownOwnerCount=0
  if($pmOwns){$knownOwnerCount++}
  if($holderOwns){$knownOwnerCount++}
  Add-ErrorIf ($knownOwnerCount -ne @($ownerPids).Count) $errors 'native:unknown_owner'

  $cne=Get-Field $State 'cne' $errors 'root'
  $requestId=Get-Field $cne 'requestId' $errors 'cne'
  $satisfiedId=Get-Field $cne 'satisfiedId' $errors 'cne'
  $currentEvidence=Get-Field $cne 'currentEvidenceValid' $errors 'cne'
  Add-ErrorIf (-not (Test-Bool $currentEvidence) -or -not $currentEvidence) $errors 'cne:not_current_or_invalid'
  Add-ErrorIf ($null -ne $requestId -and (-not (Test-Integer $requestId) -or [int64]$requestId -lt 0)) $errors 'cne:request_id'
  Add-ErrorIf ($null -ne $satisfiedId -and (-not (Test-Integer $satisfiedId) -or [int64]$satisfiedId -lt 0)) $errors 'cne:satisfied_id'
  Add-ErrorIf ($null -ne $satisfiedId -and $null -eq $requestId) $errors 'cne:satisfied_without_request'

  $health=Get-Field $State 'health' $errors 'root'
  $imsRaw=Get-Field $health 'imsRegistrationRaw' $errors 'health'
  $transportRaw=Get-Field $health 'transportRaw' $errors 'health'
  $voiceIwlan=Get-Field $health 'voiceIwlanAvailable' $errors 'health'
  $wfcAvailable=Get-Field $health 'wfcAvailable' $errors 'health'
  $reportedStrong=Get-Field $health 'goldenStrong' $errors 'health'
  Add-ErrorIf (-not (Test-Integer $imsRaw) -or -not (Test-Integer $transportRaw)) $errors 'health:raw_type'
  Add-ErrorIf (-not (Test-Bool $voiceIwlan) -or -not (Test-Bool $wfcAvailable) -or -not (Test-Bool $reportedStrong)) $errors 'health:boolean_type'
  $calculatedStrong=((Test-Integer $imsRaw) -and [int64]$imsRaw -eq 2 -and (Test-Integer $transportRaw) -and [int64]$transportRaw -eq 2 -and $voiceIwlan -eq $true -and $wfcAvailable -eq $true)
  Add-ErrorIf ($reportedStrong -is [bool] -and $reportedStrong -ne $calculatedStrong) $errors 'health:golden_strong_contradiction'

  $nativeClean=($x55Online -and $perMgrState -eq 'running' -and $pmOwns -and -not $holderOwns -and @($ownerPids).Count -eq 1)
  $frozen=($x55Online -and $holderOwns -and -not $pmOwns -and @($ownerPids).Count -eq 1 -and @('running','stopped') -contains [string]$perMgrState)
  # This is not a generic UNKNOWN promotion. It is the exact, previously
  # authoritative frozen-split fingerprint: the audited holder is the sole
  # owner, native pm-service is alive but is not an owner, per_mgr is running,
  # vendor state is OFFLINE while the kernel state remains ONLINE, and every
  # fixed target/process/current-evidence gate above has passed.
  $frozenSplit=($x55FrozenSplit -and $perMgrState -eq 'running' -and $holderOwns -and -not $pmOwns -and @($ownerPids).Count -eq 1)
  $classification='UNKNOWN'
  $writeEligible=$false
  if($errors.Count -eq 0 -and $qcrilValid) {
    if($calculatedStrong -and ($nativeClean -or $frozen)) {
      $classification='HEALTHY_FREEZE'
    } elseif([int64]$airplaneMode -eq 0 -and $nativeClean) {
      $classification='A0_READY'
      $writeEligible=$true
    } elseif([int64]$airplaneMode -eq 1 -and $nativeClean) {
      $classification='P0_READY'
      $writeEligible=$true
    } elseif([int64]$airplaneMode -eq 0 -and $frozen) {
      $classification='FROZEN_RESIDUE'
      $writeEligible=$true
    } elseif([int64]$airplaneMode -eq 0 -and $frozenSplit) {
      $classification='FROZEN_SPLIT_RESIDUE'
      # The only write this classification may authorize is the existing,
      # identity-gated qcrild2 reacquire normalization. Callers must not treat
      # this as general write eligibility.
      $writeEligible=$false
    }
  }

  [pscustomobject][ordered]@{
    schema='voxi-wfc-lightweight-classification-v1'
    classification=$classification
    writeEligible=$writeEligible
    failClosed=($classification -eq 'UNKNOWN')
    goldenStrong=$calculatedStrong
    nativeClean=$nativeClean
    frozenResidue=$frozen
    frozenSplitResidue=$frozenSplit
    errors=@($errors)
  }
}

$resolved=(Resolve-Path -LiteralPath $InputPath).Path
$state=Get-Content -LiteralPath $resolved -Raw | ConvertFrom-Json
$result=Classify-LightweightState $state
if($OutputFormat -eq 'Text') {
  Write-Output ("CLASSIFICATION={0}" -f $result.classification)
  Write-Output ("WRITE_ELIGIBLE={0}" -f $result.writeEligible)
  Write-Output ("FAIL_CLOSED={0}" -f $result.failClosed)
  foreach($errorItem in @($result.errors)){Write-Output ("ERROR={0}" -f $errorItem)}
} else {
  $result | ConvertTo-Json -Depth 6 -Compress
}
