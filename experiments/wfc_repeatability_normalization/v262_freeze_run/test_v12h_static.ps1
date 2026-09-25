Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Files=@(
    (Join-Path $PSScriptRoot 'X55-WFC-AGGRESSIVE-CONSERVATIVE-v1.2H-engine.ps1'),
    (Join-Path $PSScriptRoot 'X55-WFC-AGGRESSIVE-CONSERVATIVE-v1.2H.ps1'),
    (Join-Path $PSScriptRoot 'prepare_frozen_residue_split.ps1'),
    (Join-Path $PSScriptRoot 'X55-WFC-OneClick-v2.6.2-fast-holder-exp.ps1')
)
foreach($file in $Files){$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors);if(@($errors).Count -ne 0){throw "PS5.1 parse failure: $file"}}

$old=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1')
$fast=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'X55-WFC-OneClick-v2.6.2-fast-holder-exp.ps1')
if($old.Count -ne $fast.Count){throw 'FAST core line count differs'}
$different=@(for($i=0;$i -lt $old.Count;$i++){if($old[$i] -cne $fast[$i]){$i}})
if($different.Count -ne 1){throw "FAST core conceptual diff count != 1: $($different.Count)"}
$fastLine=$fast[$different[0]]
if($fastLine -notmatch 'trap.*TERM INT HUP' -or $fastLine -notmatch 'sleep 3600 9<&- &' -or $fastLine -notmatch 'wait.*child'){throw 'FAST holder audited structure missing'}

$engine=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'X55-WFC-AGGRESSIVE-CONSERVATIVE-v1.2H-engine.ps1') -Raw
foreach($required in @('$ASettleMinSeconds=5','$ASettleMaxSeconds=20','$PSettleMinSeconds=5','$PSettleMaxSeconds=20','X55-WFC-OneClick-v2.6.2-fast-holder-exp.ps1','FROZEN_RESIDUE_FAST_COUNT','FROZEN_SPLIT_FAST_COUNT','FULL_FALLBACK_COUNT')){if(-not $engine.Contains($required)){throw "engine invariant missing: $required"}}
foreach($forbidden in @('kill -9','pkill','killall')){if($fastLine -match [regex]::Escape($forbidden)){throw "forbidden holder primitive: $forbidden"}}

Write-Host 'PS5.1_PARSE=PASS'
Write-Host 'FAST_HOLDER_STATIC_AUDIT=PASS'
Write-Host 'FAST_CORE_CONCEPTUAL_DIFF_LINES=1'
Write-Host 'FROZEN_PATH_STATIC_AUDIT=PASS'
Write-Host 'PHONE_WRITES=0'
