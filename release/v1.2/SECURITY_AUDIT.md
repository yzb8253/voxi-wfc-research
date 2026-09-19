# Security Audit

## Fixed identities and direct health

- Target VOXI: subId11, slot1, phoneId1, carrierId28, MCCMNC23415.
- Protected China Telecom: subId1, slot0, carrierId2237, MCCMNC46011.
- Direct health remains REGISTERED(2), WLAN(2), VOICE/IWLAN available, and WFC available.
- IMS NetworkAgent and other data-path observations remain supporting evidence only.

## Boot service barriers

- Automatic recovery is disabled unless the parsed configuration is exactly `AUTO_RECOVER_BOOT=1`.
- The service waits for boot completion, then 60 additional seconds.
- Network readiness is checked read-only every 10 seconds and is bounded at five minutes.
- Healthy state exits with zero Telephony writes.
- Strict F1 and both SIM identities must pass twice, 30 seconds apart.
- A boot-ID marker is created atomically immediately before the attempt; an existing marker blocks recovery.
- `service.sh` contains exactly one recovery invocation: `wfcctl.sh deep-recover`.
- `wfcctl.sh deep-recover` performs its own fresh safety probe before any write.
- Success or failure exits the service. There is no background process, unbounded watcher, or periodic recovery.

## Only automatic Telephony write path

```text
service.sh
  -> wfcctl.sh deep-recover
  -> fixed setUiccApplicationsEnabled(false,11), at most once
  -> confirmed F8/inactive
  -> fixed setUiccApplicationsEnabled(true,11), at most once
```

The Java helper JARs are byte-identical to v1.1.1. No retry path invokes either write a second time.

## Locking

- Recovery locking uses atomic `mkdir` only.
- FD redirection, `flock`, and `LOCK_FILE` are absent from executable module code.
- A process removes the recovery lock only if it acquired that lock itself.

## Forbidden operations

Executable module code has no resetIms, disableIms, enableIms, radio reset, airplane toggle, reboot, process kill, CarrierConfig write, settings write, setprop, SELinux change, Wi-Fi enable, VPN modification, or location modification path.

Uninstall removes only module-owned configuration, logs, state, and module files. It does not modify SIM, UICC, IMS, radio, or network state.
