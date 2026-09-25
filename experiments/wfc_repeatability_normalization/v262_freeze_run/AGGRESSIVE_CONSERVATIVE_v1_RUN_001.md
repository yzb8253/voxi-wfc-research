# AGGRESSIVE_CONSERVATIVE_v1 run 001

Date: 2026-09-25 20:50–20:51 CST  
Tested commits: `867f516`, `2129b34`, `0672e64`  
Result: `ABORTED_PRE_NORMALIZATION_ACTIVE_CNE_SHADOW_MISMATCH`

This is not a recovery failure and not a holder experiment. The run stopped
before normalization, qcrild2 restart, core execution, or SIM power writes.

## Entry and observation

- ADB/root/ROM/VOXI safety gate: PASS.
- Airplane: OFF.
- Holder: PID 29927, sole `/dev/subsys_esoc0` owner.
- `vendor.per_mgr`: stopped.
- vendor/kernel X55: ONLINE/ONLINE.
- crash_count: 3.
- qcrild/qcrild2: 1971 / 25719, unchanged after stop.
- WFC: F1.
- Initial lightweight capture: 3,765 ms; settle actual 5 s.
- Initial class was not the v1 split fingerprint because current CNE evidence
  was non-null (`request=1518`, `satisfied=1518`). The wrapper correctly chose
  full fallback.

The old full snapshot took 35,579 ms, including 28,025 ms of historical
qcril/X55 logcat evidence. Its old current-request projection was blank while
the adjacent lightweight observation reported request/satisfied 1518. The
existing shadow safety rule classified this as an active-ID mismatch and
stopped with `SHADOW_TELEMETRY_STOP exit=81`.

## Mutation accounting and preserved state

- Idempotent environment command: one existing `svc wifi enable` invocation;
  Wi-Fi was already enabled.
- Holder TERM: 0.
- qcrild2 restart: 0.
- X55 normalization: 0.
- v2.6.2 core runs: 0.
- SIM OFF: 0.
- SIM ON: 0.
- UICC fallback: 0.

Read-only post-check retained holder 29927 as sole owner, X55 ONLINE/ONLINE,
crash_count 3, per_mgr stopped, qcrild/qcrild2 1971/25719, and airplane OFF.

Per test discipline, no immediate patch, retry, or remaining three runs were
performed. The run neither measures the expected exact-split v1 A0 duration
nor falsifies the v1 split fast path.
