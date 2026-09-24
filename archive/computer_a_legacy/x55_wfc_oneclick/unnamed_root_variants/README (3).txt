X55 + VOXI WFC One-Click Recovery v2.2

Validated device
- Xiaomi Mi 10 Ultra (cas)
- Android 13
- V816.0.4.0.TJJCNXM
- Qualcomm SDX55M
- Magisk root
- VOXI slot 1 / phoneId 1 / subId 11

Recovery timing
- X55 controlled OFF
- X55 controlled ON
- Confirm new PON_SUCCESS
- Wait 10 seconds after PON_SUCCESS
- If WFC unhealthy:
  1) SIM2 software POWER OFF (validated transaction 182)
  2) Hold POWER OFF for 8 seconds
  3) SIM2 software POWER ON
  4) Start WFC checks after 5 seconds
  5) Poll up to 30 seconds
- If still unhealthy, repeat that SIM2 cycle exactly once
- Never performs a third automatic SIM power cycle

v2.2 fix
- Fixes a v2.1 diagnostic snapshot quoting bug that stopped execution before transaction 182.
- SIM/UICC snapshot collection is now read-only and strictly non-fatal.
- Snapshot failure can never prevent SIM2 POWER OFF/ON recovery.

WFC success requires:
- IMS REGISTERED (raw 2)
- Transport WLAN (raw 2)
- VOICE/IWLAN AVAILABLE
- WFC AVAILABLE

Safety:
- Exact device/build/fingerprint gate before transaction 182
- No subsystem_restart()
- No sysfs state/restart_level/system_debug writes
- Does not kill mdm_helper, ks, or qcrild
