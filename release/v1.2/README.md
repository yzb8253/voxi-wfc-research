# VOXI WFC Recovery v1.2 Release

Install `VOXI-WFC-Recovery-v1.2.zip` through Magisk. The module is fixed to the validated Xiaomi 14 Pro dual-SIM identity documented in `module/README.md`.

v1.2 adds opt-in, once-per-boot F1 recovery orchestration around the existing v1.1.1 recovery state machine. Boot Auto Recover is disabled by default. Enable or disable it explicitly with:

```sh
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh auto-enable'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh auto-disable'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh auto-status'
```

When enabled, the service waits for boot completion plus 60 seconds, waits up to five minutes for an established Wi-Fi network, exits without recovery if WFC is healthy, and requires strict F1 with the complete dual-SIM gate twice 30 seconds apart. It then creates one atomic boot-ID attempt marker and invokes the existing `wfcctl.sh deep-recover` command at most once. It does not run as a daemon or periodic watcher.

The direct health rule remains REGISTERED(2) + WLAN(2) + VOICE/IWLAN available + Wi-Fi Calling available. IMS NetworkAgent remains supporting evidence, not a hard condition.

The v1.2 ZIP was built and tested from the current HEALTHY/F0 state. It was not installed, and no reboot, Deep Recover, false/true call, or fault injection was performed during v1.2 testing.
