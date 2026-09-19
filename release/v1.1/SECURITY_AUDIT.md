# Security Audit

## Fixed scope

- Target VOXI: subId11, slot1, phoneId1, carrierId28, MCCMNC23415.
- Protected China Telecom: subId1, slot0, carrierId2237, MCCMNC46011.
- Helpers accept only fixed mode words and no caller-supplied target identifiers.
- Both Java write helpers require UID 0 and revalidate their expected state and both SIM identities.

## Allowed Telephony writes

- Safe Recover: exactly one fixed `ISub.setUiccApplicationsEnabled(true,11)` after inactive/apps-disabled validation.
- Manual Deep Recover: exactly one fixed `ISub.setUiccApplicationsEnabled(false,11)`, mandatory F8/inactive confirmation, then exactly one fixed `ISub.setUiccApplicationsEnabled(true,11)`.
- No retry loop invokes either write a second time.

## Deep Recover barriers

- Requires ACTIVE + UICC enabled + F1 + NOT_REGISTERED + WFC false.
- Requires complete target and protected-slot safety gates.
- Runs the remove helper's independent dry-run gate before false.
- Blocks true unless F8 plus inactive/apps-disabled is observed within 30 seconds.
- Stops after 60 seconds if direct health does not return.
- Safe and Deep Recover share one nonblocking `flock`; an atomic-directory fallback exists only for environments without a flock applet.

## Forbidden operation scan

Executable shell and Java sources were scanned for resetIms, disableIms, enableIms, `cmd phone`, radio reset, airplane toggles, reboot, kill, setprop, settings writes, CarrierConfig writes, and SELinux changes. No executable occurrence was found. Documentation names prohibited operations only to state that they are absent.

The module contains no boot service, daemon, `system.prop`, sepolicy rule, package patch, framework patch, or WebUI.

## Health safety

The core health decision uses only REGISTERED(2), WLAN(2), VOICE/IWLAN availability, and WFC availability. NetworkAgent, qti.cne, UDP/4500, XFRM, and MMTEL READY are displayed as supporting evidence and cannot turn directly healthy WFC into BROKEN.

## Test boundary

Only syntax, structure, healthy status, and healthy Action zero-write tests were run. Neither write helper was invoked in write mode during v1.1 engineering.
