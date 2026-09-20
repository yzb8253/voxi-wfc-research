# L1.5 Pre-execution Readiness

Date: 2026-09-20
Device endpoint: `192.168.137.127:40027`
Device model: `23116PN5BC` (Xiaomi 14 Pro)

## Runtime identity

- ADB: online
- Shell: UID 2000, `u:r:shell:s0`
- Magisk helper: UID 0, `u:r:magisk:s0`
- Helper Binder/framework binding: PASS

## Zero-write DRY_RUN

- VOXI: subId 11, slot 1, phoneId 1, carrierId 28, MCC 234, MNC 15
- VOXI active: true
- VOXI UICC applications enabled: true
- VOXI SIM state: READY (5)
- China Telecom: subId 1, slot 0, carrierId 2237, MCC 460, MNC 11
- China Telecom active and SIM state READY: true
- Target mapping gate: PASS
- Protected slot0 gate: PASS
- Combined strict gate: PASS
- Helper result: `DRY_RUN_ZERO_WRITE`

The live IMS/WFC probe remained F1 (`NOT_REGISTERED`, transport unknown, WFC unavailable). This is observational and does not affect the identity/safety gate.

## Deployment

The audited JAR and watchdog were deployed to `/data/local/tmp/voxi-l1_5-executor`, owned by root with directory mode 0700. No runtime telephony write was executed.

## Watchdog validation

- `ARM_ROLLBACK`: PASS
- Independent watchdog process: PASS
- `watchdog.ready`: observed at 2026-09-20T10:47:38+08:00
- No POWER_DOWN marker: PASS
- Safe no-down exit: observed at 2026-09-20T10:48:38+08:00
- `power_down.sent`: ABSENT
- `power_up.confirmed`: ABSENT
- `ROLLBACK firing` count: 0
- `command=POWER_UP` count: 0
- Lock and ready cleanup after exit: PASS

## Stop point

- Build: PASS
- DEX audit: PASS
- DRY_RUN: PASS
- Dual-SIM safety gate: PASS
- Watchdog ready: PASS
- Real SIM power cycle executed: NO

`NEXT_ACTION`: after explicit user authorization only, perform one fixed slot1 POWER_DOWN/POWER_UP cycle under the validated watchdog. Do not accept any runtime target identifiers.
