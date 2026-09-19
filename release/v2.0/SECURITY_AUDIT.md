# Security Audit

## Scope

VOXI WFC Recovery v2.0 is fixed to one validated Xiaomi 14 Pro dual-SIM mapping. All state-changing helpers have compile-time targets. No CLI accepts a target identifier.

## Full lifecycle write budget

- Software remove: maximum 1.
- Reboot: maximum 1.
- Software insert: maximum 1.
- Automatic retries after any failure: 0.

The full lifecycle starts only from strict F1 with the complete VOXI and China Telecom safety gates. The reboot is reachable only after one successful remove, two persistent F8 confirmations, and an atomically written and synced pending marker.

Before software insert, the boot service requires a different boot ID, boot completion, two post-boot F8 confirmations, validated Wi-Fi, validated VPN/TUN with an active default route, a 30-second stability period, a second network check, and two more F8 confirmations.

The true-attempt counter is persisted before the insert Binder call. This favors no duplicate write after a crash. Any malformed, consumed, failed, same-boot, network-timeout, or health-timeout marker becomes terminal and is never retried automatically.

## Protected slot

Every pre-write gate confirms China Telecom remains subId 1, slot 0, carrierId 2237, MCC 460, MNC 11. A mismatch blocks the write.

## Action

`action.sh` calls only status and network-readiness commands. It has no path to recovery helpers or lifecycle start/cancel commands.

## Forbidden paths

Executable scripts contain no IMS reset, IMS disable/enable, vendor process termination, radio/modem reset, SSR, qcrild restart, airplane-mode mutation, settings mutation, property mutation, Wi-Fi toggle, or SELinux mutation. The sole executable reboot line is in the guarded full lifecycle start path.

## Persistence and privacy

Lifecycle state is written atomically under `/data/adb/voxi-wfc-recovery/state`, synced before reboot, and protected with mode 0700/0600. Logs redact ICCID, card strings, phone numbers, IMSI/subscriber identifiers, and long digit sequences.

## Verification

- Offline full lifecycle model: PASS.
- Source static audit: PASS.
- Android `sh -n` parsing for all executable scripts: PASS.
- Unpacked release audit: PASS.