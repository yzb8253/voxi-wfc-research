# STABLE_CNE_V1 static audit

## Scope

`STABLE_CNE_V1` is one isolated test build. It preserves the existing A0/P0 preparation, controlled X55 shutdown, temporary holder, `PON_SUCCESS`, 10-second PON settle, one SIM2 power cycle with a 3-second OFF hold, safety gates, and frozen-healthy behavior.

The only main-path recovery addition is the historically proven UICC lifecycle copied from `uicc_apps_deep_fallback.ps1`:

`UICC false,11 -> verified F8 -> UICC true,11`

The copied implementation retains the exact Binder transaction, subId 11 target, slot/carrier/MCC-MNC guards, protected slot0 guard, F8 predicate, reinsert predicate, and emergency TRUE rollback. Its entry airplane predicate is set to ON because this version invokes the same lifecycle inside the existing P/core phase. The original helper and all original cores are unchanged.

## CNE and health contract

- Baseline and freshness use the audited connectivity **current table only** parser.
- Baseline `null` requires a non-null request; a non-null baseline requires a different non-null request.
- Missing current-table boundary fails closed.
- Fresh-CNE maximum observation is 45 seconds and returns immediately on freshness.
- After fresh CNE, success still requires IMS `REGISTERED(2)`, transport `WLAN(2)`, `VOICE/IWLAN AVAILABLE`, and `WFC AVAILABLE`.
- No CNE freshness timeout of 10 or 15 seconds was introduced.

## Prohibited additions

This build contains no new `resetIms`, vendor.cnd restart, qtidataservices restart, qcrild2 restart, userspace rebuild, second attempt, or deep fallback. Failure uses the inherited transactional safety cleanup; the UICC helper independently guarantees a single emergency TRUE if false was sent but normal true was not completed.

## Frozen sources

- Original v2.6.2 core SHA256: `70C81B1CC2F69F80540CB08DDD0C4F16FF2871B48D9D46E25F72C0F66CE51E76`
- Original FAST core SHA256: `0876285019658EC56BE4964B76A5FE807CE2FCDA237CC891CC9BE347E6725F22`

Both remain unmodified. The generated files have independent names and the sole user entry is `RUN-X55-WFC-STABLE-CNE-V1.cmd`.

## Static result

- Windows PowerShell 5.1 parser: PASS
- classifier fixtures: 17/17 PASS
- current-CNE and freshness fixtures: 13/13 PASS
- holder identity fixtures: 7/7 PASS
- unsafe promotion: 0
- safety contract: PASS
- static phone writes: 0

No device experiment was run while building or auditing this version.
