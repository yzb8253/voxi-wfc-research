# VOXI WFC Machine Handoff

## Purpose

This file is the durable cross-computer resume contract for the VOXI WFC project.

When the user changes computers, Codex should not ask them to reconstruct Git state, rerun completed experiments, or remember an old wireless ADB endpoint. Sync from GitHub, verify the current device, read the latest checkpoints, and continue from the recorded next action.

## Repository

- Repository: `yzb8253/voxi-wfc-research`
- Working branch: `voxi-wfc-auto-recovery`
- Remote: `origin`
- Remote branch HEAD is authoritative.

## New-computer bootstrap

If the repository already exists:

```powershell
git fetch origin
git checkout voxi-wfc-auto-recovery
git pull --ff-only origin voxi-wfc-auto-recovery
git rev-parse HEAD
git rev-parse origin/voxi-wfc-auto-recovery
```

The two commit IDs must match before continuing.

If the local repository is absent, clone the repository first, then switch to `voxi-wfc-auto-recovery`.

After sync:

1. Read `AGENTS.md`.
2. Read `autopilot/AUTOPILOT_STATE.md`.
3. Read `autopilot/AUTOPILOT_FINDINGS.md`.
4. Read this file.
5. Run `adb devices` and resolve the current device endpoint.
6. Confirm the Xiaomi target and root access.
7. Continue from the latest `NEXT_ACTION`.

Never reuse a previous computer's wireless ADB IP:port without resolving it again.

## Automatic Git checkpointing

After each meaningful completed unit of work:

- update the state/finding/handoff summaries;
- stage source, scripts, plans, sanitized reports, audits, and other non-sensitive project artifacts;
- commit;
- push to `origin/voxi-wfc-auto-recovery`;
- verify the remote commit;
- leave the worktree clean when practical.

Do not upload raw run captures or telephony dumps containing subscriber identifiers. Do not upload secrets, tokens, ICCID, IMSI, MSISDN, or similarly sensitive artifacts. Summarize/sanitize them first.

If a push cannot be completed, record the exact blocker instead of reporting success.

## User-facing handoff convention

The user's intended workflow is:

1. They paste the last Codex output when useful.
2. They say “换电脑了” / “I changed computers”.
3. Codex automatically performs Git sync, state recovery, ADB rediscovery, identity/root checks, and resumes from the latest checkpoint.
4. The user should not need to type Git synchronization commands manually.

## Current checkpoint

- Date: 2026-09-20, single-SIM full userspace rebuild complete.
- A fixed, audited executor sent one TERM each to imsdatadaemon, imsqmidaemon, cnd, qtidataservices, and Qualcomm IMS in that order. Every target acquired a new stable PID and ImsService rebound.
- qcrild, qcrild2, netmgrd, phone, and system_server remained at their protected PIDs. No SIM-power, radio, modem, resetIms, airplane, or reboot action occurred.
- Final state is ACTIVE + ENABLED + F1 with no native IMS demand, qti.cne/TNF/DNC IMS request, ePDG/XFRM, IMS registration, or WFC.
- cnd reconstruction cleared residual IWLAN/HOME; final PS/WLAN is UNKNOWN and IWLAN preferred is false.
- slot0 remains ABSENT; wlan0 and tun0 remain up.
- Sanitized report: `experiments/sim_soft_reset/single_sim_isolation/full_userspace_rebuild/SINGLE_SIM_FULL_USERSPACE_REBUILD_RESULT.md`.

NEXT_ACTION: stop. Do not repeat this sequence or append phone/system_server/RIL/modem/SIM-power/resetIms actions. A new below-boundary hypothesis requires explicit authorization and separate safety review.

## Earlier checkpoint: computer-B recovery

- Date: 2026-09-20, computer-B read-only recovery.
- USB ADB currently resolves one target: `fd0ff892`, Xiaomi 14 Pro, Magisk UID 0.
- VOXI remains subId11/slot1/phoneId1/carrierId28/MCCMNC23415, ACTIVE and UICC enabled.
- China SIM slot0 is ABSENT; the two-slot SIM-state property is `ABSENT,LOADED`.
- Current health is F1: IMS NOT_REGISTERED/UNKNOWN, VOICE-IWLAN unavailable, WFC unavailable; no qti.cne IMS request or ePDG tunnel.
- single-SIM helper source and reports are present; static audit passes. `device/*.sh` is now pinned to LF to make Windows checkouts safe.
- No device write was executed during this handoff.

NEXT_ACTION: preserve F1. Do not execute the single-SIM cycle merely because the computer changed; the latest completed experiment boundary still applies.

## Current checkpoint: QCRIL setDataProfile race confirmation

- Date: 2026-09-20.
- Read-only analysis of the successful physical-insert lifecycle is complete.
- Both insertions sent the same IMS-bearing profile array and received successful `SET_DATA_PROFILE` responses.
- The successful `IMS -> IWLAN` QNS callback occurred 341 ms before the second insertion's first new `SET_DATA_PROFILE`; the proposed second-dispatch race is not confirmed and is materially weakened.
- Earliest concrete divergence: DSD/QNS qualified-network indication or cache synchronization after IWLAN/HOME.
- No device write or recovery action occurred.
- Sanitized report: `experiments/sim_soft_reset/single_sim_isolation/QCRIL_SETDATAPROFILE_RACE_CONFIRMATION.md`.

NEXT_ACTION: no write. If continuing this hypothesis, first statically audit a fixed-slot1 `IIWlan.getAllQualifiedNetworks(serial)` read-semantics cache query. Treat it only as a cache/callback discriminator, not as a QMI or modem refresh.

## Current checkpoint: QCRIL IIWLAN cache snapshot

- Date: 2026-09-20.
- Fixed target remained VOXI slot1/phoneId1/subId11; slot0 remains absent.
- Static audit passed: `getAllQualifiedNetworks` is a cache read, but a second client cannot privately capture its result without callback ownership concerns.
- No helper was uploaded and no HIDL response callback was registered or replaced. `getAllQualifiedNetworks` was not executed.
- One read-only `lshal debug vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot2` call exposed the built-in native cache dump.
- Current IMS APN is present with `networks=[]`; DEFAULT and EIMS are also present with empty lists. Native global preference is IWLAN and DSD/WDS/IWLAN readiness is true.
- Framework remains IWLAN-preferred, but IMS is NOT_REGISTERED and WFC unavailable. Verdict: `NATIVE_QNS_CACHE=STALE`.
- Phone writes: 0.
- Sanitized report: `experiments/sim_soft_reset/single_sim_isolation/QCRIL_IIWLAN_CACHE_SNAPSHOT.md`.

NEXT_ACTION: continue only with read-only/static DSD indication-to-cache analysis. Do not replay setDataProfile, replace IIWlan callbacks, or invoke a refresh API.

## Current checkpoint: DSD/QNS golden-diff preparation

- Date: 2026-09-20.
- Current fixed-slot2 F1 BAD snapshot is complete: IMS, DEFAULT, and EIMS APNs exist but all native qualified-network vectors are empty.
- Static cache-writer analysis is complete. Global IWLAN preference does not populate an APN vector; per-APN DSD available-system or intent-to-change indications do.
- `convertResultList` skips empty/UNKNOWN vectors. Raw current DSD per-APN preferred/available values remain UNKNOWN because the dump does not expose them.
- New script: `experiments/sim_soft_reset/single_sim_isolation/dsd_qns_golden_diff/capture_qns_native_snapshot.ps1`.
- Script validation passed with 12/12 read-only sections. Captures are stored only under the ignored local `captures/` directory; no raw subscriber dump is committed.
- Phone writes: 0. No `getAllQualifiedNetworks`, `setResponseFunctions`, QMI request, SIM operation, restart, or recovery action occurred.

NEXT_ACTION: wait for the user to produce a real WFC Golden state. Then execute the same script once and field-diff the two ignored snapshots; do not change the capture command set between BAD and GOLDEN.

## Earlier checkpoint

- Date: 2026-09-20
- Branch: voxi-wfc-auto-recovery
- Device endpoint at last check: 192.168.1.106:41701; always rediscover after reconnect.
- Current kernel boot ID at last check: 8034952d-9ad8-4ccd-930a-c595cd7bcab4.
- The attempted Golden Boot baseline was rejected as a fresh-boot claim because kernel uptime was about 48 hours and telephony/framework PIDs were continuous with the prior run.
- Current state remains VOXI active/enabled F1; slot0 mapping is protected.
- Current-ROM restart-modem chain terminates in Radio HAL ResetNvType.RELOAD, not ERASE or FACTORY_RESET.
- The shell entry cannot execute on this production user build because TelephonyShellCommand requires UID0 and TelephonyUtils.IS_USER=false.
- No modem restart, direct Binder bypass, SIM power cycle, process kill, radio toggle, or AP reboot was executed in this phase.
- Sanitized report: experiments/sim_soft_reset/modem_only_restart/MODEM_ONLY_RECOVERY_RESULT.md.

NEXT_ACTION: preserve F1 and do not bypass the user-build shell gate. If a direct fixed-target ITelephony.rebootModem experiment is desired, obtain separate explicit authorization and repeat the complete dual-SIM/modem-wide risk review.

## Current checkpoint (2026-09-20T15:15:32+08:00)

- Branch: voxi-wfc-auto-recovery.
- Latest device endpoint: 192.168.1.106:41701; rediscover before use.
- Prepared and audited experiments/sim_soft_reset/L1_5_voxi_power_cycle/executor/stabilized_absent_second_reinsert/.
- No device write was used during preparation. Static audit and Android shell syntax checks pass.
- NEXT_ACTION: run the explicitly authorized bounded executor. Do not exceed two POWER_DOWN, two normal POWER_UP, one soft-stack rebuild, and never issue a third POWER_DOWN.

## Current checkpoint (2026-09-20 stabilized absent experiment complete)

- Branch: voxi-wfc-auto-recovery.
- Latest known online ADB alias: adb-fd0ff892-wZRh7k._adb-tls-connect._tcp; last discovered numeric endpoint was 192.168.1.106:41615. Always rediscover.
- Sanitized result: experiments/sim_soft_reset/L1_5_voxi_power_cycle/executor/stabilized_absent_second_reinsert/STABILIZED_ABSENT_SECOND_REINSERT_RESULT.md.
- Actual write accounting: two fixed slot1 POWER_DOWN callbacks, two fixed slot1 POWER_UP callbacks, one soft-stack rebuild, no third down.
- Final device state: VOXI ACTIVE + UICC ENABLED + IWLAN HOME + strict F1. China Telecom slot0 protected.
- NEXT_ACTION: stop. Do not repeat this experiment. New below-boundary work requires explicit authorization; otherwise use the known full reboot lifecycle for recovery.

## Current checkpoint: BAD vs GOLDEN DSD/QNS diff

- Date: 2026-09-20.
- The exact audited capture script was run once against a user-created real-WFC GOLDEN state; phone writes were 0.
- GOLDEN passed REGISTERED(2)/WLAN(2), VOICE-IWLAN and WFC availability, active qti.cne IMS request/NetworkAgent, UDP/4500, and XFRM.
- BAD hash: `31727FD5AAC506D429BB14DFD205280ED0B5A2D90BC411253A9982E1189B5687`; GOLDEN hash: `602E81EA342A7185BDA3000CCCDF406C77354878D17DD7BF253B28361E371CB6`.
- CASE B result: the current native IMS, DEFAULT, and EIMS vectors are `[]` in both states; `globalPrefSys=IWLAN`, `hasPendingIntent=false`, and empty `LastReportedNetworkAvailability` are also identical.
- GOLDEN internal history shows transient IMS qualification to `[IWLAN,UNKNOWN]`, but the current cache later returns empty without tearing down the established IMS path. The dump table is therefore not a durable active-network truth source.
- Sanitized report: `experiments/sim_soft_reset/single_sim_isolation/dsd_qns_golden_diff/BAD_VS_GOLDEN_NATIVE_DSD_QNS_DIFF.md`.

NEXT_ACTION: remain read-only. Candidate only: on a future real recovery, collect a synchronized lifecycle trace of native DSD/NAH update, ANM callback, CNE request, ePDG/XFRM, and IMS registration. Do not call a refresh/query/write interface.


## Current checkpoint: R/C/P airplane boundary

- Date: 2026-09-21.
- Branch baseline before this checkpoint: `50d2d63b48514cdb3e616dbd76d6a7c5983362ff`.
- USB ADB target for this run: `fd0ff892`; always rediscover on the next machine/session.
- The user manually performed airplane OFF and airplane ON. Codex executed read-only collection only; phone writes: 0.
- R was true WFC F0 with IMS REGISTERED/WLAN, VOICE-IWLAN/WFC available, qti.cne request 267, IMS NetworkAgent 102, UDP/4500, and XFRM.
- C released request 267 and changed the native IMS preferred report to EUTRAN.
- P restored IWLAN/HOME and `mIsIwlanPreferred=true`, but native IMS qualification was ordered `[UNKNOWN,IWLAN]`; no fresh IMS/IWLAN report, CNE IMS request, ePDG, or IMS registration appeared.
- The retained native last-reported IMS preference remained EUTRAN. DSD/WDS/IWLAN readiness flags remained true.
- Sanitized report: `experiments/sim_soft_reset/single_sim_isolation/dsd_qns_golden_diff/R_C_P_AIRPLANE_BOUNDARY.md`. Raw captures are ignored and must not be committed.

NEXT_ACTION: static analysis only. Find one fixed-slot2 lifecycle entry that recreates the QCRIL DataModule/IIWlan NetworkAvailabilityHandler modem-facing DSD AP-assist indication session. Do not execute a refresh, callback replacement, SIM/radio action, or process restart without separate authorization.

## Current checkpoint: minimum QCRIL reinit entry audit

- Date: 2026-09-21.
- Static-only audit completed; Codex phone writes: 0.
- `NetworkAvailabilityHandler` is owned by slot-local DataModule and recreated only by `initializeIWLAN()`; no standalone reset method exists.
- Fixed `IIWlan/slot2 setResponseFunctions` reaches `IWLANCapabilityHandshake(true)` and `initializeIWLAN()`, but does not fetch fresh DSD status.
- Minimum complete internal sequence identified: `sendAPAssistIWLANSupportedSync`, `registerForSystemStatusSync`, `initializeIWLAN`, `generateDsdSystemStatusInd`.
- Source reference revision: `36fc163a534963a5b3af52186af5efcc63401ad2`; current ROM symbol/runtime correspondence is strong, but current binary was not read after SELinux denied access.
- Modem-side DSD scope remains UNKNOWN because capability/registration QMI messages do not include a slot field.
- Sanitized report: `experiments/sim_soft_reset/single_sim_isolation/dsd_qns_golden_diff/MINIMUM_QCRIL_REINIT_ENTRY_AUDIT.md`.

NEXT_ACTION: no execution. Statically design a one-shot fixed-RIL-instance-1 internal diagnostic hook for exactly the four-step sequence, preserving slot0 gates and avoiding callback replacement by an external IIWlan client.

## Current checkpoint: one-shot QCRIL slot2 reinit preparation

- Date: 2026-09-21.
- USB ADB target during the read-only dry run: `fd0ff892`; rediscover on resume.
- Kernel boot ID during the dry run: `d5226877-9ac1-48b7-8ad3-2da783d6f6b0`.
- Fixed qcrild2 target verified: PID 1919 at capture time, `/vendor/bin/hw/qcrild -c 2`, PPID 1, UID radio, SELinux `u:r:rild:s0`.
- `/proc/1919/maps` and the current `libril-qc-hal-qmi.so` image are SELinux-protected. Module base, exact function addresses, current-ROM ABI, DataModule pointer, and DSD endpoint pointer remain unresolved.
- A safe call must be dispatched on the existing DataModule looper. No exported complete-sequence message or non-invasive handler-installation route was found.
- No hook was built or deployed. No ptrace/debugger/injection, second IIWlan callback registration, target call, process restart, or phone write occurred.
- Report: `experiments/sim_soft_reset/single_sim_isolation/dsd_qns_golden_diff/ONE_SHOT_QCRIL_SLOT2_REINIT_PREPARATION.md`.

NEXT_ACTION: STOP before execution. Do not guess offsets/pointers or attach an injector. Continue only with exact current-ROM binary/build-symbol access plus a statically verified DataModule-looper dispatch mechanism; otherwise retain `FAIL_SAFE`.


## Current checkpoint: QCRIL external reinit trigger audit

- Date: 2026-09-21.
- Static analysis only; phone writes: 0.
- Current-ROM inventories confirm `IQtiOemHook/oemhook0`, `oemhook1`, `IIWlan/slot1`, and `IIWlan/slot2`.
- `IIWlan.setResponseFunctions()` is a partial looper-safe path: it recreates NAH but does not generate fresh DSD status and would replace production callbacks.
- DSD endpoint recovery is the complementary partial path: it refreshes capability/registrations/status but does not recreate NAH in the post-SSR branch.
- OEM Hook/QcRilHook, legacy socket, QtiBus, DIAG, and property/init tables contain no complete reinit command.
- Verdict: `NO_EXISTING_EXTERNAL_TRIGGER`.
- Report: `experiments/sim_soft_reset/single_sim_isolation/dsd_qns_golden_diff/QCRIL_EXTERNAL_REINIT_TRIGGER_AUDIT.md`.

NEXT_ACTION: no device experiment. The single minimum alternative is a matching vendor-source build adding one fixed `IIWlan/slot2` diagnostic request that dispatches one dedicated message on the existing DataModule looper.

## Current checkpoint: QCRIL patch deployment feasibility

- Date: 2026-09-21; static-only audit; phone writes: 0.
- `IIWlan/slot2` inherited `IBase::debug()` is the narrow existing path. Correct implementation dispatches one fixed message on DataModule's looper with instance-1, slot2, boot-ID, atomic-one-shot, timeout, and no-retry guards.
- Current `libril-qc-hal-qmi.so` is a large AArch64 library loaded by both qcrild processes. Exact SONAME/build ID/dependencies/exports remain unavailable; no SELinux bypass was attempted.
- Source mirror `36fc163a534963a5b3af52186af5efcc63401ad2` is behaviorally close but is not the exact Xiaomi `V816.0.4.0.TJJCNXM` build tree.
- ABI-compatible replacement is not currently supportable. Magisk bind-mount is only mechanical, requires AP reboot, and is unsafe without a verified artifact.
- Report: `experiments/sim_soft_reset/single_sim_isolation/dsd_qns_golden_diff/QCRIL_PATCH_DEPLOYMENT_FEASIBILITY.md`.

NEXT_ACTION: STOP. Do not build, patch, mount, or deploy until exact matching vendor build artifacts can reproduce the library ABI.

## Current checkpoint: fixed-slot2 qcrild2 cold restart

- Date: 2026-09-21. USB ADB target during the run: `fd0ff892`; rediscover on resume.
- Precondition was P/F1 with VOXI active and UICC-enabled, native IMS `[UNKNOWN,IWLAN]`, and no CNE/ePDG/WFC.
- Exactly one `vendor.qcrild2` native init restart was executed. Target PID 1919 -> 855; primary qcrild remained PID 1879; boot ID unchanged.
- New DataModule initialization and NetworkAvailabilityHandler construction were observed. DSD/WDS/IWLAN readiness returned and the process stayed stable for 120 seconds.
- Fresh IMS qualified ordering remained `[UNKNOWN,IWLAN]`; it never became `[IWLAN,UNKNOWN]`. No IMS publication, qti.cne request, UDP/4500/XFRM, IMS registration, VOICE/IWLAN, or WFC followed.
- Final result: `CASE_C`, `P_TO_R=NO`. Slot0 remained physically absent/inactive; VOXI identity stayed stable. No modem reset or AP reboot occurred.
- Sanitized report: `experiments/sim_soft_reset/single_sim_isolation/dsd_qns_golden_diff/P_TO_R_QCRILD2_COLD_RESTART_RESULT.md`. Raw captures remain ignored and must not be committed.

NEXT_ACTION: STOP. Do not repeat this restart or run Magic SIM cycle automatically. Continue only from a separately authorized, evidence-based hypothesis outside qcrild2 process lifetime.

## Current checkpoint: X55 ownership handoff blocked before write

- Date: 2026-09-23; ADB serial during precheck: `fd0ff892` (rediscover on resume).
- Branch was synchronized at `b513bd627da0c4476fc18012c318248b2c4d1d8c` before this checkpoint.
- The user supplied a cross-account summary of v2.6.2 X55 rebirth and Peripheral Manager work, but the corresponding source/log/checkpoint does not exist in GitHub or on this computer.
- Live process scene: pm-service 13288, pm-proxy 1699, primary qcrild 1926, qcrild2 13706 (`-c 2`), mdm_helper 1297; no holder file found; VOXI identity active/enabled and correct.
- SELinux denied `/proc/13288/fd`, X55 sysfs state, and crash_count reads. The existing repository has no compatible ownership observer. Native owner, X55 ONLINE, and zero crash count therefore remain unverified.
- No phone write occurred. The holder/pm-service/qcrild2 handoff experiment is `NOT_RUN`.
- Sanitized report: `experiments/x55_native_handoff/OWNERSHIP_HANDOFF_PRECHECK.md`.

NEXT_ACTION: import the exact missing v2.6.2/X55 artifacts into the authoritative branch, audit the holder and observer, then re-run only the read-only entry gate. Never infer ownership from PID equality.

## Current checkpoint: X55 ownership handoff aborted before contention

- Date: 2026-09-23; branch baseline before this checkpoint: `56bd01aff49b79ba3bd751ad5939ce8d37c8a8e7`.
- Experiment ID: `X55-OWNERSHIP-HANDOFF-001`.
- Entry gate PASS: pm-service 13288 sole FD9 owner, X55 ONLINE, crash_count 0, no holder, qcrild2 13706.
- Holder-alone phase PASS: holder PID 31163 sole owner, X55 ONLINE, crash_count 0.
- Host probe aborted on a PowerShell `$Pid`/`$PID` collision before contended per_mgr start. Source is fixed but was not rerun.
- Fail-safe final state: per_mgr running PID 31818, owner NONE, X55 OFFLINE, crash_count 0, holder absent, qcrild2 unchanged PID 13706.
- qcrild2 restart/re-vote was NOT RUN. Result is `ABORTED_BEFORE_CONTENDED_PHASE / INCONCLUSIVE`; phone writes 5.
- Raw logcat remains outside Git. Sanitized report and selected logs are under `experiments/x55_native_handoff/`.

NEXT_ACTION: no automatic recovery or experiment. Preserve the current scene and wait for a new explicit user decision.

## Current checkpoint: X55 ownership follow-up 001B

- Entry gate PASS on preserved owner-NONE/X55-OFFLINE state.
- Exactly one qcrild2 restart: PID 13706 -> 873.
- Final native state: pm-service PID 31818 sole FD9 owner, X55 ONLINE, crash_count 0, holder absent.
- Required QCRIL register/vote messages were absent from complete logcat.
- Result: `QCRILD2_RESTART_NO_VALID_REVOTE`; phone writes 2; no additional recovery action.
- Sanitized report: `experiments/x55_native_handoff/X55_OWNERSHIP_HANDOFF_001B.md`. Raw logcat is host-only.

NEXT_ACTION: stop and wait for a new explicit decision.


## Current checkpoint: v2.7-alpha native-handoff ready for approval

- Date: 2026-09-23.
- Source directory: experiments/x55_native_handoff/v2.7-alpha-native-handoff/.
- v2.6.2 is preserved and was not modified.
- 001B classification: VERIFIED_NATIVE_REACQUIRE_AFTER_QCRILD2_RESTART; REVOTE_MECHANISM_LOG_UNPROVEN.
- New implementation is dry-run by default and requires EXECUTE-V2.7-ALPHA-NATIVE-HANDOFF for a real run.
- Native success requires holder absent, pm-service sole node owner, X55 ONLINE, crash_count 0, and changed qcrild2 PID. Vote logs are supporting evidence, not a hard gate.
- WFC healthy after native handoff skips SIM power. Otherwise exactly one audited fixed-slot1 cycle is available; no retry.
- Local PowerShell parse, Android shell parse, and static policy audit pass.
- No ADB/device action occurred in this checkpoint; phone writes 0.

NEXT_ACTION: sync the authoritative branch, review the v2.7-alpha audit, and wait for explicit user approval before any device run.

## Current checkpoint: v2.7-alpha host compatibility accepted after second blocked launch

- Date: 2026-09-23; Computer B; Account A.
- Second launch at `cd222ea058dbb1f2b88905b99987885f3a9438ce` stopped pre-write on a `$matches`/automatic `$Matches` collision; its native-state payload also carried Windows CRLF into Android `sh`.
- Classification: `BLOCKED_PRE_WRITE_HOST_SCRIPT_COMPATIBILITY`, not recovery failure. Phone writes 0; holder/process/SIM actions 0.
- Repair replaces the collection with `$resolvedProcesses` and normalizes all Android shell text to LF at the `Invoke-Root` boundary plus direct holder launch.
- Windows PowerShell 5.1 parser and host-only self-test pass; automatic-variable audit PASS; Android payload CR count 0; holder/qcrild2/SIM command builds PASS; state machine unchanged.
- No ADB command was issued during the repair and the third device experiment has not been run.

NEXT_ACTION: sync the authoritative branch and stop. Wait for explicit user approval before any third v2.7-alpha device launch.

## Current checkpoint: third v2.7-alpha launch blocked by missing helper

- Date: 2026-09-23 21:24; Computer B; Account A; tested commit `e279af23770c7fd37562f3589095429380dd44eb`.
- Fresh device/native gate passed; initial WFC F1; pm-service 31818 sole FD9 owner; X55 ONLINE; crash_count 0; qcrild2 873; holder absent.
- One launcher invocation stopped at `Assert-LocalArtifact` because the ignored single-SIM helper JAR was absent.
- Classification: `BLOCKED_PRE_WRITE_MISSING_AUDITED_SINGLE_SIM_HELPER`; recovery/native-handoff NOT_RUN; SIM OFF/ON 0/0; phone writes 0.
- Post-state remained native-clean and unchanged. Raw logs are host-only under `voxi_wfc_local_runs/v27_alpha_native_handoff_20260923_212413`.

NEXT_ACTION: rebuild and exact-hash verify the helper plus host-only packaging preflight. Do not run another device experiment without explicit approval.

## Current checkpoint: audited single-SIM helper is repository-tracked

- Date: 2026-09-23; Computer A.
- Path: `experiments/sim_soft_reset/single_sim_isolation/build/single-sim-slot1-power-helper.jar`.
- Size: 11534 bytes.
- SHA-256: `90D6F55FBE1F941C1E3EEE1AA1F93B569FA3AE4084B93C5560082A38AAAF5C39`.
- Provenance: existing audited artifact from Computer A, re-hashed before force-add.
- Global `*.jar` ignore remains unchanged; only this exact helper is tracked.
- Purpose: fixed single-SIM slot1 power helper used behind v2.7-alpha's fixed hash gate.
- No ADB command, phone write, or v2.7-alpha execution occurred.

NEXT_ACTION: sync the authoritative branch on other computers. A fresh device execution still requires explicit user approval.

## Current checkpoint: fourth v2.7-alpha launch blocked at PS5.1 hash command

- Date: 2026-09-23 21:48; Computer B; Account A; tested `12e59b9b78589657f3f62938b957ba73ff9ee183`.
- Fresh external gate passed; initial native state was pm-service 31818 sole FD9 owner, X55 ONLINE, crash_count 0, qcrild2 873, holder absent, WFC F1.
- One launcher invocation stopped pre-write because `Get-FileHash` was not resolved inside `Assert-LocalArtifact`.
- Result: `BLOCKED_PRE_WRITE_PS51_FILEHASH_RESOLUTION`; recovery/native-handoff NOT_RUN; SIM OFF/ON 0/0; phone writes 0.
- Post-state was unchanged. Raw logs remain host-only in `voxi_wfc_local_runs/v27_alpha_native_handoff_20260923_214813`.

NEXT_ACTION: exact-launcher PS5.1 hash repair plus no-ADB artifact assertion. Do not run another device experiment without explicit approval.

## Current checkpoint: Computer A legacy assets recovered

- Date: 2026-09-24.
- Report: `docs/COMPUTER_A_LEGACY_RECOVERY_20260924.md`.
- Full host-only disposition index: `docs/COMPUTER_A_RAW_EVIDENCE_MANIFEST.csv`.
- Imported provenance: `archive/computer_a_legacy/SOURCE_PROVENANCE.csv`.
- Exact v2.6.2 host source is now present; historical raw logs remain incomplete.
- PassiveMonitor v1.2 canonical path: `tools/x55_voxi_passive_monitor/`.
- StateSearcher v3.0-v3.5 and SSR read-only audit are preserved.
- D: originals were not changed; ADB not used; phone writes 0.

NEXT_ACTION: sync this checkpoint on other computers. Do not run any historical tool or phone experiment without separate explicit authorization.

## Current checkpoint: v2.7-alpha run 007 preserved dual-owner timeout

- Date: 2026-09-24 09:20; Computer A; Account A; exact commit tested `9ccf2eeeac9b4f14b5b662e4a8b076a1552695d4`.
- Fresh gate and paired PS5.1 selftest passed. Initial native state was pm-service 22536 sole owner, X55 ONLINE, crash_count 0, holder absent, qcrild2 873, single-SIM VOXI F1.
- Production reached holder 27125 sole owner, X55 rebirth/new PON_SUCCESS, and exact dual ownership with new pm-service 28220.
- One exact TERM was sent, but holder 27125 did not exit within 10 seconds. Its child `sleep 60` remained live. No retry, manual cleanup, qcrild2 restart, or SIM cycle occurred.
- Current preserved scene at last read: holder 27125 + pm-service 28220 dual owners; holder PID file present; per_mgr running; X55 ONLINE; crash_count 0; qcrild2 873 unchanged; WFC F1.
- Sanitized report: `experiments/x55_native_handoff/v2.7-alpha-native-handoff/SEVENTH_DEVICE_RUN_RESULT.md`. Raw logs remain host-only.

NEXT_ACTION: preserve the scene. Static-only holder-loop redesign is required before any separately authorized cleanup or rerun.
## Current checkpoint: W1/V1 recovery event diff

- Date: 2026-09-24; branch `experiment/v263-repeatable-state-machine`.
- Host-only evidence shows both runs reached ANM `ims -> [IWLAN]`, NRM IWLAN/HOME, and complete ImsResolver/MMTEL reconstruction.
- Failed V1 did not deliver the returned IWLAN/HOME result into slot-1 SST/DNC. Successful W1 did, then created qti.cne request 293 about 15.6 seconds after SIM ON returned.
- A/P canonical and v2.6.2 recovery were not changed. Historical log filtering prevents a definitive DSD/QNS/QIms internal claim.
- Report: `experiments/wfc_repeatability_normalization/runs/v263_state_machine_3cycle/W1_V1_RECOVERY_EVENT_DIFF.md`.

NEXT_ACTION: preserve the phone scene. Improve capture-only transition telemetry before deciding whether a pre-P canonical discriminator exists.

## Current checkpoint: deterministic reset-boundary analysis

- Date: 2026-09-24; Computer B; Account B; baseline `b3547a32c2a74b2eb60d943e5f006efe9cb72d9c`.
- Static report: `experiment/reset-boundary-analysis/RESET_BOUNDARY_ANALYSIS.md`.
- R0 resets X55/PM/qcrild2 but not Phone[1]-owned ANM/NRM/QtiSST/DNC.
- R1 (slot1 Phone reconstruction) is the causal minimum but has no verified callable boundary.
- R2 (`.qtidataservices`) rebuilds QNS/IWLAN/CNE providers, not existing framework objects.
- R3 (`com.android.phone`) is the minimum available deterministic framework object reset, diagnostic only, with both-slot impact.
- Proposed test freezes R3, P and exact v2.6.2 for three cycles; any valid failure falsifies R3 and forbids an in-run workaround.
- No ADB/device access; phone writes 0.

NEXT_ACTION: no device action is authorized by this checkpoint. Build an R3 safety/executor audit only after a new explicit decision.

## Current checkpoint: R3 safety/determinism audit passed

- Date: 2026-09-24; Computer B; Account B.
- Audit: `experiment/reset-boundary-r3/R3_SAFETY_DETERMINISM_AUDIT.md`.
- Method: one exact main UID-1001 `com.android.phone` PID TERM; no force-stop, wide kill, retry or SIGKILL.
- ActivityManager persistent auto-recreate and fresh Phone/ANM/NRM/QtiSST/DNC construction are confirmed from current records plus same-ROM C7 evidence.
- R3_READY: 120-second fail-closed state gate with fresh creation markers and unchanged vendor scope.
- Frozen v2.6.2 checkout hash restored to `445752BB49FB487850D0B1A1EFF4F0AA29D58C363C3A86E75BAA841E4CC08F75`; logic unchanged.
- Audit scripts parse under PS5.1 and pass STATIC_NO_ADB. Phone writes 0 so far.

NEXT_ACTION: after this audit is committed/pushed, run the separately authorized one-time reboot baseline, then fixed R3/P/v2.6.2 cycles. Stop at the first valid failure.

## Current checkpoint: R3 run stopped at Cycle 2 pre-R3

- Full result: `experiment/reset-boundary-r3/runs/r3_3cycle/RESULT.md`.
- Cycle 1 passed: exact main phone PID 3472 -> 17402, R3_READY PASS, fixed P, exact v2.6.2, one SIM cycle, WFC healthy in 11 seconds, M1-M7 complete.
- Cycle 2 fixed R0 ended native-clean (pm-service 27719 sole owner, qcrild2 29967, X55 ONLINE/crash zero) but the runner stopped at `R0_NOT_CANONICAL` because framework IWLAN/preferred residue was tested before R3.
- Cycle 2 never executed phone TERM/P/SIM/recovery. Cycle 3 was not run. Do not treat this as R3 falsification or 3-cycle support.
- Current scene: airplane OFF, holder absent, per_mgr running, native clean, VOXI active/UICC enabled, F1.

NEXT_ACTION: no continuation or phone workaround. Redefine the post-R0 intermediate gate in a new, separately authorized series.

## R3 v2 gate-fix checkpoint

- Gate correction report: `experiment/reset-boundary-r3/STATE_MACHINE_GATE_FIX.md`.
- `R0_NATIVE_READY` no longer requires terrestrial framework state; `R3_FRAMEWORK_READY` retains the complete post-recreation canonical gate.
- New series and reboot marker are isolated as `r3_3cycle_v2` / `CONTROL_A0_V2`.
- PS5.1 parser, AST gate-order audit and STATIC_NO_ADB pass. Proven v2.6.2 bytes are unchanged.

NEXT_ACTION: run the newly authorized CONTROL_A0_V2 reboot baseline, then fixed cycles. Stop on the first valid failure.

## R3 v2 final checkpoint

- Result: `experiment/reset-boundary-r3/runs/r3_3cycle_v2/RESULT.md`.
- One reboot baseline used. Cycle 1 passed R0 native readiness and R3 framework readiness; phone PID 3425 -> 17756.
- The fixed P transition did not reach canonical IWLAN/HOME: NRM returned NOT_REG_OR_SEARCHING, ANM IMS->IWLAN was absent, and the 60-second snapshot was UNKNOWN/preferred=false.
- Fail-closed occurred before v2.6.2. SIM OFF/ON 0/0. Cycles 2/3 were not run.
- Classification: `R3_FALSIFIED_AT_CYCLE=1`, `FIRST_MISSING_MILESTONE=M1`.
- Preserved state: airplane ON, native pm-service ownership clean, X55 ONLINE/crash zero, holder absent, VOXI active/UICC enabled, F1.

NEXT_ACTION: stop. Do not add an SST/QNS workaround or another reset to this run.

## Current checkpoint: R4 boot-equivalent boundary design

- Date: 2026-09-24; branch `experiment/v263-repeatable-state-machine`; starting commit `73735fe1356276b64614f925dd7917073da3c0ee`.
- R3 remains validly falsified at Cycle 1. No phone experiment was run during this phase.
- Reports:
  - `experiment/reset-boundary-r4-analysis/BOOT_RESET_DEPENDENCY_GRAPH.md`
  - `experiment/reset-boundary-r4-analysis/R3_VS_BOOT_LIFECYCLE_DIFF.md`
  - `experiment/reset-boundary-r4-analysis/R4_CANDIDATES.md`
- Refined H2: the old epoch is not necessarily the rebound Java Service object. The directly preserved epoch begins at qcrild2 DataModule/DSD/NAH and qtidataservices process/static IIWlan ownership, while the framework consumer graph is new.
- Recommended first falsifiable boundary: R4a = fixed R0 -> exact qcrild2 restart -> native provider readiness -> exact R3 -> A_READY -> fixed P -> unchanged v2.6.2.
- R4b adds qtidataservices recreation; R4c adds the broader RIL/CNE/vendor-IMS userspace producer stack. They are separate future series, not fallbacks.
- ADB not used; phone writes 0.

NEXT_ACTION: no phone action. If authorized later, statically audit R4a and begin a new one-reboot three-cycle series. Stop at the first valid failure.

## Current checkpoint: R4a pre-write implementation audit

- Directory: `experiment/reset-boundary-r4a/`.
- Static audit passed under Windows PowerShell 5.1; R3 default behavior and frozen v2.6.2 hash are unchanged.
- qcrild2 reset primitive is the historical exact one-shot init restart. R4a adds only the frozen producer-first/consumer-second lifecycle composition and fail-closed producer gate.
- No phone write has occurred in this implementation phase. ADB was used only for a read-only current-ROM IIWlan dump.

NEXT_ACTION: establish `CONTROL_A0_R4A` with the one authorized reboot, then run `Run-R4aThreeCycle.ps1`. Stop on the first failed child stage.

## Current checkpoint: R4a v1 stopped before R3

- Result: `experiment/reset-boundary-r4a/runs/r4a_3cycle_v1/RESULT.md`.
- One reboot baseline used. One qcrild2 restart changed 1988 -> 19229 and produced a real cold DataModule/NAH epoch.
- Producer script falsely timed out because it did not parse those two timestamped markers from the IIWlan debug history it had already captured.
- No phone TERM, P, v2.6.2, SIM write, Cycle 2 or Cycle 3 occurred.
- Final scene: airplane OFF, F1, native ownership clean, X55 ONLINE/crash zero, qcrild2 19229 stable.
- R4a is not falsified and R4b is not justified. Phone write actions in the full phase: 4.

NEXT_ACTION: stop. Do not resume this series. A new v2 gate correction needs a new explicit reboot authorization.

## Current checkpoint: R4a v2 frozen before execution

- User authorized one new reboot baseline and `runs/r4a_3cycle_v2`.
- `R4A_V2_EVIDENCE_ADAPTER.md` documents the sole code correction.
- Producer events are read from their authoritative sources and must be fresh relative to the current restart lower bound; stale IIWlan history is rejected.
- All reset and recovery semantics remain unchanged. Static PS5/order/hash/no-write audits pass.

NEXT_ACTION: establish `CONTROL_A0_R4A_V2`, then run `Run-R4aThreeCycle.ps1 -RunName r4a_3cycle_v2` exactly once and stop fail-closed at the first child failure.

## Current checkpoint: R4a v2 falsified at Cycle 2 P

- Result: `experiment/reset-boundary-r4a/runs/r4a_3cycle_v2/RESULT.md`.
- Cycle 1 passed through WFC HEALTHY with one SIM cycle.
- Cycle 2 producer and R3/A_READY passed, but P ended Unknown/UNKNOWN/preferred=false with no fresh M1 to the new phone process.
- v2.6.2 did not run in Cycle 2; SIM writes were zero; Cycle 3 did not run.
- Phone remains in the airplane-ON P-failure scene. No cleanup or adaptive action was performed.
- R4a is falsified. R4b is eligible for design only, focused on qtidataservices/QNS provider lifecycle before the new framework consumer.

NEXT_ACTION: preserve the scene and stop. Do not execute R4b without a separate static audit and explicit authorization.

## Current checkpoint: R4b static provider-lifecycle design

- Starting commit: `99f5af8cd83622ca7d4233c2f3b54cd54d4497a6`; branch `experiment/v263-repeatable-state-machine`.
- R4a counterexample remains frozen. Phone remains in Cycle 2 airplane-ON P failure; no cleanup occurred.
- Reports are under `experiment/reset-boundary-r4b-analysis/`.
- `.qtidataservices` is persistent ActivityManager process `.qtidataservices`, UID 10104, shared by IWLAN/QNS, CneApp and CACert; there is no init service.
- APK inspection proves new QNS provider creation actively queries `IIWlan.getAllQualifiedNetworks` and processes current cache before registering change notifications.
- Future primitive: one exact dynamically verified PID TERM, followed by ActivityManager recreation and a 120-second fail-closed PROVIDER_READY gate. No action was executed in this phase.
- Frozen order: R0 -> qcrild2 cold producer -> qtidataservices cold provider -> exact R3 phone consumer -> fixed P -> unchanged v2.6.2 only if P passes.
- Phone writes: 0.

NEXT_ACTION: preserve the phone. Do not execute R4b until the user separately authorizes implementation, static audit and a fresh one-reboot series.

## Current checkpoint: R4b v1 host-adapter abort

- Branch: `experiment/v263-repeatable-state-machine`; starting commit `bf4ac6d85d017ac6021cb34af8d2b34bb822677e`.
- Result: `experiment/reset-boundary-r4b/runs/r4b_3cycle_v1/RESULT.md`.
- Baseline reboot passed; Cycle 1 producer passed (`qcrild2 1980 -> 14590`).
- One provider TERM recreated `.qtidataservices 3366 -> 23798`, then PS5.1 scalar `.Count` handling aborted the evidence adapter.
- R3/P/v2.6.2/SIM and Cycles 2/3 did not run. R4b is neither passed nor falsified.
- Current frozen state: airplane OFF, F1, pm-service sole owner, X55 ONLINE, crash_count 0; no cleanup or recovery action followed.
- Source correction is static-only and unexecuted.

NEXT_ACTION: sync this checkpoint and stop. Any corrected R4b device series requires new explicit authorization and a new reboot baseline.

## Current checkpoint: R4b v2 falsified at Cycle 1 P

- New series `r4b_3cycle_v2` used one reboot baseline.
- Cycle 1 PIDs: qcrild2 `1961 -> 14682`, qtidataservices `3385 -> 23859`, phone `3448 -> 27795`.
- PRODUCER_READY, PROVIDER_READY and A_READY passed. Provider response serial 0 completed; native IMS cache contained EUTRAN/IWLAN, while exact Java payload/update logs were unobservable.
- Fixed P failed with M1 absent and Unknown/UNKNOWN/preferred=false. v2.6.2, SIM cycle and Cycles 2/3 were not run.
- Result file: `experiment/reset-boundary-r4b/runs/r4b_3cycle_v2/RESULT.md`.
- No workaround, retry or post-failure write occurred.

NEXT_ACTION: preserve the airplane-ON P failure scene. R4b is falsified; do not continue this series.

## Current checkpoint: R4b order/callback analysis completed

- Branch: `experiment/v263-repeatable-state-machine`; analysis started from `896536fc80546234df51ad90dbda0e03e7019b9f`.
- Frozen result remains R4b falsified at Cycle 1 P/M1.
- New phone did create a fresh slot1 provider/callback/query; no existing-provider short circuit explains missing M1.
- QNS internal dump plus target APK semantics prove query serials 0 and 6 returned zero entries. Native NAH IMS `[EUTRAN,IWLAN]` was not the Java/HIDL response payload.
- Boot provider creation is consumer-driven by phone/ANM bind, although qtidataservices host starts first.
- Four sanitized reports are in `experiment/reset-boundary-r4b-analysis/`; raw logs and decompilation artifacts remain host-only.
- Current phase performed read-only inspection only; phone writes 0. No reboot, restart, cleanup, R4c or recovery occurred.

NEXT_ACTION: statically trace the target native IIWlan GET response construction and reconcile it with NAH dump state. Do not execute another reset until that mismatch is understood and a separate experiment is authorized.
