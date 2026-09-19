# VOXI WFC Recovery v2.0

Device-specific Magisk recovery tooling for VOXI Wi-Fi Calling on the validated Xiaomi 14 Pro dual-SIM configuration.

## Fixed device identity

- China Telecom: slot 0, phoneId 0, subId 1, carrierId 2237, MCCMNC 46011.
- VOXI: slot 1, phoneId 1, subId 11, carrierId 28, MCCMNC 23415.
- Targets are fixed. No command accepts arbitrary SIM, slot, phone, or subscription identifiers.

## Recommended recovery

`full-recover` is the preferred strict-F1 recovery because it most closely reproduces the reliable physical lifecycle:

1. Verify strict active-but-broken F1 and both SIM identities.
2. Disable VOXI UICC applications once.
3. Confirm persistent F8 twice, including the inactive recovery helper gate.
4. Atomically persist and sync a pending marker.
5. Reboot exactly once.
6. On the new boot, verify the new boot ID and persistent F8 again.
7. Wait up to five minutes for validated Wi-Fi and VPN/TUN readiness.
8. Hold the network stable for 30 seconds and recheck every safety gate.
9. Enable VOXI UICC applications once.
10. Wait up to 120 seconds for direct IMS/WFC health.

Success requires IMS `REGISTERED(2)`, transport `WLAN(2)`, VOICE over IWLAN available, Wi-Fi Calling available, and the protected slot 0 gate still passing.

## Commands

Run through Magisk root, replacing `<module>` with the installed module path.

```sh
su -c '<module>/bin/wfcctl.sh status'
su -c '<module>/bin/wfcctl.sh status-json'
su -c '<module>/bin/wfcctl.sh full-status'
su -c '<module>/bin/wfcctl.sh full-recover'
su -c '<module>/bin/wfcctl.sh full-cancel'
```

`full-recover` intentionally disables VOXI and reboots the phone once. Run it only when the phone is in the known strict F1 state and the UK Wi-Fi/VPN environment can return after boot.

`full-cancel` only removes the lifecycle marker. It never changes UICC state. If cancellation happens while F8 is present, VOXI may remain disabled and the command prints a warning.

Existing `safe-recover`, `deep-recover`, and `recover-hard` commands remain available. They retain their v1.3 behavior. For this device, prefer `full-recover` for strict F1.

## Lifecycle state

The pending record is stored at:

`/data/adb/voxi-wfc-recovery/state/full_recover_pending`

Visible states are `WAITING_FOR_REBOOT`, `WAITING_FOR_NETWORK`, `WAITING_TO_INSERT`, `WAITING_FOR_WFC`, `FAILED`, and `COMPLETE`. A successful run archives `COMPLETE` in `full_recover_last` and removes the pending record.

The marker records whether false, reboot, and true have been attempted. The maximum for one lifecycle is one each. A failure is terminal: no automatic retry, second reboot, or second SIM write occurs.

## Action and boot behavior

The Magisk Action is status-only and performs zero recovery writes. It shows the full lifecycle state, boot-auto setting, network prerequisites, and current WFC health.

At boot, a pending full lifecycle is handled before normal v1.3 boot-auto logic. Without a pending marker, existing boot behavior is unchanged. `AUTO_RECOVER_BOOT` remains disabled by default and an existing setting survives upgrades.

## Safety boundaries

The package contains no IMS reset, vendor process restart, radio/modem reset, SSR, qcrild restart, airplane-mode toggle, settings mutation, or property mutation path. It does not turn Wi-Fi or VPN on; it only waits for the user environment to become ready.

## Installation

Install `VOXI-WFC-Recovery-v2.0.zip` in Magisk and reboot. This build task does not install the package.