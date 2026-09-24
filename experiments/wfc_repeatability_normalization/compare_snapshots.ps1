[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Left,
  [Parameter(Mandatory=$true)][string]$Right,
  [Parameter(Mandatory=$true)][string]$Output
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Flatten($Value,[string]$Prefix='') {
  $result=[ordered]@{}
  if($null -eq $Value){$result[$Prefix]=$null;return $result}
  if($Value -is [Collections.IEnumerable] -and $Value -isnot [string] -and $Value -isnot [pscustomobject]) {
    $result[$Prefix]=(@($Value)|ConvertTo-Json -Compress -Depth 10);return $result
  }
  if($Value -is [pscustomobject]) {
    foreach($property in $Value.PSObject.Properties) {
      $next=if($Prefix){$Prefix+'.'+$property.Name}else{$property.Name}
      $child=Flatten $property.Value $next
      foreach($key in $child.Keys){$result[$key]=$child[$key]}
    }
    return $result
  }
  $result[$Prefix]=$Value
  $result
}
$leftObject=Get-Content -Raw -LiteralPath $Left|ConvertFrom-Json
$rightObject=Get-Content -Raw -LiteralPath $Right|ConvertFrom-Json
$a=Flatten $leftObject; $b=Flatten $rightObject
$ignore=@('label','timestamp','gitHead')
$lines=[Collections.Generic.List[string]]::new()
foreach($key in @($a.Keys+$b.Keys|Sort-Object -Unique)) {
  if($ignore -contains $key){continue}
  $av=if($a.Contains($key)){$a[$key]}else{'[MISSING]'}
  $bv=if($b.Contains($key)){$b[$key]}else{'[MISSING]'}
  $displayA=if($null -eq $av){'[NULL]'}else{[string]$av}
  $displayB=if($null -eq $bv){'[NULL]'}else{[string]$bv}
  if($displayA -cne $displayB){$lines.Add("$key`n  LEFT: $displayA`n  RIGHT: $displayB")}
}
$outputParent=Split-Path -Parent $Output
if($outputParent -and -not (Test-Path -LiteralPath $outputParent)) {
  New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
}
[IO.File]::WriteAllLines($Output,@("LEFT=$Left","RIGHT=$Right","DIFF_COUNT=$($lines.Count)",'')+$lines,[Text.UTF8Encoding]::new($false))
Write-Host "DIFF_COUNT=$($lines.Count)"
Write-Host "OUTPUT=$Output"
