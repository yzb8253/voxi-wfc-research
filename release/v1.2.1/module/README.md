# VOXI WFC Recovery v1.2.1

This Magisk module provides status, Safe Recover, diagnostics, and a separate manual Deep Recover command for one validated Xiaomi 14 Pro dual-SIM mapping.

## Fixed identities

- Protected: China Telecom slot0, phoneId0, subId1, carrierId2237, MCCMNC46011.
- Target: VOXI slot1, phoneId1, subId11, carrierId28, MCCMNC23415.

The target identifiers are compile-time constants. No command accepts an arbitrary subscription, slot, or phone ID.

## Commands

Run as root:

```sh
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh status'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh recover'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh diagnose'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh auto-enable'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh auto-disable'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh auto-status'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh auto-run-now'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh network-status'
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh version'
```

Manual experimental Deep Recover:

```sh
su -c '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh deep-recover'
```

The equivalent wrapper is `bin/wfc-deep-recover.sh`.

## Health rule

`HEALTHY` requires all four direct conditions:

- IMS registration state is REGISTERED (raw 2).
- IMS registration transport is WLAN (raw 2).
- MMTEL VOICE over IWLAN is available.
- `isWifiCallingAvailable(11)` is true.

IMS NetworkAgent, qti.cne, UDP/4500, XFRM, and MMTEL READY are supporting evidence. A missing supporting field does not override healthy direct IMS/WFC state.

## Safe Recover

The Magisk Action remains conservative:

- Healthy: zero writes.
- Inactive or UICC-apps-disabled VOXI: revalidate both SIM identities, then make exactly one fixed `ISub.setUiccApplicationsEnabled(true,11)` call.
- Active but broken F1: report that Deep Recover is available, but do not run it.

## Deep Recover

Deep Recover is manual. It proceeds only when the complete dual-SIM gate passes and VOXI is ACTIVE, UICC apps are ENABLED, failure class is F1, IMS is NOT_REGISTERED, and WFC availability is false.

Its fixed state machine is:

1. Revalidate F1 and both SIM identities.
2. Make exactly one fixed `ISub.setUiccApplicationsEnabled(false,11)` call.
3. Wait up to 30 seconds for confirmed F8/inactive or apps-disabled state.
4. Only after that confirmation, make exactly one fixed `ISub.setUiccApplicationsEnabled(true,11)` call.
5. Wait up to 60 seconds for the four direct health conditions.

There are no retries. If F8 is not confirmed, the true call is blocked. The module never calls resetIms, disableIms, enableIms, radio reset, airplane-mode toggles, reboot, process kill, settings writes, property writes, or CarrierConfig writes.

Safe and Deep Recover share one atomic `mkdir` lock. The process removes the lock directory only when it acquired that lock itself; an existing lock is never removed automatically. Logs are stored under `/data/adb/voxi-wfc-recovery/logs/` with restrictive permissions and identifier redaction.

## Boot Auto Recover

Boot Auto Recover is disabled by default. `auto-enable` writes `AUTO_RECOVER_BOOT=1` to `/data/adb/voxi-wfc-recovery/config.conf`; `auto-disable` writes `AUTO_RECOVER_BOOT=0`.

When enabled, `service.sh` runs once per boot: it waits for boot completion, waits up to five minutes each for an established Wi-Fi network and a validated VPN NetworkAgent backed by an active TUN interface/default route, waits another 20 seconds for those prerequisites to remain stable, probes WFC, requires strict F1 twice 30 seconds apart, creates one boot-ID attempt marker, and delegates the only possible Telephony write path to the existing `wfcctl.sh deep-recover` state machine. Healthy state, a failed gate, a changed second probe, unavailable networking, or an existing attempt marker all exit with zero Telephony writes.

`auto-run-now` uses the same network gates, 20-second stabilization, strict-F1 double-check, boot-attempt marker, and existing Deep Recover state machine. It is intended for a manual check after the user has established the required UK VPN and location environment. It never enables or changes those prerequisites.

Upgrade persistence is explicit: `customize.sh` creates `AUTO_RECOVER_BOOT=0` only when `/data/adb/voxi-wfc-recovery/config.conf` does not exist. An existing value, including `AUTO_RECOVER_BOOT=1`, is preserved.

The service never enables Wi-Fi, modifies VPN/location/airplane mode, runs a periodic watcher, or stays resident after its one boot flow. Boot logs are stored under `/data/adb/voxi-wfc-recovery/logs/boot/`.

The Magisk Action displays Boot Auto Recover status but keeps its original behavior. Enabling boot recovery does not make Action invoke Deep Recover.

No WebUI, daemon, property overlay, or SELinux modification is included. Uninstall removes only module-owned files and never changes SIM, UICC, or IMS state.
