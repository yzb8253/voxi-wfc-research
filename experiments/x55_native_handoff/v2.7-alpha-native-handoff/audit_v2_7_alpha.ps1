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
Write-Host "WINDOWS_POWERSHELL_VERSION=$($PSVersionTable.PSVersion.ToString())"
Check ($PSVersionTable.PSVersion.Major -eq 5) 'Windows PowerShell major version 5'
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
$automaticAssignmentPattern='(?im)(?<![A-Za-z0-9_])\$(?:PID|Matches|Error|Args|Input|Home|Host|Null|True|False)(?![A-Za-z0-9_])\s*(?:\+\+|--|\+=|-=|=)'
Check (-not [regex]::IsMatch($mainText,$automaticAssignmentPattern)) 'no automatic-variable custom assignments'
$forbiddenMatchesToken=([string][char]36) + 'matches'
Check ($mainText.IndexOf($forbiddenMatchesToken,[StringComparison]::OrdinalIgnoreCase) -lt 0) 'no custom Matches variable token'
Check ((Count-Literal $mainText 'Get-FileHash') -eq 0) 'no legacy hash cmdlet dependency'
Check ($mainText.Contains('function Get-Sha256Hex') -and $mainText.Contains('[IO.File]::OpenRead($Path)') -and $mainText.Contains('[Security.Cryptography.SHA256]::Create()')) '.NET SHA-256 implementation present'
Check ($mainText.Contains('$sha.Dispose()') -and $mainText.Contains('$stream.Dispose()')) 'hash resources disposed'
Check ($mainText.Contains('$actualHash=Get-Sha256Hex $Path') -and $mainText.Contains('$actualHash -ceq $ExpectedHash')) 'artifact assertion uses exact production hash'
Check ($mainText.Contains('Assert-LocalArtifact $SingleHelperLocal $SingleHelperHash')) 'selftest invokes production artifact assertion'
Check ($mainText.Contains('BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD')) 'SHA-256 known vector pinned'
Check ($mainText.Contains('$orchestratorHash=Get-Sha256Hex $orchestratorLocal')) 'orchestrator uses production hash engine'
Check (-not $mainText.Contains('$info.ArgumentList')) 'no ProcessStartInfo.ArgumentList dependency'
Check (-not $mainText.Contains('.Kill($true)')) 'no Process.Kill(bool) dependency'
Check ($mainText.Contains('function Stop-OwnedHostProcessTree') -and $mainText.Contains("'/PID {0} /T /F' -f `$Process.Id")) 'PS5.1 exact host process-tree cleanup retained'
Check ($mainText.Contains('Join-WindowsCommandLine $Arguments')) 'PS5.1 process argv builder used'
Check ($mainText.Contains("Join-WindowsCommandLine @('-s',`$Serial,'shell'")) 'holder argv uses PS5.1 builder'
Check ($mainText.Contains('[switch]$StaticNoAdb')) 'explicit static no-ADB mode'
Check ($mainText.IndexOf('if($StaticNoAdb)') -lt $mainText.IndexOf('[IO.Directory]::CreateDirectory($RunDir)')) 'static mode exits before run/ADB initialization'
Check ($mainText.Contains("Require (`$PSVersionTable.PSVersion.Major -eq 5)")) 'static mode requires Windows PowerShell 5.1'
Check ($launcherText -match '(?im)^if /I "%~1"=="selftest"') 'launcher exposes selftest mode'
Check ($launcherText -match '-StaticNoAdb') 'launcher selftest is no-ADB'
Check (-not [regex]::IsMatch($mainText,'(?i)ForEach-Object\s+-Parallel|\bJoin-String\b|\bGet-Error\b|\bTest-Json\b|\$IsWindows\b')) 'no known PS7-only cmdlets or variables'
Check ($mainText.Contains('[switch]$Execute')) 'execution requires explicit switch'
Check ($mainText.Contains('EXECUTE-V2.7-ALPHA-NATIVE-HANDOFF')) 'fixed confirmation token'
Check ($launcherText -match '(?im)^\) else if /I "%~1"=="execute"') 'launcher requires explicit execute argument'
Check ($launcherText -match '-Execute -Confirmation EXECUTE-V2\.7-ALPHA-NATIVE-HANDOFF') 'launcher forwards fixed confirmation'
Check ((Count-Literal $mainText 'setprop ctl.stop vendor.per_mgr') -eq 1) 'one per_mgr stop call site'
$qcrild2RestartToken='setprop ctl.'+'restart vendor.qcrild2'
Check ((Count-Literal $mainText $qcrild2RestartToken) -eq 0) 'no qcrild2 restart in new production path'
Check ((Count-Literal $mainText "setprop ctl.restart vendor.qcrild'") -eq 0) 'no primary qcrild restart'
Check ((Count-Literal $mainText 'kill -TERM $($script:HolderAndroidProcessId)') -eq 1) 'one fixed holder TERM call site'
Check ($mainText.Contains('Test-ExactAndroidHolderIdentity $script:HolderAndroidProcessId')) 'exact Android holder identity revalidated before TERM'
Check ($mainText.Contains("PidFileValue -cne `$ExpectedProcessId.ToString()") -and $mainText.Contains("Fd9 -cne `$DeviceNode")) 'holder PID-file and FD9 identity gates'
Check ($mainText.Contains("`$parts[0] -ceq '/system/bin/sh'") -and $mainText.Contains("`$parts[2] -ceq (New-HolderCommand)")) 'holder exact cmdline gate'
Check (-not $mainText.Contains('function Test-OwnedHolder')) 'Android holder identity no longer depends on host process lifetime'
Check ($mainText.Contains('function Test-HolderSoleOwnerModel') -and $mainText.Contains('function Test-HolderPmDualOwnerModel') -and $mainText.Contains('function Test-PmSoleOwnerModel')) 'three ownership topology models present'
Check ($mainText.Contains('ids.Count -eq 2') -and $mainText.Contains('ids.Count -eq 1')) 'owner models enforce exact cardinality'
Check ($mainText.Contains("`$script:NativeHandoffResult='EXPECTED_DUAL_OWNER_NOT_FORMED'")) 'missing dual-owner result is explicit'
Check ($mainText.Contains("`$script:NativeHandoffResult='POST_BREAK_NATIVE_OWNER_INVALID'")) 'invalid post-break owner result is explicit'
Check ($mainText.Contains("`$script:NativeHandoffResult='POST_BREAK_X55_REGRESSION'")) 'post-break X55 regression result is explicit'
Check ($mainText.Contains("`$script:NativeHandoffResult='MAKE_BEFORE_BREAK_NATIVE_HANDOFF_SUCCESS'")) 'make-before-break success result is explicit'
Check ($mainText.Contains('SIM cycle forbidden')) 'native handoff failure forbids SIM cycle'
Check ($mainText.IndexOf("$" + "script:NativeHandoffResult='MAKE_BEFORE_BREAK_NATIVE_HANDOFF_SUCCESS'") -lt $mainText.IndexOf('Start-OneShotSimCycle $orchestratorRemote')) 'SIM cycle occurs only after native handoff success'
Check ($mainText.Contains('if(Test-Healthy $postHandoff)')) 'healthy post-handoff skips cycle branch'
Check ($mainText.Contains('0,3,6,9,12,15,18,21,24,27,30')) 'post-cycle observation bounded to 30 seconds'
Check ($mainText.Contains('$script:RecoveryResult') -and $mainText.Contains('$script:NativeHandoffResult') -and $mainText.Contains('$script:FinalWfcResult') -and $mainText.Contains('$script:CleanupResult')) 'separate result dimensions'
Check ($mainText.Contains('BE877B6E9694B4100F2487DC892803DE6399C89588F194A1E54D4C3AE3173A31') -and $mainText.Contains('90D6F55FBE1F941C1E3EEE1AA1F93B569FA3AE4084B93C5560082A38AAAF5C39')) 'fixed audited helper hashes'
Check ($mainText.Contains("$" + "helperClass='Slot1SimPowerHelper'") -and $mainText.Contains("$" + "helperClass='SingleSimSlot1PowerHelper'")) 'fixed helper classes'
Check ($mainText.Contains('[int]$target.slotId -eq 1') -and $mainText.Contains('[int]$slot0.slotId -eq 0')) 'fixed target/protected slot gates'
Check ($mainText.Contains("`$released.X55 -ne 'ONLINE' -or `$released.CrashCount -ne '0'")) 'post-break handoff requires ONLINE and crash zero'
Check ($mainText.Contains('(Test-PmSoleOwner $released)')) 'post-break handoff requires exact pm-service sole ownership'
Check ($mainText.Contains('ProcessId -eq $entryQcrild2ProcessId')) 'qcrild2 PID must remain unchanged'
Check ($mainText.Contains('REVOTE_MECHANISM_LOG=') -and $mainText.Contains('UNPROVEN')) 're-vote evidence is reported separately'
Check ($mainText.Contains("`$single + `$Value.Replace(`$single, `$escape) + `$single")) 'Android su command single-quote escaping retained'
Check ($mainText.Contains('function Normalize-AndroidShellText') -and $mainText.Contains('.Replace("`r`n", "`n").Replace("`r", '''')')) 'Android LF normalization helper exists'
Check ($mainText.Contains('$androidCommand = Normalize-AndroidShellText $Command')) 'all Invoke-Root payloads normalized'
Check ($mainText.Contains('$holderCommand=Normalize-AndroidShellText (New-HolderCommand)')) 'direct holder payload normalized'
Check ($mainText.Contains("@('shell', ('su -c ' + (ConvertTo-ShSingleQuoted `$androidCommand)))")) 'normalized su -c payload remains one adb argument'
Check ($mainText.Contains("exec 9<{1}") -and $mainText.Contains("echo `$$ > {0}") -and $mainText.Contains("while :; do sleep 60; done")) 'holder shell lifecycle and FD9 syntax retained'
Check ($mainText.Contains("trap ''rm -f {0}'' EXIT") -and $mainText.Contains("trap ''exit 0'' TERM INT HUP")) 'holder PID-file and TERM traps retained'
$stopPerMgrCall=[regex]::Match($mainText,'(?m)^  Stop-PerMgr\r?$').Index
$holderStartCall=[regex]::Match($mainText,'(?m)^  \$script:HolderHostProcess=Start-OwnedHolder\r?$').Index
$startPerMgrCall=[regex]::Match($mainText,'(?m)^  Start-PerMgr\r?$').Index
$dualGateCall=[regex]::Match($mainText,'(?m)^  \$dualOwnerReady=Wait-Until \{\r?$').Index
$holderStopCall=[regex]::Match($mainText,'(?m)^  Stop-OwnedHolder\r?$').Index
$pmSoleGateCall=[regex]::Match($mainText,'(?m)^  \$pmSoleReady=Wait-Until \{\r?$').Index
$nativeReadyMark=[regex]::Match($mainText,'(?m)^  \$script:NativeHandoffResult=''MAKE_BEFORE_BREAK_NATIVE_HANDOFF_SUCCESS''\r?$').Index
$simCycleCall=[regex]::Match($mainText,'(?m)^    Start-OneShotSimCycle \$orchestratorRemote\r?$').Index
Check ($stopPerMgrCall -gt 0 -and $stopPerMgrCall -lt $holderStartCall -and $holderStartCall -lt $startPerMgrCall -and
       $startPerMgrCall -lt $dualGateCall -and $dualGateCall -lt $holderStopCall -and
       $holderStopCall -lt $pmSoleGateCall -and $pmSoleGateCall -lt $nativeReadyMark -and
       $nativeReadyMark -lt $simCycleCall) 'make-before-break state-machine order'
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
Write-Host 'PS51_PARSE=PASS'
Write-Host 'AUTO_VARIABLE_AUDIT=PASS'
Write-Host 'CUSTOM_MATCHES_VARIABLES=0'
Write-Host 'ADB_QUOTING_AUDIT=PASS'
Write-Host 'HOLDER_IDENTITY_REDESIGNED=PASS'
Write-Host 'HOST_PROCESS_DEPENDENCY_REMOVED=PASS'
Write-Host 'DUAL_OWNER_GATE=PASS'
Write-Host 'EXACT_TERM_GATE=PASS'
Write-Host 'PM_SOLE_POST_BREAK_GATE=PASS'
Write-Host 'QCRILD2_RESTART_REMOVED_FROM_PRODUCTION_PATH=PASS'
Write-Host 'QCRILD2_RESTARTS_IN_NEW_PATH=0'
Write-Host 'MAKE_BEFORE_BREAK_STATE_MACHINE=PASS'
Write-Host 'STATIC_AUDIT=PASS'
Write-Host 'PHONE_ACTIONS=0'
