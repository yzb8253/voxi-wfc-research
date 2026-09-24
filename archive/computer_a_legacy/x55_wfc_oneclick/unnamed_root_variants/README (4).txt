X55 + VOXI WFC One-Click Recovery

Validated target:
- Device: Xiaomi Mi 10 Ultra (cas)
- Android: 13
- Build: V816.0.4.0.TJJCNXM
- Modem: Qualcomm SDX55M
- Root: Magisk
- ADB serial: fd0ff892

Usage:
1. Start from normal cellular state with airplane mode OFF.
2. Turn airplane mode ON to reproduce the polluted WFC state.
3. Keep Wi-Fi, proxy and location unchanged.
4. Double-click X55-WFC-OneClick.cmd.
5. Do not close the minimized X55 HOLDER window while using the recovered WFC state.

Automatic recovery flow:
- Controlled X55 OFF
- X55 ON and new PON_SUCCESS verification
- SIM2 software power cycle #1: OFF -> 3s -> ON
- Wait up to 30s for IMS/WFC
- If still unhealthy, one second SIM2 power cycle
- Wait up to 30s again
- Never performs a third automatic SIM power cycle

Success requires all four:
- IMS REGISTERED (raw 2)
- Transport WLAN (raw 2)
- VOICE/IWLAN AVAILABLE
- WFC AVAILABLE

The old module's overall Result: UNSAFE and protected-slot0 gate are intentionally not used as WFC success criteria in airplane mode.

Safety:
- Exact device/build/fingerprint gate required before transaction 182.
- No subsystem_restart().
- No sysfs state/restart_level/system_debug writes.
- Does not kill mdm_helper, ks, qcrild.
