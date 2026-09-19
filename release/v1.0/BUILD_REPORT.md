# VOXI WFC Recovery v1.0 Build Report

## Result

- Core recovery: VALIDATED 3/3
- Magisk module: PASS
- Action button: PASS
- Healthy-state zero-write test: PASS
- Safety gate: PASS
- Optional WebUI: NOT INCLUDED
- Automatic boot/background behavior: NONE

## Build Identity

- Module ID: `voxi_wfc_recovery`
- Name: `VOXI WFC Recovery`
- Version: `v1.0`
- Version code: `100`
- Target: Xiaomi 14 Pro / HyperOS / Qualcomm / Magisk

## Frozen Inputs

The release `reference/` directory contains the validated PC scripts, Java sources, and exact helper JARs. The module JAR SHA-256 values match their frozen reference copies.

## Static Tests

- Android `/system/bin/sh -n`: PASS for `action.sh`, `customize.sh`, `uninstall.sh`, and `bin/wfcctl.sh`.
- JAR structure: PASS; each helper archive contains `classes.dex`.
- ZIP structure: PASS; `module.prop`, `customize.sh`, `action.sh`, `uninstall.sh`, `bin/`, `lib/`, and `README.md` are at the archive root.
- Absent by design: `system.prop`, `sepolicy.rule`, `post-fs-data.sh`, `service.sh`, WebUI, daemon, and boot recovery.

## Device Tests

The module was not installed. A temporary copy under `/data/local/tmp` was used only for read-only healthy-state tests.

- `wfcctl.sh status`: PASS, result `HEALTHY`, failure class `F0`.
- Direct fingerprint: REGISTERED, WLAN, VOICE/IWLAN available, WFC available, IMS NetworkAgent active, ePDG active.
- `action.sh`: PASS; printed `WFC already healthy` and `No action required`.
- Telephony writes during tests: ZERO.
- Fault injection: NOT PERFORMED.

## Artifact

- ZIP: `C:\Users\ZJH\Desktop\platform-tools\voxi_wfc_research\release\v1.0\VOXI-WFC-Recovery-v1.0.zip`
- SHA-256: `858E55BDE41C874D717CD7F20B3FF4E098562241ADB35B597B587F5660FAD22A`

## Manual Installation

1. Transfer `VOXI-WFC-Recovery-v1.0.zip` to the phone by the user's preferred method.
2. Open Magisk 30.7, choose Modules, then Install from storage.
3. Select the ZIP and review the installer output.
4. Complete Magisk's normal activation flow manually if prompted.
5. Use the module's Action button or the documented root CLI.

No installation, module activation, reboot, or Telephony state change was performed during this build.
