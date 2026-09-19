$ErrorActionPreference = 'Stop'

function Invoke-FullLifecycleModel {
    param(
        [ValidateSet('F1','HEALTHY','F8','UNSAFE')] [string] $Initial = 'F1',
        [bool] $RemoveSucceeds = $true,
        [bool] $F8Confirmed = $true,
        [bool] $MarkerPersists = $true,
        [bool] $NewBootId = $true,
        [bool] $PostBootF8 = $true,
        [bool] $NetworkReady = $true,
        [bool] $PreInsertF8 = $true,
        [bool] $InsertSucceeds = $true,
        [bool] $WfcRecovers = $true
    )
    $r = [ordered]@{ falseCalls=0; reboots=0; trueCalls=0; stage='IDLE'; outcome='' }
    if ($Initial -ne 'F1') { $r.outcome='START_BLOCKED_ZERO_WRITE'; return [pscustomobject]$r }
    $r.falseCalls=1
    if (-not $RemoveSucceeds) { $r.outcome='REMOVE_FAILED'; return [pscustomobject]$r }
    if (-not $F8Confirmed) { $r.outcome='F8_NOT_CONFIRMED'; return [pscustomobject]$r }
    if (-not $MarkerPersists) { $r.outcome='MARKER_FAILED'; return [pscustomobject]$r }
    $r.stage='WAITING_FOR_REBOOT'; $r.reboots=1
    if (-not $NewBootId) { $r.stage='FAILED'; $r.outcome='NEW_BOOT_NOT_CONFIRMED'; return [pscustomobject]$r }
    if (-not $PostBootF8) { $r.stage='FAILED'; $r.outcome='POST_BOOT_F8_FAILED'; return [pscustomobject]$r }
    $r.stage='WAITING_FOR_NETWORK'
    if (-not $NetworkReady) { $r.stage='FAILED'; $r.outcome='NETWORK_TIMEOUT'; return [pscustomobject]$r }
    if (-not $PreInsertF8) { $r.stage='FAILED'; $r.outcome='PRE_INSERT_F8_FAILED'; return [pscustomobject]$r }
    $r.stage='WAITING_TO_INSERT'; $r.trueCalls=1; $r.stage='WAITING_FOR_WFC'
    if (-not $InsertSucceeds) { $r.stage='FAILED'; $r.outcome='INSERT_FAILED_NO_RETRY'; return [pscustomobject]$r }
    if (-not $WfcRecovers) { $r.stage='FAILED'; $r.outcome='WFC_TIMEOUT_NO_RETRY'; return [pscustomobject]$r }
    $r.stage='COMPLETE'; $r.outcome='PASS'; return [pscustomobject]$r
}

$cases = @(
    @{Name='strict-f1-success'; Args=@{}; F=1; R=1; T=1; Stage='COMPLETE'; Outcome='PASS'},
    @{Name='healthy-blocked'; Args=@{Initial='HEALTHY'}; F=0; R=0; T=0; Stage='IDLE'; Outcome='START_BLOCKED_ZERO_WRITE'},
    @{Name='f8-start-blocked'; Args=@{Initial='F8'}; F=0; R=0; T=0; Stage='IDLE'; Outcome='START_BLOCKED_ZERO_WRITE'},
    @{Name='unsafe-blocked'; Args=@{Initial='UNSAFE'}; F=0; R=0; T=0; Stage='IDLE'; Outcome='START_BLOCKED_ZERO_WRITE'},
    @{Name='remove-fails'; Args=@{RemoveSucceeds=$false}; F=1; R=0; T=0; Stage='IDLE'; Outcome='REMOVE_FAILED'},
    @{Name='f8-not-confirmed'; Args=@{F8Confirmed=$false}; F=1; R=0; T=0; Stage='IDLE'; Outcome='F8_NOT_CONFIRMED'},
    @{Name='marker-not-persisted'; Args=@{MarkerPersists=$false}; F=1; R=0; T=0; Stage='IDLE'; Outcome='MARKER_FAILED'},
    @{Name='same-boot-blocked'; Args=@{NewBootId=$false}; F=1; R=1; T=0; Stage='FAILED'; Outcome='NEW_BOOT_NOT_CONFIRMED'},
    @{Name='post-boot-f8-fails'; Args=@{PostBootF8=$false}; F=1; R=1; T=0; Stage='FAILED'; Outcome='POST_BOOT_F8_FAILED'},
    @{Name='network-timeout'; Args=@{NetworkReady=$false}; F=1; R=1; T=0; Stage='FAILED'; Outcome='NETWORK_TIMEOUT'},
    @{Name='pre-insert-f8-fails'; Args=@{PreInsertF8=$false}; F=1; R=1; T=0; Stage='FAILED'; Outcome='PRE_INSERT_F8_FAILED'},
    @{Name='insert-fails-no-retry'; Args=@{InsertSucceeds=$false}; F=1; R=1; T=1; Stage='FAILED'; Outcome='INSERT_FAILED_NO_RETRY'},
    @{Name='wfc-timeout-no-retry'; Args=@{WfcRecovers=$false}; F=1; R=1; T=1; Stage='FAILED'; Outcome='WFC_TIMEOUT_NO_RETRY'}
)

$failed=0
foreach($c in $cases){
  $argsMap=$c.Args
  $a=Invoke-FullLifecycleModel @argsMap
  $pass=$a.falseCalls -eq $c.F -and $a.reboots -eq $c.R -and $a.trueCalls -eq $c.T -and $a.stage -eq $c.Stage -and $a.outcome -eq $c.Outcome
  if(-not $pass){$failed++}
  '{0}: {1} false={2} reboot={3} true={4} stage={5} outcome={6}' -f $c.Name,$(if($pass){'PASS'}else{'FAIL'}),$a.falseCalls,$a.reboots,$a.trueCalls,$a.stage,$a.outcome
}
if($failed){throw "$failed full lifecycle state-machine tests failed"}