# Boot provider/consumer order on the target ROM

Date: 2026-09-24

Source: retained CONTROL_A0_R4B_V2 reboot log evidence plus target-ROM construction semantics.
Phone writes: **0**

## Result

The real boot lifecycle is **consumer-driven provider construction (model B)**, not a provider object created independently before the framework consumer. The `.qtidataservices` host process starts slightly before `com.android.phone`, but its per-slot QNS provider is created only after ANM binds and invokes the QNS create-provider Binder path.

## Retained boot timeline

| Time | Boot event |
|---|---|
| 21:38:50.679 | qcrild2 `RIL_register` |
| 21:38:50.692 | radio HIDL service registration |
| 21:38:52.077 / .289 | early `DSD Client unavailable` during producer bring-up |
| 21:38:54.792 | `.qtidataservices` PID 3385 started |
| 21:38:54.843 | `com.android.phone` PID 3448 started |
| 21:38:55.630 | phone connected to radio via `setResponseFunctions` |
| 21:38:55.831 | ANM-0 constructed |
| 21:38:56.125 | ANM-1 constructed |
| 21:38:56.799 | ANM-0 initiated vendor QNS bind |
| 21:38:56.803 | QNS Service object constructed in qtidataservices |
| 21:38:57.195 | ANM-1 initiated vendor QNS bind |
| 21:38:59.994 | first retained ANM-1 qualified-network event, including IMS -> EUTRAN |
| 21:39:02.313 | later ANM-1 update: IMS/emergency -> EUTRAN, default group -> NGRAN |

The old qtidataservices internal debug ring was lost when R4b later restarted that process, so boot-time provider-query serials are not recoverable from the current Service dump. The construction direction is nevertheless fixed by target code: ANM's service connection calls `createNetworkAvailabilityProvider(slot, callback)`; only that message invokes the vendor provider factory.

## Boot dependency order

```text
qcrild2 producer/HIDL service ready enough to accept clients
        v
qtidataservices host process available
        v
com.android.phone starts and creates ANM objects
        v
ANM binds QNS and requests a provider for each slot
        v
QNS Service constructs vendor per-slot provider
        v
IWlanProxy connects IIWlan, sends initial query, registers indication handler
        v
provider publishes updateQualifiedNetworkTypes
        v
ANM receives qualified-network event
```

The process birth order (`qtidataservices` 51 ms before phone) must not be confused with provider-object order. At boot, the consumer triggers provider construction.

## Comparison with R4b

R4b's first provider was created by the still-old phone consumer, then R3 killed that consumer. This differs from boot. However, the new phone subsequently created another fresh Service/provider and query, so the order difference did not leave the new consumer permanently attached only to the old provider.

The remaining concrete difference is payload state: the fresh serial-6 initial query returned zero entries. Boot reached actual ANM publications; R4b's new provider did not receive content to publish.

## Consequence for reset design

A future coordinated reset should avoid old/new epoch overlap and preserve boot's consumer-driven construction. But order-only redesign is not yet ready for execution, because a fresh new-consumer-driven provider already returned an empty IIWlan response in R4b. That lower response/cache mismatch must be explained first.
