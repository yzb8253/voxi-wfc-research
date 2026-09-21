# Autopilot State

## 2026-09-20 single-SIM simple reinsert complete

- Static, rebuilt-class, DEX write-surface, and fixed-target audits passed. slot0 was ABSENT and had no write path.
- Exactly one fixed slot1 POWER_DOWN returned callback 0, produced true ABSENT/inactive/UICC-disabled/lost mapping, and held that state for 10 seconds.
- Exactly one fixed slot1 POWER_UP returned callback 0. The independent 90-second watchdog saw `power_up.confirmed` and exited without firing its fallback.
- SIM READY/LOADED, subId11 mapping, UICC enabled, CarrierConfig change, and MMTEL READY all returned.
- Through 120 seconds there was no native IMS demand, qti.cne/TNF/DNC IMS request, UDP/4500, XFRM, IMS registration, VOICE/IWLAN, or WFC. Final state is ACTIVE + ENABLED + F1.
- slot0 remained ABSENT; wlan0 and tun0 remained up. No soft-stack, process, modem, airplane, or reboot action occurred.
- Sanitized result: `experiments/sim_soft_reset/single_sim_isolation/SINGLE_SIM_SIMPLE_REINSERT_RESULT.md`.

NEXT_ACTION: stop and preserve F1. Do not repeat the simple reinsert or fall through to soft-stack recovery. Any new below-boundary candidate requires a distinct hypothesis and explicit authorization.

## 2026-09-20 computer-B read-only handoff

- Authoritative branch was fast-forwarded to checkpoint `9c32fabbfbd322db74c1ee65ea6f241a616592cc` before inspection.
- USB ADB resolved exactly one Xiaomi 14 Pro target, serial `fd0ff892`; Magisk root returned UID 0.
- Current VOXI mapping is subId 11 / slot 1 / phoneId 1 / carrierId 28 / MCCMNC 23415, ACTIVE with UICC applications enabled.
- China SIM slot0 is physically/logically absent: `gsm.sim.state=ABSENT,LOADED`, no active protected subscription row.
- Direct health is F1: IMS NOT_REGISTERED, transport UNKNOWN, VOICE/IWLAN unavailable, and WFC unavailable. IWLAN/HOME and MMTEL READY alone do not change the classification.
- The single-SIM source, audit, build report, watchdog, and simple cycle are present. Static audit passes after adding an LF checkout rule for device shell scripts on Windows.
- No POWER_DOWN, POWER_UP, process action, deployment, or other phone write was executed.

NEXT_ACTION: preserve the current single-SIM active/enabled F1 scene. Do not run the simple cycle or watchdog without a new explicit experiment authorization and review of the latest no-repeat boundary.

## 2026-09-20 modem-only restart gate stopped before write

- The purported fresh post-reboot baseline was not a new boot epoch: kernel uptime was about 48 hours and all relevant PIDs remained continuous with the preceding soft-stack experiment.
- Current state remained active/enabled F1: IWLAN/HOME and MMTEL READY, but IMS NOT_REGISTERED/UNKNOWN, VOICE/WFC unavailable, and no qti.cne IMS request/ePDG.
- Current-ROM static trace: shell -> TelephonyManager.rebootRadio -> ITelephony.rebootModem -> Phone.rebootModem -> RIL nvResetConfig(1) -> HAL ResetNvType.RELOAD.
- RELOAD is distinct from HAL ERASE and FACTORY_RESET, and no AP-reboot/PDC/MBN/EFS/persist/flash fallback exists in the framework path.
- The actual shell entry is unavailable: handleRestartModemCommand rejects every user build through TelephonyUtils.IS_USER even for UID0. This phone is user, non-debuggable, release-keys.
- No controlled F1 injection, restart-modem command, direct Binder bypass, process signal, or phone write was executed.
- Result: MODEM_ONLY_RECOVERY=NOT_TESTED.

NEXT_ACTION: preserve the current F1 state. Do not bypass the user-build shell gate. A future direct fixed-target ITelephony.rebootModem helper requires separate explicit authorization and renewed dual-SIM review.


## 2026-09-20 corrected absent-state soft-reboot retry

- The corrected experiment executed exactly one fixed-slot1 POWER_DOWN; callback 0 and card-down/inactive/UICC-disabled state were confirmed.
- Every fixed soft-stack target was signaled once. system_server did restart, but Telephony Binder was not ready before the orchestrator deadline, so its normal POWER_UP path failed before API invocation.
- The independent watchdog fired exactly one fallback POWER_UP at 120 seconds; callback 0.
- VOXI returned to subId11/slot1/phoneId1, ACTIVE, UICC enabled, SIM READY. China Telecom slot0/sub1 remained correctly mapped.
- CarrierConfig ABSENT -> CLEAR_CONFIG -> no-SIM -> ESSENTIAL_LOADED -> LOADED and ImsResolver/MMTEL subId -1 -> 11 were confirmed.
- More than eight minutes later, IWLAN/HOME and MMTEL READY were present, but IMS remained NOT_REGISTERED/UNKNOWN with VOICE/WFC unavailable and no qti.cne IMS request, UDP/4500, or XFRM.
- Result: ABSENT_STATE_SOFT_REBOOT_RETRY=FAIL. The selected stack does not reproduce the full-reboot recovery effect.

NEXT_ACTION: preserve the active/enabled F1 scene. Do not repeat this candidate unchanged. Continue read-only delta analysis unless the user explicitly authorizes a distinct write hypothesis.


## 2026-09-20 absent-state attempt safe-aborted

- Dedicated 120-second watchdog and fixed-target device orchestrator were committed before execution.
- Zero-write runtime preflight passed every helper hash, dual-SIM, network, and process identity gate.
- POWER_DOWN was rejected by the Java helper before API invocation because the dedicated watchdog marker name did not match the helper's generic `watchdog.ready` requirement.
- Actual POWER_DOWN count: 0. Process TERM count: 0. No absent state or soft-stack rebuild occurred.
- The old failure branch issued one POWER_UP against an already-READY slot1; callback 0, with no mapping or state change.
- Final VOXI and China Telecom strict gates passed; wlan0/tun0 remained UP. Live state remains the original F1.
- Source is corrected to bridge both ready markers and to avoid POWER_UP on pre-marker POWER_DOWN rejection. Syntax/static audit passes.

NEXT_ACTION: no automatic retry. Obtain new explicit authorization before one corrected real fixed-slot1 absent-state experiment.

## 2026-09-20 L1.5 pre-execution ready

- Repository recovered from authoritative private remote branch on the new host.
- Current live serial: `192.168.137.127:40027`; Xiaomi 14 Pro identity and Magisk UID 0 confirmed.
- Official Android build-tools 37.0.0 and Temurin JDK 21.0.12.1 produced `slot1-sim-power-helper.jar`.
- Artifact SHA256: `be877b6e9694b4100f2487dc892803de6399c89588f194a1e54d4c3ae3173a31`.
- Source, shell, DEX, fixed-slot, dual-lock, and forbidden-path audits: PASS.
- Device DRY_RUN: PASS. VOXI slot1/sub11 and protected China Telecom slot0/sub1 gates were both READY and strict gate passed.
- Root-only deployment and independent watchdog-ready validation: PASS.
- Watchdog was hardened to absolute wall-clock deadlines; no-down test exited exactly after 60 seconds with no POWER_DOWN or POWER_UP marker/call.
- Real slot1 SIM power cycle executed: NO.
- Current direct IMS/WFC observation remains F1; this was not modified.

NEXT_ACTION: Wait for explicit authorization, then perform one fixed slot1 SIM power cycle using the audited executor and independent rollback watchdog. Do not accept runtime target identifiers and do not run any older IMS/CNE/qcrild/system_server/modem experiments.

## 2026-09-19 phase handoff

- New active workstream: `experiments/sim_soft_reset/`.
- Goal: emulate physical VOXI SIM remove/insert through a reversible slot1 UICC/Radio/UIM lifecycle without AP reboot.
- Current live serial: `192.168.1.25:42319` (mDNS alias also visible).
- Current preserved state: ACTIVE + UICC ENABLED + F1; direct IMS/WFC unhealthy, slot0 mapping gate PASS.
- Matrix and independent scripts created; L0 read-only capture passed.
- No new phone write was executed.
- Preferred next work: statically prove and build fixed `setSimPowerStateForSlot(1, POWER_DOWN/POWER_UP)` helper. Raw QMI/HIDL calls stay blocked.
- Existing auto-recovery module is unchanged.

## 2026-09-19 slot mapping checkpoint

- Read-only automatic mapping completed under `experiments/sim_soft_reset/SLOT_MAPPING/`.
- VOXI: MCCMNC 23415 -> subId 11 -> Android slot/phone 1 -> `IRadio/slot2` -> `IUim/Uim1` -> `vendor.qcrild2 -c 2` -> modem/QMI stack 1.
- China Telecom: MCCMNC 46011 -> subId 1 -> Android slot/phone 0 -> `IRadio/slot1` -> `IUim/Uim0` -> primary `vendor.qcrild` -> stack 0.
- ICCIDs are represented only as SHA-256 hashes; privacy scan passed.
- No SIM power, UIM reset, qcrild operation or other write was executed.
- L2-01 stays blocked until the current-ROM method chain, power constants, result callback and rollback behavior are proven.

UPDATED: 2026-09-18T10:30:40+08:00
STATUS: PHASE8D_COMPLETE_FAILED_PRESERVED
FINAL_GOAL: ACHIEVED
HARD_BLOCKER: NONE
VALIDATION: 3/3 PASS

CURRENT_DEVICE_SERIAL: fd0ff892
CURRENT_EXPECTED_STATE: ACTIVE_ENABLED_F1_PS_WLAN_UNKNOWN
CURRENT_FAILURE_CLASS: F1_IMS_NOT_REGISTERED

PHASE 8A QCOM IMS PROCESS RESTART:
- Exactly one `kill -TERM 3184` targeted the verified `org.codeaurora.ims` process at 2026-09-18T09:08:07+08:00.
- Persistent process restarted as PID 23125 within 24 ms and rebound within 58 ms.
- Both slot MMTEL features were recreated and READY after about 2.2 seconds.
- No new qti.cne IMS request, UDP/4500, XFRM, IMS registration, VOICE/IWLAN, or WFC appeared through 180 seconds; final 195.7-second sample remained F1.
- China Telecom mapping remained protected; its shared MMTEL service connection was transiently unavailable for about 2.216 seconds and then READY.
- Result: `QCOM_IMS_RESTART_RECOVERY=FAIL`. Candidate B was not executed.

PHASE 8B CNE/QTIDATASERVICES RESTART:
- Exactly one `kill -TERM 3170` targeted the verified shared `.qtidataservices` process at 2026-09-18T09:21:00+08:00.
- Process restarted as PID25920 in about 30 ms; CneApp and co-hosted IWLAN services rebound within about 225 ms.
- No new qti.cne IMS request, ePDG, XFRM, IMS registration, VOICE/IWLAN, or WFC appeared through 120 seconds.
- slot0 safety gate and wlan0/tun0 remained intact. Result: `CNE_RESTART_RECOVERY=FAIL`.

PHASE 8C FAST-FOLLOW:
- All technical and dual-SIM gates passed for independent init service `vendor.cnd`.
- Exactly one `kill -TERM 1838` was executed at 2026-09-18T10:05:29+08:00; init restarted cnd as PID909.
- No observable CNE callback replay, qti.cne IMS request, ePDG/XFRM, IMS registration, VOICE/IWLAN, or WFC appeared through 120 seconds.
- Slot1 residual IWLAN/HOME fell to UNKNOWN after the restart. slot0 mapping and wlan0/tun0 remained protected.
- Result: `CND_RESTART_RECOVERY=FAIL`. No additional write is authorized or pending.

PHASE 8D COORDINATED CND + CNE RESTART:
- Safety gates passed in the preserved active/enabled F1 state.
- One root TERM restarted cnd from PID909 to PID7716; after stabilization, one root TERM restarted `.qtidataservices` from PID25920 to PID7876.
- CneApp and all co-hosted IWLAN services rebound. Generic qti.cne INTERNET/listener requests were recreated, but no IMS capability request or observable native IMS-demand callback replay appeared.
- PS/WLAN remained UNKNOWN, IWLAN preferred remained false, and no ePDG/XFRM or direct IMS/WFC health appeared through 122.6 seconds.
- slot0 and wlan0/tun0/VPN/airplane state remained protected. Result: `COORDINATED_CND_CNE_RESTART=FAIL`.
- No further radio/modem/SSR experiment is authorized or pending.

WRITE_BUDGET:
- fault_injections_used: 4 / 4
- level1_write_experiments_used: 10 / 10

VALIDATED RECOVERY CONTRACT:
- A: If subId 11 is inactive, slot mapping is lost, and UICC applications are disabled, execute exactly one hard-coded `ISub.setUiccApplicationsEnabled(true,11)` after all VOXI and protected-slot0 gates pass.
- B: If `goldenStrong=true`, perform no write.
- C: If subscription is active but WFC is unhealthy, perform no automatic write, do not call false, and do not call resetIms; report the probe state and `failureClass`.

HISTORICAL 3/3 CHECKPOINT:
- Target: subId 11 / slot 1 / phoneId 1 / carrierId 28 / MCCMNC 23415.
- IMS: REGISTERED (2), WLAN (2).
- MMTEL VOICE/IWLAN: available and capable.
- WFC availability: true.
- IMS IWLAN NetworkAgent: 104.
- qti.cne IMS request: 380.
- UDP/4500 NAT-T keepalive: present.
- China Telecom slot0/subId1/MCCMNC46011: protected and active.
- `ITelephony.resetIms(1)` was never executed and is not part of automatic recovery.

CURRENT RECONCILED CHECKPOINT:
- Direct IMS/WFC: REGISTERED(2), WLAN(2), VOICE/IWLAN true, WFC availability true.
- User-visible WFC icon: PRESENT.
- ePDG: UDP/4500 keepalive and bidirectional XFRM tunnel present.
- Dedicated IMS IWLAN NetworkAgent: absent supporting signal, not a direct-health failure.
- Stability: 31/31 direct-health samples passed over 301 seconds; slot0 protected.

LATEST F1 EXPERIMENT:
- Real active/enabled F1 -> one false -> persistent F8 -> one true.
- Partial recovery reached REGISTERED(2), WLAN(2), VOICE/WFC true, MMTEL READY, and UDP/4500 keepalive.
- IMS IWLAN NetworkAgent remained absent, but user-visible WFC, direct IMS/WFC APIs, UDP/4500, and bidirectional XFRM/ePDG were healthy.
- Reconciliation observed 31/31 passing direct-health samples over 301 seconds with slot0 protected.
- Final result PASS; no resetIms was executed and no further F1 experiment is permitted.

PHASE 6 RESETIMS SLOT1 CONTROLLED TEST:
- Current-ROM scope and fixed target safety gate passed.
- Exactly one `ITelephony.resetIms(1)` was executed at 2026-09-17T23:01:55.429+08:00.
- Qualcomm IMS received paired slot1 disable/enable registration-change requests and returned both Binder/radio responses.
- The follow-up registration query returned `General_Error17-Unable to connect` on IWLAN.
- No new qti.cne IMS request, ePDG UDP/4500, XFRM, IMS registration, VOICE/IWLAN, or WFC appeared through 120 seconds.
- Slot0 remained protected. Result: `RESETIMS_RECOVERY=FAIL`; no second write was executed.

## 2026-09-20T15:15:32+08:00 stabilized absent + second reinsert pre-execution checkpoint

- Current live state remains fixed-target ACTIVE + UICC ENABLED strict F1; no write was performed while preparing this checkpoint.
- Added two fixed watchdogs: cycle1 rollback at 300 seconds from power_down.sent, cycle2 rollback at 90 seconds.
- Added a device-side cycle1 orchestrator with one fixed POWER_DOWN, true-ABSENT confirmation, exact 10-second absent hold, one ordered soft-stack rebuild, continuous 15-second stability gate, extra 20-second recheck, and one normal POWER_UP targeted within 180 seconds.
- Added a host executor that permits a second and final POWER_DOWN/POWER_UP only if the first reinsert restores complete mapping but remains strict F1 through 90 seconds.
- Static write-count/forbidden-path audit, PowerShell parse, helper SHA256, and Android sh -n checks: PASS.

NEXT_ACTION: execute the explicitly authorized stabilized absent-state experiment once. Maximum budget: two POWER_DOWN, two normal POWER_UP, one soft-stack rebuild; watchdog POWER_UP is fallback only. Stop immediately on any gate failure or after the second reinsert result.

## 2026-09-20 stabilized absent + second reinsert complete

- Result: FAIL. The complete bounded write budget was consumed: two fixed slot1 POWER_DOWN callbacks, two fixed slot1 POWER_UP callbacks, and one soft-stack rebuild. No third POWER_DOWN occurred.
- First cycle reached true ABSENT and rebuilt the full userspace stack. The 15-second stability gate passed, but the extra 20-second check crossed the 180-second normal-up target.
- The 300-second watchdog exposed a design incompatibility: the helper rollback arm lives only five minutes and expired before fallback. The rejected fallback did not reach the Telephony API. A same-boot fixed-target arm renewal safely completed the authorized first POWER_UP.
- First insertion restored ACTIVE/UICC ENABLED/IWLAN HOME but remained strict F1.
- The second and final remove/reinsert completed without process restarts. Through approximately 182 seconds it remained strict F1 with no native IMS demand, qti.cne IMS request, UDP/4500, XFRM, IMS registration, or WFC.
- China Telecom slot0 and wlan0/tun0 remained protected. Current final state is ACTIVE + UICC ENABLED + F1.

NEXT_ACTION: no further SIM power cycle or userspace restart. Preserve the active/enabled F1 scene. Any experiment below this proven boundary requires new explicit authorization and a separate safety review; otherwise recover only by the already known full reboot lifecycle.

## 2026-09-20 single-SIM full userspace rebuild complete

- Result: FAIL. Exactly one TERM was sent to each verified current PID in this order: imsdatadaemon, imsqmidaemon, cnd, qtidataservices, Qualcomm IMS.
- All five targets restarted and stabilized; Qualcomm ImsService rebound. qcrild, qcrild2, netmgrd, phone, and system_server remained at their protected PIDs.
- No native IMS demand, qti.cne/TNF/DNC IMS request, UDP/4500, XFRM, IMS registration, VOICE/IWLAN, or WFC appeared during the stabilization window.
- cnd reconstruction cleared the residual slot1 IWLAN/HOME state; final PS/WLAN is UNKNOWN and IWLAN preferred is false.
- slot0 remains ABSENT, VOXI remains ACTIVE/UICC ENABLED/F1, and wlan0/tun0 remain up.

NEXT_ACTION: stop. Do not append phone, system_server, RIL, modem, SIM-power, or resetIms work to this failed run. Any new experiment requires a distinct hypothesis and explicit authorization.

## 2026-09-20 QCRIL setDataProfile race confirmation

- Read-only all-buffer log analysis confirmed that both physical insertions built the same Data/IMS/EIMS profile list, sent multiple slot1 `SET_DATA_PROFILE` requests, and received successful RIL responses.
- The successful second-insertion `qualifiedNetworksChangeIndication(IMS,[IWLAN])` occurred at 20:52:24.825, 341 ms before that insertion's first `SET_DATA_PROFILE` request at 20:52:25.166.
- The setDataProfile-to-QNS race is therefore not confirmed and materially weakened. The earliest concrete divergence is now DSD/QNS APN qualification/cache synchronization after IWLAN/HOME.
- No phone write, SIM operation, process restart, Binder/HIDL write, or recovery action was executed.
- Sanitized report: `experiments/sim_soft_reset/single_sim_isolation/QCRIL_SETDATAPROFILE_RACE_CONFIRMATION.md`.

NEXT_ACTION: preserve the scene. Candidate only: statically audit a fixed-slot1, read-semantics `IIWlan.getAllQualifiedNetworks(serial)` cache query as a discriminator between stale native cache and missing callback replay. Do not execute it without a separate authorization and safety review.

## 2026-09-20 QCRIL IIWLAN cache snapshot

- Static audit confirmed that `getAllQualifiedNetworks` copies the native cache and returns it without a cache update or QMI write, but its response belongs to the already registered global `IWlanResponse`.
- No zero-write shell/business-method client was available, so `getAllQualifiedNetworks` was not invoked and `setResponseFunctions` was never called.
- One standard read-only `IBase::debug` call exposed the current native cache without changing callback ownership: IMS, DEFAULT, and EIMS entries are present, but all have `networks=[]`.
- Native global preference is IWLAN, registration state is HOME, and DSD/WDS/Auth/IWLAN readiness flags are true. Framework still reports `mIsIwlanPreferred=true`, while IMS/WFC remains strict F1.
- Verdict: `NATIVE_QNS_CACHE=STALE`; the fault is in DSD APN qualification/indication/cache synchronization, not merely Java provider replay.
- Phone writes performed: 0.
- Sanitized report: `experiments/sim_soft_reset/single_sim_isolation/QCRIL_IIWLAN_CACHE_SNAPSHOT.md`.

NEXT_ACTION: read-only/static trace of the DSD indication-to-NetworkAvailabilityHandler cache-update path. Do not replay setDataProfile or invoke a refresh/write API.

## 2026-09-20 DSD/QNS golden-diff preparation

- Captured a complete current F1 BAD snapshot through the existing fixed-slot2 `IBase::debug` path and other read-only dumps; phone writes remained 0.
- Current native APN entries: IMS, DEFAULT, and EIMS present, all with `hasPendingIntent=false` and `networks=[]`; `LastReportedNetworkAvailability` is empty.
- Static analysis proves that setDataProfile handling clears/rebuilds the APN map with empty network vectors. Only per-APN DSD available-system or intent-to-change preferred-system indications populate those vectors.
- `convertResultList` explicitly skips an empty network vector or one whose first value is UNKNOWN. `globalPrefSys=IWLAN` is a separate handler-level field and does not populate the IMS per-APN vector.
- Raw current per-APN DSD preferred/available-system fields are not exposed by the dump and remain UNKNOWN.
- Added and successfully executed `dsd_qns_golden_diff/capture_qns_native_snapshot.ps1`: 12/12 read-only sections completed, output is host-only and Git-ignored, and no IIWlan business method was called.
- Sanitized report: `experiments/sim_soft_reset/single_sim_isolation/dsd_qns_golden_diff/DSD_NETWORK_AVAILABILITY_GOLDEN_DIFF_PREPARATION.md`.

NEXT_ACTION: wait for the user to create a real WFC Golden state, then run exactly the same capture script once and perform a field-level BAD-vs-GOLDEN diff. Do not attempt recovery in this phase.

## 2026-09-20 GOLDEN DSD/QNS snapshot complete

- A real-WFC GOLDEN state passed REGISTERED/WLAN, VOICE-IWLAN, WFC, CNE request, UDP/4500, and XFRM gates.
- The exact audited BAD/GOLDEN script was used; phone writes remained 0.
- GOLDEN hash: `602E81EA342A7185BDA3000CCCDF406C77354878D17DD7BF253B28361E371CB6`.
- Result is CASE B: current native IMS/DEFAULT/EIMS vectors remain empty in both BAD and GOLDEN; `globalPrefSys=IWLAN` and `hasPendingIntent=false` are also unchanged.
- The current native dump table cannot distinguish broken F1 from healthy WFC. A transient IMS/IWLAN update is visible in GOLDEN history, but it is not retained after the IMS path is established.
- Root boundary remains unresolved between transient DSD/QNS qualification delivery and persistent CNE IMS demand; do not label the current empty cache as the root cause.
- Report: `experiments/sim_soft_reset/single_sim_isolation/dsd_qns_golden_diff/BAD_VS_GOLDEN_NATIVE_DSD_QNS_DIFF.md`.

NEXT_ACTION: no write. Candidate only: a future timestamp-aligned read-only lifecycle capture around a real recovery, correlating NAH/DSD, ANM, CNE, ePDG/XFRM, and IMS registration.


## 2026-09-21 R/C/P airplane boundary complete

- Captured R (airplane-on WFC healthy), C (airplane off), and P (airplane on again) with the same audited read-only command set. Codex phone writes: 0.
- R was F0: REGISTERED/WLAN, VOICE-IWLAN and WFC available, qti.cne request 267, IMS NetworkAgent 102, UDP/4500, and XFRM active.
- R->C released request 267 and the IMS data path. Native NetworkAvailabilityHandler completed IMS preference as EUTRAN and retained IMS=EUTRAN in `LastReportedNetworkAvailability`.
- P restored PS/WLAN IWLAN/HOME and `mIsIwlanPreferred=true`, but IMS remained NOT_REGISTERED/UNKNOWN with no qti.cne IMS request, NetworkAgent, UDP/4500, or XFRM.
- The decisive P transition produced IMS `[UNKNOWN,IWLAN]`, not R's successful `[IWLAN,UNKNOWN]`. No outbound IMS/IWLAN availability report followed, and the last-reported IMS preference remained EUTRAN.
- DSD/WDS readiness, IWLAN enablement, modem capability, global IWLAN preference, and HOME registration remained ready; basic service readiness is not the missing state.
- Sanitized report: `experiments/sim_soft_reset/single_sim_isolation/dsd_qns_golden_diff/R_C_P_AIRPLANE_BOUNDARY.md`.

NEXT_ACTION: no execution. Statically locate and audit one fixed-slot2 lifecycle entry that recreates the QCRIL DataModule/IIWlan NetworkAvailabilityHandler DSD AP-assist indication session without changing SIM, radio, or modem state.

## 2026-09-21 minimum QCRIL reinit entry audit complete

- Current-ROM target library/process identity: `libril-qc-hal-qmi.so` in fixed `/vendor/bin/hw/qcrild -c 2`; current binary content was not bypass-read after SELinux denial.
- Source-correlated audit found `DataModule` exclusively owns NetworkAvailabilityHandler as a unique_ptr. `initializeIWLAN()` replaces it; `deinitializeIWLAN()` destroys it.
- No single runtime entry both recreates NAH, re-registers AP-assist/system-status indications, and obtains fresh per-APN DSD status.
- Closest entry: fixed-slot2 `setResponseFunctions -> IWLANCapabilityHandshake(true) -> initializeIWLAN`. It recreates NAH and registers AP-assist indications but only replays cached status.
- Minimum complete source-level sequence: `sendAPAssistIWLANSupportedSync -> registerForSystemStatusSync -> initializeIWLAN -> generateDsdSystemStatusInd`.
- AP-side DataModule targeting is fixed slot2. Modem-side QMI DSD scope is UNKNOWN because these requests carry no explicit slot field.
- No phone write or business method was executed.
- Report: `experiments/sim_soft_reset/single_sim_isolation/dsd_qns_golden_diff/MINIMUM_QCRIL_REINIT_ENTRY_AUDIT.md`.

NEXT_ACTION: no execution. Design and statically audit a one-shot fixed-RIL-instance-1 diagnostic hook for only the four-step sequence; do not replace production IIWlan callbacks from a second client.

## 2026-09-21 one-shot QCRIL slot2 reinit preparation

- Fixed runtime target was verified read-only as `/vendor/bin/hw/qcrild -c 2`, PID 1919 at capture time, PPID 1, UID radio, SELinux `u:r:rild:s0`.
- The runtime base of `libril-qc-hal-qmi.so` could not be read: `/proc/1919/maps` is denied even from the available Magisk context. The current library bytes are likewise protected.
- Consequently, all four exact current-ROM function addresses remain unresolved. The live `DataModule` and `DSDModemEndPoint` pointers also have no safe exported source.
- Direct calls from an arbitrary injected thread are unsafe. A valid implementation must post one custom fixed message onto the existing DataModule looper and obtain the endpoint from that live context.
- No non-invasive in-process integration route was found. No hook binary was built or deployed, no debugger/injector was attached, and no target function was called.
- Dry-run verdict: FAIL_SAFE. Phone writes: 0.
- Sanitized report: `experiments/sim_soft_reset/single_sim_isolation/dsd_qns_golden_diff/ONE_SHOT_QCRIL_SLOT2_REINIT_PREPARATION.md`.

NEXT_ACTION: execution remains blocked. Do not guess offsets or object pointers. Resume only if an exact matching current-ROM library with symbols/verified build identity and a non-invasive DataModule-looper hook path become available; do not use a second IIWlan callback client, ptrace/debugger injection, or process restart.
