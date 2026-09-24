# R3 versus boot lifecycle diff

Date: 2026-09-24

Accepted result: `R3_FALSIFIED_AT_CYCLE=1`. This report does not weaken, reclassify or work around that counterexample.

## Fixed observations

The independent series used one reboot to establish `CONTROL_A0_V2`. Cycle 1 then passed `R0_NATIVE_READY`, sent one exact TERM to the audited main phone PID, and passed `R3_FRAMEWORK_READY`. Phone/SST/ANM/NRM/DNC, CarrierConfig and framework IMS objects were genuinely reconstructed.

The unchanged P transition nevertheless failed before recovery:

- no ANM IMS->IWLAN publication;
- NRM returned IWLAN `NOT_REG_OR_SEARCHING`, not HOME;
- SST consumed that non-home result;
- DNC moved WLAN state to UNKNOWN;
- no qti.cne IMS request;
- v2.6.2 and SIM cycle were not run.

This is a valid R3 failure, not a readiness or orchestration failure.

## Reset coverage diff

| Relevant state | Full boot reset | R0 + R3 reset | Consequence |
|---|---|---|---|
| AP/kernel/system_server boot epoch | YES | NO | system services and Binder registries are old under R3 |
| X55 firmware / modem QMI epoch | YES | R0 normalizes X55/PM but does not equal a full AP boot ordering | native modem state is gated clean, but boot-order equivalence is not proven |
| pm-service/per_mgr ownership | YES | YES through R0 | not the R3 counterexample |
| primary qcrild / QtiBus | YES | NO, only identity/stability gated | shared radio/QMI coordinator remains old |
| qcrild2 process | YES | only restarted if R0 fallback requires it; unchanged in the falsifying cycle | DataModule/DSD/WDS/NAH/IIWlan epoch remained old in the valid counterexample |
| DSD/WDS QMI client registrations | YES | NO in the falsifying cycle | no boot-like re-registration/fresh initial status guarantee |
| native NAH/cache/last-reported state | YES | NO in the falsifying cycle | old native qualification epoch remains |
| `.qtidataservices` process/static state | YES | NO | HIDL proxy/callback ownership, CNE trackers/static state may survive |
| QNS/IWLAN bound Service instances | YES | **Partly.** R3 unbind/rebind caused `Qualified networks service created` and `Network service created` in the same old PID | Java Service recreation alone did not yield desired initial publication |
| `vendor.cnd` native CNE | YES | NO | old native CNE request/listener epoch remains |
| Qualcomm IMS process | YES | NO | framework resolver rebinds the old vendor IMS process |
| `com.android.phone` process | YES | YES through R3 | all framework consumers were new |
| Phone/ANM/NRM/SST/DNC | YES | YES through R3 | confirmed new, therefore not sufficient |
| CarrierConfig and MMTEL framework state | YES | YES through R3 | restored and not the first missing event |

## What new framework consumers registered to after R3

The same-ROM R3 log gives a concrete sequence:

1. phone PID changed `3425 -> 17756` while qcrild2 `1927`, qtidataservices `3319` and Qualcomm IMS `3332` stayed unchanged;
2. Phone[1], ANM-1, NRM-I-1, SST-1 and DNC-1 were constructed;
3. qtidataservices PID 3319 logged `Qualified networks service created` and later `Network service created`;
4. ANM-1 bound `vendor.qti.iwlan`; NRM-I-1 bound `IWlanNetworkService`; DNC bound `IWlanDataService`;
5. IWlanNetworkService answered repeated new NRM queries, but every retained response was IWLAN `NOT_REG_OR_SEARCHING`;
6. CarrierConfig and MMTEL later reached current subId 11 / READY;
7. no QNS IMS->IWLAN callback appeared during fixed P.

This rules out the crude explanation “new phone never bound the vendor services.” It did bind and query them. It also shows that the Java QNS/NetworkService component instance can be recreated without resetting the qtidataservices process or native qcrild2 producer.

## Registration and replay semantics

| Relationship | Registration direction | What a new consumer gets | R3 evidence |
|---|---|---|---|
| ANM -> QualifiedNetworksService | framework ANM binds and creates a per-slot provider callback | Desired state depends on provider/native qualified-network publication; a guaranteed IMS->IWLAN replay on every rebind is not established | service recreated and ANM rebound, but no IMS->IWLAN callback followed |
| NRM -> IWlanNetworkService | NRM binds, registers for changes, and explicitly requests registration state | query response plus later change indications | query worked; current producer returned `NOT_REG_OR_SEARCHING` |
| DNC -> IWlanDataService | DataServiceManager binds provider | current data-call state and later indications | binding succeeded; no IMS request/data path existed |
| qtidataservices -> IIWlan/slot2 | IWlanProxy obtains HIDL service and calls `setResponseFunctions` | callback registration causes `IWLANCapabilityHandshake(true)` and native NAH initialization | no qcrild2/HIDL death occurred in R3, so a new native callback/NAH epoch is not established |
| CneApp -> native cnd | Java connector registers private native callback | native cnd must emit/replay demand | no CNE process/native daemon epoch changed; no IMS demand appeared |

Static QCRIL analysis is important here: a new `setResponseFunctions` handshake recreates NAH and AP-assist registrations but, by itself, replays `mCachedSystemStatus` rather than guaranteeing a fresh DSD system-status query. A qcrild2 cold start does perform fresh DataModule initialization, but a prior isolated qcrild2 restart still produced poisoned `[UNKNOWN,IWLAN]` ordering. Therefore neither “rebind only” nor “qcrild2 only” has already been proven sufficient.

## H2: provider epoch mismatch audit

### What is confirmed

- The valid R3 counterexample had a **new framework epoch** and unchanged qcrild2/qtidataservices/cnd/Qualcomm-IMS processes.
- The new ANM/NRM/DNC clients bound successfully to services in the old qtidataservices process.
- The old native IIWlan/DataModule/DSD epoch returned non-home WLAN state and did not publish IMS->IWLAN during fixed P.
- Full reboot recreates producer and consumer epochs together.

### What is not confirmed

- No exposed callback-registration ID proves that a stale callback was retained.
- The R3 log shows Java QNS and NetworkService Service creation in the old PID, so their Service-object generation was not simply old.
- There is no proof that binder death cleanup failed; successful rebind argues against total callback loss.
- There is no proof that resetting one particular provider process will restore boot ordering.
- H2 is therefore **supported as a falsifiable generation/order hypothesis, not established root cause**.

## Earliest boot-versus-R3 mismatch

The earliest directly established mismatch is below ANM:

```text
BOOT:
new qcrild2 DataModule/DSD/NAH + new qtidataservices HIDL/provider epoch
  -> new phone consumers
  -> later P can receive a natural IMS->IWLAN qualification

R3 counterexample:
old qcrild2 DataModule/DSD/NAH + old qtidataservices process/static HIDL epoch
  -> recreated QNS/NetworkService bound-Service instances
  -> new phone consumers
  -> NRM query returns NOT_REG_OR_SEARCHING; no IMS->IWLAN publication
```

The first *possible* cross-process epoch mismatch is thus the `IIWlan/slot2` callback/NAH/DSD producer relationship consumed by qtidataservices, not SST. The first *observed* functional divergence remains M1/M2 at ANM/NRM. The evidence does not justify claiming which hidden native field is wrong.

## Components prioritized by causality

1. **qcrild2 DataModule/DSD/NAH + IIWlan callback relationship** — earliest producer of both observed missing outputs.
2. **qtidataservices process/static IWlanProxy and per-slot QNS/IWLAN providers** — bridge that turns HIDL state into framework callbacks/responses.
3. **primary qcrild/shared QtiBus, cnd and Qualcomm IMS native/vendor peers** — broader boot-created telephony producer context.
4. **system_server/AP boot epoch** — upper bound, not the next candidate merely because it is broad.

This ordering is causal, not based on which PID is easiest to terminate.
