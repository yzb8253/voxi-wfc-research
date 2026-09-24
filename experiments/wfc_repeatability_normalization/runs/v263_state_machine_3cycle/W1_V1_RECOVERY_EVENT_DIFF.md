# W1 Success vs V1 Failure Event Timeline Diff

Date: 2026-09-24

Scope: host-only forensic comparison. No ADB command or phone write was issued for this analysis. A/P canonical definitions and the v2.6.2 recovery were not changed.

## Evidence

- Successful W1 host log: `experiments/wfc_repeatability_normalization/v262_freeze_run/X55-Logs/X55-WFC-20260924_154317.log`
  - SHA-256: `258F69D4B2FF1CE03DC2B9314E76BC7D0499EE75BB946EE415E302852C1669AE`
- Failed V1 host log: `experiments/wfc_repeatability_normalization/v262_freeze_run/X55-Logs/X55-WFC-20260924_163933.log`
  - SHA-256: `2D7BE2A4EA5C1A7751BDCDFCCD6CEC5B1754F6E81E1492FD14BC714434AB0A2F`
- Host-only post-state `ims.txt`, `qcril_x55_evidence.txt`, `network.txt`, and snapshot JSON for W1 and V1.

The saved `qcril_x55_evidence.txt` files are filtered `logcat -d` tails. Their capture filter includes `IWLAN`, `qti.cne`, and `NetworkAvailabilityHandler`, but not every QNS, DSD, WDS, QImsService, UICC, or CarrierConfig tag. Absence of an event outside that filter is not proof that the event did not occur.

## Control Path Before SIM ON

Both runs completed the same externally visible control sequence:

| Event | W1 success | V1 failure |
|---|---:|---:|
| Entry F1 confirmed | 15:43:25.246 | 16:39:41.738 |
| X55 OFFLINE, crash count 0 | 15:43:29.566 | 16:39:45.999 |
| Holder confirmed | 15:43:33.787 | 16:39:50.446 |
| X55 ONLINE | 15:43:35.322 | 16:39:52.079 |
| New `PON_SUCCESS` | 15:43:35.491 | 16:39:52.226 |
| Ten-second settle started | 15:43:35.638 | 16:39:52.398 |
| SIM OFF accepted | 15:43:59.998 | 16:40:17.254 |
| SIM ON command returned | 15:44:03.949 | 16:40:21.286 |

Before SIM OFF, both sides also showed slot 1 returning to `PS/WLAN HOME`, `IWLAN`, and `mIsIwlanPreferred=true`. During SIM OFF, both sides delivered `NOT_REG_OR_SEARCHING` to SST and changed DNC WLAN from `IWLAN/HOME` to `UNKNOWN/UNKNOWN`. No event-level fork is proven before SIM ON.

## SIM ON Timeline

Times below are device timestamps. Relative offsets use the first observed post-insert slot-1 `setSubId=11` event as zero because host command timestamps and device logcat timestamps have a small clock/logging offset.

### Successful W1

| Relative | Time | Event |
|---:|---:|---|
| +0.000 s | 15:44:03.346 | MMTEL and RCS `setSubId=11` |
| +0.221 s | 15:44:03.567 | `ANM-1 onQualifiedNetworkTypesChanged: ims -> [IWLAN]` |
| +0.221 s | 15:44:03.567 | `NRM-I-1` returns `PS/WLAN HOME`, `IWLAN`, service `DATA` |
| +0.237 s | 15:44:03.583 | MMTEL `connectionReady -1` |
| +0.242 s | 15:44:03.588 | SST consumes the IWLAN/HOME result |
| +0.262 s | 15:44:03.608 | SST broadcasts service state with IWLAN and preferred=true |
| +0.368 s | 15:44:03.714 | DNC-1 changes WLAN `UNKNOWN -> IWLAN`, `UNKNOWN -> HOME` |
| +0.390 s | 15:44:03.735 | second MMTEL `setSubId=11` |
| +3.103 s | 15:44:06.449 | ImsResolver removes old slot-1 MMTEL controller |
| +3.105 s | 15:44:06.451 | ImsResolver adds slot-1 MMTEL for subId 11 |
| +3.154 s | 15:44:06.500 | MMTEL `connectionReady 11` |
| +3.398 s | 15:44:06.744 | additional NRM IWLAN/HOME result |
| +16.214 s | 15:44:19.560 | qti.cne creates IMS request 293 for subId 11 |
| +16.224 s | 15:44:19.570 | `TelephonyNetworkFactory[1]` receives request 293 |
| +16.228 s | 15:44:19.574 | DNC-1 adds request 293 |
| +16.240 s | 15:44:19.586 | IMS IWLAN NetworkAgent 105 is registered |
| +18.826 s | 15:44:22.172 | IMS/WFC service-state evidence becomes in-service |

The qti.cne request appeared 15.611 seconds after the host logged that SIM ON returned, or 15.799 seconds after the host logged the invocation. The device-side lifecycle places it about 16.214 seconds after the first observed insertion event.

### Failed V1

| Relative | Time | Event |
|---:|---:|---|
| +0.000 s | 16:40:20.659 | MMTEL and RCS `setSubId=11` |
| +0.036 s | 16:40:20.695 | MMTEL `connectionReady -1` |
| +0.149 s | 16:40:20.808 | `ANM-1 onQualifiedNetworkTypesChanged: ims -> [IWLAN]` |
| +0.221 s | 16:40:20.880 | `NRM-I-1` returns `PS/WLAN HOME`, `IWLAN`, service `DATA` |
| +0.380 s | 16:40:21.039 | second MMTEL `setSubId=11` |
| +3.083 s | 16:40:23.742 | ImsResolver slot-1 subId changes `-1 -> 11` |
| +3.088 s | 16:40:23.747 | ImsResolver adds slot-1 MMTEL for subId 11 |
| +3.135 s | 16:40:23.794 | MMTEL `connectionReady 11` |
| missing | expected after 16:40:20.880 | no slot-1 SST consumption of the new IWLAN/HOME result |
| missing | expected next | no DNC-1 WLAN `UNKNOWN -> IWLAN/HOME` transition |
| missing | through final window | no qti.cne IMS request, TNF request, DNC IMS request, or IMS NetworkAgent |

The final V1 state remained `PS/WLAN UNKNOWN`, `mIsIwlanPreferred=false`, IMS `NOT_REGISTERED`, and WFC unavailable.

## First Fork

The first ordering difference is that W1 publishes ANM/NRM before MMTEL reports `connectionReady -1`, while V1 reports `connectionReady -1` before ANM/NRM. This is a reproducible ordering observation, but the saved evidence does not prove it is causal.

The first clearly missing downstream event is stronger: after V1's successful `NRM-I-1` IWLAN/HOME callback at 16:40:20.880, no slot-1 `SST handlePollStateResultMessage` follows. In W1, SST consumes the equivalent result 21 ms later and DNC receives the IWLAN/HOME transition 147 ms after the ANM event.

This locates the earliest observed consequential fork between NetworkRegistrationManager completion and ServiceStateTracker/DNC propagation. It is earlier than the missing qti.cne request and later than the QNS/ANM qualified-network publication.

## Interpretation

- QNS/qualified-network publication was not wholly missing: both runs reached `ANM-1` with `ims -> [IWLAN]`.
- Subscription, UICC-visible mapping, CarrierConfig reload, and ImsResolver/MMTEL remove/add completed in both runs.
- The failed run did not propagate its returned IWLAN/HOME registration into slot-1 SST/DNC state after insertion.
- qti.cne request creation is therefore a later divergence, not the first one.
- A hidden callback-generation, pending-poll, registration-listener, or message-ordering state between NRM and SST is a candidate explanation. The current evidence cannot distinguish those internals.
- Direct QNS/DSD/WDS/QImsService events were not retained by the historical filter, so no claim is made that a particular vendor event was absent.

## Canonical-Gate Decision

The current A/P schema records steady state (`PS/WLAN`, IWLAN preferred, IMS, CNE request), but not liveness of the next `NRM -> SST -> DNC` delivery or the ordering between MMTEL readiness and ANM publication. That hidden transition state is not represented by the current canonical snapshots.

Do not change A/P canonical or v2.6.2 recovery from this single comparison. The newly identified state is dynamic and post-SIM-ON; it is not yet a proven read-only pre-P discriminator. Add it first as capture-only event telemetry and as a post-SIM progress gate:

1. ANM publishes `ims -> [IWLAN]`.
2. NRM returns `PS/WLAN HOME`.
3. SST consumes that exact result.
4. DNC-1 observes `UNKNOWN -> IWLAN/HOME`.
5. qti.cne creates the IMS request.

Only promote a field into the P canonical hard gate after a stable pre-SIM read-only observable for this callback/dispatch state is identified. On present evidence, modifying the recovery would be premature.

## Answers

1. W1's new qti.cne IMS request appeared approximately 15.6 seconds after the SIM ON command returned (about 16.2 seconds after the first device-side insertion event).
2. Before it: subId restoration, ANM `ims -> [IWLAN]`, NRM IWLAN/HOME, SST consumption and broadcast, DNC WLAN restoration, CarrierConfig/ImsResolver MMTEL rebuild, and `connectionReady 11` all occurred.
3. V1 reached ANM and NRM, plus the same ImsResolver/MMTEL rebuild, but lacked SST consumption and the DNC WLAN restoration after SIM ON. It then lacked the qti.cne/TNF/DNC IMS request chain.
4. Earliest ordering difference: MMTEL `connectionReady -1` moved ahead of ANM/NRM. Earliest clearly missing event: SST consumption of the NRM IWLAN/HOME result.
5. Yes. NRM-to-SST callback/poll-generation liveness and event ordering are absent from the current snapshot schema.
6. Capture this state before changing recovery, but do not yet make it a P canonical hard gate. It is currently observable only during the post-SIM transition; use it as telemetry/progress evidence until a deterministic pre-P read-only representation is proven.

Phone writes: 0. ADB used: no.
