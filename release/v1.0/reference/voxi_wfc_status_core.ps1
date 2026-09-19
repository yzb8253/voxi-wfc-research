$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "run_wfc_state_probe.ps1"
& powershell -NoProfile -ExecutionPolicy Bypass -File $probe
