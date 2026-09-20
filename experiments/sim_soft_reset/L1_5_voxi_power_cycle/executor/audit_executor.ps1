$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Java = Get-Content -Raw (Join-Path $Root "src\Slot1SimPowerHelper.java")
$Runner = Get-Content -Raw (Join-Path $Root "run_l1_5_executor.sh")
$Watchdog = Get-Content -Raw (Join-Path $Root "device\l1_5_rollback_watchdog.sh")

function Require-Match([string]$Text, [string]$Pattern, [string]$Label) {
    if ($Text -notmatch $Pattern) { throw "AUDIT FAIL: $Label" }
    Write-Host "PASS: $Label"
}

function Reject-Match([string]$Text, [string]$Pattern, [string]$Label) {
    if ($Text -match $Pattern) { throw "AUDIT FAIL: $Label" }
    Write-Host "PASS: $Label"
}

function Require-Count([string]$Text, [string]$Pattern, [int]$Expected, [string]$Label) {
    $Count = ([regex]::Matches($Text, $Pattern)).Count
    if ($Count -ne $Expected) { throw "AUDIT FAIL: $Label (expected $Expected, found $Count)" }
    Write-Host "PASS: $Label"
}

Require-Match $Java 'TARGET_SLOT_ID\s*=\s*1\s*;' 'target slot is compile-time fixed to 1'
Require-Match $Java 'PROTECTED_SLOT_ID\s*=\s*0\s*;' 'slot0 is protection-only'
Require-Match $Java 'setSimPowerStateForSlot"\s*,\s*int\.class\s*,\s*int\.class\s*,\s*Executor\.class\s*,\s*Consumer\.class' 'callback overload is selected'
Require-Match $Java 'method\.invoke\(tm, TARGET_SLOT_ID, state, direct, callback\)' 'write call uses fixed target constant'
Require-Count $Java 'method\.invoke\(tm, TARGET_SLOT_ID, state, direct, callback\)' 1 'exactly one SIM-power invocation exists'
Require-Match $Java 'args\.length != 1' 'helper accepts exactly one command token'
Require-Match $Java '(?s)"DRY_RUN"\.equals\(args\[0\]\).*"ARM_ROLLBACK"\.equals\(args\[0\]\).*"CHECK_ROLLBACK"\.equals\(args\[0\]\).*"POWER_DOWN"\.equals\(args\[0\]\).*"POWER_UP"\.equals\(args\[0\]\)' 'command allowlist is closed'
Require-Match $Java '"1"\.equals\(System\.getenv\("LAB_MODE"\)\)' 'helper requires LAB_MODE=1'
Require-Match $Java '"YES"\.equals\(System\.getenv\("LAB_EXECUTE"\)\)' 'helper requires LAB_EXECUTE=YES'
Require-Match $Java 'WATCHDOG_READY_FILE' 'POWER_DOWN requires watchdog readiness'
Require-Match $Watchdog 'ROLLBACK_AFTER_DOWN=30' 'watchdog timeout is fixed at 30 seconds'
Require-Match $Watchdog 'deadline=\$\(\( \$\(date \+%s\) \+ MAX_WAIT_FOR_DOWN \)\)' 'watchdog no-down wait uses a wall-clock deadline'
Require-Match $Watchdog 'deadline=\$\(\( \$\(date \+%s\) \+ ROLLBACK_AFTER_DOWN \)\)' 'watchdog rollback wait uses a wall-clock deadline'
Require-Match $Watchdog 'helper POWER_UP' 'watchdog owns an independent POWER_UP path'
Require-Match $Watchdog 'mkdir "\$LOCK_DIR"' 'watchdog uses an atomic single-instance lock'
Require-Match $Runner 'LAB_MODE=\$\{LAB_MODE:-0\}' 'runner defaults LAB_MODE to 0'
Require-Match $Runner 'LAB_EXECUTE=\$\{LAB_EXECUTE:-NO\}' 'runner defaults execution authorization to NO'
Reject-Match $Java 'method\.invoke\(tm,\s*PROTECTED_SLOT_ID' 'no slot0 power invocation'
Reject-Match ($Runner + $Watchdog) '(restart-modem|setprop|settings put|reboot|killall|pkill|qcrild)' 'no unrelated radio/process action'

Write-Host "STATIC EXECUTOR AUDIT: PASS"
