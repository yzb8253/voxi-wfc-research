# v2.6.3 three-cycle validation result

Date: 2026-09-24

Result: `STOPPED_V1_A_NORMALIZATION_HOST_WRAPPER`

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

Fresh authorization is required before resuming from the preserved known fallback-precondition scene.
