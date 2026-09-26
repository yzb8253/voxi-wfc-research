[CmdletBinding()]
param(
    [string]$RepoRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Get-Text([string]$Path) {
    if(-not (Test-Path -LiteralPath $Path)) { throw "Missing offline evidence: $Path" }
    Get-Content -LiteralPath $Path -Raw
}

function Match-One([string]$Text, [string]$Pattern, [string]$Label) {
    $matches = [regex]::Matches($Text, $Pattern)
    if($matches.Count -ne 1) { throw "$Label expected exactly once; found $($matches.Count)" }
    $matches[0]
}

$runs = @(
    [pscustomobject]@{ Name='UICC_CYCLE_1'; Dir='autopilot\experiments\cycle1_uicc_true'; Write='true_write.txt'; RequestId=360 },
    [pscustomobject]@{ Name='UICC_CYCLE_2'; Dir='autopilot\experiments\cycle2_validation'; Write='writes.txt'; RequestId=374 },
    [pscustomobject]@{ Name='UICC_CYCLE_3'; Dir='autopilot\experiments\cycle3_validation'; Write='writes.txt'; RequestId=380 }
)

$result = foreach($run in $runs) {
    $dir = Join-Path $RepoRoot $run.Dir
    $writeText = Get-Text (Join-Path $dir $run.Write)
    $observation = Get-Text (Join-Path $dir 'observation.txt')

    $write = Match-One $writeText 'writeStartEpochMs=(\d+)' "$($run.Name) true write"
    $requestPattern = "(?m)^(\d\d-\d\d) (\d\d:\d\d:\d\d\.\d{{3}}).*(?:ConnectivityService: requestNetwork|TelephonyNetworkFactory\[1\]: got request).*REQUEST id={0}, .*RequestorPkg: com\.qualcomm\.qti\.cne" -f $run.RequestId
    $requestMatches = [regex]::Matches($observation,$requestPattern)
    if($requestMatches.Count -lt 1) { throw "$($run.Name) fresh request not found" }
    $request = $requestMatches[0]

    $epochMs = [int64]$write.Groups[1].Value
    $writeTime = [DateTimeOffset]::FromUnixTimeMilliseconds($epochMs).ToOffset([TimeSpan]::FromHours(8))
    $requestTime = [DateTimeOffset]::ParseExact(
        ("{0}-{1}T{2}+08:00" -f $writeTime.Year,$request.Groups[1].Value,$request.Groups[2].Value),
        'yyyy-MM-ddTHH:mm:ss.fffzzz',
        [Globalization.CultureInfo]::InvariantCulture
    )

    $golden = Get-ChildItem -LiteralPath $dir -Filter '*.json' -File |
        Where-Object { $_.Name -match '^(t_|recover_)' } |
        ForEach-Object {
            try { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json }
            catch { $null }
        } |
        Where-Object { $null -ne $_ -and $_.goldenStrong } |
        Sort-Object { [DateTimeOffset]$_.timestamp } |
        Select-Object -First 1

    if($null -eq $golden) { throw "$($run.Name) has no GOLDEN_STRONG sample" }
    $goldenTime = [DateTimeOffset]$golden.timestamp

    [pscustomobject]@{
        Run = $run.Name
        TrueWrite = $writeTime.ToString('o')
        FreshRequestId = $run.RequestId
        FreshRequest = $requestTime.ToString('o')
        TrueToFreshRequestMs = [math]::Round(($requestTime - $writeTime).TotalMilliseconds)
        FirstGoldenStrong = $goldenTime.ToString('o')
        TrueToGoldenStrongMs = [math]::Round(($goldenTime - $writeTime).TotalMilliseconds)
        Evidence = ($run.Dir -replace '\\','/') + '/observation.txt'
    }
}

$result
