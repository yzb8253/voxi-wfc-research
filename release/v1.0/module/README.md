# VOXI WFC Recovery v1.0

This Magisk module provides an on-device status command and a narrowly scoped recovery for the validated Xiaomi 14 Pro dual-SIM environment.

## Fixed identities

- Protected: China Telecom slot0, phoneId0, subId1, carrierId2237, MCCMNC46011.
- Target: VOXI slot1, phoneId1, subId11, carrierId28, MCCMNC23415.

## Usage

Use the Magisk Action button, or run as root:

```sh
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh status'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh recover'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh diagnose'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh version'
```

The controller itself resolves its module directory dynamically. The example path above is only the normal Magisk CLI location.

## Safety state machine

- Healthy: no write.
- Inactive/apps disabled: the Java helper revalidates the historical VOXI record and protected slot0, then permits exactly one fixed `ISub.setUiccApplicationsEnabled(true,11)` call.
- Active but abnormal: no write; diagnostics and the failure class are shown.

There is no boot recovery, background service, daemon, radio reset, IMS reset, airplane-mode toggle, process kill, property change, or CarrierConfig write.

Logs and diagnostics are stored under `/data/adb/voxi-wfc-recovery/` with restrictive permissions and redaction. Uninstall removes only this module's external logs and state; it never changes SIM/UICC state.

## PC tools

The release `reference/` directory preserves the ADB/PowerShell status and recovery tools. The PC and Magisk versions use the same validated safety model.
