# AGGRESSIVE_CONSERVATIVE_v1.2H static audit

`v1.2H` combines two independently bounded changes in new files only:

1. The previously validated FAST holder experimental core.
2. A strict ordinary `FROZEN_RESIDUE` transition: one `ctl.start vendor.per_mgr`, wait up to 15 seconds for the exact `FROZEN_SPLIT_READY` fingerprint, then invoke the unchanged `normalize_a1_qcrild2_reacquire.ps1`.

The transition helper revalidates the exact lightweight observation and live holder/owner/X55/crash/QCRIL epoch before its sole write. Pre-write drift returns to the existing full fallback. Once `ctl.start` has been sent, failure to reach strict split stops the run; it cannot invoke full normalization, restart per_mgr, or perform another write.

`FROZEN_RESIDUE` (`ONLINE/ONLINE`, per_mgr stopped, pm-service absent) and `FROZEN_SPLIT_RESIDUE` (`OFFLINE/ONLINE`, per_mgr running, pm-service live but not owner) remain separate fingerprints.

Frozen timing and recovery contracts remain unchanged: A/P dynamic 5–20 seconds, PON settle 10 seconds, SIM OFF hold 3 seconds, SIM observation 30-second sleep budget plus probe runtime, two normal attempts, unchanged deep fallback and health predicate.

Static results:

- Windows PowerShell 5.1 parsing: PASS.
- Existing classifier fixtures: 17/17 PASS; unsafe promotions 0.
- v1.2H frozen-path fixtures: PASS; unsafe promotions 0.
- Controlled per_mgr start sites: exactly 1.
- Forbidden transition mutations: 0.
- FAST holder audit: PASS; the experimental core differs from the original v2.6.2 core by one holder-command line only.
- Original golden/stable/v2.6.2 files: unchanged.
- Phone execution during static construction: none.

Run 1 is a migration run if its entry holder is OLD. Only Run 2 with `ENTRY_HOLDER_IMPL=FAST` is a FAST-to-FAST performance sample.
