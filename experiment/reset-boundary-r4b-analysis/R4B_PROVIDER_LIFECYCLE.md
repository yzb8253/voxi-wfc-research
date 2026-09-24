# R4b qtidataservices provider lifecycle

Date: 2026-09-24

Status: static/read-only analysis only. `R4A_FALSIFIED_AT_P` and `FIRST_MISSING_MILESTONE=M1` remain frozen. The phone remains in the Cycle 2 airplane-ON P-failure scene. Phone writes: **0**.

## Conclusion

`.qtidataservices` is on the narrowed failure boundary. R4a proved that the new qcrild2 producer could publish IMS -> IWLAN to old phone PID 24403 through the still-live PID 3373 provider epoch, while new phone PID 19318 received no corresponding M1 after R3. This supports, but does not prove, an old-provider/new-consumer replay-generation mismatch.

A full `.qtidataservices` process epoch is materially different from recreating a bound QNS Service object inside the old process. It destroys the process-static `IWlanProxy.instances[]`, per-slot reference counts, production HIDL response/indication objects, registrant lists, outstanding request table, service/death-recipient relationship, and all co-hosted Java service/tracker objects. These are exactly the states that survived R3.

## Current-ROM identity

Read-only inspection of the current ROM established:

| Field | Current-ROM result |
|---|---|
| init service | **None found.** There is no `init.svc.*qtidata*` property or qtidataservices init rc entry. |
| native binary | **None.** This is an Android application process, not a vendor native daemon. |
| process name | `.qtidataservices` |
| current PID | 3373 at analysis time; this is evidence only and must never be hard-coded |
| UID | 10104 (`u0_a104`) |
| shared user | `com.qualcomm.qti.qtidataservices` |
| SELinux | `u:r:vendor_qtidataservices_app:s0:c104,c256,c512,c768` |
| parent | zygote64 (current PPID 920), not init |
| ActivityManager class | `PERS`, fixed persistent process, `maxAdj=-800` |
| restart owner | ActivityManager persistent-process/service recovery |
| critical/init restart | not applicable; no init service and no init `critical` option |

The persistent anchor is `com.qualcomm.qti.cne`: its package has the `PERSISTENT` flag and starts `CneApp` from the direct-boot `LOCKED_BOOT_COMPLETED` receiver. Historical current-ROM evidence confirms that after exact PID death ActivityManager logged `Re-adding persistent process`, started a new `.qtidataservices` process about 30 ms later, and rebound it about 74 ms after death.

## Actual hosted scope

The live ActivityManager process record lists all three signed packages under the shared UID and process:

- `vendor.qti.iwlan` from `/vendor/app/IWlanService/IWlanService.apk`;
- `com.qualcomm.qti.cne` from `/vendor/app/CneApp/CneApp.apk`;
- `vendor.qti.hardware.cacert.server` from `/vendor/app/CACertService/CACertService.apk`.

The same PID currently hosts:

| Component | Role |
|---|---|
| `vendor.qti.iwlan/.QualifiedNetworksServiceImpl` | Android QualifiedNetworksService; creates per-slot NetworkAvailabilityProvider objects and publishes qualified transports to ANM |
| `vendor.qti.iwlan/.IWlanNetworkService` | WLAN NetworkService; answers NRM registration queries and indications |
| `vendor.qti.iwlan/.IWlanDataService` | WLAN DataService; serves DNC/DataServiceManager data-call operations |
| `com.qualcomm.qti.cne/.CneApp` | Java CNE endpoint and DataCallAgent/Connectivity bridge for native cnd requests |
| `vendor.qti.hardware.cacert.server/.CACertService` | unrelated CA certificate service, but unavoidably co-restarted |

All three IWLAN services are currently bound by `com.android.phone`. CneApp is a started persistent service. This is shared process scope across both slots, not a slot1-only process.

## QNS provider construction and initial publication

Static inspection used a host copy whose SHA-256 `28BD393231B75C1F826D82F9115D5C5ADB5F0B8967A20D247656265A01F246C6` exactly matches the live `/vendor/app/IWlanService/IWlanService.apk`. It gives the exact provider sequence:

```text
QualifiedNetworksServiceImpl.onCreateNetworkAvailabilityProvider(slot)
  -> new NetworkAvailabilityProviderImpl(slot)
       -> IWlanProxy.getInstanceBySlotId(context, slot)
       -> create provider HandlerThread/Handler
       -> IWlanProxy.getAllQualifiedNetworks(message=EVENT_GET_COMPLETE)
       -> IWlanProxy.registerForQualifiedNetworksChanged(handler, EVENT_CHANGED)
```

This answers the four lifecycle questions:

1. **Active current-state query: YES.** Provider construction calls `getAllQualifiedNetworks`.
2. **Wait only for the next modem indication: NO.** A query is issued before indication registration.
3. **Initial state comes from qcrild2: YES.** `IWlanProxy.getAllQualifiedNetworks` calls `IIWlan/slot2.getAllQualifiedNetworks(serial)`, which reads the new producer's native NetworkAvailabilityHandler cache.
4. **Framework republication path exists: YES, conditionally.** Both the query completion and later indication paths call the same `updateQualifiedNetworks(list)`, which calls framework `updateQualifiedNetworkTypes(apnMask, networks)`.

“Conditionally” matters: the APK implements the path, but no source establishes that every rebind of a new phone consumer receives an already-published old Java value. R4a is direct evidence that the required IMS -> IWLAN publication did not reach the new phone consumer. The Android base-service Binder callback state and timing are not exposed as a generation ID, so the precise internal reason remains unobservable.

## Process-cold objects

The following are necessarily new after the old process is gone and a new process is started:

- class statics `IWlanProxy.instances[]`, `instanceRefCount[]`, and modem-support flag initialization;
- one new per-slot `IWlanProxy`, when the first provider/service requests it;
- new `IWlanResponse`, `IWlanIndication`, death recipient, request list, serial/wakelock counters, and three registrant lists;
- a new HIDL connection to `IIWlan/slot2`, new death cookie, and production `setResponseFunctions(newResponse,newIndication)` registration;
- new `QualifiedNetworksServiceImpl` and slot1 `NetworkAvailabilityProviderImpl` with a new handler thread;
- a new initial `getAllQualifiedNetworks` request/response and conversion into framework updates;
- new IWlan NetworkServiceProvider and DataServiceProvider objects when framework creates them;
- new CneApp, CNE Java connector, trackers and callback endpoint;
- new framework-facing Binder endpoints for the three IWLAN services.

The native qcrild2 NetworkAvailabilityHandler/cache is deliberately **not** recreated by this step; it was recreated immediately before it by the R4b producer stage.

## Qualified-network conversion

`NetworkAvailabilityProviderImpl.updateQualifiedNetworks` consumes the native list as follows:

- entries with a non-empty network vector are grouped by preferred network and published with `updateQualifiedNetworkTypes(apnMask, [network])`;
- entries with an empty/null network vector are combined and published with `updateQualifiedNetworkTypes(apnMask, null)`;
- the current implementation uses the first network in the native vector as the preferred network.

Therefore provider readiness must prove that the production query completed and was processed, but it must not require IMS -> IWLAN before fixed P. In the canonical pre-P state an empty or terrestrial qualification can be valid. M1 remains an outcome milestone after P, not a provider-stage gate.

## Observable versus unobservable

Observable evidence includes old/new PID and identity; ActivityManager process/service records; QNS/Network/Data service creation; slot-specific `new IWlan Proxy`; `IIWlan client connected on slot2`; the production GET request/completion; `updateQualifiedNetworkTypes` processing; HIDL service inventory; qcrild process identity; and absence of fatal/death-loop logs.

Unobservable fields must not be reported as PASS:

- native or Java object addresses/generation IDs;
- the exact Binder callback generation held internally by the Android base QualifiedNetworksService;
- the numeric identity of the production HIDL callback registration;
- proof that native cnd replayed every prior callback;
- a modem-side acknowledgement that no indication occurred in the small query-before-register interval.

## Answers to the H3 questions

1. **Is qtidataservices on the known failure boundary?** YES. It is the surviving bridge between the proven-working new producer and the new consumer that missed M1.
2. **Does it hold state across framework reconstruction?** YES. PID 3373 and its process-static proxies, registries and HIDL callbacks survived R3, even though individual bound Service objects were recreated.
3. **Should an old provider theoretically replay to a new consumer?** The Android/vendor path provides initial query and publication when a NetworkAvailabilityProvider is constructed, but a guaranteed replay of an already-published value to every new framework generation is not proven.
4. **Does R4a fit missing replay/republication?** YES. Old phone received live M1 after producer reset; new phone did not receive M1 after R3.
5. **Does process restart form a real new provider epoch?** YES structurally, because it destroys all process statics/proxies/callback registries and reconstructs production bindings and the initial native-cache query.
6. **Is producer -> provider -> consumer the dependency order?** YES; the data and registrations flow in that direction.
7. **Is R4b a causal reset rather than a workaround?** YES. It injects no ANM/QNS result and changes no timeout or recovery logic; it reconstructs the dependency epochs in boot-like order.
8. **Is there a smaller equally complete reset?** No verified one. Service unbind/rebind is smaller but R3 already recreated service objects inside the old PID and left process statics/HIDL ownership alive. No public command/Binder method atomically destroys all three shared per-slot providers, proxy statics, callbacks, and trackers.

## Evidence anchors

- `experiment/reset-boundary-r4a/R4A_V2_COUNTEREXAMPLE.md`
- `experiment/reset-boundary-r4a/runs/r4a_3cycle_v2/RESULT.md`
- `experiment/reset-boundary-r4-analysis/BOOT_RESET_DEPENDENCY_GRAPH.md`
- `autopilot/phase8b_restart_cne/PHASE8B_CNE_RESTART_RESULT.md`
- current-ROM package/process/service inventory captured read-only on 2026-09-24
- current `/vendor/app/IWlanService/IWlanService.apk` static method inspection
