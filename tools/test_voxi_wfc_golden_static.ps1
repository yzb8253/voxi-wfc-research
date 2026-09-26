[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Module = Join-Path $Repo 'modules\voxi_wfc_golden'
function Assert-True([bool]$Condition,[string]$Message) { if(-not $Condition) { throw "STATIC_ASSERT_FAIL: $Message" } }
$sh = Get-Command sh.exe -ErrorAction SilentlyContinue
if($null -eq $sh) { $sh = Get-Command sh -ErrorAction SilentlyContinue }
$shPath = if($null -ne $sh) { $sh.Source } else { 'C:\Program Files\Git\bin\sh.exe' }
Assert-True (Test-Path -LiteralPath $shPath) 'sh parser unavailable'
$runtime = @('customize.sh','action.sh','service.sh','uninstall.sh','bin\common.sh','bin\goldenctl.sh','bin\golden-selftest.sh','bin\golden-runner.sh','bin\golden-preflight.sh','bin\x55-holder.sh') | ForEach-Object { Join-Path $Module $_ }
foreach($path in $runtime) {
  Assert-True (Test-Path -LiteralPath $path) "missing $path"
  & $shPath -n $path
  Assert-True ($LASTEXITCODE -eq 0) "sh -n failed: $path"
  Assert-True ((@([IO.File]::ReadAllBytes($path) | Where-Object { $_ -eq 13 }).Count) -eq 0) "Android payload contains CR: $path"
}
$prop = Get-Content (Join-Path $Module 'module.prop') -Raw
foreach($line in @('name=VOXI WFC Golden Recovery RC3','version=v1.1.0-rc3','versionCode=112')) { Assert-True ($prop -match "(?m)^$([regex]::Escape($line))$") "module.prop missing $line" }
$action = Get-Content (Join-Path $Module 'action.sh') -Raw
$ctl = Get-Content (Join-Path $Module 'bin\goldenctl.sh') -Raw
$runner = Get-Content (Join-Path $Module 'bin\golden-runner.sh') -Raw
$preflight = Get-Content (Join-Path $Module 'bin\golden-preflight.sh') -Raw
$common = Get-Content (Join-Path $Module 'bin\common.sh') -Raw
$selftest = Get-Content (Join-Path $Module 'bin\golden-selftest.sh') -Raw
Assert-True ($action -match 'goldenctl\.sh" recover') 'RC3 Action does not dispatch recover'
Assert-True ($ctl -match 'recover_command\(\)[\s\S]*selftest_command') 'recover does not call frozen self-test first'
Assert-True ($ctl -match 'export PRE_RECOVERY_GATE_PASSED=YES') 'self-test authorization export missing'
Assert-True ($runner -match 'PRE_RECOVERY_GATE_PASSED') 'runner does not require pre-recovery token'
Assert-True ($ctl -match 'self-test\) selftest_command') 'read-only self-test CLI missing'
$restoreSegment = [regex]::Match($ctl,'restore_native_command\(\)[\s\S]*?\n\}\n\nlogs_command').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($restoreSegment)) 'restore-native command segment not found'
Assert-True ($restoreSegment -notmatch 'step_target_gate_readonly|step_network_observe_readonly|step_probe_gate') 'restore-native incorrectly depends on target/network/probe gates'
Assert-True ($restoreSegment -match 'step_root_gate' -and $restoreSegment -match 'step_module_runtime_gate' -and $restoreSegment -match 'step_platform_gate_readonly') 'restore-native prerequisite set incomplete'
Assert-True ($runner -match 'A_SETTLE_SECONDS=20' -and $runner -match 'P_SETTLE_SECONDS=20' -and $runner -match 'MAX_RECOVERY_ATTEMPTS=2' -and $runner -match 'POST_PON_SETTLE_SECONDS=10' -and $runner -match 'SIM_OFF_HOLD_SECONDS=3') 'Golden timing changed'
Assert-True ($runner -match 'while \[ "\$I" -lt 20 \]' -and $runner -match 'while \[ "\$I" -lt 30 \]' -and $runner -match 'while \[ "\$I" -lt 15 \]') 'Golden timeout budget changed'
foreach($stage in @('A0','P','X55_SHUTDOWN','HOLDER_START','X55_POWERUP','PON_SUCCESS','SIM_CYCLE','WFC_WAIT','FREEZE_COMMIT','ATTEMPT_FAILURE_CLEANUP')) { Assert-True ($runner -match "stage_run\s+$stage\b") "stage invocation missing: $stage" }
$normalOff = [regex]::Matches($runner,'service call phone "\$SIM_POWER_TRANSACTION" i32 1 i32 0').Count
$normalOn = [regex]::Matches($runner,'service call phone "\$SIM_POWER_TRANSACTION" i32 1 i32 1').Count
Assert-True ($normalOff -eq 1) "SIM OFF count=$normalOff"
Assert-True ($normalOn -eq 2) "SIM ON count=$normalOn (normal + emergency expected)"
Assert-True ([regex]::Matches($runner,'service call phone[^\r\n]*i32 0 i32').Count -eq 0) 'slot0 write path detected'
Assert-True ($runner -match 'SIM_MAY_BE_OFF=1' -and $runner -match 'emergency_sim_on') 'emergency ON guard missing'
Assert-True ($runner -match 'FREEZE_ON_HEALTHY=1') 'freeze success missing'
Assert-True ([regex]::Matches($runner,'(?m)^\s*FREEZE_ON_HEALTHY=1\s*$').Count -eq 1) 'premature/multiple freeze commit assignment'
Assert-True ($runner -match 'commit_freeze_success\(\)[\s\S]*FREEZE_ON_HEALTHY=1') 'freeze commit function missing assignment'
Assert-True ($runner -match 'attempt_failure_cleanup\(\)[\s\S]*emergency_sim_on[\s\S]*restore_native') 'attempt cleanup ordering missing'
Assert-True ($runner -match 'stage_run ATTEMPT_FAILURE_CLEANUP attempt_failure_cleanup[\s\S]*ATTEMPT=\$\(\(ATTEMPT \+ 1\)\)') 'attempt cleanup is not before bounded retry'
Assert-True ($runner -match 'FREEZE_INTEGRITY_FAILED[\s\S]*ATTEMPT_FAILURE_CLEANUP') 'freeze integrity failure does not enter cleanup'
Assert-True ($preflight -notmatch 'killall|pkill') 'broad holder kill detected'
Assert-True ([regex]::Matches($preflight,'kill -TERM "\$HPID"').Count -eq 1) 'exact holder TERM count changed'
Assert-True ([regex]::Matches($preflight,'kill -KILL "\$HPID"').Count -eq 1) 'exact holder KILL count changed'
foreach($name in @('load_probe_fields','collect_platform_status','collect_network_status','collect_owner_entry_status','print_health','print_network_status','print_owner_entry_status')) { Assert-True ($common -match "(?s)$name\(\).*?return 0\s*\n\}") "explicit return 0 missing: $name" }
Assert-True ($common -match 'if \[ "\$\(settings get global wifi_on') 'Wi-Fi no-op check missing'
Assert-True ($common -notmatch 'grep[^\r\n]*\^default[^\r\n]*dev tun0') 'strict default/tun0 gate remains'
Assert-True ($selftest -notmatch 'cmd connectivity airplane-mode|svc wifi enable|setprop ctl\.|service call phone') 'read-only self-test has effect'
Assert-True ($runner -notmatch 'exit\s+1\b' -and $ctl -notmatch 'exit\s+1\b' -and $action -notmatch 'exit\s+1\b') 'public RC=1 leak remains'
$owner = Join-Path $Repo 'tools\test_voxi_wfc_golden_owner_preflight.sh'
$selftestFixture = Join-Path $Repo 'tools\test_voxi_wfc_golden_selftest.sh'
$mock = Join-Path $Repo 'tools\test_voxi_wfc_golden_recovery_mock.sh'
foreach($fixture in @($owner,$selftestFixture,$mock)) { & $shPath -n $fixture; Assert-True ($LASTEXITCODE -eq 0) "fixture parse failed: $fixture" }
$ownerOut = @(& $shPath $owner 2>&1); Assert-True ($LASTEXITCODE -eq 0 -and (($ownerOut -join "`n") -match 'OWNER_PREFLIGHT_FIXTURES=7/7 PASS')) 'owner fixtures failed'
$selfOut = @(& $shPath $selftestFixture 2>&1); Assert-True ($LASTEXITCODE -eq 0 -and (($selfOut -join "`n") -match 'RC1_SELFTEST_FIXTURE=PASS')) 'self-test fixture failed'
$mockOut = @(& $shPath $mock 2>&1); Assert-True ($LASTEXITCODE -eq 0 -and (($mockOut -join "`n") -match 'HOST_MODEL_PASS fixtures=16')) 'recovery host model failed'
$matrix = Join-Path $Repo 'tools\test_voxi_wfc_golden_shell_matrix.ps1'
$matrixOut = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $matrix 2>&1); Assert-True ($LASTEXITCODE -eq 0 -and (($matrixOut -join "`n") -match 'SHELL_OPTION_REGRESSION=PASS')) 'shell option matrix failed'
$stagedGolden = @(git -C $Repo diff --cached --name-only -- 'experiments/wfc_repeatability_normalization/v262_freeze_run')
Assert-True ($stagedGolden.Count -eq 0) 'Golden source staged for modification'
$unstagedGolden = @(git -C $Repo diff --name-only -- 'experiments/wfc_repeatability_normalization/v262_freeze_run')
Assert-True ($unstagedGolden.Count -eq 0) 'Golden source modified in worktree'
$selftestDiff = @(git -C $Repo diff --name-only -- 'modules/voxi_wfc_golden/bin/golden-selftest.sh')
Assert-True ($selftestDiff.Count -eq 0) 'RC1 self-test changed'
Write-Host 'PS5.1_STATIC=PASS'
Write-Host 'RC1_SELFTEST_PATH_STATE_WRITES=0'
Write-Host 'RECOVERY_CONTROLFLOW_AUDIT=PASS'
Write-Host 'OWNER_PREFLIGHT_FIXTURES=7/7 PASS'
Write-Host 'HOST_MODEL_PASS fixtures=16'
Write-Host 'SHELL_OPTION_REGRESSION=PASS'
Write-Host 'SIM_OFF_WRITE_PATHS=1'
Write-Host 'SIM_ON_NORMAL_WRITE_PATHS=1'
Write-Host 'SIM_ON_EMERGENCY_GUARDED_PATHS=1'
Write-Host 'SLOT0_WRITE_PATHS=0'
Write-Host 'UNKNOWN_HOLDER_KILL_PATHS=0'
Write-Host 'MAX_ATTEMPTS=2'
Write-Host 'GOLDEN_TIMING_UNCHANGED=PASS'
Write-Host 'GOLDEN_STAGED_CHANGES=0'
Write-Host 'RC1_SELFTEST_UNCHANGED=PASS'
Write-Host 'RESTORE_NATIVE_NO_NETWORK_TARGET_DEPENDENCY=PASS'
Write-Host 'PHONE_WRITES=0'
Write-Host 'STATIC_TESTS=PASS'
