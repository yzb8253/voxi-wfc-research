# Current Blockers

Updated: 2026-09-23

Only active blockers belong here. Historical blockers belong in the experiment log or decisions file.

## 1. Re-vote mechanism is not directly evidenced

001B changed qcrild2 PID 13706 -> 873 and pm-service PID 31818 reacquired `/dev/subsys_esoc0`, returning X55 ONLINE with crash_count 0. The complete captured logcat did not contain any required PerMgrLib/PerMgrSrv QCRIL register/vote line.

Resolution: do not infer a verified re-vote from the ownership transition. Further mechanism work requires a separate evidence-based plan and explicit authorization.

## 2. Historical artifact provenance remains incomplete

The exact historical v2.6.2 source and raw evidence remain absent from GitHub. This does not invalidate the independently captured 001/001B evidence, but it limits comparison with the older implementation.

## 3. Required single-SIM helper binary is absent on a fresh checkout

The v2.7-alpha single-SIM path requires `experiments/sim_soft_reset/single_sim_isolation/build/single-sim-slot1-power-helper.jar` with pinned SHA-256 `90D6F55FBE1F941C1E3EEE1AA1F93B569FA3AE4084B93C5560082A38AAAF5C39`. The JAR is ignored by `*.jar` and is absent on Computer B.

Resolution: reproduce the helper from audited source, verify the exact pinned hash, and add a host-only packaging/preflight acceptance that proves required binaries exist before device authorization. Do not weaken the hash gate.

## Current disposition

- 001: `ABORTED_BEFORE_CONTENDED_PHASE / INCONCLUSIVE`
- 001B: `QCRILD2_RESTART_NO_VALID_REVOTE`
- Current native state: pm-service PID 31818 sole FD9 owner, X55 ONLINE, crash_count 0, holder absent, qcrild2 PID 873.
- 001B phone writes: 2
- Detailed evidence: `X55_OWNERSHIP_HANDOFF_001B.md`
- v2.7-alpha second device launch: `BLOCKED_PRE_WRITE_HOST_SCRIPT_COMPATIBILITY`; phone writes 0; native phone scene unchanged.
- Detailed second-launch evidence: `v2.7-alpha-native-handoff/SECOND_DEVICE_RUN_RESULT.md`
- Both host-script blockers are statically repaired and audited. No active host compatibility blocker remains, but no third device run is authorized.
- Third launch: `BLOCKED_PRE_WRITE_MISSING_AUDITED_SINGLE_SIM_HELPER`; phone writes 0; native scene unchanged.
- Detailed third-launch evidence: `v2.7-alpha-native-handoff/THIRD_DEVICE_RUN_RESULT.md`

NEXT_ACTION: static helper rebuild/hash verification and packaging/preflight correction only. Do not perform another phone execution or recovery action without fresh explicit approval.
