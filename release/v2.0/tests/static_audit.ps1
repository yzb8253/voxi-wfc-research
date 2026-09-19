$ErrorActionPreference = 'Stop'
$release = Split-Path -Parent $PSScriptRoot
$module = Join-Path $release 'module'
$ctl = Get-Content -LiteralPath (Join-Path $module 'bin/wfcctl.sh') -Raw
$full = Get-Content -LiteralPath (Join-Path $module 'bin/wfc-full-lifecycle.sh') -Raw
$auto = Get-Content -LiteralPath (Join-Path $module 'bin/wfc-auto-recover.sh') -Raw
$service = Get-Content -LiteralPath (Join-Path $module 'service.sh') -Raw
$action = Get-Content -LiteralPath (Join-Path $module 'action.sh') -Raw
$customize = Get-Content -LiteralPath (Join-Path $module 'customize.sh') -Raw
$prop = Get-Content -LiteralPath (Join-Path $module 'module.prop') -Raw
$scriptText = Get-ChildItem -LiteralPath $module -Recurse -File | Where-Object {$_.Extension -eq '.sh'} | ForEach-Object {Get-Content -LiteralPath $_.FullName -Raw}
$allScripts = $scriptText -join "`n"
function Assert-True([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL: $Name"}; "$Name`: PASS"}
function Count-Matches([string]$Text,[string]$Pattern){([regex]::Matches($Text,$Pattern,[Text.RegularExpressions.RegexOptions]::Multiline)).Count}

Assert-True ($prop -match '(?m)^version=v2\.0$') 'version'
Assert-True ($prop -match '(?m)^versionCode=200$') 'version-code'
Assert-True ($ctl -match 'VERSION=v2\.0') 'ctl-version'
Assert-True ($ctl -match 'full-recover\) require_root; exec "\$FULL_RUNNER" start') 'full-recover-dispatch'
Assert-True ($ctl -match 'full-status\) require_root; exec "\$FULL_RUNNER" status') 'full-status-dispatch'
Assert-True ($ctl -match 'full-cancel\) require_root; exec "\$FULL_RUNNER" cancel') 'full-cancel-dispatch'
Assert-True ((Count-Matches $full 'Slot1UiccDisableHelper disable') -eq 1) 'full-single-false-callsite'
Assert-True ((Count-Matches $full '(?m)^\s*reboot\s*$') -eq 1) 'full-single-reboot-callsite'
Assert-True ((Count-Matches $full 'Slot1UiccRecoverHelper recover') -eq 1) 'full-single-true-callsite'
Assert-True ($full -match 'F8_CONFIRM_COUNT|COUNT=\$\(\(COUNT \+ 1\)\)') 'persistent-f8-counter'
Assert-True ($full -match '\[ "\$COUNT" -ge 2 \]') 'persistent-f8-two-samples'
Assert-True ($full -match 'write_marker WAITING_FOR_REBOOT') 'pending-before-reboot'
Assert-True ($full.IndexOf('write_marker WAITING_FOR_REBOOT') -lt $full.IndexOf("`n  reboot`n")) 'marker-order-before-reboot'
Assert-True ($full -match 'reboot_attempted=%s') 'reboot-attempt-persisted'
Assert-True ($full -match 'MARK_TRUE=1') 'true-attempt-marker'
Assert-True ($full.IndexOf('MARK_TRUE=1') -lt $full.IndexOf('Slot1UiccRecoverHelper recover')) 'true-attempt-persisted-before-call'
Assert-True ($full -match 'for PROBE_AT in 5 10 15 20 30 45 60 90 120') 'wfc-timeout-schedule'
Assert-True ($full -match 'while \[ \$\(\( \$\(date \+%s\) - START \)\) -lt 300 \]') 'network-five-minute-timeout'
Assert-True ($full -match 'network_stability_delay_seconds=30') 'network-stability-delay'
Assert-True ($full -match 'No automatic retry will be attempted') 'no-retry'
Assert-True ($service.IndexOf('full_recover_pending') -lt $service.IndexOf('wfc-auto-recover.sh')) 'boot-resume-precedes-normal-auto'
Assert-True ($service -match 'wfc-full-lifecycle\.sh" resume') 'boot-resume-dispatch'
Assert-True ($action -match 'full-status') 'action-shows-full-status'
Assert-True ($action -match 'status-only\. ZERO WRITE') 'action-zero-write-label'
Assert-True ($action -notmatch 'full-recover|full-cancel|safe-recover|deep-recover|recover-hard|Slot1Uicc') 'action-no-write-entry'
Assert-True ($customize -match 'bin/wfc-full-lifecycle\.sh') 'installer-requires-full-runner'
Assert-True ($customize -match 'set_perm "\$MODPATH/bin/wfc-full-lifecycle\.sh" 0 0 0755') 'runner-executable-permission'
Assert-True ($auto -match 'if \[ "\$MODE" = boot \] && \[ -e "\$ATTEMPT_MARK" \]') 'legacy-boot-loop-protection-retained'
Assert-True ($customize -match 'if \[ ! -f /data/adb/voxi-wfc-recovery/config\.conf \]') 'config-upgrade-preserved'

$forbidden=@('resetIms','disableIms','enableIms','killall','pkill','qcrild','modem reset','radio reset','setprop','settings put','settings delete','setenforce','svc wifi','vendor.cnd','qtidataservices','org.codeaurora.ims')
foreach($term in $forbidden){Assert-True ($allScripts -notmatch [regex]::Escape($term)) "forbidden-absent-$term"}
Assert-True ((Count-Matches $allScripts '(?m)^\s*reboot\s*$') -eq 1) 'package-exactly-one-reboot-callsite'