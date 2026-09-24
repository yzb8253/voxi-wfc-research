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

## X55-V27-ALPHA-FIFTH-DEVICE-005

Date: 2026-09-24 08:49 Asia/Shanghai
Environment: Computer A, Account A; exact clean commit `13d2969acbfe6e43171929583f40b18ed4ceb361`; Windows PowerShell 5.1.19041.6456; USB serial `fd0ff892`.
Pre-state: fresh gate PASS; pm-service PID 31818 sole owner; X55 ONLINE; crash_count 0; holder absent; qcrild2 PID 873; VOXI active/enabled; single-SIM slot0-absent topology; WFC strict F1.
Commands/actions: exact paired selftest PASS, followed by exactly one authorized launcher `execute`. No manual follow-up or retry.
Observed result: per_mgr stop and holder rebirth succeeded; Android holder PID 22129 became sole owner and produced a new PON_SUCCESS. After per_mgr restart, new pm-service PID 22536 acquired the device while the holder still held it, producing dual ownership. The script classified `BEHAVIOR_CHANGED` and stopped before holder release, qcrild2 restart, or SIM cycle.
Fail-safe result: holder TERM was refused because the holder was no longer the unique owner. Final scene remains per_mgr running, holder 22129 plus pm-service 22536 as dual owners, X55 ONLINE, crash_count 0, qcrild2 unchanged at 873, WFC F1, SIM OFF/ON 0/0.
Mechanism evidence: server-side `PerMgrSrv: QCRIL registered` and `PerMgrSrv: QCRIL voting for SDX55M` were captured; the full four-line bilateral evidence gate remains UNPROVEN.
Conclusion: `X55_REBIRTH_SUCCESS / BEHAVIOR_CHANGED / NOT_CHECKED / NOT_RUN`; phone write actions 3. Preserve the scene and do not rerun or clean up without separate explicit authorization.
Evidence: `v2.7-alpha-native-handoff/FIFTH_DEVICE_RUN_RESULT.md`; large logs remain host-only.

## X55-V27-DUAL-OWNER-CLEANUP-006

Date: 2026-09-24 08:58-08:59 Asia/Shanghai
Pre-state: preserved fifth-run scene with holder PID 22129 and pm-service PID 22536 as the exact two `/dev/subsys_esoc0` owners; per_mgr running; X55 ONLINE; crash_count 0; qcrild2 PID 873; WFC F1.
Identity gate: PID file, exact holder cmdline/status, FD9 target, owner set, pm-service PPID/executable, qcrild2 identity, X55, and crash_count all PASS.
Action: exactly one `kill -TERM 22129`; no retry, SIGKILL, service restart, SIM action, or other write.
Observed result: holder and v2.7 PID file disappeared; pm-service 22536 became sole native owner; X55 remained ONLINE; crash_count remained 0; qcrild2 remained PID 873. WFC remained F1 with no qti.cne/ePDG/XFRM recovery.
Conclusion: `MAKE_BEFORE_BREAK_NATIVE_HANDOFF_SUCCESS`; phone write actions 1.
Evidence: `X55_DUAL_OWNER_CLEANUP_006.md`; before/after raw captures remain host-only.

## X55-V27-MAKE-BEFORE-BREAK-STATIC-007

Date: 2026-09-24 Asia/Shanghai
Scope: repository-only redesign and validation; no ADB invocation and no phone access.
Evidence basis: experiment 005 established the exact holder + pm-service dual-owner intermediate state. Cleanup 006 proved that one identity-gated holder TERM transitioned directly to pm-service sole ownership while X55 stayed ONLINE, crash_count stayed 0, and qcrild2 PID did not change.
Changes: separated exact Android holder identity from owner topology; modeled holder sole, exact two-owner holder+pm-service, and pm-service sole states; removed host-process lifetime from holder identity; preserved stale PID files; removed qcrild2 restart from the production path; required unchanged qcrild2 identity; retained at most one optional SIM OFF/ON cycle after native handoff success.
Validation: Windows PowerShell 5.1 parse PASS; paired `.cmd selftest` PASS; artifact hash gate PASS; A-G ownership models PASS; unknown third owner rejected; make-before-break order PASS; production qcrild2 restart count 0; static audit PASS.
Conclusion: `MAKE_BEFORE_BREAK_STATIC_REDESIGN=PASS / PHONE_NOT_RUN`. This validates the implementation model only. It does not promote cleanup 006 into WFC recovery proof.

## X55-V27-ALPHA-MAKE-BEFORE-BREAK-007

Date: 2026-09-24 09:20 Asia/Shanghai
Commit: exact clean `9ccf2eeeac9b4f14b5b662e4a8b076a1552695d4`; paired PS5.1 selftest PASS.
Pre-state: native-clean single-SIM F1; pm-service 22536 sole owner; X55 ONLINE; crash_count 0; holder absent; qcrild2 873.
Observed path: per_mgr stop PASS; holder 27125 sole owner PASS; X55 rebirth/new PON_SUCCESS PASS; per_mgr start formed exact holder 27125 + pm-service 28220 dual ownership PASS.
Stop point: one identity-gated TERM was sent to holder 27125, but it did not exit within 10 seconds. The script stopped without retry. Immediate read-only state showed the holder waiting on child `sleep 60`, PID file present, dual ownership preserved, X55 ONLINE, crash_count 0, and qcrild2 unchanged at 873.
SIM/WFC: SIM OFF/ON 0/0; WFC remained F1; no qti.cne/ePDG/XFRM.
Conclusion: `HOLDER_TERM_DEFERRED_TIMEOUT / PRESERVED_DUAL_OWNER`; production results `X55_REBIRTH_SUCCESS / NOT_RUN / NOT_CHECKED / NOT_RUN`; phone write actions 4.
Evidence: `v2.7-alpha-native-handoff/SEVENTH_DEVICE_RUN_RESULT.md`; raw logs remain host-only.


## X55-V27-ALPHA-EIGHTH-DEVICE-008

Date: 2026-09-24 09:40-09:43 Asia/Shanghai
Commit: exact clean `81b5de257941f7bad9183cc4e9ec7b241de7b63e`; paired PS5.1 selftest PASS.
Pre-state: native-clean single-SIM F1; pm-service 28220 sole owner; X55 ONLINE; crash_count 0; holder absent; qcrild2 873.
Observed path: per_mgr stop PASS; holder sole PASS; X55 rebirth/new PON_SUCCESS PASS; per_mgr contended start PASS; exact dual ownership PASS; exact holder TERM/exit PASS; pm-service sole PASS; native cleanup PASS. Production qcrild2 restart count remained zero.
SIM/WFC: exactly one single-SIM software POWER_DOWN/POWER_UP cycle completed successfully at the helper/API level. The subscription/UICC stack rebuilt, but bounded WFC samples remained IMS NOT_REGISTERED, WFC unavailable, qti.cne request absent, ePDG absent, XFRM absent.
Conclusion: `X55_REBIRTH_SUCCESS / MAKE_BEFORE_BREAK_NATIVE_HANDOFF_SUCCESS / FAILED_AFTER_ONE_SIM_CYCLE / NATIVE_CLEAN`. The remaining question is recovery ordering: run 008 performed native cleanup before the SIM cycle, unlike the previously successful v2.5/v2.6.2 holder/per_mgr-stopped recovery scene.
Evidence: `v2.7-alpha-native-handoff/EIGHTH_DEVICE_RUN_RESULT.md`; key evidence archive and full raw logcat remain host-side.

## X55-V27-RECOVERY-BEFORE-CLEANUP-STATIC-009

Date: 2026-09-24 Asia/Shanghai
Scope: repository-only source redesign after run 008; no phone operation performed by this change.
Change: move the optional one-shot SIM recovery cycle into the fresh-X55 holder-sole/vendor.per_mgr-stopped window; only afterward perform the already validated make-before-break native cleanup. Add `PRE_CLEANUP_WFC_RESULT` and a post-cleanup WFC survival check so recovery and cleanup effects are separable.
Safety retained: exact holder identity; one optional SIM OFF/ON; no qcrild2 restart; no cnd restart; no kill -9; exact dual-owner cleanup; pm-service sole/X55 ONLINE/crash_count 0 gate.
Conclusion: source redesign committed; exact paired PS5.1 selftest still required before any new phone execution.


## X55-V27-RECOVERY-BEFORE-CLEANUP-DEVICE-010

Date: 2026-09-24 10:21-10:26 Asia/Shanghai
Baseline: exact clean `a45bd0633b18be765bab80b45ed41cbfc66160f5`; paired PS5.1 selftest PASS.
Pre-state: native-clean single-SIM F1; pm-service sole owner; X55 ONLINE/crash_count 0; holder absent; qcrild2 PID 873.
Observed recovery: per_mgr stop PASS; holder sole PASS; X55 rebirth/new PON_SUCCESS PASS; exactly one SIM POWER_DOWN/UP completed. Full WFC recovered before cleanup, including IMS REGISTERED over WLAN, qti.cne request 929, IMS IWLAN NetworkAgent 107, UDP/4500 keepalive and XFRM in later read-only status.
Critical timing: qcrild2 logged PeripheralManager server death at 10:21:25.263 and failed service-reconnect rounds through 10:21:55.556. The script did not start pm-service until 10:25:12.954; the new server reported SDX55M voter/listener count 0/0 and no client, so exact dual ownership never formed.
Result: recovery success before cleanup; cleanup blocked as `EXPECTED_DUAL_OWNER_NOT_FORMED`; live scene intentionally preserved with WFC healthy, holder sole, pm-service running without esoc0 ownership, X55 ONLINE/crash_count 0, qcrild2 unchanged.
Evidence: `v2.7-alpha-native-handoff/RECOVERY_BEFORE_CLEANUP_102120_RESULT.md`.
Next design: pre-stage slow artifacts before per_mgr stop and request per_mgr start immediately after successful SIM POWER_UP while keeping the holder alive until WFC observation completes.


## X55-V27-TIMING-OPTIMIZED-SELFTEST-011

Date: 2026-09-24 11:xx Asia/Shanghai
Commit: `355436b8a74fe883f16829bbcb52af22f7df4b5c`
Environment: Windows PowerShell 5.1.19041.6456.

Paired launcher `selftest` passed with zero phone writes. Key results:

```text
PS51_PARSE=PASS
ARTIFACT_GATE=PASS
HOLDER_IDENTITY_MODEL=PASS
HOLDER_SOLE_MODEL=PASS
DUAL_OWNER_MODEL=PASS
PM_SOLE_MODEL=PASS
MAKE_BEFORE_BREAK_STATE_MACHINE=PASS
RECOVERY_BEFORE_CLEANUP_STATE_MACHINE=PASS
TIMING_OPTIMIZED_RECONNECT_WINDOW=PASS
PRESTAGE_BEFORE_PER_MGR_STOP=PASS
EARLY_PER_MGR_START_AFTER_POWER_UP=PASS
QCRILD2_RESTARTS_IN_NEW_PATH=0
SIM_OFF_MAX=1
SIM_ON_MAX=1
STATIC_NO_ADB=PASS
WINDOWS_ARGUMENT_ROUNDTRIP=PASS
PHONE_WRITES=0
```

The current live phone scene from the previous recovery run is intentionally not a valid entry state for device execution: WFC is healthy, the exact holder remains sole owner of `/dev/subsys_esoc0`, and pm-service is running without esoc0 ownership. Do not execute the timing-optimized path against that preserved scene. Establish a fresh native-clean baseline first.
