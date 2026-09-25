# Phase 1.7 real-device read-only collector benchmark

Date: 2026-09-25  
Branch: `wfc-latency-study-20260925`  
Starting commit: `aac8a209d40a9c2b58de33449165e19c0af8e6ca`  
Device: `fd0ff892`  
Final valid run ID: `20260925T114613Z`

## Safety and static audit

- Windows PowerShell version: 5.1.19041.6456.
- PS5.1 parser errors across collector, classifier, and benchmark runner: 0.
- Mutation-token hits across those scripts: 0.
- Offline regression: 17 fixtures, 0 mismatches, 0 unsafe old FAIL/UNKNOWN to new PASS promotions.
- `PHONE_WRITES=0`.
- `RECOVERY_RUNS=0`.
- The lightweight classifier remains disconnected from `repeatability_preflight.ps1` and every mutation path.

The collector records five timed root reads (`meta`, `status`, `processes`, `holder`, and `native`). The classifier retains its fixed 15,000 ms host/device-span fail-closed ceiling.

## Pre-valid-run corrections

Two read-only orchestration/collector defects were found before the final benchmark:

1. The first local runner attempt completed LIGHT_A and FULL but could not obtain paths emitted through PowerShell 5.1's Host stream. No LIGHT_B or valid cycle was produced. Evidence paths are now derived deterministically from the full collector's fixed output convention.
2. An initial three-cycle diagnostic run found that the standard `lsof` header was being treated as an esoc owner record. Every lightweight result correctly failed closed with `parse_error:esoc_owner`. The parser now ignores only the exact `COMMAND PID ...` header; owner validation and classification semantics are unchanged.

Both corrections are host-side profiling fixes. Neither changed recovery state, waits, timeouts, attempts, mutation order, health predicates, or phone state. PS5.1 parsing, mutation audit, and all 17 offline fixtures were rerun after the correction.

## Final benchmark results

Each cycle used `LIGHT_A -> FULL -> LIGHT_B`, followed by a 10-second read-only inter-cycle pause. Durations below are host-observed elapsed times. Device span is the interval between the first and last device timestamps inside the lightweight capture.

| Cycle | Start state | LW_A | FULL | LW_B | LW_A elapsed / device ms | FULL ms | LW_B elapsed / device ms | Commands A/B | Drift | Side effect |
|---:|---|---|---|---|---:|---:|---:|---:|---|---|
| 1 | airplane OFF, Wi-Fi ON, F1, native clean | A0_READY | A0_READY | A0_READY | 3644 / 3156 | 33488 | 3134 / 2912 | 5 / 5 | NO | NONE |
| 2 | airplane OFF, Wi-Fi ON, F1, native clean | A0_READY | A0_READY | A0_READY | 3254 / 3035 | 33303 | 3239 / 3031 | 5 / 5 | NO | NONE |
| 3 | airplane OFF, Wi-Fi ON, F1, native clean | A0_READY | A0_READY | A0_READY | 3216 / 2999 | 33449 | 3211 / 2997 | 5 / 5 | NO | NONE |

All six lightweight captures were complete and produced zero collector/classifier errors. There were no more-conservative results and no unsafe promotions in the final valid run.

## Root-read timings

| Cycle/side | metadata ms | status ms | processes ms | holder ms | native ms | host span ms |
|---|---:|---:|---:|---:|---:|---:|
| 1 A | 228 | 1440 | 222 | 110 | 1129 | 3463 |
| 1 B | 198 | 1467 | 166 | 113 | 1085 | 3109 |
| 2 A | 203 | 1433 | 248 | 121 | 1148 | 3230 |
| 2 B | 195 | 1462 | 256 | 112 | 1107 | 3223 |
| 3 A | 202 | 1438 | 211 | 141 | 1103 | 3204 |
| 3 B | 189 | 1448 | 232 | 104 | 1134 | 3193 |

The slowest lightweight root read was `status`: 1,433-1,467 ms. `native` was second at 1,085-1,148 ms. Maximum device span was 3,156 ms and maximum host span was 3,463 ms, both well below the unchanged 15,000 ms ceiling.

The full snapshot took 33.303-33.488 seconds in this run. Its all-buffer filtered logcat read remained dominant at approximately 27.2 seconds.

## Key-field stability

LIGHT_A and LIGHT_B were identical in every required decision field in all three cycles:

- environment: airplane `0`, Wi-Fi setting `1`;
- target: subId 11, slotId 1, phoneId 1, carrierId 28, MCC/MNC 234/15, ACTIVE, UICC enabled;
- holder: pidfile absent, process absent, no cmdline or fd9;
- native: one owner, pm-service PID 13861, executable `/vendor/bin/pm-service`, per_mgr running, vendor/kernel X55 ONLINE, crash_count 3;
- QCRIL: primary PID 1971 with exact `qcrild` identity; secondary PID 16115 with exact `qcrild -c 2` identity;
- health: IMS raw 0, transport raw -1, VOICE/IWLAN false, WFC false;
- CNE: request ID null, satisfied ID null.

No qcrild/qcrild2/pm-service PID changed. There was no owner transition, X55 epoch/state change, or crash_count change. No cycle was marked `STATE_DRIFT / INCONCLUSIVE`.

## CNE current-table cross-check

For every cycle, the full `dumpsys connectivity` text was truncated before `mNetworkRequestInfoLogs`; only the current request table was searched. It contained no active subId11 IMS request from `com.qualcomm.qti.cne`. The full `wfcctl status-json` and both lightweight captures independently reported request ID null and satisfied ID null.

Result for the tested F1/no-request state: current absence semantics are confirmed in 3/3 cycles. A naturally active non-null request/satisfied-ID state did not occur, so non-null ID equivalence remains unobserved. This is acceptable only for a no-write shadow phase; it is not evidence to authorize production writes from an active-ID classification.

## Verdict

`READY_FOR_SHADOW_INTEGRATION`

The collector is fast enough, parses the current device correctly, matches the legacy classifier in 3/3 stable bracketed cycles, and caused no observed system side effect. The next phase may feed its result into telemetry/shadow comparison only. It must not replace the current preflight, authorize a phone write, or run recovery until active-CNE and additional natural-state coverage are reviewed.

