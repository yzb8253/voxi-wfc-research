$ErrorActionPreference = 'Stop'

function Invoke-Model {
    param(
        [ValidateSet('HEALTHY','F8','F1','UNSAFE')] [string] $Initial,
        [bool] $PersistentF8 = $true,
        [bool] $Recovers = $true,
        [ValidateSet('boot','deep-recover','recover-hard','auto-run-now')] [string] $Mode = 'recover-hard',
        [bool] $BootMarkerExists = $false
    )

    $result = [ordered]@{ falseCalls = 0; trueCalls = 0; outcome = ''; markerRead = $false; markerCreated = $false }
    if ($Initial -eq 'HEALTHY') { $result.outcome = 'HEALTHY_ZERO_WRITE'; return [pscustomobject]$result }
    if ($Initial -eq 'UNSAFE') { $result.outcome = 'BLOCKED_ZERO_WRITE'; return [pscustomobject]$result }
    if ($Initial -eq 'F8') { $result.trueCalls = 1; $result.outcome = $(if ($Recovers) {'SAFE_SUCCESS'} else {'SAFE_FAILED_NO_RETRY'}); return [pscustomobject]$result }

    if ($Mode -eq 'boot') {
        $result.markerRead = $true
        if ($BootMarkerExists) { $result.outcome = 'BOOT_ALREADY_ATTEMPTED_ZERO_WRITE'; return [pscustomobject]$result }
        $result.markerCreated = $true
    }

    $result.falseCalls = 1
    if (-not $PersistentF8) { $result.outcome = 'F8_NOT_CONFIRMED_TRUE_BLOCKED'; return [pscustomobject]$result }
    $result.trueCalls = 1
    $result.outcome = $(if ($Recovers) {'DEEP_SUCCESS'} else {'DEEP_RECOVERY_FAILED_NO_RETRY'})
    return [pscustomobject]$result
}

$cases = @(
    @{ Name='healthy-zero-write'; Args=@{Initial='HEALTHY'}; False=0; True=0; Outcome='HEALTHY_ZERO_WRITE' },
    @{ Name='f8-safe-once'; Args=@{Initial='F8'}; False=0; True=1; Outcome='SAFE_SUCCESS' },
    @{ Name='f1-deep-once'; Args=@{Initial='F1'}; False=1; True=1; Outcome='DEEP_SUCCESS' },
    @{ Name='f8-not-confirmed'; Args=@{Initial='F1';PersistentF8=$false}; False=1; True=0; Outcome='F8_NOT_CONFIRMED_TRUE_BLOCKED' },
    @{ Name='post-insert-failure-no-retry'; Args=@{Initial='F1';Recovers=$false}; False=1; True=1; Outcome='DEEP_RECOVERY_FAILED_NO_RETRY' },
    @{ Name='unsafe-zero-write'; Args=@{Initial='UNSAFE'}; False=0; True=0; Outcome='BLOCKED_ZERO_WRITE' },
    @{ Name='boot-marker-blocks-boot'; Args=@{Initial='F1';Mode='boot';BootMarkerExists=$true}; False=0; True=0; Outcome='BOOT_ALREADY_ATTEMPTED_ZERO_WRITE' },
    @{ Name='manual-deep-ignores-marker'; Args=@{Initial='F1';Mode='deep-recover';BootMarkerExists=$true}; False=1; True=1; Outcome='DEEP_SUCCESS' },
    @{ Name='manual-hard-ignores-marker'; Args=@{Initial='F1';Mode='recover-hard';BootMarkerExists=$true}; False=1; True=1; Outcome='DEEP_SUCCESS' },
    @{ Name='manual-auto-ignores-marker'; Args=@{Initial='F1';Mode='auto-run-now';BootMarkerExists=$true}; False=1; True=1; Outcome='DEEP_SUCCESS' }
)

$failed = 0
foreach ($case in $cases) {
    $argsMap = $case.Args
    $actual = Invoke-Model @argsMap
    $pass = $actual.falseCalls -eq $case.False -and $actual.trueCalls -eq $case.True -and $actual.outcome -eq $case.Outcome
    if (-not $pass) { $failed++ }
    '{0}: {1} false={2} true={3} outcome={4}' -f $case.Name, $(if ($pass) {'PASS'} else {'FAIL'}), $actual.falseCalls, $actual.trueCalls, $actual.outcome
}

if ($failed -ne 0) { throw "$failed state-machine tests failed" }
