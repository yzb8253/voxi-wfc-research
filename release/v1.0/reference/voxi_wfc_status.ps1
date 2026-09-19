$ErrorActionPreference = "Stop"
$tool = Join-Path $PSScriptRoot "autopilot\voxi_wfc_status.ps1"
& powershell -NoProfile -ExecutionPolicy Bypass -File $tool
exit $LASTEXITCODE
