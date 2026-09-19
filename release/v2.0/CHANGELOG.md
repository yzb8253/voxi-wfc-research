# Changelog

## v2.0

- Added the recommended `full-recover` lifecycle: one software remove, persistent F8 confirmation, one reboot, network readiness wait, one software insert, and direct WFC verification.
- Added crash-safe pending state with boot-ID validation and one-attempt counters.
- Added boot-time lifecycle resume before normal boot-auto processing.
- Added strict five-minute Wi-Fi/VPN/TUN wait and 30-second stability delay.
- Added `full-status` and non-mutating `full-cancel` commands.
- Kept the Magisk Action status-only.
- Retained v1.3 safe, deep, hard, and opt-in boot recovery commands.
- Added full lifecycle offline state-machine and release-package audits.

## v1.3

- Finalized safe and deep recovery behavior, 120-second direct health wait, no automatic retries, boot marker protection, status JSON, and persistent boot-auto configuration.