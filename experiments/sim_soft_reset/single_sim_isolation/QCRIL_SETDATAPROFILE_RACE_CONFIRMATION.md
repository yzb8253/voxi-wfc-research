# QCRIL SETDATAPROFILE RACE CONFIRMATION

Date: 2026-09-20

Device scope: VOXI slot 1 / phoneId 1 / subId 11

Method: read-only analysis of the retained successful-WFC `logcat -b all` buffers plus the current-ROM static call graph. No SIM, process, Binder/HIDL write, radio, modem, or reboot action was performed.

## Executive finding

The proposed race—first insertion's `setDataProfile` missing `NetworkAvailabilityHandler`, then the second insertion's `setDataProfile` repairing the QNS cache—is **not confirmed and is materially weakened**.

Both insertions caused Android to build the same three-profile list, including `Vodafone UK IMS` (`apn=ims`, type `ims`), send `SET_DATA_PROFILE` for SUB1 multiple times, and receive successful RIL responses. More decisively, the successful second-insertion QNS callback occurred **before** that insertion's first framework profile dispatch:

```text
20:52:24.821  PS/WLAN reports HOME over IWLAN
20:52:24.825  ANM-1 onQualifiedNetworkTypesChanged: ims -> IWLAN
20:52:24.826  ANM-1 setPreferredTransports: ims -> WLAN
20:52:24.880  DNC-1 IMS preferred on WLAN
20:52:25.166  first second-insertion SET_DATA_PROFILE request
```

The QNS success callback leads the second-insertion profile request by 341 ms. It therefore cannot have been caused by that request traversing `DataModule -> NetworkAvailabilityHandler`.

The earliest concrete first/second divergence remains the DSD/QNS qualified-network path: both runs reached `IWLAN/HOME`, but only the second produced `qualifiedNetworksChangeIndication`/`onQualifiedNetworkTypesChanged` for IMS. The evidence moves the fault boundary to DSD APN availability/preferred-system indication or its synchronization with the already populated NetworkAvailability cache.

## Evidence standard and limitations

- Framework and RIL transaction logs are present and timestamped to milliseconds.
- `SET_DATA_PROFILE` success proves the vendor radio request was accepted and completed through QCRIL's DataModule dispatch path.
- This ROM does not emit the internal C++ symbol names `handleSetDataProfileRequestMessage`, `processSetDataProfileRequest`, `updateNetworkAvailabilityCache`, or `setProfileSupportedAPNTypes` into Android logcat. Those individual internal branches therefore cannot honestly be marked as directly observed.
- `NetworkAvailabilityHandler` and `ProfileHandler` branch results are recorded as `UNKNOWN`, not inferred from a successful top-level RIL response.
- Java QNS was created and reported AP-assisted operation for slot 1 at 20:49:20, before either insertion. No per-insertion native `IWLANCapabilityHandshake`, `initializeIWLAN`, or DSD indication-registration log is exposed; native registration state is therefore `UNKNOWN`.
- Raw logs are intentionally not committed because they contain subscriber data. This report contains only sanitized evidence.

## === FIRST INSERT SETDATAPROFILE TRACE ===

Time: 20:51:00.577 SIM present through 20:52:00.323 removal

Framework sent setDataProfile: **YES**

- 20:51:05.245 `DPM-1: updateDataProfilesAtModem: set 3 data profiles`
- 20:51:05.245 `QtiDSM-C-1: setDataProfile`
- Repeated at 20:51:07.303 and 20:51:07.502.

QCRIL received SetDataProfileRequestMessage: **YES (top-level transaction evidence)**

- 20:51:05.246 `[1][0231]> SET_DATA_PROFILE ... [SUB1]`
- 20:51:05.434 `[1][0231]< SET_DATA_PROFILE [SUB1]`
- Requests 0268 and 0273 also completed successfully.
- Static routing maps this HIDL request to `SetDataProfileRequestMessage`.

DataModule handler: **YES (architectural routing plus completed QCRIL response; internal entry log absent)**

ProfileHandler: **UNKNOWN**

NetworkAvailabilityHandler processSetDataProfileRequest: **UNKNOWN**

updateNetworkAvailabilityCache: **UNKNOWN**

IMS APN visible: **YES**

- 20:51:05.242 `DPM-1` added `Vodafone UK IMS`, DNN/APN `ims`, APN type `ims`.
- 20:51:05.244 the complete three-profile list contained Data, IMS, and EIMS.
- The RIL request logged the same IMS profile.

AP-assist initialization state: **READY at Java QNS boundary; native DataModule readiness UNKNOWN**

- 20:49:20.358 `ANM-1: operates in AP-assisted mode`, before the first insertion.

DSD indication registration: **UNKNOWN**

qualifiedNetworksChangeIndication: **NO**

- No `ANM-1 onQualifiedNetworkTypesChanged` for IMS occurred from first present through removal.

## === SECOND INSERT SETDATAPROFILE TRACE ===

Time: 20:52:20.569 SIM present through WFC recovery

Framework sent setDataProfile: **YES**

- First dispatch: 20:52:25.165/20:52:25.166.
- Repeated at 20:52:27.288 and 20:52:27.463.

QCRIL received SetDataProfileRequestMessage: **YES (top-level transaction evidence)**

- 20:52:25.166 `[1][0396]> SET_DATA_PROFILE ... [SUB1]`
- 20:52:25.252 `[1][0396]< SET_DATA_PROFILE [SUB1]`
- Requests 0436 and 0441 also completed successfully.

DataModule handler: **YES (architectural routing plus completed QCRIL response; internal entry log absent)**

ProfileHandler: **UNKNOWN**

NetworkAvailabilityHandler processSetDataProfileRequest: **UNKNOWN**

updateNetworkAvailabilityCache: **UNKNOWN**

IMS APN visible: **YES**

- 20:52:25.163 `DPM-1` added the same `Vodafone UK IMS` profile.
- 20:52:25.165 the same Data/IMS/EIMS three-profile list was built.

AP-assist initialization state: **READY at Java QNS boundary; native DataModule readiness UNKNOWN**

DSD indication registration: **UNKNOWN**

qualifiedNetworksChangeIndication: **YES**

- 20:52:24.825 `ANM-1: onQualifiedNetworkTypesChanged: apnTypes=[ims], networks=[IWLAN]`.
- This was 341 ms before the second insertion's first `SET_DATA_PROFILE` request.

## Requested T1-T8/T9 timeline

### First insertion

| Label | Time | Observation |
|---|---:|---|
| T1 SIM PRESENT | 20:51:00.577 | Slot 1 reports `CARDSTATE_PRESENT`. |
| T2 framework setDataProfile | 20:51:05.245-05.246 | Three profiles sent; IMS profile present. Replays at 07.303 and 07.502. |
| T3 QCRIL DataModule | 20:51:05.246-05.434 | Request/response completed; internal C++ entry log absent. |
| T4 NetworkAvailabilityHandler | UNKNOWN | No branch-specific log. |
| T5 IWLANCapabilityHandshake | Before insertion / UNKNOWN exact time | QNS was already AP-assisted by 20:49:20.358. Native handshake log absent. |
| T6 initializeIWLAN | Before insertion / UNKNOWN exact time | No per-insertion initialization event observed. |
| T7 DSD indication registration | UNKNOWN | No direct register log. |
| T8 IWLAN HOME | 20:51:04.777 | PS/WLAN registration returns HOME/IWLAN. |
| QNS outcome | None through 20:52:00.323 | No IMS -> IWLAN qualified-network callback. |

### Second insertion

| Label | Time | Observation |
|---|---:|---|
| T1 SIM PRESENT | 20:52:20.569 | Slot 1 reports `CARDSTATE_PRESENT`. |
| T2 framework setDataProfile | 20:52:25.165-25.166 | Same three profiles sent; IMS profile present. Replays at 27.288 and 27.463. |
| T3 QCRIL DataModule | 20:52:25.166-25.252 | Request/response completed; internal C++ entry log absent. |
| T4 NetworkAvailabilityHandler | UNKNOWN | No branch-specific log. Importantly, T9 already occurred before T2/T3. |
| T5 IWLANCapabilityHandshake | Before insertion / UNKNOWN exact time | Same pre-existing AP-assisted QNS instance. |
| T6 initializeIWLAN | Before insertion / UNKNOWN exact time | No per-insertion initialization event observed. |
| T7 DSD indication registration | UNKNOWN | No direct register log. |
| T8 IWLAN HOME | 20:52:24.821 | PS/WLAN registration returns HOME/IWLAN. |
| T9 qualifiedNetworks IMS -> IWLAN | 20:52:24.825 | QNS callback follows HOME by 4 ms and precedes T2 by 341 ms. |

The T-labels describe requested logical stages, not the observed chronological order. In the successful run the observed order is `T1 -> T8 -> T9 -> T2 -> T3`, which directly weakens a second-dispatch setDataProfile race.

## Strict differential

### Framework profile dispatch

Not the first divergence. Both insertions built and sent the same IMS-bearing profile list, with successful RIL responses. Case C is rejected.

### QCRIL profile/cache branch

Case A is not demonstrated. Android logs do not expose the internal `NetworkAvailabilityHandler` branch, and the successful callback predates the second insertion's profile dispatch. Even if the second dispatch later entered the handler, it cannot explain the earlier T9 event.

The first insertion's successful profile requests may have populated or preserved the native cache, but this cannot be proven from the available branch-level logging.

### AP-assist readiness

The slot-1 QNS was already AP-assisted before both insertions. No QNS/qtidataservices process restart or new service creation separates the two insertion windows. An initialization race is therefore possible only inside an unlogged native/QMI registration state, not at the visible Java QNS creation boundary.

### DSD indication/cache synchronization

This is now the leading boundary. First insertion reached IWLAN/HOME at 20:51:04.777 without an IMS qualified-network callback. Second insertion reached IWLAN/HOME at 20:52:24.821 and emitted IMS -> IWLAN four milliseconds later, before any second-insertion profile dispatch. That ordering is consistent with a DSD APN-availability/preferred-system indication or cache replay triggered by the UICC lifecycle, not a fresh framework profile write.

## === SETDATAPROFILE RACE VERDICT ===

FIRST INSERT:

Framework dispatched three successful `SET_DATA_PROFILE` transactions containing the IMS APN. IWLAN/HOME appeared, but no IMS qualified-network callback followed. Internal ProfileHandler/NetworkAvailabilityHandler branch logging is absent.

SECOND INSERT:

IWLAN/HOME appeared at 20:52:24.821 and IMS -> IWLAN qualified networks at 20:52:24.825. The first new `SET_DATA_PROFILE` was not sent until 20:52:25.166, so it was downstream in time and cannot be the cause of the QNS callback.

First concrete divergence:

`IWLAN/HOME -> qualifiedNetworksChangeIndication(IMS,[IWLAN])` was emitted only on the second insertion. The concrete divergence is at the DSD/QNS qualified-network indication/cache boundary, not framework profile construction or dispatch.

Race hypothesis: **WEAKENED**

Missing component: **DSD APN indication / NetworkAvailability cache synchronization**

`SETDATAPROFILE_QNS_RACE = NOT CONFIRMED`

Confidence: **HIGH** for rejecting the second-insertion profile dispatch as the direct trigger; **MEDIUM** for assigning the remaining fault specifically between DSD indication delivery and cache synchronization because native branch/QMI logs are absent.

## NEXT_SAFE_TRIGGER

Candidate only; not executed:

Use the existing slot-1 QNS/IIWlan **read-semantics cache query** `IIWlan.getAllQualifiedNetworks(serial)` through the current `IWlanProxy`, after separately proving a fixed slot-1 invocation path and auditing that it performs no profile/QMI write. This is preferable to `setDataProfile`: static analysis shows it reads the native qualified-network cache and returns it to Java, while `setDataProfile` modifies modem WDS profile state and is now temporally excluded as the successful trigger.

Interpretation for a future separately authorized test:

- If the cache query returns `IMS -> IWLAN` and Java applies it, the missing boundary is callback delivery/replay.
- If the cache query lacks IMS despite IWLAN/HOME, the missing boundary is DSD APN availability/preferred-system state or its native cache update.
- The query is not a modem re-evaluation API and must not be represented as one.

No candidate was executed in this phase.
