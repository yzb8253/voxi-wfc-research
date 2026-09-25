[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Classifier=Join-Path $PSScriptRoot 'classify_lightweight_state.ps1'
$Fixture=Join-Path $PSScriptRoot 'fixtures\12_x55_vendor_kernel_split.json'
$Aggressive=Join-Path $Repo 'experiments\wfc_repeatability_normalization\v262_freeze_run\X55-WFC-AGGRESSIVE-CONSERVATIVE-v0.ps1'
$Shadow=Join-Path $PSScriptRoot 'invoke_shadow_comparison.ps1'
$Runner=Join-Path $PSScriptRoot 'run_phase18_shadow_validation.ps1'

foreach($file in @($Classifier,$Aggressive,$Shadow,$Runner)) {
  $tokens=$null;$errors=$null
  [void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
  if(@($errors).Count -ne 0){throw "PS51_PARSE_FAIL $file"}
}
Write-Output 'PS51_PARSER=PASS'

$classification=((& $Classifier -InputPath $Fixture -OutputFormat Json)|ConvertFrom-Json)
if($classification.classification -ne 'UNKNOWN'){throw 'Semantic residue fixture did not classify UNKNOWN'}
if(@($classification.errors|Where-Object{$_ -eq 'native:x55_unknown_combination'}).Count -ne 1){throw 'Expected semantic residue diagnostic missing'}
$structural=@($classification.errors|Where-Object{$_ -match '^(missing:|schema:|capture:)'})
if($structural.Count -ne 0){throw 'Semantic UNKNOWN was incorrectly structural'}
Write-Output 'SEMANTIC_UNKNOWN_MORE_CONSERVATIVE=PASS'

$tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('voxi-shadow-child-test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tempRoot)|Out-Null
$pidPath=Join-Path $tempRoot 'child.pid'
$parentPath=Join-Path $tempRoot 'parent.ps1'
$parentSource=@'
param([string]$PidPath)
$child=Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile -Command "Start-Sleep -Seconds 30"' -PassThru -WindowStyle Hidden
[IO.File]::WriteAllText($PidPath,[string]$child.Id)
'@
[IO.File]::WriteAllText($parentPath,$parentSource,[Text.UTF8Encoding]::new($false))
$timer=[Diagnostics.Stopwatch]::StartNew()
$parent=Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -File "'+$parentPath+'" -PidPath "'+$pidPath+'"') -PassThru -WindowStyle Hidden
while(-not $parent.HasExited -and $timer.Elapsed.TotalSeconds -lt 5){Start-Sleep -Milliseconds 100;$parent.Refresh()}
if(-not $parent.HasExited){throw 'Direct parent did not exit promptly'}
$parent.WaitForExit();$timer.Stop()
if(-not (Test-Path -LiteralPath $pidPath)){throw 'Dummy child PID missing'}
$childPid=[int](Get-Content -LiteralPath $pidPath -Raw)
$child=Get-Process -Id $childPid -ErrorAction SilentlyContinue
if($null -eq $child){throw 'Long-lived dummy child did not survive direct parent'}
Stop-Process -Id $childPid -Force
Remove-Item -LiteralPath $tempRoot -Recurse -Force
Write-Output ("DIRECT_PARENT_ONLY_WAIT=PASS elapsedMs={0}" -f $timer.ElapsedMilliseconds)
Write-Output 'RETAINED_DESCENDANT_NOT_WAITED_OR_TOUCHED_BY_RUNNER=PASS'

$golden='253ab93a2127806837cb472071846f568c811a34'
$mergeBase=(git -C $Repo merge-base $golden HEAD).Trim()
if($mergeBase -ne $golden){throw 'Golden commit is not an ancestor'}
Write-Output 'GOLDEN_ANCESTRY=PASS'
Write-Output 'HARNESS_FIX_TESTS=PASS'
