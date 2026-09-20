# Stabilized Absent + Second Reinsert Result

Date: 2026-09-20
Result: FAIL
Final state: ACTIVE + UICC ENABLED + F1

## Scope and write accounting

- Fixed target: VOXI slot 1 / phoneId 1 / subId 11.
- Protected target: China Telecom slot 0 / subId 1.
- Actual POWER_DOWN API callbacks: 2, both result 0.
- Actual POWER_UP API callbacks: 2, both result 0.
- Soft-stack rebuilds: 1.
- Third POWER_DOWN: never executed.
- Forbidden modem/SSR/radio/airplane/reboot/ISub/resetIms operations: none.

## First absent-state cycle

- T0 15:42:05.840: first POWER_DOWN callback result 0.
- T1 15:42:07: true ABSENT confirmed: active=false, UICC apps disabled, SIM state ABSENT, slot mapping lost. Slot0 remained READY and mapped.
- T2 15:42:17: soft-stack restart began after an exact 10-second absent hold.
- Exact live PIDs were re-resolved before each TERM. The fixed order completed: qcrild2, qcrild, netmgrd, imsqmidaemon, imsdatadaemon, cnd, qtidataservices, Qualcomm IMS, com.android.phone, system_server.
- T3 15:42:33: new system_server PID observed.
- 15:42:43: final post-system_server Java process PIDs resolved.
- T5 15:44:46: continuous 15-second stability gate passed.
- At 15:45:06, the extra 20-second check reached the 180-second normal-POWER_UP limit, so the orchestrator correctly did not call POWER_UP.

## Rollback defect and restoration

The 300-second watchdog fired at 15:47:05, but the helper's rollback arm lifetime was only five minutes from 15:42:00.437. It had expired about five seconds before watchdog execution. The helper rejected POWER_UP before the Telephony API, so no callback occurred.

The same-boot fixed-target arm was validated and extended only to complete the authorized rollback. An initial shell arithmetic attempt overflowed to a negative millisecond value and was rejected before API invocation. With non-overflowing expiry construction, POWER_UP was called once and returned callback result 0 at 15:53:50.190.

By 15:58:16 the complete slot1 mapping, ACTIVE subscription, UICC ENABLED, IWLAN/HOME, and MMTEL READY had returned, but direct health remained strict F1 with no IMS demand, CNE IMS request, ePDG, or WFC.

## Second and final reinsert

All cycle2 gates passed while the device was ACTIVE + ENABLED strict F1 and slot0/network remained protected.

- T12 16:03:07.899: second and final POWER_DOWN callback result 0.
- T13 16:03:09: true ABSENT confirmed.
- No process was restarted in cycle2.
- T14 16:03:19.517: second and final POWER_UP callback result 0 after a 10-second absent hold.
- The 90-second watchdog observed the callback marker and exited without a duplicate POWER_UP.

Read-only samples from approximately 47 through 182 seconds after the second POWER_UP were identical: ACTIVE, UICC ENABLED, mapping restored, IWLAN/HOME, MMTEL READY, but strict F1.

## Final direct state

- IMS registration: NOT_REGISTERED (0).
- Registration transport: UNKNOWN (-1).
- VOICE over IWLAN: unavailable.
- Wi-Fi Calling availability: false.
- qti.cne IMS request: absent.
- IMS NetworkAgent: absent.
- UDP/4500 keepalive: absent.
- XFRM tunnel: absent.
- China Telecom slot0 mapping: protected throughout.
- wlan0/tun0: remained ready at every write gate.

## Conclusion

`STABILIZED_ABSENT_SOFT_REBOOT = FAIL`.

`SECOND_REINSERT_RECOVERY = FAIL`.

The failure is substantive. Even after true ABSENT, one complete userspace soft-stack rebuild, a stable framework/service window, successful first insertion, and a second clean remove/reinsert against the rebuilt stack, the missing native IMS data demand did not reappear. The full AP reboot success therefore depends on a boot-only boundary or ordering effect not recreated by this userspace stack.

No further SIM power cycle is authorized or recommended from this experiment. The current phone state is safely restored to ACTIVE + UICC ENABLED F1 with slot0 intact.