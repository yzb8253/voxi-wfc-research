# v2.6.2 freeze-on-success static audit

Date: 2026-09-24

Result: `PASS`

## Source integrity

- Historical source: `archive/computer_a_legacy/x55_wfc_oneclick/v2.6.2/X55-WFC-OneClick-v2.6.2-native-owner-restore.ps1`
- Historical SHA-256: `0B83D687F354F1A6B920937E22ACF9D761BAC51E064C8D3CC14BDDAA51FE3CE7`
- Experimental source: `v262_freeze_run/X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1`
- Experimental SHA-256: `445752BB49FB487850D0B1A1EFF4F0AA29D58C363C3A86E75BAA841E4CC08F75`

A decoded line-by-line comparison found only the intended changes:

1. change the script version label;
2. add the `FreezeOnHealthy` flag;
3. set the flag after `X55_ONLY_SUCCESS` or `SIM_CYCLE_1_SUCCESS`;
4. skip `Invoke-TransactionalCleanup` when that flag is set;
5. report the frozen healthy state without a post-cleanup health probe.

The recovery sequence, timing, fixed target, safety gates, X55 rebirth, new-PON check, ten-second settle, five-second X55-only health window, one SIM OFF/ON cycle, three-second OFF hold, and thirty-second health window are unchanged.

## Forbidden-path audit

The recovery path contains none of the following:

- vendor.cnd restart;
- qtidataservices restart;
- second SIM power cycle;
- qcrild/qcrild2 restart;
- mdm_helper restart;
- resetIms;
- radio-power workaround.

The original transactional cleanup functions remain in the copied file so failure behavior stays faithful to v2.6.2. They are not reachable after direct WFC health sets `FreezeOnHealthy`. The two real successful runs both emitted `SKIPPED_FREEZE_ON_HEALTHY`.

## Parser and data audit

- Seven PowerShell files parsed with zero syntax errors.
- Ten sanitized snapshot JSON files parsed successfully.
- Snapshot diffs were regenerated after correcting current qti.cne request detection.
- The collector now derives `qtiCneRequest` only from Connectivity's current request table and retains the historical probe result separately as `qtiCneProbeReported`.
- No IMSI, ICCID, MSISDN, credential, token, or long subscriber identifier was found in the files selected for this checkpoint.
- Raw device captures and recovery logs remain host-only and are not committed.

## Diff summary

- P0 vs A0: 4 expected environment/transport differences.
- A1 vs A0: 14 differences before residue normalization.
- A1 normalized and settled vs A0: 6 non-functional PID/owner-text/pidfile/diagnostic differences.
- P1 vs P0: 5 non-functional PID/owner-text/pidfile differences.
- W1 vs W0: 4 non-functional holder/qcrild2/owner-text/timestamp differences.

## Preflight status

`repeatability_preflight.ps1` is a fail-closed experimental candidate, not production code. It was intentionally not executed against the preserved W1 healthy scene. Its healthy branch is zero-write; normalization is opt-in and permitted only for the exact airplane-OFF frozen-residue fingerprint. Unknown fingerprints fail closed.

The two normalization helpers expose only the recorded narrow write surfaces:

- native-owner attempt: start/restart vendor.per_mgr, then TERM only the exact verified holder after dual ownership;
- fallback: TERM only the exact verified holder, require owner NONE and clean X55 OFFLINE, then restart vendor.qcrild2 once.

Neither helper performs a SIM cycle, IMS reset, radio reset, CND restart, modem reset, or AP reboot.

## Preserved scene

No phone operation was performed during this final audit. The last recorded scene remains W1 HEALTHY with airplane mode and Wi-Fi on, vendor.per_mgr stopped, exact holder PID 31050 as sole owner, and X55 ONLINE with crash count zero.
