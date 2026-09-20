$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Watchdog = Get-Content -Raw (Join-Path $Root "device\absent_soft_reboot_watchdog.sh")
$Orchestrator = Get-Content -Raw (Join-Path $Root "device\absent_soft_reboot_orchestrator.sh")

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

Require-Match $Watchdog 'ROLLBACK_AFTER_DOWN=120' 'dedicated rollback deadline is 120 seconds'
Require-Match $Orchestrator 'HOST_SOFT_DEADLINE=75' 'device-side host soft deadline is 75 seconds'
Require-Match $Watchdog 'deadline=\$\(\( \$\(date \+%s\) \+ ROLLBACK_AFTER_DOWN \)\)' 'rollback uses absolute wall-clock deadline'
Require-Match $Orchestrator 'EXPECTED_HELPER_SHA256=be877b6e9694b4100f2487dc892803de6399c89588f194a1e54d4c3ae3173a31' 'audited helper hash is pinned'
Require-Match $Orchestrator 'before\.strictGate=true' 'strict dual-SIM helper gate is required'
Require-Match $Orchestrator 'ip link show wlan0' 'wlan0 is gated'
Require-Match $Orchestrator 'ip link show tun0' 'tun0 is gated'
Require-Match $Orchestrator 'slot0.*active=true.*simState=5.*mappingGate=true' 'slot0 remains protected during down confirmation'
Require-Count $Orchestrator 'helper POWER_DOWN' 1 'exactly one POWER_DOWN call path exists'
Require-Count $Orchestrator 'helper POWER_UP' 1 'exactly one normal POWER_UP call path exists'
Require-Count $Watchdog 'helper POWER_UP' 1 'exactly one watchdog fallback POWER_UP path exists'
Require-Match $Orchestrator 'vendor\.qcrild2 main u:r:rild:s0.*-c 2' 'target qcrild2 identity is fixed to ROM Name=main'
Require-Match $Orchestrator 'vendor\.qcrild main u:r:rild:s0' 'primary qcrild identity is fixed to ROM Name=main'
Require-Match $Orchestrator 'vendor\.netmgrd.*u:r:vendor_netmgrd:s0' 'netmgrd identity is fixed'
Require-Match $Orchestrator 'vendor\.imsqmidaemon.*u:r:vendor_ims:s0' 'imsqmidaemon identity is fixed'
Require-Match $Orchestrator 'vendor\.imsdatadaemon.*u:r:vendor_ims:s0' 'imsdatadaemon identity is fixed'
Require-Match $Orchestrator 'vendor\.cnd.*u:r:vendor_cnd:s0' 'cnd identity is fixed'
Require-Match $Orchestrator 'find_exact_app \.qtidataservices 10104' 'qtidataservices UID and name are fixed'
Require-Match $Orchestrator 'find_exact_app org\.codeaurora\.ims 10196' 'Qualcomm IMS UID and name are fixed'
Require-Match $Orchestrator 'find_exact_app com\.android\.phone 1001' 'primary phone UID and name are fixed'
Require-Match $Orchestrator 'find_exact_app system_server 1000' 'system_server UID and name are fixed'
Require-Match $Orchestrator '\[ "\$#" -eq 0 \]' 'orchestrator accepts no arguments'
Require-Match $Watchdog '\[ "\$#" -eq 0 \]' 'watchdog accepts no arguments'
Require-Match $Orchestrator 'kill -TERM "\$old"' 'only exact resolved PIDs are signaled'
Reject-Match ($Watchdog + $Orchestrator) 'kill\s+-9|killall|pkill|restart-modem|resetIms|setRadioPower|setprop|settings\s+(put|delete)|\breboot\b|ctl\.restart|QMI.*transaction|setenforce' 'forbidden operations are absent'
Reject-Match ($Watchdog + $Orchestrator) 'TARGET_SLOT_ID|slotId=|subId=.*\$|POWER_DOWN\s+[0-9]|POWER_UP\s+[0-9]' 'no runtime target argument is accepted'
Require-Match $Orchestrator '(?s)ABSENT_PREFLIGHT_ONLY.*YES.*PREFLIGHT_ONLY_PASS.*exit 0.*watchdog.ready' 'zero-write runtime preflight exits before watchdog gate and POWER_DOWN'
Require-Match $Watchdog 'GENERIC_READY_FILE=\$STATE_DIR/watchdog\.ready' 'dedicated watchdog bridges the helper generic ready marker'
Require-Match $Watchdog 'rm -f "\$READY_FILE" "\$GENERIC_READY_FILE"' 'both ready markers are cleaned'
Require-Match $Orchestrator 'POWER_DOWN_REJECTED_BEFORE_MARKER; no POWER_UP needed' 'pre-marker POWER_DOWN rejection does not issue POWER_UP'
Write-Host "ABSENT-STATE STATIC AUDIT: PASS"
