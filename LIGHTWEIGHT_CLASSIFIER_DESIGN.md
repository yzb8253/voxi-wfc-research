# LOW_PERTURBATION collector and classifier design

Phase: 1.6 offline implementation and classifier equivalence

Status: implemented but **not connected to the recovery wrapper**

Phone writes: 0

ADB used during implementation/testing: NO

## 1. Boundary and non-goals

The implementation is isolated under `experiments/wfc_repeatability_normalization/lightweight_profiling/`:

- `capture_lightweight_state.ps1` collects a compact current-state JSON for a future read-only benchmark.
- `classify_lightweight_state.ps1` is a pure JSON-to-classification boundary and can run entirely offline.
- `build_offline_fixtures.ps1` derives sanitized fixtures from committed archived snapshots.
- `test_classifier_equivalence.ps1` executes the fail-closed regression suite.

No call site in `repeatability_preflight.ps1`, the stable wrapper, v2.6.2 core, normalization scripts, or deep fallback was changed. No wait, timeout, attempt count, mutation, ordering, health rule, or golden branch changed.

## 2. Full-snapshot fields that are actual gate inputs

The old preflight directly consumed:

- target mapping and identity: subId11, slot1, phoneId1, carrierId28, MCC/MNC 23415, mapping gate;
- subscription active and UICC applications enabled;
- airplane mode;
- holder process PID and whether it owned `/dev/subsys_esoc0`;
- pm-service PID and whether it owned `/dev/subsys_esoc0`;
- `vendor.per_mgr` state;
- combined X55-online indication and crash count;
- four-field WFC `goldenStrong` result;
- current qti.cne request only as post-normalization output, not as A0/P0 native classification.

The lightweight classifier preserves all of these and deliberately strengthens identity validation for the holder, pm-service, qcrild, qcrild2, owner list, timestamps, and health-field consistency.

The ordinary slot1 power target remains independently fixed by the recovery core. No protected-slot0 rule is changed. `uicc_apps_deep_fallback.ps1` remains untouched and retains its separate protected-slot0 fail-closed gate.

## 3. Diagnostic-only fields removed from the normal critical path

The lightweight collector does not collect:

- all-buffer logcat or historical qcril/X55 evidence;
- full `dumpsys phone`;
- full `dumpsys telephony.registry`;
- full `dumpsys isub`;
- full carrier-config dump;
- full IMS dump bundle;
- complete IP address and route inventory;
- complete or duplicate connectivity dumps;
- XFRM and UDP socket tables;
- module temp-directory inventory;
- tombstone, ANR, crash-buffer, or other forensic bundles.

Those remain available through `capture_snapshot.ps1` after UNKNOWN, a safety-gate failure, a new failure class, or a terminal failure. They are evidence, not permission to perform the next write.

## 4. Lightweight schema

Schema name: `voxi-wfc-lightweight-state-v1`.

| Object | Required fields |
|---|---|
| `capture` | observation epoch UUID, host start/end UTC, device start/end milliseconds, span, command count, complete flag, errors |
| `environment` | airplane mode, Wi-Fi setting |
| `target` | fixed identity/mapping, ACTIVE, UICC enabled |
| `holder` | pidfile presence/content, live-process flag, PID, exact cmdline, fd9 target |
| `native` | exact subsys owner count/list, per_mgr state, pm-service PID/PPID/cmdline/exe/init PID, vendor/kernel X55, crash count |
| `qcril` | primary and slot2 PID/PPID/name/cmdline |
| `cne` | current qti.cne request ID, current satisfied ID, current-evidence-valid flag |
| `health` | IMS registration raw, transport raw, VOICE/IWLAN, WFC availability, reported goldenStrong |

The classifier recomputes strong health rather than trusting `goldenStrong` alone.

## 5. Field sources and future command budget

The collector uses one host `adb devices` identity check and five bounded root reads:

| Root read | Source |
|---|---|
| metadata | device timestamp, `settings get global airplane_mode_on`, `wifi_on` |
| status | existing `wfcctl.sh status-json`, including fixed target, ACTIVE/UICC, current CNE IDs and direct health |
| processes | on-device filtered `ps` for qcrild, qcrild2 and pm-service |
| holder | fixed pidfile, `/proc/PID`, exact `ps` row and `/proc/PID/fd/9` |
| native | per_mgr/init PID, `/proc/PID/exe`, vendor/kernel X55, crash count, `lsof /dev/subsys_esoc0`, ending device timestamp |

This is intentionally not one giant shell payload. Five root reads keep quoting and parser boundaries reviewable while eliminating the expensive diagnostic commands.

## 6. State classifier truth table

Every row first requires a complete, current, internally consistent capture; exact target; ACTIVE/UICC enabled; valid qcrild/qcrild2 identity; current CNE evidence; and known native owners.

| Health | Airplane | Native fingerprint | Result | Write eligible |
|---|---:|---|---|---:|
| strong | either | exact native-clean or exact frozen holder | `HEALTHY_FREEZE` | no |
| not strong | 0 | pm-service sole owner, no live holder, both X55 ONLINE | `A0_READY` | yes |
| not strong | 1 | pm-service sole owner, no live holder, both X55 ONLINE | `P0_READY` | yes |
| not strong | 0 | exact holder sole owner, pm-service not owner, both X55 ONLINE | `FROZEN_RESIDUE` | yes, only for the existing normalization path |
| any other combination | any | any | `UNKNOWN` | no |

`UNKNOWN` is the implemented representation of UNKNOWN/UNSAFE. No new write-permitting fingerprint was invented.

## 7. UNKNOWN fail-closed rules

The result is UNKNOWN if any of the following occurs:

- missing, null where forbidden, malformed, or contradictory field;
- capture incomplete, collector error, reversed timestamps, or capture span over 15 seconds;
- target mismatch or incomplete mapping;
- inactive target or disabled UICC applications;
- qcrild/qcrild2 missing, duplicated, wrong parent, name, or exact command line;
- live holder without matching pidfile/PID/cmdline/fd9;
- dead holder carrying live-process identity fields;
- pm-service PID mismatch between init and `ps`, wrong parent/name/cmdline/executable;
- owner count mismatch, malformed owner, or unknown owner;
- vendor/kernel X55 not both ONLINE;
- missing/malformed crash count;
- non-current or contradictory CNE evidence;
- raw health types invalid or `goldenStrong` contradicts the four direct fields.

A dead numeric pidfile with no process and no ownership remains a recognized stale residue and does not turn native-clean A0 into UNKNOWN. This matches the archived A0 condition.

## 8. Offline fixture equivalence

Seventeen fixtures were generated from committed A0/P0/A1/W0/W1 and instrumented preflight snapshots, with explicit mutations for negative cases.

Result:

- exact equivalent: 14;
- deliberately more conservative: 3;
- old FAIL/UNKNOWN -> new PASS: 0;
- mismatches against expected result: 0.

The three conservative cases are:

1. an additional unknown esoc owner: old classifier only looked for the expected PID and returned A0; new rejects every unknown owner;
2. wrong qcrild2 command line: old classifier ignored QCRIL identity and returned A0; new returns UNKNOWN;
3. string-valued crash count: old null-only check accepted it; new requires a non-negative integer and returns UNKNOWN.

Detailed results are in `classifier_equivalence_results.csv`.

## 9. Timing and stale-state contract

Every snapshot receives an observation-epoch UUID plus host and device start/end times. Captures over 15 seconds fail closed. This makes excessive collector duration visible; it does not claim atomicity across five reads.

The classifier has no cache. A classified object is valid only in the observation epoch in which it was captured. Any state-changing command invalidates all earlier lightweight states. A future integration must capture again after every mutation and must never reuse a pre-mutation classification.

Based on the measured approximately 2.8-second `wfcctl` probe and removal of the 38-41 second logcat scan and large dump bundle, the theoretical target is approximately 4-10 seconds, with a hard classifier ceiling of 15 seconds. This is an estimate, not a device benchmark.

## 10. Remaining risks

- Android `date +%s%3N`, `lsof`, `ps`, and init PID formatting must be confirmed on the real ROM.
- Five sequential reads can straddle a process transition even when total span is short. Identity contradictions should fail closed, but a coherent-looking race remains possible.
- `wfcctl status-json` current-CNE semantics are relied upon and need a read-only device comparison with the current connectivity table.
- The 15-second ceiling has not been measured on the device and may be too strict; it must not be silently raised during a benchmark.
- Fixture conversion supplies fields absent from the old schema using archived process/owner evidence. It tests decision conservatism, not the future collector's Android parsing.
- Full evidence fallback has not been wired because no production/preflight integration is authorized in Phase 1.6.

## 11. Recommendation

The next safe step is one read-only collector benchmark from a stable phone scene. It should run the lightweight collector and full collector as separate observations, perform no recovery action, compare classifications and duration, and stop. Do not integrate lightweight results into a phone-write path until Android parsing, current-CNE semantics, and classification equivalence are confirmed on-device.
