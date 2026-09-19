# VOXI WFC Research

This repository contains the Xiaomi 14 Pro / VOXI UK Wi-Fi Calling research record, reproducible evidence, guarded recovery tools, and Magisk-compatible modules. The fixed tested mapping is China Telecom on slot 0/subId 1 and VOXI on slot 1/subId 11.

## Current result

- Direct health is `REGISTERED(2) + WLAN(2) + VOICE/IWLAN available + isWifiCallingAvailable(11)=true`.
- The inactive/F8 fixed `setUiccApplicationsEnabled(true,11)` recovery is validated 3/3 with slot0 protected.
- Active + enabled F1 can stall before Qualcomm IMS creates a new CNE IMS NetworkRequest.
- `resetIms(1)`, Qualcomm IMS, CNE/qtidataservices, vendor.cnd, coordinated CND+CNE, full userspace, `system_server`, and coordinated RIL-pair restarts did not recover that preserved F1 scene.
- A standard external-modem SSR trigger was not available on the tested ROM, so M3 was stopped at its static safety gate and was not executed.

The best next experiment is to deploy the monitor in read-only mode, collect a new airplane-off failure from boot, and compare the first missing modem-facing demand against a successful full reboot. Automatic escalation beyond the validated F8 recovery remains intentionally blocked.

## Auto-recovery module

Source: [`modules/voxi_wfc_auto_recover`](modules/voxi_wfc_auto_recover)

The daemon periodically checks IMS registration, WLAN transport, direct WFC availability, ePDG/XFRM, qti.cne demand, qcrild presence, Wi-Fi and VPN/TUN readiness. It is disabled on first install and preserves its configuration during upgrades.

Its automatic state machine is deliberately narrow:

1. Healthy: zero write.
2. Strict F8/inactive, confirmed twice, complete dual-SIM gate: one fixed true-only recovery, at most once per boot.
3. Active F1 or any other failure: log `ESCALATION_REQUIRED`, preserve the scene, zero write.
4. Unsafe mapping, missing VPN/TUN or unknown state: zero write.

IMS/RIL restart and airplane-toggle code is not included in unattended recovery. Those methods either failed in controlled testing or interrupt both SIMs and conflict with the ordinary-mobile-network protection requirement.

## Commands

Read-only status:

```powershell
.\voxi_wfc_research\voxi_wfc_status.ps1
```

Controlled recovery:

```powershell
.\voxi_wfc_research\voxi_wfc_recover.ps1
```

The recovery command writes only in the verified F8 condition where VOXI subId 11 is inactive, slot mapping is absent, and UICC applications are disabled. It then performs one fixed `ISub.setUiccApplicationsEnabled(true,11)` call. Healthy and active-but-unhealthy states receive no write.

See `VALIDATION_REPORT.md` for evidence and `FINAL_RUNBOOK.md` for the operating boundary.

## Build and install

On Windows:

```powershell
.\tools\build_auto_recover.ps1
adb push .\release\auto-recovery\voxi_wfc_auto_recover-v0.1.0.zip /sdcard/Download/
```

Install the ZIP manually in the root manager and reboot once. Do not enable writes until read-only status confirms the fixed slot mapping:

```powershell
adb shell su -c '/data/adb/modules/voxi_wfc_auto_recover/bin/voxi-autoctl.sh status'
adb shell su -c '/data/adb/modules/voxi_wfc_auto_recover/bin/voxi-autoctl.sh enable'
```

The Action button is status-only. A `webroot` dashboard is available in KernelSU/APatch-compatible WebUI managers; Magisk managers without the WebUI bridge should use Action or shell commands.

## Test and log collection

Windows one-click read-only collection:

```powershell
.\tools\collect_voxi_logs.ps1 -Serial 192.168.1.25:41201
```

POSIX/Git Bash:

```sh
./tools/collect_voxi_logs.sh 192.168.1.25:41201
```

The collector saves full logcat plus IMS/qcril-focused output, telephony/IMS/connectivity dumps, process state, routes and XFRM state. It does not modify the phone.

Recommended validation sequence: install with `ENABLED=0`, capture healthy status, turn airplane mode off manually, collect the failure scene, verify slot0 mapping, then enable the daemon. A recovery is accepted only when all four direct health conditions return and remain stable for at least 60 seconds.

## SIM soft-reset laboratory

The next research phase changes the question from generic IMS restart to reproducing the lifecycle of physical VOXI SIM removal/insertion without rebooting Android. The staged experiment matrix and independently gated scripts live in [`experiments/sim_soft_reset`](experiments/sim_soft_reset). Existing auto-recovery sources and releases are unchanged.

The read-only slot-to-Radio/UIM/QMI mapping is documented in [`experiments/sim_soft_reset/SLOT_MAPPING/VOXI_SLOT_MAPPING.md`](experiments/sim_soft_reset/SLOT_MAPPING/VOXI_SLOT_MAPPING.md). It does not execute SIM power or process operations.
