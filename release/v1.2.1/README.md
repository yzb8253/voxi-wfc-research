# VOXI WFC Recovery v1.2.1 Release

v1.2.1 is a timing and configuration-persistence hotfix based on v1.2. It preserves Safe Recover, Deep Recover, the atomic `mkdir` recovery lock, all fixed dual-SIM safety gates, the four-condition direct health rule, and the one-attempt-per-boot limit.

## Persistent opt-in configuration

Boot Auto Recover remains opt-in. `/data/adb/voxi-wfc-recovery/config.conf` is external to the replaceable Magisk module directory. During installation or upgrade, `customize.sh` creates `AUTO_RECOVER_BOOT=0` only if that file does not exist. An existing value—including the user's current `AUTO_RECOVER_BOOT=1`—is never overwritten.

## Network-aware sequence

When boot automation is enabled, the one-shot service follows this sequence:

```text
boot_completed=1
  -> validated Wi-Fi NetworkAgent ready (up to 5 minutes)
  -> validated VPN-over-Wi-Fi NetworkAgent + active TUN + TUN default route ready (up to 5 minutes)
  -> prerequisites remain ready for 20 seconds
  -> first WFC probe
  -> HEALTHY: zero write and exit
  -> strict F1: wait 30 seconds
  -> second strict F1 + complete dual-SIM gate
  -> one boot-attempt marker
  -> existing wfcctl.sh deep-recover, at most once
```

The VPN gate is based on this device's observed Android state: a connected `WIFI|VPN` NetworkAgent with INTERNET and VALIDATED, an associated `tunN` interface that is UP/LOWER_UP, and a default route through that same interface. Detection is read-only. The module never starts or changes Wi-Fi, VPN, location, airplane mode, or routing.

If Wi-Fi/VPN is unavailable or lost during the 20-second stabilization period, the flow exits with zero Telephony writes before creating the boot-attempt marker.

## Commands

```sh
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh auto-status'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh auto-enable'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh auto-disable'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh network-status'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh auto-run-now'
```

`auto-run-now` bypasses only the boot/config trigger. It uses the same network gates, 20-second stabilization, strict-F1 double-check, boot-attempt limit, safety gates, and existing Deep Recover state machine.

The ZIP is not installed automatically.
