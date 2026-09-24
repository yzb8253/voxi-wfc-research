# Current Blockers

Updated: 2026-09-24

Only active blockers belong here. Historical blockers belong in the experiment log or decisions file.

## 1. Full re-vote mechanism is not completely evidenced

001B changed qcrild2 PID 13706 -> 873 and pm-service PID 31818 reacquired `/dev/subsys_esoc0`, returning X55 ONLINE with crash_count 0. The complete captured logcat did not contain any required PerMgrLib/PerMgrSrv QCRIL register/vote line.

Resolution: do not infer a verified re-vote from the ownership transition. Further mechanism work requires a separate evidence-based plan and explicit authorization.

The fifth run added direct server-side evidence: `PerMgrSrv: QCRIL registered` and `PerMgrSrv: QCRIL voting for SDX55M`. The two required `PerMgrLib` registration/vote strings were still absent, so the four-line bilateral evidence gate remains `UNPROVEN`.

## 2. Historical artifact provenance remains incomplete

Exact historical v2.6.2 host source was recovered from Computer A on 2026-09-24 and is now preserved with SHA-256 provenance. Historical raw evidence remains incomplete; source recovery must not be described as full raw-log recovery.

## 3. Exact launcher file-hash path resolved on host

The fourth launch stopped pre-write at `Assert-LocalArtifact` because `Get-FileHash` was not resolved in the paired Windows PowerShell 5.1 process. The production script now uses an internal .NET `SHA256` implementation, and the exact paired `.cmd selftest` invokes production `Assert-LocalArtifact` successfully under Windows PowerShell `5.1.19041.6456`.

Resolution: host/runtime PASS with the pinned helper hash, known SHA-256 vector, orchestrator hash, and zero legacy hash-cmdlet dependencies. At that checkpoint `PHONE_NOT_RERUN`; the later fifth run is recorded below.

## 4. Production contention/cleanup gate redesign complete

The fifth authorized run showed that pm-service can acquire `/dev/subsys_esoc0` while the script holder remains an owner. This violates the production script's expected holder-only contention gate. The holder cleanup predicate requires unique ownership, so fail-safe TERM was refused after dual ownership appeared.

Experiment 006 then strictly revalidated holder PID 22129 and sent one TERM. The holder and PID file disappeared, pm-service PID 22536 became sole owner, X55 stayed ONLINE, crash_count stayed 0, and qcrild2 remained PID 873. This proves the make-before-break native handoff behavior for this scene.

The live cleanup blocker and static production-design blocker are resolved. v2.7-alpha now requires the exact holder as sole owner before rebirth, then exactly holder + init-owned pm-service, then TERM of that exact Android holder, and finally pm-service as sole owner while X55 remains ONLINE. Android holder identity is based on PID file, live PID, exact cmdline, and FD9 target; it no longer depends on the Windows host process. Unknown third owners fail closed. The production qcrild2 restart was removed.

This is static acceptance only. Cleanup 006 proved the native handoff mechanics, not WFC recovery. A future phone run requires explicit authorization.

## 5. Holder TERM trap is deferred by the sleep child

Authorized run 007 reached the exact dual-owner gate, then sent one TERM to the exact holder. The holder remained alive beyond the production 10-second deadline while its process tree showed a `sleep 60` child. The PID file and dual-owner state remained present; X55 stayed ONLINE and qcrild2 did not change.

The likely cause is deferred shell trap handling while waiting for the foreground sleep child. No retry or cleanup was performed. A future change must be static-only first and must make exact-holder TERM completion deterministic without broad kill, SIGKILL, or weakening identity checks.

## 6. Recovery ordering is now the active blocker

Run 008 proved the redesigned native ownership handoff itself: X55 rebirth, exact dual ownership, exact holder TERM, pm-service sole ownership, unchanged qcrild2 PID, and native cleanup all completed. The one-shot SIM helper then executed POWER_DOWN/POWER_UP successfully, but WFC remained F1 through the bounded observation window.

The ordering differed from the earlier successful v2.5/v2.6.2 scene: run 008 restored native pm-service ownership before the SIM cycle. The production script has now been reordered so the optional single SIM cycle occurs while the fresh X55 is still held by the exact holder and vendor.per_mgr remains stopped. Make-before-break native cleanup now runs only after the recovery window, followed by a post-cleanup WFC survival check.

This is a source-level redesign only. Exact paired PS5.1 selftest must pass again before another phone execution.

## Current disposition

- 001: `ABORTED_BEFORE_CONTENDED_PHASE / INCONCLUSIVE`
- 001B: `QCRILD2_RESTART_NO_VALID_REVOTE`
- Current native state after cleanup 006: pm-service PID 22536 is sole `/dev/subsys_esoc0` owner; holder and holder PID file absent; X55 ONLINE; crash_count 0; qcrild2 PID 873; WFC F1.
- 001B phone writes: 2
- Detailed evidence: `X55_OWNERSHIP_HANDOFF_001B.md`
- v2.7-alpha second device launch: `BLOCKED_PRE_WRITE_HOST_SCRIPT_COMPATIBILITY`; phone writes 0; native phone scene unchanged.
- Detailed second-launch evidence: `v2.7-alpha-native-handoff/SECOND_DEVICE_RUN_RESULT.md`
- Host-script compatibility and exact-launcher artifact hashing are repaired and audited. The fifth authorized run exposed the separate contention/cleanup blocker below.
- Third launch: `BLOCKED_PRE_WRITE_MISSING_AUDITED_SINGLE_SIM_HELPER`; phone writes 0; native scene unchanged. The packaging blocker is now resolved by force-tracking the exact audited 11534-byte artifact with SHA-256 `90D6F55FBE1F941C1E3EEE1AA1F93B569FA3AE4084B93C5560082A38AAAF5C39` while retaining the global `*.jar` ignore.
- Detailed third-launch evidence: `v2.7-alpha-native-handoff/THIRD_DEVICE_RUN_RESULT.md`
- Fourth launch: `BLOCKED_PRE_WRITE_PS51_FILEHASH_RESOLUTION`; phone writes 0; native scene unchanged.
- Detailed fourth-launch evidence: `v2.7-alpha-native-handoff/FOURTH_DEVICE_RUN_RESULT.md`
- Fourth-launch blocker repair: exact paired PS5.1 no-ADB selftest PASS; production artifact gate PASS before the fifth run.
- Fifth launch: `X55_REBIRTH_SUCCESS / BEHAVIOR_CHANGED`; phone write actions 3; qcrild2 restart 0; SIM OFF/ON 0/0; live holder preserved in a dual-owner state.
- Detailed fifth-launch evidence: `v2.7-alpha-native-handoff/FIFTH_DEVICE_RUN_RESULT.md`
- Cleanup 006: exact-holder TERM once; `MAKE_BEFORE_BREAK_NATIVE_HANDOFF_SUCCESS`; phone write actions 1; qcrild2/SIM/service restart 0.
- Detailed cleanup evidence: `X55_DUAL_OWNER_CLEANUP_006.md`
- Seventh run: `HOLDER_TERM_DEFERRED_TIMEOUT / PRESERVED_DUAL_OWNER`; exact TERM once; SIM OFF/ON 0/0; X55 ONLINE; qcrild2 unchanged.
- Detailed seventh-run evidence: `v2.7-alpha-native-handoff/SEVENTH_DEVICE_RUN_RESULT.md`
- Eighth run: native handoff and cleanup PASS; one software SIM cycle completed; final WFC `FAILED_AFTER_ONE_SIM_CYCLE`; qcrild2 unchanged; cleanup native-clean.
- Detailed eighth-run evidence: `v2.7-alpha-native-handoff/EIGHTH_DEVICE_RUN_RESULT.md`

NEXT_ACTION: pull the recovery-before-cleanup source redesign to Computer A and run the exact paired PS5.1 `selftest` only. Do not execute the phone path until that selftest is reviewed.


## 7. PeripheralManager reconnect-window timing is the active blocker

The 10:21 recovery-before-cleanup device run restored full WFC while the fresh X55 remained under the exact holder and vendor.per_mgr remained stopped. Cleanup then failed because pm-service did not acquire `/dev/subsys_esoc0`.

Captured logs show qcrild2 PID 873 detected the PeripheralManager server death at 10:21:25.263 and retried until 10:21:55.556. vendor.per_mgr was not restarted until 10:25:12.954, when the new pm-service reported SDX55M voter/listener count 0/0 and no client. This supports a finite reconnect/retry window as the current cleanup blocker.

The production source now pre-stages helper/orchestrator work before stopping vendor.per_mgr and the device-side SIM orchestrator requests vendor.per_mgr start immediately after a successful POWER_UP. The holder is retained while exact dual ownership forms and while WFC is observed; only afterward may exact-holder TERM complete native cleanup.

This source change is not yet device-validated. The current live phone scene after the 10:21 run is valuable evidence and must not be manually cleaned or rerun while WFC remains healthy.

NEXT_ACTION: pull the timing-optimized source and run the paired PS5.1 `selftest` only. Do not execute the phone path against the preserved live holder scene.
