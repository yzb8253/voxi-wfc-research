# Golden Magisk Parity Audit

## Status

`WRITABLE DEVICE VALIDATION REQUIRED`

Reference: `dfd82415073470691295547d39753f6172054748`. This audit establishes static behavioral correspondence only. It does not claim that the Magisk execution environment has reproduced the historical Golden result.

## Stage mapping

| Windows dfd8241 | Magisk implementation | Static parity | Runtime status |
| --- | --- | --- | --- |
| `X55-WFC-STABLE-v1.ps1` stable wrapper | `bin/golden-runner.sh` | Same 20 s A settle, 20 s P settle, maximum 2 attempts and final safe A0 | NOT YET VALIDATED |
| Platform/target gate | `platform_gate`, `target_gate` in `bin/common.sh` | Exact `cas`, Android 13, build, fingerprint, SDX55M and VOXI slot1/sub11/23415 | NOT YET VALIDATED |
| Existing `wfcctl` probe | bundled `lib/wfc-probe.jar`, `goldenctl.sh status[-json]` | Same WfcStateProbe health fields; no external module dependency | NOT YET VALIDATED |
| User enters airplane OFF | runner accepts ON or OFF, constructs OFF/A0 first | Golden A0→P sequence preserved; UI entry is intentionally broadened before core writes | NOT YET PARITY (runtime) |
| Network preflight | Wi-Fi hard prerequisite plus advisory VPN detection | v1.0.1 removes v1.0.0-only `tun0`/ordinary default-route hard gates that did not exist in dfd8241 | STATIC PASS; runtime re-test pending |
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
| Success freeze | `HEALTHY_CANDIDATE` then `FREEZE_COMMIT` | Freeze is committed only after exact holder ownership, X55 ONLINE, stopped per_mgr, and final strict WFC recheck | STATIC PASS |
| Per-attempt failure cleanup | `ATTEMPT_FAILURE_CLEANUP` | Guarded emergency SIM ON, transactional native restore, then strict native-baseline verification before retry | NOT YET VALIDATED |
| Final safe A0 | runner failure tail | Airplane OFF, A0 prepare, bounded exit | NOT YET VALIDATED |

## Intentional implementation differences

1. Host orchestration is replaced by Android root shell. No PC process or ADB lifetime exists.
2. Airplane-ON user entry is accepted by first returning to the same Golden A0 state.
3. Logs contain selected, sanitized state rather than Golden's broad host-side snapshots.
4. The holder is detached with device `nohup`; survival and signal behavior require first-device validation.
5. qcrild2 reacquire is deliberately available only from the next airplane-OFF A0 normalization, not from `restore-native` or core cleanup.
6. v1.0.1 keeps Wi-Fi as a prerequisite with a bounded 20-second readiness wait. VPN detection is advisory: Android policy routing/fwmark means an active VPN need not expose `tun0` or an ordinary `default ... dev tun0` route. The module cannot verify the public exit country; the user remains responsible for selecting a UK full-tunnel endpoint.

## v1.0.0 first-device network-gate finding

The first v1.0.0 Action run stopped before any phone write with:

```text
NETWORK_GATE=FAIL Wi-Fi/tun0/VPN
PHONE_WRITE_COUNT=0
```

The device had connected Wi-Fi, an active FlClash UK global VPN and working Internet access. The failure was a false negative caused by a port-only gate requiring `tun0`, an ordinary default route through `tun0`, and tightly coupled Wi-Fi/VPN text matches. The frozen dfd8241 wrapper did not impose those requirements; it primarily ensured Wi-Fi was enabled.

v1.0.1 corrects only this migration deviation. It reports independent Wi-Fi/VPN diagnostic fields, blocks only when Wi-Fi is not ready after the bounded wait, and reports an unconfirmed VPN as `VPN=UNVERIFIED` with a warning rather than rejecting recovery. No public-IP lookup is performed.

## v1.0.1 first-device owner-preflight finding

The next device run proved the v1.0.1 network correction (`WIFI=READY`, `VPN=DETECTED`, `NETWORK_PREFLIGHT=PASS`) but exited before A0 with `PHONE_WRITE_COUNT=0`. The old runner placed an unlabelled holder/owner probe between network preflight and the attempt loop and used a bare negative-probe `&&` list. Consequently the captured Action output could not distinguish a shell-status/control-flow exit from the expected fail-closed unknown-owner branch.

v1.0.2 preserved the recovery state machine and added owner classification plus stage/reason diagnostics. Its real-device run proved a clean native entry snapshot (`vendor.per_mgr=running`, `/vendor/bin/pm-service`, X55 ONLINE, one native owner, no module holder), but then exited with `EXIT_RC=1`, `EXIT_STAGE=OWNER_INSPECTION`, and `EXIT_REASON=NOT_SET`. The exact leaking command is not proven from the available evidence.

## Port test history

| Version | Real-device result | Interpretation |
| --- | --- | --- |
| v1.0.0 | `NETWORK_GATE=FAIL`, zero phone writes | Port-only strict tun0/default-route gate caused a false negative |
| v1.0.1 | Network observation PASS, stopped before A0, zero phone writes | Network migration deviation fixed; owner/control-flow boundary remained opaque |
| v1.0.2 | Native owner snapshot proved clean, then public RC=1 leaked during OWNER_INSPECTION | Shell/control-flow defect confirmed; exact command/root cause **NOT PROVEN** |
| v1.1.0-rc1 | **DEVICE READ-ONLY VALIDATION PASS** | `READY_FOR_RECOVERY=YES`, `SELFTEST_RESULT=PASS`, `ACTION_EXIT_RC=0`; all write counters zero under Magisk BusyBox `libbusybox.so` |
| v1.1.0-rc2 | Writable candidate; device validation required | Calls the same frozen self-test before Golden A0 → P → X55 → SIM2 flow |
| v1.1.0-rc3 | Writable candidate; device validation required | Restores dfd8241 per-attempt cleanup boundary and commits freeze only after final holder/X55/health verification |
| v1.1.0-rc4 | Writable candidate; device validation required | Emergency SIM ON failure still continues native cleanup; uncertain SIM state blocks retry fail-closed |

v1.1.0-rc1 adds the shared `pre_recovery_self_test`, explicit step BEGIN/END markers, shell option reporting, one-snapshot/one-classification owner handling, separated write counters, and public RC sanitization. It does not execute A0, P, X55, holder, qcrild, or SIM recovery. See [GOLDEN_MAGISK_CONTROLFLOW_AUDIT.md](GOLDEN_MAGISK_CONTROLFLOW_AUDIT.md).

## RC2 → RC4 safety parity corrections

RC2 deferred native cleanup after a core failure to the retry/A0 path or the process exit guard. That diverged from the dfd8241 core `finally` boundary: emergency SIM ON (when needed) and transactional native cleanup occur before the bounded stable-wrapper retry receives the failure.

RC3 restores that order with `ATTEMPT_FAILURE_CLEANUP`: guarded SIM ON, `restore_native`, and strict native-baseline verification all complete before attempt 2 is eligible. A cleanup failure blocks retry fail-closed.

RC2 also set `FREEZE_ON_HEALTHY=1` immediately after strict WFC health, before holder persistence was committed. RC3 separates `HEALTHY_CANDIDATE` from `FREEZE_ON_HEALTHY`; only `FREEZE_COMMIT` may set the freeze flag, after exact holder PID/fd9/cmdline/lsof sole-owner, X55 ONLINE, stopped `vendor.per_mgr`, and a final strict WFC probe. A failed freeze commit runs native cleanup and is never reported as a Golden freeze success.

RC4 corrects the remaining failure-cleanup parity edge: an emergency slot1 SIM ON failure no longer returns before `restore_native`. The runner retains `SIM_MAY_BE_OFF=1` unless the ON transaction succeeds, restores and verifies the native baseline regardless of the SIM guard result, then returns 70 without retry when the SIM state is uncertain.

These differences do not introduce a new recovery hypothesis, but they prevent a claim of runtime parity until tested.

## Static conclusion

- Control-flow/write-budget parity: **PASS by inspection and fixtures**.
- Device/runtime parity: **NOT YET PARITY / WRITABLE RC4 VALIDATION REQUIRED**.
- Original Golden files: unchanged.
