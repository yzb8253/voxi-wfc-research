# Success versus failure native qualified-network diff

Date: 2026-09-24
Phone writes: **0**

## Compared samples

- Success control: R4a v2 Cycle 1 (`WFC HEALTHY`).
- Failure counterexample: R4b v2 Cycle 1 (`R4B_FALSIFIED_AT_P`, first missing M1).
- W0/W1 remain consistent historical successes, but their saved evidence does not expose every serial-level native stage. No unavailable field is inferred from final WFC alone.

## First concrete difference

| Native stage | R4a Cycle 1 success | R4b Cycle 1 failure |
|---|---|---|
| NAH generation | constructor 20:26:27.319 | old constructor 21:40:33.273; replacement constructor 21:41:35.048 |
| working cache | current entries include IMS `[EUTRAN,IWLAN]` | replacement handler current working cache empty |
| last-reported/query cache | current IMS entry exists (`prefNw=EUTRAN`) | replacement handler current last-reported list empty |
| initial provider query | fresh framework later receives EUTRAN publication | serial 0 handled 24 ms after replacement constructor; response count 0 |
| fresh-phone query | new ANM receives terrestrial qualified-network publication | serial 6 response count 0 |
| fixed P M1 | ultimately present in successful run | absent |

The earliest demonstrated `SUCCESS != FAILURE` is not final WFC and not ANM. It is:

**current-generation `LastReportedNetworkAvailability` is populated before consumer query in the success control, but empty when queried in R4b.**

## R4a evidence

R4a Cycle 1 current dump:

```text
globalPrefSys= IWLAN
NetworkAvailabilityCache:
  apn=ims ... networks=[EUTRAN,IWLAN]
LastReportedNetworkAvailability:
  apnType=IMS prefNw=EUTRAN
```

The qtidataservices PID remained 3373 while qcrild2 was rebuilt. The NAH was constructed at 20:26:27.319, published IMS at 20:26:28.194, and the fresh phone later received ANM EUTRAN at 20:27:32.209. This proves the new producer generation had a reportable value before the consumer epoch queried it.

## R4b evidence

R4b killed and recreated qtidataservices after qcrild2 producer readiness. Reconnecting the new Java process caused a second native enable handshake and a second NAH constructor. The replacement handler's live dump is empty even though the process history still contains the old handler's IMS line. Serial 0 was handled almost immediately after replacement construction and serial 6 remained empty roughly 113 seconds later.

Thus R4b did not merely add a Java provider reset. It also unintentionally reset the native NAH generation through `setResponseFunctions -> initializeIWLAN`, after the earlier PRODUCER_READY proof had been collected.

## Query-too-early assessment

- Serial 0: **strong evidence** of query-too-early relative to the replacement NAH publication boundary. Request queued before the constructor; handler entered 24 ms after construction; current report list was empty.
- Serial 6: not a second timing race by itself. It shows the replacement generation never reached a non-empty published state during the observed interval.
- The existing PROVIDER_READY gate therefore proved response completion, not native publication readiness. It also accepted stale process-history lines from the prior NAH generation.

## Causal boundary

The smallest supported boundary is:

`qtidataservices reconnect -> native initializeIWLAN creates replacement NAH -> missing/delayed current-generation DSD/profile population or publication -> GET returns empty -> QNS has nothing to publish -> M1 absent`.

Whether the missing input is invalid cached DSD status, no fresh post-handshake DSD/APN indication, or a profile/indication ordering dependency is not fully observable in the saved run. It must remain narrower-but-unresolved rather than being guessed.
