[CmdletBinding()]
param([string]$Serial='fd0ff892')

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$engine=Join-Path $PSScriptRoot 'X55-WFC-STABLE-CNE-V1-engine.ps1'
if(-not (Test-Path -LiteralPath $engine)){throw "STABLE_CNE_V1 engine missing: $engine"}

Write-Host 'MODE=STABLE_CNE_V1'
Write-Host '[1/7] Preparing clean state' -ForegroundColor Cyan
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $engine -Serial $Serial -MaxRecoveryAttempts 1 -A0PreflightMode V12H
exit $LASTEXITCODE
