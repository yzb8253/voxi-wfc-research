# Build Report

## Artifact

- Product: VOXI WFC Recovery
- Version: v1.2
- Version code: 120
- ZIP: `VOXI-WFC-Recovery-v1.2.zip`
- ZIP SHA-256: `CBD9E99E578E2186E6FC512E698B62CE8CA4437AE0AC2DDE8CDD95A4D8F5ECC3`
- Installation performed during build: no

## Base and unchanged recovery payload

v1.2 is based on v1.1.1. The probe, fixed `true,11` helper, and fixed `false,11` helper JARs are byte-identical to v1.1.1. Safe Recover, Deep Recover, direct health evaluation, the complete dual-SIM gates, and the atomic `mkdir` recovery lock remain intact.

## Added engineering

- One-shot Magisk `service.sh`, disabled by default through `/data/adb/voxi-wfc-recovery/config.conf`.
- Bounded boot, network, and strict-F1 confirmation waits.
- Atomic `/data/adb/voxi-wfc-recovery/state/boot_attempt_<boot_id>` marker.
- Configuration commands and Action status display.
- Per-boot logs under `/data/adb/voxi-wfc-recovery/logs/boot/`.

## Verification

- Current device before and after tests: HEALTHY/F0.
- Android `/system/bin/sh -n` for every module shell script: PASS.
- Configuration round trip: DISABLED -> ENABLED -> DISABLED, PASS.
- Final configuration: `AUTO_RECOVER_BOOT=0`, mode 0600.
- HEALTHY Action: PASS, zero recovery writes.
- HEALTHY service dry-run: PASS, zero recovery writes.
- Recovery-log file count before/after zero-write tests: unchanged (2 -> 2).
- Protected China Telecom slot0 gate: PASS.
- Static strict-F1 double-check and single boot-attempt audit: PASS.
- ZIP root structure and extracted Android shell syntax: PASS.

No reboot, fault injection, `false,11`, `true,11`, Safe Recover, or Deep Recover was executed during v1.2 testing.
