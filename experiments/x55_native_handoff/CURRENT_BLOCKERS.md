# Current Blockers

Updated: 2026-09-23

Only active blockers belong here. Historical blockers belong in the experiment log or decisions file.

## 1. Re-vote mechanism is not directly evidenced

001B changed qcrild2 PID 13706 -> 873 and pm-service PID 31818 reacquired `/dev/subsys_esoc0`, returning X55 ONLINE with crash_count 0. The complete captured logcat did not contain any required PerMgrLib/PerMgrSrv QCRIL register/vote line.

Resolution: do not infer a verified re-vote from the ownership transition. Further mechanism work requires a separate evidence-based plan and explicit authorization.

## 2. Historical artifact provenance remains incomplete

Exact historical v2.6.2 host source was recovered from Computer A on 2026-09-24 and is now preserved with SHA-256 provenance. Historical raw evidence remains incomplete; source recovery must not be described as full raw-log recovery.

## 3. Exact launcher file-hash path resolved on host

The fourth launch stopped pre-write at `Assert-LocalArtifact` because `Get-FileHash` was not resolved in the paired Windows PowerShell 5.1 process. The production script now uses an internal .NET `SHA256` implementation, and the exact paired `.cmd selftest` invokes production `Assert-LocalArtifact` successfully under Windows PowerShell `5.1.19041.6456`.

Resolution: host/runtime PASS with the pinned helper hash, known SHA-256 vector, orchestrator hash, and zero legacy hash-cmdlet dependencies. `PHONE_NOT_RERUN`; device recovery remains unvalidated.

## Current disposition

- 001: `ABORTED_BEFORE_CONTENDED_PHASE / INCONCLUSIVE`
- 001B: `QCRILD2_RESTART_NO_VALID_REVOTE`
- Current native state: pm-service PID 31818 sole FD9 owner, X55 ONLINE, crash_count 0, holder absent, qcrild2 PID 873.
- 001B phone writes: 2
- Detailed evidence: `X55_OWNERSHIP_HANDOFF_001B.md`
- v2.7-alpha second device launch: `BLOCKED_PRE_WRITE_HOST_SCRIPT_COMPATIBILITY`; phone writes 0; native phone scene unchanged.
- Detailed second-launch evidence: `v2.7-alpha-native-handoff/SECOND_DEVICE_RUN_RESULT.md`
- Host-script compatibility and exact-launcher artifact hashing are statically repaired and audited. No new device run is authorized.
- Third launch: `BLOCKED_PRE_WRITE_MISSING_AUDITED_SINGLE_SIM_HELPER`; phone writes 0; native scene unchanged. The packaging blocker is now resolved by force-tracking the exact audited 11534-byte artifact with SHA-256 `90D6F55FBE1F941C1E3EEE1AA1F93B569FA3AE4084B93C5560082A38AAAF5C39` while retaining the global `*.jar` ignore.
- Detailed third-launch evidence: `v2.7-alpha-native-handoff/THIRD_DEVICE_RUN_RESULT.md`
- Fourth launch: `BLOCKED_PRE_WRITE_PS51_FILEHASH_RESOLUTION`; phone writes 0; native scene unchanged.
- Detailed fourth-launch evidence: `v2.7-alpha-native-handoff/FOURTH_DEVICE_RUN_RESULT.md`
- Fourth-launch blocker repair: exact paired PS5.1 no-ADB selftest PASS; production artifact gate PASS; `PHONE_NOT_RERUN`.

NEXT_ACTION: await fresh explicit authorization before any phone execution or recovery action.
