# R_BIG_V1 Five-Cycle Result

Date: 2026-09-25

Status: stopped fail-closed during Cycle 2 normalization, before any R_BIG_V1 action.

## Verdict

- CONTROL_A0: PASS
- Cycle 1: PASS_FREEZE
- Cycle 2: FAIL at `HOLDER`
- Cycle 3: NOT_RUN
- Cycle 4: NOT_RUN
- Cycle 5: NOT_RUN
- `R_BIG_V1_UPPER_BOUND_NOT_FALSIFIED_3_RESCUES`: NOT_ACHIEVED
- R_BIG_V1 itself: NOT_TESTED / NOT_FALSIFIED

## CONTROL_A0

Exactly one AP reboot established the baseline. The target identity and subscription gates passed. Airplane mode was OFF, Wi-Fi and the configured VPN network were ready, pm-service PID 1273 was the native `/dev/subsys_esoc0` owner, X55 was ONLINE with crash count 0, qcrild PID was 1923, and qcrild2 PID was 1947. The initial WFC state was F1, as expected before fixed P.

## Cycle 1

Fixed P passed with qcrild2 PID 1947, pm-service PID 1273, X55 ONLINE and crash count 0. The unchanged hash-locked v2.6.2 recovery then:

1. stopped per_mgr;
2. confirmed X55 OFFLINE;
3. created exact holder PID 22768;
4. confirmed X55 ONLINE and a new PON_SUCCESS;
5. waited the fixed 10-second settle;
6. sent exactly one SIM2 POWER OFF;
7. waited 3 seconds;
8. sent exactly one SIM2 POWER ON.

Direct health became REGISTERED/WLAN with VOICE/IWLAN and WFC available at approximately 11 seconds. The recovery froze immediately with per_mgr stopped and holder PID 22768 retained. No post-success cleanup ran.

## Cycle 2 Stop

After airplane mode returned OFF, the historical minimal normalization captured `C2_MINIMAL_BEFORE` and strictly verified holder PID 22768. Exactly one TERM was sent at `08:36:05`. The holder exited approximately 47 seconds later. Its exact stale pidfile was removed at `08:36:52`.

The frozen 20-second native-offline gate then failed at `HOLDER_RELEASE_NATIVE_OFFLINE_FAIL`. The stop snapshot proves:

- holder process: absent;
- holder pidfile: absent;
- `/dev/subsys_esoc0` owner: none;
- per_mgr: stopped;
- pm-service: absent;
- kernel X55 state: OFFLINE;
- crash count: 0;
- vendor peripheral state: ONLINE.

The gate required both vendor and kernel X55 states to be OFFLINE. The persistent vendor-ONLINE/kernel-OFFLINE disagreement was therefore the earliest anomaly and the exact reason for the fail-closed stop.

No qcrild2 restart, fixed P, v2.6.2 invocation, or SIM power action occurred in Cycle 2. Cycles 3 through 5 and every R_BIG_V1 stage remained unexecuted.

## Telemetry Summary

| Point | qcrild | qcrild2 | pm-service | holder | per_mgr | vendor X55 | kernel X55 | IMS/WFC |
|---|---:|---:|---:|---:|---|---|---|---|
| CONTROL_A0 | 1923 | 1947 | 1273 | none | running | ONLINE | ONLINE | F1 |
| C1_P | 1923 | 1947 | 1273 | none | running | ONLINE | ONLINE | F1 |
| C1_W | 1923 | 1947 | none | 22768 | stopped | ONLINE | ONLINE | REGISTERED/WLAN, WFC true |
| C2_MINIMAL_BEFORE | 1923 | 1947 | none | 22768 | stopped | ONLINE | ONLINE | F1 |
| C2_STOP | 1923 | 1947 | none | none | stopped | ONLINE | OFFLINE | F1 |

No qcrild2 GEN_A/GEN_B, qtidataservices replacement PID, phone replacement PID, or new NAH generation exists for Cycles 3-5 because R_BIG_V1 did not run.

## Action Accounting

- AP reboot: 1, baseline only.
- Cycle 1 SIM OFF: 1.
- Cycle 1 SIM ON: 1.
- Cycle 2 holder TERM: 1.
- Cycle 2 exact stale-pidfile removal: 1.
- Cycle 2 qcrild2 restart: 0.
- R_BIG_V1 actions: 0.
- Adaptive repair after failure: 0.

Full raw logs remain host-only. The committed JSON snapshots are the sanitized machine-readable evidence.
