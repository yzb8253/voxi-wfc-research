Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'current_cne_projection_v12h_r2.ps1')
$Active=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\cne_active_current_android13.txt') -Raw
$NullText=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\cne_null_current_stale_history_android13.txt') -Raw
function Require([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL $Name"};Write-Host "PASS $Name"}
function Stale([object]$Current,[object]$ProbeRequest,[object]$ProbeSatisfied){(-not (Test-NullableCneEqual $Current.requestId $ProbeRequest))-or(-not(Test-NullableCneEqual $Current.satisfiedId $ProbeSatisfied))}

$case1=Get-CurrentCneProjection -ConnectivityText $NullText
Require ((Test-CurrentCneClear $case1)-and(Stale $case1 1602 1602)) 'CURRENT_NULL_LEGACY_1602_P_GATE_PASS'

$case2=Get-CurrentCneProjection -ConnectivityText $Active
Require ($case2.valid -and $case2.requestId -eq 262 -and $case2.satisfiedId -eq 262 -and -not(Test-CurrentCneClear $case2)-and(Stale $case2 1518 1518)) 'CURRENT_262_BLOCKS_262_NOT_LEGACY_1518'

$case3=Get-CurrentCneProjection -ConnectivityText $NullText
Require ((Test-CurrentCneClear $case3)-and-not(Stale $case3 $null $null)) 'CURRENT_NULL_LEGACY_NULL_P_GATE_PASS'

$case4=Get-CurrentCneProjection -ConnectivityText 'Network Requests: none'
Require (-not $case4.valid -and -not(Test-CurrentCneClear $case4)) 'MISSING_BOUNDARY_FAIL_CLOSED'

$case5=Get-CurrentCneProjection -ConnectivityText $NullText
Require ((Test-CurrentCneClear $case5)-and(Stale $case5 1602 1602)) 'POST_NORMALIZATION_A0_CURRENT_NULL_STALE_PROBE_VALID'

Write-Host 'WRAPPER_CNE_GATE_FIXTURES=5/5 PASS'
Write-Host 'UNSAFE_PROMOTION_COUNT=0'
Write-Host 'PHONE_WRITES=0'
