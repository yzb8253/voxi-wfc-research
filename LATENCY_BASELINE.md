# VOXI WFC latency baseline

Date: 2026-09-25

Branch: `wfc-latency-study-20260925`

Instrumentation commit: `cd6b4d7cfd13e2e430ed7582de57eb079f1a3277`

Computer-B path compatibility commit: `32007fbcac0d22f037882dfcdcf658444444d07e`

## Scope and validity

This is a profiling baseline, not an optimization result. No timeout, wait, gate, recovery primitive, target, attempt count, health rule, or freeze behavior was changed.

The real-device run started from the priority-B state: airplane OFF after a previous frozen-holder success. It produced three complete frozen-residue preflight/normalization samples and two unchanged v2.6.2 core attempts in one wrapper invocation. Both core attempts ended in `NO_CNE_REQUEST`; therefore this run is not a WFC-success validation sample.

Further independent runs, including priority-A native-clean A0, were stopped because protected subId1 was physically/unambiguously absent from slot0. The existing UICC deep fallback correctly failed closed before any UICC write.

## Timing distribution

All values are milliseconds. Median is the arithmetic midpoint for an even sample count.

| Step | n | Min | Median | Max | Share of 1,129,357 ms wrapper run | Safety critical | Phone write | Candidate | Risk |
|---|---:|---:|---:|---:|---:|---|---|---|---|
| Full snapshot total | 6 | 46,389 | 48,356 | 50,969 | 25.7% across six calls | Diagnostic depth, not all fields are gate inputs | No | Split lightweight gate from failure-only evidence | Low if gate fields remain complete |
| Snapshot `qcril_x55_evidence` logcat scan | 6 | 37,628 | 39,897 | 40,892 | 21.0% across six calls; subset of snapshot | Diagnostic only | No | Collect only on unexpected/failure state | Low |
| Complete preflight normalization | 3 | 139,013 | 175,180 | 188,608 | 44.5% across three calls | Yes | Mixed | Optimize diagnostics first | Low/medium |
| Quick native-owner probe | 3 | 22,510 | 23,730 | 24,295 | 6.2% | Yes | May start/restart per_mgr | Keep until separately proven | Medium |
| qcrild2 reacquire total | 3 | 20,681 | 50,698 | 66,779 | 12.2% | Yes | Yes | Observe variance; no reduction yet | High |
| Holder TERM latency | 3 | 5,108 | 34,529 | 53,297 | 8.2% | Yes | Yes | Investigate host/holder exit latency only | High |
| Owner NONE/X55 OFFLINE | 3 | 1,794 | 1,994 | 2,135 | 0.5% | Yes | No new action | Keep | High |
| qcrild2 PID change | 3 | 1,387 | 1,527 | 1,550 | 0.4% | Yes | One validated restart | Keep | High |
| pm-service reacquire/X55 ONLINE | 3 | 5,501 | 5,728 | 6,241 | 1.5% | Yes | No new action | Keep | High |
| Ensure Wi-Fi ON | 5 | 3,285 | 3,365 | 3,434 | 1.5% | Yes | Idempotent enable | Later readiness redesign only | Medium |
| A settle | 3 | 20,005 | 20,007 | 20,014 | 5.3% | Yes | No | Do not reduce before diagnostic optimization | Medium |
| Airplane OFF to ON | 2 | 3,629 | 3,703 | 3,777 | 0.7% | Yes | Yes | Keep | High |
| P settle | 2 | 20,005 | 20,009 | 20,012 | 3.5% | Yes | No | Do not reduce yet | Medium |
| v2.6.2 core total | 2 | 212,852 | 220,194 | 227,536 | 39.0% across two calls | Yes | Yes | Separate failure-cleanup cost in later instrumentation | High |
| Core preconditions | 2 | 7,160 | 7,675 | 8,190 | 1.4% | Yes | No | Cache nothing across writes | High |
| X55 OFFLINE | 2 | 4,104 | 4,295 | 4,485 | 0.8% | Yes | Yes | Keep | High |
| Holder start to X55 ONLINE | 2 | 5,886 | 6,109 | 6,332 | 1.1% | Yes | Yes | Keep | High |
| PON_SUCCESS | 2 | 141 | 169 | 196 | <0.1% | Yes | No | Keep | High |
| Fixed post-PON settle | 2 | 10,003 | 10,006 | 10,009 | 1.8% | Yes | No | Frozen at 10 seconds | High |
| X55-only health checks | 2 | 10,745 | 10,771 | 10,796 | 1.9% | Yes | No | Probe cost is material; study later | Medium |
| SIM OFF request | 2 | 137 | 182 | 226 | <0.1% | Yes | Yes | Keep | High |
| SIM OFF hold including evidence snapshot | 2 | 3,760 | 3,914 | 4,067 | 0.7% | Yes | No after OFF | Fixed three-second hold | High |
| SIM ON request | 2 | 142 | 159 | 175 | <0.1% | Yes | Yes | Keep | High |
| SIM ON to health-window result | 2 | 61,755 | 61,872 | 61,989 | 11.0% | Yes | No after ON | Fix accounting only after separate review | Medium |

## Main finding

The 153-second historical suspicion is confirmed. In this run a frozen-residue preflight took 139-189 seconds. Two full snapshots consume roughly 94-102 seconds, and their two all-buffer logcat scans alone consume roughly 76-81 seconds. Diagnostic collection is the highest-value low-risk optimization target.

The second large variable is holder termination: 5.1, 34.5, and 53.3 seconds. This variance is real and must not be hidden by shortening safety gates.

## Timing defect discovered

The post-SIM function describes a 30-second maximum, but it increments a logical sleep counter and excludes each `wfcctl status` probe's roughly 2.8-second runtime. The observed SIM-ON-to-result wall time was 61.8-62.0 seconds. This is a timeout-accounting defect, not evidence that the 30-second recovery window should be shortened. No fix is included in this phase.

## Next safe profiling action

Do not run more phone mutations until the protected-slot0 contract is satisfied again or the user explicitly supplies a revised, audited single-SIM safety contract. Once unblocked, collect independent native-clean A0 and frozen-holder success samples with the same instrumentation commit before changing behavior.
