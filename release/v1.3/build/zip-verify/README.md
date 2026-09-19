# VOXI WFC Recovery v1.3 FINAL

Device-specific module for Xiaomi 14 Pro / HyperOS / VOXI slot1 subId11 MCCMNC23415, with China Telecom slot0/subId1 protected. Do not use it on a different mapping.

Direct HEALTHY requires REGISTERED(2), WLAN(2), VOICE/IWLAN available, and WFC available. NetworkAgent, qti.cne, UDP/4500, XFRM, and MMTEL READY are supporting evidence only.

Commands:

```sh
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh status'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh status-json'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh safe-recover'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh deep-recover'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh recover-hard'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh auto-enable'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh auto-disable'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh auto-status'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh auto-run-now'
```

Magisk Action is status-only and always performs zero Telephony writes.

Safe Recover handles only verified inactive/apps-disabled F8 and calls fixed `true,11` once. Deep Recover handles only verified active/enabled strict F1, calls fixed `false,11` once, requires two persistent F8 samples, calls fixed `true,11` once, and waits up to 120 seconds. There are no automatic retries.

Boot Auto Recover defaults to disabled and is limited to one Deep Recover attempt per boot. Manual Deep Recover, Recover Hard, and Auto Run Now are independent of the boot marker but retain the shared atomic recovery lock and all safety gates.

Deep Recover is not 100% successful. On failure the module prints `HARD RECOVERY REQUIRED`; it never reboots or escalates to resetIms, process restarts, radio/modem reset, SSR, or airplane toggles.
