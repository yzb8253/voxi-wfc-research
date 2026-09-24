# Project Goal

Develop a repeatable, fail-safe VOXI WFC recovery for Xiaomi 10/cas with Qualcomm SDX55M, with GitHub as the durable evidence source.

# Device / Environment

Windows; Xiaomi 10 (`cas`), Android 13, Magisk; SDX55M. VOXI uses physical slot2 / Android slot index 1 and phoneId 1, commonly subId 11, MCCMNC 23415, carrierId 28. Rediscover ADB serials and PIDs.

# Verified Architecture

Peripheral Manager uses Binder `vendor.qcom.PeripheralManager` / `vendor.qcom.IPeripheralManager`; `vendor.per_mgr` runs `/vendor/bin/pm-service`; `vendor.per_proxy` runs `/vendor/bin/pm-proxy`; external-modem node is `/dev/subsys_esoc0`. `libperipheral_client.so` exports client register, connect, disconnect, unregister, and event acknowledgement. Known loaders include pm-service, pm-proxy, qcrild/qcrild2, GNSS, CNSS, and xtra-daemon.

# Verified Recovery Path

Transferred experiments establish: stop per_mgr -> X55 OFFLINE -> holder opens `/dev/subsys_esoc0` -> X55 ONLINE/new PON_SUCCESS -> one fixed SIM2 OFF, 3-second wait, ON -> WFC HEALTHY. It succeeded in at least two key runs. Exact v2.6.2 host source is now imported; historical raw-log completeness remains unresolved.

# Verified Peripheral Manager Behavior

In clean native state without a holder, pm-service held the node (typically FD9) and X55 was ONLINE. After per_mgr stop/start, new pm-service PID 13288 reacquired it before qcrild2 restart; X55 was ONLINE. Ownership is not boot-only.

# QCRIL / Peripheral Manager Relationship

Primary RIL is `/vendor/bin/hw/qcrild`; fixed-slot2 RIL is `/vendor/bin/hw/qcrild -c 2`. Transferred logs showed:

```text
PerMgrSrv: SDX55M state: is on-line, add client QCRIL
PerMgrSrv: QCRIL registered
PerMgrLib: QCRIL successfully registered for SDX55M
PerMgrLib: QCRIL voting for SDX55M
PerMgrSrv: QCRIL voting for SDX55M
PerMgrSrv: SDX55M num voters is 2
```

Thus `qcrild2 -> libperipheral_client -> register -> connect/vote -> Peripheral Manager` is verified behavior.

# X55 State Model

- Clean native: pm-service owner, no holder, X55 ONLINE.
- Rebirth: native owner removed, X55 OFFLINE, holder opens node, X55 ONLINE/PON_SUCCESS.
- Contended cleanup: holder owns node while pm-service starts; pm-service cannot acquire.
- Desired handoff: holder exits, owner briefly empty, native client vote prompts pm-service acquisition.

# WFC Recovery Results

X55 rebirth plus one fixed SIM2 cycle restored WFC HEALTHY. qcrild2 restart can cause transient RADIO_NOT_AVAILABLE and DSD/IMS reconstruction. WFC is not an ownership-test success criterion.

# Native Ownership Findings

Clean stop/start reacquisition is verified by transferred evidence. Holder-contended reacquisition is unresolved. Automatic retry after holder release is unknown; a fresh qcrild2 QCRIL vote is the leading trigger hypothesis.

# Current Open Questions

1. Does pm-service automatically reacquire after holder exit?
2. If not, does one qcrild2 restart/vote cause it?
3. Can a smaller official client action trigger the vote?

# Current Best Hypothesis

Starting pm-service while a holder owns the node misses acquisition. After release, a new fixed-slot2 QCRIL vote may cause retry. This remains a hypothesis.

# Latest Ownership Experiment

`X55-OWNERSHIP-HANDOFF-001` passed its direct entry gate and proved that correctly quoted root reads can observe the native owner, X55 state, and crash count under enforcing SELinux. The run stopped before holder-plus-pm-service contention because a PowerShell parameter named `$Pid` collided with the automatic `$PID` variable.

The holder-alone phase succeeded: holder PID 31163 was the sole `/dev/subsys_esoc0` owner and X55 was ONLINE with crash_count 0. Fail-safe cleanup removed the holder and restarted per_mgr, but the final preserved scene is pm-service PID 31818 running with no node owner, X55 OFFLINE, crash_count 0, and qcrild2 unchanged at PID 13706. No qcrild2 re-vote occurred, so the handoff hypothesis remains untested.

# Next Experiments

001B is complete. No additional recovery or process action is automatically authorized; obtain a new explicit decision.

# Safety Constraints

GitHub only; no guessed PID/raw transaction/unverified holder/SELinux bypass; no SIM cycle in this test, physical SIM action, radio/modem reset, unrelated restart ladder, or environment toggle. Every write needs PRE/POST evidence and fail-safe cleanup.

# Follow-up 001B

From the preserved no-owner/X55-OFFLINE scene, the read-only entry gate passed and exactly one fixed-slot2 qcrild2 restart changed PID 13706 to 873. pm-service PID 31818 then became sole FD9 owner and X55 became ONLINE with crash_count 0.

The complete 15-second logcat captured qcrild2/RIL initialization but none of the four required PerMgrLib/PerMgrSrv QCRIL register/vote messages. Therefore native reacquisition is device-confirmed, while the proposed QCRIL re-vote mechanism is not log-confirmed. The predefined result is `QCRILD2_RESTART_NO_VALID_REVOTE`.


# v2.7-alpha Engineering State

001B proved the externally observable native reacquisition result: after one fixed-slot2 qcrild2 restart, the existing pm-service acquired /dev/subsys_esoc0 and X55 returned ONLINE with crash_count 0. The exact QCRIL re-vote mechanism was not directly logged and remains unproven.

A new, non-replacing v2.7-alpha implementation now orders recovery as native owner -> controlled holder rebirth -> start per_mgr under contention -> release holder -> one qcrild2 restart -> native reacquire -> WFC check -> optional one fixed SIM2 cycle. Native reacquire failure forbids SIM power. Healthy WFC skips SIM power. No retry exists.

Build status: PowerShell syntax PASS, Android shell syntax PASS, static safety audit PASS, phone execution NOT RUN, phone writes 0.

The first authorized device launch was attempted from Computer B at commit `1949b6f90572e2b7eee60963cab8b18fc6b07591`. The independent read-only entry gate passed, but the paired `.cmd` launcher selected Windows PowerShell 5.1 and the script failed before its first ADB call because `ProcessStartInfo.ArgumentList` is unavailable in that runtime.

Result: `BLOCKED_PRE_WRITE_PS51_INCOMPATIBILITY`; phone writes 0. No holder, ownership transition, qcrild2 restart, or SIM cycle occurred. Post-check state remained pm-service PID 31818 sole FD9 owner, qcrild2 PID 873, X55 ONLINE, crash_count 0, and WFC F1.

Windows PowerShell 5.1 compatibility is now statically repaired and accepted: version 5.1.19041.6456, parser errors 0, exact launcher self-test PASS, Windows argv/holder payload round-trip PASS, and full static safety audit PASS. The phone state machine and safety logic are unchanged; phone writes during the repair were 0.

Next action: stop and obtain fresh authorization before another real execution. Do not treat the failed host launch as a native-handoff result and do not automatically rerun the repaired script.

## v2.7-alpha Second Authorized Launch

The exact repaired commit `cd222ea058dbb1f2b88905b99987885f3a9438ce` was tested once on Computer B with Windows PowerShell 5.1.19041.6456. The fresh independent read-only gate passed and the phone began in native-clean F1: pm-service PID 31818 sole FD9 owner, qcrild2 PID 873, X55 ONLINE, crash_count 0, no holder, VOXI active/enabled.

The script stopped before its internal entry gate and before any write. `Resolve-ExactProcess` used `$matches`, which is the case-insensitive automatic `$Matches` variable. Its `-match` condition converted the variable to a hashtable, and `$matches += $item` raised `A hash table can only be added to another hash table.` The saved entry artifact also showed CRLF characters from a PowerShell here-string reaching Android `sh`, invalidating commands such as `id` and `2>&1`.

Result: `BLOCKED_PRE_WRITE_HOST_SCRIPT_COMPATIBILITY`; recovery and native handoff NOT_RUN, final WFC NOT_CHECKED, SIM OFF/ON 0/0, phone writes 0. A fresh read-only post-check confirmed the same native owner, X55, crash count, qcrild2 PID, absent holder, and F1 state. No retry or recovery action was performed.

Both host defects are now statically repaired. The process collection no longer collides with automatic `$Matches`; a central LF normalizer covers all `Invoke-Root` payloads and the direct holder launch. Windows PowerShell 5.1 parser, automatic-variable, payload-CR, command-construction, argv, holder, fail-safe, and unchanged-state-machine checks pass. `ANDROID_PAYLOAD_CR_COUNT=0`, `STATIC_NO_ADB=PASS`, and phone writes during repair are 0.

Next action: stop. Any third real execution requires new explicit approval.

## v2.7-alpha Third Authorized Launch

The exact commit `e279af23770c7fd37562f3589095429380dd44eb` was launched once after a fresh device/native gate passed. It stopped at the local artifact gate because `experiments/sim_soft_reset/single_sim_isolation/build/single-sim-slot1-power-helper.jar` was absent. The JAR is ignored by the repository's `*.jar` rule.

No state-machine write occurred: per_mgr was not stopped, no holder was created, qcrild2 was not restarted, and no SIM cycle ran. Result: `BLOCKED_PRE_WRITE_MISSING_AUDITED_SINGLE_SIM_HELPER`; recovery/native-handoff NOT_RUN, final WFC NOT_CHECKED, SIM OFF/ON 0/0, phone writes 0.

Post-check remained pm-service PID 31818 sole FD9 owner, X55 ONLINE, crash_count 0, qcrild2 PID 873, holder absent, and WFC F1.

Next action: static helper rebuild/hash verification and packaging/preflight correction only. Another device execution requires new explicit approval.

## v2.7-alpha Fourth Authorized Launch

Commit `12e59b9b78589657f3f62938b957ba73ff9ee183` contained the exact tracked helper, and the fresh external device/native gate passed. The exact launcher nevertheless stopped pre-write because Windows PowerShell 5.1 did not resolve `Get-FileHash` inside `Assert-LocalArtifact`.

Result: `BLOCKED_PRE_WRITE_PS51_FILEHASH_RESOLUTION`; per_mgr/holder/qcrild2/SIM state machine NOT_RUN, SIM OFF/ON 0/0, phone writes 0. Post-state remained pm-service PID 31818 sole owner, X55 ONLINE, crash_count 0, qcrild2 PID 873, holder absent, and WFC F1.

Historical next action was to repair the hash implementation and extend exact-launcher host-only coverage through the real artifact gate; the host-side resolution is recorded below. Another device run still requires new explicit approval.

## v2.7-alpha PS5.1 Hash Blocker Resolution

The exact paired launcher no-ADB selftest now passes under Windows PowerShell `5.1.19041.6456`. Production `Assert-LocalArtifact` and orchestrator hashing share an internal .NET `SHA256` implementation; the helper hash matched `90D6F55FBE1F941C1E3EEE1AA1F93B569FA3AE4084B93C5560082A38AAAF5C39`, the known `abc` vector passed, and the main script contains zero `Get-FileHash` dependencies.

This resolved `BLOCKED_PRE_WRITE_PS51_FILEHASH_RESOLUTION` at the host/runtime level. At that checkpoint the phone had not been rerun; the later fifth authorized launch is recorded below.

## Single-SIM Helper Packaging Resolution

Computer A supplied the exact previously audited helper at `experiments/sim_soft_reset/single_sim_isolation/build/single-sim-slot1-power-helper.jar`. It is 11534 bytes and hashes to `90D6F55FBE1F941C1E3EEE1AA1F93B569FA3AE4084B93C5560082A38AAAF5C39`, exactly matching v2.7-alpha's fixed safety gate.

The repository's global `*.jar` ignore remains unchanged. This one exact artifact is force-tracked so a fresh checkout has the required fixed single-SIM slot1 helper. This resolves the packaging blocker only; it does not authorize or perform another device run. ADB was not used and phone writes were 0.

## Computer A Legacy Recovery

On 2026-09-24, 465 Computer A candidates under `D:\` were hashed and classified. Exact v2.6.2 source, PassiveMonitor v1.0-v1.2, StateSearcher v3.0-v3.5, the SSR read-only topology audit, selected compact negative-result histories, and historical source variants were preserved without changing original bytes.

Large raw evidence (353 files, 416795027 bytes), system/vendor binaries, and ZIP containers remain host-only and hash-indexed. The two unique source-less kernel modules are now isolated under `archive/computer_a_legacy/unique_binaries/` as historical do-not-load artifacts. The comprehensive report is `docs/COMPUTER_A_LEGACY_RECOVERY_20260924.md`.

## v2.7-alpha Fifth Authorized Launch

Commit `13d2969acbfe6e43171929583f40b18ed4ceb361` passed the fresh device gate and exact paired PS5.1 selftest, then ran once. X55 controlled rebirth succeeded, with Android holder PID 22129 becoming sole owner and producing a new PON_SUCCESS.

When per_mgr restarted under contention, pm-service PID 22536 also acquired `/dev/subsys_esoc0`; the resulting dual-owner state violated the expected holder-only gate. The script stopped as `BEHAVIOR_CHANGED` before holder release, qcrild2 restart, deployment, or SIM cycle. Fail-safe TERM was refused by the unique-owner identity check.

At the fifth-run abort checkpoint, per_mgr was running; holder 22129 and pm-service 22536 both owned the device; X55 was ONLINE; crash_count was 0; qcrild2 remained PID 873; VOXI remained active/enabled in F1; SIM OFF/ON was 0/0. Cleanup 006 below supersedes that preserved live scene.

## Dual-Owner Cleanup 006

Fresh identity checks proved that PID 22129 was the exact fifth-run holder and that FD9 still targeted `/dev/subsys_esoc0`. One authorized TERM was sent. The holder exited, its PID file was removed by the EXIT trap, and pm-service PID 22536 naturally became the sole native owner while X55 remained ONLINE and crash_count remained 0. qcrild2 stayed at PID 873; no service restart or SIM action occurred.

Result: `MAKE_BEFORE_BREAK_NATIVE_HANDOFF_SUCCESS`. WFC remained F1, so this validates native ownership handoff only, not WFC recovery. Current native state is clean: per_mgr running, pm-service sole owner, holder absent, X55 ONLINE, crash_count 0.

## v2.7-alpha Make-Before-Break Static Redesign

The production path now models the experimentally observed sequence directly: native pm-service sole owner -> stop per_mgr -> exact holder sole owner/X55 rebirth -> start per_mgr -> exact holder+pm-service dual ownership -> TERM only the exact Android holder -> pm-service sole owner with X55 still ONLINE -> WFC check -> at most one optional SIM cycle.

Holder identity is independent of the Windows-side ADB process and requires the exact PID file value, live Android PID, exact shell command, and FD9 target. The dual-owner gate accepts exactly those two verified processes and rejects unknown third owners. The old qcrild2 restart has been removed from the production path; its PID must remain unchanged. PS5.1 parse, paired no-ADB selftest, A-G ownership models, artifact gate, and static audit all pass. No phone was accessed or modified.

This redesign is supported by 005 and cleanup 006 for native ownership mechanics only. It has not yet proven final WFC recovery.

## v2.7-alpha Make-Before-Break Device Run 007

Exact commit `9ccf2eeeac9b4f14b5b662e4a8b076a1552695d4` passed the fresh entry gate and paired PS5.1 selftest. The production path reached holder sole ownership, X55 rebirth, a new PON_SUCCESS, and exact holder+pm-service dual ownership.

One exact-holder TERM was sent, but holder PID 27125 did not exit within 10 seconds. The script stopped before pm-service-sole validation, WFC check, deployment, or SIM cycle. Immediate read-only state preserved holder 27125 plus pm-service 28220 as dual owners, X55 ONLINE, crash_count 0, qcrild2 PID 873 unchanged, and WFC F1. The holder had a live `sleep 60` child, supporting a deferred shell-trap timeout explanation.

Result: `HOLDER_TERM_DEFERRED_TIMEOUT / PRESERVED_DUAL_OWNER`; SIM OFF/ON 0/0. Do not claim native handoff or WFC recovery success.


## v2.7-alpha Eighth Device Run

Exact commit `81b5de257941f7bad9183cc4e9ec7b241de7b63e` completed the redesigned native handoff end to end: holder rebirth, exact dual ownership, exact holder TERM, pm-service sole ownership, X55 ONLINE/crash_count 0, and native cleanup all passed with qcrild2 unchanged. Exactly one software SIM OFF/ON cycle then completed successfully at the helper/API level, but WFC remained F1 through the bounded observation window.

Result: `RECOVERY_RESULT=X55_REBIRTH_SUCCESS`, `NATIVE_HANDOFF_RESULT=MAKE_BEFORE_BREAK_NATIVE_HANDOFF_SUCCESS`, `FINAL_WFC_RESULT=FAILED_AFTER_ONE_SIM_CYCLE`, `CLEANUP_RESULT=NATIVE_CLEAN`.

The remaining active hypothesis is ordering. Successful historical v2.5/v2.6.2 recovery performed the SIM cycle while the fresh X55 remained held by the temporary holder with vendor.per_mgr stopped. Run 008 restored native pm-service ownership before the SIM cycle.

## Recovery-Before-Cleanup Source Redesign

The production path is now reordered so recovery is attempted before native cleanup:

`native entry -> stop per_mgr -> holder sole -> X55 rebirth/new PON_SUCCESS -> WFC check -> at most one SIM cycle while holder sole/per_mgr stopped -> make-before-break native cleanup -> post-cleanup WFC check`.

Native cleanup mechanics remain the already validated 005/006 model. qcrild2 restart count remains zero. The script now emits `PRE_CLEANUP_WFC_RESULT` to distinguish pre-cleanup recovery from WFC loss after cleanup. This source change has not yet been phone-executed; the exact paired PS5.1 selftest must pass first.

## WFC Repeatability / Canonical-State Run 2026-09-24

A new-boot A0 and first-airplane P0 were captured with one uniform collector. P0 differed from A0 only in the expected airplane/Wi-Fi enumeration and IWLAN transport-preference fields; VOXI identity, active/enabled subscription, QCRIL processes, native pm-service ownership, and X55 ONLINE/crash-count state matched.

The unchanged archived `v2.5-single-on` source then completed X55 rebirth/new PON_SUCCESS and exactly one fixed slot1 SIM cycle, but produced no qti.cne IMS request and no WFC. Its historical one-time vendor.cnd fallback also produced no request. IMS remained NOT_REGISTERED/UNKNOWN and the run stopped before W0, A1, P1, or W1. No residue normalization or second recovery was attempted. See `experiments/wfc_repeatability_normalization/RUN_20260924_RESULT.md`.

This run does not test post-success residue because it never reached a success state. It shows that a fresh reboot and A0-equivalent first P0 were not sufficient for this historical source on this attempt.

Correction: that attempt used the wrong v2.5 source and is now classified `WRONG_RECOVERY_SEQUENCE_CND_FALLBACK`. It must not be used to judge the verified v2.6.2 path.

## v2.6.2 Freeze-on-Success Two-Cycle Validation

The corrected experiment used `X55-WFC-OneClick-v2.6.2-native-owner-restore.ps1` as the sole recovery basis and changed only its post-success cleanup branch. Both W0 and W1 reached direct WFC health about 11 seconds after one SIM cycle. Each success froze per_mgr stopped, an exact holder as sole esoc0 owner, and X55 ONLINE/crash count 0. No post-success cleanup, CND fallback, or extra SIM cycle ran.

After W0, airplane OFF exposed the expected native residue. Starting and then restarting per_mgr while the holder remained active did not produce native takeover. A strict fallback TERM'd only the exact holder, required owner NONE/X55 OFFLINE/crash 0, then restarted qcrild2 once. qcrild2 changed 1994 -> 27223; pm-service 23598 reacquired esoc0; X55 returned ONLINE/crash 0; primary qcrild was unchanged. The resulting A1 was A0-equivalent on critical fields. P1 was P0-equivalent, and the same recovery produced W1 equivalent to W0.

The previous qti.cne active flag was also corrected: the old probe treated Connectivity request-history entries as current. The uniform collector now parses only the current request table and keeps the old result as `qtiCneProbeReported`.

Full report: `experiments/wfc_repeatability_normalization/runs/v262_freeze_run/RESULT.md`.
