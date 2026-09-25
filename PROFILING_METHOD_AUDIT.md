# VOXI WFC Phase 1.5 profiling methodology audit

Date: 2026-09-25  
Golden commit: `253ab93a2127806837cb472071846f568c811a34`  
Instrumented commit audited: `e9a50f9f998fbcb5efd4642e886e0bd076f36738`

## Decision

Do not start latency optimization or another phone-write run yet.

Two earlier statements require correction or qualification:

1. The repository does **not** prove that protected subId1 was physically present in slot0 during the golden 6/6 series. The retained project state instead says that the phone had been single-SIM, with slot0 ABSENT, since 2026-09-20. The claim that the 2026-09-25 profiling run had a different physical start state is therefore unsupported and should be withdrawn.
2. The 46-51 second full snapshots were not added by the Stopwatch instrumentation. They already existed in the golden preflight. The timers exposed their cost; they did not create those calls. Even so, the golden path itself is observationally intrusive: read-only work that adds tens of seconds can change an asynchronous telephony outcome.

No slot0 safety contract, recovery wait, timeout, attempt count, mutation order, or health rule is changed by this audit.

## 1. Golden 6/6 slot0 evidence

### Evidence inventory and limits

The golden commit contains committed W0/W1 state summaries and JSON snapshots. It does not contain the raw W0/W1 logs: `RESULT.md` calls them host-only and records only these hashes:

- W0: `53DAA5E3EC49F19683745F8AB62E85DCA77EEF59754B5F89929B51C7B818E47C`
- W1: `258F69D4B2FF1CE03DC2B9314E76BC7D0499EE75BB946EE415E302852C1669AE`

Those files are not present in this checkout. The later four successes are retained only as the aggregate user-observed 6/6 statement and latest-run timeline in `CODEX_WFC_LATENCY_HANDOFF.md`; their wrapper logs, X55 logs, full `dumpsys isub`, and per-run result files are not committed. Consequently, a six-row table containing measured subId1 fields cannot be reconstructed from Git without inventing evidence.

| Golden success | Retained raw evidence | subId1 fields | subId11 fields |
|---|---|---|---|
| W0 | committed snapshot and result; raw log host-only | not captured by snapshot schema | slot1 / phoneId1 / subId11 / carrierId28 / 23415; ACTIVE; UICC enabled |
| W1 | committed snapshot and result; raw log host-only | not captured by snapshot schema | slot1 / phoneId1 / subId11 / carrierId28 / 23415; ACTIVE; UICC enabled |
| success 3 | aggregate handoff only | unavailable | fixed-target gate reported successful, but no per-run raw row retained |
| success 4 | aggregate handoff only | unavailable | fixed-target gate reported successful, but no per-run raw row retained |
| success 5 | aggregate handoff only | unavailable | fixed-target gate reported successful, but no per-run raw row retained |
| success 6 | aggregate handoff/latest timeline only | unavailable | fixed-target gate reported successful, but no per-run raw row retained |

The committed W0/W1 snapshots were taken at 2026-09-24 15:19:49 and 15:45:32. Both record the exact VOXI mapping and subscription above. Their schema has no `protectedSlot0` object, so they cannot establish `subId1.simSlotIndex` either way.

### Continuity evidence

The strongest retained physical-state evidence predates the golden series:

- `autopilot/AUTOPILOT_STATE.md` records on 2026-09-20 that China SIM slot0 was physically/logically absent, `gsm.sim.state=ABSENT,LOADED`, and there was no active protected subscription row.
- The same document repeatedly states that slot0 remained ABSENT through the single-SIM reinsert and full-userspace experiments.
- The 2026-09-24 v2.7 run checkpoint still describes its initial scene as `single-SIM F1`.
- No repository event between that checkpoint and the 2026-09-24/25 golden wrapper series records reinsertion of the China Telecom SIM.

This is continuity evidence, not a substitute for missing per-run isub dumps. It supports the conclusion, with high but not absolute confidence, that golden 6/6 also ran with slot0 ABSENT and subId1 database-only (`simSlotIndex=-1`). It provides no honest basis to claim that subId1 was active in physical slot0 during any of the six successes.

### Answers A-E

**A/B.** The golden archive does not directly measure subId1 in each run. The retained chronology favors B: slot0 was already absent and subId1 was already unmapped. The prior claim that the current profiling run introduced a new physical start state is not supported.

**C.** `Protected slot0 ... gate=FAIL` did not block the golden v2.6.2 core because `Test-WfcHealthy` explicitly ignores the legacy overall SAFE/UNSAFE result and protected-slot0 display gate. The source comment states that airplane mode can make that legacy gate fail while VOXI WFC is healthy.

**D.** In the stable core and normal two-attempt wrapper path, the null protected-slot0 value is health/display telemetry, not the slot1 SIM-power write gate. A distinct protected-slot0 hard gate exists only in `uicc_apps_deep_fallback.ps1`, before the optional subId11 false/true fallback. That fallback correctly refused to run in the profile.

**E.** Yes. Normal SIM power writes are hard-coded as transaction 182 with `slotId=1`: `service call phone 182 i32 1 i32 0/1`. The wrapper independently requires the target status JSON to be subId11, slotId1, phoneId1, carrierId28, MCC/MNC 23415, ACTIVE, and UICC enabled. It does not derive the write target from the protected-slot0 output.

This explains why the core could continue when the legacy protected-slot0 line was null. It does not authorize weakening the separate UICC deep-fallback gate.

## 2. Golden versus instrumented critical-path timing

`git diff 253ab93..e9a50f9` shows that the profiling changes add Stopwatches, `TIMING` output, and portable ADB path resolution. They do not add a snapshot invocation. Golden `repeatability_preflight.ps1` already performed one full snapshot before classification and one after normalization.

The measured run made six full snapshots because preflight ran three times. That call count follows the pre-existing wrapper flow: attempt 1 A normalization, attempt 2 A normalization, and final safe-A restoration.

| Boundary | Golden/latest retained timing | Instrumented timing | Methodological meaning |
|---|---:|---:|---|
| wrapper start -> preflight normalization start | about 27 s | 27.2 s | equivalent A settle and entry work |
| complete preflight normalization | about 153 s | 140.0 / 189.3 / 176.3 s | same heavy preflight family; instrumentation exposed variance |
| qcrild2/native reacquire -> normalized snapshot completion | not separately timed | about 46-51 s snapshot, of which 38-41 s was logcat scan | pre-existing critical-path observation delay |
| preflight PASS -> P prep | included in aggregate only | 5.9 s | no new snapshot between PASS and P |
| P prep -> core start | about 37 s | 35.9 / 35.5 s | equivalent 20 s P settle plus probes/commands |
| attempt 1 core exit -> attempt 2 A prep | not retained | 9.4 s | wrapper health/CNE probes plus airplane transition |
| SIM ON -> health-window result | historical successes about 11, 17, 22.4, or 23 s | failures 61.8-62.0 s | logical 30-second budget excludes probe runtime |

The measured 46-51 second snapshot cost is real, but it is not extra time introduced by the timers. It is extra time imposed by the golden observation design relative to a low-observation recovery path.

## 3. Can read-only profiling perturb the state machine?

Yes. “No new writes” is not equivalent to “behavior unchanged.” A synchronous all-buffer logcat scan, large dumpsys bundle, host/device process creation, USB/ADB traffic, and 40-50 seconds of wall-clock delay can allow or suppress races among qcrild2, QNS, SST, DNC, CNE, IMS, and X55 ownership transitions.

The current evidence supports two narrower statements:

- Stopwatch logging itself is low overhead and did not reorder recovery actions.
- The full snapshots already on the golden critical path are a confounder. Their presence in successful golden runs proves compatibility with some successes, not causal neutrality.

Therefore the failed instrumented run is valid for timing decomposition, but it cannot isolate whether the same state would fail under a low-observation path.

## 4. Low-perturbation profiling design

The next implementation should be a separate, explicit `LOW_PERTURBATION` profiling mode. It must preserve all recovery actions, sleeps, polling semantics, timeouts, attempt count, mutation order, target, and health predicate.

### Critical-path lightweight gate

Retain only fields used by a decision or required to reject an unsafe mutation:

- airplane-mode setting and Wi-Fi setting;
- fixed target: subId11 / slotId1 / phoneId1 / carrierId28 / MCC/MNC 23415;
- target subscription active and UICC enabled;
- holder pidfile, live PID, exact cmdline, and fd9 target;
- `/dev/subsys_esoc0` owner count and identity;
- `vendor.per_mgr` state, PID, and `/vendor/bin/pm-service` executable;
- vendor and kernel X55 state and crash count;
- qcrild and qcrild2 PIDs;
- current qti.cne IMS request ID/satisfaction, from current state rather than history;
- REGISTERED(2), WLAN(2), VOICE/IWLAN available, and WFC available.

Collect these with a small number of bounded commands and compact on-device filtering. Stopwatch/TIMING lines remain.

### Move out of the successful critical path

- all-buffer logcat scan;
- complete dumpsys bundles;
- large phone, subscription, connectivity, IMS, and carrier-config dumps;
- duplicate connectivity collection;
- historical X55/qcril evidence scans;
- tombstone/ANR inventory;
- full evidence JSON/raw directory generation.

Full evidence collection should run only after an `UNKNOWN` fingerprint, safety-gate failure, new failure class, or final failure, when no further recovery mutation will be attempted. A post-run diagnostic capture is permissible only after the recovery result is frozen and must not be counted as recovery latency. A separate diagnostic-only invocation remains the cleanest option.

### Fail-closed equivalence requirement

Before a device trial, feed archived snapshots into both classifiers and require identical decisions for at least A0, frozen residue, P0, W0/W1, and known failure fingerprints. Any lightweight field that is missing, unparsable, contradictory, or stale must classify `UNKNOWN` and trigger failure-only full capture; it must never be treated as PASS.

This audit intentionally does not implement the mode. Replacing the full snapshot would materially change critical-path wall time, so it requires a reviewed profiling-only patch and offline classifier-equivalence test before a phone run.

## 5. Nominal 30 seconds versus real 62 seconds

Current `Wait-WfcHealthy -MaxSeconds 30` uses a logical sleep accumulator. Each roughly 2.8-second health probe is outside that accumulator. The observed failed windows therefore lasted about 61.8-62.0 seconds.

Classification: `TIMEOUT_ACCOUNTING_DEFECT / CONTRACT_AMBIGUITY`.

The current behavioral contract is “up to 30 seconds of scheduled sleep budget, plus the runtime of every health probe, with immediate success when any probe passes.” It is not a 30-second wall-clock deadline. Converting it to one would shorten a historically validated window and is a separate behavior experiment.

## 6. `core exit=30` to wrapper success contract

The core returns 30 only when `$CleanupOk` is false. On the intended freeze-on-health success branch, cleanup is deliberately skipped, `$CleanupOk=true`, and the core returns 0. On a failed recovery, cleanup tries to restore native pm-service ownership; if takeover or verification fails, it intentionally keeps the temporary holder as a safety action and returns 30.

The wrapper ignores the core exit code for its immediate success decision. After the core exits, it runs a new independent four-field WFC probe. If WFC becomes healthy after the core's last failed probe but before this wrapper probe, it can log `ATTEMPT SUCCESS coreExit=30` and freeze.

No retained golden raw log proves that this race occurred in one of the six successes. The source makes it possible; the available profile produced exit 30 followed by unhealthy wrapper probes. This is a code contract, not a proven golden event sequence.

Independent strong WFC health is sufficient to say “WFC is currently healthy.” It is not, by itself, sufficient to say “native state is a verified supported freeze state.” Exit 30 may mean the holder was intentionally retained because native cleanup failed.

The explicit contract should be:

- `coreExit=0` plus strong wrapper health: success, subject to the normal frozen-state invariant.
- `coreExit=30` plus strong wrapper health: **late-health / cleanup-failed exceptional state**, not ordinary success, unless a read-only native invariant check also proves exact holder identity, sole expected ownership, X55 ONLINE, stable crash count, active/enabled target, and no unknown owner.
- `coreExit=30` plus unhealthy wrapper probe: failure; the bounded wrapper may normalize on the next configured attempt.

This audit documents the gap only. It does not change wrapper classification.

## 7. Required next step

1. Preserve current recovery code and slot0 contracts.
2. Implement low-perturbation collection as a profiling-only mode.
3. Prove offline decision equivalence against archived A/P/W/residue/failure snapshots.
4. Perform PowerShell 5.1 parser and static no-ADB checks.
5. Review the patch before authorizing any phone-write run.
6. Treat timeout accounting and exit-30 classification as separate future experiments, not opportunistic fixes.

Phone writes performed for this audit: **0**.  
ADB used for this audit: **NO**.
