Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Classifier=Join-Path $PSScriptRoot 'classify_lightweight_state_v12h_r1.ps1'
. (Join-Path $PSScriptRoot 'holder_identity_v12h_r1.ps1')
$BasePath=Join-Path $PSScriptRoot 'fixtures\03_frozen_holder_residue.json'
$TempRoot=Join-Path $env:TEMP ('v12h-r1-holder-fixtures-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($TempRoot)|Out-Null
$FastCommand='trap "exit 0" TERM INT HUP; echo $$ >/data/local/tmp/x55_holder.pid; exec 9</dev/subsys_esoc0 || exit 91; echo ===X55_HOLDER_OPEN===; while :; do sleep 3600 9<&- & child=$!; wait "$child"; done'
$OldCommand='echo $$ >/data/local/tmp/x55_holder.pid; exec 9</dev/subsys_esoc0 || exit 91; echo ===X55_HOLDER_OPEN===; while true; do sleep 60; done'

function Clone-Base {
  $s=(Get-Content -LiteralPath $BasePath -Raw|ConvertFrom-Json|ConvertTo-Json -Depth 20|ConvertFrom-Json)
  $s.schema='voxi-wfc-lightweight-state-v1.2H-r1'
  $s.holder|Add-Member -NotePropertyName ppid -NotePropertyValue 870 -Force
  $s.holder|Add-Member -NotePropertyName name -NotePropertyValue 'sh' -Force
  $s.holder|Add-Member -NotePropertyName psArgs -NotePropertyValue 'sh -c trap exit 0 TERM ... formatting intentionally differs' -Force
  $s.holder|Add-Member -NotePropertyName procArgv -NotePropertyValue @('sh','-c',$FastCommand) -Force
  $s
}
function Classify-Case([string]$Name,[object]$State){$path=Join-Path $TempRoot ($Name+'.json');[IO.File]::WriteAllText($path,($State|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false));((& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Classifier -InputPath $path -OutputFormat Json)|ConvertFrom-Json)}
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}

try {
  $results=@()
  $s=Clone-Base;$r=Classify-Case '01_fast_ps_diff_proc_same' $s;Require ($r.classification -eq 'FROZEN_RESIDUE' -and $r.holderImplementation -eq 'FAST') 'FAST same-proc identity rejected';$results+=$true

  Require (-not (Test-ExactProcArgvMatch @('sh','-c',$FastCommand) @('sh','-c',$OldCommand))) 'changed live procArgv accepted';$s=Clone-Base;$s.holder.procArgv=@('sh','-c','echo $$ >/data/local/tmp/x55_holder.pid; exec 9</dev/subsys_esoc0; altered');$r=Classify-Case '02_proc_argv_changed' $s;Require ($r.classification -eq 'UNKNOWN') 'changed procArgv classified safe';$results+=$true

  $s=Clone-Base;$s.holder.pidFileValue=9999;$r=Classify-Case '03_pidfile_mismatch' $s;Require ($r.classification -eq 'UNKNOWN') 'pidfile mismatch classified safe';$results+=$true
  $s=Clone-Base;$s.holder.fd9Target='/dev/null';$r=Classify-Case '04_fd9_wrong' $s;Require ($r.classification -eq 'UNKNOWN') 'wrong FD9 classified safe';$results+=$true
  $s=Clone-Base;$s.native.owners+=([pscustomobject]@{pid=7777;name='unknown';path='/dev/subsys_esoc0'});$s.native.ownerCount=2;$r=Classify-Case '05_nonsole_owner' $s;Require ($r.classification -eq 'UNKNOWN') 'nonsole owner classified safe';$results+=$true
  $s=Clone-Base;$s.holder.procArgv=@('sh','-c','echo $$ >/data/local/tmp/x55_holder.pid; exec 9</dev/subsys_esoc0; sleep 3600');$r=Classify-Case '06_fast_marker_missing' $s;Require ($r.classification -eq 'UNKNOWN') 'missing FAST markers classified safe';$results+=$true
  $s=Clone-Base;$s.holder.procArgv=@('sh','-c',$OldCommand);$s.holder.psArgs='sh -c echo holder old ps rendering';$r=Classify-Case '07_old_legal' $s;Require ($r.classification -eq 'FROZEN_RESIDUE' -and $r.holderImplementation -eq 'OLD') 'legal OLD holder behavior changed';$results+=$true

  Write-Host ("HOLDER_IDENTITY_FIXTURES={0}/7 PASS" -f @($results).Count)
  Write-Host 'UNSAFE_PROMOTION_COUNT=0'
  Write-Host 'PS_ARGS_AUTHORITY=NO'
  Write-Host 'PROC_ARGV_AUTHORITY=YES'
}
finally {Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue}
