# Build Report

## Artifact

- Product: VOXI WFC Recovery
- Version: v1.3 FINAL
- Version code: 130
- ZIP: `VOXI-WFC-Recovery-v1.3.zip`
- ZIP size: 30,447 bytes
- ZIP SHA-256: `4B9BB284723DC43567309848613EAA13B4197BEC8DD4D4C67E7449C0F854316E`
- Installation performed: no
- Phone state modification during build: none

## Final recovery contract

- HEALTHY/F0: zero writes.
- F8/inactive/apps-disabled: one fixed Safe Recover `true,11` call.
- Strict F1 active/enabled: one fixed `false,11`, two consecutive persistent-F8 samples, one fixed `true,11`, then direct-health probes through 120 seconds.
- Deep failure: terminal for the invocation; no automatic retry, resetIms, process restart, radio/modem/SSR action, airplane toggle, or reboot.
- Hard Recovery is guidance only after the single safe attempt fails.

## Verification

- Offline state-machine tests: 10/10 PASS.
- HEALTHY zero-write model: PASS.
- F8 Safe Recover single-true model: PASS.
- Strict-F1 single-false/single-true model: PASS.
- Missing persistent F8 blocks true: PASS.
- Post-insert failure performs no retry: PASS.
- Boot marker blocks only boot mode: PASS.
- Manual Deep Recover, Recover Hard, and Auto Run Now ignore the boot marker: PASS.
- Atomic `mkdir` recovery lock retained: PASS.
- Configuration upgrade preserves `AUTO_RECOVER_BOOT=1`: PASS.
- First install defaults to `AUTO_RECOVER_BOOT=0`: PASS.
- Helper JAR hashes unchanged from v1.2.1: PASS.
- Source shell syntax through Android `/system/bin/sh -n` via stdin: 7/7 PASS.
- Extracted-ZIP shell syntax through Android `/system/bin/sh -n` via stdin: 7/7 PASS.
- ZIP root contains `module.prop` and has no wrapper directory: PASS.
- Source versus extracted file hashes: PASS.
- Extracted release file set: exact, 12 files.
- Action status-only/zero-write audit: PASS.
- Deep Recover 5/10/15/20/30/45/60/90/120 schedule: PASS.
- Explicit no-retry and hard-recovery failure output: PASS.
- Forbidden experimental executable paths: NONE.

## Helper hashes

- `wfc-deep-remove-helper.jar`: `00D48EAB084FFBDD3D70DDA3D9EA11C794712CD1B6CA9D870B4CFE83A069B076`
- `wfc-probe.jar`: `AC46E9F62DB88C043DA08E4D5BB1D100EA8AC10EF2A74838F99C2237C2B9A91D`
- `wfc-recovery-helper.jar`: `735BC524937907ED738A34083881AD969ABF6652AE71D6CE7CC30D66926D34B3`

No F1/F8 state was manufactured, no recovery helper was invoked, and the release ZIP was not installed. Android shell was used only as a stdin syntax parser.
