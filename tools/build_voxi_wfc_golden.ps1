[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Module = Join-Path $Repo 'modules\voxi_wfc_golden'
$Release = Join-Path $Repo 'release\golden-magisk'
$Stage = Join-Path $Release '.stage-v1.1.0-rc5'
$Zip = Join-Path $Release 'VOXI-WFC-Golden-Recovery-v1.1.0-rc5.zip'
$ExpectedProbe = 'AC46E9F62DB88C043DA08E4D5BB1D100EA8AC10EF2A74838F99C2237C2B9A91D'

$required = @(
  'module.prop','customize.sh','action.sh','service.sh','uninstall.sh','README.md',
  'bin\common.sh','bin\goldenctl.sh','bin\golden-selftest.sh','bin\golden-runner.sh','bin\golden-preflight.sh','bin\x55-holder.sh',
  'lib\wfc-probe.jar'
)
foreach($item in $required) {
  if(-not (Test-Path -LiteralPath (Join-Path $Module $item))) { throw "Missing module file: $item" }
}

$probeHash = (Get-FileHash -LiteralPath (Join-Path $Module 'lib\wfc-probe.jar') -Algorithm SHA256).Hash
if($probeHash -ne $ExpectedProbe) { throw "wfc-probe.jar hash mismatch: $probeHash" }

New-Item -ItemType Directory -Force -Path $Release | Out-Null
$releaseFull = [IO.Path]::GetFullPath($Release).TrimEnd('\') + '\'
$stageFull = [IO.Path]::GetFullPath($Stage)
if(-not $stageFull.StartsWith($releaseFull,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe stage path' }
if(Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
New-Item -ItemType Directory -Path $Stage | Out-Null

Copy-Item -Path (Join-Path $Module '*') -Destination $Stage -Recurse -Force
if(Test-Path -LiteralPath $Zip) { Remove-Item -LiteralPath $Zip -Force }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$stream = [IO.File]::Open($Zip,[IO.FileMode]::CreateNew)
$writer = [IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
try {
  foreach($file in Get-ChildItem -LiteralPath $Stage -Recurse -File) {
    $relative = $file.FullName.Substring($stageFull.Length).TrimStart('\').Replace('\','/')
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
      $writer,$file.FullName,$relative,[IO.Compression.CompressionLevel]::Optimal
    )
  }
}
finally {
  $writer.Dispose()
  $stream.Dispose()
}
Remove-Item -LiteralPath $Stage -Recurse -Force

$archive = [IO.Compression.ZipFile]::OpenRead($Zip)
try {
  $entries = @($archive.Entries | ForEach-Object FullName)
  foreach($item in $required) {
    $normalized = $item.Replace('\','/')
    if($entries -notcontains $normalized) { throw "ZIP missing root entry: $normalized" }
  }
}
finally { $archive.Dispose() }

$zipHash = (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash
Write-Host "ZIP=$Zip"
Write-Host "SHA256=$zipHash"
Write-Host 'BUILD=PASS'
