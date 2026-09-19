# L1.5 executor code audit

Date: 2026-09-19

## Result

**STATIC AUDIT: PASS**

**REAL POWER CYCLE: NOT EXECUTED**

## Verified controls

- Target slot is a compile-time constant: `TARGET_SLOT_ID=1`.
- The helper accepts commands only; it accepts no caller-provided slot, phoneId, subId, Binder transaction, or numeric state.
- The only SIM-power invocation passes `TARGET_SLOT_ID` and a state restricted to down `0` or up `1`.
- The four-argument callback overload is selected explicitly with `Executor` and `Consumer` parameter types.
- The helper requires `LAB_MODE=1`, `LAB_EXECUTE=YES`, and UID 0 before any SIM-power request.
- POWER_DOWN requires the strict current dual-SIM gate, a valid same-boot rollback token, and `watchdog.ready`.
- Strict gate includes both SIMs in READY state; VOXI UICC applications must be enabled.
- POWER_UP requires both live mapping gates or the valid same-boot pre-down token. This preserves rollback if framework subscription rows temporarily disappear.
- Callback timeout and non-success result codes fail closed.
- The watchdog deadline is fixed at 30 seconds after `power_down.sent`.
- An atomic directory lock prevents two watchdog instances from arming concurrently; a stale lock fails closed for manual review.
- The watchdog contains its own fixed POWER_UP invocation and does not wait for user interaction.
- No qcrild, modem, radio-power, airplane-mode, reboot, settings, property, raw Binder, raw HIDL, or direct QMI command exists in the executor.

## Checks run

- `audit_executor.ps1`: PASS.
- `bash -n run_l1_5_executor.sh`: PASS.
- `bash -n device/l1_5_rollback_watchdog.sh`: PASS.
- Git whitespace check: PASS at audit time.

## Build status

The source intentionally avoids compile-time Android dependencies by using reflection against the already verified current-ROM signatures. A reproducible javac/D8 driver is included. This computer does not currently expose an audited JDK/D8 pair, so no dex JAR was generated or deployed in this phase. A future build must record the JDK/D8 versions, output SHA-256, source commit, and a decompilation check before deployment.

## Remaining pre-write review

Before authorization to execute, review the built dex against this source, deploy the helper/watchdog to the fixed root-only directory, run `DRY_RUN`, confirm the current boot ID and dual-SIM gate, and verify that the watchdog reaches `ready` without invoking either power state. Do not test watchdog firing by powering down until the user authorizes the actual one-shot experiment.
