# v2.6.3 three-cycle validation result

Date: 2026-09-24

Result: `STOPPED_V1_WFC_RECOVERY_FAILED_AFTER_ORCHESTRATOR_RESUME`

## Scope reached

- V1 A_RAW capture: PASS.
- Frozen-success residue classification: PASS.
- V1 A normalization: stopped before the verified qcrild2 reacquire stage.
- P creation: NOT RUN.
- v2.6.2 recovery: NOT RUN.
- SIM cycle: 0.
- Validation cycles 1/2/3: NOT COMPLETED.

## Initial fingerprint

`V1_A_RAW.json` showed the exact known residue:

- airplane OFF, wlan0 and VPN ready;
- VOXI identity/mapping, active subscription, and UICC gate PASS;
- vendor.per_mgr stopped and pm-service absent;
- exact holder PID 31050 sole owner of `/dev/subsys_esoc0`;
- vendor and kernel X55 ONLINE, crash count zero;
- primary qcrild PID 1958 and qcrild2 PID 27223;
- IMS NOT_REGISTERED and no current qti.cne IMS request.

## Stop cause

The make-before-break helper performed its recorded start/restart attempt and correctly returned nonzero because pm-service did not form dual ownership. This nonzero result is the expected transition into the strict qcrild2 native-reacquire helper.

The new host state machine had `$ErrorActionPreference=Stop` while capturing child stderr. PowerShell promoted the helper's expected stderr to a terminating `NativeCommandError` before the parent could inspect the exit code and invoke the fallback. The driver correctly stopped all later phases and cycles.

This is a host orchestration defect, not evidence that the device normalization path failed.

## Preserved failure scene

`V1_FAILURE_HOST_WRAPPER.json` records:

- airplane OFF;
- VOXI mapping/active/UICC unchanged;
- vendor.per_mgr running, pm-service PID 11529 present but not owner;
- holder PID 31050 remains sole `/dev/subsys_esoc0` owner;
- vendor X55 OFFLINE, kernel X55 ONLINE, crash count zero;
- qcrild PID 1958 and qcrild2 PID 27223 unchanged;
- IMS NOT_REGISTERED/WFC unavailable.

The holder was not TERM'd. The qcrild2 fallback, airplane transition, SIM cycle, recovery, CND, IMS reset, and later cycles did not run.

Phone writes in this stopped run: vendor.per_mgr start once and vendor.per_mgr restart once, both inside the previously audited make-before-break helper.

## Correction

The candidate now invokes child PowerShell scripts through an explicit result wrapper that temporarily allows stderr capture, records the real exit code, restores the parent's fail-closed preference, and then performs the intended state transition. The correction has passed static parsing but has not been executed on the phone.

Fresh authorization was received and the run resumed from this preserved fallback-precondition scene. The original stop remains classified `ORCHESTRATOR_FAILURE`, not `WFC_RECOVERY_FAILURE`.

## Resumed V1 execution

The corrected child boundary self-test captured intentional stderr and exit code 23 without suppressing real failures. The resumed device sequence then completed:

1. recognized the exact qcrild2 fallback precondition;
2. TERM'd exact holder PID 31050 once;
3. proved owner NONE, vendor/kernel X55 OFFLINE, crash count zero;
4. restarted only vendor.qcrild2 once, PID 27223 -> 16258;
5. pm-service PID 11529 became sole native owner;
6. X55 returned ONLINE, crash count zero;
7. after 60 seconds, `V1_A_NORMALIZED` passed the canonical A gate;
8. airplane ON and Wi-Fi ensure were applied;
9. after 60 seconds, `V1_P_RAW` matched canonical P on its first check;
10. the hash-locked v2.6.2 freeze-on-success recovery ran unchanged.

Recovery reached clean X55 OFFLINE, holder PID 19581, X55 ONLINE, crash count zero, a new PON_SUCCESS, the fixed ten-second settle, and exactly one SIM2 OFF/ON cycle with a three-second OFF hold.

It did not produce a current qti.cne IMS request. IMS remained NOT_REGISTERED/UNKNOWN, VOICE/IWLAN unavailable, UDP/4500 and XFRM absent, and WFC unavailable through the full thirty-second window. The recovery returned `AUTO_RECOVERY_FAILED`.

The original v2.6.2 failure cleanup started and restarted vendor.per_mgr while preserving the holder, but pm-service did not acquire esoc0. No qcrild2 recovery workaround, CND fallback, qtidataservices restart, second SIM cycle, IMS reset, or later validation cycle ran.

## Validation table

| Cycle | A normalization | P match | X55 rebirth | New PON_SUCCESS | SIM cycles | WFC elapsed | Freeze | Result |
|---|---|---|---|---|---:|---|---|---|
| 1 | PASS: exact holder TERM + one qcrild2 restart | PASS first check | PASS | PASS | 1 | no health by 30s | NO | FAIL |
| 2 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | 0 | n/a | NO | STOPPED |
| 3 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | 0 | n/a | NO | STOPPED |

## Final preserved scene

`V1_FAILURE.json` records:

- airplane ON, Wi-Fi/VPN environment retained;
- VOXI identity, active subscription, and UICC enabled;
- vendor.per_mgr running, pm-service PID 28375 present but not owner;
- exact holder PID 19581 sole owner of `/dev/subsys_esoc0`;
- vendor X55 OFFLINE, kernel X55 ONLINE, crash count zero;
- primary qcrild PID 1958, qcrild2 PID 16258;
- IMS NOT_REGISTERED, transport UNKNOWN, VOICE/IWLAN unavailable, WFC unavailable;
- no current qti.cne request, UDP/4500, or XFRM.

This is the same known ownership-residue family, not a new residue type. It is deliberately preserved without further phone operations.

Host-only v2.6.2 recovery log SHA-256: `2D7BE2A4EA5C1A7751BDCDFCCD6CEC5B1754F6E81E1492FD14BC714434AB0A2F`.
