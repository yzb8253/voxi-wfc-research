[CmdletBinding()]
param(
    [string]$Serial = 'fd0ff892',
    [ValidateRange(1,3)][int]$MaxRecoveryAttempts = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$Engine=Join-Path $PSScriptRoot 'X55-WFC-AGGRESSIVE-CONSERVATIVE-v1.2H-engine.ps1'
$LogDir=Join-Path $PSScriptRoot 'Aggressive-Conservative-Logs'
[IO.Directory]::CreateDirectory($LogDir)|Out-Null
$LogFile=Join-Path $LogDir ('X55-WFC-AGGRESSIVE-CONSERVATIVE-v1.2H-{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$Utf8NoBom=[Text.UTF8Encoding]::new($false)
$StartedAt=Get-Date

function Write-RunLine([string]$Line) {
    Write-Host $Line
    [IO.File]::AppendAllText($LogFile,$Line+[Environment]::NewLine,$Utf8NoBom)
}
function Last-Metric([string[]]$Lines,[string]$Name,[string]$Default) {
    $pattern=('{0}=(.*)$' -f [regex]::Escape($Name))
    $match=@($Lines|Where-Object{$_ -match $pattern})|Select-Object -Last 1
    if($match -match $pattern){return $Matches[1].Trim()}
    $Default
}
function Same-NullableValue([object]$Left,[object]$Right) {
    if($null -eq $Left -and $null -eq $Right){return $true}
    if($null -eq $Left -or $null -eq $Right){return $false}
    [string]$Left -ceq [string]$Right
}

if(-not (Test-Path -LiteralPath $Engine)){throw "Validated v1 engine missing: $Engine"}

# This must remain the first line in the v1.2H aggregate log.
[IO.File]::WriteAllText($LogFile,'MODE=AGGRESSIVE_CONSERVATIVE_V1_2H'+[Environment]::NewLine,$Utf8NoBom)
Write-Host 'MODE=AGGRESSIVE_CONSERVATIVE_V1_2H'
Write-RunLine ("SERIAL={0}" -f $Serial)
Write-RunLine ("MAX_RECOVERY_ATTEMPTS={0}" -f $MaxRecoveryAttempts)
Write-RunLine 'CNE_WRITE_DECISION_SOURCE=CONNECTIVITY_CURRENT_TABLE_ONLY'
Write-RunLine 'HOLDER_IMPL=FAST'

$captured=New-Object 'System.Collections.Generic.List[string]'
$savedEap=$ErrorActionPreference
try {
    $ErrorActionPreference='Continue'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Engine `
        -Serial $Serial `
        -MaxRecoveryAttempts $MaxRecoveryAttempts `
        -A0PreflightMode V12H 2>&1 | ForEach-Object {
            $line=[string]$_
            $captured.Add($line)
            Write-RunLine $line
        }
    $EngineExit=$LASTEXITCODE
}
finally {
    $ErrorActionPreference=$savedEap
}

$lines=@($captured)
$frozenResidueFastCount=Last-Metric $lines 'FROZEN_RESIDUE_FAST_COUNT' '0'
$frozenSplitFastCount=Last-Metric $lines 'FROZEN_SPLIT_FAST_COUNT' '0'
$postNormalizationLightCount=@($lines|Where-Object{$_ -match 'POST_NORMALIZATION_LIGHT=PASS A0_READY'}).Count
$staleProbeCount=0
$lightFiles=@(Get-ChildItem -LiteralPath $LogDir -Filter 'light_*.json' -File -ErrorAction SilentlyContinue |
    Where-Object{$_.LastWriteTime -ge $StartedAt})
foreach($file in $lightFiles) {
    try {
        $state=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json
        $cne=$state.cne
        $hasCurrent=($null -ne $cne.PSObject.Properties['requestId'] -and $null -ne $cne.PSObject.Properties['satisfiedId'])
        $hasProbe=($null -ne $cne.PSObject.Properties['probeReportedRequestId'] -and $null -ne $cne.PSObject.Properties['probeReportedSatisfiedId'])
        if($hasCurrent -and $hasProbe -and
           (-not (Same-NullableValue $cne.requestId $cne.probeReportedRequestId) -or
            -not (Same-NullableValue $cne.satisfiedId $cne.probeReportedSatisfiedId))) {
            $staleProbeCount++
            Write-RunLine ("STALE_PROBE_DIAGNOSTIC file={0} current={1}/{2} probe={3}/{4}" -f
                $file.Name,$cne.requestId,$cne.satisfiedId,$cne.probeReportedRequestId,$cne.probeReportedSatisfiedId)
        }
    }
    catch {
        Write-RunLine ("STALE_PROBE_DIAGNOSTIC_PARSE_FAIL file={0}" -f $file.Name)
    }
}

$total=Last-Metric $lines 'TOTAL_RECOVERY_MS' 'UNKNOWN'
$attempt=Last-Metric $lines 'ATTEMPT_USED' '0'
$wfc=Last-Metric $lines 'WFC_RESULT' 'UNKNOWN'
$lightFast=Last-Metric $lines 'LIGHT_FAST_COUNT' '0'
$fullFallback=Last-Metric $lines 'FULL_FALLBACK_COUNT' '0'

Write-RunLine ("TOTAL_RECOVERY_MS={0}" -f $total)
Write-RunLine ("ATTEMPT_USED={0}" -f $attempt)
Write-RunLine ("WFC_RESULT={0}" -f $wfc)
Write-RunLine ("LIGHT_FAST_COUNT={0}" -f $lightFast)
Write-RunLine ("FULL_FALLBACK_COUNT={0}" -f $fullFallback)
Write-RunLine ("FROZEN_SPLIT_FAST_COUNT={0}" -f $frozenSplitFastCount)
Write-RunLine ("FROZEN_RESIDUE_FAST_COUNT={0}" -f $frozenResidueFastCount)
Write-RunLine ("POST_NORMALIZATION_LIGHT_COUNT={0}" -f $postNormalizationLightCount)
Write-RunLine ("CNE_STALE_PROBE_COUNT={0}" -f $staleProbeCount)
foreach($metric in @('ENTRY_HOLDER_IMPL','A_LIGHT_MS','PER_MGR_START_COUNT','PER_MGR_START_TO_SPLIT_MS','SPLIT_GATE_RESULT','QCRILD2_REACQUIRE_MS','HOLDER_TERM_TO_OWNER_NONE_MS','HOLDER_TERM_TO_MAIN_GONE_MS','POST_NORMALIZATION_LIGHT_MS','FIRST_FULL_MS','SECOND_FULL_MS','A0_TOTAL_MS','P_TOTAL_MS','CORE_TOTAL_MS')) {
    Write-RunLine ("{0}={1}" -f $metric,(Last-Metric $lines $metric '0'))
}
Write-RunLine ("ENGINE_EXIT={0}" -f $EngineExit)
Write-RunLine ("LOG={0}" -f $LogFile)
exit $EngineExit
