# Real run 002 — pidfile publication race

Date: 2026-09-25

Result: `BLOCKED_AFTER_FAST_START_PIDFILE_RACE`

## Entry

- Entry mode: native owner
- airplane mode: `1`
- pm-service: PID `27267`, sole `/dev/subsys_esoc0` owner
- X55 vendor/kernel: `ONLINE/ONLINE`
- crash_count: `3`
- qcrild/qcrild2: `1971/27832`

## Observed failure

- `vendor.per_mgr` was stopped once.
- owner `NONE` and kernel X55 `OFFLINE` were reached in 1557 ms.
- FAST holder main PID `29604` opened FD9 and became the sole esoc owner.
- The runner read the main pidfile before the child pidfile had been published.
- This is an orchestrator synchronization defect, not a holder lifecycle failure.
- The intended 300-second stability interval never began.

## Cleanup

- Exact FAST holder PID `29604` was identified by cmdline and FD9 ownership and received TERM once.
- Child PID `29795` had no FD9 and received TERM once.
- No SIGKILL, killall, or broad process selection was used.
- `vendor.per_mgr` was started once; because pm-service did not reacquire esoc within the bounded wait, `vendor.qcrild2` was restarted once as the documented rollback fallback (`27832` -> `30774`).
- Final native state: pm-service PID `30638` sole owner, X55 `ONLINE/ONLINE`, crash_count `3`, primary qcrild PID `1971` unchanged.
- SIM writes: `0`; airplane writes: `0`.

## Required correction

Wait for both main and child pidfiles before reading either. Log the cmdline and FD9 values before any exact-PID TERM decision. Use a single phone-side release-state sample per poll so host ADB round trips do not inflate the measured release latency.
