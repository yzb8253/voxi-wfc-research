# Phase 1.8 shadow integration static audit

Date: 2026-09-25  
Branch: `wfc-latency-study-20260925`  
Starting commit: `6914001f3703afa640766cd7b456e8a45ce63a87`

## Control-flow isolation

The authoritative classifier remains `repeatability_preflight.ps1` operating on the existing full snapshot. Its original target, health, airplane, native-clean, and frozen-residue branches remain the only inputs to normal recovery control flow.

The new shadow adapter receives the already-computed old classification as data, performs one lightweight capture, and writes host-only telemetry. No branch executes a phone write because of `newResult`, `writeEligible`, CNE IDs, or any other lightweight field.

The only non-zero shadow exits are experiment stop conditions explicitly required for Phase 1.8:

- lightweight parser/classifier error;
- old non-write state promoted to a new write-eligible state;
- old-current versus lightweight-current CNE ID mismatch.

These exits fail closed before the next recovery action. A normal equivalent or more-conservative shadow result cannot authorize, suppress, reorder, or repeat a recovery mutation.

## Capture placement

One lightweight capture is added immediately after each full preflight snapshot already present in the stable path. No additional full snapshot is introduced. If native normalization produces the existing second full snapshot, that snapshot receives exactly one corresponding lightweight capture.

The Phase 1.8 driver performs one extra lightweight capture 30 seconds after a successful frozen-health result. That delay and capture occur after the recovery stopwatch is stopped, and do not alter freeze behavior.

## Frozen recovery behavior

- v2.6.2 core path: unchanged from the latency branch baseline.
- waits and timeouts: unchanged.
- maximum attempts: unchanged at two.
- mutation order: unchanged.
- SIM OFF/ON budget: unchanged.
- deep fallback: unchanged.
- health predicate: unchanged.
- qcrild primary behavior: unchanged.
- golden branch: untouched.

The stable wrapper changed only its syntax-gate file list so the three shadow scripts are parsed before recovery.

Between successful cycles, the driver uses the already-established exact `cmd connectivity airplane-mode disable` transition and a 60-second A-state settle. It adds no recovery primitive.

## Static and offline results

- Windows PowerShell 5.1 parser errors: 0.
- Offline classifier fixtures: 17.
- Fixture mismatches: 0.
- Unsafe fixture promotions: 0.
- Standalone real-device read-only shadow probe: `A0_READY -> A0_READY`, CNE null/null match, exit 0.
- Standalone shadow elapsed: 3609 ms; device span 3048 ms.
- Phone writes during static audit and standalone probe: 0.
- Recovery runs during static audit: 0.

## Execution decision

`READY_FOR_PHASE18_REAL_RECOVERY_VALIDATION`

The validation must stop on the first non-zero wrapper exit, new failure class, parser/runtime error, unsafe promotion, or CNE ID mismatch. It may run at most five cycles.

