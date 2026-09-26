[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('OLD','FAST')][string]$ABVariant,
    [string]$Serial='fd0ff892'
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Engine=Join-Path $PSScriptRoot 'X55-WFC-AGGRESSIVE-CONSERVATIVE-v1.2H-r2-engine.ps1'
$LogDir=Join-Path $PSScriptRoot 'Holder-AB-Logs'
[IO.Directory]::CreateDirectory($LogDir)|Out-Null
$LogFile=Join-Path $LogDir ('X55-WFC-AB-{0}-{1}.log' -f $ABVariant,(Get-Date -Format 'yyyyMMdd_HHmmss'))
$Utf8NoBom=[Text.UTF8Encoding]::new($false)

function Write-AbLine([string]$Line) {
    Write-Host $Line
    [IO.File]::AppendAllText($LogFile,$Line+[Environment]::NewLine,$Utf8NoBom)
}

if(-not (Test-Path -LiteralPath $Engine)){throw "Shared r2 engine missing: $Engine"}
[IO.File]::WriteAllText($LogFile,("MODE=HOLDER_AB_R2`nAB_VARIANT={0}`nMAX_RECOVERY_ATTEMPTS=1`n" -f $ABVariant),$Utf8NoBom)
Write-Host 'MODE=HOLDER_AB_R2'
Write-Host ("AB_VARIANT={0}" -f $ABVariant)
Write-Host 'MAX_RECOVERY_ATTEMPTS=1'

$savedEap=$ErrorActionPreference
try {
    $ErrorActionPreference='Continue'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Engine `
        -Serial $Serial `
        -MaxRecoveryAttempts 1 `
        -A0PreflightMode V12H `
        -ABVariant $ABVariant 2>&1 | ForEach-Object {Write-AbLine ([string]$_)}
    $engineExit=$LASTEXITCODE
}
finally {$ErrorActionPreference=$savedEap}

Write-AbLine ("ENGINE_EXIT={0}" -f $engineExit)
Write-AbLine ("AB_LOG={0}" -f $LogFile)
exit $engineExit
