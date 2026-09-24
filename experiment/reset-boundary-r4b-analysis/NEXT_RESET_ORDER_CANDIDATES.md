# Next reset-order candidates

Date: 2026-09-24

Status: design-only; no device action authorized.
Phone writes: **0**

## Fixed constraints

- Keep `R4B_FALSIFIED_AT_P`, Cycle 1, M1 frozen.
- Do not add periodic QNS re-report, forced IMS -> IWLAN, callback injection, SST workaround, timeout extension, or an adaptive second reset.
- Do not execute R4c until the native-cache/IIWlan-response mismatch is explained.
- Any later experiment must start a new series and use one frozen order for every cycle.

## ORDER-A: executed R4b

```text
R0 -> qcrild2 cold producer -> qtidataservices cold process/provider while old phone lives
   -> R3 new phone consumer -> fixed P
```

Result: **falsified at Cycle 1 P/M1**. First provider query serial 0 and new-phone fresh provider query serial 6 both had empty responses, while the native NAH debug cache exposed IMS `[EUTRAN,IWLAN]`. ORDER-A must not be rerun unchanged.

## ORDER-B: consumer-driven, boot-shaped coordinated epochs

Conceptual order:

```text
R0
-> qcrild2 cold producer and verified producer readiness
-> terminate exact old phone consumer once
-> after new phone PID birth but before its ANM QNS bind, terminate exact old qtidataservices PID once
-> ActivityManager creates new qtidataservices process
-> new phone ANM drives fresh QNS/provider construction
-> verify one new provider <-> one new consumer relationship
-> A_READY -> fixed P -> unchanged v2.6.2 only if P passes
```

Why this shape: on target boot, the qtidataservices host exists before ANM binds, but ANM drives per-slot provider creation. The observed post-phone-birth/pre-QNS-bind interval was roughly 1.2 seconds.

Risks and limitations:

- Coordination is timing-sensitive and must use event gates, not fixed sleeps.
- If ANM binds before old qtidataservices death, the candidate is invalid and must fail closed.
- qtidataservices is a shared both-slot process.
- This order does not explain why a fresh serial-6 query returned zero entries; it is **not recommended for immediate execution**.

Required proof before any ORDER-B run: both old PIDs gone; no old QNS relationship remains; new provider creation is after both old PIDs are gone; query request/response content is captured rather than inferred; any race or unobservable ownership fails closed.

## ORDER-C: analysis gate before another reset

This is the recommended next step and performs no reset:

1. statically trace `IIWlan::getAllQualifiedNetworks` in `libril-qc-hal-qmi.so` from HIDL request to response construction;
2. identify the exact response cache and compare it with `NetworkAvailabilityHandler::dumpCache`;
3. locate filters, readiness, slot and client conditions that can turn a populated NAH dump into a zero-entry response;
4. determine whether serial 0/6 emptiness is expected pre-P, stale client state, or a producer projection failure;
5. only then freeze ORDER-B or a justified larger boundary.

## R4c decision

`R4c` is **not currently required**. It becomes eligible only if static/read-only evidence shows the empty response is caused by state outside the qcrild2/qtidataservices/phone epochs already reset by R4b, or if a separately frozen boot-shaped order reaches a valid fresh query but reproduces the same upstream failure.

Any future run remains one order, one reset primitive per stage, no adaptive fallback, no second reset/SIM cycle, and immediate stop on the first valid missing stage.
