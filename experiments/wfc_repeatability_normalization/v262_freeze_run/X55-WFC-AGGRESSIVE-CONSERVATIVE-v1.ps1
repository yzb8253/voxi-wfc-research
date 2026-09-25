[CmdletBinding()]
param(
    [string]$Serial = 'fd0ff892',
    [ValidateRange(1,3)][int]$MaxRecoveryAttempts = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$engine = Join-Path $PSScriptRoot 'X55-WFC-AGGRESSIVE-CONSERVATIVE-v0.ps1'
if(-not (Test-Path -LiteralPath $engine)) {
    throw "AGGRESSIVE_CONSERVATIVE v0 engine missing: $engine"
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $engine `
    -Serial $Serial `
    -MaxRecoveryAttempts $MaxRecoveryAttempts `
    -A0PreflightMode V1
exit $LASTEXITCODE
