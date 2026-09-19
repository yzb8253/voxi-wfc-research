# Build Report

## Artifact

- Product: VOXI WFC Recovery
- Version: v2.0 FULL LIFECYCLE
- Version code: 200
- ZIP: `VOXI-WFC-Recovery-v2.0.zip`
- ZIP size: 35415 bytes
- ZIP SHA-256: `9F1C8FC98ECA5B8136DCFD67476CB310222B44E1A49D5757F45FD6D7FCE54A1D`
- Installation performed: no
- Phone state modification during build: none

## Primary recovery contract

- Entry requires strict F1: fixed VOXI identity, active subscription, enabled UICC applications, IMS not registered, WFC unavailable, and protected slot 0 gate passing.
- Executes one fixed software remove for subId 11.
- Requires two consecutive F8 confirmations plus the inactive helper gate.
- Atomically writes and syncs the pending marker before the only reboot call.
- Requires a new boot ID and reconfirms persistent F8 after boot completion.
- Waits up to 300 seconds for validated Wi-Fi and validated VPN/TUN with UP/LOWER_UP and a default route.
- Holds the network stable for 30 seconds and reconfirms network, F8, and slot 0.
- Persists the true-attempt bit before one fixed software insert for subId 11.
- Probes through 120 seconds for REGISTERED(2), WLAN(2), VOICE/IWLAN available, WFC available, and slot 0 safety.
- Every failure is terminal. There is no automatic retry.

## Write budget

- Maximum false writes: 1.
- Maximum reboot commands: 1.
- Maximum true writes: 1.
- Reboot-loop protection: PASS.
- Crash-safe at-most-once true behavior: PASS.

## Verification

- Offline full lifecycle state-machine tests: 13/13 PASS.
- Strict-F1 success path: PASS.
- HEALTHY, F8-at-entry, and unsafe zero-write blocking: PASS.
- Missing F8 or pending persistence blocks reboot and true: PASS.
- Same boot ID, post-boot F8 loss, network timeout, and pre-insert F8 loss block true: PASS.
- Insert failure and WFC timeout perform no retry: PASS.
- Source static audit: PASS.
- Android `/system/bin/sh -n` source validation via stdin: 8/8 PASS.
- ZIP root contains `module.prop` and no wrapper directory: PASS.
- Source versus extracted file set and hashes: PASS (13 files).
- Extracted release static audit: PASS.
- Android `/system/bin/sh -n` extracted validation via stdin: 8/8 PASS.
- Action status-only/zero-write audit: PASS.
- Full lifecycle boot resume precedes normal boot-auto logic: PASS.
- Five-minute network wait and 30-second stability delay: PASS.
- Existing `AUTO_RECOVER_BOOT` upgrade persistence: PASS.
- Default `AUTO_RECOVER_BOOT=0`: PASS.
- Forbidden experimental executable paths: NONE.

## Helper hashes

- `wfc-deep-remove-helper.jar`: `00D48EAB084FFBDD3D70DDA3D9EA11C794712CD1B6CA9D870B4CFE83A069B076`
- `wfc-probe.jar`: `AC46E9F62DB88C043DA08E4D5BB1D100EA8AC10EF2A74838F99C2237C2B9A91D`
- `wfc-recovery-helper.jar`: `735BC524937907ED738A34083881AD969ABF6652AE71D6CE7CC30D66926D34B3`

No recovery helper, reboot command, or module script was executed on the phone. Android shell was used only as a stdin syntax parser. The ZIP was not installed.