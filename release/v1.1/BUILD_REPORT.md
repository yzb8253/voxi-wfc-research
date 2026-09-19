# Build Report

## Artifact

- Product: VOXI WFC Recovery
- Version: v1.1
- Version code: 110
- ZIP: `VOXI-WFC-Recovery-v1.1.zip`
- ZIP SHA-256: `2EB715DD52D18C11FA7BFFACAAFBBBFA164CF1F0292057E215AADF168CD28149`
- WebUI: not included
- Installation performed during build: no

## Components

- `wfc-probe.jar`: read-only direct IMS/WFC and supporting-evidence probe.
- `wfc-recovery-helper.jar`: previously validated fixed `true,11` recovery helper.
- `wfc-deep-remove-helper.jar`: fixed `false,11` helper with root and complete dual-SIM identity gates.
- `wfcctl.sh`: status, Safe Recover, manual Deep Recover, diagnostics, and shared lock.
- `action.sh`: health-first Action; F1 reports the manual command and performs zero writes.

## Build

Java sources were compiled with `javac --release 8`. D8 from the existing local Phase 4 toolchain produced dex JARs. The module ZIP was generated with all Magisk files at the archive root.

## Tests

- Java compilation and D8 conversion: PASS.
- Android `/system/bin/sh -n` for all shell scripts: PASS.
- ZIP root structure: PASS.
- Current healthy status test: PASS.
- Current healthy Magisk Action test: PASS, return code 0.
- Healthy Action recovery-log directory before/after diff: empty, confirming zero recovery writes/log operations.
- Direct core health: REGISTERED(2), WLAN(2), VOICE/IWLAN available, WFC available.
- Protected China Telecom slot0 gate: PASS.
- Supporting evidence observed: qti.cne request registered, UDP/4500 present, XFRM present, MMTEL READY; dedicated IMS NetworkAgent missing without affecting HEALTHY.

No `recover` or `deep-recover` command was executed. No new fault was injected.
