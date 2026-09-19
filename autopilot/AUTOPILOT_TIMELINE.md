# Autopilot Timeline

- 2026-09-16 16:44:15 +08:00: Historical Phase 4D-2 software-remove write executed.
- 2026-09-16 16:44:16 +08:00: qti.cne IMS request released; subscription, CarrierConfig, ImsResolver, MMTEL/RCS, and IWLAN transiently rebuilt.
- 2026-09-17 08:00-09:01 +08:00: Rebooted/manual environment confirmed operational WFC and captured Phase 5A/5B true Golden.
- 2026-09-17 09:07 +08:00: FULL AUTOPILOT mode initialized; current expected class F0/GOLDEN_STRONG; no new autopilot writes used.
- 2026-09-17 09:34:55 +08:00: Cycle 1 fault injection executed exactly once: `ISub.setUiccApplicationsEnabled(false,11)`, return 1.
- 2026-09-17 09:35-09:40 +08:00: Persistent F8 confirmed through 300 seconds; slot0 remained protected. qti.cne request 263 remained visible but unsatisfied.
- 2026-09-17 13:35 +08:00: Live F8 probe showed delayed cleanup of qti.cne request 263; VOXI remained disabled/inactive.
- 2026-09-17 13:40:16 +08:00: Symmetric recovery executed exactly once: `ISub.setUiccApplicationsEnabled(true,11)`, return 1.
- 2026-09-17 13:40:26 +08:00: CNE created replacement IMS request 360 for subId 11.
- 2026-09-17 13:40:28 +08:00: IMS IWLAN NetworkAgent 102 connected; GOLDEN_STRONG reached by the 10-second probe.
- 2026-09-17 13:45:55 +08:00: GOLDEN_STRONG remained stable through 300 seconds; slot0 remained intact; resetIms was not executed.
- 2026-09-17 14:56:13 +08:00: Cycle 2 false executed exactly once; persistent F8 and protected slot0 confirmed.
- 2026-09-17 14:56:32 +08:00: Cycle 2 true executed exactly once; qti.cne request 374 and IMS NetworkAgent 103 appeared; GOLDEN_STRONG by 18 seconds.
- 2026-09-17 15:02 +08:00: Cycle 2 completed with 302 continuous GOLDEN_STRONG seconds.
- 2026-09-17 15:02:34 +08:00: Cycle 3 false executed exactly once; persistent F8 and protected slot0 confirmed.
- 2026-09-17 15:02:52 +08:00: Cycle 3 true executed exactly once; qti.cne request 380 and IMS NetworkAgent 104 appeared; GOLDEN_STRONG by 37 seconds.
- 2026-09-17 15:08 +08:00: Cycle 3 completed with 302 continuous GOLDEN_STRONG seconds. Validation reached 3/3 PASS.
- 2026-09-17 15:09:13 +08:00: Final read-only probe confirmed F0/GOLDEN_STRONG and protected slot0. FINAL_GOAL marked ACHIEVED.
