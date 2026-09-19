$ErrorActionPreference = 'Stop'

$release = Split-Path -Parent $PSScriptRoot
$module = Join-Path $release 'module'
$ctl = Get-Content -LiteralPath (Join-Path $module 'bin/wfcctl.sh') -Raw
$auto = Get-Content -LiteralPath (Join-Path $module 'bin/wfc-auto-recover.sh') -Raw
$action = Get-Content -LiteralPath (Join-Path $module 'action.sh') -Raw
$customize = Get-Content -LiteralPath (Join-Path $module 'customize.sh') -Raw
$executableText = Get-ChildItem -LiteralPath $module -Recurse -File |
    Where-Object { $_.Extension -in '.sh','.prop' } |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
$all = $executableText -join "`n"

function Assert-True([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    "${Name}: PASS"
}

Assert-True ($ctl -match 'VERSION=v1\.3') 'version'
Assert-True ($ctl -match 'status-json\) status_json_command') 'status-json-command'
Assert-True ($ctl -match 'safe-recover\|recover\) safe_recover_command') 'safe-recover-command'
Assert-True ($ctl -match 'recover-hard\) recover_hard_command') 'recover-hard-command'
Assert-True ($ctl -match 'for PROBE_AT in 5 10 15 20 30 45 60 90 120') 'deep-timeout-schedule'
Assert-True ($ctl -match 'F8_CONFIRM_COUNT.*-ge 2') 'persistent-f8-two-samples'
Assert-True (($ctl | Select-String -Pattern 'Slot1UiccDisableHelper disable' -AllMatches).Matches.Count -eq 1) 'single-false-callsite'
Assert-True (($ctl | Select-String -Pattern 'Slot1UiccRecoverHelper recover' -AllMatches).Matches.Count -eq 2) 'true-callsites-safe-and-deep-only'
Assert-True ($ctl -match 'No automatic retry performed') 'no-retry-log'
Assert-True ($ctl -match 'HARD RECOVERY REQUIRED') 'hard-recovery-guidance'
Assert-True ($action -match 'status-only\. ZERO WRITE') 'action-zero-write'
Assert-True ($action -notmatch 'safe-recover|deep-recover|recover-hard|Slot1Uicc') 'action-no-recovery-call'
Assert-True ($auto -match 'if \[ "\$MODE" = boot \] && \[ -e "\$ATTEMPT_MARK" \]') 'marker-read-boot-only'
Assert-True ($auto -match 'manual_run=YES boot_attempt_marker=IGNORED_AND_NOT_CREATED') 'manual-marker-independence'
Assert-True ($customize -match 'if \[ ! -f /data/adb/voxi-wfc-recovery/config\.conf \]') 'config-existence-guard'
Assert-True ($customize -match "AUTO_RECOVER_BOOT=0") 'default-auto-disabled'

$forbidden = @(
    'resetIms', 'disableIms', 'enableIms', 'killall', 'pkill', 'kill -',
    'qcrild', 'modem reset', 'radio reset', 'setprop', 'settings put',
    'settings delete', 'setenforce', 'svc wifi', 'vendor.cnd',
    'qtidataservices', 'org.codeaurora.ims'
)
foreach ($term in $forbidden) {
    Assert-True ($all -notmatch [regex]::Escape($term)) "forbidden-absent-$term"
}
Assert-True ($all -notmatch '(?m)^\s*reboot([[:space:]]|$)') 'forbidden-absent-reboot-command'

$temp = Join-Path $env:TEMP ('voxi-v13-config-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $config = Join-Path $temp 'config.conf'
    Set-Content -LiteralPath $config -Value 'AUTO_RECOVER_BOOT=1'
    if (-not (Test-Path -LiteralPath $config)) { Set-Content -LiteralPath $config -Value 'AUTO_RECOVER_BOOT=0' }
    Assert-True ((Get-Content -LiteralPath $config -Raw).Trim() -eq 'AUTO_RECOVER_BOOT=1') 'config-upgrade-preserves-enabled'
    Remove-Item -LiteralPath $config
    if (-not (Test-Path -LiteralPath $config)) { Set-Content -LiteralPath $config -Value 'AUTO_RECOVER_BOOT=0' }
    Assert-True ((Get-Content -LiteralPath $config -Raw).Trim() -eq 'AUTO_RECOVER_BOOT=0') 'config-first-install-disabled'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
}
