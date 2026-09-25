[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$classifier=Join-Path $repo 'experiments\wfc_repeatability_normalization\lightweight_profiling\classify_lightweight_state.ps1'
$fixture=Join-Path $repo 'experiments\wfc_repeatability_normalization\lightweight_profiling\fixtures\03_frozen_holder_residue.json'
$engine=Join-Path $PSScriptRoot 'X55-WFC-AGGRESSIVE-CONSERVATIVE-v0.ps1'
$entry=Join-Path $PSScriptRoot 'X55-WFC-AGGRESSIVE-CONSERVATIVE-v1.ps1'
$reacquire=Join-Path $PSScriptRoot 'normalize_a1_qcrild2_reacquire.ps1'
$core=Join-Path $PSScriptRoot 'X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1'
$expectedCoreHash='70C81B1CC2F69F80540CB08DDD0C4F16FF2871B48D9D46E25F72C0F66CE51E76'
$failures=New-Object 'System.Collections.Generic.List[string]'

function Check([bool]$Condition,[string]$Name) {
    if($Condition){Write-Host "PASS $Name"}else{$failures.Add($Name);Write-Host "FAIL $Name"}
}

foreach($file in @($classifier,$engine,$entry,$reacquire,$core)) {
    $tokens=$null;$errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
    Check (@($errors).Count -eq 0) ("PS5_PARSE " + (Split-Path $file -Leaf))
}

Check ((Get-FileHash -LiteralPath $core -Algorithm SHA256).Hash -ceq $expectedCoreHash) 'V262_CORE_HASH_FROZEN'
$engineText=Get-Content -LiteralPath $engine -Raw
Check ($engineText -match "ASettleMinSeconds=5" -and $engineText -match "ASettleMaxSeconds=20") 'A_DYNAMIC_5_20_UNCHANGED'
Check ($engineText -match "PSettleMinSeconds=5" -and $engineText -match "PSettleMaxSeconds=20") 'P_DYNAMIC_5_20_UNCHANGED'
Check ($engineText -match "ValidateRange\(1,3\).*MaxRecoveryAttempts = 2") 'ATTEMPT_DEFAULT_UNCHANGED'
Check ($engineText -match "V1_FROZEN_SPLIT_NORMALIZATION=START action=EXISTING_QCRILD2_REACQUIRE_ONLY") 'SPLIT_ACTION_SCOPED_TO_REACQUIRE'
Check ($engineText -match "POST_NORMALIZATION_FULL_FALLBACK=START") 'POST_LIGHT_FAIL_CLOSED_FULL_FALLBACK'

$state=Get-Content -LiteralPath $fixture -Raw|ConvertFrom-Json
$state.native.perMgrState='running'
$state.native.vendorX55State='OFFLINE'
$state.native.kernelX55State='ONLINE'
$state.native.pmService=[pscustomobject]@{processExists=$true;pid=24001;ppid=1;name='pm-service';cmdline='pm-service';exe='/vendor/bin/pm-service';initPid=24001}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('voxi-split-'+[guid]::NewGuid().ToString('N')+'.json')
try {
    [IO.File]::WriteAllText($temp,($state|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    $result=(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $classifier -InputPath $temp -OutputFormat Json)|ConvertFrom-Json
    Check ($result.classification -ceq 'FROZEN_SPLIT_RESIDUE') 'EXACT_SPLIT_CLASSIFIED'
    Check (-not $result.writeEligible -and -not $result.failClosed) 'SPLIT_NOT_GENERAL_WRITE_ELIGIBLE'

    $state.holder.fd9Target=$null
    [IO.File]::WriteAllText($temp,($state|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    $bad=(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $classifier -InputPath $temp -OutputFormat Json)|ConvertFrom-Json
    Check ($bad.classification -ceq 'UNKNOWN' -and $bad.failClosed) 'SPLIT_IDENTITY_MISMATCH_FAILS_CLOSED'
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}

if($failures.Count -ne 0) {
    Write-Host ("AUDIT=FAIL count={0}" -f $failures.Count)
    exit 1
}
Write-Host 'AUDIT=PASS'
Write-Host 'PHONE_WRITES=0'
exit 0
