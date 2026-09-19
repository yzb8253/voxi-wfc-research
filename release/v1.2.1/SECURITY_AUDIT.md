# Security Audit

## Preserved safety boundary

- Target VOXI remains fixed to subId11, slot1, phoneId1, carrierId28, MCCMNC23415.
- Protected China Telecom remains fixed to subId1, slot0, carrierId2237, MCCMNC46011.
- Direct health remains REGISTERED(2) + WLAN(2) + VOICE/IWLAN available + WFC available.
- NetworkAgent remains supporting WFC evidence; it is used only as a prerequisite for VPN readiness.
- Safe Recover, Deep Recover, fixed helper JARs, complete safety gates, and atomic `mkdir` recovery lock are unchanged.

## Read-only network gates

Wi-Fi readiness requires an actual connected Wi-Fi NetworkAgent with INTERNET and VALIDATED. VPN/TUN readiness requires all of:

- a connected VPN NetworkAgent;
- `WIFI|VPN` transport;
- INTERNET and VALIDATED capabilities;
- an associated `tunN` interface;
- UP and LOWER_UP kernel interface flags;
- a default route through the same `tunN` interface.

The module uses only `dumpsys connectivity`, `ip link`, and `ip route` reads. It has no command that enables/switches VPN or Wi-Fi, changes location or airplane mode, or writes routes.

## Orchestration barriers

- Missing Wi-Fi or VPN/TUN times out after five minutes with zero Telephony writes.
- A 20-second stabilization delay is followed by a fresh Wi-Fi and VPN/TUN recheck.
- Network failures occur before the boot-attempt marker, so they do not consume the attempt.
- HEALTHY exits before strict-F1 handling and with zero Telephony writes.
- Strict F1 and the complete dual-SIM gate must pass twice, 30 seconds apart.
- The boot-ID marker is created atomically only after both probes pass.
- Boot and `auto-run-now` share one orchestrator and one attempt limit.

## Only automatic Telephony write path

```text
service.sh or wfcctl.sh auto-run-now
  -> bin/wfc-auto-recover.sh
  -> wfcctl.sh deep-recover (single invocation site)
  -> fixed false,11 once
  -> confirmed F8/inactive
  -> fixed true,11 once
```

There is no second automatic call or retry.

## Configuration persistence

The only installation default write is guarded by `if [ ! -f config.conf ]`. Existing enabled configuration is preserved across module upgrades, and reboot code only reads it.

## Forbidden operations

Executable module code contains no FD/flock lock, resetIms, disableIms, enableIms, radio reset, airplane toggle, reboot, process kill, CarrierConfig write, settings write, setprop, SELinux change, VPN/Wi-Fi control, location change, or route modification path.
