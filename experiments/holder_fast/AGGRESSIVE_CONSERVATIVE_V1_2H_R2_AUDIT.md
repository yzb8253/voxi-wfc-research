# AGGRESSIVE_CONSERVATIVE_v1.2H-r2 CNE gate audit

The sole conceptual change is the source of wrapper-level CNE decisions.

- A shared `Get-CurrentCneProjection` implements the already-audited boundary: only text before `mNetworkRequestInfoLogs` is current state.
- The r2 lightweight collector and r2 wrapper use that same function.
- Missing history boundary fails closed.
- Current null/null is valid and clear.
- A current active request returns its real request/satisfied IDs and still blocks the P gate.
- `wfcctl status-json` request IDs are retained only as `ProbeReported*` diagnostics. A mismatch emits `STALE_PROBE_DIAGNOSTIC=1` and cannot block the core.
- A0, P, P_CNE_GATE, post-core failure classification, and deep-fallback no-CNE counting now use current-table state.

FAST holder, holder canonical identity, frozen-to-split transition, qcrild2 reacquire, A/P timing, PON/SIM timing, attempts, deep fallback implementation, recovery core, golden/stable, original v2.6.2, v1.2H, and v1.2H-r1 are unchanged.

Fixtures: wrapper CNE gates 5/5 PASS; classifier 17/17 PASS; holder identity 7/7 PASS; unsafe promotions 0.
