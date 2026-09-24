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

## X55-V27-ALPHA-FIRST-DEVICE-001

Date: 2026-09-23 20:37 Asia/Shanghai
Environment: Computer B, Account A, fresh clean GitHub clone at `1949b6f90572e2b7eee60963cab8b18fc6b07591`, USB serial `fd0ff892`.
Pre-state: independent read-only entry gate PASS; pm-service PID 31818 sole FD9 owner; X55 ONLINE; crash_count 0; no holder; qcrild2 PID 873; VOXI active/enabled; initial WFC F1.
Commands/actions: executed the repository paired launcher exactly once with argument `execute`.
Observed result: Windows PowerShell 5.1 raised `ProcessStartInfo.ArgumentList` missing before the first ADB call. State-machine results remained NOT_RUN/NOT_CHECKED and phone writes were 0.
Post-state: pm-service PID 31818 remained sole owner; qcrild2 PID 873 unchanged; X55 ONLINE; crash_count 0; holder absent; SIM OFF 0; SIM ON 0; WFC unchanged F1.
Logs: host-only complete log `voxi_wfc_local_runs/v27_alpha_native_handoff_20260923_203708/experiment.log`; sanitized result `v2.7-alpha-native-handoff/FIRST_DEVICE_RUN_RESULT.md`.
Interpretation: host runtime compatibility blocker; no native experiment occurred.
Conclusion: `BLOCKED_PRE_WRITE_PS51_INCOMPATIBILITY / NOT_RUN`; phone writes 0.
Next action: fix and audit exact Windows PowerShell 5.1 launcher compatibility, then require fresh authorization before another execution.

## X55-V27-ALPHA-PS51-COMPAT-001

Date: 2026-09-23 20:52 Asia/Shanghai
Environment: Computer B, Account A; host-only development at baseline `54d38cdfe72e8bd5d6e60e1be19fc5c051c11d22`; no ADB invocation.
Pre-state: first launcher run classified `BLOCKED_PRE_WRITE_PS51_INCOMPATIBILITY`; phone remained clean/native F1 with phone writes 0.
Commands/actions: replaced .NET Core-only process argument/kill APIs with Windows PowerShell 5.1-compatible equivalents; added a local-only launcher self-test; expanded the static audit.
Observed result: Windows PowerShell `5.1.19041.6456`; parser errors 0; static audit PASS; `.cmd selftest` PASS; complex Windows argv/Android holder payload round-trip PASS.
Safety result: PID-variable, ADB quoting, holder lifecycle, fail-safe, forbidden paths, helper hashes, fixed target gates, and native handoff state-machine ordering all PASS. State machine unchanged.
Phone writes: 0. No ADB command, holder, X55 transition, process restart, or SIM action occurred.
Conclusion: `PS51_COMPATIBILITY_STATIC_ACCEPTANCE=PASS / PHONE_NOT_RERUN`.
Next action: stop and wait for explicit approval before another real v2.7-alpha execution.

## X55-V27-ALPHA-SECOND-DEVICE-002

Date: 2026-09-23 21:00:59 Asia/Shanghai
Environment: Computer B, Account A, clean branch `voxi-wfc-auto-recovery` at exact commit `cd222ea058dbb1f2b88905b99987885f3a9438ce`; Windows PowerShell 5.1.19041.6456; USB serial `fd0ff892`.
Pre-state: fresh independent read-only entry gate PASS; pm-service PID 31818 sole FD9 owner; X55 ONLINE; crash_count 0; holder absent; qcrild2 PID 873; VOXI active/enabled; WFC F1.
Commands/actions: executed `Run-X55-WFC-v2.7-alpha-native-handoff.cmd execute` exactly once. No manual follow-up or recovery action.
Observed result: script exited before its internal entry gate with `A hash table can only be added to another hash table.` `$matches` in `Resolve-ExactProcess` collided with automatic `$Matches`. The raw entry artifact also showed CRLF-contaminated Android shell tokens.
Post-state: read-only confirmation found pm-service PID 31818 still sole owner, qcrild2 PID 873 unchanged, X55 ONLINE, crash_count 0, holder absent, SIM OFF 0, SIM ON 0, WFC F1.
Logs: host-only `C:\Users\TT\Desktop\platform-tools\voxi_wfc_local_runs\v27_alpha_native_handoff_20260923_210059`; durable result `v2.7-alpha-native-handoff/SECOND_DEVICE_RUN_RESULT.md`.
Interpretation: a second host compatibility blocker prevented the native experiment; no state-machine write phase occurred.
Conclusion: `BLOCKED_PRE_WRITE_HOST_SCRIPT_COMPATIBILITY / NOT_RUN`; phone writes 0.
Next action: repair both host defects, rerun static/no-ADB acceptance, and require fresh authorization before any device execution.

## X55-V27-ALPHA-HOST-COMPAT-002

Date: 2026-09-23
Environment: Computer B, Account A; host-only repair from commit `1da149f1629a103cb05ce30200ec727aa31f3a7c`; no ADB invocation.
Pre-state: second device launch classified `BLOCKED_PRE_WRITE_HOST_SCRIPT_COMPATIBILITY`; native phone scene preserved with phone writes 0.
Commands/actions: renamed the custom process collection; added central Android LF normalization; expanded the Windows PowerShell 5.1 parser, automatic-variable, payload, and command-construction tests. No phone command was executed.
Observed result: PS5.1 parser PASS; automatic-variable audit PASS; custom Matches variables 0; LF normalization PASS; Android payload CR count 0; holder/qcrild2/SIM command builds PASS; static no-ADB PASS.
Safety result: native handoff ordering, hard gates, holder identity, fail-safe, qcrild2 limit, SIM OFF/ON limits, forbidden paths, and fixed target design remain unchanged.
Conclusion: `HOST_SCRIPT_COMPATIBILITY_STATIC_ACCEPTANCE=PASS / PHONE_NOT_RERUN`; phone writes 0.
Next action: stop and wait for explicit approval before any third real v2.7-alpha launch.

## X55-V27-ALPHA-THIRD-DEVICE-003

Date: 2026-09-23 21:24:13 Asia/Shanghai
Environment: Computer B, Account A; exact clean commit `e279af23770c7fd37562f3589095429380dd44eb`; Windows PowerShell 5.1.19041.6456; USB serial `fd0ff892`.
Pre-state: fresh device/native gates PASS; pm-service PID 31818 sole FD9 owner; X55 ONLINE; crash_count 0; holder absent; qcrild2 PID 873; VOXI active/enabled; WFC F1.
Commands/actions: executed the repository launcher exactly once with `execute`; no manual follow-up.
Observed result: fixed single-SIM helper JAR missing from its git-ignored build path. `Assert-LocalArtifact` stopped before `ENTRY_GATE=PASS` logging, logcat startup, or the first phone write.
Post-state: pm-service PID 31818 remained sole owner; X55 ONLINE; crash_count 0; qcrild2 PID 873; holder absent; SIM OFF/ON 0/0; WFC F1.
Logs: host-only `C:\Users\TT\Desktop\platform-tools\voxi_wfc_local_runs\v27_alpha_native_handoff_20260923_212413`; sanitized result `v2.7-alpha-native-handoff/THIRD_DEVICE_RUN_RESULT.md`.
Conclusion: `BLOCKED_PRE_WRITE_MISSING_AUDITED_SINGLE_SIM_HELPER / NOT_RUN`; phone writes 0.
Next action: static artifact rebuild/hash verification and packaging preflight correction; require fresh authorization before another device launch.

## X55-V27-ALPHA-FOURTH-DEVICE-004

Date: 2026-09-23 21:48:13 Asia/Shanghai
Environment: Computer B, Account A; exact clean commit `12e59b9b78589657f3f62938b957ba73ff9ee183`; Windows PowerShell 5.1.19041.6456; USB serial `fd0ff892`.
Pre-state: fresh external device/native gate PASS; pm-service PID 31818 sole FD9 owner; X55 ONLINE; crash_count 0; holder absent; qcrild2 PID 873; VOXI active/enabled; WFC F1.
Commands/actions: paired launcher executed exactly once with `execute`; no manual follow-up.
Observed result: local `Assert-LocalArtifact` stopped because `Get-FileHash` was not resolved in the exact launcher runtime. No state-machine write began.
Post-state: pm-service PID 31818 sole owner; X55 ONLINE; crash_count 0; qcrild2 PID 873; holder absent; SIM OFF/ON 0/0; WFC F1.
Logs: host-only `C:\Users\TT\Desktop\platform-tools\voxi_wfc_local_runs\v27_alpha_native_handoff_20260923_214813`; sanitized report `v2.7-alpha-native-handoff/FOURTH_DEVICE_RUN_RESULT.md`.
Conclusion: `BLOCKED_PRE_WRITE_PS51_FILEHASH_RESOLUTION / NOT_RUN`; phone writes 0.
Next action: exact-launcher PS5.1 hash repair and no-ADB artifact-gate coverage; require fresh authorization before another device launch.

## COMPUTER-A-LEGACY-RECOVERY-20260924

Date: 2026-09-24
Environment: Computer A filesystem and Git only.
Actions: hashed 465 D: candidates; compared them with the authoritative repository; copied selected source and compact evidence without modifying D:; inspected ZIP entries; generated provenance, raw-evidence, and parser manifests.
Observed result: exact v2.6.2 host source recovered; PassiveMonitor v1.2 canonicalized; StateSearcher v3.0-v3.5 and SSR read-only audit preserved. Large raw logs and non-source binaries remain host-only.
Validation: source hash match PASS; critical PassiveMonitor v1.2 and v2.6.2 parser checks PASS; 20/22 imported PowerShell files parse, with two exact historical originals explicitly retained as parser failures.
Conclusion: `COMPUTER_A_LEGACY_RECOVERY=PASS`; ADB not used; phone writes 0.
Next action: no device experiment is authorized by this import.
