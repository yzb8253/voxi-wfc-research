# Phase 1.8 shadow integration real-recovery result

Date: 2026-09-25

Tested instrumentation commit: `8cd82f8`  
Run ID: `20260925T120057Z`  
Result: `ABORTED_SHADOW_ORCHESTRATOR_RUNTIME_BUG`  
Shadow verdict: `NOT_READY`

## Scope and stop point

One real recovery cycle started. Attempt 1 executed the unchanged stable path, including one X55 rebirth and exactly one fixed slot1 SIM OFF/ON cycle. It remained F1 with no CNE request and the existing v2.6.2 cleanup could not transfer esoc ownership from the safety holder to pm-service.

The wrapper then entered its existing bounded retry, disabled airplane mode, and began Attempt 2 A0 preparation. The authoritative full preflight classified the retained state as `FROZEN_RESIDUE`. The lightweight classifier returned `UNKNOWN`, a valid more-conservative result, because vendor X55 was OFFLINE while kernel X55 remained ONLINE.

The shadow adapter incorrectly treated every classifier diagnostic as a parser/runtime error and returned exit 82. The experiment stopped before Attempt 2 normalization, P, core, or SIM write. Cycles 2-5 did not start.

No adaptive recovery, manual cleanup, extra SIM cycle, service restart, or retry was performed after the stop.

## Classifier comparisons

| Observation | Old authoritative | New lightweight | Relation | Unsafe promotion | CNE IDs |
|---|---|---|---|---|---|
| Cycle 1 Attempt 1 A0 | A0_READY | A0_READY | EQUIVALENT | NO | null/null match |
| Cycle 1 Attempt 2 residue | FROZEN_RESIDUE | UNKNOWN | MORE_CONSERVATIVE | NO | null/null match |

Statistics:

- total comparisons: 2;
- equivalent: 1;
- more conservative: 1;
- unsafe promotions: 0;
- null CNE samples: 2;
- non-null CNE samples: 0;
- CNE ID mismatches: 0.

## Recovery result

- real recovery cycles started: 1;
- valid cycles completed: 0;
- Attempt 1 successes: 0;
- Attempt 2 successes: 0;
- deep fallback executions: 0;
- recovery failures before instrumentation stop: Attempt 1 `NO_CNE_REQUEST`;
- SIM OFF count: 1;
- SIM ON count: 1;
- wrapper stop time: 382,389 ms from initial wrapper start;
- successful-recovery P50/P95/max: unavailable because no cycle completed successfully.

## Shadow timing

The two shadow captures cost 3,711 ms and 3,762 ms.

- observed P50: 3,736.5 ms;
- observed P95: approximately 3,759 ms (descriptive only, n=2);
- observed max: 3,762 ms.

These values are telemetry overhead, not successful recovery duration.

## Native and system state at stop

- qcrild primary PID: 1971, unchanged;
- qcrild2 PID: 16115, unchanged;
- holder PID: 32733, sole `/dev/subsys_esoc0` owner;
- pm-service PID: 13670, running but not owner;
- per_mgr: running;
- vendor X55: OFFLINE;
- kernel X55: ONLINE;
- crash_count: 3, unchanged;
- VOXI: slot1/sub11 ACTIVE, UICC enabled;
- IMS/WFC: F1 / unavailable;
- airplane mode: OFF;
- CNE request/satisfied: null/null.

The holder and split X55 telemetry are the preserved, known cleanup-failure residue from the unchanged core path. They were not cleaned up because the Phase 1.8 stop rule forbids post-failure adaptive actions.

## Bugs found

### 1. Semantic UNKNOWN was misclassified as runtime failure

`native:x55_not_consistently_online` describes current state. It is not a JSON/parser/runtime failure. The adapter incorrectly exited on any non-empty classifier error list, even though Phase 1.8 explicitly permits the new classifier to be more conservative.

Static correction: exit 82 is now restricted to incomplete collector execution, collector command errors, or structural `missing/schema/capture` errors. State-derived conservative UNKNOWN remains telemetry and cannot alter the authoritative recovery branch.

### 2. Host runner waited for the holder descendant

Windows PowerShell `Start-Process -Wait` waited on the process tree, including the holder-host process intentionally retained for X55 safety. The direct wrapper had exited, but the driver did not return.

Static correction: the driver now polls only the direct wrapper process's `HasExited` state, then reads its exit code. It does not terminate or manipulate the holder.

Both corrections are unexecuted on a phone. No further Phase 1.8 experiment was run after the required stop.

## State coverage

| State type | Occurrences | Equal | More conservative | Unsafe promotion |
|---|---:|---:|---:|---:|
| A0_READY | 1 | 1 | 0 | 0 |
| FROZEN_RESIDUE | 1 | 0 | 1 | 0 |
| P0_READY | 0 | 0 | 0 | 0 |
| HEALTHY_FREEZE | 0 | 0 | 0 | 0 |
| active/non-null CNE | 0 | 0 | 0 | 0 |

## Conclusion

`SHADOW_VALIDATION_NOT_COMPLETE`

The data collected so far contains no unsafe promotion and correctly demonstrates a more-conservative residue classification. However, the required five completed cycles, active CNE comparison, healthy 30-second recheck, success distribution, and latency distribution were not obtained.

Do not replace ordinary full snapshots with lightweight collection based on this run. A new explicitly approved experiment must begin from a separately reviewed preserved-state plan; the statically corrected runner must not be launched automatically.

