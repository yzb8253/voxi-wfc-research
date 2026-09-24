# v2.6.2 freeze-on-success repeatability result

Date: 2026-09-24

Result: `TWO_CYCLE_REPEATABILITY_PASS`

## Recovery source

- Original: `archive/computer_a_legacy/x55_wfc_oneclick/v2.6.2/X55-WFC-OneClick-v2.6.2-native-owner-restore.ps1`
- Original SHA-256: `0B83D687F354F1A6B920937E22ACF9D761BAC51E064C8D3CC14BDDAA51FE3CE7`
- Experimental copy: `X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1`
- Experimental SHA-256 before execution: `445752BB49FB487850D0B1A1EFF4F0AA29D58C363C3A86E75BAA841E4CC08F75`

The recovery path is unchanged. The experimental copy changes only the post-success branch: when direct health succeeds after X55-only or the one allowed SIM cycle, it sets `FreezeOnHealthy`, skips `Invoke-TransactionalCleanup`, and exits successfully without starting per_mgr or releasing the holder.

No CND fallback, qtidataservices restart, second SIM cycle, IMS reset, radio workaround, or QCRIL restart exists in the recovery path.

## A0

`snapshot_A0.json` captured the fresh-boot airplane-OFF baseline:

- VOXI subId 11 / slot 1 / phoneId 1 / carrierId 28 / MCCMNC 23415.
- Subscription active; UICC applications enabled.
- qcrild PID 1958; qcrild2 PID 1994.
- vendor.per_mgr running; pm-service PID 1289 sole owner of `/dev/subsys_esoc0`.
- X55 ONLINE; crash count 0.
- No live holder. A dead cross-boot pidfile was recorded as a non-live residue.
- IMS NOT_REGISTERED / UNKNOWN, with no current qti.cne IMS request.

## P0

Airplane mode was enabled and Wi-Fi was restored. After the common settle window, `snapshot_P0.json` differed from A0 only in four expected fields:

- airplane 0 -> 1
- Wi-Fi setting enumeration 1 -> 2
- RIL technology LTE -> IWLAN
- IWLAN preferred false -> true

All identity, UICC, native ownership, QCRIL, X55, and current IMS-request fields matched.

## W0

The v2.6.2 sequence completed exactly:

1. stop vendor.per_mgr
2. X55 clean OFFLINE
3. temporary holder PID 15643 became sole owner
4. X55 ONLINE / crash count 0
5. new PON_SUCCESS
6. fixed 10-second settle
7. X55-only health check
8. one SIM2 OFF, 3-second hold, one SIM2 ON
9. direct-health observation

WFC reached direct health at approximately 11 seconds after the SIM cycle:

- IMS REGISTERED
- transport WLAN
- VOICE/IWLAN available
- WFC available
- current qti.cne IMS request active
- UDP/4500 active
- XFRM active

The script emitted `SKIPPED_FREEZE_ON_HEALTHY`. W0 retained per_mgr stopped, holder 15643 sole ownership, and X55 ONLINE/crash count 0. No success cleanup ran.

Host-only W0 log SHA-256: `53DAA5E3EC49F19683745F8AB62E85DCA77EEF59754B5F89929B51C7B818E47C`.

## A1 and residue classification

After airplane OFF and settling, `snapshot_A1.json` was compared with A0.

Confirmed `RESIDUE`:

- vendor.per_mgr stopped
- pm-service absent
- temporary holder 15643 sole owner of `/dev/subsys_esoc0`
- live holder pidfile

`TRANSIENT`:

- IWLAN technology immediately after airplane OFF; it naturally returned to LTE.

`DIAGNOSTIC_FALSE_POSITIVE`:

- legacy `wfcctl` reported qti.cne request 272 active because it parsed request history. Connectivity's current request table showed request 272 had been released. The uniform collector now computes `qtiCneRequest` only from the current table and preserves the legacy result as `qtiCneProbeReported`.

`EXPECTED`:

- PID and owner-line text changes after intentional process reconstruction.
- removal of the old dead holder pidfile.

## A1 normalization

The first minimal make-before-break attempt started per_mgr while holder 15643 remained alive. A PowerShell `$PID` naming defect stopped the host helper after the start, without releasing the holder. The variable was corrected.

Neither the initial start nor the original v2.6.2 cleanup's one allowed per_mgr restart produced dual ownership. The gate refused to TERM the holder while native takeover was absent.

The state then matched the proven native-reacquire boundary:

- per_mgr running / pm-service present but not owner
- holder sole owner
- vendor X55 OFFLINE, kernel X55 ONLINE
- crash count 0
- qcrild/qcrild2 unchanged

The fingerprint-specific fallback performed:

1. one exact-holder TERM, no SIGKILL
2. confirmed holder gone, owner NONE, X55 OFFLINE, crash count 0
3. one `vendor.qcrild2` restart
4. qcrild2 PID 1994 -> 27223
5. pm-service PID 23598 reacquired `/dev/subsys_esoc0`
6. X55 returned ONLINE with crash count 0
7. primary qcrild remained PID 1958

`snapshot_A1_NORMALIZED_SETTLED.json` is A0-equivalent on the critical fingerprint. Remaining differences are expected PIDs/owner text, the removed dead pidfile, and the retained legacy-probe diagnostic field.

## P1

Airplane mode and Wi-Fi were applied exactly as for P0. `snapshot_P1.json` is P0-equivalent on every functional field. Its five raw diffs are only expected PIDs/owner text and absence of P0's dead pidfile. No P1-specific repair was needed.

## W1

The exact same freeze-on-success script ran with no workaround. It again reached WFC health at approximately 11 seconds after exactly one SIM cycle and emitted `SKIPPED_FREEZE_ON_HEALTHY`.

`snapshot_W1.json` matches W0 on every functional field:

- IMS REGISTERED
- transport WLAN
- VOICE/IWLAN available
- WFC available
- current qti.cne IMS request active
- UDP/4500 active
- XFRM active
- per_mgr stopped
- holder sole owner
- X55 ONLINE / crash count 0

The four raw W1/W0 differences are holder PID, qcrild2 PID inherited from normalization, owner-line PIDs, and holder-pidfile timestamp.

Host-only W1 log SHA-256: `258F69D4B2FF1CE03DC2B9314E76BC7D0499EE75BB946EE415E302852C1669AE`.

## Proven repeatability rule

The residue that prevented a second clean entry was not IMS or WFC state itself. It was the intentionally frozen native ownership state. A repeatable next run requires:

1. HEALTHY -> zero writes and FREEZE.
2. At the next airplane-OFF launch, detect exact holder/native-owner residue.
3. Restore pm-service sole ownership using the narrowest matching path.
4. If per_mgr cannot acquire while the holder lives, release only the exact holder, require owner NONE/X55 OFFLINE/crash 0, then restart qcrild2 once for native reacquire.
5. Confirm A0-equivalent critical fingerprint.
6. Recreate P0 and run the unchanged v2.6.2 recovery path.
7. On WFC health, FREEZE again.

`repeatability_preflight.ps1` implements this as a fail-closed experimental preflight candidate. It has not been run against W1 because healthy state permits snapshots and Git operations only.
