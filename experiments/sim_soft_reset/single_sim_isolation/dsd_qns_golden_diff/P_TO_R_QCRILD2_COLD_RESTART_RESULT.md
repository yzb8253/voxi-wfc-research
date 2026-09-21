# P to R qcrild2 Cold Restart Result

Date: 2026-09-21

## Scope and safety

- Authorized write: exactly one native init restart of `vendor.qcrild2`.
- Target identity before restart: `/vendor/bin/hw/qcrild -c 2`, PID 1919, PPID 1, UID radio, SELinux domain `u:r:rild:s0`.
- Init definition: `/vendor/etc/init/qcrild.rc`, service `vendor.qcrild2`.
- Primary qcrild remained PID 1879 throughout.
- Kernel boot ID did not change. No AP reboot, modem reset, SIM power action, radio-power action, retry, or additional process restart occurred.
- Slot0 remained physically absent/inactive. VOXI retained subId 11, slot 1, phoneId 1, carrierId 28, and MCCMNC 23415.

## P baseline

`P_BASELINE=PASS`.

- VOXI subscription active; UICC applications enabled.
- PS/WLAN registration `HOME`; `mIsIwlanPreferred=true`.
- IMS `NOT_REGISTERED(0)` with transport `UNKNOWN(-1)`.
- VOICE/IWLAN unavailable and Wi-Fi Calling unavailable.
- No qti.cne IMS request, IMS NetworkAgent, UDP/4500 flow, or XFRM state.
- Native slot2 IMS qualified networks: `[UNKNOWN,IWLAN]`.
- DSD and WDS endpoints ready; IWLAN and modem capability enabled.

## One-shot restart

The single authorized state-changing command used Android init's native restart control for `vendor.qcrild2`.

- Old PID: 1919
- New PID: 855
- Restart count: 1
- New process remained stable through the 120-second observation window.

## Cold initialization evidence

- `performDataModuleInitialization` appeared in the new process at 10:03:48.180.
- A new `NetworkAvailabilityHandler` was constructed at 10:03:50.602.
- `IIWlan/slot2` reconnected at 10:03:50.596.
- The new process populated its first IMS qualified list at 10:03:50.635 as `[UNKNOWN,IWLAN]`.
- DSD/WDS/Auth readiness, IWLAN enablement, modem capability, global IWLAN preference, and `REG_HOME` were re-established.
- This is functional evidence of a fresh DSD-status population. The exact `generateDsdSystemStatusInd` method name was not emitted in Android logcat.

## Observation result

The desired R ordering never appeared.

- Before: IMS `[UNKNOWN,IWLAN]`.
- Immediately after cold initialization: IMS `[UNKNOWN,IWLAN]`.
- Later current vectors: empty; retained startup history still showed `[UNKNOWN,IWLAN]`.
- IMS `[IWLAN,UNKNOWN]`: not observed.
- Outbound IMS/IWLAN availability publication: not observed.
- qti.cne IMS request: not observed.
- UDP/4500 or XFRM: not observed.
- IMS remained `NOT_REGISTERED(0)` / `UNKNOWN(-1)`.
- VOICE/IWLAN and Wi-Fi Calling remained unavailable.

The restart caused a transient slot1 radio/UICC/framework rediscovery, but the final VOXI identity and active/enabled subscription state were unchanged. The primary qcrild PID and boot ID remained unchanged, with no evidence of modem reset or AP reboot.

## Verdict

`P_TO_R=NO`, classification `CASE_C`.

A cold initialization of fixed slot2 qcrild2 is not sufficient to convert the poisoned IMS qualified-network ordering to the reboot-clean ordering. The AP-reboot recovery boundary therefore includes state or ordering outside the lifetime of the slot2 qcrild2 process alone.

No Magic SIM cycle is proposed for immediate execution because the result is not CASE B/PARTIAL: the required native ordering/publication was not restored.

NEXT: stop and preserve the result. Any further experiment requires a new hypothesis and explicit authorization.
