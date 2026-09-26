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
$Uicc=Join-Path $PSScriptRoot 'uicc_apps_single_sim_prime.ps1'
$Observer=Join-Path $PSScriptRoot 'uicc_isub_section_observer.ps1'
$TypedJava=Join-Path $PSScriptRoot 'typed_helper\GoldenSimpleTypedUiccHelper.java'
$TypedJar=Join-Path $PSScriptRoot 'golden-simple-typed-uicc-helper.jar'
$OriginalUicc=Join-Path $Base 'uicc_apps_deep_fallback.ps1'
. $Contract
. (Join-Path $Light 'current_cne_projection_v12h_r2.ps1')
. $Observer

function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Parse-Ps51([string]$Path){$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseFile($Path,[ref]$t,[ref]$e);Require (@($e).Count -eq 0) ("PS5.1 parse failed: {0}: {1}" -f $Path,(@($e|ForEach-Object{$_.Message}) -join '; '))}

foreach($path in @($Main,$Contract,$Uicc,$Observer,(Join-Path $PSScriptRoot 'build_typed_uicc_helper.ps1'))){Parse-Ps51 $path}
Write-Host 'PS5.1_PARSER=PASS'

$sub1Stale='{id=1 iccId=x simSlotIndex=-1 carrierId=2237 mcc=460 mnc=11 areUiccApplicationsEnabled=true}'
$sub11='{id=11 iccId=x simSlotIndex=1 carrierId=28 mcc=234 mnc=15 areUiccApplicationsEnabled=true}'
$f8='{id=11 iccId=x simSlotIndex=-1 carrierId=28 mcc=234 mnc=15 areUiccApplicationsEnabled=false}'
$dump=$sub1Stale+"`n"+$sub11
Require (Test-GoldenSimpleSlot0Absent $dump 'ABSENT,LOADED') 'physical slot0 ABSENT fixture failed'
Require (-not (Test-GoldenSimpleSlot0Absent $dump 'LOADED,LOADED')) 'loaded slot0 incorrectly accepted'
Require (-not (Test-GoldenSimpleSlot0Absent ('{id=1 simSlotIndex=0 areUiccApplicationsEnabled=true}'+"`n"+$sub11) 'ABSENT,LOADED')) 'mapped slot0 incorrectly accepted'
Require (Test-GoldenSimpleVoxiEnabled $dump) 'VOXI enabled fixture failed'
Require (Test-GoldenSimpleF8 ($sub1Stale+"`n"+$f8)) 'F8 fixture failed'
Require (-not (Test-GoldenSimpleVoxiEnabled ($sub1Stale+"`n"+$f8))) 'F8 incorrectly accepted as enabled'
Write-Host 'UICC_PARSER_FIXTURES=6/6_PASS'

function New-IsubFixture([string]$ActiveRow,[string]$DbRow,[string]$AllRow,[string]$SlotMap='11',[string]$HistoryRow=''){
    "SubscriptionController:`nsSlotIndexToSubId[1]: subIds=1=[$SlotMap]`n++++++++++`nActiveSubInfoList:`n$ActiveRow`nActiveSubInfoList in the DB:`n$DbRow`n++++++++++`nAllSubInfoList:`n$AllRow`n++++++++++`n2026-09-17T00:00:00 - historical event $HistoryRow"
}
$enabled='  {id=11 simSlotIndex=1 carrierId=28 mcc=234 mnc=15 areUiccApplicationsEnabled=true}'
$disabled='  {id=11 simSlotIndex=-1 carrierId=28 mcc=234 mnc=15 areUiccApplicationsEnabled=false}'
$dbTrue='  {id=11 simSlotIndex=-1 carrierId=28 mcc=234 mnc=15 areUiccApplicationsEnabled=true}'
$normal=Get-IsubSectionObserver (New-IsubFixture $enabled $enabled $enabled) 'ABSENT,LOADED' 11
Require ((Get-IsubObserverState $normal) -eq 'RESTORED') 'normal active fixture did not classify RESTORED'
$f8obs=Get-IsubSectionObserver (New-IsubFixture '' $disabled $disabled '') 'ABSENT,ABSENT' 11
Require ((Get-IsubObserverState $f8obs) -eq 'F8') 'active-missing stored-disabled fixture did not classify F8'
$conflict=Get-IsubSectionObserver (New-IsubFixture '' $dbTrue $disabled '') 'ABSENT,ABSENT' 11
Require ((Get-IsubObserverState $conflict) -eq 'CONFLICT') 'DB/ALL conflict fixture did not fail closed'
$history=Get-IsubSectionObserver (New-IsubFixture '' $disabled $disabled '' $enabled) 'ABSENT,ABSENT' 11
Require (-not $history.Active.Present -and (Get-IsubObserverState $history) -eq 'F8') 'historical event leaked into current sections'
$restored=Get-IsubSectionObserver (New-IsubFixture $enabled $enabled $enabled) 'ABSENT,LOADED' 11
Require ((Get-IsubObserverState $restored) -eq 'RESTORED' -and $restored.Active.Slot -eq '1') 'TRUE restoration fixture failed'
Write-Host 'ISUB_SECTION_OBSERVER_FIXTURES=5/5_PASS'

Require (Test-GoldenSimpleFreshCne $null 360) 'null->360 freshness failed'
Require (Test-GoldenSimpleFreshCne 360 374) '360->374 freshness failed'
Require (-not (Test-GoldenSimpleFreshCne 360 360)) 'same request incorrectly fresh'
Require (-not (Test-GoldenSimpleFreshCne $null $null)) 'null->null incorrectly fresh'
Write-Host 'CNE_FRESHNESS_FIXTURES=4/4_PASS'

Require (Test-GoldenSimpleTun0DefaultRoute 'default dev tun0 table tun0 proto static scope link') 'direct tun0 default route fixture failed'
Require (Test-GoldenSimpleTun0DefaultRoute 'default via 10.0.0.1 dev tun0 proto static') 'via tun0 default route fixture failed'
Require (-not (Test-GoldenSimpleTun0DefaultRoute 'default via 192.168.1.1 dev wlan0 proto dhcp')) 'wlan0 default route incorrectly accepted as tun0'
Write-Host 'VPN_TUN_ROUTE_FIXTURES=3/3_PASS'

$currentFixture=Get-Content -LiteralPath (Join-Path $Light 'fixtures\cne_active_current_android13.txt') -Raw
$staleFixture=Get-Content -LiteralPath (Join-Path $Light 'fixtures\cne_null_current_stale_history_android13.txt') -Raw
$active=Get-CurrentCneProjection $currentFixture 11;$stale=Get-CurrentCneProjection $staleFixture 11;$missing=Get-CurrentCneProjection 'Network Requests: none' 11
Require ($active.valid -and $active.requestId -eq 262 -and $active.satisfiedId -eq 262) 'active current-table fixture failed'
Require ($stale.valid -and $null -eq $stale.requestId -and $null -eq $stale.satisfiedId) 'historical stale request leaked into current projection'
Require (-not $missing.valid) 'missing current-table boundary did not fail closed'
Write-Host 'CNE_CURRENT_TABLE_FIXTURES=3/3_PASS'

$uiccText=Get-Content -LiteralPath $Uicc -Raw
$observerText=Get-Content -LiteralPath $Observer -Raw
$javaText=Get-Content -LiteralPath $TypedJava -Raw
$mainText=Get-Content -LiteralPath $Main -Raw
Require ($uiccText -match "Require \(\(Root 'settings get global airplane_mode_on'\) -eq '0'\)") 'single-SIM helper airplane-OFF gate missing'
Require ($uiccText -match '\$mustReenable=\$true' -and $uiccText -match 'finally\s*\{\s*if\(\$mustReenable\)' -and $uiccText -match 'typed emergency TRUE') 'emergency TRUE rollback contract missing'
Require ($uiccText -match 'UICC_F8_CONFIRMED_AFTER=' -and $uiccText -match 'UICC_REINSERT_CONFIRMED_AFTER=') 'single-SIM F8/reinsert gates missing'
Require ($uiccText -match 'getprop gsm\.sim\.state' -and $observerText -match "states\[0\] -eq 'ABSENT'" -and $observerText -match 'simSlotIndex=0') 'slot0 ABSENT/no-mapping gate missing'
Require ($observerText -match 'ActiveSubInfoList in the DB:' -and $observerText -match 'AllSubInfoList:' -and $observerText -match 'ALL_SECTION_END_MISSING') 'section boundaries are not explicit/fail-closed'
Require ($uiccText -match 'Diagnostics\.Stopwatch' -and $uiccText -match 'Elapsed\.TotalSeconds -lt 30') 'F8 wait is not a wall-clock deadline'
$rawIsubWrites=@(($uiccText+"`n"+$mainText+"`n"+$javaText) -split "\r?\n"|Where-Object{$_ -match 'service call isub|service\s+call\s+isub'})
Require ($rawIsubWrites.Count -eq 0) 'raw service call isub remains in GOLDEN_SIMPLE_V1 runtime'
Require ($javaText -match 'ISub\$Stub' -and $javaText -match 'asInterface' -and $javaText -match 'setUiccApplicationsEnabled') 'typed ISub proxy path missing'
Require ($javaText -match '"disable"\.equals' -and $javaText -match '"enable"\.equals' -and $javaText -match 'boolean enabled = "enable"\.equals') 'typed disable/enable modes missing'
Require ($javaText -match 'private static final int SUB_ID = 11' -and $javaText -notmatch 'setUiccApplicationsEnabled"[^\r\n]*,[^\r\n]*(?:0|1|10|12)\)') 'typed write target is not fixed sub11'
Require ($uiccText -match "Invoke-Typed 'disable'" -and $uiccText -match "Invoke-Typed 'enable'" -and $uiccText -match 'TYPED_EMERGENCY_ENABLE=YES') 'normal/emergency typed transport wiring missing'
Require (Test-Path -LiteralPath $TypedJar) 'typed helper dex jar missing'
$jarHash=(Get-FileHash -LiteralPath $TypedJar -Algorithm SHA256).Hash
Require ($jarHash -eq '275C9760621AC0E02879961506EDC826236523808F9DBD7E7310A9C031D240B2') 'typed helper dex jar hash mismatch'
Require ($uiccText -match [regex]::Escape($jarHash)) 'runtime helper hash gate does not match built jar'
Require ((Get-FileHash -LiteralPath $Observer -Algorithm SHA256).Hash -eq '88C03D4E97FDF859F4D72C777F3338E40872D2E4C0C9337FD1AAB90DEC57E7E4') 'section observer changed during transport-only experiment'
Write-Host 'EMERGENCY_TRUE_ROLLBACK_TEST=PASS'
Write-Host 'TYPED_ISUB_TRANSPORT_TESTS=PASS'
Write-Host 'SLOT0_WRITE_PATHS=0'

Require ($mainText -notmatch 'stop vendor\.per_mgr|ctl\.stop vendor\.per_mgr|restart vendor\.cnd|restart qtidataservices|resetIms') 'forbidden main-path mutation found'
Require ($mainText -match '\$SimPowerTransaction=182' -and $mainText -match 'Start-Sleep -Seconds 3') 'fixed SIM transaction/hold contract missing'
Require ($mainText -match '\$CneFreshWaitMax=45' -and $mainText -match 'Get-CurrentCneProjection' -and $mainText -match 'mNetworkRequestInfoLogs|current-table boundary') 'CNE wait/current-table contract missing'
Require ($mainText -match 'uicc_apps_single_sim_prime\.ps1' -and $mainText -notmatch 'uicc_apps_deep_fallback|STABLE-CNE-V1-uicc-prime') 'independent single-SIM UICC helper is not exclusively used'
Require (@($mainText -split "\r?\n"|Where-Object{$_ -match 'service call phone' -and $_ -notmatch 'i32 1 i32 [01]'}).Count -eq 0) 'SIM power write is not fixed to slot1'
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
 'experiments/wfc_repeatability_normalization/v262_freeze_run/uicc_apps_deep_fallback.ps1',
 'experiments/wfc_repeatability_normalization/v262_freeze_run/X55-WFC-STABLE-CNE-V1-core.ps1',
 'experiments/wfc_repeatability_normalization/v262_freeze_run/X55-WFC-STABLE-CNE-V1-engine.ps1'
)
$changed=@(& git -C $Repo diff --name-only -- $protected)
Require (@($changed).Count -eq 0) 'historical core/baseline file was modified'
Write-Host 'HISTORICAL_BASELINES_UNCHANGED=YES'
Write-Host 'PHONE_WRITES=0'
Write-Host 'STATIC_RESULT=PASS'
