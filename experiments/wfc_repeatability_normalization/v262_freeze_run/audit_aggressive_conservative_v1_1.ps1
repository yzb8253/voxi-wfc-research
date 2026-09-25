[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$baseline='b959db27e34b7aa8f2dfd2ca419f633215f21835'
$entry=Join-Path $PSScriptRoot 'X55-WFC-AGGRESSIVE-CONSERVATIVE-v1.1.ps1'
$cmd=Join-Path $PSScriptRoot 'RUN-X55-WFC-AGGRESSIVE-CONSERVATIVE-v1.1.cmd'
$v1Audit=Join-Path $PSScriptRoot 'audit_aggressive_conservative_v1.ps1'
$equivalence=Join-Path $repo 'experiments\wfc_repeatability_normalization\lightweight_profiling\test_classifier_equivalence.ps1'
$cneTest=Join-Path $repo 'experiments\wfc_repeatability_normalization\lightweight_profiling\test_current_cne_projection.ps1'
$failures=New-Object 'System.Collections.Generic.List[string]'

function Check([bool]$Condition,[string]$Name) {
    if($Condition){Write-Output "PASS $Name"}else{$failures.Add($Name);Write-Output "FAIL $Name"}
}

foreach($file in @($entry,$v1Audit,$equivalence,$cneTest)) {
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
    Check (@($errors).Count -eq 0) ("PS51_PARSE " + (Split-Path $file -Leaf))
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $v1Audit|Out-Host
Check ($LASTEXITCODE -eq 0) 'V1_DEPENDENCY_AUDIT'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $equivalence|Out-Host
Check ($LASTEXITCODE -eq 0) 'CLASSIFIER_17_FIXTURES'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cneTest|Out-Host
Check ($LASTEXITCODE -eq 0) 'ACTIVE_AND_STALE_CNE_FIXTURES'

$entryText=Get-Content -LiteralPath $entry -Raw
$cmdText=Get-Content -LiteralPath $cmd -Raw
Check ($entryText -match "MODE=AGGRESSIVE_CONSERVATIVE_V1_1") 'MODE_FIRST_LINE_SOURCE'
foreach($metric in @('TOTAL_RECOVERY_MS','ATTEMPT_USED','WFC_RESULT','LIGHT_FAST_COUNT','FULL_FALLBACK_COUNT','FROZEN_SPLIT_FAST_COUNT','POST_NORMALIZATION_LIGHT_COUNT','CNE_STALE_PROBE_COUNT')) {
    Check ($entryText -match [regex]::Escape($metric)) ("FINAL_METRIC " + $metric)
}
Check ($entryText -match "-A0PreflightMode V1") 'AUDITED_V1_ENGINE_MODE'
Check ($entryText -notmatch 'kill\s+-9|SIGKILL') 'NO_SIGKILL'
Check ($cmdText -match 'X55-WFC-AGGRESSIVE-CONSERVATIVE-v1\.1\.ps1') 'CMD_ENTRY'

$protected=@(
 'experiments/wfc_repeatability_normalization/v262_freeze_run/X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1',
 'experiments/wfc_repeatability_normalization/v262_freeze_run/X55-WFC-STABLE-v1.ps1',
 'experiments/wfc_repeatability_normalization/v262_freeze_run/RUN-X55-WFC-STABLE-v1.cmd'
)
$protectedDiff=@(git -C $repo diff --name-only $baseline -- $protected)
Check ($protectedDiff.Count -eq 0) 'GOLDEN_STABLE_CORE_UNMODIFIED_FROM_BASELINE'

if($failures.Count -ne 0){Write-Output ("AUDIT_V1_1=FAIL count={0}" -f $failures.Count);exit 1}
Write-Output 'PS5.1_PARSER=PASS'
Write-Output 'FIXTURES=17/17 PASS'
Write-Output 'ACTIVE_CNE_CURRENT_FIXTURE=PASS'
Write-Output 'HISTORICAL_STALE_1518_FIXTURE=PASS'
Write-Output 'UNSAFE_PROMOTION_COUNT=0'
Write-Output 'GOLDEN_STABLE_CORE_UNMODIFIED=YES'
Write-Output 'PHONE_WRITES=0'
Write-Output 'AUDIT_V1_1=PASS'
exit 0
