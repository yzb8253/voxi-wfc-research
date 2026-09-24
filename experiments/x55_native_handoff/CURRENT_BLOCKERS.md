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

## 4. Production contention/cleanup gate does not model valid dual-owner handoff

The fifth authorized run showed that pm-service can acquire `/dev/subsys_esoc0` while the script holder remains an owner. This violates the production script's expected holder-only contention gate. The holder cleanup predicate requires unique ownership, so fail-safe TERM was refused after dual ownership appeared.

Experiment 006 then strictly revalidated holder PID 22129 and sent one TERM. The holder and PID file disappeared, pm-service PID 22536 became sole owner, X55 stayed ONLINE, crash_count stayed 0, and qcrild2 remained PID 873. This proves the make-before-break native handoff behavior for this scene.

The live cleanup blocker is resolved. Production code still requires a separate static redesign/audit so it can recognize the dual-owner intermediate state and safely release only its exact holder without weakening PID/cmdline/FD9 identity checks. Do not rerun or broaden recovery automatically.

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

NEXT_ACTION: statically redesign and audit the v2.7 contention/holder cleanup gate for the now-proven dual-owner intermediate state. Do not execute another device run without explicit authorization.
