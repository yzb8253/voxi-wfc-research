Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Classifier=Join-Path $Repo 'experiments\wfc_repeatability_normalization\lightweight_profiling\classify_lightweight_state.ps1'
$Fixtures=Join-Path $Repo 'experiments\wfc_repeatability_normalization\lightweight_profiling\fixtures'
$Helper=Join-Path $PSScriptRoot 'prepare_frozen_residue_split.ps1'
$Engine=Join-Path $PSScriptRoot 'X55-WFC-AGGRESSIVE-CONSERVATIVE-v1.2H-engine.ps1'

function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Classify([string]$Name){((& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Classifier -InputPath (Join-Path $Fixtures $Name) -OutputFormat Json)|ConvertFrom-Json)}

$frozen=Classify '03_frozen_holder_residue.json'
$unknownOwner=Classify '09_unknown_owner.json'
$mapping=Classify '13_target_mapping_error.json'
$uicc=Classify '14_uicc_disabled.json'
$qcril=Classify '15_qcrild2_identity_error.json'
Require ($frozen.classification -eq 'FROZEN_RESIDUE' -and $frozen.writeEligible -and @($frozen.errors).Count -eq 0) 'exact frozen fixture rejected'
foreach($case in @($unknownOwner,$mapping,$uicc,$qcril)){Require ($case.classification -eq 'UNKNOWN' -and -not $case.writeEligible) 'unsafe fixture promoted'}

$helperText=Get-Content -LiteralPath $Helper -Raw
$engineText=Get-Content -LiteralPath $Engine -Raw
Require (@([regex]::Matches($helperText,"Root 'setprop ctl.start vendor.per_mgr'")).Count -eq 1) 'helper must contain exactly one controlled start site'
Require ($helperText -notmatch 'ctl\.restart vendor\.per_mgr|ctl\.stop vendor\.per_mgr|kill -9|pkill|killall|setSimCardPower|setUiccApplicationsEnabled') 'helper contains forbidden mutation'
Require ($helperText -match "vendor -ceq 'ONLINE'.*kernel -ceq 'ONLINE'" -and $helperText -match "v -ceq 'OFFLINE'.*k -ceq 'ONLINE'") 'ordinary/split fingerprints are not distinct'
Require ($engineText -match "prepareRc -eq 40" -and $engineText -match "prepareRc -eq 0" -and $engineText -match 'STOP with no further writes') 'engine fail-closed transition contract missing'

Write-Host 'V12H_FROZEN_FAST_PATH_FIXTURES=PASS'
Write-Host 'UNSAFE_PROMOTION_COUNT=0'
Write-Host 'PER_MGR_START_SITES=1'
Write-Host 'FORBIDDEN_MUTATIONS=0'
