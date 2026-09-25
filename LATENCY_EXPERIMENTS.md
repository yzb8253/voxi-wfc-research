# VOXI WFC latency experiments

## 2026-09-25 — instrumentation only

Status: **PASS**

- Added machine-readable `TIMING name=<stage> ms=<value>` records.
- Covered wrapper, snapshots, preflight classification, qcrild2 reacquire, and v2.6.2 subphases.
- Windows PowerShell 5.1 parser errors: 0.
- Frozen constants and control order matched golden commit `253ab93a2127806837cb472071846f568c811a34`.
- Phone writes during development: 0.

## 2026-09-25 — Computer-B ADB path portability

Status: **PASS**

- Replaced computer A's absolute ADB path with repository-relative platform-tools resolution.
- On computer A it resolves to the original location; on computer B it resolves to `C:\Users\TT\Desktop\platform-tools\adb.exe`.
- No Android command, recovery transition, gate, timeout, or target changed.

## 2026-09-25 — frozen-holder baseline profile

Status: **PROFILE_CAPTURED / RECOVERY_NOT_HEALTHY / FURTHER_RUNS_BLOCKED**

Entry:

- airplane OFF, Wi-Fi ON;
- VOXI slot1/sub11 ACTIVE + UICC enabled + F1;
- frozen holder PID 9993 sole owner;
- vendor.per_mgr stopped;
- X55 ONLINE, crash_count 1;
- qcrild PID 1971, qcrild2 PID 4234.

Execution:

- unchanged stable wrapper;
- attempt 1: qcrild2 4234 -> 28713, one SIM OFF/ON, `NO_CNE_REQUEST`;
- attempt 2: qcrild2 28713 -> 23036, one SIM OFF/ON, `NO_CNE_REQUEST`;
- final A0 normalization: qcrild2 23036 -> 16115;
- deep UICC fallback gate rejected protected subId1 because it was absent from slot0;
- UICC false/true writes: 0.

Final:

- airplane OFF, Wi-Fi ON;
- pm-service PID 13861 sole owner of `/dev/subsys_esoc0`;
- no holder or holder pid file;
- X55 ONLINE, crash_count 3;
- qcrild unchanged at PID 1971;
- qcrild2 PID 16115;
- VOXI slot1/sub11 ACTIVE + UICC enabled + F1;
- protected subId1 remains database-only with `simSlotIndex=-1`.

Classification:

- This does not falsify the historical 6/6 golden stability record. The earlier explanation that the physical start-state matrix differed is withdrawn: retained chronology indicates the golden period was already single-SIM/slot0-absent, while per-run golden isub dumps are unavailable.
- It does confirm the latency decomposition and a real nominal-time versus wall-time accounting defect.
- No optimization candidate has been applied.

## Candidate queue

1. **Lightweight preflight gate** — retain every decision input, move full dumps/logcat to unexpected/failure capture. Highest value; profiling-method change requiring offline classifier equivalence, not implemented.
2. **Remove duplicate diagnostics inside one snapshot** — `dumpsys connectivity` is collected in both network and IMS bundles. Medium value, low risk, not implemented.
3. **Probe accounting** — use a wall-clock deadline while preserving the same 30-second policy and early-exit semantics. Requires its own design/review; not implemented.
4. **A/P settle study** — deferred until diagnostic overhead is reduced and successful A/B baselines exist.

No candidate may be implemented from this partial run alone.

## 2026-09-25 — Phase 1.6 offline lightweight classifier

Status: **OFFLINE PASS / NOT INTEGRATED**

- Added a five-root-read lightweight collector and a separate pure JSON classifier.
- Recovery scripts, call sites, waits, timeouts, attempts, mutation order, and health predicate are unchanged.
- Seventeen archived/derived fixtures produced 14 exact-equivalent and 3 more-conservative results.
- Unsafe old FAIL/UNKNOWN -> new PASS transitions: 0.
- Windows PowerShell 5.1 parser and offline runtime suite pass.
- Theoretical target is 4-10 seconds versus the measured 46-51 second full snapshot; no device benchmark has occurred.
- Next permitted experiment is read-only collector benchmarking only, after review.

## 2026-09-25 — Phase 1.7 real-device read-only benchmark

Status: **READY_FOR_SHADOW_INTEGRATION / NOT CONNECTED TO WRITES**

- Final valid run: three `LIGHT_A -> FULL -> LIGHT_B` cycles with 10-second inter-cycle pauses.
- Every cycle classified `A0_READY / A0_READY / A0_READY`; no state drift and no unsafe promotion occurred.
- Lightweight host spans were 3.109-3.463 seconds; device spans were 2.912-3.156 seconds, below the unchanged 15-second ceiling.
- Full snapshots took 33.303-33.488 seconds; their approximately 27.2-second logcat scan remained dominant.
- Slowest lightweight root read was `status` at 1.433-1.467 seconds.
- qcrild/qcrild2/pm-service PIDs, native owner, X55 states, crash_count, environment, target mapping, and health did not change across any A/B bracket.
- Current CNE absence semantics were confirmed 3/3 against the connectivity current table. Active non-null ID semantics were not naturally exercised.
- `PHONE_WRITES=0`; `RECOVERY_RUNS=0`.
- Detailed report: `LIGHTWEIGHT_DEVICE_BENCHMARK.md`.

No lightweight result is connected to preflight or a mutation path. The next allowed step is no-write shadow telemetry only.
