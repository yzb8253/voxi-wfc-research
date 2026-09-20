# L1.5 Executor DEX Audit Report

Date: 2026-09-20

## Source and shell audit

- Host runner shell syntax: PASS
- Device watchdog shell syntax: PASS
- Fixed target `TARGET_SLOT_ID=1`: PASS
- Protected `PROTECTED_SLOT_ID=0`: PASS
- Callback overload `(int, int, Executor, Consumer)`: PASS
- Exactly one source-level SIM power invocation: PASS
- Invocation uses `TARGET_SLOT_ID`, never `PROTECTED_SLOT_ID`: PASS
- Closed command allowlist: PASS
- Dual execution locks `LAB_MODE=1` and `LAB_EXECUTE=YES`: PASS
- POWER_DOWN requires same-boot rollback arm and watchdog-ready marker: PASS
- Watchdog rollback deadline remains 30 seconds: PASS
- Both watchdog waits now use absolute device wall-clock deadlines: PASS
- No unrelated radio/process operations: PASS

## DEX audit

- DEX checksum: PASS
- `invokePowerWithCallback(int,String)` validates state as only 0 or 1.
- The reflected method name is exactly `setSimPowerStateForSlot`.
- The four-argument overload is resolved with `(int,int,Executor,Consumer)`.
- Immediately before `Method.invoke`, the first boxed integer comes from register `v0`; the method initializes `v0` to constant 1. This is the slot argument.
- The second boxed integer comes from the validated state parameter.
- No DEX strings or calls for `resetIms`, `setRadioPower`, `qcrild`, `reboot`, `setprop`, `killall`, or `pkill` were found.
- The helper accepts no numeric slot, phoneId, subId, transaction code, or power-state argument.

Result: `DEX_AUDIT=PASS`.
