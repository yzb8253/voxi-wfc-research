# X55 Native Handoff Experiment Log

Append new entries. Never rewrite old records; append a correction when interpretation changes.

## X55-PM-CLEAN-RESTART-001

Date: 2026-09-23 handoff import; original run time not preserved in Git
Environment: Xiaomi 10/cas, Android 13, Magisk, SDX55M, clean native clients, no holder.
Pre-state: pm-service PID 1232 owned `/dev/subsys_esoc0`; X55 ONLINE.
Commands/actions: one per_mgr stop, then one per_mgr start.
Observed result: new pm-service PID 13288 reacquired the node before qcrild2 restart; X55 ONLINE.
Logs: transferred ChatGPT handoff; raw source log pending import.
Interpretation: ownership reacquisition works without AP boot when no holder contends.
Conclusion: `VERIFIED` by transferred device evidence; raw provenance pending.
Next action: keep separate from holder-contended behavior.

## X55-QCRIL-VOTE-001

Date: 2026-09-23 handoff import; original run time not preserved in Git
Environment: fixed-slot2 `/vendor/bin/hw/qcrild -c 2`.
Pre-state: SDX55M ONLINE in the transferred qcrild2 restart experiment.
Commands/actions: restart fixed-slot2 qcrild2.
Observed result: QCRIL was added and registered, successfully registered for SDX55M, voted, and voter count reached two.
Logs: exact messages in `docs/CURRENT_RESEARCH_STATE.md`; raw source pending import.
Interpretation: qcrild2 is a real Peripheral Manager client/voter.
Conclusion: `VERIFIED` by transferred device logs; raw provenance pending.
Next action: at most one qcrild2 re-registration as candidate trigger after holder release.

## X55-V262-CLEANUP-001

Date: 2026-09-23 handoff import; original run time not preserved in Git
Environment: v2.6.2 X55 rebirth and one fixed SIM2 cycle.
Pre-state: clean native baseline followed by polluted airplane OFF -> ON state.
Commands/actions: X55 rebirth; one SIM2 OFF -> 3 seconds -> ON; cleanup attempted while holder stayed alive.
Observed result: WFC HEALTHY after about 11 seconds; cleanup failed to restore native pm-service ownership because pm-service started while holder owned the node.
Logs: transferred handoff; v2.6.2 source/raw logs missing from Git.
Interpretation: recovery succeeded, cleanup ordering failed; post-release handoff remains unresolved.
Conclusion: recovery `VERIFIED`; cleanup `FAILED`; ownership behavior `INCONCLUSIVE`.
Next action: ownership-only test after exact artifacts return.

## X55-OWNERSHIP-PRECHECK-20260923

Date: 2026-09-23 15:06:53 Asia/Shanghai
Environment: Computer A, Account A, serial `fd0ff892`, baseline `12ffbdf79d45b1b61ee67ae317a67b2608ffc5d9`.
Pre-state: pm-service 13288, pm-proxy 1699, qcrild 1926, qcrild2 13706, mdm_helper 1297; VOXI active/enabled; no holder file.
Commands/actions: read-only Git, process, init, node, status, and SELinux-access checks; no phone write.
Observed result: SELinux denied pm-service FD and X55 state/crash_count reads; Git lacked holder/observer. Native owner, ONLINE, and zero crash count were unverified.
Logs: `OWNERSHIP_HANDOFF_PRECHECK.md`, command audit, and experiments JSONL.
Interpretation: safety gate incomplete; historical PID match is not current owner proof.
Conclusion: `BLOCKED_PRE_WRITE / NOT_RUN`; phone writes 0.
Next action: restore and audit holder/observer, then repeat read-only gate.

## X55-OWNERSHIP-HANDOFF-001

Date: 2026-09-23 15:56:55 Asia/Shanghai
Environment: Computer A, Account A, serial `fd0ff892`; enforcing SELinux; new independent PowerShell probe.
Pre-state: entry gate PASS; pm-service PID 13288 sole FD9 owner; X55 ONLINE; crash_count 0; no holder; qcrild2 PID 13706.
Commands/actions: logcat clear; per_mgr stop; one fixed holder start; after host-script failure, TERM own holder and start per_mgr for fail-safe cleanup. No qcrild2 restart.
Observed result: holder PID 31163 became sole owner and X55 ONLINE, but a PowerShell `$Pid`/`$PID` collision aborted before per_mgr was started under contention. Cleanup left per_mgr running as PID 31818, no node owner, X55 OFFLINE, crash_count 0, holder absent, qcrild2 unchanged.
Logs: `X55_OWNERSHIP_HANDOFF_001_ABORTED.md`, `logs/20260923_155633/`, and `logs/20260923_155655/`; full raw logcat retained host-only.
Interpretation: holder power-up worked, but holder+pm-service contention and QCRIL re-vote were not tested.
Conclusion: `ABORTED_BEFORE_CONTENDED_PHASE / INCONCLUSIVE`; phone-write count 5.
Next action: preserve OFFLINE/no-owner scene; no automatic rerun or qcrild2 restart without a new explicit decision.

## X55-OWNERSHIP-HANDOFF-001B

Date: 2026-09-23 16:20:25 Asia/Shanghai
Environment: preserved no-owner/X55-OFFLINE scene from 001; serial `fd0ff892`; enforcing SELinux.
Pre-state: entry gate PASS; per_mgr running; pm-service PID 31818; owner none; X55 OFFLINE; crash_count 0; holder absent; fixed-slot2 qcrild2 PID 13706.
Commands/actions: one logcat clear and exactly one `ctl.restart vendor.qcrild2`; no other phone write.
Observed result: qcrild2 PID 13706 -> 873; pm-service PID 31818 became sole FD9 owner; X55 ONLINE; crash_count 0. Complete logcat contained no required PerMgrLib/PerMgrSrv QCRIL register/vote lines.
Logs: `X55_OWNERSHIP_HANDOFF_001B.md`, `logs/20260923_162025/`; full raw logcat retained host-only.
Interpretation: native reacquisition occurred, but the experiment did not log-confirm a valid qcrild2 register/vote sequence.
Conclusion: `QCRILD2_RESTART_NO_VALID_REVOTE`; phone writes 2.
Next action: stop; do not execute an additional recovery action.


## X55-V27-ALPHA-STATIC-001

Date: 2026-09-23
Environment: local repository only; phone disconnected/not required.
Pre-state: 001B behavioral native reacquire confirmed; internal re-vote log mechanism unproven.
Commands/actions: created v2.7-alpha host state machine, explicit launcher, fixed dual/single device orchestrators, and repeatable static policy audit. No ADB or phone action.
Observed result: PowerShell parse PASS; Android shell parse PASS; static write-surface and safety audit PASS; v2.6.2 untouched.
Interpretation: the approved native-owner-first design is implemented and ready only for a separately authorized controlled run.
Conclusion: BUILD_STATIC_AUDIT_PASS / NOT_EXECUTED; phone writes 0.
Next action: wait for explicit execution approval.
