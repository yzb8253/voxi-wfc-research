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
