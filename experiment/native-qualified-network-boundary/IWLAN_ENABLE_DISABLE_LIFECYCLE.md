# Target-ROM IWLAN enable/disable lifecycle

Date: 2026-09-24
Phone writes: **0**

## Enable path

Target binary symbols establish this path:

1. `IWlanImpl::setResponseFunctions` / `setResponseFunctions_nolock` installs the HIDL response and indication objects plus death recipient.
2. It dispatches `IWLANCapabilityHandshake(true)`.
3. `DataModule::handleIWLANCapabilityHandshake(...)` calls `initializeIWLAN()` after its readiness gates pass.
4. `DataModule::initializeIWLAN()`:
   - resolves the pending handshake;
   - calls `DSDModemEndPoint::registerForAPAsstIWlanIndsSync(true)`;
   - allocates a **new** `NetworkAvailabilityHandler` and replaces/destroys any existing handler at the DataModule member slot;
   - replays cached DSD system status into the new handler only when the DataModule's cached-status valid flag is already true;
   - invokes the data-control enable callback.

Crucially, `initializeIWLAN()` does not itself request a fresh DSD system status. A new handler can therefore be alive and queryable while both its current caches remain empty if the cached DSD status is invalid and no fresh indication has yet arrived.

## Disable path

`IWlanImpl::iwlanDisabled()` dispatches `IWLANCapabilityHandshake(false)`. `DataModule::deinitializeIWLAN()` then:

- unregisters AP-assist IWLAN indications with `registerForAPAsstIWlanIndsSync(false)`;
- destroys/resets the current `NetworkAvailabilityHandler`;
- invokes the disable callback.

The Java provider `close()` path can decrement the process-static `IWlanProxy` reference count and, when the last user disappears, invoke this HIDL disable path.

## HIDL callback death is not disable

`IWlanImpl::IWlanDeathRecipient::serviceDied(...)` calls `clearResponseFunctions()`. Target disassembly shows that `clearResponseFunctions()` clears the HIDL response/indication references and resets callback/wakelock state, but does **not** call `iwlanDisabled()` and does not deinitialize the NAH.

In R4b, terminating the whole qtidataservices process caused callback death rather than an orderly provider `close()`. The preserved timeline has no current-epoch evidence for:

- `QNP Service Closing`;
- `iwlanDisabled()`;
- AP-assist deregistration;
- a clean disable handshake.

Accordingly, direct `iwlanDisabled()` participation is **NOT OBSERVED** and is not needed to explain the result.

## What reset the cache in R4b

After the new qtidataservices process connected, its new `setResponseFunctions(...)` executed the enable handshake. `initializeIWLAN()` then replaced the old NAH with a new empty NAH at 21:41:35.048. This is sufficient to explain why the old generation remains visible in the process history while the live/current dump is empty.

The supported sequence is:

```text
old qtidataservices dies
-> native callback death clears response functions (no proven disable)
-> new qtidataservices installs response functions
-> IWLANCapabilityHandshake(true)
-> initializeIWLAN
-> new NAH replaces old NAH
-> initial GET reaches new NAH before population/publication
```

There is no evidence for the proposed state “old current NAH cache preserved, but a distinct query cache was cleared by iwlanDisabled.” Both current containers belong to the replacement handler and are empty.
