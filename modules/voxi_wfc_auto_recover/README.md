# VOXI WFC Auto Recover

Device-specific module for the tested Xiaomi 14 Pro mapping: China Telecom slot 0/subId 1 and VOXI slot 1/subId 11.

The daemon polls direct IMS/WFC health after Android boot. It requires validated Wi-Fi and VPN/TUN before considering recovery. Healthy state is always zero-write. The only automatic write is the 3/3-validated fixed `setUiccApplicationsEnabled(true, 11)` operation when strict F8/inactive state and the complete dual-SIM gate are both confirmed. It runs at most once per boot.

Active + enabled failures (including F1) are logged as `ESCALATION_REQUIRED` and preserved. Previously failed IMS, CNE, RIL, userspace and system_server restart experiments are not repeated. Airplane toggling is excluded because it interrupts ordinary mobile service and cannot satisfy the slot0 protection requirement.

Configuration is stored at `/data/adb/voxi-wfc-auto-recover/config.conf` and is preserved on upgrade. Automatic recovery is disabled on first install. Enable it with:

```sh
su -c /data/adb/modules/voxi_wfc_auto_recover/bin/voxi-autoctl.sh enable
```

Read-only status and diagnostics:

```sh
su -c /data/adb/modules/voxi_wfc_auto_recover/bin/voxi-autoctl.sh status
su -c /data/adb/modules/voxi_wfc_auto_recover/bin/voxi-autoctl.sh diagnose
```

The optional `webroot` works in root managers that implement the KernelSU-compatible WebUI bridge. Traditional Magisk builds without a WebUI bridge can use the module Action button (status only) and shell commands.

