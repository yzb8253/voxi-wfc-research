[CmdletBinding()]
param(
    [string]$Javac='C:\Users\TT\Desktop\platform-tools\Microsoft Build of OpenJDK with Hotspot 21_21.0.12.101_Machine_X64_wix_en-US\SourceDir\PFiles64\Microsoft\jdk-21.0.12.101-hotspot\bin\javac.exe',
    [string]$D8Jar='C:\Users\TT\Desktop\platform-tools\.single-sim-toolchain\build-tools-37\android-37.0\lib\d8.jar'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot 'typed_helper\GoldenSimpleTypedUiccHelper.java'
$build=Join-Path $PSScriptRoot 'typed_helper\build'
$classes=Join-Path $build 'classes';$dex=Join-Path $build 'dex'
$intermediate=Join-Path $build 'golden-simple-typed-uicc-classes.jar'
$output=Join-Path $PSScriptRoot 'golden-simple-typed-uicc-helper.jar'
$jar=Join-Path (Split-Path $Javac -Parent) 'jar.exe'
$java=Join-Path (Split-Path $Javac -Parent) 'java.exe'
foreach($p in @($source,$Javac,$D8Jar,$jar,$java)){if(-not(Test-Path -LiteralPath $p)){throw "Missing build input: $p"}}
New-Item -ItemType Directory -Force -Path $classes,$dex|Out-Null
Get-ChildItem $classes -Force -ErrorAction SilentlyContinue|Remove-Item -Recurse -Force
Get-ChildItem $dex -Force -ErrorAction SilentlyContinue|Remove-Item -Recurse -Force
Remove-Item $intermediate,$output -Force -ErrorAction SilentlyContinue
& $Javac --release 8 -d $classes $source;if($LASTEXITCODE-ne0){throw 'javac failed'}
Push-Location $classes;try{& $jar cf $intermediate .;if($LASTEXITCODE-ne0){throw 'class jar failed'}}finally{Pop-Location}
& $java -cp $D8Jar com.android.tools.r8.D8 --min-api 26 --output $dex $intermediate;if($LASTEXITCODE-ne0){throw 'd8 failed'}
Push-Location $dex;try{& $jar cf $output classes.dex;if($LASTEXITCODE-ne0){throw 'dex jar failed'}}finally{Pop-Location}
$item=Get-Item $output;$hash=(Get-FileHash $output -Algorithm SHA256).Hash
Write-Host "TYPED_HELPER_JAR=$($item.FullName)";Write-Host "TYPED_HELPER_SIZE=$($item.Length)";Write-Host "TYPED_HELPER_SHA256=$hash";Write-Host 'PHONE_WRITES=0'
