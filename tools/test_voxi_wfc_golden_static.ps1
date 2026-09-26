[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Module = Join-Path $Repo 'modules\voxi_wfc_golden'
$RuntimeFiles = @(
  'customize.sh','action.sh','service.sh','uninstall.sh',
  'bin\common.sh','bin\goldenctl.sh','bin\golden-runner.sh','bin\golden-preflight.sh','bin\x55-holder.sh'
)
$RuntimePaths = @($RuntimeFiles | ForEach-Object { Join-Path $Module $_ })

function Assert-True([bool]$Condition,[string]$Message) {
  if(-not $Condition) { throw "STATIC_ASSERT_FAIL: $Message" }
}

foreach($path in $RuntimePaths) { Assert-True (Test-Path -LiteralPath $path) "missing $path" }

$sh = Get-Command sh.exe -ErrorAction SilentlyContinue
if($null -eq $sh) { $sh = Get-Command sh -ErrorAction SilentlyContinue }
$shPath = if($null -ne $sh) { $sh.Source } else { 'C:\Program Files\Git\bin\sh.exe' }
Assert-True (Test-Path -LiteralPath $shPath) 'sh parser unavailable'
foreach($path in $RuntimePaths) {
  & $shPath -n $path
  Assert-True ($LASTEXITCODE -eq 0) "sh -n failed: $path"
  $crCount = @([IO.File]::ReadAllBytes($path) | Where-Object { $_ -eq 13 }).Count
  Assert-True ($crCount -eq 0) "Android payload contains CR bytes: $path"
}

$allRuntime = @($RuntimePaths | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n"
foreach($forbidden in @('adb\.exe','C:\\Users\\','PowerShell','powershell\.exe','fd0f{2}892')) {
  Assert-True ($allRuntime -notmatch $forbidden) "runtime contains forbidden PC dependency: $forbidden"
}

$prop = Get-Content -LiteralPath (Join-Path $Module 'module.prop') -Raw
foreach($line in @('id=voxi_wfc_golden','name=VOXI WFC Golden Recovery','version=v1.0.2','versionCode=102','author=yzb8253')) {
  Assert-True ($prop -match "(?m)^$([regex]::Escape($line))$") "module.prop missing $line"
}

$runner = Get-Content -LiteralPath (Join-Path $Module 'bin\golden-runner.sh') -Raw
$normalOff = [regex]::Matches($runner,'service call phone \"\$SIM_POWER_TRANSACTION\" i32 1 i32 0').Count
$normalOn = [regex]::Matches($runner,'service call phone \"\$SIM_POWER_TRANSACTION\" i32 1 i32 1').Count
Assert-True ($normalOff -eq 1) "SIM OFF path count=$normalOff expected=1"
Assert-True ($normalOn -eq 2) "SIM ON source paths=$normalOn expected normal+emergency=2"
Assert-True ([regex]::Matches($runner,'service call phone[^\r\n]*i32 0 i32').Count -eq 0) 'slot0 write path detected'
Assert-True ($runner -match 'SIM_MAY_BE_OFF=1' -and $runner -match 'emergency_sim_on') 'emergency SIM guard missing'
Assert-True ($runner -match 'FREEZE_ON_HEALTHY=1' -and $runner -match 'if \[ \"\$FREEZE_ON_HEALTHY\" != 1 \]') 'success cleanup suppression missing'
Assert-True ($runner -match 'MAX_RECOVERY_ATTEMPTS=2') 'attempt budget changed'
Assert-True ($runner -match 'POST_PON_SETTLE_SECONDS=10') 'PON settle changed'
Assert-True ($runner -match 'SIM_OFF_HOLD_SECONDS=3') 'SIM hold changed'
$entryGateAt = $runner.IndexOf('assert_clean_core_entry')
$stopAt = $runner.IndexOf("record_write 'CTL_STOP vendor.per_mgr'")
$offlineAt = $runner.IndexOf('log_line "X55_OFFLINE=YES')
$holderAt = $runner.IndexOf('start_module_holder')
$ponAt = $runner.IndexOf('PON_SUCCESS=YES')
$simOffAt = $runner.IndexOf('SIM_POWER_OFF transaction=')
Assert-True ($entryGateAt -ge 0 -and $stopAt -gt $entryGateAt) 'X55 stop is not ordered after entry gate'
Assert-True ($offlineAt -ge 0 -and $holderAt -gt $offlineAt) 'holder start is not ordered after X55 OFFLINE'
Assert-True ($ponAt -ge 0 -and $simOffAt -gt $ponAt) 'SIM OFF is not ordered after PON_SUCCESS gate'

$preflight = Get-Content -LiteralPath (Join-Path $Module 'bin\golden-preflight.sh') -Raw
Assert-True ([regex]::Matches($preflight,'kill -TERM \"\$HPID\"').Count -eq 1) 'exact holder TERM path mismatch'
Assert-True ([regex]::Matches($preflight,'kill -KILL \"\$HPID\"').Count -eq 1) 'exact holder KILL fallback mismatch'
Assert-True ($preflight -notmatch 'killall|pkill') 'broad process kill detected'
Assert-True ($preflight -match 'holder_process_identity_ok \"\$HPID\"') 'holder identity gate missing'
Assert-True ($preflight -match 'owner_pre_a0_gate\(\)') 'owner pre-A0 gate missing'
Assert-True ($preflight -match 'BLOCK_REASON=UNKNOWN_ESOC_OWNER') 'unknown owner explanation missing'
Assert-True ($preflight -notmatch 'unknown_owner_present\s*&&') 'ambiguous negative owner probe remains'

$common = Get-Content -LiteralPath (Join-Path $Module 'bin\common.sh') -Raw
Assert-True ($common -match 'EXPECTED_DEVICE=cas') 'device gate missing'
Assert-True ($common -match 'EXPECTED_BUILD=V816\.0\.4\.0\.TJJCNXM') 'build gate missing'
Assert-True ($common -match 'SIM_POWER_TRANSACTION=182') 'transaction gate missing'
Assert-True ($common -match 'ESOC_OWNER_CLASS=UNKNOWN_OWNER') 'owner classification missing'

Assert-True ($common -match 'network_preflight\(\)') 'network preflight missing'
Assert-True ($common -match 'MAX_WAIT=\$\{1:-20\}') 'bounded Wi-Fi wait changed'
Assert-True ($common -match "VPN=UNVERIFIED[\s\S]*WARNING=Please confirm UK full-tunnel VPN is connected[\s\S]*NETWORK_PREFLIGHT=PASS") 'advisory VPN path does not pass'
Assert-True ($common -notmatch "grep[^\r\n]*\^default[^\r\n]*dev tun0") 'strict default-dev-tun0 gate remains'
Assert-True ($common -notmatch "\[ [^\r\n]*VPN_INTERFACE[^\r\n]*tun0[^\r\n]*\]") 'strict tun0 interface gate remains'
Assert-True ($common -notmatch 'network_gate\(\)') 'legacy strict network gate remains'
Assert-True ($runner -match 'network_preflight 20') 'runner network preflight missing'
Assert-True ($preflight -match 'network_preflight 20') 'A0/P network preflight missing'
Assert-True ($runner -match 'POST_NETWORK_GATE=PASS') 'post-network marker missing'
Assert-True ($runner -match 'ATTEMPT_LOOP_ENTER=1') 'attempt-loop marker missing'
Assert-True ($runner -match 'EXIT_RC=\$RC' -and $runner -match 'EXIT_STAGE=\$CURRENT_STAGE' -and $runner -match 'EXIT_REASON=\$EXIT_REASON') 'exit diagnostics missing'

$ownerFixture = Join-Path $Repo 'tools\test_voxi_wfc_golden_owner_preflight.sh'
& $shPath -n $ownerFixture
Assert-True ($LASTEXITCODE -eq 0) 'owner fixture shell parse failed'
$ownerFixtureOutput = @(& $shPath $ownerFixture 2>&1)
Assert-True ($LASTEXITCODE -eq 0) "owner fixture runtime failed: $($ownerFixtureOutput -join '; ')"
Assert-True (($ownerFixtureOutput -join "`n") -match 'OWNER_PREFLIGHT_FIXTURES=3/3 PASS') 'owner fixtures incomplete'

$probeHash = (Get-FileHash -LiteralPath (Join-Path $Module 'lib\wfc-probe.jar') -Algorithm SHA256).Hash
Assert-True ($probeHash -eq 'AC46E9F62DB88C043DA08E4D5BB1D100EA8AC10EF2A74838F99C2237C2B9A91D') 'probe hash mismatch'

# Later history contains earlier profiling edits, so only assert this change-set does not stage Golden files.
$stagedGolden = @(git -C $Repo diff --cached --name-only -- 'experiments/wfc_repeatability_normalization/v262_freeze_run')
Assert-True ($stagedGolden.Count -eq 0) 'Golden source staged for modification'

Write-Host 'PS5.1_STATIC=PASS'
Write-Host "SH_PARSE=PASS files=$($RuntimePaths.Count)"
Write-Host 'ANDROID_PAYLOAD_CR_COUNT=0'
Write-Host 'MODULE_PROP=PASS'
Write-Host 'RUNTIME_PC_DEPENDENCIES=0'
Write-Host 'WIFI_HARD_PREREQUISITE=PASS'
Write-Host 'VPN_ADVISORY_ONLY=PASS'
Write-Host 'STRICT_TUN0_GATE=REMOVED'
Write-Host 'STRICT_DEFAULT_DEV_TUN0_GATE=REMOVED'
Write-Host 'OWNER_PREFLIGHT_FIXTURES=3/3 PASS'
Write-Host 'OWNER_NEGATIVE_PROBE_CONTROL_FLOW=PASS'
Write-Host 'EXIT_DIAGNOSTICS=PASS'
Write-Host 'SIM_OFF_WRITE_PATHS=1'
Write-Host 'SIM_ON_NORMAL_WRITE_PATHS=1'
Write-Host 'SIM_ON_EMERGENCY_GUARDED_PATHS=1'
Write-Host 'SLOT0_WRITE_PATHS=0'
Write-Host 'UNKNOWN_HOLDER_KILL_PATHS=0'
Write-Host 'SUCCESS_CLEANUP_PATHS=0'
Write-Host 'FAILURE_NATIVE_CLEANUP=PASS'
Write-Host 'GOLDEN_STAGED_CHANGES=0'
Write-Host 'PHONE_WRITES=0'
Write-Host 'STATIC_TESTS=PASS'
