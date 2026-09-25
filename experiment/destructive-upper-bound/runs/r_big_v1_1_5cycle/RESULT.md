# R_BIG_V1.1 Five-Cycle Result

Date: 2026-09-25

Status: stopped fail-closed at Cycle 2 `V262/WFC`, after the corrected holder-release gate and native qcrild2 reacquire passed.

## Verdict

- CONTROL_A0: PASS
- Cycle 1: PASS_FREEZE
- Cycle 2 holder release: PASS
- Cycle 2 qcrild2 native reacquire: PASS
- Cycle 2 fixed P: PASS
- Cycle 2 v2.6.2/WFC: FAIL (`NO_CNE_REQUEST`)
- Cycle 3: NOT_RUN
- Cycle 4: NOT_RUN
- Cycle 5: NOT_RUN
- `R_BIG_V1_1_UPPER_BOUND_NOT_FALSIFIED_3_RESCUES`: NOT_ACHIEVED
- R_BIG_V1.1 upper-bound sequence itself: NOT_TESTED / NOT_FALSIFIED

## CONTROL_A0 and Cycle 1

Exactly one AP reboot established CONTROL_A0 with qcrild PID 1933, qcrild2 PID 1964, pm-service PID 1273 as native owner, X55 ONLINE, crash count zero, airplane OFF, and expected F1.

Cycle 1 fixed P passed. The unchanged hash-locked v2.6.2 recovery created holder PID 19306, produced a new PON_SUCCESS, sent exactly one SIM OFF and one SIM ON, and reached REGISTERED/WLAN plus WFC in approximately 8 seconds. FREEZE retained the holder and stopped per_mgr.

## Cycle 2 Gate Correction Result

After airplane OFF, the exact holder 19306 received one TERM. At the corrected release boundary:

- holder: gone;
- `/dev/subsys_esoc0` owner count: 0;
- kernel X55: OFFLINE;
- crash count: 0;
- vendor peripheral state: ONLINE, telemetry only.

This passed `HOLDER_RELEASE_READY`. No wait extension or action was added for the vendor property.

The existing sequence then started per_mgr into the running/non-owner precondition and performed exactly one qcrild2 restart:

- qcrild2: 1964 -> 24725;
- pm-service: PID 24465, sole native owner;
- kernel X55: ONLINE;
- vendor peripheral state: ONLINE;
- crash count: 0.

The native state therefore reconciled naturally after qcrild2 restart. This confirms that the vendor-ONLINE value at holder release was transitional/stale telemetry for gate purposes.

## Cycle 2 Real Failure

Cycle 2 fixed P passed. The unchanged v2.6.2 recovery entered from a clean native baseline, then:

1. stopped per_mgr and confirmed X55 OFFLINE;
2. created holder PID 27699;
3. returned X55 ONLINE and confirmed a new PON_SUCCESS;
4. waited the fixed settle;
5. sent exactly one SIM OFF and one SIM ON.

Unlike Cycle 1, no qti.cne IMS request appeared. IMS remained NOT_REGISTERED/UNKNOWN and WFC remained unavailable for the full 30-second recovery window. v2.6.2 classified `AUTO_RECOVERY_FAILED` with `NO_CNE_REQUEST`.

Its unchanged failure-cleanup branch started and restarted per_mgr but could not establish pm-service ownership while holder 27699 remained active. It intentionally retained that holder. The final read-only snapshot records airplane ON, per_mgr running, pm-service PID 6144 non-owner, holder 27699 as sole `/dev/subsys_esoc0` owner, kernel X55 ONLINE, vendor state OFFLINE, crash count zero, qcrild2 PID 24725, and F1.

The outer runner stopped on v2.6.2 exit 30. No Cycle 3-5 action, qtidataservices TERM, qcrild2 GEN_B, NATIVE_READY, or phone TERM occurred.

## Telemetry Summary

| Point | qcrild | qcrild2 | pm-service | holder | kernel X55 | vendor state | Result |
|---|---:|---:|---:|---:|---|---|---|
| CONTROL_A0 | 1933 | 1964 | 1273 | none | ONLINE | ONLINE | F1 baseline |
| C1_P | 1933 | 1964 | 1273 | none | ONLINE | ONLINE | P PASS |
| C1_W | 1933 | 1964 | none | 19306 | ONLINE | ONLINE | WFC PASS |
| C2 pre-release | 1933 | 1964 | none | 19306 | ONLINE | ONLINE | F1 |
| C2 holder-release boundary | 1933 | 1964 | none | none | OFFLINE | ONLINE | release PASS |
| C2 after qcrild2 restart | 1933 | 24725 | 24465 | none | ONLINE | ONLINE | native reacquire PASS |
| C2_P | 1933 | 24725 | 24465 | none | ONLINE | ONLINE | P PASS |
| C2 final stop | 1933 | 24725 | 6144 non-owner | 27699 | ONLINE | OFFLINE | F1 / no CNE request |

## Classification

`R_BIG_V1_1_SERIES_STOPPED_AT_CYCLE2_V262_WFC_NO_CNE_REQUEST`

The corrected gate is validated. The historical Cycle 2 normalization reached a clean native baseline, but the subsequent known-good recovery did not reproduce WFC. Because the series stopped before Cycle 3, R_BIG_V1.1 remains NOT TESTED / NOT FALSIFIED and no stable upper bound was established.

Raw logs remain host-only. Committed JSON snapshots are sanitized machine-readable evidence.
