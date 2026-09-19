# VOXI WFC Recovery v1.3 FINAL

This is a device-specific Magisk recovery module produced from real-device research on one Xiaomi 14 Pro running HyperOS with VOXI in slot 1. It is fixed to VOXI subId 11, slot/phoneId 1, carrierId 28, MCCMNC 23415, while protecting China Telecom subId 1 in slot 0, MCCMNC 46011. It is not a general recovery module for other phones, SIM layouts, or carriers.

## Proven recovery boundary

The only repeatedly successful recovery mechanism is:

```text
software remove: setUiccApplicationsEnabled(false, 11) exactly once
  -> persistent F8/inactive confirmed twice
software insert: setUiccApplicationsEnabled(true, 11) exactly once
  -> wait up to 120 seconds for direct WFC health
```

Deep Recover is not guaranteed to succeed. If the insert completes but direct health does not return within 120 seconds, v1.3 stops with `DEEP_RECOVERY_FAILED` and `HARD RECOVERY REQUIRED`. It never retries false/true and never reboots automatically.

The following experiments failed and are intentionally excluded from executable recovery logic: `resetIms(1)`, restarting `org.codeaurora.ims`, restarting `.qtidataservices`, restarting `vendor.cnd`, and coordinated `vendor.cnd -> .qtidataservices` restart.

## Direct health rule

`HEALTHY/F0` requires all four conditions:

- IMS registration state `REGISTERED (2)`
- registration transport `WLAN (2)`
- MMTEL VOICE over IWLAN available
- `isWifiCallingAvailable(11) == true`

NetworkAgent, qti.cne, UDP/4500, XFRM, and MMTEL READY are supporting diagnostic evidence, not hard health conditions.

## Commands

Run as root using the installed module path:

```sh
wfcctl.sh status
wfcctl.sh status-json
wfcctl.sh safe-recover
wfcctl.sh deep-recover
wfcctl.sh recover-hard
wfcctl.sh auto-enable
wfcctl.sh auto-disable
wfcctl.sh auto-status
wfcctl.sh auto-run-now
```

- `status` and `status-json` are read-only.
- `safe-recover` writes only one fixed `true,11`, and only from verified F8/inactive/apps-disabled state.
- `deep-recover` is a manual strict-F1 operation: one false, persistent F8 confirmation, one true, then probes at 5/10/15/20/30/45/60/90/120 seconds.
- `recover-hard` performs one safe classification: HEALTHY is zero-write, F8 uses Safe Recover once, and strict F1 uses Deep Recover once. Failure only prints the hard-recovery guidance; it never reboots.
- `auto-run-now` is a manual network-aware orchestration and is independent of the boot attempt marker.

## Boot Auto Recovery

Boot automation is disabled by default. When explicitly enabled, the one-shot boot service waits for boot completion, validated Wi-Fi, validated VPN/TUN, and 20 seconds of network stability. HEALTHY exits with zero writes. F8 invokes Safe Recover once. Strict F1 is confirmed again after 30 seconds before one Deep Recover attempt.

Only boot mode uses the boot-ID attempt marker, limiting automatic Deep Recover to once per boot. Manual `deep-recover`, `recover-hard`, and `auto-run-now` do not consult or create that marker. Every recovery path still uses the atomic `mkdir` lock and complete dual-SIM gate.

The persistent configuration is `/data/adb/voxi-wfc-recovery/config.conf`. Installation creates `AUTO_RECOVER_BOOT=0` only when the file does not already exist, so upgrades preserve an existing enabled value.

## Hard recovery

After a failed Deep Recover:

1. Keep the UK VPN and Wi-Fi environment ready.
2. Reboot the device once.
3. Allow boot auto recovery to run if enabled.
4. Otherwise run manual Deep Recover only once.

No module command automatically toggles airplane mode, resets radio/modem/IMS, restarts vendor processes, changes settings/properties, or reboots the phone. The ZIP is generated only; it is not installed automatically.
