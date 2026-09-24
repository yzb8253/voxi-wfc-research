# Target-ROM QNS provider and callback lifecycle

Date: 2026-09-24

Scope: target-ROM `framework.jar` and exact `IWlanService.apk` static inspection, correlated with R4b Cycle 1.
Phone writes: **0**

## Framework service ownership

`android.telephony.data.QualifiedNetworksService` owns a Service-instance `SparseArray` named `mProviders`, keyed by slot index. Each `NetworkAvailabilityProvider` owns one `IQualifiedNetworksServiceCallback mCallback`, one `SparseArray<int[]> mQualifiedNetworkTypesList`, and its slot index. This cache belongs to the individual QNS Service/provider object; it is not the qcrild2 native NetworkAvailabilityHandler dump cache.

## Create behavior when a slot already exists

The target ROM matches the relevant AOSP behavior:

1. The handler checks `mProviders.get(slot)`.
2. If non-null, it logs `Network availability provider for slot <n> already existed.`
3. It returns immediately.
4. It does **not** replace the callback and does **not** call `registerForQualifiedNetworkTypesChanged()` on that existing object.

If absent, it calls the vendor factory, stores the returned provider, then calls `registerForQualifiedNetworkTypesChanged(callback)`.

## Callback registration and replay

`registerForQualifiedNetworkTypesChanged(callback)` assigns the callback, then synchronously iterates every entry already present in `mQualifiedNetworkTypesList` and invokes `onQualifiedNetworkTypesChanged()`. A fresh callback therefore receives only values cached in that same provider object. A native NAH value that never arrived through `updateQualifiedNetworkTypes()` is not replayable.

`onUpdateQualifiedNetworkTypes()` first updates `mQualifiedNetworkTypesList`, then calls the current callback. A `RemoteException` is logged, but the inspected base implementation does not clear the callback, link an explicit callback death recipient, or autonomously close the provider.

## Remove and unbind behavior

- Removing one slot calls `provider.close()` and removes it from `mProviders`.
- `QualifiedNetworksService.onUnbind()` posts remove-all; the handler calls `close()` on every provider and clears `mProviders`.
- Vendor `NetworkAvailabilityProviderImpl.close()` logs `QNP Service Closing`, unregisters its handler from `IWlanProxy`, and releases/disables its proxy reference.

The base provider has no independent callback-death cleanup path. Service binding teardown is what should drive provider closure.

## Vendor provider construction

The target vendor provider constructor does this in order:

```text
IWlanProxy.getInstanceBySlotId(slot)
create provider HandlerThread/Handler
IWlanProxy.getAllQualifiedNetworks(EVENT_GET_COMPLETE)
IWlanProxy.registerForQualifiedNetworksChanged(EVENT_CHANGED)
```

Both query completion and later change indications converge on `updateQualifiedNetworks()`, which eventually calls framework `updateQualifiedNetworkTypes()` for converted groups.

## What happened in R4b Cycle 1

### Old phone epoch

- qtidataservices PID 23859 created its first slot1 provider at 21:41:35.014 while old phone PID 3448 lived.
- Its framework callback therefore belonged to phone PID 3448.
- Initial query response serial 0 completed with a zero-entry payload.

### Phone death and new epoch

- phone PID 3448 died at 21:43:26.231.
- No `QNP Service Closing`, vendor unregister, explicit Binder-death, or callback `RemoteException` was found in the captured transition.
- new phone PID 27795 started at 21:43:26.265.
- ANM-0 bound at 21:43:27.496 and caused a new `QualifiedNetworksService` object at 21:43:27.500.
- ANM-1 bound at 21:43:27.922.
- a **fresh slot1 provider** was created at 21:43:28.501; no `already existed` message was observed.
- that fresh provider issued query serial 6; its response was also a zero-entry payload.

The old provider did not visibly close, but the new phone did not reuse it. A new Service object has a new `mProviders` array; the new slot1 provider registered a fresh callback for phone PID 27795.

## Callback replacement and replay answers

There was no “replace callback on an existing provider” operation. The old provider/callback belonged to phone PID 3448, while a newly constructed provider/callback belonged to PID 27795.

The target framework would replay entries cached in the new provider. The new provider's initial IIWlan response contained zero entries, so there was no IMS qualification to cache and no IMS -> IWLAN value to replay. M1 did not occur. This is not evidence that replay code failed after holding a valid IMS cache; it is evidence that the fresh provider never received the required initial value.

## Residue still visible

The qtidataservices process-static `IWlanProxy` survived phone death. Its slot1 reference count rose when new QNS/Network/Data providers were created, while no matching old-provider close was logged. This is a lifecycle-cleanliness concern, but its causal role is unproven and secondary to the directly observed empty IIWlan responses.
