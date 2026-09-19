# VOXI WFC Recovery v2.0

This module is device-specific. Its fixed mapping is China Telecom on slot 0/subId 1 and VOXI on slot 1/subId 11.

The recommended strict-F1 command is:

```sh
su -c "$MODDIR/bin/wfcctl.sh full-recover"
```

It performs exactly one software remove, confirms F8, persists a pending record, reboots once, waits for validated Wi-Fi and VPN/TUN after boot, performs exactly one software insert, and waits for direct WFC health. Failures are terminal and are not retried automatically.

Read-only commands:

```sh
su -c "$MODDIR/bin/wfcctl.sh status"
su -c "$MODDIR/bin/wfcctl.sh full-status"
su -c "$MODDIR/bin/wfcctl.sh network-status"
```

`full-cancel` only clears the pending workflow marker. It does not re-enable VOXI.

The Magisk Action is status-only. Boot Auto Recover remains disabled by default. A pending v2.0 full lifecycle always resumes before the older optional boot-auto policy.