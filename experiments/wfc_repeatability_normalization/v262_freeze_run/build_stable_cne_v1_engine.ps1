[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$source=Join-Path $PSScriptRoot 'X55-WFC-AGGRESSIVE-CONSERVATIVE-v1.2H-r2-engine.ps1'
$target=Join-Path $PSScriptRoot 'X55-WFC-STABLE-CNE-V1-engine.ps1'
$text=[IO.File]::ReadAllText($source)

function Replace-One([string]$Old,[string]$New,[string]$Label) {
    $first=$script:text.IndexOf($Old,[StringComparison]::Ordinal)
    if($first -lt 0){throw "Missing engine anchor: $Label"}
    if($script:text.IndexOf($Old,$first+$Old.Length,[StringComparison]::Ordinal) -ge 0){throw "Non-unique engine anchor: $Label"}
    $script:text=$script:text.Substring(0,$first)+$New+$script:text.Substring($first+$Old.Length)
}

Replace-One @'
[CmdletBinding()]
param(
    [string]$Serial = 'fd0ff892',
    [ValidateRange(1,3)][int]$MaxRecoveryAttempts = 2,
    [ValidateSet('V12H')][string]$A0PreflightMode = 'V12H',
    [ValidateSet('NONE','OLD','FAST')][string]$ABVariant = 'NONE'
)
'@ @'
[CmdletBinding()]
param(
    [string]$Serial = 'fd0ff892',
    [ValidateRange(1,1)][int]$MaxRecoveryAttempts = 1,
    [ValidateSet('V12H')][string]$A0PreflightMode = 'V12H'
)
$ABVariant = 'NONE'
'@ 'parameter lock'

Replace-One '$UiccDeepFallback = Join-Path $PSScriptRoot ''uicc_apps_deep_fallback.ps1''' '$StableUiccPrime = Join-Path $PSScriptRoot ''STABLE-CNE-V1-uicc-prime.ps1''' 'uicc dependency'
Replace-One @'
$OldHolderRecovery = Join-Path $PSScriptRoot 'X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1'
$FastHolderRecovery = Join-Path $PSScriptRoot 'X55-WFC-OneClick-v2.6.2-fast-holder-exp.ps1'
$Recovery = if($ABVariant -eq 'OLD'){$OldHolderRecovery}else{$FastHolderRecovery}
'@ @'
$Recovery = Join-Path $PSScriptRoot 'X55-WFC-STABLE-CNE-V1-core.ps1'
'@ 'recovery core'
Replace-One '        $UiccDeepFallback,' '        $StableUiccPrime,' 'syntax dependency'
Replace-One '    Require (Test-Path -LiteralPath $UiccDeepFallback) ("UICC deep fallback missing: {0}" -f $UiccDeepFallback)' '    Require (Test-Path -LiteralPath $StableUiccPrime) ("STABLE_CNE UICC prime missing: {0}" -f $StableUiccPrime)' 'platform dependency'

$text=$text.Replace('Aggressive-Conservative-Logs','Stable-CNE-Logs')
$text=$text.Replace('$VariantLabel = ''v1.2H''','$VariantLabel = ''STABLE-CNE-V1''')
$text=$text.Replace('X55-WFC-AGGRESSIVE-CONSERVATIVE-{0}-{1}.log','X55-WFC-STABLE-CNE-{0}-{1}.log')

$start=$text.IndexOf('function Invoke-UiccDeepFallback {',[StringComparison]::Ordinal)
$end=$text.IndexOf('$script:WrapperTotal =',$start,[StringComparison]::Ordinal)
if($start -lt 0 -or $end -lt 0){throw 'Missing deep function anchors'}
$text=$text.Substring(0,$start)+$text.Substring($end)

$start=$text.IndexOf('    if($safeA0Restored -and $noCneFailureCount',[StringComparison]::Ordinal)
$end=$text.IndexOf('    $script:WfcResult=''NOT_RECOVERED''',$start,[StringComparison]::Ordinal)
if($start -lt 0 -or $end -lt 0){throw 'Missing deep branch anchors'}
$text=$text.Substring(0,$start)+"    Log 'DEEP_FALLBACK=NOT_PRESENT_STABLE_CNE_V1'`n`n"+$text.Substring($end)

Replace-One 'Log ''MODE=AGGRESSIVE_CONSERVATIVE_V1_2H_R2''' 'Log ''MODE=STABLE_CNE_V1''' 'mode'
Replace-One @'
Log ("AB_VARIANT={0}" -f $ABVariant)
Log ("HOLDER_IMPL={0}" -f $(if($ABVariant -eq 'OLD'){'OLD'}else{'FAST'}))
'@ @'
Log 'STABLE_CNE_MAIN_PATH=UICC_FALSE_F8_TRUE'
Log 'HOLDER_IMPL=GOLDEN_V262'
'@ 'variant logging'
Replace-One 'Log ''X55 WFC AGGRESSIVE CONSERVATIVE v1.2H-r2 started''' 'Log ''X55 WFC STABLE_CNE_V1 started''' 'startup log'
Replace-One 'Log ("Core recovery is the isolated v2.6.2 {0}-holder copy; all non-holder core behavior is unchanged." -f $(if($ABVariant -eq ''OLD''){''OLD''}else{''FAST''}))' 'Log ''Core is an isolated v2.6.2-derived STABLE_CNE_V1 copy; original cores remain unchanged.''' 'core log'
Replace-One @'
    if($ABVariant -ne 'NONE') {
        Require ($MaxRecoveryAttempts -eq 1) 'A/B harness is locked to MaxRecoveryAttempts=1.'
        Log 'AB_DEEP_FALLBACK=DISABLED_BY_SINGLE_ATTEMPT_INVARIANT'
    }
'@ @'
    Require ($MaxRecoveryAttempts -eq 1) 'STABLE_CNE_V1 is locked to one core attempt.'
    Log 'SECOND_ATTEMPT=NOT_PRESENT DEEP_FALLBACK=NOT_PRESENT'
'@ 'single attempt gate'
Replace-One @'
        if($ABVariant -ne 'NONE'){
            $afterCne=Get-CurrentCneSnapshot
            Write-AbCoreResult -Healthy $coreHealthy -CurrentCne $afterCne -CoreExit $coreRc
        }
'@ '        $afterCne=Get-CurrentCneSnapshot' 'remove AB reporting'
Replace-One '        if($ABVariant -eq ''NONE''){$afterCne=Get-CurrentCneSnapshot}' '        $afterCne=Get-CurrentCneSnapshot' 'current cne failure capture'
$text=$text.Replace('within the bounded attempts and guarded deep fallback','within the single bounded STABLE_CNE_V1 attempt')

[IO.File]::WriteAllText($target,$text,(New-Object Text.UTF8Encoding($false)))
Write-Host "BUILT=$target"
