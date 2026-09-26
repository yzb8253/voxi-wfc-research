[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Base=Join-Path $Repo 'experiments\wfc_repeatability_normalization\v262_freeze_run'
$Light=Join-Path $Repo 'experiments\wfc_repeatability_normalization\lightweight_profiling'
$Main=Join-Path $PSScriptRoot 'X55-WFC-GOLDEN-SIMPLE-V1.ps1'
$Contract=Join-Path $PSScriptRoot 'golden_simple_contract.ps1'
$Cmd=Join-Path $PSScriptRoot 'RUN-X55-WFC-GOLDEN-SIMPLE-V1.cmd'
$Uicc=Join-Path $Base 'uicc_apps_deep_fallback.ps1'
. $Contract
. (Join-Path $Light 'current_cne_projection_v12h_r2.ps1')

function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Parse-Ps51([string]$Path){$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseFile($Path,[ref]$t,[ref]$e);Require (@($e).Count -eq 0) ("PS5.1 parse failed: {0}: {1}" -f $Path,(@($e|ForEach-Object{$_.Message}) -join '; '))}

foreach($path in @($Main,$Contract,$Uicc)){Parse-Ps51 $path}
Write-Host 'PS5.1_PARSER=PASS'

$sub1='{id=1 iccId=x simSlotIndex=0 carrierId=2237 mcc=460 mnc=11 areUiccApplicationsEnabled=true}'
$sub11='{id=11 iccId=x simSlotIndex=1 carrierId=28 mcc=234 mnc=15 areUiccApplicationsEnabled=true}'
$f8='{id=11 iccId=x simSlotIndex=-1 carrierId=28 mcc=234 mnc=15 areUiccApplicationsEnabled=false}'
$dump=$sub1+"`n"+$sub11
Require (Test-GoldenSimpleProtectedSlot0 $dump) 'protected slot0 fixture failed'
Require (Test-GoldenSimpleVoxiEnabled $dump) 'VOXI enabled fixture failed'
Require (Test-GoldenSimpleF8 ($sub1+"`n"+$f8)) 'F8 fixture failed'
Require (-not (Test-GoldenSimpleVoxiEnabled ($sub1+"`n"+$f8))) 'F8 incorrectly accepted as enabled'
Write-Host 'UICC_PARSER_FIXTURES=4/4_PASS'

Require (Test-GoldenSimpleFreshCne $null 360) 'null->360 freshness failed'
Require (Test-GoldenSimpleFreshCne 360 374) '360->374 freshness failed'
Require (-not (Test-GoldenSimpleFreshCne 360 360)) 'same request incorrectly fresh'
Require (-not (Test-GoldenSimpleFreshCne $null $null)) 'null->null incorrectly fresh'
Write-Host 'CNE_FRESHNESS_FIXTURES=4/4_PASS'

$currentFixture=Get-Content -LiteralPath (Join-Path $Light 'fixtures\cne_active_current_android13.txt') -Raw
$staleFixture=Get-Content -LiteralPath (Join-Path $Light 'fixtures\cne_null_current_stale_history_android13.txt') -Raw
$active=Get-CurrentCneProjection $currentFixture 11;$stale=Get-CurrentCneProjection $staleFixture 11;$missing=Get-CurrentCneProjection 'Network Requests: none' 11
Require ($active.valid -and $active.requestId -eq 262 -and $active.satisfiedId -eq 262) 'active current-table fixture failed'
Require ($stale.valid -and $null -eq $stale.requestId -and $null -eq $stale.satisfiedId) 'historical stale request leaked into current projection'
Require (-not $missing.valid) 'missing current-table boundary did not fail closed'
Write-Host 'CNE_CURRENT_TABLE_FIXTURES=3/3_PASS'

$uiccText=Get-Content -LiteralPath $Uicc -Raw
Require ($uiccText -match "Require \(\(Root 'settings get global airplane_mode_on'\) -eq '0'\)") 'audited helper airplane-OFF gate missing'
Require ($uiccText -match '\$mustReenable=\$true' -and $uiccText -match 'finally\s*\{\s*if\(\$mustReenable\)' -and $uiccText -match 'Sending one emergency TRUE') 'emergency TRUE rollback contract missing'
Require ($uiccText -match 'UICC_F8_CONFIRMED_AFTER=' -and $uiccText -match 'UICC_REINSERT_CONFIRMED_AFTER=') 'audited F8/reinsert gates missing'
Write-Host 'EMERGENCY_TRUE_ROLLBACK_TEST=PASS'

$mainText=Get-Content -LiteralPath $Main -Raw
Require ($mainText -notmatch 'stop vendor\.per_mgr|ctl\.stop vendor\.per_mgr|restart vendor\.cnd|restart qtidataservices|resetIms') 'forbidden main-path mutation found'
Require ($mainText -match '\$SimPowerTransaction=182' -and $mainText -match 'Start-Sleep -Seconds 3') 'fixed SIM transaction/hold contract missing'
Require ($mainText -match '\$CneFreshWaitMax=45' -and $mainText -match 'Get-CurrentCneProjection' -and $mainText -match 'mNetworkRequestInfoLogs|current-table boundary') 'CNE wait/current-table contract missing'
Require ($mainText -match 'uicc_apps_deep_fallback\.ps1' -and $mainText -notmatch 'STABLE-CNE-V1-uicc-prime') 'exact original UICC helper is not used'
Require ((Get-Content -LiteralPath $Cmd -Raw) -match 'powershell\.exe -NoProfile -ExecutionPolicy Bypass') 'CMD does not force Windows PowerShell'
Write-Host 'STATIC_SAFETY_GATE=PASS'

$classifierOut=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Light 'test_classifier_equivalence.ps1') -ResultsPath (Join-Path $env:TEMP ('golden-simple-classifier-'+[guid]::NewGuid().ToString('N')+'.csv')) 2>&1)
Require ($LASTEXITCODE -eq 0) ("classifier fixtures failed: {0}" -f ($classifierOut -join '; '))
Write-Host 'CLASSIFIER_FIXTURES=PASS'
$holderOut=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Light 'test_holder_identity_v12h_r1.ps1') 2>&1)
Require ($LASTEXITCODE -eq 0) ("holder identity fixtures failed: {0}" -f ($holderOut -join '; '))
Write-Host 'LEGACY_RESIDUE_IDENTITY=PASS'

$protected=@(
 'experiments/wfc_repeatability_normalization/v262_freeze_run/X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1',
 'experiments/wfc_repeatability_normalization/v262_freeze_run/X55-WFC-OneClick-v2.6.2-fast-holder-exp.ps1',
 'experiments/wfc_repeatability_normalization/v262_freeze_run/X55-WFC-STABLE-v1.ps1',
 'experiments/wfc_repeatability_normalization/v262_freeze_run/X55-WFC-STABLE-CNE-V1-core.ps1',
 'experiments/wfc_repeatability_normalization/v262_freeze_run/X55-WFC-STABLE-CNE-V1-engine.ps1'
)
$changed=@(& git -C $Repo diff --name-only -- $protected)
Require (@($changed).Count -eq 0) 'historical core/baseline file was modified'
Write-Host 'HISTORICAL_BASELINES_UNCHANGED=YES'
Write-Host 'PHONE_WRITES=0'
Write-Host 'STATIC_RESULT=PASS'
