param(
    [string]$Javac = $env:JAVAC,
    [string]$D8 = $env:D8
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Source = Join-Path $Root "src\Slot1SimPowerHelper.java"
$Build = Join-Path $Root "build"
$Classes = Join-Path $Build "classes"
$Intermediate = Join-Path $Build "slot1-sim-power-helper-classes.jar"
$DexDir = Join-Path $Build "dex"
$Output = Join-Path $Build "slot1-sim-power-helper.jar"

if ([string]::IsNullOrWhiteSpace($Javac) -or -not (Test-Path -LiteralPath $Javac)) {
    throw "Set JAVAC to an audited JDK javac executable."
}
if ([string]::IsNullOrWhiteSpace($D8) -or -not (Test-Path -LiteralPath $D8)) {
    throw "Set D8 to an audited Android build-tools d8 executable."
}
$Jar = Join-Path (Split-Path -Parent $Javac) "jar.exe"
if (-not (Test-Path -LiteralPath $Jar)) {
    $Jar = Join-Path (Split-Path -Parent $Javac) "jar"
}
if (-not (Test-Path -LiteralPath $Jar)) {
    throw "jar executable was not found beside JAVAC."
}

New-Item -ItemType Directory -Force -Path $Classes,$DexDir | Out-Null
Get-ChildItem -LiteralPath $Classes -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
Get-ChildItem -LiteralPath $DexDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
Remove-Item -LiteralPath $Intermediate,$Output -Force -ErrorAction SilentlyContinue

& $Javac --release 8 -d $Classes $Source
if ($LASTEXITCODE -ne 0) { throw "javac failed: $LASTEXITCODE" }

Push-Location $Classes
try {
    & $Jar cf $Intermediate .
    if ($LASTEXITCODE -ne 0) { throw "jar failed: $LASTEXITCODE" }
} finally {
    Pop-Location
}

& $D8 --min-api 26 --output $DexDir $Intermediate
if ($LASTEXITCODE -ne 0) { throw "d8 failed: $LASTEXITCODE" }

Compress-Archive -LiteralPath (Join-Path $DexDir "classes.dex") -DestinationPath $Output
$Hash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "Built: $Output"
Write-Host "SHA256: $Hash"
