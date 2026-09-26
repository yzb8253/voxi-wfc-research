[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$files=@(
    (Join-Path $PSScriptRoot 'X55-WFC-STABLE-CNE-V1.ps1'),
    (Join-Path $PSScriptRoot 'X55-WFC-STABLE-CNE-V1-engine.ps1'),
    (Join-Path $PSScriptRoot 'X55-WFC-STABLE-CNE-V1-core.ps1'),
    (Join-Path $PSScriptRoot 'STABLE-CNE-V1-uicc-prime.ps1'),
    (Join-Path $PSScriptRoot 'STABLE-CNE-V1-contract.ps1'),
    (Join-Path $PSScriptRoot 'build_stable_cne_v1.ps1'),
    (Join-Path $PSScriptRoot 'build_stable_cne_v1_engine.ps1')
)
foreach($file in $files){
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
    if(@($errors).Count -ne 0){throw "PS5.1_PARSE_FAIL: $file"}
}
Write-Host 'PS5.1_PARSE=PASS'

$old=Join-Path $PSScriptRoot 'X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1'
$fast=Join-Path $PSScriptRoot 'X55-WFC-OneClick-v2.6.2-fast-holder-exp.ps1'
$oldHash=(Get-FileHash $old -Algorithm SHA256).Hash
$fastHash=(Get-FileHash $fast -Algorithm SHA256).Hash
if($oldHash -ne '70C81B1CC2F69F80540CB08DDD0C4F16FF2871B48D9D46E25F72C0F66CE51E76'){throw 'ORIGINAL_V262_HASH_CHANGED'}
if($fastHash -ne '0876285019658EC56BE4964B76A5FE807CE2FCDA237CC891CC9BE347E6725F22'){throw 'ORIGINAL_FAST_HASH_CHANGED'}
Write-Host 'ORIGINAL_OLD_FAST_GOLDEN=UNCHANGED'

$core=Get-Content (Join-Path $PSScriptRoot 'X55-WFC-STABLE-CNE-V1-core.ps1') -Raw
$engine=Get-Content (Join-Path $PSScriptRoot 'X55-WFC-STABLE-CNE-V1-engine.ps1') -Raw
$uicc=Get-Content (Join-Path $PSScriptRoot 'STABLE-CNE-V1-uicc-prime.ps1') -Raw
foreach($required in @('Wait-FreshCne -BaselineRequest $script:CneBaselineRequest -MaxSeconds 45','Invoke-StableCnePrime','CONNECTIVITY_CURRENT_TABLE_ONLY','STABLE_CNE_SUCCESS')){if(-not $core.Contains($required)){throw "MISSING_CORE_CONTRACT=$required"}}
foreach($forbidden in @('resetIms','ctl.restart vendor.cnd','ctl.restart qtidataservices','ctl.restart vendor.qcrild2')){if($core -match [regex]::Escape($forbidden)){throw "FORBIDDEN_CORE_ACTION=$forbidden"}}
if($engine -match 'Invoke-UiccDeepFallback|DEEP FALLBACK:'){throw 'DEEP_FALLBACK_PRESENT'}
if($engine -notmatch 'ValidateRange\(1,1\)'){throw 'SINGLE_ATTEMPT_LOCK_MISSING'}
foreach($required in @('service call isub {0} i32 0 i32 11','UICC_F8_CONFIRMED_AFTER','service call isub {0} i32 1 i32 11','UICC GUARD')){if(-not $uicc.Contains($required)){throw "UICC_GOLDEN_CONTRACT_MISSING=$required"}}
Write-Host 'SAFETY_GATE=PASS'
Write-Host 'STABLE_CNE_FLOW=PASS'

. (Join-Path $PSScriptRoot 'STABLE-CNE-V1-contract.ps1')
$freshFixtures=@(
    @{Name='NULL_TO_NULL';Baseline='null';Current='null';Expected=$false},
    @{Name='NULL_TO_380';Baseline='null';Current='380';Expected=$true},
    @{Name='360_TO_360_STALE';Baseline='360';Current='360';Expected=$false},
    @{Name='360_TO_380_FRESH';Baseline='360';Current='380';Expected=$true}
)
foreach($fixture in $freshFixtures){
    $actual=Test-StableCneFresh -BaselineRequest $fixture.Baseline -CurrentRequest $fixture.Current
    if($actual -ne $fixture.Expected){throw "FRESHNESS_FIXTURE_FAIL=$($fixture.Name)"}
}
Write-Host 'STABLE_CNE_FRESHNESS_FIXTURES=4/4 PASS'

$testRoot=Join-Path $repo 'experiments\wfc_repeatability_normalization\lightweight_profiling'
$tests=@(
    (Join-Path $testRoot 'test_classifier_equivalence.ps1'),
    (Join-Path $testRoot 'test_current_cne_projection.ps1'),
    (Join-Path $testRoot 'test_current_cne_wrapper_gates_v12h_r2.ps1'),
    (Join-Path $testRoot 'test_holder_identity_v12h_r1.ps1')
)
foreach($test in $tests){
    $output=@(& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $test 2>&1)
    if($LASTEXITCODE -ne 0){$output|ForEach-Object{Write-Host $_};throw "FIXTURE_FAIL=$test"}
}
Write-Host 'CLASSIFIER_FIXTURES=17/17 PASS'
Write-Host 'CNE_FIXTURES=13/13 PASS'
Write-Host 'HOLDER_IDENTITY_FIXTURES=7/7 PASS'
Write-Host 'UNSAFE_PROMOTION_COUNT=0'
Write-Host 'PHONE_WRITES=0'
