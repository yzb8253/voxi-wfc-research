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

## Lock hotfix

- FD redirection and `flock` are absent from executable module code.
- Lock acquisition uses atomic `mkdir` on `/data/adb/voxi-wfc-recovery/state/recovery.lock.d`.
- An existing lock blocks recovery and is not automatically removed.
- Cleanup is gated by `LOCK_OWNED=true`, which is set only after this process successfully creates the lock directory.

## Recovery and health invariants

- Deep Recover still requires ACTIVE + UICC enabled + F1 + NOT_REGISTERED + WFC false and the complete target/protected-slot gates.
- The true call remains blocked until F8 plus inactive/apps-disabled is confirmed.
- Core health remains REGISTERED(2), WLAN(2), VOICE/IWLAN available, and WFC available.
- IMS NetworkAgent and other data-path observations remain supporting evidence only.

## Forbidden-operation scan

Executable shell and Java sources contain no recovery path for resetIms, disableIms, enableIms, radio reset, airplane-mode toggles, reboot, process kill, settings writes, property writes, CarrierConfig writes, or SELinux changes. The module contains no boot service, daemon, `system.prop`, sepolicy rule, framework patch, or WebUI.
