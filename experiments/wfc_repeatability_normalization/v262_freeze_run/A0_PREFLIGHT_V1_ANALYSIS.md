# A0 preflight v1 analysis

Date: 2026-09-25  
Baseline: `4270183152e599ef25d8a4e660d0ec44ffc44fd4`  
Scope: A-state preflight only

## Measured current budget

The latest successful v0 run spent 167,299 ms in A preflight and 280,497 ms
end to end.

| Component | Value | Status |
|---|---:|---|
| A lightweight capture | 3.2–3.6 s collector; about 9 s including the frozen 5 s settle and orchestration | MEASURED |
| First full snapshot | 34.610 s | MEASURED |
| Historical qcril/X55 scan inside first full | 27.976 s | MEASURED |
| Quick native-owner probe | 18.301 s | MEASURED |
| Existing qcrild2 reacquire total | 69.688 s | MEASURED |
| Holder TERM to holder process gone | 57.974 s | MEASURED |
| qcrild2 restart + native reacquire remainder | about 11.714 s (`69.688 - 57.974`) | DERIVED |
| Second normalized full snapshot | 35.089 s | MEASURED |
| Historical qcril/X55 scan inside second full | 28.640 s | MEASURED |
| A total | 167.299 s (wrapper phase reported 167.995 s) | MEASURED |

`snapshot_qcril_x55_evidence` is not read by `TargetGate`, `NativeClean`,
`FrozenResidue`, or any write authorization in `repeatability_preflight.ps1`.
It is diagnostic history. v1 leaves its implementation intact in the old full
fallback but does not execute it on the exact normal split path.

## Exact fast classification

`FROZEN_SPLIT_RESIDUE` requires all of the following in one bounded current
observation epoch:

- airplane mode OFF;
- exact VOXI slot 1 / phone 1 / sub 11 / carrier 28 / 23415 mapping;
- subscription active and UICC applications enabled;
- exact primary `qcrild` and secondary `qcrild -c 2` identities, PID > 1,
  PPID 1;
- numeric holder pidfile, live matching PID, expected holder command and FD9
  pointing to `/dev/subsys_esoc0`;
- exactly one esoc owner and it is that holder;
- `vendor.per_mgr=running` and exact live `/vendor/bin/pm-service`, but
  pm-service is not an owner;
- vendor X55 `OFFLINE`, kernel X55 `ONLINE`, numeric crash count;
- complete current CNE evidence with null request and null satisfied IDs;
- no missing, parse, schema, identity, unknown-owner, or contradictory field.

It deliberately reports `writeEligible=false`. The v1 orchestrator recognizes
the named class and permits exactly one existing audited action:
`normalize_a1_qcrild2_reacquire.ps1`. It cannot authorize SIM power, the core,
UICC fallback, or any other write. Any mismatch remains `UNKNOWN` and uses the
old full fail-closed path.

After a successful reacquire, v1 captures one lightweight state. Exact
`A0_READY` continues. Anything else invokes the old full classifier without
`-ApplyNormalization`, so the fallback is read-only and cannot repeat the
normalization.

## Holder lifecycle/epoch audit

The holder implementation is:

```sh
echo $$ >/data/local/tmp/x55_holder.pid
exec 9</dev/subsys_esoc0
while true; do sleep 60; done
```

The FD is opened by the outer shell before it launches each foreground
`sleep 60`. Historical authorized run 007 captured holder PID 27125 still
alive after its one exact TERM, with a live `sleep 60` child, pidfile present,
and holder/pm-service ownership still present. That is direct evidence that
the outer shell may not complete termination until its current foreground
sleep returns. It also creates a credible inherited-FD descendant risk, but
the old evidence did not record each descendant FD, so descendant FD9
ownership remains `UNKNOWN` rather than asserted.

### Evidence reorganized by lifecycle epoch

The historical formats did not capture `boot_id`, uptime, holder creation
ordinal, per-second descendants, or all transition timestamps. Missing cells
are therefore `UNKNOWN`; rows are not forced into one statistical distribution.

| Lifecycle class | Source/run | boot_id / uptime | Recovery ordinal in boot | Holder / tree | qcrild2 epoch | pm-service | crash | TERM→main gone | descendants gone | owner NONE | vendor/kernel OFFLINE | Interpretation |
|---|---|---|---|---|---|---|---:|---:|---|---|---|---|
| A: first after clean boot | reported historical fast sample | UNKNOWN | reported first | PID/tree UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN | ~5 s | UNKNOWN | UNKNOWN | UNKNOWN | Compatible with TERM arriving near end of a 60 s sleep; insufficient raw evidence to prove clean-boot causality |
| B/C: repeated freeze normalization | run 007 | UNKNOWN | repeated epoch, exact ordinal UNKNOWN | 27125 → live `sleep 60` child | 873 unchanged at stop | 28220 | 0 | >10 s (timeout observation) | child live | not reached | X55 remained ONLINE | Direct deferred-sleep evidence; experiment fail-closed without escalation |
| B/C: repeated normalization | R3 cycle 2 | UNKNOWN | cycle 2 in series | 21676; descendants not captured | 2010→29967 | 27719 | final 0 | roughly low-30 s class from orchestration timestamps; exact timer absent | UNKNOWN | UNKNOWN | UNKNOWN | Compatible with residual sleep phase |
| C/D: later repeated normalization | R4A cycle 2 | UNKNOWN | cycle 2 after prior successful freeze | 27719; descendants not captured | 15426→5785 | 2218 | final 0 | roughly 50 s class from orchestration timestamps; exact timer absent | UNKNOWN | UNKNOWN | UNKNOWN | Compatible with later TERM phase within sleep cycle |
| D: latest manual repeated recovery | aggressive v0 success | UNKNOWN | later run after prior freeze; exact ordinal UNKNOWN | 32733; parent 870; child tree not captured | 16115 before normalization | 13670 | 3 | 57.974 s | UNKNOWN | separately polled after main gone | separately polled after main gone | Near-complete 60 s residual cycle |

The reported ~5/~34/~53/~58 s values are therefore **not treated as ordinary
random jitter**. They are consistent with a quantized maximum near 60 seconds
whose observed value is the remaining time when TERM reaches the current
sleep. The available evidence does **not** yet prove a monotonic relationship
with recovery count: boot identity and holder birth/sleep-phase timestamps were
not recorded, and a newly created holder can begin its sleep at a different
phase on every cycle. qcrild2/X55 epoch accumulation is not required to explain
the values, though it also cannot be excluded by old data.

Future proof-quality capture must record boot ID, uptime, recovery and holder
ordinals, holder/descendant PID+PPID+start time, FD9 for every member, and
separate device-monotonic times for TERM, main gone, descendants gone, owner
NONE, vendor OFFLINE, and kernel OFFLINE. This is observation only; v1 neither
shrinks the 70-second deadline nor changes signal/escalation behavior.

## Holder implementation decision

Not modified in v1. Although the 60-second sleep is the leading and
high-confidence cause of the quantized process-exit latency, changing the
holder created by the frozen v2.6.2 core would change that core's lifecycle
implementation. A future isolated experiment may use an Android-shell-native
holder with an immediately serviceable TERM path and explicit descendant/FD
proof. It must be separately reversible and must not use SIGKILL.

## Expected v1 budget

| Component | V1 value | Status |
|---|---:|---|
| A minimum settle | 5 s | FROZEN CONTRACT |
| A lightweight capture/classification | 3.2–3.6 s | MEASURED baseline |
| First full snapshot | 0 s on exact split; 34–35 s on fallback | EXPECTED |
| Quick native-owner probe | 0 s on exact split | EXPECTED |
| Holder termination | 5–60 s observed range; no v1 change | ESTIMATED from historical observations |
| qcrild2 restart + native reacquire after holder exit | about 12 s | ESTIMATED from latest run |
| Post-normalization lightweight verification | 3.2–3.6 s | ESTIMATED from measured collector |
| Second full snapshot | 0 s on exact A0; 35 s on fallback | EXPECTED |
| Normal exact-split A total | about 28–84 s | ESTIMATED |
| Future separate holder target | holder ≤2 s; A about 25–27 s | TARGET, not implemented or measured |

No target number is presented as a measurement.
