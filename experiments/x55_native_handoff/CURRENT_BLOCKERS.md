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

NEXT_ACTION: stop. Wait for a new explicit decision; do not perform an additional recovery or process action.

## 3. v2.7-alpha paired launcher is incompatible with Windows PowerShell 5.1

The first authorized launch stopped before its first ADB call because `Run-X55-WFC-v2.7-alpha-native-handoff.cmd` invokes `powershell.exe`, while the state machine uses `ProcessStartInfo.ArgumentList`, which is not available in Windows PowerShell 5.1.

Disposition: `BLOCKED_PRE_WRITE / NOT_RUN`; phone writes 0. No holder, qcrild2 restart, ownership transition, or SIM cycle occurred.

Resolution required: make the process wrapper compatible with Windows PowerShell 5.1 or explicitly select a verified compatible runtime, then extend the audit to execute a dry-run through the exact paired launcher. A second real run requires fresh authorization.
