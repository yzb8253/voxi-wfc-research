# Next native hypotheses and minimum falsifiable candidate

Date: 2026-09-24
Status: analysis-only; no device action authorized
Phone writes: **0**

## Corrected hypotheses

### H5 — separate query cache

**FALSIFIED.** GET reads the same `LastReportedNetworkAvailability` container shown by current NAH dump. There is no separate query-facing cache and no GET filter that discarded populated entries.

### H6 — replacement NAH queried before current-generation publication

**SUPPORTED for serial 0; not yet sufficient to explain why the generation stayed empty through serial 6.** The initial request was accepted before the replacement constructor and handled 24 ms after it. The old IMS line used by the v2 gate was stale generation history.

### H7 — initializeIWLAN lacks replayable cached DSD status

**PLAUSIBLE, NOT PROVEN.** Target code replays DSD state only when a cached-status valid flag is set and does not actively fetch fresh status. If invalid, the replacement NAH needs a later indication/profile sequence before it can publish.

### H8 — explicit iwlanDisabled cleared a distinct query cache

**NOT SUPPORTED.** No disable/close/deregister event was observed; callback death only clears callbacks. The later enable handshake's replacement NAH fully explains the empty current state.

## Minimum next candidate: readiness-gate correction

Do not add a reset or a delay. In a separately authorized new series, keep the reset order fixed but define provider/native readiness using only evidence newer than the **latest current-epoch NAH constructor**:

1. identify the latest constructor after qtidataservices reconnect;
2. require the live/current `NetworkAvailabilityCache` to contain the expected IMS APN entry;
3. require live/current `LastReportedNetworkAvailability` to be non-empty and contain IMS with the appropriate pre-P terrestrial network (normally EUTRAN in the canonical A state);
4. require a fresh initial GET response from that same generation to contain the corresponding IMS entry;
5. reject all earlier LocalLogBuffer lines, even if their text matches;
6. proceed to R3/P only if those predicates remain stable under the existing timeout; otherwise fail closed as `NATIVE_PUBLICATION_NOT_READY`.

This is an observation/gate correction, not periodic re-report, callback injection, forced IMS/IWLAN, additional sleep, second restart, or workaround.

## Falsification outcomes

- If current-generation working/report caches never populate: boundary remains native DSD/profile/NAH population after IWLAN re-enable.
- If both caches populate and GET returns the same non-empty IMS entry, but fresh QNS does not call `updateQualifiedNetworkTypes`: boundary moves to HIDL response/QNS processing.
- If QNS updates correctly but the new phone still receives no M1: boundary moves to provider-to-framework consumer replay/binding.

Each outcome is distinguishable without adapting the run after failure.

## R4c decision

R4c is **not required and not justified now**. The R4b reset order invalidated its own earlier producer-readiness proof by creating another native NAH generation. The minimum next test is to make current-generation native publication part of the readiness predicate. Only a valid run reaching that predicate and still failing downstream can justify a larger reset boundary.
