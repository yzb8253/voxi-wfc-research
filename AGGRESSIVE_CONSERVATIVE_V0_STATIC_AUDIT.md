# Aggressive conservative v0 static audit

Branch: `wfc-aggressive-conservative-20260925`

## Provenance and isolation

- Golden commit `253ab93a2127806837cb472071846f568c811a34` is an ancestor of this branch.
- Phase 1.8 fixed baseline: `60c8181ce3942052984e258baeeee48c00df50bd`.
- The new branch adds an independent wrapper and CMD entry.
- `X55-WFC-STABLE-v1.ps1`, `RUN-X55-WFC-STABLE-v1.cmd`, and the v2.6.2 core have no diff from the branch point.
- Current v2.6.2 core SHA256: `70C81B1CC2F69F80540CB08DDD0C4F16FF2871B48D9D46E25F72C0F66CE51E76`.

## Harness fixes

- Semantic `UNKNOWN` with state diagnostics such as `native:x55_not_consistently_online` is accepted as more-conservative telemetry, not a runtime abort.
- Runtime abort remains limited to collector incomplete/command errors and missing/schema/capture structural errors.
- The Phase 1.8 driver waits only for the direct wrapper PID. It neither waits for nor terminates a retained holder descendant.
- Dummy parent/long-lived child test passed; direct parent observation returned in 567 ms while the dummy child remained alive until test cleanup.

## Experimental fast path

Lightweight fast path is limited to phase-appropriate `A0_READY`, `P0_READY`, or `HEALTHY_FREEZE` with:

- complete capture;
- no collector or structural errors;
- classifier identity/ownership checks satisfied;
- current CNE request and satisfied IDs both null.

Immediate full fallback occurs for `FROZEN_RESIDUE`, residue/identity-derived `UNKNOWN`, active CNE, missing/schema/capture errors, collector runtime failure, unexpected owner, or identity contradiction. Other unclear states continue bounded observation and fall back at the 20-second sleep-budget maximum.

## Frozen timing and recovery contracts

- A settle sleep budget: dynamic 5-20 seconds.
- P settle sleep budget: dynamic 5-20 seconds.
- Post-PON settle: unchanged in the reused core at 10 seconds.
- SIM OFF hold: unchanged in the reused core at 3 seconds.
- SIM ON health window: unchanged 30-second sleep budget plus probe runtime.
- Maximum attempts: 2.
- Deep fallback, qcrild2 reacquire, native normalization, mutation order, and health predicate: unchanged.

## Verification

- Windows PowerShell 5.1 parser: PASS.
- Offline fixtures: 17.
- Mismatches: 0.
- Unsafe promotions: 0.
- Semantic UNKNOWN regression: PASS.
- Direct-parent/long-lived-child regression: PASS.
- Golden ancestry: PASS.
- Golden/stable files modified by this branch: NO.
- ADB used for this task: NO.
- Phone writes: 0.

The new scripts have not been run against a phone. Manual testing must start with airplane mode OFF and use only the experimental CMD entry.
