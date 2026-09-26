# Golden Magisk Parity Audit

## Status

`UNTESTED PORT OF VALIDATED GOLDEN`

Reference: `dfd82415073470691295547d39753f6172054748`. This audit establishes static behavioral correspondence only. It does not claim that the Magisk execution environment has reproduced the historical Golden result.

## Stage mapping

| Windows dfd8241 | Magisk implementation | Static parity | Runtime status |
| --- | --- | --- | --- |
| `X55-WFC-STABLE-v1.ps1` stable wrapper | `bin/golden-runner.sh` | Same 20 s A settle, 20 s P settle, maximum 2 attempts and final safe A0 | NOT YET VALIDATED |
| Platform/target gate | `platform_gate`, `target_gate` in `bin/common.sh` | Exact `cas`, Android 13, build, fingerprint, SDX55M and VOXI slot1/sub11/23415 | NOT YET VALIDATED |
| Existing `wfcctl` probe | bundled `lib/wfc-probe.jar`, `goldenctl.sh status[-json]` | Same WfcStateProbe health fields; no external module dependency | NOT YET VALIDATED |
| User enters airplane OFF | runner accepts ON or OFF, constructs OFF/A0 first | Golden A0→P sequence preserved; UI entry is intentionally broadened before core writes | NOT YET PARITY (runtime) |
| A0 prepare | `prepare_a0` | Airplane OFF, Wi-Fi enable, 20 s settle, target gate and native normalization | NOT YET VALIDATED |
| `repeatability_preflight.ps1` | `prepare_a0`, `verify_native_fingerprint`, `restore_native` | Native-clean or exact module-holder residue only; unknown states fail closed | NOT YET VALIDATED |
| `normalize_a1_native_owner.ps1` | dual-owner path in `restore_native` | Start/restart per_mgr with holder retained, verify `/vendor/bin/pm-service`, then exact holder release | NOT YET VALIDATED |
| `normalize_a1_qcrild2_reacquire.ps1` | `qcrild2_reacquire` | Strict split fingerprint, one exact holder TERM, owner-none/OFFLINE, one qcrild2 restart, primary unchanged | NOT YET VALIDATED |
| Airplane ON / P gate | `prepare_p` | Wi-Fi/VPN, 20 s settle, health check and null CNE request gate | NOT YET VALIDATED |
| Core clean entry | `assert_clean_core_entry` | per_mgr running, pm-service exact owner, X55 ONLINE, no module holder | NOT YET VALIDATED |
| `ctl.stop vendor.per_mgr` | `core_recovery` | Same operation after clean entry gate | NOT YET VALIDATED |
| X55 OFFLINE | `core_recovery` | 20 s maximum, readable non-decreasing crash count | NOT YET VALIDATED |
| PowerShell-launched Android holder | `bin/x55-holder.sh` launched with device `nohup` | Same main shell FD9 and `sleep 60` loop; PC lifetime removed | NOT YET PARITY (runtime persistence) |
| X55 ONLINE | `core_recovery` | 30 s maximum; holder exact owner; crash count stable from OFFLINE | NOT YET VALIDATED |
| New `PON_SUCCESS` | `core_recovery` | Compares last event before/after; 15 s maximum; blocks SIM cycle if absent | NOT YET VALIDATED |
| Post-PON settle | `core_recovery` | Exactly 10 s | STATIC PASS |
| X55-only health check | `wait_wfc_healthy 5` | Golden 3 s then bounded check rhythm | STATIC PASS |
| SIM2 OFF | `service call phone 182 i32 1 i32 0` | Exact validated transaction and fixed slot1; one normal path | STATIC PASS |
| 3 s hold | `core_recovery` | 1 s observation plus 2 s remainder | STATIC PASS |
| SIM2 ON | `service call phone 182 i32 1 i32 1` | One normal path; duplicate normal ON absent | STATIC PASS |
| Emergency SIM ON | `emergency_sim_on` | At most one guarded slot1 ON when `SIM_MAY_BE_OFF=1` | STATIC PASS |
| WFC health | `test_wfc_healthy` | raw 2 registration + raw 2 WLAN + VOICE/IWLAN + direct WFC | STATIC PASS |
| 30 s WFC window | `wait_wfc_healthy 30` | 5 s first probe then 3 s cadence, same sleep-budget semantics | STATIC PASS |
| Success freeze | `FREEZE_ON_HEALTHY=1` and exit guard | No native cleanup; holder/per_mgr frozen at healthy state | STATIC PASS |
| Failure cleanup | `restore_native` | Transactional start/restart per_mgr only; holder retained until verified native takeover | NOT YET VALIDATED |
| Final safe A0 | runner failure tail | Airplane OFF, A0 prepare, bounded exit | NOT YET VALIDATED |

## Intentional implementation differences

1. Host orchestration is replaced by Android root shell. No PC process or ADB lifetime exists.
2. Airplane-ON user entry is accepted by first returning to the same Golden A0 state.
3. Logs contain selected, sanitized state rather than Golden's broad host-side snapshots.
4. The holder is detached with device `nohup`; survival and signal behavior require first-device validation.
5. qcrild2 reacquire is deliberately available only from the next airplane-OFF A0 normalization, not from `restore-native` or core cleanup.

These differences do not introduce a new recovery hypothesis, but they prevent a claim of runtime parity until tested.

## Static conclusion

- Control-flow/write-budget parity: **PASS by inspection and fixtures**.
- Device/runtime parity: **NOT YET PARITY / UNTESTED PORT**.
- Original Golden files: unchanged.
