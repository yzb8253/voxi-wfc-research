$ErrorActionPreference='Stop'
$Root=$PSScriptRoot
$W1=Get-Content -Raw (Join-Path $Root 'device\stabilized_watchdog_cycle1.sh')
$W2=Get-Content -Raw (Join-Path $Root 'device\stabilized_watchdog_cycle2.sh')
$O=Get-Content -Raw (Join-Path $Root 'device\stabilized_cycle1_orchestrator.sh')
$C2=Get-Content -Raw (Join-Path $Root 'device\stabilized_cycle2_orchestrator.sh')
$H=Get-Content -Raw (Join-Path $Root 'run_stabilized_absent_second_reinsert.ps1')
foreach ($f in Get-ChildItem (Join-Path $Root 'device') -Filter '*.sh') { if ([IO.File]::ReadAllBytes($f.FullName) -contains 13) { throw "AUDIT FAIL: CR byte in device script $($f.Name)" }; Write-Host "PASS: LF-only $($f.Name)" }
function Need($T,$P,$L){if($T-notmatch$P){throw "AUDIT FAIL: $L"};"PASS: $L"}
function Reject($T,$P,$L){if($T-match$P){throw "AUDIT FAIL: $L"};"PASS: $L"}
function Count($T,$P,$N,$L){$c=([regex]::Matches($T,$P)).Count;if($c-ne$N){throw "AUDIT FAIL: $L expected=$N actual=$c"};"PASS: $L"}
Need $W1 'ROLLBACK_AFTER_DOWN=300' 'cycle1 absolute rollback is 300s'
Need $W2 'ROLLBACK_AFTER_DOWN=90' 'cycle2 absolute rollback is 90s'
Need ($W1+$W2) 'down_epoch=\$\(stat -c %Y "\$DOWN_FILE"\)' 'deadlines derive from power_down marker mtime'
Need $O 'NORMAL_UP_LIMIT=180' 'normal first POWER_UP target is bounded at 180s'
Need $O 'sleep 10\s+log "T2' 'true absent is held exactly 10 seconds before restart'
Need $O 'stable_count.*15' 'continuous 15s stable gate exists'
Need $O 'sleep 20' 'extra 20s stabilization exists'
Need $O 'service_found phone && service_found isub && service_found connectivity' 'core Binder services are gated'
Need $O 'IWlanDataService' 'IWLAN DataService binding is gated'
Need $O 'IWlanNetworkService' 'IWLAN NetworkService binding is gated'
Need $O 'QualifiedNetworksServiceImpl' 'qualified network service binding is gated'
Need $O 'QtiBus.*serverDied|serverDied.*QtiBus' 'QtiBus serverDied is rejected during stability window'
Need $O '(?s)vendor\.qcrild2.*vendor\.qcrild.*vendor\.netmgrd.*vendor\.imsqmidaemon.*vendor\.imsdatadaemon.*vendor\.cnd.*\.qtidataservices.*org\.codeaurora\.ims.*com\.android\.phone.*system_server' 'soft stack order is fixed'
Count $O 'helper POWER_DOWN' 1 'cycle1 has one POWER_DOWN call path'
Count $O 'helper POWER_UP' 1 'cycle1 has one normal POWER_UP call path'
Count $C2 'helper POWER_DOWN' 1 'cycle2 has one POWER_DOWN call path'
Count $C2 'helper POWER_UP' 1 'cycle2 has one normal POWER_UP call path'
Count $W1 'helper POWER_UP' 1 'cycle1 watchdog has one fallback path'
Count $W2 'helper POWER_UP' 1 'cycle2 watchdog has one fallback path'
Need $H '\$script:PowerDownCount -ge 2' 'host enforces two POWER_DOWN maximum'
Need $H '\$script:NormalPowerUpCount -ge 2' 'host enforces two normal POWER_UP maximum'
Need $H 'if \(DirectHealthy \$last\).*return' 'direct recovery stops before second cycle'
Need $H 'if \(-not \(StrictF1 \$r1\.State\)\).*second cycle forbidden' 'second cycle requires restored strict F1'
Need $H 'Assert-Slot0 \$r1\.State' 'slot0 is rechecked before cycle2'
Need $C2 'sleep 10' 'cycle2 absent hold is 10 seconds'
Need $O 'kill -TERM "\$old"' 'device restarts use exact re-resolved PID'
Reject ($W1+$W2+$O+$C2+$H) 'kill\s+-9|killall|pkill|restart-modem|resetIms|setUiccApplicationsEnabled|setprop|settings\s+(put|delete)|setenforce|\breboot\b|ctl\.restart|\b(?:SSR|PDC|MBN|EFS|NV)\b' 'forbidden operations are absent'
Reject $O 'kill -TERM \$[A-Z0-9_]+_OLD' 'no stale pre-recorded PID is signaled'
Need ($W1+$W2) '\[ -f "\$UP_FILE" \].*callback-confirmed' 'watchdogs suppress fallback after callback confirmation'
Need $O 'EXPECTED_HELPER_SHA256=be877b6e9694b4100f2487dc892803de6399c89588f194a1e54d4c3ae3173a31' 'helper hash is pinned device-side'
Need $H "ExpectedHash = 'be877b6e9694b4100f2487dc892803de6399c89588f194a1e54d4c3ae3173a31'" 'helper hash is pinned host-side'
[scriptblock]::Create($H)|Out-Null
'PASS: PowerShell parser accepted host executor'
'STABILIZED ABSENT SECOND REINSERT STATIC AUDIT: PASS'
