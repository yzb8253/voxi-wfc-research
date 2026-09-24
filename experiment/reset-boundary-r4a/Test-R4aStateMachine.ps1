[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$files=@(
  'Invoke-Qcrild2ColdEpoch.ps1',
  'Invoke-R4aCycle.ps1',
  'Initialize-R4aControl.ps1',
  'Run-R4aThreeCycle.ps1',
  '..\reset-boundary-r3\Prepare-R3Cycle.ps1',
  '..\..\experiments\wfc_repeatability_normalization\v263_state_machine\X55-WFC-OneClick-v2.6.3-repeatable-state-machine.ps1'
)|ForEach-Object{(Resolve-Path (Join-Path $PSScriptRoot $_)).Path}
foreach($file in $files){$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors);if($errors.Count){throw "PS5_PARSE_ERROR file=$file count=$($errors.Count)"}}
$cycle=Get-Content (Join-Path $PSScriptRoot 'Invoke-R4aCycle.ps1') -Raw
$order=@(
  "Run `$R3 (`$common+@('-StopAfterR0','-LabelPrefix','R4A_R0'))",
  "Run `$Producer @('-Cycle',[string]`$Cycle,'-Execute','-RunName',`$RunName)",
  "Run `$R3 (`$common+@('-LabelPrefix','R4A'))",
  "Run `$Pipeline @('-Cycle',[string]`$Cycle,'-Execute','-RunName',`$RunName)"
)
$last=-1
foreach($token in $order){$index=$cycle.IndexOf($token,[StringComparison]::Ordinal);if($index -le $last){throw "R4A_ORDER_INVALID=$token"};$last=$index}
$producer=Get-Content (Join-Path $PSScriptRoot 'Invoke-Qcrild2ColdEpoch.ps1') -Raw
if(([regex]::Matches($producer,[regex]::Escape("Root-Write 'setprop ctl.restart vendor.qcrild2'"))).Count -ne 1){throw 'QCRILD2_RESTART_CALL_COUNT_INVALID'}
foreach($forbidden in @('qtidataservices restart','vendor.cnd','resetIms','kill -9','airplane-mode enable')){if($producer -match [regex]::Escape($forbidden)){throw "PRODUCER_CONTAINS_FORBIDDEN=$forbidden"}}
foreach($required in @('Combined-EventEvidence','IIWlan-IBase-debug/history','PRODUCER_EPOCH_LOWER_BOUND','STALE_HISTORY_REJECTED=YES','cycle_{0}_producer_evidence.json')){if($producer -notmatch [regex]::Escape($required)){throw "EVIDENCE_ADAPTER_MISSING=$required"}}
$r3=Get-Content (Resolve-Path (Join-Path $PSScriptRoot '..\reset-boundary-r3\Prepare-R3Cycle.ps1')) -Raw
if($r3 -notmatch 'runs\\\{0\}\\snapshots.*-f \$RunName'){throw 'R3_RUNNAME_SNAPSHOT_BINDING_MISSING'}
Write-Host 'PS5_PARSE=PASS'
Write-Host 'R4A_ORDER_AUDIT=PASS'
Write-Host 'QCRILD2_RESTART_MAX_ONE=PASS'
Write-Host 'NO_ADAPTIVE_FALLBACK=PASS'
Write-Host 'RUNNAME_SNAPSHOT_BINDING=PASS'
Write-Host 'EVIDENCE_ADAPTER_AUDIT=PASS'
Write-Host 'PHONE_WRITES=0'
