# X55-WFC-STABLE-v1

Purpose: turn the manually validated recovery workflow into a bounded wrapper without changing the proven v2.6.2 recovery core.

## What remains unchanged

The wrapper calls:

- `X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1`

That file is not modified by this branch. On WFC success it still freezes the healthy state and performs no post-success native/telephony cleanup.

## Wrapper flow

1. User starts the script with airplane mode OFF.
2. Exact device / ROM / VOXI slot1 safety gate.
3. Keep Wi-Fi enabled and wait 20 seconds by default.
4. Run the validated repeatability preflight with `-ApplyNormalization`.
5. Require `A0_READY` or `A0_NORMALIZED`. Record the A-state qti.cne request, but do not require it to stay null while airplane mode is OFF because telephony may recreate a fresh IMS demand.
6. Turn airplane mode ON automatically and keep Wi-Fi enabled.
7. Wait 20 seconds by default and inspect the P-state qti.cne request. The stale-CNE gate is enforced here, not in A0.
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

- A state: 20 seconds
- P state: 20 seconds

Default maximum recovery attempts: 2.


## Guarded UICC deep fallback

The original stable two-attempt path remains unchanged.

Only when both completed v2.6.2 attempts explicitly record `CNE_REQUEST_FRESHNESS=NO_CNE_REQUEST`, and the wrapper has successfully restored a clean airplane-OFF A0 state, one additional fallback is allowed:

1. Re-verify the exact cas / Android 13 / V816.0.4.0.TJJCNXM build.
2. Re-verify VOXI subId11 is enabled on slot1 with carrierId28 / MCCMNC23415.
3. Re-verify protected China Telecom subId1 remains enabled on slot0 with MCCMNC46011.
4. Execute one `ISub.setUiccApplicationsEnabled(false, 11)` transaction.
5. Require the VOXI row to reach the verified apps-disabled F8 fingerprint: `simSlotIndex=-1` and `areUiccApplicationsEnabled=false`.
6. Execute one symmetric `ISub.setUiccApplicationsEnabled(true, 11)` transaction.
7. Require VOXI to return to slot1/apps-enabled with the same carrier identity, while slot0 remains intact.
8. Rebuild the normal A/P state and, only if still needed, run one final unchanged v2.6.2 recovery cycle.

The helper uses Android 13 ISub transaction 46 for `setUiccApplicationsEnabled(boolean,int)`. Every write is hard-coded to subId11. A guard sends one emergency TRUE to subId11 if the disable phase was entered but the normal re-enable path does not complete.

This fallback is not entered for stale-CNE, dirty-P, mapping, platform, ADB, root, or native-owner failures. It is reserved for the repeated `NO_CNE_REQUEST` failure class.


## Quick frozen-holder normalization

When a previous successful run left the validated temporary X55 holder frozen and the next run starts with airplane mode OFF, preflight no longer spends two full 20-round windows waiting for the rarely observed dual-owner handoff.

The stable wrapper now asks `normalize_a1_native_owner.ps1` for a bounded quick probe:
- up to 3 dual-owner probes,
- one vendor.per_mgr restart,
- up to 3 more dual-owner probes,
- then up to 10 seconds to verify the exact known split fingerprint required by the validated qcrild2 reacquire path.

If that split fingerprint is present, preflight immediately switches to `normalize_a1_qcrild2_reacquire.ps1`. If the fingerprint is not present, the old safety failure behavior is preserved. The normal A0 verification, P preparation, two-attempt recovery core, and post-SIM timing are unchanged.
