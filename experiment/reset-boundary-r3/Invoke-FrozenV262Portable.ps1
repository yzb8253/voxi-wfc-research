[CmdletBinding()]
param([switch]$StaticAudit)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Canonical=Join-Path $Repo 'experiments\wfc_repeatability_normalization\v262_freeze_run\X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1'
$CurrentAdb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$Expected='445752BB49FB487850D0B1A1EFF4F0AA29D58C363C3A86E75BAA841E4CC08F75'
$OldLine='$Adb = ''C:\Users\ZJH\Desktop\platform-tools\adb.exe'''
$NewLine='$Adb = '''+$CurrentAdb+''''

$actual=(Get-FileHash -LiteralPath $Canonical -Algorithm SHA256).Hash
if($actual -ne $Expected){throw "CANONICAL_V262_HASH_MISMATCH=$actual"}
$source=[IO.File]::ReadAllText($Canonical,[Text.UTF8Encoding]::new($false))
$count=([regex]::Matches($source,[regex]::Escape($OldLine))).Count
if($count -ne 1){throw "ADB_PATH_BINDING_COUNT=$count"}
$adapted=$source.Replace($OldLine,$NewLine)
if($adapted.Replace($NewLine,$OldLine) -cne $source){throw 'PORTABLE_ADAPTER_DIFF_NOT_EXACTLY_ONE_LINE'}
if(-not (Test-Path -LiteralPath $CurrentAdb)){throw "CURRENT_ADB_MISSING=$CurrentAdb"}

Write-Host "CANONICAL_V262_SHA256=$actual"
Write-Host 'PORTABLE_CHANGE=ONE_HOST_ADB_PATH_LINE_ONLY'
Write-Host "CURRENT_ADB=$CurrentAdb"
if($StaticAudit){Write-Host 'STATIC_NO_ADB=PASS';exit 0}

$hostRoot=Join-Path (Split-Path $Repo -Parent) 'voxi_wfc_local_runs\reset_boundary_r3\r3_3cycle\portable_v262'
[IO.Directory]::CreateDirectory($hostRoot)|Out-Null
$temp=Join-Path $hostRoot 'X55-WFC-OneClick-v2.6.2-freeze-on-success.portable.ps1'
[IO.File]::WriteAllText($temp,$adapted,[Text.UTF8Encoding]::new($false))
$derived=(Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash
Write-Host "PORTABLE_DERIVED_SHA256=$derived"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $temp
exit $LASTEXITCODE
