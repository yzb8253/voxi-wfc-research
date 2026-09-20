param([string]$Javac,[string]$D8)
$ErrorActionPreference='Stop'
$Root=$PSScriptRoot
$Source=Join-Path $Root 'src\SingleSimSlot1PowerHelper.java'
$Build=Join-Path $Root 'build'
$Classes=Join-Path $Build 'classes'
$Intermediate=Join-Path $Build 'single-sim-slot1-classes.jar'
$DexDir=Join-Path $Build 'dex'
$Output=Join-Path $Build 'single-sim-slot1-power-helper.jar'
$Jar=Join-Path (Split-Path -Parent $Javac) 'jar.exe'
foreach($p in @($Javac,$D8,$Jar)){if(-not(Test-Path $p)){throw "Missing tool: $p"}}
New-Item -ItemType Directory -Force $Classes,$DexDir|Out-Null
Get-ChildItem $Classes -Force -ErrorAction SilentlyContinue|Remove-Item -Recurse -Force
Get-ChildItem $DexDir -Force -ErrorAction SilentlyContinue|Remove-Item -Recurse -Force
Remove-Item $Intermediate,$Output -Force -ErrorAction SilentlyContinue
& $Javac --release 8 -d $Classes $Source
if($LASTEXITCODE-ne0){throw 'javac failed'}
Push-Location $Classes; try{& $Jar cf $Intermediate .;if($LASTEXITCODE-ne0){throw 'jar failed'}}finally{Pop-Location}
& $D8 --min-api 26 --output $DexDir $Intermediate
if($LASTEXITCODE-ne0){throw 'd8 failed'}
Push-Location $DexDir;try{& $Jar cf $Output classes.dex;if($LASTEXITCODE-ne0){throw 'final jar failed'}}finally{Pop-Location}
Get-FileHash $Output -Algorithm SHA256