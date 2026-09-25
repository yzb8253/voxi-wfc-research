# X55-WFC-STABLE-v1

Purpose: turn the manually validated recovery workflow into a bounded wrapper without changing the proven v2.6.2 recovery core.

## What remains unchanged

The wrapper calls:

- `X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1`

That file is not modified by this branch. On WFC success it still freezes the healthy state and performs no post-success native/telephony cleanup.

## Wrapper flow

1. User starts the script with airplane mode OFF.
2. Exact device / ROM / VOXI slot1 safety gate.
3. Keep Wi-Fi enabled and wait 12 seconds by default.
4. Run the validated repeatability preflight with `-ApplyNormalization`.
5. Require `A0_READY` or `A0_NORMALIZED`. Record the A-state qti.cne request, but do not require it to stay null while airplane mode is OFF because telephony may recreate a fresh IMS demand.
6. Turn airplane mode ON automatically and keep Wi-Fi enabled.
7. Wait 12 seconds by default and inspect the P-state qti.cne request. The stale-CNE gate is enforced here, not in A0.
8. If P has an existing CNE request while WFC is unhealthy, block v2.6.2, return to A0, normalize, and retry within the bounded attempt count.
9. Only when the P-state CNE gate is clean (`request=null`) run the unchanged v2.6.2 core.
10. If WFC becomes healthy: freeze and exit immediately, leaving airplane mode ON + WFC HEALTHY.
11. If the core fails: return to airplane-OFF A0, normalize, rebuild P, and retry once.
12. If all bounded attempts fail: try to restore a clean airplane-OFF A0 state and stop.

## Why there is one bounded retry

Observed manual sequence on 2026-09-25:

- successful cycles entered the SIM cycle with qti.cne request=null;
- one failed cycle entered with an existing request (357), which stayed unchanged through the SIM cycle and was classified STALE_CNE_REQUEST;
- returning to airplane-OFF A, running the known normalization path (including the fingerprint-specific qcrild2 reacquire), and rebuilding P cleared the stale condition;
- the next v2.6.2 run recovered WFC again.

The wrapper therefore does not add unbounded process resets or experimental CNE/qtidataservices/cnd actions. It only automates the already observed A -> normalize -> P -> v2.6.2 workflow and one observed failure/retry path.

## Airplane-mode contract

Normal user entry is airplane mode OFF. The wrapper verifies that state and does not silently begin from airplane mode ON.

After A0 is normalized, the wrapper enables airplane mode with:

`cmd connectivity airplane-mode enable`

It verifies `settings get global airplane_mode_on` after the command. If this ROM does not accept the command, it stops for a manual airplane-mode ON toggle and verifies again before continuing. On successful recovery, the final state intentionally remains airplane mode ON + WFC HEALTHY + frozen native holder state.

If a bounded recovery attempt fails, the wrapper may temporarily disable airplane mode in order to return to A0 and run the already validated normalization path before retrying.

## Double-click entry

Use:

`RUN-X55-WFC-STABLE-v1.cmd`

Default settle windows:

- A state: 12 seconds
- P state: 12 seconds

Default maximum recovery attempts: 2.


## Fast NO_CNE retry

When the first v2.6.2 attempt completes the X55 restart and one SIM2 power cycle but ends with `NO_CNE_REQUEST`, the stable wrapper uses a dedicated fast path:

1. v2.6.2 preserves the temporary X55 holder instead of running the slow transactional cleanup.
2. The wrapper returns to airplane mode OFF.
3. After the 12-second A-state settle window, `normalize_no_cne_fast.ps1` prepares the known pm-service/holder split fingerprint.
4. It directly runs the validated slot2 `qcrild2` reacquire path.
5. The second recovery attempt skips the normal A0 preflight because the fast path already verified native ownership recovery.
6. The wrapper rebuilds P and runs v2.6.2 again.

This fast path is only used for the explicit `NO_CNE_REQUEST` result. Other failure classes keep the normal bounded retry behavior.

## WFC detection accuracy

After SIM2 POWER ON, the core records the actual POWER ON timestamp and probes WFC frequently. It exits immediately when IMS is REGISTERED on WLAN with VOICE/IWLAN and WFC available. The expensive post-POWER-ON lifecycle snapshot is deferred to the failure path so it cannot delay successful detection. A final edge probe is made before declaring failure.
