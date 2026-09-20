# Absent-state Soft Reboot Experiment

This is a single-use controlled experiment for the fixed VOXI target at slot1/subId11. It uses the already audited `Slot1SimPowerHelper`; no slot, phone, subscription, transaction, or numeric power-state input is accepted.

## Device-side safety model

- Strict dual-SIM identity, SIM READY, wlan0, tun0, root UID, and helper SHA256 gates run before POWER_DOWN.
- A dedicated independent watchdog starts before the write and exposes `absent-watchdog.ready`.
- The watchdog performs a fixed slot1 POWER_UP if no callback-confirmed POWER_UP exists 120 seconds after the POWER_DOWN marker.
- The orchestrator aborts remaining restarts and begins normal POWER_UP at a 75-second absolute deadline.
- POWER_DOWN exists once in the orchestrator. Normal POWER_UP exists once; the watchdog owns one independent fallback path.
- Slot0 must remain active, READY, and correctly mapped when card-down is confirmed.

## Fixed absent-state restart order

1. target `vendor.qcrild2`
2. primary `vendor.qcrild`, then revalidate the pair
3. `vendor.netmgrd`
4. `vendor.imsqmidaemon`
5. `vendor.imsdatadaemon`
6. `vendor.cnd`
7. `.qtidataservices`
8. `org.codeaurora.ims`
9. primary UID-1001 `com.android.phone`
10. UID-1000 `system_server`

Each target is resolved again on-device and checked against fixed init service, process name, UID, PPID, SELinux domain, and/or cmdline expectations before its exact PID receives one TERM. No SIGKILL, broad process selector, modem SSR, radio toggle, airplane toggle, raw QMI/UIM transaction, property write, settings write, or AP reboot command is present.

## Stop rules

- Any pre-down gate failure: no write.
- POWER_DOWN callback failure: no stack restart; immediately attempt POWER_UP.
- No confirmed card-down or slot0 protection failure: immediately attempt POWER_UP.
- Any restart failure or 75-second deadline: stop remaining restarts and attempt POWER_UP.
- After POWER_UP, observation is read-only. A failure does not authorize a second POWER_DOWN or further restart.
