Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$Engine=Join-Path $PSScriptRoot 'X55-WFC-AGGRESSIVE-CONSERVATIVE-v1.2H-r2-engine.ps1'
$Wrapper=Join-Path $PSScriptRoot 'X55-WFC-HOLDER-AB-r2.ps1'
$Old=Join-Path $PSScriptRoot 'X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1'
$Fast=Join-Path $PSScriptRoot 'X55-WFC-OneClick-v2.6.2-fast-holder-exp.ps1'
$CmdOld=Join-Path $PSScriptRoot 'RUN-X55-WFC-AB-OLD-HOLDER.cmd'
$CmdFast=Join-Path $PSScriptRoot 'RUN-X55-WFC-AB-FAST-HOLDER.cmd'

foreach($file in @($Engine,$Wrapper,$Old,$Fast)){
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
    if(@($errors).Count -ne 0){throw "PS5.1 parse failure: $file"}
}

$oldLines=@(Get-Content -LiteralPath $Old)
$fastLines=@(Get-Content -LiteralPath $Fast)
if($oldLines.Count -ne $fastLines.Count){throw 'Core line counts differ.'}
$diff=@(for($i=0;$i -lt $oldLines.Count;$i++){if($oldLines[$i] -cne $fastLines[$i]){$i}})
if($diff.Count -ne 1){throw "Non-holder core differences found: $($diff.Count)"}
$oldHolder=$oldLines[$diff[0]]
$fastHolder=$fastLines[$diff[0]]
if($oldHolder -notmatch 'exec 9</dev/subsys_esoc0.*while true; do sleep 60; done'){throw 'OLD holder contract mismatch.'}
if($fastHolder -notmatch 'trap.*TERM INT HUP' -or $fastHolder -notmatch 'sleep 3600 9<&- &' -or $fastHolder -notmatch 'wait.*child'){throw 'FAST holder contract mismatch.'}
$oldNormalized=[string]::Join("`n",@($oldLines[0..($diff[0]-1)]+@('__HOLDER_IMPLEMENTATION__')+$oldLines[($diff[0]+1)..($oldLines.Count-1)]))
$fastNormalized=[string]::Join("`n",@($fastLines[0..($diff[0]-1)]+@('__HOLDER_IMPLEMENTATION__')+$fastLines[($diff[0]+1)..($fastLines.Count-1)]))
if($oldNormalized -cne $fastNormalized){throw 'Normalized core content differs outside holder implementation.'}

$engineText=Get-Content -LiteralPath $Engine -Raw
foreach($required in @("[ValidateSet('NONE','OLD','FAST')]","MaxRecoveryAttempts -eq 1",'CNE_WRITE_DECISION_SOURCE=CONNECTIVITY_CURRENT_TABLE_ONLY','Get-CurrentCneSnapshot','AB_DEEP_FALLBACK=DISABLED_BY_SINGLE_ATTEMPT_INVARIANT')){
    if(-not $engineText.Contains($required)){throw "A/B engine invariant missing: $required"}
}
if($engineText -notmatch 'noCneFailureCount -ge 2'){throw 'Deep fallback minimum-two-attempt guard changed.'}
$wrapperText=Get-Content -LiteralPath $Wrapper -Raw
if($wrapperText -notmatch '-MaxRecoveryAttempts 1'){throw 'A/B wrapper is not fixed to one attempt.'}
$oldCmd=Get-Content -LiteralPath $CmdOld -Raw
$fastCmd=Get-Content -LiteralPath $CmdFast -Raw
if($oldCmd -notmatch '-ABVariant OLD' -or $fastCmd -notmatch '-ABVariant FAST'){throw 'CMD variant binding mismatch.'}

$oldHash=(Get-FileHash -LiteralPath $Old -Algorithm SHA256).Hash
$fastHash=(Get-FileHash -LiteralPath $Fast -Algorithm SHA256).Hash
$sha=[Security.Cryptography.SHA256]::Create()
try{$normalizedHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($oldNormalized)))).Replace('-','')}finally{$sha.Dispose()}

Write-Host 'PS5.1_PARSE=PASS'
Write-Host 'AB_CORE_DIFF_LINES=1'
Write-Host 'AB_ONLY_BEHAVIOR_DIFF=HOLDER_IMPLEMENTATION'
Write-Host 'AB_NORMALIZED_DIFF=IDENTICAL'
Write-Host ("OLD_CORE_SHA256={0}" -f $oldHash)
Write-Host ("FAST_CORE_SHA256={0}" -f $fastHash)
Write-Host ("NORMALIZED_CORE_SHA256={0}" -f $normalizedHash)
Write-Host 'MAX_RECOVERY_ATTEMPTS=1'
Write-Host 'DEEP_FALLBACK_REACHABLE=NO'
Write-Host 'PHONE_WRITES=0'
