# ChatGPT to Codex Handoff

Updated: 2026-09-23 21:51 Asia/Shanghai

## Session identity

- Computer: Computer B
- Account: Account A
- Branch: `voxi-wfc-auto-recovery`
- Synchronized baseline before the latest experiment: `1949b6f90572e2b7eee60963cab8b18fc6b07591`
- Current commit: resolve with `git rev-parse HEAD`; this file is authoritative from its containing commit.
- GitHub is the only durable source of truth.

## Device / ADB

- Windows; ADB `C:\Users\TT\Desktop\platform-tools\adb.exe`
- Last serial `fd0ff892`; rediscover every session.
- Xiaomi 10 / `cas` / Android 13 / Magisk
- Qualcomm SDX55M/X55
- VOXI: physical slot2, Android slot index 1, phoneId 1, commonly subId 11, MCCMNC 23415, carrierId 28

## Current goal

Prove a safe handoff from a temporary `/dev/subsys_esoc0` holder back to native pm-service. This test has no SIM cycle and does not judge WFC health.

## Latest conclusions

Labels: `DEVICE_CONFIRMED` was reproduced in this Codex/device session. `TRANSFERRED_VERIFIED` was verified in the cross-account handoff. Exact v2.6.2 host source was recovered from Computer A on 2026-09-24; historical raw-log completeness remains unresolved.

- `TRANSFERRED_VERIFIED`: Binder `vendor.qcom.PeripheralManager`, interface `vendor.qcom.IPeripheralManager`.
- `TRANSFERRED_VERIFIED`: `libperipheral_client.so` exports register/connect/disconnect/unregister/event-acknowledge calls.
- `DEVICE_CONFIRMED`: init maps `vendor.per_mgr` to `/vendor/bin/pm-service` and starts `vendor.per_proxy` when per_mgr runs.
- `DEVICE_CONFIRMED`: fixed-slot2 RIL is `/vendor/bin/hw/qcrild -c 2`.
- `TRANSFERRED_VERIFIED`: qcrild2 logs prove QCRIL register and vote for SDX55M.
- `TRANSFERRED_VERIFIED`: X55 rebirth plus one fixed SIM2 cycle recovered WFC HEALTHY in at least two key runs.
- `TRANSFERRED_VERIFIED`: with clean native clients and no holder, per_mgr stop/start let new pm-service reacquire `/dev/subsys_esoc0` before qcrild2 restart; X55 stayed ONLINE.

## Correction

The old boot-only ownership belief is rejected. Clean/native stop-start reacquisition works. Holder contention is a separate unresolved state. See `DECISIONS_AND_CORRECTIONS.md`.

## Current experiment / phone scene

- `X55-OWNERSHIP-HANDOFF-001B`: `QCRILD2_RESTART_NO_VALID_REVOTE`.
- Entry gate passed on the preserved scene: per_mgr running, pm-service PID 31818, owner none, X55 OFFLINE, crash_count 0, holder absent, qcrild2 PID 13706.
- Exactly one qcrild2 restart changed PID 13706 -> 873.
- pm-service PID 31818 became sole FD9 owner, X55 became ONLINE, and crash_count remained 0.
- Complete logcat contained no required PerMgrLib/PerMgrSrv QCRIL register/vote lines. Native reacquisition is confirmed, but QCRIL re-vote is not.
- Phone writes: 2 (one logcat clear and one qcrild2 restart). No additional recovery action was performed. Never reuse recorded PIDs.

## Unique next action

Stop after 001B. Do not run another process action or recovery automatically; a new explicit decision is required.

## Safety / forbidden actions

Dynamic PIDs only; PRE/POST evidence; fail safe on unknown gates; no unknown holder. No arbitrary raw QMI/Binder/HIDL writes, `setenforce 0`, SELinux bypass, physical SIM action, unapproved SIM cycle, second SIM power ON, LOCATION/Anywhere/VPN changes, unrelated vendor.cnd restart, broad radio restart, or casual SIGKILL.

## Read first

1. `AGENTS.md`
2. `docs/CHATGPT_HANDOFF.md`
3. `docs/CURRENT_RESEARCH_STATE.md`
4. `docs/DECISIONS_AND_CORRECTIONS.md`
5. `experiments/x55_native_handoff/README.md`
6. `experiments/x55_native_handoff/CURRENT_BLOCKERS.md`
7. `experiments/x55_native_handoff/EXPERIMENT_LOG.md`
8. `experiments/x55_native_handoff/OWNERSHIP_HANDOFF_PRECHECK.md`


## v2.7-alpha native-handoff checkpoint

The 001B behavior is now classified as VERIFIED_NATIVE_REACQUIRE_AFTER_QCRILD2_RESTART. The proposed internal re-vote mechanism remains REVOTE_MECHANISM_LOG_UNPROVEN because the expected PerMgr register/vote strings were absent.

The new v2.7-alpha implementation restores native pm-service ownership before checking WFC and before any optional SIM2 cycle. It is dry-run by default, fail-closed on changed ownership behavior, and contains no automatic retry. Static audits pass. It has not been executed on a phone.

Unique next action: wait for explicit user approval to run the controlled v2.7-alpha experiment.

## v2.7-alpha first device launch

- Baseline: `1949b6f90572e2b7eee60963cab8b18fc6b07591` from a fresh clean GitHub clone.
- The independent read-only entry gate passed: serial/root/device/airplane/Wi-Fi/services/native owner/X55/crash count/no-holder/VOXI-UICC were valid; initial WFC was F1.
- The repository launcher was executed exactly once with `execute`.
- Result: `BLOCKED_PRE_WRITE`. Windows PowerShell 5.1 does not provide the `ProcessStartInfo.ArgumentList` property used by the script, so it failed before its first ADB call.
- Script output: recovery NOT_RUN, native handoff NOT_RUN, final WFC NOT_CHECKED, cleanup NOT_RUN, phone writes 0.
- Post-failure read-only verification found the scene unchanged: pm-service PID 31818 sole FD9 owner, qcrild2 PID 873, X55 ONLINE, crash_count 0, no holder, no SIM OFF/ON, WFC F1.
- Sanitized result: `experiments/x55_native_handoff/v2.7-alpha-native-handoff/FIRST_DEVICE_RUN_RESULT.md`.

Unique next action: fix the host process-launch wrapper for Windows PowerShell 5.1 (or change the paired launcher/runtime explicitly), add a runtime dry-run test, and obtain fresh authorization before any second real execution.

## v2.7-alpha PowerShell 5.1 compatibility repair

- First launch classification is now explicitly `BLOCKED_PRE_WRITE_PS51_INCOMPATIBILITY`, not a recovery failure.
- Exact baseline fault: `ProcessStartInfo.ArgumentList` at original line 65; original line 224 contained a second latent use. Windows PowerShell 5.1 uses .NET Framework and lacks this .NET Core collection. The .NET Core-only `Process.Kill(bool)` calls now use exact script-owned PID `taskkill /T /F` with fallback, preserving host process-tree cleanup.
- Both process launch paths now use a reviewed Windows command-line encoder with `ProcessStartInfo.Arguments`; no phone state-machine branch or safety gate changed.
- The paired launcher now supports `selftest`, which selects `-StaticNoAdb`, refuses `-Execute`, exits before ADB initialization, and round-trips the real quoting metacharacters/holder payload through a local child process.
- Native Windows PowerShell result: version `5.1.19041.6456`, parser errors 0, static audit PASS, launcher self-test PASS, argv round-trip PASS, phone writes 0.
- No ADB command was issued during repair or validation. The repaired script has not been run against the phone.

Unique next action: stop and wait for explicit approval before a second real v2.7-alpha execution.

## v2.7-alpha second device launch

- Tested the exact repaired commit `cd222ea058dbb1f2b88905b99987885f3a9438ce` from a clean worktree under Windows PowerShell `5.1.19041.6456`.
- A fresh independent read-only entry gate passed: serial/root/airplane/native services/pm-service sole FD9 owner/X55 ONLINE/crash_count 0/no holder/qcrild2/VOXI-UICC were valid; WFC was F1.
- The paired launcher was executed exactly once with `execute` and stopped before any phone write.
- Exact exception: `A hash table can only be added to another hash table.` `Resolve-ExactProcess` line 155 used `$matches`, which aliases case-insensitive automatic `$Matches`; `-match` at lines 160-161 replaced it with a hashtable before `$matches += $item`.
- The saved entry capture exposed a second blocker: the CRLF here-string at lines 179-200 reached Android `sh` unchanged, causing `id\r` and `2>&$'1\r'` errors.
- Post-failure read-only state remained native and unchanged: pm-service PID 31818 sole FD9 owner, qcrild2 PID 873, X55 ONLINE, crash_count 0, no holder, SIM OFF/ON 0/0, WFC F1.
- Classification: `BLOCKED_PRE_WRITE_HOST_SCRIPT_COMPATIBILITY`; recovery/native-handoff remain NOT_RUN, final WFC NOT_CHECKED, phone writes 0.
- Full result: `experiments/x55_native_handoff/v2.7-alpha-native-handoff/SECOND_DEVICE_RUN_RESULT.md`.

## v2.7-alpha second host compatibility repair

- `$matches` was replaced by `$resolvedProcesses`; executable source now has zero custom `$matches`/`$Matches` variables.
- `Normalize-AndroidShellText` now removes CR and converts CRLF to LF. Every `Invoke-Root` payload and the direct holder-launch payload passes through it.
- The exact CRLF-affected payload was the multiline native entry/state probe. The holder payload was single-line but is now explicitly protected too.
- Native Windows PowerShell 5.1 results: parser PASS, automatic-variable audit PASS, LF normalization PASS, Android payload CR count 0, holder/qcrild2/SIM command builds PASS, static no-ADB PASS.
- State-machine order and all safety limits are unchanged. ADB was not invoked during this repair; phone writes 0.

Unique next action: stop and wait for explicit approval before any third device launch.

## v2.7-alpha third device launch

- Tested exact commit `e279af23770c7fd37562f3589095429380dd44eb` once under Windows PowerShell `5.1.19041.6456`.
- Fresh device/native checks passed: `fd0ff892`, root, airplane mode 1, per_mgr running, pm-service PID 31818 sole FD9 owner, X55 ONLINE, crash_count 0, no holder, qcrild2 PID 873, VOXI/UICC active/enabled; initial WFC F1.
- The launcher stopped before any phone write because the fixed single-SIM helper JAR was absent from its git-ignored build path. The script rejected it at `Assert-LocalArtifact`, before logcat startup, stop-per_mgr, holder, qcrild2, or SIM stages.
- Classification: `BLOCKED_PRE_WRITE_MISSING_AUDITED_SINGLE_SIM_HELPER`; recovery/native-handoff NOT_RUN, final WFC NOT_CHECKED, phone writes 0.
- Fresh post-check remained native-clean and unchanged: pm-service PID 31818 sole FD9 owner, X55 ONLINE, crash_count 0, qcrild2 PID 873, no holder, WFC F1.
- Full report: `experiments/x55_native_handoff/v2.7-alpha-native-handoff/THIRD_DEVICE_RUN_RESULT.md`.

Unique next action: rebuild and hash-verify the exact helper and repair the host packaging/preflight path statically. Do not rerun the device experiment without explicit approval.

## v2.7-alpha fourth device launch

- Tested exact commit `12e59b9b78589657f3f62938b957ba73ff9ee183` once under Windows PowerShell `5.1.19041.6456`.
- Fresh external entry gate passed; initial native scene was pm-service PID 31818 sole FD9 owner, X55 ONLINE, crash_count 0, no holder, qcrild2 PID 873, VOXI/UICC active/enabled, WFC F1.
- The paired launcher stopped before any phone write because `Get-FileHash` was not resolved at the local `Assert-LocalArtifact` gate.
- Classification: `BLOCKED_PRE_WRITE_PS51_FILEHASH_RESOLUTION`; recovery/native-handoff NOT_RUN, final WFC NOT_CHECKED, phone writes 0.
- Post-check remained native-clean and unchanged. Full report: `experiments/x55_native_handoff/v2.7-alpha-native-handoff/FOURTH_DEVICE_RUN_RESULT.md`.

The fourth-launch blocker was repaired and host-validated before the fifth run: the exact paired launcher ran its no-ADB selftest under Windows PowerShell `5.1.19041.6456`, invoked production `Assert-LocalArtifact`, and passed the fixed helper hash gate using the internal .NET SHA-256 engine. The main script has zero `Get-FileHash` dependencies. The later fifth-run result is recorded below.

## Computer A legacy recovery checkpoint

- Exact v2.6.2 PS1/CMD source is now preserved under `archive/computer_a_legacy/x55_wfc_oneclick/v2.6.2/` with SHA-256 provenance.
- PassiveMonitor v1.2 is canonical under `tools/x55_voxi_passive_monitor/`; original logic is unchanged.
- StateSearcher v3.0-v3.5 and launchers are preserved; v3.5 is only the latest historical timing sweeper, not a proven recovery.
- The SSR read-only topology audit source and small captures are under `tools/voxi_modem_ssr_readonly_audit_v3/`.
- The two unique source-less kernel modules are isolated under `archive/computer_a_legacy/unique_binaries/` as historical binaries with explicit do-not-load warnings.
- Large raw evidence and other binaries remain host-only and hash-indexed in `docs/COMPUTER_A_RAW_EVIDENCE_MANIFEST.csv`.
- No ADB or phone operation occurred during recovery.

Read `docs/COMPUTER_A_LEGACY_RECOVERY_20260924.md` before claiming that a historical source artifact is still missing.

## v2.7-alpha fifth device launch

- Exact commit `13d2969acbfe6e43171929583f40b18ed4ceb361` was executed once after fresh entry gate and paired PS5.1 selftest PASS.
- per_mgr stop, holder rebirth, X55 ONLINE, and new PON_SUCCESS succeeded. Android holder PID 22129 was initially sole owner.
- Starting per_mgr under contention created pm-service PID 22536, which acquired `/dev/subsys_esoc0` while holder 22129 still owned it. The script correctly stopped with `NATIVE_HANDOFF_RESULT=BEHAVIOR_CHANGED` before qcrild2 restart and before any SIM cycle.
- Fail-safe TERM was not sent because the holder identity predicate requires unique ownership. Current preserved scene: per_mgr running; holder 22129 plus pm-service 22536 dual owners; X55 ONLINE; crash_count 0; qcrild2 unchanged PID 873; WFC F1; SIM OFF/ON 0/0.
- `PerMgrSrv` directly logged QCRIL registration and voting, but the full four-line bilateral evidence gate remains `UNPROVEN`.
- Full result: `experiments/x55_native_handoff/v2.7-alpha-native-handoff/FIFTH_DEVICE_RUN_RESULT.md`.

At the fifth-run checkpoint, the holder/native scene was intentionally preserved pending separate cleanup authorization. Cleanup 006 below supersedes that live scene.

## Dual-owner cleanup 006

- Fresh identity checks matched the fifth-run holder PID 22129, exact cmdline, PID file, and FD9 target.
- Exactly one TERM was sent. No retry, SIGKILL, restart, SIM action, or other recovery write occurred.
- Holder 22129 exited and its PID file disappeared. pm-service PID 22536 became sole `/dev/subsys_esoc0` owner; per_mgr remained running; X55 remained ONLINE; crash_count remained 0; qcrild2 remained PID 873.
- WFC remained F1 with qti.cne/ePDG/XFRM absent.
- Result: `MAKE_BEFORE_BREAK_NATIVE_HANDOFF_SUCCESS`. Full report: `experiments/x55_native_handoff/X55_DUAL_OWNER_CLEANUP_006.md`.

The live holder scene is now clean. Do not rerun v2.7-alpha without explicit authorization; next work is static redesign/audit of the dual-owner contention and exact-holder cleanup gates.
