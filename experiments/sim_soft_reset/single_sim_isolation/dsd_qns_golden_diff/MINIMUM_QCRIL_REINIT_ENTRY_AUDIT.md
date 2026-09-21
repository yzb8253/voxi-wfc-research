# Minimum QCRIL Reinit Entry Audit

Date: 2026-09-21

## Scope

This audit is limited to the current-ROM QCRIL data path identified as `/vendor/lib64/libril-qc-hal-qmi.so`, loaded by `/vendor/bin/hw/qcrild -c 2` for the fixed `IIWlan/slot2` service. SELinux allowed metadata inspection but denied reading the current binary, so implementation detail below is source-correlated rather than a byte-for-byte current-binary decompilation.

The narrow source reference is Qualcomm `qcril-data-hal` mirror revision `36fc163a534963a5b3af52186af5efcc63401ad2`. Its class names, method names, log strings, dump layout, and observed runtime behavior match the current ROM artifacts.

No phone write or QCRIL business method was executed.

## Ownership and lifetime

- `DataModule` owns `networkavailability_handler` as `std::unique_ptr<NetworkAvailabilityHandler>`.
- The pointer starts null in the `DataModule` constructor.
- `initializeIWLAN()` assigns a new `NetworkAvailabilityHandler`; reassignment destroys any previous object and clears both per-APN cache and last-reported state.
- `deinitializeIWLAN()` deregisters AP-assist indications, resets the pointer, and calls `datactlDisableIWlan()`.
- `NetworkAvailabilityHandler` has no public reset/recreate/init method. Its destructor is empty; state removal is achieved by destroying the object.
- The only production caller of `deinitializeIWLAN()` is `handleIWLANCapabilityHandshake(false)`.

## Function audit

| Entry | Recreates NAH | Clears old NAH state | Registers AP-assist indications | Requests fresh DSD status | Notes |
|---|---|---|---|---|---|
| `initializeIWLAN()` | YES | YES, by unique_ptr replacement | YES | NO | Replays `mCachedSystemStatus`, then enables IWLAN through datactl. |
| `handleIWLANCapabilityHandshake(true)` | YES, when readiness gates pass | YES | YES | NO | Calls `initializeIWLAN()`; the message is emitted by fixed IIWlan `setResponseFunctions()`. |
| `handleIWLANCapabilityHandshake(false)` | destroys NAH | YES | deregisters | NO | Calls `deinitializeIWLAN()` and disables IWLAN through datactl. |
| `performDataModuleInitialization()` cold branch | YES | YES | YES | YES | Broad one-time initialization; guarded by `!mInitCompleted`, not a narrow runtime reinit. |
| `performDataModuleInitialization()` post-ready/SSR branch | NO | NO | YES | YES | Reasserts capability/registrations but keeps the existing NAH object and stale last-reported state. |
| `handleQmiDsdEndpointStatusIndMessage(OPERATIONAL)` | NO after normal boot | NO | indirectly, SSR branch | indirectly, SSR branch | Calls `performDataModuleInitialization()` only on a false-to-true DSD-ready transition. |
| `registerForAPAsstIWlanIndsSync(true)` | NO | NO | YES | NO | Sends QMI DSD indication registration for intent-to-change and AP-assist result only. |
| `sendAPAssistIWLANSupportedSync()` | NO | NO | NO | NO | Sends `QMI_DSD_SET_CAPABILITY_REQ` with AP-assist mode ON. |
| `registerForSystemStatusSync()` | NO | NO | general status only | NO | Registers ordinary DSD system-status indications. |
| `generateDsdSystemStatusInd()` | NO | NO | NO | YES | Sends DSD GET SYSTEM STATUS and broadcasts global plus per-APN results. |

## Single-entry conclusion

No single existing runtime entry satisfies all required properties.

The closest single entry is:

`IWlanImpl::setResponseFunctions()` on fixed `IIWlan/slot2`
`-> IWLANCapabilityHandshake(true)`
`-> DataModule::handleIWLANCapabilityHandshake(true)`
`-> DataModule::initializeIWLAN()`

It recreates NetworkAvailabilityHandler and re-registers AP-assist indications. It does not request fresh DSD system status. The new handler immediately replays `mCachedSystemStatus`; if that cache still begins with UNKNOWN, stale ordering can be reconstructed. This explains why rebuilding qtidataservices/IIWlan callbacks alone was not sufficient in the prior experiment.

## Minimum complete internal sequence

With the modem, radio, SIM, and AP kept running, the smallest source-level sequence that covers all required lifecycle pieces is:

1. `DSDModemEndPoint::sendAPAssistIWLANSupportedSync()`
2. `DSDModemEndPoint::registerForSystemStatusSync()`
3. `DataModule::initializeIWLAN()`
4. `DSDModemEndPoint::generateDsdSystemStatusInd()`

Effects:

- Step 1 reasserts AP-assist capability.
- Step 2 reasserts ordinary DSD status indication registration.
- Step 3 replaces the old NAH object, clears its per-APN and last-reported maps, re-registers AP-assist intent/result indications, and keeps IWLAN enabled.
- Step 4 fetches a fresh global/per-APN DSD snapshot while the new handler exists.

`deinitializeIWLAN()` is intentionally omitted from the preferred sequence because it calls `datactlDisableIWlan()` and introduces an avoidable target-path teardown. Direct `initializeIWLAN()` replacement already destroys the old unique_ptr.

## Safety and scope

- AP-side targeting is fixed: `IWlanServiceInit(instanceId)` names instance 1 as `slot2`, and the current device maps it to `/vendor/bin/hw/qcrild -c 2` / RIL instance 1.
- The NAH object and DataModule instance are therefore slot2-scoped inside qcrild.
- The QMI DSD requests used for capability and indication registration carry no explicit slot identifier in this source. Their modem-side scope cannot be proven to exclude slot0.
- The sequence does not request modem reset, radio power cycling, SIM power, AP reboot, PDC/MBN/NV/EFS writes, or subscription mutation.
- It does send QMI DSD capability/registration requests and calls `datactlEnableIWlan()`. It is not a zero-write operation.
- There is no existing shell/Binder/HIDL method exposing the complete four-step sequence. `setResponseFunctions()` exposes only the handshake/initialize subset and would also replace the live production callbacks.

## Result

Best entry: `DataModule::initializeIWLAN()`, reached through fixed-slot2 `IWLANCapabilityHandshake(true)`, plus explicit DSD capability/status registration and fresh-status generation.

Does it recreate NetworkAvailabilityHandler: YES.

Does it re-register DSD indications: YES for AP-assist indications; `registerForSystemStatusSync()` is additionally required for full status registration.

Does it clear stale per-APN ordering: YES for the old in-memory NAH maps; whether the fresh DSD response returns IWLAN first remains UNKNOWN.

Does it touch modem/radio/SIM: sends non-reset QMI DSD capability/registration/status traffic and enables IWLAN datactl; no modem/radio/SIM reset or power action.

Fixed slot2 safety: AP-side HIGH; modem-side DSD scope UNKNOWN because the QMI requests have no slot field.

Recommended first controlled test: do not call `setResponseFunctions()` from a second client. First design and statically audit a one-shot, fixed-RIL-instance-1 in-process diagnostic hook implementing only the four-step sequence above, with before/after verification of slot0 identity and immediate stop after one invocation. This is a candidate only and was not executed.