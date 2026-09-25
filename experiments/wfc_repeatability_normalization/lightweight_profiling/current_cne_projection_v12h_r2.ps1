Set-StrictMode -Version Latest

function Get-CurrentCneProjection {
  param([Parameter(Mandatory=$true)][string]$ConnectivityText,[int]$SubId=11)
  $historyIndex=$ConnectivityText.IndexOf('mNetworkRequestInfoLogs')
  if($historyIndex -lt 0){return [pscustomobject]@{valid=$false;requestId=$null;satisfiedId=$null;source='CONNECTIVITY_CURRENT_TABLE';reason='MISSING_HISTORY_BOUNDARY'}}
  $current=$ConnectivityText.Substring(0,$historyIndex)
  $line=@($current -split "\r?\n"|Where-Object{
    $_ -match 'activeRequest:' -and $_ -match 'com\.qualcomm\.qti\.cne' -and
    $_ -match 'Capabilities:\s*IMS' -and $_ -match ("mSubId\s*=\s*{0}" -f $SubId)
  })|Select-Object -First 1
  $request=$null;$satisfied=$null
  if($line -match 'NetworkRequest \[ REQUEST id=(\d+)'){$request=[int]$Matches[1]}
  if($line -match 'activeRequest:\s*(\d+)'){$satisfied=[int]$Matches[1]}
  [pscustomobject]@{valid=$true;requestId=$request;satisfiedId=$satisfied;source='CONNECTIVITY_CURRENT_TABLE';reason='PASS'}
}

function Test-CurrentCneClear {
  param([Parameter(Mandatory=$true)][object]$Projection)
  [bool]$Projection.valid -and $null -eq $Projection.requestId -and $null -eq $Projection.satisfiedId
}

function Test-NullableCneEqual {
  param([object]$Left,[object]$Right)
  if($null -eq $Left -and $null -eq $Right){return $true}
  if($null -eq $Left -or $null -eq $Right){return $false}
  [string]$Left -ceq [string]$Right
}
