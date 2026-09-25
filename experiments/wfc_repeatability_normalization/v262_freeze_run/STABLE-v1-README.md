# X55-WFC-STABLE-v1

Purpose: turn the manually validated recovery workflow into a bounded wrapper without changing the proven v2.6.2 recovery core.

## What remains unchanged

The wrapper calls:

- `X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1`

That file is not modified by this branch. On WFC success it still freezes the healthy state and performs no post-success native/telephony cleanup.

## Wrapper flow

1. Exact device / ROM / VOXI slot1 safety gate.
2. If WFC is already healthy: zero-write exit.
3. Enter airplane-OFF A state.
4. Keep Wi-Fi enabled and wait 60 seconds by default.
5. Run the validated repeatability preflight with `-ApplyNormalization`.
6. Require `A0_READY` or `A0_NORMALIZED`.
7. Enter airplane-ON P state.
8. Keep Wi-Fi enabled and wait 60 seconds by default.
9. Record the current qti.cne request.
10. Run the unchanged v2.6.2 core.
11. If WFC becomes healthy: freeze and exit immediately.
12. If recovery fails: return to A, normalize, rebuild P, and retry once.
13. If both bounded attempts fail: try to restore a clean airplane-OFF A0 state and stop.

## Why there is one bounded retry

Observed manual sequence on 2026-09-25:

- successful cycles entered the SIM cycle with qti.cne request=null;
- one failed cycle entered with an existing request (357), which stayed unchanged through the SIM cycle and was classified STALE_CNE_REQUEST;
- returning to airplane-OFF A, running the known normalization path (including the fingerprint-specific qcrild2 reacquire), and rebuilding P cleared the stale condition;
- the next v2.6.2 run recovered WFC again.

The wrapper therefore does not add unbounded process resets or experimental CNE/qtidataservices/cnd actions. It only automates the already observed A -> normalize -> P -> v2.6.2 workflow and one observed failure/retry path.

## Airplane-mode automation

The wrapper first tries the normal Android shell command:

`cmd connectivity airplane-mode enable|disable`

It verifies `settings get global airplane_mode_on` after the command. If this ROM does not accept the command, it stops for a manual airplane-mode toggle and verifies again before continuing. It does not silently use another airplane-mode write method.

## Double-click entry

Use:

`RUN-X55-WFC-STABLE-v1.cmd`

Default settle windows:

- A state: 60 seconds
- P state: 60 seconds

Default maximum recovery attempts: 2.
