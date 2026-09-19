# Changelog

## v1.3 FINAL

- Consolidated the only repeatedly successful mechanism: software remove, persistent F8 confirmation, then software insert.
- Increased Deep Recover health timeout from 60 to 120 seconds with probes at 5/10/15/20/30/45/60/90/120 seconds.
- Added a two-sample persistent-F8 requirement before the insert call.
- Added `status-json`, explicit `safe-recover`, and `recover-hard` commands; retained `recover` as a compatibility alias.
- Made Magisk Action strictly status-only and zero-write.
- Made manual `deep-recover`, `recover-hard`, and `auto-run-now` independent of boot attempt markers.
- Added F8 Safe Recover handling to network-aware orchestration.
- Added explicit `DEEP_RECOVERY_FAILED`, failure-point, no-retry, and hard-recovery logging.
- Preserved atomic `mkdir` locking, fixed dual-SIM gates, helper JARs, network readiness checks, and persistent opt-in boot configuration.
- Excluded all failed experimental paths: resetIms, IMS/CNE/cnd process restarts, radio/modem reset, and SSR.
