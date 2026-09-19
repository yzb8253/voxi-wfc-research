# Phase 6 — Slot1 resetIms Controlled Test

Date: 2026-09-17  
Device: `fd0ff892`  
Authorized write budget: exactly one `ITelephony.resetIms(1)`

## Result

`RESETIMS_RECOVERY = FAIL`

At 120 seconds the phone remained in strict F1. No second reset, false/true operation, radio operation, reboot, network change, settings write, CarrierConfig write, UICC write, or process action was performed.

## Static scope verification

PASS.

- Live-device SHA-256 values for TeleService.apk, telephony-common.jar, and Qualcomm ims.apk exactly match the previously analyzed current-ROM copies.
- `PhoneInterfaceManager.resetIms(int)` uses the integer as `slotId`.
- The method calls `ImsResolver.disableIms(slotId)` and `ImsResolver.enableIms(slotId)` as one paired operation.
- ImsResolver selects IMS controllers for that slot, resolves that slot's current subId, and calls the controller with `(slotId, subId)`.
- Qualcomm IMS resolves `ImsServiceSub` by slot.
- No path in this operation changes subscription/UICC state, CarrierConfig, radio power, default/active data subscription, or slot0.

Current-ROM hashes:

- TeleService.apk: `c79ed4719bea37125f3eb02943b051d6aa762f7d93481389c790f029399116a7`
- telephony-common.jar: `bd0d407bb7a47a41bd923f79f9713174d43c3e7d98c53dff97b226b1f8141b57`
- ims.apk: `230c4f7e3bff900f66f8161bef4f07baf9350b8c9ccc0f03dc74a190820e86bb`

## Pre-state and safety gate

PASS.

- VOXI: subId 11 / slot 1 / phoneId 1 / carrierId 28 / MCC-MNC 234-15
- China Telecom: subId 1 / slot 0 / MCC-MNC 460-11
- Subscription: ACTIVE
- UICC applications: ENABLED
- IMS: NOT_REGISTERED (0)
- Transport: UNKNOWN (-1)
- VOICE/IWLAN: unavailable
- WFC: unavailable
- MMTEL: READY
- PS/WLAN: HOME
- qti.cne IMS request: absent
- ePDG/XFRM: absent
- Failure class: F1

The fixed-target helper dry-run passed every target and protected-slot check immediately before the write.

## Single call record

- Host start: 2026-09-17T23:01:55.4821916+08:00
- Binder/helper write timestamp: epoch `1789657315429`, corresponding to 2026-09-17T23:01:55.429+08:00
- Host end: 2026-09-17T23:01:56.5913405+08:00
- Helper result: `RETURNED_NO_EXCEPTION`
- Binder method: `ITelephony.resetIms(1)`
- Number of resetIms writes: exactly 1

## IMS lifecycle

The call reached Qualcomm IMS and exercised the expected paired slot1 path:

- 23:01:55.429: `QImsService ImsService : disableIms :: slotId=1`
- 23:01:55.431: registration-change request token 71, SUB1, disable state
- 23:01:55.431: `QImsService ImsService : enableIms :: slotId=1`
- 23:01:55.431: registration-change request token 72, SUB1, enable state
- 23:01:55.471: IMS Radio returned responses for both tokens
- 23:01:56.934: Qualcomm IMS queried registration state
- 23:01:56.934: query returned NOT_REGISTERED with error 999, `General_Error17-Unable to connect`, radioTech 18 (IWLAN)
- 23:01:56.935 onward: framework remained NOT_REGISTERED; MMTEL binder remained READY

The reset does not perform an ImsResolver feature remove/add/rebind. It sends a paired registration off/on to the already-bound slot1 Qualcomm IMS service.

## Observation

Continuous full-buffer logcat covers the entire operation through the 120-second endpoint. Probe snapshots were captured immediately after return and at subsequent checkpoints. The nominal 10/15/20/30-second probe files were delayed by host runner scheduling and actually landed around 31–35 seconds; the continuous logcat covers that gap without interruption. Checkpoints near 45, 60, 90, and 120 seconds landed on schedule.

Every probe retained:

- ACTIVE / UICC ENABLED
- MMTEL READY
- PS/WLAN HOME
- IMS NOT_REGISTERED (0)
- transport UNKNOWN (-1)
- VOICE/IWLAN unavailable
- WFC unavailable
- qti.cne IMS request null
- ePDG UDP/4500 absent
- XFRM absent
- Failure class F1

No `com.qualcomm.qti.cne` IMS NetworkRequest reached TelephonyNetworkFactory[1] or DNC-1 during the test.

## Slot0 protection

PASS.

- China Telecom remained subId 1 / slot 0 / carrierId 2237 / MCC-MNC 460-11.
- UICC applications remained enabled.
- Default and active data subId remained 1.
- No slot0 `disableIms`, `enableIms`, or IMS registration-change request appears in the test log.

## Conclusion

One slot1-scoped IMS registration off/on cycle is insufficient to restart the missing Qualcomm IMS -> qti.cne request-generation path in this preserved ACTIVE + ENABLED + F1 state. Qualcomm IMS accepted both registration-change commands, but its follow-up query immediately returned `General_Error17-Unable to connect`; no CNE IMS demand or ePDG/XFRM path followed.

The failure scene is preserved. No further experiment was entered.

