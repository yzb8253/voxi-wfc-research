# Golden Magisk Control-Flow Audit

## Scope and conclusion

- Branch: `wfc-holder-ab-20260926`
- Behavioral reference: `dfd82415073470691295547d39753f6172054748`
- RC1 artifact: `v1.1.0-rc1` (device read-only validation passed)
- RC6 artifact: `v1.1.0-rc6` (writable validation candidate)
- RC6 Action mode: **self-test then recover only on PASS**
- RC4 first writable device run: **STATE_WRITE_COUNT=1 (AIRPLANE_disable), MODEM_WRITE_COUNT=0, SIM_WRITE_COUNT=0**

The v1.0.2 device exit (`EXIT_RC=1`, `EXIT_STAGE=OWNER_INSPECTION`) is **NOT PROVEN** to a specific command. The captured output proves that platform, target, network, and the first owner snapshot succeeded and that the snapshot was native-clean. It does not identify the command whose status escaped. Host POSIX fixtures do not reproduce an exit from a normal false predicate in a conditional context, so this audit does not invent a root cause.

RC1 removes that uncertainty from its reachable path: shell options are explicitly neutralized, each step emits BEGIN/END with a captured result, collectors and printers return explicitly, owner state is classified exactly once per snapshot, public return code 1 is sanitized, and every non-zero self-test outcome has a reason.

## Public execution graph

```text
Magisk Action
  -> action.sh (records shell, set +e/+u/+x)
  -> goldenctl.sh self-test
  -> common.sh (read-only collectors/predicates only)
  -> golden-selftest.sh
  -> pre_recovery_self_test
     ROOT
     MODULE_RUNTIME
     PROBE
     PLATFORM_GATE
     TARGET_GATE
     NETWORK_OBSERVE
     OWNER_INSPECTION
     ENTRY_CAPABILITY
  -> ACTION_EXIT_RC
```

`goldenctl recover`, `goldenctl restore-native`, and direct `golden-runner.sh` execution return 30 before a state mutation in RC1. Recovery source remains packaged for audit and later v1.1.0 enablement, but it is not reachable from RC1 Action.

## Function contract inventory

### Collectors and accessors

| Function | Purpose | Return contract | Phone mutation | Callers / handling |
| --- | --- | --- | --- | --- |
| `run_probe` | Execute read-only WfcStateProbe and capture JSON | 0 success, 40 probe/runtime error | No | `step_probe_gate`, `probe_refresh`; RC captured |
| `load_probe_fields` | Populate target/IMS/CNE fields from captured JSON | Explicit 0 | No | Probe step; RC captured |
| `collect_platform_status` | Read device, Android, build, fingerprint, subsystem and modem | Explicit 0 | No | Platform step, legacy predicate |
| `collect_network_status` | Read Wi-Fi, Connectivity/VPN and route hints | Explicit 0 | No | Network step/status; RC captured |
| `collect_owner_entry_status` | Take one pm-service/X55/lsof/pidfile snapshot | Explicit 0 | No; does not delete stale pidfile | Owner step; RC captured |
| `classify_owner_entry_status` | Classify the existing owner snapshot once | Explicit 0 | No | Owner step after collection |
| `json_object`, `json_field`, `json_root_field` | Pure parse accessors | Text result; absence is empty | No | Probe field loader |
| `get_airplane`, `get_x55_state`, `get_vendor_x55_state`, `get_crash_count`, `get_last_pon`, `get_per_mgr_state`, `get_per_mgr_pid`, `get_per_mgr_exe` | Read-only scalar accessors | Text/empty; callers validate | No | Self-test and dormant recovery |
| `owner_lines`, `owner_count` | Read current ESOC owner table | Text/count; no owner is valid | No | Owner collector and dormant recovery |
| `now_iso`, `now_ms` | Timestamp accessors | Text | No | Logging/timing |

All functions named `collect_*` in the RC1 path terminate with explicit `return 0` on a completed collection. A collection error is returned as 40 by its enclosing step, not as predicate false.

### Printers

| Function | Purpose | Return contract | Mutation |
| --- | --- | --- | --- |
| `log_line` | Console and optional existing log sink | Explicit 0 | Optional filesystem log only; RC1 self-test leaves `LOG_FILE` empty |
| `print_health` | Print already-collected IMS/WFC state | Explicit 0 | No |
| `print_network_status` | Print independent Wi-Fi/VPN observation fields | Explicit 0 | No |
| `print_owner_entry_status` | Print sanitized owner classification fields | Explicit 0 | No |
| `print_write_counters` | Print state/modem/SIM/legacy/filesystem counters | Explicit 0 | No |
| `print_success` | Dormant recovery success presentation | Explicit 0 | No |
| `usage` | CLI help | Explicit 0 | No |

### Predicates

Predicates use only 0 = true and 1 = false. False is normal and must appear only inside `if`/`if !` or another predicate expression.

| Predicate | Truth tested | Mutation | Callers |
| --- | --- | --- | --- |
| `is_wfc_healthy` / compatibility `test_wfc_healthy` | Direct registered/WLAN/VOICE-IWLAN/WFC health | Probe read only | Status and dormant core, inside `if` |
| `is_target_mapping_valid` / compatibility `target_gate` | Exact VOXI slot1/phone1/sub11/carrier28/23415/active/apps | Probe read only | Target step and dormant preflight |
| `is_platform_supported` / compatibility `platform_gate` | Exact cas/Android/build/fingerprint/esoc0/SDX55M | No | Platform step and dormant runner |
| `is_wifi_ready_now` / compatibility `wifi_ready_now` | Wi-Fi setting plus live wlan0 | No | Network step/preflight, inside `if` |
| `owner_has_pid`, `snapshot_owner_has_pid` | ESOC table contains PID | No | Owner predicates/classifier |
| `pm_owns_esoc`, `native_clean` | Native pm-service ownership fingerprint | No | Dormant normalization |
| `holder_process_identity_ok`, `holder_identity_ok` | Exact module holder identity/ownership | No | Dormant recovery safety gates |
| `unknown_owner_present` | Legacy current-table unknown owner check | No | Dormant recovery only; not RC1 owner classification |
| `saved_holder_pid` | Valid readable numeric module pidfile | No | Dormant recovery |
| `assert_clean_core_entry`, `verify_native_fingerprint` | Frozen Golden core entry predicates | No | Dormant recovery |
| `qcrild_primary_line`, `qcrild2_line`, `line_pid` | Legacy process lookup/accessors | No | Dormant normalization |

No predicate is invoked as an unhandled top-level statement in the RC1 Action graph.

### Read-only steps and public commands

| Function | Purpose | Allowed RC | Mutation | Caller handling |
| --- | --- | --- | --- | --- |
| `step_root_gate` | Root identity | 0/40 | No | `run_selftest_step`, captured |
| `step_module_runtime_gate` | Runtime files and probe hash | 0/90 | No | Captured |
| `step_probe_gate` | Probe execution and parse | 0/40 | No | Captured |
| `step_platform_gate_readonly` | Exact platform gate | 0/30/40 | No | Captured |
| `step_target_gate_readonly` | Exact VOXI mapping gate | 0/30 | No | Captured |
| `step_network_observe_readonly` | Wi-Fi prerequisite and advisory VPN observation | 0/30/40 | No | Captured |
| `step_owner_inspection_readonly` | Single snapshot/classification/case | 0/30/40 | No | Captured |
| `run_selftest_step` | Emit step markers and preserve RC | Step RC | No | Pre-recovery self-test |
| `pre_recovery_self_test` | Unified read-only recovery capability gate | 0/30/40/90 | No | `goldenctl self-test` |
| `selftest_command` | Public self-test command | 0/30/40/90 | No | Public RC sanitizer |
| `status_command`, `status_json_command`, `logs_command` | Read-only CLI | 0/20/40 | No phone-state writes | Public RC sanitizer |

Public commands never intentionally return 1. Any unclassified public result is converted to 40 with `INTERNAL_UNCLASSIFIED_RC`.

### RC6 recovery effects retained from Golden

| Function | Purpose | RC contract | Mutation | RC6 reachability |
| --- | --- | --- | --- | --- |
| `set_airplane`, `ensure_wifi_on` | Construct A/P | 0/60 | State | RC6 recovery graph |
| `stop_exact_holder`, `start_module_holder` | Exact holder lifecycle | 0/30/60/70 | Modem ownership | RC6 recovery graph |
| `qcrild2_reacquire`, `restore_native`, `normalize_a0_native` | Golden normalization | 0/30/60/70 | Modem/services | RC6 graph / restore CLI |
| `prepare_a0`, `prepare_p` | Golden A/P steps | 0/10/30/40/60/70 | Airplane/Wi-Fi/native | RC6 recovery graph |
| `core_recovery` | Frozen dfd8241 X55/SIM recovery | 0/20/30/40/60/70 | Modem/SIM | RC6 recovery graph |
| `commit_freeze_success`, `attempt_failure_cleanup`, `runner_exit_guard` | Freeze commit and failure safety | Guarded documented RC | Native/SIM cleanup | RC6 recovery graph |
| `golden_runner_main` | Recovery orchestrator | Sanitized public RC set | State/modem/SIM | Requires self-test token |

RC6 preserves Golden timing and mutation ordering while exposing stage transitions and documented Effect/Step return codes. It remains a candidate until writable device validation completes.

## Owner snapshot contract

One call to `collect_owner_entry_status` captures:

- `vendor.per_mgr` state/PID/executable;
- kernel X55 state;
- one lsof snapshot and owner count;
- module pidfile presence/value, liveness and exact identity;
- stale pidfile status without deletion.

One following call to `classify_owner_entry_status` emits exactly one of:

- `NATIVE_PM_SERVICE`
- `MODULE_GOLDEN_HOLDER`
- `UNKNOWN_OWNER`
- `NO_OWNER`
- `MULTIPLE_OWNERS`

RC1 then uses a single `case`. Only `NATIVE_PM_SERVICE` returns success. No second owner probe or normalization occurs.

## `&&` / `||` audit

- RC1 orchestration: no `predicate && effect` or `predicate || effect`.
- RC1 collectors/printers: no normal false status is exposed as the function API.
- Conditional conjunctions remain inside explicit `if` predicates; these are intentional.
- Pipelines are either parsed as data or have their result explicitly classified by the step.
- RC6 writable orchestration no longer uses `predicate && effect` or `predicate || effect`; helper-level predicate conjunctions remain internal and do not form a public recovery transition.
- `service.sh`, `uninstall.sh`, and `x55-holder.sh` are not reachable from Action. Their effects are separately documented; RC1 Action never invokes them.

## Shell option and shell implementation tests

The entry scripts explicitly capture initial flags, then run `set +e`, `set +u`, and `set +x`. The same owner and full self-test fixtures were run with:

- errexit OFF / nounset OFF
- errexit ON / nounset OFF
- errexit OFF / nounset ON
- errexit ON / nounset ON

Host shells actually tested: Git `sh`, GNU `bash`, and `dash`. BusyBox `ash` and `mksh` were unavailable and are reported `SKIPPED`, not PASS. All tested combinations produced identical results.

## Write-counter contract

- `STATE_WRITE_COUNT`: all airplane/Wi-Fi/init/service/holder/SIM state operations recorded through `record_write`.
- `MODEM_WRITE_COUNT`: per_mgr/qcrild/holder/X55-related subset.
- `SIM_WRITE_COUNT`: `service call phone` subset.
- `PHONE_WRITE_COUNT`: legacy aggregate retained for compatibility.
- `FILESYSTEM_WRITE_COUNT`: separate filesystem bookkeeping counter.

RC1 self-test does not acquire a lock, create a log, remove a stale pidfile, or invoke `record_write`; all five counters finish at zero.

## Golden invariants

The historical source under `experiments/wfc_repeatability_normalization/v262_freeze_run/` is untouched. Dormant module recovery constants remain: A settle 20 s, P settle 20 s, two attempts, post-PON settle 10 s, OFFLINE 20 s, ONLINE 30 s, PON 15 s, transaction 182/slot1, SIM OFF hold 3 s, one normal ON, one guarded emergency ON, unchanged WFC health and freeze/cleanup order.

## RC1 device validation and RC2 recovery audit

RC1 was device-validated on 2026-09-26. The Magisk Action completed ROOT, MODULE_RUNTIME, PROBE, PLATFORM_GATE, TARGET_GATE, NETWORK_OBSERVE, OWNER_INSPECTION, and ENTRY_CAPABILITY with RC=0. It reported the real native `pm-service` sole-owner state and all write counters at zero. The runtime shell executable was Magisk BusyBox `libbusybox.so`.

RC2 freezes that exact `pre_recovery_self_test`. `goldenctl.sh recover` runs it first and exports `PRE_RECOVERY_GATE_PASSED=YES` only after RC=0 plus `READY_FOR_RECOVERY=YES`; the runner rejects direct execution without that token. The writable graph now emits explicit begin/end markers for A0, P, X55 shutdown, holder start, X55 power-up, PON, SIM cycle, and WFC wait. Effect steps return documented 0/10/20/30/40/50/60/70/90 codes; predicates retain private 0/1 semantics.

Host fixtures model recovery paths and holder identity transitions only; they do not emulate X55 or assert device validation.

## Publication status

`v1.1.0-rc6` is a recovery candidate, not a stable release.

## RC3/RC4 freeze and cleanup parity corrections

RC3 retains the read-only RC1 self-test unchanged. In the writable graph, strict WFC health now creates `HEALTHY_CANDIDATE=1`; it does not commit a frozen state. `commit_freeze_success` is the only function that can set `FREEZE_ON_HEALTHY=1`, and it rechecks the created holder PID, exact module-holder cmdline, FD9 ownership, lsof sole ownership, X55 ONLINE, stopped `vendor.per_mgr`, and strict WFC health. A failed commit is `FREEZE_INTEGRITY_FAILED`, returns 70, and leaves the freeze flag clear.

For any core failure, `ATTEMPT_FAILURE_CLEANUP` runs before a retry: guarded emergency SIM ON if necessary, `restore_native`, and strict native-fingerprint verification. Only a clean native baseline permits attempt 2. A cleanup failure stops fail-closed. `goldenctl.sh restore-native` intentionally omits Wi-Fi/VPN and VOXI target gates because its sole purpose is to release an exact verified module holder; it still requires root, module runtime, the exact supported platform, and one owner snapshot/classification.

RC4 keeps `SIM_MAY_BE_OFF=1` when the guarded emergency ON transaction fails. That failure is recorded independently but cannot skip `restore_native` or strict native verification. If native cleanup succeeds while SIM state remains uncertain, the result is `SIM_EMERGENCY_ON_FAILED_NATIVE_RESTORED`, returns 70, and blocks attempt 2. The final exit guard may perform one separately labelled, bounded final emergency attempt; it never clears the SIM flag on an unconfirmed ON.

## RC4 writable-device BusyBox finding and RC5 correction

RC4 passed the frozen RC1 self-test on the real device, entered A0, wrote only `AIRPLANE_disable`, completed A-settle/network checks, and then failed before any modem or SIM write. Magisk BusyBox printed the native lsof row `pm-service  1260 ... /dev/subsys_esoc0` followed by `unexpected '1260'`. The exact BusyBox implementation mechanism is not source-proven, but the failure site is high-confidence: A0's native verification is the first writable path to invoke the legacy `unknown_owner_present` function, whose business variable was named `LINES`.

RC5 removes that special-name collision by replacing the business assignment with `ESOC_UNKNOWN_OWNER_LINES` while retaining predicate semantics (0 = unknown owner exists, 1 = no unknown owner). It adds an exact owner-row regression fixture, a runtime audit for common shell special names, and explicit `NATIVE_FINGERPRINT_CHECK` / `A0_STEP` markers. Golden X55, holder, PON, SIM, freeze, cleanup, timing, and the device-validated RC1 self-test are unchanged.

## RC5 writable-device Golden success and RC6 Wi-Fi automation correction

The RC5 device run passed the frozen RC1 gate and completed the writable Golden path: A0, P, native X55 shutdown, exact module holder start, X55 ONLINE, fresh PON_SUCCESS, one slot1 SIM OFF/ON cycle, strict IMS/WLAN/VOICE-IWLAN/WFC health, and FREEZE_COMMIT. The final result was `WFC_HEALTHY_FREEZE` with `ACTION_EXIT_RC=0`. This validates the Magisk holder/X55/SIM/WFC core path.

However, the run was not fully one-click: after `AIRPLANE_enable`, `ensure_wifi_on` returned without calling `svc wifi enable` because it trusted the stale/nonzero global `wifi_on` setting. The device then disabled Wi-Fi as part of airplane-mode transition, and the user manually re-enabled Wi-Fi. Therefore RC5 proves the Golden core, but not autonomous P-state Wi-Fi restoration.

RC6 leaves the validated Golden core and timing unchanged. In P state it force-reasserts Wi-Fi with `svc wifi enable` immediately after airplane-mode entry and waits up to 15 seconds for the live `wlan0` readiness predicate before starting the existing 20-second P settle. The forced command is write-accounted as `WIFI_ENABLE_AFTER_AIRPLANE`.

**STATUS: GOLDEN CORE VALIDATED WITH MANUAL WI-FI ASSIST / RC6 ONE-CLICK AUTOMATION VALIDATION REQUIRED**
