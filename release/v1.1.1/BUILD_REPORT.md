# Build Report

## Artifact

- Product: VOXI WFC Recovery
- Version: v1.1.1
- Version code: 111
- ZIP: `VOXI-WFC-Recovery-v1.1.1.zip`
- ZIP SHA-256: `62E422D6A9A995656FD90237903DE1DCE6844E5E3FE337E3580DFA7685CDCD10`
- WebUI: not included
- Installation performed during build: no

## Change scope

The only executable engineering change from v1.1 is the recovery lock implementation in `bin/wfcctl.sh`: the FD-based `flock` branch was removed and replaced by one atomic `mkdir` path with explicit local ownership tracking. Version metadata and release documentation were updated for v1.1.1. JAR payloads and all Telephony/recovery logic are unchanged.

## Verification

- Target device: USB ADB serial `fd0ff892`.
- Installed source before hotfix: v1.1 (`versionCode=110`).
- Toybox: 0.8.6; `flock` accepts an FD and the former path reproduced `Bad file descriptor`.
- Original device script backup: `/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh.bak`.
- Android `/system/bin/sh -n`: PASS.
- Forbidden-operation source scan: PASS.
- Strict pre-run F1 and complete dual-SIM safety gate: PASS.
- Deep Recover writes: exactly one `false,11`, confirmed F8 after 5 seconds, exactly one `true,11`.
- Direct WFC health restored in 19 seconds.
- Stability: 7/7 healthy samples over approximately 79 seconds.
- Protected China Telecom slot0: PASS in every sample.
- ZIP root structure and extracted shell syntax: PASS.

The v1.1.1 ZIP was not installed on the device.
