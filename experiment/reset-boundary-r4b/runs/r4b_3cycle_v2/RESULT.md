# R4b three-cycle v2 result

> **2026-09-24 evidence corrections:** response serials 0 and 6 completed with **zero QualifiedNetworks entries**. The earlier `QUERY_RESPONSE_VALID` label established response completion, not a valid non-empty payload. Later target-native inspection proves `PROVIDER_IMS_CONTENT` was derived from an old-generation NAH history line, not a separate current cache; the replacement handler's current caches were empty and agreed with GET. These corrections do not weaken the frozen result: `R4B_FALSIFIED_AT_P`, Cycle 1, first missing M1. See `experiment/native-qualified-network-boundary/`.

## Verdict

```text
R4B_FALSIFIED_AT_P
R4B_FALSIFIED_AT_CYCLE=1
FIRST_MISSING_MILESTONE=M1
```

This was a new independent series; v1 was not resumed. Cycle 1 was valid through R0, producer, provider and A readiness. Fixed P failed, so v2.6.2, the SIM cycle and Cycles 2/3 were not run.

## CONTROL_A0_R4B_V2

- One authorized reboot: PASS; no later reboot.
- Initial qcrild/qcrild2/qtidataservices/phone: `1927 / 1961 / 3385 / 3448`.
- Initial native ownership clean, X55 ONLINE, crash_count 0, VOXI active/UICC enabled, terrestrial A baseline and F1.

## Cycle 1 process generations

| Layer | Old PID | New PID | Gate |
|---|---:|---:|---|
| qcrild2 producer | 1961 | 14682 | PRODUCER_READY PASS |
| qtidataservices provider | 3385 | 23859 | PROVIDER_READY PASS |
| com.android.phone consumer | 3448 | 27795 | A_READY PASS |

Primary qcrild 1927, cnd 1838 and Qualcomm IMS 3434 remained unchanged through the provider gate.

## T1-T14

| T | Time | Evidence/result |
|---|---|---|
| T1 | 21:41:34.839 | old qtidataservices 3385 died |
| T2 | 21:41:34.861 | new qtidataservices 23859 born |
| T3 | 21:41:35.014 | slot1 QNS provider created |
| T4 | 21:41:35.012 | new-process slot1 IWlanProxy created |
| T5 | 21:41:35.014 | IIWlan/slot2 connected |
| T6 | UNOBSERVABLE | request log and request serial not emitted |
| T7 | 21:41:35.074 | `QualifiedNetworksServiceImpl: 0 > Response Processed`; response serial 0 |
| T8 | UNOBSERVABLE | `get complete, Calling updateQualifiedNetworks` not emitted in available log |
| T9 | UNOBSERVABLE | `Calling updateQualifiedNetworkTypes` and its exact payload not emitted |
| T10 | UNOBSERVABLE | runtime callback object/registration not exposed; static constructor order is known |
| T11 | 21:43:26.231 device time | old phone 3448 died after the one TERM |
| T12 | 21:43:26.265 | new phone 27795 born |
| T13 | 21:43:27.922 | new ANM-1 bound to vendor.qti.iwlan |
| T14 | MISSING | no new-phone ANM IMS-to-IWLAN callback through fixed P |

Provider query classification at runtime was `QUERY_RESPONSE_VALID` under the frozen v1 gate: T3 and T7 completed, response serial was 0, and the contemporaneous producer cache's current IMS entry was `networks=[EUTRAN,IWLAN]`. The request serial and exact response/update payload are nevertheless `UNOBSERVABLE`; the native cache must not be misreported as the exact Java response body.

No ANM IMS callback was observed to either the old phone after provider restart or the new phone after R3.

## Fixed P and milestones

At the fixed 60-second P snapshot:

- airplane ON, Wi-Fi/VPN ready;
- rilTechnology `Unknown`;
- PS/WLAN `UNKNOWN`;
- access network `UNKNOWN`;
- `mIsIwlanPreferred=false`;
- no qti.cne IMS request;
- IMS NOT_REGISTERED/UNKNOWN and WFC unavailable.

| Milestone | Result |
|---|---|
| M1 ANM IMS -> IWLAN | MISSING |
| M2 NRM IWLAN/HOME | MISSING; NRM returned NOT_REG_OR_SEARCHING before P and no positive HOME result followed |
| M3 SST consumes positive NRM result | MISSING; SST consumed only negative/unknown WLAN state |
| M4 DNC IWLAN/HOME | MISSING |
| M5 new qti.cne IMS request | NOT REACHED / absent |
| M6 IMS REGISTERED/WLAN | NOT REACHED / absent |
| M7 WFC HEALTHY | NOT REACHED / absent |

v2.6.2 and SIM OFF/ON counts: `NOT RUN`, `0 / 0`.

## Boundary interpretation

The evidence does not satisfy strict CASE B because T8/T9 and the exact Java response payload are unobservable. It also does not prove CASE A because the producer cache was current and a provider response was processed.

The earliest unclosed internal interval is:

```text
IIWlan response serial 0
-> QNS updateQualifiedNetworks/updateQualifiedNetworkTypes (T8/T9 unobservable)
-> framework replay/publication to new ANM (T14 missing)
```

The first concrete functional divergence is T14/M1 at the qtidataservices/QNS-to-new-framework-consumer publication/replay boundary. R4b's complete producer + provider + consumer reset was therefore falsified at fixed P, without identifying which side of the unobservable T8/T9 interval dropped the current IMS qualification.

No periodic QNS report, forced transport, callback injection, retry, fallback, timeout extension, second reset or second SIM cycle was used.

Phone-write actions in the complete v2 phase: 8 (baseline reboot, baseline airplane OFF, baseline Wi-Fi enable, one qcrild2 restart, one qtidataservices TERM, one phone TERM, fixed-P airplane ON, fixed-P Wi-Fi enable). SIM writes: 0.
