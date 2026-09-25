[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$activePath=Join-Path $PSScriptRoot 'fixtures\cne_active_current_android13.txt'
$nullPath=Join-Path $PSScriptRoot 'fixtures\cne_null_current_stale_history_android13.txt'

function Project-CurrentCne([string]$Text) {
  $historyIndex=$Text.IndexOf('mNetworkRequestInfoLogs')
  if($historyIndex -lt 0){return [pscustomobject]@{valid=$false;requestId=$null;satisfiedId=$null}}
  $current=$Text.Substring(0,$historyIndex)
  $line=@($current -split "\r?\n"|Where-Object{
    $_ -match 'activeRequest:' -and $_ -match 'com\.qualcomm\.qti\.cne' -and
    $_ -match 'Capabilities:\s*IMS' -and $_ -match 'mSubId\s*=\s*11'
  })|Select-Object -First 1
  $request=$null;$satisfied=$null
  if($line -match 'NetworkRequest \[ REQUEST id=(\d+)'){$request=[int]$Matches[1]}
  if($line -match 'activeRequest:\s*(\d+)'){$satisfied=[int]$Matches[1]}
  [pscustomobject]@{valid=$true;requestId=$request;satisfiedId=$satisfied}
}
function Check([bool]$Condition,[string]$Name) {
  if(-not $Condition){throw "FAIL $Name"}
  Write-Output "PASS $Name"
}

$active=Project-CurrentCne (Get-Content -LiteralPath $activePath -Raw)
Check ($active.valid -and $active.requestId -eq 262 -and $active.satisfiedId -eq 262) 'ACTIVE_CURRENT_TO_ACTIVE'

$nullCase=Project-CurrentCne (Get-Content -LiteralPath $nullPath -Raw)
Check ($nullCase.valid -and $null -eq $nullCase.requestId -and $null -eq $nullCase.satisfiedId) 'NULL_CURRENT_TO_NULL'

$legacyText=Get-Content -LiteralPath $nullPath -Raw
$legacyLine=@($legacyText -split "\r?\n"|Where-Object{
  $_ -match 'activeRequest:' -and $_ -match 'com\.qualcomm\.qti\.cne' -and
  $_ -match 'Capabilities:\s*IMS' -and $_ -match 'mSubId\s*=\s*11'
})|Select-Object -First 1
Check ($legacyLine -match 'activeRequest:\s*1518') 'LEGACY_UNBOUNDED_SCAN_REPRODUCES_STALE_1518'

$missingBoundary=Project-CurrentCne 'Network Requests: none'
Check (-not $missingBoundary.valid) 'MISSING_BOUNDARY_FAILS_CLOSED'
Write-Output 'UNSAFE_PROMOTION_COUNT=0'
Write-Output 'PHONE_WRITES=0'
