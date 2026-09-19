$ErrorActionPreference = "Stop"
$tool = Join-Path $PSScriptRoot "autopilot\voxi_wfc_recover.ps1"
& powershell -NoProfile -ExecutionPolicy Bypass -File $tool
exit $LASTEXITCODE
