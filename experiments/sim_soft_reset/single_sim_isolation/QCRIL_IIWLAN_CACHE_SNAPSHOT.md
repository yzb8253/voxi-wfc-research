# QCRIL IIWLAN Qualified-Network Cache Snapshot

Date: 2026-09-20

Branch: `voxi-wfc-auto-recovery`

Target: fixed `IIWlan/slot2` / VOXI slot 1

Mode: read-only; phone writes: **0**

## Result

The current native QCRIL `NetworkAvailabilityHandler` cache contains an IMS APN entry, but its qualified-network list is empty:

```text
NetworkAvailabilityHandler:
    globalPrefSys= IWLAN
    NetworkAvailabilityCache ==>
    apn=sos ... networks=[]
    apn=ims ... networks=[]
    apn=wap.vodafone.co.uk ... networks=[]
    LastReportedNetworkAvailability ==>
```

Verdict: **`NATIVE_QNS_CACHE = STALE`**.

This rules out the narrower hypothesis that the native cache is currently healthy with `IMS -> [IWLAN]` and only Java provider/ANM replay is missing. The cache knows the IMS APN, and the handler's global preferred system is IWLAN, but the per-APN IMS qualified-network list has not retained or reconstructed IWLAN.

## Static query audit

### Native request path

The current-ROM binaries were inspected locally. The relevant path is:

```text
IWlanImpl::getAllQualifiedNetworks(serial)
  -> GetAllQualifiedNetworkRequestMessage
  -> DataModule::handleGetAllQualifiedNetworksMessage(...)
  -> NetworkAvailabilityHandler::getQualifiedNetworks(output)
  -> QualifiedNetworkResult_t solicited response
  -> IWlanResponse::getAllQualifiedNetworksResponse(...)
```

Findings:

- `IWlanImpl::getAllQualifiedNetworks(int)` constructs and dispatches a request message. It does not call `setResponseFunctions`.
- `DataModule::handleGetAllQualifiedNetworksMessage` checks readiness and the handler pointer, then calls `NetworkAvailabilityHandler::getQualifiedNetworks`.
- `NetworkAvailabilityHandler::getQualifiedNetworks` iterates the in-memory cache, copies entries into the result vector, and logs the returned entries. No cache update or QMI request is present in this path.
- The solicited response is delivered to the already registered global `IWlanResponse`. A second client does not receive a private response unless it replaces the callback, which was explicitly forbidden.
- `setResponseFunctions` was not called. The existing `.qtidataservices` response/indication callback remained untouched.

Static query audit: **PASS** for read semantics, but no zero-write generic shell client was found for directly invoking the HIDL business method.

## Zero-disturbance observation path

ROM inventory found no `cmd`, Binder shell command, vendor diagnostic binary, or pre-existing device helper that exposes `getAllQualifiedNetworks`. Uploading a helper would have violated the zero-phone-write constraint.

The standard HIDL `IBase::debug` entry was therefore used once:

```text
lshal debug vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot2
```

This did not invoke `getAllQualifiedNetworks`, did not register or replace any callback, and did not rebuild a provider. The HAL's existing debug implementation directly exposed `NetworkAvailabilityHandler::dumpCache()` state, including the complete cache, last-reported list, InitTracker state, and internal bounded history.

Supporting current native state:

```text
globalPrefSys=IWLAN
RegistrationState=REG_HOME
AuthServiceReady=true
DsdServiceReady=true
WdsServiceReady=true
IWLANEnabled=true
ModemCapability=true
CurrentDDS=1
LastReportedNetworkAvailability=[]
```

Thus service readiness and global IWLAN preference are present while the APN-level cache remains empty.

## Historical contrast retained by the same dump

The handler's internal history preserves the successful second-insert transition:

```text
20:52:24.703 Updated network list for apn=ims ... networks=[IWLAN,UNKNOWN,]
20:52:24.818 type=IMS networks=[IWLAN,UNKNOWN,]
```

The current dump instead shows `apn=ims ... networks=[]`. This is direct evidence that the successful per-APN qualification existed previously but is absent from the current cache; it is not merely hidden from Android's ANM callback.

## Current framework and WFC state

The existing read-only probe reported:

- subscription active and UICC applications enabled;
- PS/WLAN `HOME`, radio data technology `IWLAN`;
- `mIsIwlanPreferred=true`, so the current framework-side IMS preferred transport is WLAN;
- IMS `NOT_REGISTERED`, registration transport unknown;
- VOICE/IWLAN unavailable and WFC unavailable;
- failure class F1.

This apparent mismatch is important: framework service state still says IWLAN is preferred, while the current native per-APN QNS cache has no network for IMS.

## Required result block

```text
=== QCRIL IIWLAN CACHE SNAPSHOT ===

Static query audit:
PASS

Existing callback preserved:
YES

setResponseFunctions called:
NO

getAllQualifiedNetworks executed:
NO

Response captured:
NO (not executed; complete cache captured through existing IBase::debug/dumpCache)

Qualified networks:

IMS:
present YES
networks:
[]

DEFAULT:
present YES (wap.vodafone.co.uk; DEFAULT|MMS|SUPL|HIPRI)
networks:
[]

EIMS:
present YES (sos; EMERGENCY)
networks:
[]

Native cache verdict:
STALE

Framework ANM current:
IMS preferred transport:
WLAN (mIsIwlanPreferred=true)

Current WFC:
UNAVAILABLE; IMS NOT_REGISTERED; transport UNKNOWN; VOICE/IWLAN unavailable; F1

Interpretation:
The native cache contains the IMS APN but no IWLAN qualification. The fault is below Java replay/ANM delivery: DSD APN preferred-system/availability calculation, indication delivery, or synchronization into NetworkAvailabilityHandler is stale. Replaying a healthy native cache is not the correct next hypothesis.

NEXT_SAFE_ACTION:
Read-only/static trace of the DSD indication-to-NetworkAvailabilityHandler cache-update path, using the now-proven IBase::debug snapshot before and after naturally occurring lifecycle events. Do not replay setDataProfile and do not trigger a refresh/write API.

Phone writes performed:
0
```
