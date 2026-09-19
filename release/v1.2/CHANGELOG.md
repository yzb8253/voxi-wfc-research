# Changelog

## v1.2

- Added an opt-in Magisk `service.sh` for one boot-time health check and safe strict-F1 recovery.
- Added a 60-second post-boot settle delay and a bounded five-minute Wi-Fi network-ready wait.
- Added strict F1 confirmation twice, 30 seconds apart, before automatic recovery is permitted.
- Added an atomic boot-ID attempt marker that limits automatic Deep Recover to one attempt per boot.
- Reused the existing validated `wfcctl.sh deep-recover` state machine; no recovery logic was duplicated.
- Added `auto-enable`, `auto-disable`, and `auto-status`; the default is `AUTO_RECOVER_BOOT=0`.
- Added Boot Auto Recover status to Magisk Action without changing Action recovery behavior.
- Added per-boot logs and diagnostics capture after a failed automatic attempt.
- Retained the v1.1.1 atomic `mkdir` recovery lock; no FD/flock path was reintroduced.

## v1.1.1

- Replaced the incompatible Toybox FD/flock lock with one atomic `mkdir` lock.

## v1.1

- Added the validated manual F1 Deep Recover sequence and corrected direct WFC health rule.
