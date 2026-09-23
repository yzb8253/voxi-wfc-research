Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Main = Join-Path $Root 'X55-WFC-OneClick-v2.7-alpha-native-handoff.ps1'
$Launcher = Join-Path $Root 'Run-X55-WFC-v2.7-alpha-native-handoff.cmd'
$Dual = Join-Path $Root 'device\v27_sim_cycle_dual.sh'
$Single = Join-Path $Root 'device\v27_sim_cycle_single.sh'
$Failures = [Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name) { if($Condition){ Write-Host "PASS $Name" } else { Write-Host "FAIL $Name"; $Failures.Add($Name) } }
function Count-Literal([string]$Text,[string]$Needle) { ([regex]::Matches($Text,[regex]::Escape($Needle))).Count }
foreach($path in @($Main,$Launcher,$Dual,$Single)){ Check (Test-Path -LiteralPath $path) "exists: $(Split-Path $path -Leaf)" }
if($Failures.Count){ throw "Missing required files: $($Failures -join ', ')" }
$mainText=[IO.File]::ReadAllText($Main)
$launcherText=[IO.File]::ReadAllText($Launcher)
$dualText=[IO.File]::ReadAllText($Dual)
$singleText=[IO.File]::ReadAllText($Single)
$tokens=$null; $errors=$null
[void][Management.Automation.Language.Parser]::ParseFile($Main,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'PowerShell parser'
Check (-not [regex]::IsMatch($mainText,'(?i)(?<![A-Za-z0-9_])\$pid(?![A-Za-z0-9_])')) 'no PID automatic-variable collision'
Check ($mainText.Contains('[switch]$Execute')) 'execution requires explicit switch'
Check ($mainText.Contains('EXECUTE-V2.7-ALPHA-NATIVE-HANDOFF')) 'fixed confirmation token'
Check ($launcherText -match '(?im)^if /I "%~1"=="execute"') 'launcher requires explicit execute argument'
Check ($launcherText -match '-Execute -Confirmation EXECUTE-V2\.7-ALPHA-NATIVE-HANDOFF') 'launcher forwards fixed confirmation'
Check ((Count-Literal $mainText 'setprop ctl.stop vendor.per_mgr') -eq 1) 'one per_mgr stop call site'
Check ((Count-Literal $mainText 'setprop ctl.restart vendor.qcrild2') -eq 1) 'one qcrild2 restart call site'
Check ((Count-Literal $mainText "setprop ctl.restart vendor.qcrild'") -eq 0) 'no primary qcrild restart'
Check ((Count-Literal $mainText 'kill -TERM $($script:HolderAndroidProcessId)') -eq 1) 'one fixed holder TERM call site'
Check ($mainText.Contains('Test-OwnedHolder $script:HolderAndroidProcessId')) 'holder identity revalidated before TERM'
Check ($mainText.Contains('$contended.PmService.ParentProcessId -eq 1')) 'contended pm-service requires init parent'
Check ($mainText.Contains('$candidate.ParentProcessId -ne 1')) 'replacement qcrild2 requires init parent'
Check ($mainText.Contains('NATIVE_REACQUIRE_FAILED') -and $mainText.Contains('SIM cycle forbidden')) 'native failure forbids SIM cycle'
Check ($mainText.IndexOf("$" + "script:NativeHandoffResult='PM_SERVICE_REACQUIRED'") -lt $mainText.IndexOf('Start-OneShotSimCycle $orchestratorRemote')) 'SIM cycle occurs only after native reacquire'
Check ($mainText.Contains('if(Test-Healthy $postHandoff)')) 'healthy post-handoff skips cycle branch'
Check ($mainText.Contains('0,3,6,9,12,15,18,21,24,27,30')) 'post-cycle observation bounded to 30 seconds'
Check ($mainText.Contains('$script:RecoveryResult') -and $mainText.Contains('$script:NativeHandoffResult') -and $mainText.Contains('$script:FinalWfcResult') -and $mainText.Contains('$script:CleanupResult')) 'separate result dimensions'
Check ($mainText.Contains('BE877B6E9694B4100F2487DC892803DE6399C89588F194A1E54D4C3AE3173A31') -and $mainText.Contains('90D6F55FBE1F941C1E3EEE1AA1F93B569FA3AE4084B93C5560082A38AAAF5C39')) 'fixed audited helper hashes'
Check ($mainText.Contains("$" + "helperClass='Slot1SimPowerHelper'") -and $mainText.Contains("$" + "helperClass='SingleSimSlot1PowerHelper'")) 'fixed helper classes'
Check ($mainText.Contains('[int]$target.slotId -eq 1') -and $mainText.Contains('[int]$slot0.slotId -eq 0')) 'fixed target/protected slot gates'
Check ($mainText.Contains("$" + "state.X55 -eq 'ONLINE' -and $" + "state.CrashCount -eq '0'")) 'native reacquire requires ONLINE and crash zero'
Check ($mainText.Contains('(Test-PmOwner $state $state.PmService.ProcessId)')) 'native reacquire requires pm-service ownership'
Check ($mainText.Contains('ProcessId -eq $oldQcrild2ProcessId')) 'native reacquire requires changed qcrild2 PID'
Check ($mainText.Contains('REVOTE_MECHANISM_LOG=') -and $mainText.Contains('UNPROVEN')) 're-vote evidence is reported separately'
$forbidden=@('restart-modem','ctl.restart vendor.cnd','ctl.restart .qtidataservices','ctl.restart org.codeaurora.ims','resetIms','setenforce','kill -9','killall','pkill','settings put','settings delete','reboot')
foreach($item in $forbidden){ Check (-not $mainText.Contains($item)) "forbidden path absent: $item" }
foreach($pair in @(@('dual',$dualText),@('single',$singleText))){
  $name=$pair[0]; $text=$pair[1]
  Check ($text.Contains('[ "$#" -eq 0 ]')) "$name accepts no arguments"
  Check ($text.Contains('[ "$X55_V27_MODE" = 1 ]') -and $text.Contains('[ "$X55_V27_EXECUTE" = YES ]')) "$name environment locks"
  Check ((Count-Literal $text 'helper POWER_DOWN') -eq 1) "$name one POWER_DOWN call site"
  Check ((Count-Literal $text 'helper POWER_UP') -eq 1) "$name one POWER_UP call site"
  Check ($text.Contains('UP_STARTED=1') -and $text.Contains('[ "$UP_STARTED" -eq 0 ]')) "$name POWER_UP one-shot guard"
  Check ($text.Contains('sleep 3')) "$name fixed three-second hold"
  Check ($text.Contains('up_rc=$?') -and $text.Contains('[ "$up_rc" -eq 0 ]')) "$name preserves POWER_UP status"
  Check (-not $text.Contains([string][char]13)) "$name LF-only"
}
if($Failures.Count){ Write-Host "STATIC_AUDIT=FAIL count=$($Failures.Count)"; throw ($Failures -join [Environment]::NewLine) }
Write-Host 'STATIC_AUDIT=PASS'
Write-Host 'PHONE_ACTIONS=0'
