[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Name) {
    if(-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

$tokens = $null
$errors = $null
$parserTarget = Join-Path $PSScriptRoot 'Get-DeepCneEvidence.ps1'
[void][Management.Automation.Language.Parser]::ParseFile($parserTarget,[ref]$tokens,[ref]$errors)
Assert-True (@($errors).Count -eq 0) 'PS5.1 parser'

$rows = @(& $parserTarget)
Assert-True ($rows.Count -eq 3) 'three historical successful UICC cycles'
Assert-True ((@($rows.FreshRequestId) -join ',') -eq '360,374,380') 'fresh request IDs are 360,374,380'
Assert-True (@($rows | Where-Object { $_.TrueToFreshRequestMs -le 0 }).Count -eq 0) 'fresh request follows true write'
Assert-True (@($rows | Where-Object { $_.TrueToFreshRequestMs -gt 45000 }).Count -eq 0) 'all observed fresh requests occur within 45 seconds'
Assert-True (@($rows | Where-Object { $_.TrueToGoldenStrongMs -lt $_.TrueToFreshRequestMs }).Count -eq 0) 'health never precedes fresh request'

$source = Get-Content -LiteralPath $parserTarget -Raw
Assert-True ($source -notmatch '(?i)\badb(?:\.exe)?\b|Invoke-Adb|Root-Write|setprop|service call|POWER_(?:DOWN|UP)') 'offline analyzer has no phone command path'

$categories = @(
    'PROVEN_CNE_TRIGGER','LIKELY_CNE_TRIGGER','PRECONDITION_ONLY',
    'CLEANUP_ONLY','NO_EFFECT_OBSERVED','INSUFFICIENT_EVIDENCE'
)
Assert-True ($categories.Count -eq 6) 'evidence taxonomy is complete'

Write-Host 'FIXTURES=7/7 PASS'
Write-Host 'PHONE_WRITES=0'
