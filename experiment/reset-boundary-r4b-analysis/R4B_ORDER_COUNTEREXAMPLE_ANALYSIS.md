# R4b order counterexample analysis

Date: 2026-09-24

Baseline commit: `896536fc80546234df51ad90dbda0e03e7019b9f`

Method: target-ROM static inspection plus existing R4b Cycle 1 evidence; device access in this phase was read-only.
Phone writes: **0**

> **Superseding native-cache correction (2026-09-24):** target-ROM disassembly now proves that GET reads the same container printed as current `LastReportedNetworkAvailability`. The IMS `[EUTRAN,IWLAN]` line cited below was from the prior NAH generation retained in the process-level history buffer, not the replacement handler's current cache. The replacement handler's current working and last-reported containers were both empty. See `experiment/native-qualified-network-boundary/`. The frozen R4b/P/M1 classification is unchanged.

## Frozen causal result

The following result is not weakened by this analysis:

- `R4B_FALSIFIED_AT_P`
- `R4B_FALSIFIED_AT_CYCLE=1`
- `FIRST_MISSING_MILESTONE=M1`

R4b created the intended producer, provider-process and framework-consumer epochs, but fixed P still did not produce ANM `IMS -> IWLAN`. v2.6.2 and the SIM cycle did not run.

## Executed order

| Time | Event |
|---|---|
| 21:41:34.861 | new `.qtidataservices` PID 23859 born |
| 21:41:35.012 | new slot1 `IWlanProxy` process epoch |
| 21:41:35.014 | slot1 provider created and IIWlan/slot2 connected |
| 21:41:35.074 | `getAllQualifiedNetworks` response serial 0 processed |
| 21:43:26.231 | old phone PID 3448 died |
| 21:43:26.265 | new phone PID 27795 born |
| 21:43:27.922 | new ANM-1 bound vendor QNS |
| 21:43:28.501 | a **new** slot1 provider was created in PID 23859 |
| 21:43:28.508 | a second initial query, response serial 6, completed |
| fixed P | M1 absent; state Unknown/UNKNOWN/preferred=false |

The first provider was attached while phone PID 3448 was alive. That callback therefore belonged to the old phone epoch. This observation motivated H4, but it is not the end of the evidence.

## Decisive correction: both initial query payloads were empty

The live QNS service dump retained its internal per-provider history:

```text
2026-09-24T21:41:35.018051 0 > REQUEST_GET_QUALIFIED_NETWORKS
2026-09-24T21:41:35.074693 getAllQualifiedNetworksResponse:
2026-09-24T21:41:35.074778 0 > Response Processed
2026-09-24T21:41:35.075370 get complete, Calling updateQualifiedNetworks
2026-09-24T21:43:28.507416 6 > REQUEST_GET_QUALIFIED_NETWORKS
2026-09-24T21:43:28.508412 getAllQualifiedNetworksResponse:
2026-09-24T21:43:28.508520 6 > Response Processed
2026-09-24T21:43:28.509131 get complete, Calling updateQualifiedNetworks
```

Target APK bytecode proves `qualifiedNetworksListToString()` appends a message for every entry, including entries with an empty network vector. A completely blank suffix therefore means the returned `ArrayList<QualifiedNetworks>` had zero entries; it is not merely an IMS entry whose network list was empty.

Consequently:

- serial 0: completed, **empty payload**;
- serial 6: completed, **empty payload**;
- the previous `QUERY_RESPONSE_VALID` label meant only “response completed” and was too strong;
- the historical `NetworkAvailabilityHandler` IMS `[EUTRAN,IWLAN]` line cannot substitute for the replacement handler's current cache or actual IIWlan response payload.

## First concrete internal divergence

```text
old NetworkAvailabilityHandler generation/history
  IMS -> [EUTRAN, IWLAN]
        |
        | qtidataservices reconnect causes initializeIWLAN
        v
replacement NetworkAvailabilityHandler
  current working cache = empty
  current LastReportedNetworkAvailability = empty
        v
IIWlan getAllQualifiedNetworks response
  zero QualifiedNetworks entries             <-- expected projection
        v
vendor provider cache has nothing to publish/replay
        v
new ANM receives no M1
```

This boundary is earlier and more specific than a stale callback-only explanation:

`qtidataservices reconnect -> native initializeIWLAN replacement NAH -> missing current-generation publication -> IIWlan GET returns empty -> vendor QNS provider`.

## H4 verdict

Two distinct claims must be separated:

1. **Specific H4 / STALE_PROVIDER_CALLBACK_EPOCH:** not supported and effectively falsified for this run. The new phone caused a new QNS Service object, a new slot1 provider, and a new serial-6 query. No `already existed` path blocked the callback, and the new provider did not depend on replay from the old provider object.
2. **Broad ordering/lifecycle-residue hypothesis:** remains possible but unproven. There was no observed old-provider `close()`/unregister during phone death, and slot1 `IWlanProxy` reference counts increased across the new phone bind. A leaked old registrant/reference may exist, but it did not prevent fresh provider construction and does not explain away the empty serial-6 response.

## Why R4c is not yet justified

The evidence does not require a larger reset set. The apparent interface mismatch is resolved: current dump and GET agree. Expanding to R4c before testing a current-generation native-publication readiness gate would mix a new primitive into an unresolved lifecycle-generation boundary.

That static/read-only analysis is now complete in `experiment/native-qualified-network-boundary/`. The next safe candidate is a fail-closed readiness predicate tied to the latest NAH generation, its live current containers and a matching non-empty GET response. No recovery action is authorized by this report.

## Evidence anchors

- Host-only raw evidence: `voxi_wfc_local_runs/reset_boundary_r4b/r4b_3cycle_v2/` (not committed).
- Sanitized frozen result: `experiment/reset-boundary-r4b/runs/r4b_3cycle_v2/RESULT.md`.
- Target `framework.jar` SHA-256: `2F6AA4B89B86DE5E0E80DEC7FB8E6AE2D69F73AF73E2C51776F7B64E58C9C4D1`.
- Target `IWlanService.apk` SHA-256: `28BD393231B75C1F826D82F9115D5C5ADB5F0B8967A20D247656265A01F246C6`.
