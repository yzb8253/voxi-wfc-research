# Current Blockers

Updated: 2026-09-23

Only active blockers belong here. Historical blockers belong in the experiment log or decisions file.

## 1. Re-vote mechanism is not directly evidenced

001B changed qcrild2 PID 13706 -> 873 and pm-service PID 31818 reacquired `/dev/subsys_esoc0`, returning X55 ONLINE with crash_count 0. The complete captured logcat did not contain any required PerMgrLib/PerMgrSrv QCRIL register/vote line.

Resolution: do not infer a verified re-vote from the ownership transition. Further mechanism work requires a separate evidence-based plan and explicit authorization.

## 2. Historical artifact provenance remains incomplete

The exact historical v2.6.2 source and raw evidence remain absent from GitHub. This does not invalidate the independently captured 001/001B evidence, but it limits comparison with the older implementation.

## Current disposition

- 001: `ABORTED_BEFORE_CONTENDED_PHASE / INCONCLUSIVE`
- 001B: `QCRILD2_RESTART_NO_VALID_REVOTE`
- Current native state: pm-service PID 31818 sole FD9 owner, X55 ONLINE, crash_count 0, holder absent, qcrild2 PID 873.
- 001B phone writes: 2
- Detailed evidence: `X55_OWNERSHIP_HANDOFF_001B.md`
- v2.7-alpha second device launch: `BLOCKED_PRE_WRITE_HOST_SCRIPT_COMPATIBILITY`; phone writes 0; native phone scene unchanged.
- Detailed second-launch evidence: `v2.7-alpha-native-handoff/SECOND_DEVICE_RUN_RESULT.md`
- Both host-script blockers are statically repaired and audited. No active host compatibility blocker remains, but no third device run is authorized.

NEXT_ACTION: stop. Do not perform an additional phone execution or recovery action without fresh explicit approval.
