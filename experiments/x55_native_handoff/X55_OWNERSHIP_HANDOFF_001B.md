# X55 Ownership Handoff 001B - qcrild2 Re-vote Follow-up

Date: 2026-09-23
Experiment ID: `X55-OWNERSHIP-HANDOFF-001B`
Result: `QCRILD2_RESTART_NO_VALID_REVOTE`

## Entry gate

`PASS`.

- Device `fd0ff892` online; Magisk UID 0; SELinux enforcing.
- `vendor.per_mgr` running; dynamic pm-service PID 31818.
- No `/dev/subsys_esoc0` owner.
- X55 OFFLINE; crash_count 0.
- `vendor.qcrild2` running as PID 13706 with exact command line `qcrild -c 2`.
- Both known holder PID files absent.

## Authorized writes

1. Cleared all logcat buffers once.
2. Executed exactly one `setprop ctl.restart vendor.qcrild2`.

No SIM cycle, primary qcrild restart, vendor.cnd action, location/VPN change, modem/radio reset, AP reboot, retry, or recovery action occurred.

## Observed result

- qcrild2 PID changed from 13706 to 873.
- pm-service remained PID 31818 and became the sole FD9 owner of `/dev/subsys_esoc0`.
- X55 changed from OFFLINE to ONLINE.
- crash_count remained 0.
- Holder files remained absent.
- The complete captured logcat showed the new qcrild2/RIL initialization.
- None of the four required Peripheral Manager lines appeared:
  - `PerMgrLib: QCRIL successfully registered for SDX55M`
  - `PerMgrLib: QCRIL voting for SDX55M`
  - `PerMgrSrv: QCRIL registered`
  - `PerMgrSrv: QCRIL voting for SDX55M`

The native ownership transition is device-confirmed, but a valid QCRIL register/vote sequence is not log-confirmed. Under the experiment's predefined classification, this is not a verified re-vote result.

## Evidence

- Sanitized files: `logs/20260923_162025/`
- Complete raw logcat, retained host-only:
  `C:\Users\ZJH\Desktop\platform-tools\voxi_wfc_local_runs\x55_ownership_handoff_001b_20260923_162025\logcat_all.raw.txt`
- Raw logcat size: 1,790,421 bytes
- Raw logcat SHA256: `D03FA79845B3D487D07842EFB4E47E6495DEADD0ADF6274D79B37A7E5B8BA4F1`

## Conclusion

`RESULT = QCRILD2_RESTART_NO_VALID_REVOTE`

qcrild2 restart correlated with native pm-service reacquisition and X55 ONLINE, but the required register/vote evidence was absent. Do not claim `VERIFIED_QCRILD2_REVOTE_NATIVE_REACQUIRE`.

NEXT_ACTION: stop. No additional recovery or process action is authorized.
