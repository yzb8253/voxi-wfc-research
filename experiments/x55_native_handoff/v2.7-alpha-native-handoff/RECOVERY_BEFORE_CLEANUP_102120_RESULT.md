# Recovery-before-cleanup device result — 2026-09-24 10:21

Environment: Computer A, Windows PowerShell 5.1.19041.6456, Xiaomi cas, serial fd0ff892.

Tested source baseline before timing optimization: `a45bd0633b18be765bab80b45ed41cbfc66160f5`.

## Result

The recovery-before-cleanup ordering restored full VOXI WFC before native cleanup:

```text
RECOVERY_RESULT=X55_REBIRTH_SUCCESS
NATIVE_HANDOFF_RESULT=EXPECTED_DUAL_OWNER_NOT_FORMED
PRE_CLEANUP_WFC_RESULT=HEALTHY_AFTER_ONE_SIM_CYCLE
FINAL_WFC_RESULT=NOT_CHECKED
CLEANUP_RESULT=NOT_RUN
REVOTE_MECHANISM_LOG=UNPROVEN
```

The cleanup failure occurred after WFC had already recovered.

## Exact timing evidence

PeripheralManager was stopped and qcrild2 PID 873 immediately observed the vendor PeripheralManager server death:

```text
10:21:25.263  PerMgrLib: Peripheral manager server died
```

qcrild2 then retried the vendor PeripheralManager service and logged failed retry rounds at:

```text
10:21:31.316
10:21:37.402
10:21:43.438
10:21:49.506
10:21:55.556
```

The final observed round ended with:

```text
Service vendor.qcom.PeripheralManager didn't start. Returning NULL
PerMgrLib: SDX55M get service fail
```

No later qcrild2 PeripheralManager retry is present in the captured 10:21-10:26 window.

## SIM and WFC recovery

The one-shot SIM helper executed exactly one POWER_DOWN and one POWER_UP:

```text
10:21:58.871  POWER_DOWN callbackResult=0
10:22:03.004  POWER_UP callbackResult=0
```

After POWER_UP, the WFC chain rebuilt:

```text
10:22:19.170  qti.cne IMS request 929 created
10:22:21.153  isImsRegistered = true
10:22:21.187  IMS IWLAN NetworkAgent 107 registered
10:22:21.840  IMS data DISCONNECTED -> CONNECTED
```

This confirms that the fresh-X55 + holder-sole + vendor.per_mgr-stopped recovery window is sufficient to restore the full IMS/IWLAN path with one software SIM cycle.

## Why cleanup failed

The script did not restart vendor.per_mgr until approximately 10:25:12, long after the last observed qcrild2 PeripheralManager retry.

The new pm-service PID 13098 started at:

```text
10:25:12.954  PerMgrSrv: Peripheral Mananager service start
10:25:12.954  SDX55M: Current State : is off-line
10:25:12.954  SDX55M: Voter/Listener count : 0/0
10:25:12.954  SDX55M: Client list:
```

No QCRIL register/vote event followed in the captured evidence. The exact dual-owner cleanup gate therefore did not form.

A later read-only live check showed:

- WFC still fully healthy / F0
- holder PID 9228 sole owner of `/dev/subsys_esoc0`
- vendor.per_mgr running
- pm-service PID 13098 alive but without an esoc0 FD
- X55 ONLINE, crash_count 0
- qcrild2 PID 873 unchanged

## Timing-optimization decision

The next implementation must preserve the successful SIM recovery context while bringing vendor.per_mgr back before qcrild2 stops retrying:

1. deploy helper/orchestrator, dry-run, rollback arm, and marker cleanup before stopping vendor.per_mgr;
2. stop vendor.per_mgr;
3. holder sole -> X55 rebirth -> new PON_SUCCESS;
4. execute exactly one SIM POWER_DOWN / 3-second hold / POWER_UP;
5. request vendor.per_mgr start immediately after successful POWER_UP, from the device-side orchestrator;
6. require exact holder + pm-service dual ownership while keeping the holder alive;
7. allow WFC to finish rebuilding under dual ownership;
8. only after WFC observation, TERM the exact holder and require pm-service sole ownership;
9. verify WFC survives native cleanup.

This is a timing hypothesis grounded in the observed qcrild2 retry window. It is not yet a proof that WFC will survive early native dual ownership or final holder release.
