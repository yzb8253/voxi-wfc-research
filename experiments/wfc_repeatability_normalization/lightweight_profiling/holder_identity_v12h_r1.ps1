Set-StrictMode -Version Latest

function Test-HolderProcArgvSemantic {
  param([object[]]$ProcArgv)
  $argv=@($ProcArgv|ForEach-Object{[string]$_})
  $result=[ordered]@{valid=$false;implementation='UNKNOWN';reason=''}
  if($argv.Count -ne 3){$result.reason='argv_count';return [pscustomobject]$result}
  if($argv[0] -notmatch '(^|/)sh$' -or $argv[1] -cne '-c'){$result.reason='argv_shell_shape';return [pscustomobject]$result}
  $command=$argv[2]
  if($command -notmatch '(^|[ ;])echo \$\$ >/data/local/tmp/x55_holder\.pid([ ;]|$)' -or $command -notmatch 'exec 9</dev/subsys_esoc0'){$result.reason='fixed_holder_markers';return [pscustomobject]$result}
  $isFast=($command -match 'trap .*TERM INT HUP' -and $command -match 'sleep 3600 9<&- &' -and $command -match 'child=\$!' -and $command -match 'wait .*\$child')
  $isOld=($command -match 'while true; do sleep 60; done')
  if($isFast -eq $isOld){$result.reason='implementation_markers';return [pscustomobject]$result}
  $result.valid=$true;$result.implementation=if($isFast){'FAST'}else{'OLD'};$result.reason='PASS'
  [pscustomobject]$result
}

function Test-ExactProcArgvMatch {
  param([object[]]$Observed,[object[]]$Live)
  $a=@($Observed|ForEach-Object{[string]$_});$b=@($Live|ForEach-Object{[string]$_})
  if($a.Count -ne $b.Count){return $false}
  for($i=0;$i -lt $a.Count;$i++){if($a[$i] -cne $b[$i]){return $false}}
  $true
}
