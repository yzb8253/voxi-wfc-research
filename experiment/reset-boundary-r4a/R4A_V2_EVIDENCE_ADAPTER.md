# R4a v2 producer evidence adapter

Date: 2026-09-24

## Scope

This revision changes only how `PRODUCER_READY` observes an already frozen qcrild2 cold epoch. It does not change the reset primitive, reset count, ordering, readiness semantics, timeout, R3, A/P gates, v2.6.2, SIM budget or health predicate.

## Authoritative sources

Each field is evaluated from its actual source and written to the host-only `cycle_N_producer_evidence.json` with `SOURCE`, `RAW_EVIDENCE`, `TIMESTAMP` and `PASS`.

| Field | Source |
|---|---|
| old/new qcrild2, primary/qtidata/phone invariants | `/proc` and exact `ps` snapshot |
| PM sole owner, holder absence, X55, crash count | sanitized native-state snapshot |
| DataModule cold initialization | union of bounded logcat and IIWlan debug history |
| NAH construction | union of bounded logcat and IIWlan debug history |
| DSD/WDS, IWLAN enabled, modem capability | live IIWlan `IBase::debug` |
| provider services | live activity-service inventory |

## Epoch boundary and stale rejection

Immediately before the single restart, the runner records:

- the device restart lower-bound clock; and
- the complete pre-restart IIWlan debug history.

A historical marker is accepted only when its embedded device timestamp is at or after the current restart lower bound. For IIWlan history it must additionally be absent from the pre-restart history. Midnight rollover is handled explicitly. A marker with no parseable timestamp, an older timestamp or a pre-existing identical line is rejected. Missing fresh evidence remains fail-closed under the unchanged 120-second timeout.

## Frozen behavior

The write remains exactly one `setprop ctl.restart vendor.qcrild2`, followed by producer readiness, exact R3, fixed P and hash-locked v2.6.2. No fallback or extra reset was added.

