X55 + VOXI WFC One-Click Recovery v2.3

Validated device
- Xiaomi Mi 10 Ultra (cas)
- Android 13
- Build V816.0.4.0.TJJCNXM
- Qualcomm SDX55M
- Magisk root
- VOXI slot 1 / phoneId 1 / subId 11

Why v2.3 exists
The software POWER OFF path is proven to work: SIM2 becomes ABSENT and subId 11 can move to simSlotIndex=-1.
The weak point is the POWER ON side: SIM2 returns READY, but IMS/qti.cne/ePDG may not rebuild.

v2.3 intentionally reproduces the previously successful manual sequence:
1. X55 controlled OFF/ON and new PON_SUCCESS
2. Wait 10 seconds after PON_SUCCESS
3. SIM2 POWER OFF using transaction 182
4. Hold OFF for 3 seconds
5. SIM2 POWER ON
6. Wait 2 seconds
7. Send SIM2 POWER ON a second time
8. Start WFC health checks and poll up to 30 seconds
9. If still unhealthy, repeat the same sequence once
10. Never perform a third automatic SIM cycle

Success criteria
- IMS REGISTERED (raw 2)
- Transport WLAN (raw 2)
- VOICE/IWLAN AVAILABLE
- WFC AVAILABLE

Safety
- Exact device/build/fingerprint gate before transaction 182
- No subsystem_restart()
- No sysfs state/restart_level/system_debug writes
- Does not kill mdm_helper, ks, or qcrild
