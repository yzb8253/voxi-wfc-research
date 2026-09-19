# VOXI WFC automatic recovery design

## Repository assessment

The repository already contains the complete experimental history, raw Android/Qualcomm evidence, a fixed-mapping probe, guarded UICC helpers, releases v1.0-v2.0, and the 3/3-validated inactive/F8 recovery. These assets are reused rather than replaced.

The unresolved state is active subscription + enabled UICC + F1. In that state framework reconstruction can complete through CarrierConfig, ImsResolver, MMTEL and IWLAN preference, while the first downstream Qualcomm IMS/CNE network demand is absent. Controlled attempts at `resetIms(1)`, IMS/CNE/cnd restart, coordinated RIL recovery, full userspace recovery and `system_server` restart did not restore direct WFC health. The ROM-specific modem SSR experiment was not executed because no verified standard trigger was found.

## Missing capabilities

Before this branch the project did not have a conservative long-running monitor, a cross-manager WebUI, a host-side one-command full diagnostic collector, or an explicit automatic policy that separates the validated F8 repair from unproven active-F1 escalation.

## Implemented boundary

`voxi_wfc_auto_recover` uses the existing read-only `WfcStateProbe` and fixed-target recovery helper. It cannot accept an arbitrary slot, phone or subscription identifier.

- Health requires IMS registered raw 2, WLAN transport raw 2, VOICE/IWLAN available, and WFC available.
- Network prerequisite checks are read-only and require validated Wi-Fi plus a validated VPN network on an UP `tun*` interface.
- Healthy, unsafe, unknown and active-broken states receive no write.
- Only strict F8/inactive, confirmed twice with the complete dual-SIM gate, can invoke one fixed true-only operation.
- The per-boot write budget is one. No retry follows failure.
- Configuration and logs live outside the module directory and survive upgrades.

## Best next experiment

Install the module disabled, verify status and mapping, and gather a fresh airplane-off transition with the host collector. Enable the monitor only after a healthy baseline is captured. If the failure is active F1, preserve it and compare the earliest modem-facing/QMI demand event with a successful full reboot; do not automatically replay previously failed restart experiments. If strict F8 appears, allow the validated one-shot path and require the four-part direct health rule plus 60 seconds of stability.

Airplane toggling is deliberately not implemented: it affects both SIMs and ordinary mobile service, so it cannot be the final fallback while the stated slot0 protection requirement remains in force.
