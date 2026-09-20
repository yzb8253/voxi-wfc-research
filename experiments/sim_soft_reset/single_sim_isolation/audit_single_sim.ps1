$ErrorActionPreference='Stop'
$R=$PSScriptRoot
$J=Get-Content -Raw (Join-Path $R 'src\SingleSimSlot1PowerHelper.java')
$W=Get-Content -Raw (Join-Path $R 'device\single_sim_watchdog.sh')
$C=Get-Content -Raw (Join-Path $R 'device\single_sim_simple_cycle.sh')
function Need($T,$P,$L){if($T-notmatch$P){throw "FAIL $L"};"PASS $L"}
function Reject($T,$P,$L){if($T-match$P){throw "FAIL $L"};"PASS $L"}
function Count($T,$P,$N,$L){$x=([regex]::Matches($T,$P)).Count;if($x-ne$N){throw "FAIL $L expected=$N actual=$x"};"PASS $L"}
foreach($f in Get-ChildItem (Join-Path $R 'device') -Filter '*.sh'){if([IO.File]::ReadAllBytes($f.FullName)-contains 13){throw "FAIL CR byte $($f.Name)"};"PASS LF-only $($f.Name)"}
Need $J 'TARGET_SLOT_ID\s*=\s*1\s*;' 'fixed target slot1'
Need $J 'TARGET_SUB_ID\s*=\s*11\s*;' 'fixed target sub11'
Need $J 'TARGET_CARRIER_ID\s*=\s*28\s*;' 'fixed carrier28'
Need $J 'TARGET_MCC\s*=\s*234\s*;' 'fixed MCC234'
Need $J 'TARGET_MNC\s*=\s*15\s*;' 'fixed MNC15'
Need $J 'PROTECTED_SLOT_ID\s*=\s*0\s*;' 'slot0 protection only'
Need $J 'SIM_STATE_ABSENT\s*=\s*1' 'ABSENT constant fixed'
Need $J '(?s)!s\.protectedActive.*!contains\(slot0, PROTECTED_SUB_ID\).*!contains\(slot0, TARGET_SUB_ID\)' 'slot0 must have no active subscription'
Need $J 's\.slot0Gate = s\.slot0Gate && eq\(s\.protectedSimState, SIM_STATE_ABSENT\)' 'slot0 SIM must be ABSENT'
Need $J 'require\(before\.slot0Gate && \(before\.targetGate \|\| armed\)' 'POWER_UP also requires slot0 ABSENT'
Need $J 'ARM_LIFETIME_MS = 15 \* 60 \* 1000L' 'arm lifetime exceeds watchdog'
Count $J 'method\.invoke\(tm, TARGET_SLOT_ID, state, direct, callback\)' 1 'one fixed SIM power API call site'
Reject $J 'method\.invoke\(tm,\s*PROTECTED_SLOT_ID' 'no slot0 power API path'
Count $C 'helper POWER_DOWN' 1 'simple cycle one POWER_DOWN path'
Count $C 'helper POWER_UP' 1 'simple cycle one normal POWER_UP path'
Count $W 'helper POWER_UP' 1 'watchdog one fallback POWER_UP path'
Need $C 'sleep 10' 'true absent hold 10 seconds'
Need $W 'ROLLBACK_AFTER_DOWN=90' 'rollback deadline 90 seconds'
Reject ($J+$W+$C) 'kill\s|killall|pkill|restart-modem|resetIms|setprop|settings\s+(put|delete)|setenforce|\breboot\b|SSR|setUiccApplicationsEnabled' 'forbidden paths absent'
[scriptblock]::Create((Get-Content -Raw (Join-Path $R 'build_single_sim_helper.ps1')))|Out-Null
'PASS PowerShell build parser'
'SINGLE-SIM STATIC AUDIT: PASS'