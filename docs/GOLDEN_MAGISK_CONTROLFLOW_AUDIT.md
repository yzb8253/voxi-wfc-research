# Golden Magisk Control-Flow Audit

## Scope and conclusion

- Branch: `wfc-holder-ab-20260926`
- Behavioral reference: `dfd82415073470691295547d39753f6172054748`
- RC artifact: `v1.1.0-rc1`
- RC Action mode: **read-only self-test only**
- Device writes performed during development: **0**

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

### Dormant recovery effects retained from Golden

| Function | Purpose | RC contract when enabled later | Mutation | Current RC1 reachability |
| --- | --- | --- | --- | --- |
| `set_airplane`, `ensure_wifi_on` | Construct A/P | 0/60 | State | Unreachable |
| `step_owner_preflight` | Future writable owner normalization gate | 0/30/40 | Possible native restore | Unreachable |
| `stop_exact_holder`, `start_module_holder` | Exact holder lifecycle | Internal legacy RC; wrapper must map before v1.1.0 | Modem ownership | Unreachable |
| `qcrild2_reacquire`, `restore_native`, `normalize_a0_native` | Golden normalization | Internal legacy RC; wrapper must map before v1.1.0 | Modem/services | Unreachable |
| `prepare_a0`, `prepare_p` | Golden A/P steps | Internal legacy RC; wrapper must map before v1.1.0 | Airplane/Wi-Fi/native | Unreachable |
| `core_recovery` | Frozen dfd8241 X55/SIM recovery | 0/20/30 | Modem/SIM | Unreachable |
| `emergency_sim_on`, `runner_exit_guard` | Failure safety | Guarded internal RC | SIM/native cleanup | Unreachable |
| `golden_runner_main` | Recovery orchestrator | Sanitized public RC set | State/modem/SIM | Direct runner blocked before invocation |

The dormant recovery implementation is retained to preserve Golden timing and mutation ordering. Its remaining internal short-circuit expressions are recorded, not hidden; RC1 does not claim the writable v1.1.0 runner is device-ready. They must be converted to the same explicit step contract before writable enablement.

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
- Writable Golden source still contains legacy short-circuit expressions inside the dormant runner/preflight. Direct execution is blocked in RC1, and the static reachable-path audit excludes them without pretending they were removed.
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

## Publication status

`v1.1.0-rc1` is not a recovery release. Its only purpose is to validate the Android/Magisk shell and pre-recovery control-flow boundary on the real device.

**STATUS: READ-ONLY DEVICE VALIDATION REQUIRED**
