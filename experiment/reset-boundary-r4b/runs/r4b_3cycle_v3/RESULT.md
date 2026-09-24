# R4b publication-gated v3 result

Date: 2026-09-24

## Classification

`ABORTED_PRE_NATIVE_PUBLICATION_GATE_LEGACY_PROVIDER_OBSERVER`

This is **not** an R4b publication-gated lifecycle failure and does not falsify the candidate. The runner stopped inside the inherited v2 `PROVIDER_READY` evidence adapter before the new `NATIVE_PUBLICATION_READY` script was invoked.

The adapter required ten consecutive samples of one-shot qtidataservices creation log lines. The loop reached nine passing samples, then those historical logcat lines were no longer returned while the live process/services remained valid. It timed out after the already-authorized single qtidataservices TERM. No reset was repeated.

## Executed scope

- Baseline: one authorized reboot; airplane OFF/Wi-Fi enabled; `CONTROL_A0_R4B_V3` captured in F1.
- Cycle 1 R0: PASS, no write.
- qcrild2: `1966 -> 14018`, exactly one restart; producer ready PASS.
- qtidataservices: `3348 -> 22991`, exactly one exact-PID TERM; new process and hosted services observed.
- phone: remained `3423`; R3 did not execute.
- v2.6.2: not executed.
- SIM OFF/ON: `0/0`.
- Cycles 2/3: not run.

## Native evidence retained at stop

- Latest NAH constructor: `2026-09-24 22:53:48.139`.
- At `22:56:01`, more than 120 seconds later, the **live current** `NetworkAvailabilityCache` was empty.
- Live current `LastReportedNetworkAvailability` was empty.
- `globalPrefSys=UNKNOWN`.
- Historical IMS/EUTRAN/IWLAN lines before the constructor were rejected as prior-generation evidence.

This strongly supports CASE 1, but the frozen new gate did not continuously evaluate its own current-generation predicate. Therefore the scientifically valid output is **not** `NATIVE_PUBLICATION_NOT_READY`; it is an invalid pre-gate abort. No timeout extension or post-timeout resume was attempted.

## Requested fields

| Field | Cycle 1 |
|---|---|
| qcrild2 PID | `1966 -> 14018` |
| qtidataservices PID | `3348 -> 22991` |
| phone PID | `3423` unchanged; R3 not run |
| NAH generation | `2026-09-24 22:53:48.139` |
| working cache | empty at stop |
| LastReported cache | empty at stop |
| publication-ready time | NOT REACHED |
| R3 generation invariant | NOT TESTED |
| natural post-R3 GET serial | NOT RUN |
| GET response | NOT RUN |
| QNS update | NOT RUN |
| P canonical | NOT RUN |
| M1-M7 | NOT RUN |
| earliest failure boundary | host observer before `NATIVE_PUBLICATION_READY` |
| publication-gated candidate | NOT TESTED / NOT FALSIFIED |

## Phone-write count

Five authorized actions were issued: baseline reboot, airplane disable, Wi-Fi enable, one qcrild2 restart, and one qtidataservices TERM. There was no cleanup or adaptive phone action after the abort.

Final read-only check: airplane OFF, `vendor.per_mgr` running, X55 ONLINE, crash count 0, pm-service PID 1279, qcrild2 PID 14018, qtidataservices PID 22991, VOXI ACTIVE/UICC ENABLED/F1. IMS remained NOT_REGISTERED/UNKNOWN and WFC unavailable.

## Static correction after stop

The unexecuted correction adds `-EpochOnly`: the qtidataservices stage now gates only the new process identity, hosted services and native IIWlan readiness for three stable samples. Publication semantics are delegated exclusively to `NATIVE_PUBLICATION_READY`, as the v3 design requires. This correction was not run against the phone and cannot retroactively validate Cycle 1.
