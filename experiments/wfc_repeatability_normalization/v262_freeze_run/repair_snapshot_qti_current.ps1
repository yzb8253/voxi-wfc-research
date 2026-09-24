[CmdletBinding()]
param([string]$RunName='v262_freeze_run')

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ExperimentRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$RawRoot=Join-Path (Split-Path $Repo -Parent) ("voxi_wfc_local_runs\repeatability_normalization\{0}" -f $RunName)
$SnapshotRoot=Join-Path (Join-Path (Join-Path $ExperimentRoot 'runs') $RunName) 'snapshots'
$pattern='(?m)^\s*uid/pid:[^\r\n]*activeRequest:\s*\d+[^\r\n]*Capabilities:\s*IMS[^\r\n]*mSubId = 11[^\r\n]*RequestorPkg: com\.qualcomm\.qti\.cne'

Get-ChildItem -LiteralPath $SnapshotRoot -Filter '*.json' | ForEach-Object {
  $snapshot=Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
  $networkPath=Join-Path (Join-Path $RawRoot $snapshot.label) 'network.txt'
  if(-not (Test-Path -LiteralPath $networkPath)){throw "Missing raw network capture: $networkPath"}
  $network=Get-Content -LiteralPath $networkPath -Raw
  $index=$network.IndexOf('mNetworkRequestInfoLogs')
  $current=if($index -ge 0){$network.Substring(0,$index)}else{$network}
  $probeReported=[bool]$snapshot.data.qtiCneRequest
  $snapshot.data.qtiCneRequest=[bool]($current -match $pattern)
  $snapshot.data | Add-Member -NotePropertyName qtiCneProbeReported -NotePropertyValue $probeReported -Force
  $json=$snapshot|ConvertTo-Json -Depth 10
  [IO.File]::WriteAllText($_.FullName,$json+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
  Write-Host ("{0}: current={1} probe={2}" -f $_.Name,$snapshot.data.qtiCneRequest,$probeReported)
}
