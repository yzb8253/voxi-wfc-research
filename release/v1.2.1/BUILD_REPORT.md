# Build Report

## Artifact

- Product: VOXI WFC Recovery
- Version: v1.2.1
- Version code: 121
- ZIP: `VOXI-WFC-Recovery-v1.2.1.zip`
- ZIP SHA-256: `6E76F8A3B0365FEBE16B76757436F9A3B6BBC8ED90FC21637D560494D5C50271`
- Installation performed during build: no

## Device evidence

- Device: `fd0ff892`.
- Current persistent configuration: `AUTO_RECOVER_BOOT=1`.
- Wi-Fi: connected NetworkAgent, INTERNET, VALIDATED.
- VPN: connected network 101, `WIFI|VPN`, INTERNET, VALIDATED, underlying Wi-Fi network 100.
- TUN: `tun0` UP/LOWER_UP with a default route through `tun0`.
- Protected China Telecom slot0 gate: PASS.
- The live WFC probe was F1 during this build; the preserved scene was not modified.

## Configuration persistence

PASS. `customize.sh` uses an existence guard around the only default write:

```sh
if [ ! -f /data/adb/voxi-wfc-recovery/config.conf ]; then
  printf 'AUTO_RECOVER_BOOT=0\n' > /data/adb/voxi-wfc-recovery/config.conf
fi
```

The service and restart paths only read this file. They do not reset it.

## Verification

- Android `/system/bin/sh -n` via ADB stdin for all source shell scripts: PASS; no device file was written.
- Device-specific Wi-Fi readiness combination: READY.
- Device-specific VPN/TUN readiness combination: READY.
- Current configuration re-read: `AUTO_RECOVER_BOOT=1`.
- Helper JAR hashes versus v1.2: identical.
- Recovery state machine diff: unchanged except command dispatch/version metadata.
- Automatic Deep Recover invocation count in shared orchestrator: one.
- VPN timeout/stabilization exits precede attempt-marker creation: PASS.
- Strict-F1 double-check precedes attempt-marker creation: PASS.
- HEALTHY branch exits before strict-F1 handling, marker creation, or Deep Recover: PASS.
- ZIP root structure and extracted shell syntax: PASS.

No reboot, Deep Recover, Safe Recover, false/true helper call, fault injection, resetIms, or phone/network state modification was performed during v1.2.1 work. Because the live device was F1 at build time, HEALTHY zero-write was verified by unchanged v1.2 regression evidence plus v1.2.1 static control-flow audit rather than by altering the device into a test state.
