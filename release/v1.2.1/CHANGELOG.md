# Changelog

## v1.2.1

- Reordered boot automation to wait for validated Wi-Fi, then validated VPN/TUN, before probing WFC.
- Added a 20-second network-prerequisite stabilization interval and a final readiness recheck.
- Added a device-validated VPN/TUN gate combining VPN NetworkAgent, `WIFI|VPN`, INTERNET, VALIDATED, active `tunN`, and a TUN default route.
- Added a five-minute VPN/TUN timeout that exits with zero Telephony writes and does not consume the boot attempt.
- Added `wfcctl.sh auto-run-now`, which reuses the same network-aware safe orchestration.
- Added `wfcctl.sh network-status` and Wi-Fi/VPN readiness display to Magisk Action.
- Made upgrade persistence explicit: an existing external `config.conf` is preserved; the disabled default is created only when absent.
- Kept the existing Deep Recover state machine and helper JARs unchanged.

## v1.2

- Added opt-in, once-per-boot strict-F1 auto recovery with a double-check and one boot-attempt marker.

## v1.1.1

- Replaced the incompatible Toybox FD/flock lock with atomic `mkdir` locking.
