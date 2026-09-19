param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\release\auto-recovery")
)

$ErrorActionPreference = "Stop"
$module = (Resolve-Path (Join-Path $PSScriptRoot "..\modules\voxi_wfc_auto_recover")).Path
$output = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $output -Force | Out-Null
$zip = Join-Path $output "voxi_wfc_auto_recover-v0.1.0.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip }

Compress-Archive -Path (Join-Path $module "*") -DestinationPath $zip -CompressionLevel Optimal
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLowerInvariant()
Set-Content -LiteralPath (Join-Path $output "SHA256SUMS.txt") -Value "$hash  voxi_wfc_auto_recover-v0.1.0.zip" -Encoding ascii
Write-Host "$zip"
Write-Host "SHA256 $hash"

