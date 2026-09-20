# Modem-only Recovery Experiment

Date: 2026-09-20
Result: `NOT_TESTED`
Phone writes executed: 0

## Boot-baseline verification

The connected phone did not present evidence of a new AP boot epoch:

- Current kernel uptime at 14:50:06 CST: 172756 seconds (about 48 hours).
- Current boot ID: 8034952d-9ad8-4ccd-930a-c595cd7bcab4.
- `sys.boot_completed=1`.
- `ro.boot.bootreason=reboot,shell` describes the reason for the existing boot; it does not establish that the reboot was recent.
- Current telephony and framework PIDs match the processes created by the preceding absent-state soft-stack run.

Therefore this capture cannot be labeled a fresh post-reboot Golden baseline.

## Current direct state

- VOXI: subId11 / slot1 / phoneId1 / carrierId28 / MCCMNC23415
- China Telecom: subId1 / slot0 / carrierId2237 / MCCMNC46011
- Both subscription mappings: PASS
- UICC applications: ENABLED
- PS/WLAN: HOME
- Access network: IWLAN
- IWLAN preferred: true
- MMTEL feature: READY
- IMS: NOT_REGISTERED (0)
- Registration transport: UNKNOWN (-1)
- VOICE/IWLAN: unavailable
- WFC availability: false
- qti.cne IMS request: absent
- IMS IWLAN NetworkAgent: absent
- UDP/4500: absent
- XFRM: absent
- Failure class: F1

`POST_REBOOT_GOLDEN=FAIL`.

## Current-ROM restart-modem chain

Current-ROM DEX disassembly confirms:

1. `TelephonyShellCommand.handleRestartModemCommand()`
2. Requires `Binder.getCallingUid() == 0` and `TelephonyUtils.IS_USER == false`
3. Calls `TelephonyManager.getDefault().rebootRadio()`
4. Calls `ITelephony.rebootModem(getSlotIndex())`
5. `PhoneInterfaceManager.rebootModem(slotIndex)`
6. Enforces modify-phone-state/carrier privilege, clears Binder identity, and sends main-thread request 64
7. Handler calls `Phone.rebootModem(response)`
8. `Phone.rebootModem` calls `CommandsInterface.nvResetConfig(1, response)`
9. RIL request 121 calls `RadioModemProxy.nvResetConfig`
10. Current HIDL path calls `android.hardware.radio@1.5::IRadio.nvResetConfig`
11. Framework conversion maps Java reset type 1 to HAL reset type 0
12. Current-ROM HAL constants are: 0=RELOAD, 1=ERASE, 2=FACTORY_RESET

The requested path therefore selects RELOAD, not ERASE or FACTORY_RESET. The Java/framework path contains no AP-reboot fallback and no PDC, MBN, EFS, persist, firmware-flash, or factory-reset operation. It asks the radio HAL to reload NV and reboot the modem runtime.

## Blocking condition

This device reports:

- `ro.build.type=user`
- `ro.debuggable=0`
- release keys

On this build, `TelephonyUtils.IS_USER` is true. The shell command's condition therefore rejects `cmd phone restart-modem` even when launched through Magisk as UID0.

The command was not invoked merely to reproduce its deterministic permission denial. Bypassing the wrapper through a direct Binder/helper call was not authorized and was not attempted.

## Experiment disposition

- Fresh post-reboot Golden baseline: NOT ESTABLISHED
- Controlled F1 injection: NOT EXECUTED
- restart-modem static safety semantics: PASS for RELOAD versus ERASE/FACTORY_RESET
- restart-modem executable shell route: FAIL on this user build
- Actual modem restart: NOT EXECUTED
- AP reboot caused by this phase: NO
- SIM/UICC write: NO
- Process kill/restart: NO
- MODEM_ONLY_RECOVERY: NOT_TESTED

## Evidence handling

Raw framework/APK/DEX, dumpsys, process, connectivity, and logcat captures remain outside Git. Only this sanitized result is committed.

NEXT_ACTION: do not execute the shell command or bypass it. Re-establish a verifiable new boot epoch if a Golden Boot comparison is still required. Any direct fixed-target `ITelephony.rebootModem` helper would require a separate explicit authorization and a new dual-SIM safety review.
