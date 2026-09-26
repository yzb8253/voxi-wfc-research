# Deep CNE Request Recovery Analysis

## Executive verdict

The old four-to-five-minute wrappers did **not** contain a hidden process restart that was proven to regenerate CNE demand. Their special “deep” addition was one guarded VOXI UICC-applications software remove/insert (`false,11` -> confirmed F8 -> `true,11`), followed, if needed, by another unchanged v2.6.2 run.

The smallest historical action with direct, repeated fresh-request evidence is therefore:

> **one fixed `ISub.setUiccApplicationsEnabled(true,11)` after one fixed false operation has reached confirmed F8.**

That re-enable produced new current Connectivity requests 360, 374 and 380 in three controlled cycles. It did so without restarting the CNE Java process: all requests were issued by UID/PID `10104/3236`. The disable half is a required lifecycle precondition because it removes the old request and establishes F8; it is not itself the positive request trigger.

This is a proven trigger **in those three historical F8 cycles**, not a deterministic cure for every active+enabled F1. Later runs show one success and two failures of the same false/true idea. Consequently the proposed `MINIMAL_CNE_RECOVERY` is a falsifiable candidate, not production authorization.

`PHONE_WRITES=0` for this analysis.

## 1. Scope and evidence rules

The analysis uses repository history, committed scripts, sanitized reports and existing local logs only. It did not call ADB or alter the phone. Current-table Connectivity evidence is preferred over legacy whole-dump `wfcctl` request projection, which is known to confuse historical RELEASE records with live requests.

Evidence levels used below:

- `PROVEN_CNE_TRIGGER`: a fresh current request ID appears after the action, with the old request removed or a null baseline, in repeated controlled evidence.
- `LIKELY_CNE_TRIGGER`: tight temporal placement and supporting repeats, but the action was not isolated or has counterexamples.
- `PRECONDITION_ONLY`: prepares a required lifecycle or ownership state but did not itself produce a request.
- `CLEANUP_ONLY`: restores safe ownership/state after a result.
- `NO_EFFECT_OBSERVED`: controlled execution completed and no IMS CNE request appeared in its observation window.
- `INSUFFICIENT_EVIDENCE`: execution or the needed current-table observation is absent.

## 2. Version evolution

```text
Phase 4D / releases v1.0-v1.3
  false,11 -> confirmed F8 -> true,11
  purpose: force complete subscription/UICC/CarrierConfig/IMS lifecycle
  result: three early controlled cycles generated fresh requests 360/374/380
          later active-F1 runs were non-deterministic

Phase 6-9 process-boundary isolation
  resetIms(1), org.codeaurora.ims, qtidataservices, vendor.cnd,
  cnd+qtidataservices, full userspace stack
  purpose: find a narrower replay boundary
  result: no fresh IMS CNE request

SIM soft-reset and RIL boundary
  slot1 SIM power cycle; primary/target RIL repair; qcrild2 cold epoch
  purpose: reproduce physical insert / native producer epoch
  result: each alone insufficient

X55 v2.6.2 lifecycle
  X55 shutdown -> holder/PON_SUCCESS -> one slot1 SIM power cycle
  purpose: rebuild modem-facing epoch, then replay SIM lifecycle
  result: many fresh-request successes, plus genuine NO_CNE counterexamples

STABLE-v1 deep fallback (commits 14b1e76/d3b1368/949bfab)
  two normal NO_CNE attempts -> safe A0 -> guarded UICC false/true
  -> P -> one more unchanged v2.6.2 run
  purpose: bounded last resort for repeated NO_CNE only
  result: code/audit exists; no committed execution proves the complete long wrapper

R3/R4a/R4b reset-boundary work
  phone consumer, qcrild2 producer, qtidataservices provider epochs
  purpose: reproduce boot-like QNS publication/replay
  result: counterexamples narrowed the fault to native per-APN availability/cache
          and provider/consumer publication; no smaller deterministic reset proven
```

Why deep recovery was added: normal v2.6.2 could finish a complete SIM cycle with current request still null (`NO_CNE_REQUEST`) or could retain the same current request ID (`STALE_CNE_REQUEST`). A later retry/cleanup then made the run four-to-five minutes long. The deep UICC lifecycle was added after two explicit NO_CNE attempts because earlier F8 validation had shown new request generation.

## 3. Fault definitions

### NO_CNE_REQUEST

After SIM ON and the full normal observation window, current-table request and satisfied IDs remain null, qti.cne has no live sub11 IMS demand, TNF/DNC receive no new IMS request, and IMS/WFC remain unhealthy.

### STALE_CNE_REQUEST

A live current-table IMS request exists before the cycle and the same ID remains after the cycle without producing healthy WFC. Historical log-only IDs do not qualify. The current-table parser is authoritative.

The two classes matter because the old guarded UICC deep fallback was authorized only after repeated `NO_CNE_REQUEST`, not after stale, dirty-P, mapping or native-owner failures.

## 4. Proven UICC deep-recovery timeline

The offline extractor is `Get-DeepCneEvidence.ps1`; its fixtures verify the committed evidence rather than relying on prose.

| Cycle | true write | subscription/UICC | MMTEL | first fresh current request | request delay | IMS NetworkAgent / IMS / WFC |
|---|---|---|---|---|---:|---|
| 1 | 13:40:16.027 | ACTIVE+enabled by first +1 s sample | READY by first +2 s sample | id 360 at 13:40:26.120 | 10.093 s | all healthy by first 15.499 s sample |
| 2 | 14:56:32.140 | ACTIVE+enabled by first +6.5 s host sample | READY in same sample | old 360 released; id 374 at 14:56:44.193 | 12.053 s | agent/REGISTERING sampled +13.182 s; WFC +19.726 s |
| 3 | 15:02:52.983 | ACTIVE+enabled and MMTEL READY by first +6.5 s host sample | READY | old 374 released; id 380 at 15:03:27.320 | 34.337 s | agent/REGISTERED/WFC first sampled +39.222 s |

Cycle 1’s raw event chain is particularly complete:

```text
true,11
 -> UICC ENABLEMENT_CHANGED true
 -> USIM/ISIM READY
 -> sub11 remapped ACTIVE
 -> MMTEL READY
 -> qti.cne UID/PID 10104/3236 requestNetwork id=360
 -> TNF[1] accepts IMS/sub11
 -> DNC[1] selects Vodafone UK IMS over IWLAN
 -> IMS NetworkAgent / ePDG
 -> REGISTERED/WLAN
 -> WFC AVAILABLE
```

Cycles 2 and 3 prove replacement rather than mere rediscovery: request 360 was released before 374, and 374 was released before 380. The qti.cne process PID stayed 3236, so neither CNE nor qtidataservices process restart was necessary for these successful reissues.

### Counterevidence and limits

- The later 22:28 run again succeeded: after true, the first decisive CNE request appeared at 22:29:01.576 and WFC followed.
- The 22:37 and 22:39 runs executed the same false/F8/true lifecycle, restored Subscription, UICC, CarrierConfig, ImsResolver and MMTEL, but produced no request through 60 seconds.
- A physical-style slot1 POWER_DOWN/POWER_UP and a stabilized second reinsert also failed.

Therefore UICC true-after-F8 is the smallest historically proven request generator, but UICC lifecycle alone is not sufficient in every native/QNS epoch.

## 5. Deep-action causal classification

| Action | Evidence | Classification |
|---|---|---|
| UICC apps false for sub11 | releases old request and establishes inactive/apps-disabled F8; never creates the positive request | `PRECONDITION_ONLY` |
| UICC apps true after confirmed F8 | fresh IDs 360/374/380 in 3/3 early controlled cycles; later failures exist | `PROVEN_CNE_TRIGGER` within validated F8 preconditions; globally `LIKELY_CNE_TRIGGER` |
| `resetIms(1)` | disable/enable reached Qualcomm IMS; General_Error17; no request for 120 s | `NO_EFFECT_OBSERVED` |
| restart `org.codeaurora.ims` | new PID and fresh MMTEL objects; no request for 195.7 s | `NO_EFFECT_OBSERVED` |
| restart `.qtidataservices` | CneApp/QNS/IWLAN rebound; no native IMS replay for 120 s | `NO_EFFECT_OBSERVED` |
| restart `vendor.cnd` | new PID; residual IWLAN cleared; no request for 120 s | `NO_EFFECT_OBSERVED` |
| cnd then qtidataservices | generic requests recreated, but no IMS request | `NO_EFFECT_OBSERVED` |
| full IMS/data userspace sequence | all five targets rebuilt; no IMS demand | `NO_EFFECT_OBSERVED` |
| coordinated primary/target RIL repair | QtiBus and target stability restored; no IMS request | `PRECONDITION_ONLY` / `NO_EFFECT_OBSERVED` for CNE |
| qcrild2 cold epoch alone | new NAH/IIWlan/DSD/WDS, but wrong/empty qualification and no request | `NO_EFFECT_OBSERVED` |
| R3 phone consumer epoch | can rebuild ANM/NRM/SST/DNC; fails at P/M1 in counterexample | `PRECONDITION_ONLY` |
| R4a producer + R3 consumer | one cycle reached M1-M7, next valid cycle failed at M1 | `INSUFFICIENT_EVIDENCE` as deterministic recovery |
| R4b producer/provider/consumer | replacement NAH initial query empty; M1 absent | `NO_EFFECT_OBSERVED` for tested order |
| X55 shutdown/rebirth + new PON_SUCCESS | current request remains null before SIM cycle | `PRECONDITION_ONLY` |
| slot1 SIM OFF | removes/rebuilds lifecycle; no positive request by itself | `PRECONDITION_ONLY` |
| slot1 SIM ON after prepared X55 epoch | repeatedly followed by fresh current request, but has NO_CNE counterexamples | `LIKELY_CNE_TRIGGER` |
| complete X55 epoch + one SIM cycle | multiple current-table fresh-request successes | `PROVEN_CNE_TRIGGER` as a set, not as isolated primitives |
| native ownership restoration/holder cleanup | occurs after outcome or prepares next A0 | `CLEANUP_ONLY` |
| STABLE-v1 full deep wrapper | no committed completed run found | `INSUFFICIENT_EVIDENCE` |

## 6. QNS/CNE divergence

The stable common prefix is:

```text
SIM/UICC active and enabled
 -> CarrierConfig loaded
 -> ImsResolver/MMTEL READY
```

The success-only branch is:

```text
per-APN native qualification becomes usable
 -> QNS publishes IMS -> IWLAN
 -> native CNE calls requestNetwork(true, IMS/slot1)
 -> CneApp creates a fresh Connectivity request
 -> TNF/DNC attach IMS over IWLAN
 -> IMS NetworkAgent/ePDG/XFRM
 -> REGISTERED/WLAN -> WFC
```

The NO_CNE branch stops before `requestNetwork`. Existing evidence supports several narrower facts:

- UICC and MMTEL recovery are not discriminators.
- CneApp can be alive and own generic listeners while lacking the IMS request.
- Restarting CneApp/QNS does not make native cnd replay IMS demand.
- `globalPrefSys=IWLAN` does not synthesize `IMS -> [IWLAN]`; the per-APN availability vector must be populated.
- In the R4b counterexample, qtidataservices reconnection created a replacement NetworkAvailabilityHandler whose live cache was empty, so the initial query returned empty and QNS had nothing to publish.
- qcrild2 alone did not fix the per-APN ordering/cache state.

The first objectively missing event is therefore the native per-APN IMS qualification/demand publication that precedes the qti.cne Connectivity request. Whether a given failure is caused by missing DSD APN indication, lost cache replay, or consumer publication remains `ROOT_CAUSE_NOT_PROVEN`.

## 7. Proposed `MINIMAL_CNE_RECOVERY`

This is an experiment design only; it is not integrated and was not executed.

### Entry gate

After the unchanged normal SIM cycle and at least the unchanged full normal CNE window:

- direct health is unhealthy;
- exact VOXI slot1/phone1/sub11/carrier28/23415 mapping is ACTIVE and UICC enabled;
- current-table CNE is either null/null (`NO_CNE_REQUEST`) or a rigorously proven unchanged live ID (`STALE_CNE_REQUEST`);
- qcrild/qcrild2 identities are exact;
- X55 is ONLINE, crash count is readable and not changing during the gate;
- holder/native owner is exact and contradiction-free;
- no parse/schema/owner/mapping ambiguity exists.

### Candidate action

1. Start a fixed-target rollback watchdog that can issue only `true,11` if false was sent.
2. Execute exactly one `setUiccApplicationsEnabled(false,11)`.
3. Require confirmed F8 (`simSlotIndex=-1`, apps disabled) and prove any old current CNE request is gone.
4. Execute exactly one `setUiccApplicationsEnabled(true,11)`.
5. Stop all deep mutations immediately.
6. Observe current-table CNE for up to 45 seconds; the historical maximum fresh-request delay was 34.337 seconds.
7. On a new ID, transition immediately to ordinary IMS/IWLAN/WFC observation; do not run another v2.6.2, process restart or SIM cycle.
8. If no fresh ID appears, stop and preserve the scene. No second false/true.

The important reduction from the old long wrapper is what is omitted: no second normal v2.6.2 attempt before the candidate, no third v2.6.2 attempt after it, and no process restart. The experiment tests the one old sub-action that actually has direct fresh-ID evidence.

### Expected time

- Existing normal recovery: about 100-120 seconds.
- F8 transition and re-enable: expected roughly 5-15 seconds, bounded by the existing guarded helper/watchdog design.
- Fresh-request observation: up to 45 seconds.
- WFC final confirmation after fresh request: up to 15 seconds based on historical request-to-health samples, with a conservative stop at the agreed experiment bound.

Expected NO_CNE total is approximately 145-180 seconds. A universal 120-second failure-path guarantee is not supported without shortening the normal CNE window or overlapping an unproven write; neither is recommended.

## 8. `crash_count=4`

`crash_count=4` is correlation, not a root cause:

- There are successful v2.6.2 logs with `PRE_SHUTDOWN_CRASH_COUNT=3` and with `=4`; request 1518 and request 1582 were created and WFC became healthy.
- There are NO_CNE failures with counts 2, 3 and 4.
- R_BIG v1.1 Cycle 2 produced NO_CNE with crash count zero.
- Later code deliberately changed the gate from absolute zero to relative “no increment during this transition,” documenting that the field is cumulative telemetry.
- A reboot did reset observed count to zero, but zero did not prevent all NO_CNE failures and nonzero did not prevent success.

Thus `ROOT_CAUSE_NOT_PROVEN`. It remains useful as a transition-integrity signal, not as a CNE eligibility predicate.

## 9. Time-budget recommendation

Stability takes priority over a hard 120-second total. The normal path should remain unchanged:

| Segment | Budget |
|---|---:|
| A0/P0 preparation | 35 s |
| X55 OFFLINE, holder -> ONLINE, PON settle | 30 s |
| SIM OFF/ON lifecycle | 5 s |
| normal CNE/WFC sleep budget plus probes | 35-45 s |
| total normal success | about 105-115 s, with <=120 s target |

For NO_CNE, reserve a second bounded band rather than stealing from the normal window:

| Additional segment | Budget |
|---|---:|
| strict candidate gate + F8/true lifecycle | 10-20 s |
| fresh CNE request wait | <=45 s |
| request -> final WFC verification | <=15 s |
| expected total | about 145-180 s |

## 10. Next minimal phone experiment

Run one controlled A/B pair only after separate authorization:

1. Control: unchanged v2.6.2 once, preserving its full CNE window.
2. Only if it ends `NO_CNE_REQUEST`, do **not** normalize or start a second core attempt.
3. Capture a lightweight epoch: current request/satisfied, qcrild2/cnd/qtidataservices PIDs, native cache/QNS publication if observable, X55/owner/crash count, UICC/MMTEL.
4. Execute the one guarded F8 false/true candidate above.
5. Sample at 1, 2, 5, 10, 15, 20, 30, 45 and 60 seconds without adding a second write.
6. Primary endpoint: a new current-table CNE request ID. Secondary endpoints: TNF/DNC, IMS NetworkAgent, ePDG/XFRM and direct WFC health.
7. Stop on success, timeout or any gate contradiction. Preserve all PIDs and process epochs so a new request cannot be incorrectly attributed to an unnoticed restart.

Success would validate the reduced deep subset for that failure scene. It would not yet prove reliability; require at least three naturally occurring NO_CNE entries with the exact frozen candidate before production integration.

## 11. Risks and rollback

- The candidate deliberately removes and restores VOXI UICC applications; calls and SMS on slot1 are interrupted.
- The historical false operation can persist indefinitely, so the independent true-only rollback watchdog is mandatory.
- The action can still fail to repopulate native per-APN QNS state, as the later active-F1 failures demonstrate.
- It must never accept a dynamic subId/slot and must not touch slot0.
- On no fresh request, preserve the failure scene; do not cascade into qcrild2, qtidataservices, cnd, resetIms or another SIM/UICC cycle.

## Direct answer

**In the old four-to-five-minute design, the only deep sub-action directly shown to regenerate a fresh CNE request was the fixed VOXI UICC re-enable (`true,11`) after a fixed disable had reached confirmed F8.** It generated fresh IDs 360, 374 and 380 in three controlled cycles while the CNE process remained the same PID. The surrounding second/third v2.6.2 runs, process restarts and cleanup were not the proven cause. Because later identical false/true attempts failed, this is the best minimal candidate—not yet a deterministic production recovery.
