# Frozen v1.0 Reference

This directory freezes the validated PC entry points, Android Java sources, and exact helper JARs used to build VOXI WFC Recovery v1.0.

- `WfcStateProbe.java` / `wfc-state-probe.jar`: read-only unified state probe.
- `Slot1UiccRecoverHelper.java` / `slot1-uicc-recover.jar`: fixed-target inactive recovery helper.
- `voxi_wfc_status*.ps1` and `voxi_wfc_recover*.ps1`: PC/ADB tools as validated at release time.

The wrapper PowerShell files retain their original relative layout assumptions. Use the project-root PC tools for normal operation.
