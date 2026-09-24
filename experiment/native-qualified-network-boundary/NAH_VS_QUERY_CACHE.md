# NAH dump versus query cache

Date: 2026-09-24
Phone writes: **0**

## Exact data structures

Target-ROM disassembly of `NetworkAvailabilityHandler::dump(...)` identifies two separate member containers:

- object `+0x38`: printed under `NetworkAvailabilityCache ==>`; this is the working per-APN cache;
- object `+0x60`: printed under `LastReportedNetworkAvailability ==>`; this is the qualified-network list most recently published/reported.

`NetworkAvailabilityHandler::dumpCache()` iterates the working container at `+0x38` for logs. By contrast, `NetworkAvailabilityHandler::getQualifiedNetworks(...)` iterates **the same `+0x60` container** that `dump(...)` labels `LastReportedNetworkAvailability`.

Therefore the answer to H5's structural question is:

- NAH current `LastReportedNetworkAvailability` and GET source: **same cache/container**;
- GET dynamically regenerates from DSD: **no**;
- GET reads a separate snapshot: **no**;
- GET returns a filtered view: **no**; it copies every entry.

## Why the earlier apparent mismatch was false

The R4b provider debug artifact has two very different sections.

Its **current object state** is:

```text
NetworkAvailabilityHandler:
    globalPrefSys= UNKNOWN
    NetworkAvailabilityCache ==>
    LastReportedNetworkAvailability ==>
```

Both containers are empty.

Later in the same dump, `Logs: NetworkAvailability:` is a process-level historical/local log buffer. It contains:

```text
21:40:33.273 [NAH]constructor
21:40:34.377 [NAH]type=IMS networks=[EUTRAN,IWLAN,]
...
21:41:35.048 [NAH]constructor
21:41:35.072 [NAH]process get qualified networks
```

The IMS line belongs to the **previous NAH generation** created at 21:40:33. The qtidataservices restart caused a new IWLAN handshake and a replacement NAH at 21:41:35.048. Its current working and last-reported containers were empty when queried 24 ms later.

The earlier report treated the historical IMS line as contemporaneous current-cache state. That interpretation is superseded. The frozen experimental outcome is unchanged (`R4B_FALSIFIED_AT_P`, Cycle 1, M1), but there is no native-cache-versus-GET mismatch.

## Publication path

QMI DSD indications and profile information update the working per-APN state through functions including:

- `processQmiDsdSystemStatusInd(...)`;
- `updateNetworkAvailabilityCache(...)` overloads;
- `processQmiDsdIntentToChangeApnPrefSysInd(...)` where applicable;
- `convertResultList(...)`.

`convertResultList` derives the reportable `QualifiedNetwork_t` list from the working per-APN state and compares/builds the reported result. The target logs `type=... networks=[...]` at this publication boundary. GET subsequently reads the resulting `LastReportedNetworkAvailability`; it does not repeat the conversion.

## R4a successful control

The R4a Cycle 1 producer dump, captured from the successful cycle, shows a coherent current generation:

```text
globalPrefSys= IWLAN
NetworkAvailabilityCache:
  apn=ims ... networks=[EUTRAN,IWLAN]
LastReportedNetworkAvailability:
  apnType=IMS prefNw=EUTRAN
```

Its fresh phone received ANM publication at 20:27:32.209. Thus a non-empty current `+0x60` list existed before the new framework consumer queried/bound. This differs from R4b before any final WFC outcome is considered.

## H5 verdict

`H5: separate native query cache mismatch` is **FALSIFIED at the data-structure level**.

The surviving hypothesis is a generation/readiness race: R4b's new qtidataservices process triggered a fresh native NAH generation, but the provider's initial query ran before that generation produced a current reportable list.
