# Absent-state Soft Reboot Retry Result

Date: 2026-09-20
Result: `FAIL_RECOVERY` (the authorized absent-state experiment ran; slot1 was restored, but WFC remained F1)

## Executive finding

The corrected run successfully reproduced the core software remove/insert lifecycle for VOXI and rebuilt the selected native/framework stack. It did not restore the missing IMS network demand. After slot1 returned active and UICC applications were enabled, the device reached IWLAN/HOME and MMTEL READY but remained IMS NOT_REGISTERED with no qti.cne IMS request, ePDG/XFRM, VOICE/IWLAN, or WFC availability.

This is substantive evidence that the selected absent-state soft stack is not equivalent to the known-good full reboot path.

## Timeline

- 13:53:23.563: fixed-slot1 `POWER_DOWN` requested.
- 13:53:23.667: `POWER_DOWN` callback returned 0.
- 13:53:25: slot1 card-down confirmed: subId11 inactive, mapping lost, UICC applications disabled, SIM state ABSENT.
- 13:53:25-13:53:34: qcrild2, qcrild, netmgrd, imsqmidaemon, imsdatadaemon, cnd, qtidataservices, org.codeaurora.ims, and com.android.phone were terminated once and relaunched.
- 13:53:34: system_server was terminated once. The new framework instance later appeared as PID19232.
- 13:53:42: the orchestrator''s readiness deadline expired before Telephony Binder was available. Its normal `POWER_UP` attempt failed locally with `Telephony is null` and no SIM-power API call.
- 13:53:56.628: CarrierConfig observed phoneId1 as ABSENT.
- 13:53:56.844: slot1 MMTEL connection existed with subId -1 and state UNAVAILABLE.
- 13:53:57.232: CarrierConfig `EVENT_CLEAR_CONFIG` for phoneId1.
- 13:53:57.666-13:53:57.931: no-SIM default config fetched for phoneId1.
- 13:55:23.684: independent watchdog issued its single fixed-slot1 fallback `POWER_UP`.
- 13:55:23.752: fallback callback returned 0.
- 13:55:24.717: CarrierConfig phoneId1 entered ESSENTIAL_LOADED.
- 13:55:24.180-13:55:24.470: ImsResolver reassigned slot1 MMTEL/RCS to subId11.
- 13:55:27.067: CarrierConfig phoneId1 entered LOADED.
- 13:55:27.318: slot1 MMTEL was added for subId11 and reported READY.
- 14:03:37: final direct probe remained F1, more than 8 minutes after successful fallback POWER_UP.

## Process rebuild

- qcrild2: 8330 -> 16677
- qcrild: 9201 -> 16823
- netmgrd: 1815 -> 17061
- imsqmidaemon: 26664 -> 17237
- imsdatadaemon: 26887 -> 17313
- vendor.cnd: 27097 -> 17387
- qtidataservices: 3532 -> 17558 during the scripted step; final Java process PID19988 after framework restart
- org.codeaurora.ims: 3553 -> 17944 during the scripted step; final PID20001 after framework restart
- com.android.phone: 9164 -> 18265 during the scripted step; final PID20045 after framework restart
- system_server: 2267 -> 19232

The orchestrator logged `FAIL system_server` because the new framework/Telephony services were not ready inside its deadline, not because system_server stayed dead.

## Final state

- VOXI identity: subId11 / slot1 / phoneId1 / carrierId28 / MCCMNC23415
- Subscription: ACTIVE
- UICC applications: ENABLED
- SIM state: READY
- IWLAN: PS/WLAN HOME, access network IWLAN, preferred=true
- IMS: NOT_REGISTERED (0)
- Registration transport: UNKNOWN (-1)
- MMTEL feature: READY
- VOICE/IWLAN: unavailable
- WFC availability: false
- Native IMS demand: no positive evidence
- qti.cne IMS request: absent
- IMS IWLAN NetworkAgent: absent
- UDP/4500 keepalive: absent
- XFRM tunnel: absent
- China Telecom: subId1 / slot0 / carrierId2237 / MCCMNC46011 active and correctly mapped
- wlan0: UP
- tun0: present and configured

## Requested result fields

- POWER_DOWN invoked: YES, exactly once
- POWER_DOWN callback: 0
- Card-down confirmed: YES
- Watchdog ready markers: both dedicated and generic markers present before POWER_DOWN
- Soft stack rebuild: all fixed targets were signaled once; system_server/Telephony readiness missed the normal-power-up deadline
- Normal POWER_UP callback: NONE; pre-API failure because Telephony Binder was unavailable
- Watchdog fallback used: YES, exactly once
- Fallback POWER_UP callback: 0
- SIM/UICC restored: YES
- subId11 restored: YES
- CarrierConfig remove/insert lifecycle: CONFIRMED
- ImsResolver -1 -> 11 lifecycle: CONFIRMED
- Native IMS demand: NO POSITIVE EVIDENCE
- qti.cne IMS request: NO
- ePDG/XFRM: NO
- IMS: NOT_REGISTERED (0)
- Transport: UNKNOWN (-1)
- VOICE/IWLAN: unavailable
- WFC: unavailable
- slot0 impact: transient framework service unavailability during system_server restart; final mapping/state PASS
- VPN/tun0 impact: final wlan0 UP and tun0 present/configured
- ABSENT_STATE_SOFT_REBOOT_RETRY: FAIL

## Safety and interpretation

- Actual POWER_DOWN count: 1
- Actual POWER_UP count: 1, watchdog fallback only
- No second POWER_DOWN or POWER_UP was issued.
- No modem SSR, radio toggle, airplane toggle, AP reboot, or unplanned process restart was executed.
- Raw captures remain outside Git.

The test proves that software card absence plus this broad process/framework restart can reconstruct Subscription, CarrierConfig, ImsResolver, and MMTEL state without reconstructing the missing CNE/ePDG/IMS-registration path. Further writes are not authorized by this result.

NEXT_ACTION: preserve the current active/enabled F1 scene. Do not repeat this candidate unchanged. Any new write experiment requires a distinct hypothesis and explicit authorization.
