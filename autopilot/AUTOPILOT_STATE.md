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


## 2026-09-21 QCRIL external reinit trigger audit

- Static audit covered current/source-correlated OEM Hook/QcRilHook, IIWlan HIDL, local/OEM sockets, QtiBus, DIAG, and Android property/init control surfaces. Phone writes: 0.
- No existing external command closes the required capability registration + system-status registration + NAH recreation + fresh DSD status chain.
- `IIWlan/slot2.setResponseFunctions()` reaches the DataModule looper and recreates NAH, but replaces production callbacks and does not refresh DSD status.
- A real DSD endpoint non-operational -> operational transition reaches the DataModule looper and refreshes DSD registration/status, but the post-SSR path does not recreate NAH; safely inducing the transition has no narrow external API.
- OEM Hook event tables have no IWLAN/DSD/DataModule reinit command. QtiBus exposes only DDS-switch and IA-info DataModule messages. DIAG is logging-only for this path. No property/init reinit trigger exists.
- Result: `NO_EXISTING_EXTERNAL_TRIGGER`.
- Report: `experiments/sim_soft_reset/single_sim_isolation/dsd_qns_golden_diff/QCRIL_EXTERNAL_REINIT_TRIGGER_AUDIT.md`.

NEXT_ACTION: no execution. The minimum alternative is vendor source instrumentation: one fixed `IIWlan/slot2` diagnostic method dispatching one dedicated message onto the existing DataModule looper. Do not pursue runtime injection, callback replacement, SELinux bypass, or SSR.

## 2026-09-21 QCRIL patch deployment feasibility

- Static implementation/deployment audit completed; phone writes: 0.
- Existing `IBase::debug()` reaches current `IWlanImpl` and can carry one exact token without replacing production response callbacks.
- A safe implementation must dispatch a dedicated message to the DataModule looper and hard-check process instance 1, `IIWlan/slot2`, boot ID, and atomic one-shot state.
- The source mirror is behaviorally correlated but cannot produce a proven ABI-compatible current-ROM library: exact SONAME/build-id/DT_NEEDED/exports and Xiaomi build inputs remain unavailable.
- Magisk bind-mount is mechanically possible and leaves `/vendor` unchanged, but activation requires AP reboot and an unverified library could break both qcrild instances.
- Report: `experiments/sim_soft_reset/single_sim_isolation/dsd_qns_golden_diff/QCRIL_PATCH_DEPLOYMENT_FEASIBILITY.md`.

NEXT_ACTION: STOP. Do not build, binary-patch, mount, or deploy until exact matching vendor build artifacts are available.

## 2026-09-21 fixed-slot2 qcrild2 cold restart complete

- P baseline passed: VOXI remained active/UICC-enabled on subId 11, slot 1, phoneId 1, carrierId 28, MCCMNC 23415; IMS/WFC was strict F1 and native IMS ordering was `[UNKNOWN,IWLAN]`.
- Exactly one native init restart of `vendor.qcrild2` was performed. PID changed 1919 -> 855; primary qcrild stayed PID 1879, and the kernel boot ID did not change.
- The new process performed DataModule cold initialization, constructed a new NetworkAvailabilityHandler, reconnected `IIWlan/slot2`, and re-established DSD/WDS/IWLAN readiness.
- Its first fresh IMS qualified list was still `[UNKNOWN,IWLAN]`; `[IWLAN,UNKNOWN]` and outbound IMS/IWLAN publication never appeared.
- No qti.cne IMS request, ePDG/XFRM, IMS registration, VOICE/IWLAN, or WFC appeared through 120 seconds.
- Result: `CASE_C`, `P_TO_R=NO`. Slot2 qcrild2 cold initialization alone is below the AP-reboot recovery boundary.
- Sanitized report: `experiments/sim_soft_reset/single_sim_isolation/dsd_qns_golden_diff/P_TO_R_QCRILD2_COLD_RESTART_RESULT.md`.

NEXT_ACTION: stop. Do not repeat qcrild2 restart or execute a Magic SIM cycle; the native ordering/publication prerequisite was not restored. Any next experiment requires a new hypothesis and explicit authorization.

## 2026-09-23 X55 ownership handoff precheck

- GitHub and local `voxi-wfc-auto-recovery` were synchronized at `b513bd627da0c4476fc18012c318248b2c4d1d8c`; no remote branch or history contains the later v2.6.2/X55 holder work described in the cross-account handoff.
- Device `fd0ff892` is online and rooted. Current processes include pm-service PID 13288, pm-proxy 1699, primary qcrild 1926, fixed-slot2 qcrild2 13706, and mdm_helper 1297. No holder file was found.
- Init RC confirms the expected native Peripheral Manager service topology. VOXI remains active/enabled on subId 11, slot 1, phoneId 1, carrierId 28, MCCMNC 23415.
- The available Magisk SELinux domain cannot read pm-service FDs or X55 state/crash_count. Therefore current native ownership, X55 ONLINE, and `crash_count=0` could not be directly verified.
- The installed module is v2.0 and the authoritative repository lacks the previously audited v2.6.2 holder/observer implementation.
- Result: `BLOCKED_PRE_WRITE / FAIL_SAFE`. The ownership handoff experiment was not run and phone writes were 0.
- Report: `experiments/x55_native_handoff/OWNERSHIP_HANDOFF_PRECHECK.md`.

NEXT_ACTION: recover the missing v2.6.2/X55 holder and read-only ownership observer into GitHub, audit them, and repeat the entry gate. Do not stop Peripheral Manager or create a live holder until owner, ONLINE state, and crash count are directly confirmed.

## 2026-09-23 X55 ownership handoff attempt

- Experiment `X55-OWNERSHIP-HANDOFF-001` passed the direct root/native entry gate: pm-service PID 13288 sole FD9 owner, X55 ONLINE, crash_count 0, no holder, qcrild2 PID 13706.
- per_mgr stop and holder startup succeeded. Holder PID 31163 became sole owner and powered X55 ONLINE.
- The host probe aborted before the contended per_mgr start because `$Pid` collided with PowerShell's automatic `$PID`. The parameter is corrected to `$ProcessId`, syntax/write-surface audited, and not rerun.
- Fail-safe cleanup TERM'd only the owned holder and started per_mgr. Final preserved state: pm-service PID 31818 running, owner NONE, X55 OFFLINE, crash_count 0, holder absent, qcrild2 unchanged PID 13706.
- Holder contention and qcrild2 re-vote remain untested. Result: `ABORTED_BEFORE_CONTENDED_PHASE / INCONCLUSIVE`. Phone writes: 5.
- Full raw logcat remains host-only; only sanitized evidence is checkpointed.

NEXT_ACTION: preserve the OFFLINE/no-owner scene. No automatic rerun, qcrild2 restart, or recovery write; obtain a new explicit user decision.

## 2026-09-23 X55 ownership follow-up 001B

- Preserved-scene entry gate PASS: pm-service 31818, owner NONE, X55 OFFLINE, crash_count 0, holder absent, qcrild2 13706.
- Exactly one `vendor.qcrild2` restart changed PID 13706 -> 873.
- pm-service 31818 became sole FD9 owner; X55 became ONLINE; crash_count stayed 0.
- Complete logcat had no required PerMgrLib/PerMgrSrv QCRIL registration/voting strings.
- Result: `QCRILD2_RESTART_NO_VALID_REVOTE`. Phone writes: 2. No recovery action followed.

NEXT_ACTION: stop. Require a new explicit decision before any further phone write.


## 2026-09-23 v2.7-alpha native-handoff static build

- Phase: static development and audit only.
- 001B behavioral conclusion: VERIFIED_NATIVE_REACQUIRE_AFTER_QCRILD2_RESTART.
- Mechanism qualification: REVOTE_MECHANISM_LOG_UNPROVEN.
- Added a new v2.7-alpha state machine without replacing v2.6.2.
- Flow: native entry gate -> controlled X55 rebirth -> contended per_mgr start -> owned-holder TERM -> one fixed qcrild2 restart -> native pm-service reacquire -> WFC check -> at most one fixed SIM2 cycle if still unhealthy.
- Default is dry-run. Real execution requires an explicit switch and fixed confirmation token.
- Static policy audit PASS; PowerShell and Android shell parsing PASS.
- No ADB wait, no device execution, and phone writes 0.

NEXT_ACTION: wait for explicit user approval before running v2.7-alpha on the device.

## 2026-09-23 v2.7-alpha host compatibility repair after second launch

- The second authorized launch stopped before any phone write and is classified `BLOCKED_PRE_WRITE_HOST_SCRIPT_COMPATIBILITY`, not a recovery failure.
- Exact blockers were a custom `$matches` collision with automatic `$Matches` and CRLF contamination of the multiline Android native-state probe.
- The custom collection is now `$resolvedProcesses`. All `Invoke-Root` payloads and the direct holder payload use explicit LF normalization.
- Windows PowerShell 5.1 parser, automatic-variable, Android payload CR, holder/qcrild2/SIM command-build, quoting, holder lifecycle, fail-safe, and state-machine-order audits pass.
- `CUSTOM_MATCHES_VARIABLES=0`, `ANDROID_PAYLOAD_CR_COUNT=0`, `STATIC_NO_ADB=PASS`, `STATE_MACHINE_UNCHANGED=YES`, phone writes 0.

NEXT_ACTION: stop. Do not run a third device experiment without explicit user approval.

## 2026-09-23 v2.7-alpha third launch blocked pre-write

- Fresh device/native gate passed on `fd0ff892`; initial scene was native-clean F1.
- The single authorized launcher invocation stopped on the missing hash-pinned single-SIM helper JAR before any phone write.
- The artifact path is covered by repository `*.jar` ignore and was absent on Computer B.
- No per_mgr stop, holder, qcrild2 restart, SIM action, or recovery action occurred. Post-state remained pm-service PID 31818 sole owner, X55 ONLINE, crash_count 0, qcrild2 PID 873, holder absent, F1.
- Result: `BLOCKED_PRE_WRITE_MISSING_AUDITED_SINGLE_SIM_HELPER`; phone writes 0.

NEXT_ACTION: static helper rebuild/hash verification and packaging/preflight correction. Do not rerun the phone experiment without explicit approval.

## 2026-09-23 single-SIM helper artifact checkpoint

- Computer A artifact exists at `experiments/sim_soft_reset/single_sim_isolation/build/single-sim-slot1-power-helper.jar`.
- Size: 11534 bytes.
- SHA-256: `90D6F55FBE1F941C1E3EEE1AA1F93B569FA3AE4084B93C5560082A38AAAF5C39`.
- Provenance: existing Computer A audited artifact, re-verified before staging.
- The repository-wide `*.jar` ignore remains unchanged; this one exact binary is force-tracked.
- v2.7-alpha's fixed hash safety gate remains unchanged.
- Git-only work: ADB not used; phone writes 0; v2.7-alpha not run.

NEXT_ACTION: wait for fresh explicit authorization before any additional v2.7-alpha device execution.

## 2026-09-23 v2.7-alpha fourth launch blocked pre-write

- Exact tracked artifact was present and the fresh external device/native gate passed.
- The one launcher invocation stopped because `Get-FileHash` was not resolved by the exact Windows PowerShell 5.1 runtime at `Assert-LocalArtifact`.
- No per_mgr stop, holder, qcrild2 restart, SIM action, or recovery action occurred. Post-state remained native-clean F1.
- Result: `BLOCKED_PRE_WRITE_PS51_FILEHASH_RESOLUTION`; phone writes 0.

NEXT_ACTION: repair and host-only test the actual launcher artifact assertion. Do not rerun without explicit approval.

## 2026-09-24 Computer A legacy recovery

- Git/filesystem-only audit scanned 465 D: candidates totaling 463169043 bytes.
- Exact v2.6.2 host source is recovered with SHA-256 provenance; raw-log completeness remains unresolved.
- PassiveMonitor v1.2 is canonical under `tools/`; StateSearcher v3.0-v3.5 and SSR read-only audit are preserved.
- 353 raw/unselected evidence files totaling 416795027 bytes remain host-only and hash-indexed.
- Two source-less kernel modules remain host-only pending a separate decision.
- Source hash match PASS; no D: source modified; ADB not used; phone writes 0.

NEXT_ACTION: no phone experiment is authorized by this recovery. Continue only from a new explicit user decision.

## 2026-09-24 v2.7-alpha make-before-break run 007

- Tested exact commit `9ccf2eeeac9b4f14b5b662e4a8b076a1552695d4` once after fresh gate and paired PS5.1 selftest PASS.
- Initial scene: single-SIM F1; pm-service 22536 sole owner; X55 ONLINE; crash_count 0; holder absent; qcrild2 873.
- Holder 27125 sole ownership, X55 rebirth, new PON_SUCCESS, and exact holder+new pm-service 28220 dual ownership all passed.
- One exact TERM was sent. Holder 27125 remained alive beyond 10 seconds while waiting on child `sleep 60`; no retry followed.
- Preserved scene: holder+pm-service dual ownership, holder PID file present, X55 ONLINE, crash_count 0, qcrild2 873 unchanged, WFC F1.
- SIM OFF/ON 0/0. Production result: `X55_REBIRTH_SUCCESS / NOT_RUN / NOT_CHECKED / NOT_RUN`; phone write actions 4.

NEXT_ACTION: preserve the dual-owner scene. Perform static-only redesign of deterministic holder TERM completion; no cleanup or rerun without explicit authorization.
## 2026-09-24 W1 success versus V1 failure forensic diff

- Completed a host-only event timeline diff; A/P canonical and recovery code remain unchanged.
- Both runs reached ANM `ims -> [IWLAN]` and NRM IWLAN/HOME after SIM ON.
- The first confirmed consequential fork is V1's missing NRM-to-SST delivery and therefore missing DNC WLAN restoration. The missing qti.cne request is downstream.
- Historical filters did not retain complete QNS/DSD/WDS/QImsService logs, so vendor-side absence is not claimed.
- Phone writes 0; ADB not used.

NEXT_ACTION: add capture-only event telemetry for the ANM -> NRM -> SST -> DNC -> qti.cne chain before considering any canonical gate or recovery change.

## 2026-09-24 deterministic reset-boundary analysis

- Synced exact baseline `b3547a32c2a74b2eb60d943e5f006efe9cb72d9c` on `experiment/v263-repeatable-state-machine`.
- Reframed the work from an SST workaround to a falsifiable lifecycle-reset hypothesis.
- R0 covers X55/PM/qcrild2 but leaves ANM, NRM, QtiSST, DNC and framework IMS objects alive.
- A slot1-only Phone/SST reconstruction (R1) is the causal minimum, but no verified production API exposes it.
- A `.qtidataservices` reconstruction (R2) recreates vendor QNS/IWLAN/CNE providers but only rebinds existing framework objects.
- `com.android.phone` (R3) is the first available boundary that deterministically recreates the entire framework object graph. It is diagnostic, broad and affects both slots.
- Report: `experiment/reset-boundary-analysis/RESET_BOUNDARY_ANALYSIS.md`.
- Host-only work. ADB not used; phone writes 0.

NEXT_ACTION: separately audit an R3 executor and run only after explicit authorization. Freeze R, P and v2.6.2 for three cycles; any failed valid cycle falsifies R3 without an in-run patch.

## 2026-09-24 R3 safety/determinism audit

- Current ROM main telephony process is an ActivityManager `*PERS*` UID-1001 `com.android.phone`; no independent init service exists.
- Same-ROM historical evidence confirms one exact-PID TERM causes immediate ActivityManager recreation and fresh Phone[0/1], ANM, NRM, QtiSST and DNC construction.
- Force-stop is rejected because it adds package stopped-state semantics. R3 is one exact UID-1001/radio-domain PID TERM with no retry or escalation.
- R3_READY is a 120-second state gate requiring fresh construction markers, stable mapping/UICC/MMTEL/provider bindings, unchanged vendor PIDs, clean native ownership and stable environment.
- Computer B CRLF checkout of the frozen v2.6.2 was repaired with a path-specific LF attribute; the resulting bytes match historical SHA-256 `445752BB49FB487850D0B1A1EFF4F0AA29D58C363C3A86E75BAA841E4CC08F75`.
- PS5.1 parser and STATIC_NO_ADB checks pass. Audit phone writes 0.

NEXT_ACTION: commit/push the audited runner, then use the one authorized reboot to establish CONTROL_A0 before any R3 process signal.

## 2026-09-24 R3 controlled run stopped at Cycle 2 pre-R3

- Cycle 1: valid PASS; phone 3472 -> 17402; R3_READY PASS; SIM OFF/ON 1/1; M1-M7 complete; WFC healthy.
- Cycle 2: fixed R0 restored native clean ownership, but the runner rejected retained IWLAN/preferred framework fields before executing the phone restart.
- No Cycle-2 phone TERM, P, SIM cycle or recovery ran. Cycle 3 was not run.
- Classification: `ABORTED_PRE_R3_INVALID_INTERMEDIATE_GATE_CYCLE_2`; R3 sufficiency remains inconclusive.

NEXT_ACTION: preserve the current clean-native/F1 scene. Do not patch and resume this series. A separately approved new series must correct the pre-R3 gate definition first.

## 2026-09-24 R3 gate correction ready

- Old series remains Cycle 1 valid PASS / Cycle 2 aborted pre-R3.
- New isolated series: `experiment/reset-boundary-r3/runs/r3_3cycle_v2/`.
- Gate order is now R0 native-only -> exact phone TERM -> full R3 framework readiness.
- PS5.1 and STATIC_NO_ADB audits pass; phone writes for this correction are zero.

NEXT_ACTION: use the one authorized reboot for CONTROL_A0_V2, then execute three identical cycles without reboot or adaptive recovery.

## 2026-09-24 R3 v2 falsified at Cycle 1

- CONTROL_A0_V2 captured after the single authorized reboot.
- R0_NATIVE_READY PASS; exact phone TERM 3425 -> 17756; R3_FRAMEWORK_READY PASS.
- Fixed P failed canonicality: no ANM IMS->IWLAN; NRM reported IWLAN NOT_REG_OR_SEARCHING; final PS/WLAN UNKNOWN and preferred=false.
- v2.6.2 was not invoked; SIM OFF/ON 0/0; cycles 2/3 not run.
- Result: `R3_FALSIFIED_AT_CYCLE=1`, first missing milestone M1.

NEXT_ACTION: no further phone action in this scene. A new reset boundary requires a new design and explicit authorization.

## 2026-09-24 boot-equivalent reset-boundary analysis

- Preserved the valid result `R3_FALSIFIED_AT_CYCLE=1` without reclassification.
- Built the current-ROM dependency graph from X55/PM and qcrild2 DataModule/IIWlan through qtidataservices QNS/IWLAN/CNE to Phone/ANM/NRM/SST/DNC and IMS.
- R3 recreated the framework consumer epoch and even caused QNS/NetworkService bound-Service creation in the unchanged qtidataservices PID, but did not recreate qcrild2 DataModule/DSD/NAH, qtidataservices process/static HIDL state, cnd, or vendor IMS epochs.
- H2 is supported only as a falsifiable generation/order hypothesis. There is no proof of a stale callback ID or failed Binder cleanup.
- The earliest preserved producer boundary is qcrild2 `IIWlan/slot2` / DataModule / DSD / NAH. Recommended R4a order is fixed R0 -> one verified qcrild2 restart -> native-provider readiness -> exact R3 -> A_READY -> unchanged P/v2.6.2.
- R4b additionally recreates qtidataservices; R4c recreates the broader boot-like telephony userspace producer stack. Neither is authorized for execution by this checkpoint.
- Reports: `experiment/reset-boundary-r4-analysis/`. Host-only analysis; ADB not used; phone writes 0.

NEXT_ACTION: separately audit and authorize R4a before any phone action. Freeze provider-first order and fail closed; a valid failed cycle falsifies R4a with no adaptive enlargement.

## 2026-09-24 R4a implementation frozen before device writes

- Confirmed that R4a uses the same verified init primitive as historical qcrild2 tests: one `ctl.restart vendor.qcrild2`. It is not a new low-level reset.
- The distinct hypothesis is fixed ordering: R0 native clean -> qcrild2 process epoch -> producer readiness -> exact R3 -> fixed P/v2.6.2.
- PRODUCER_READY requires old PID gone, new exact PID, cold DataModule and NAH markers, IIWlan/slot2, DSD/WDS ready, modem/IWLAN capability, live qtidataservices services, clean PM/X55 and stable samples.
- Modem-side endpoint teardown, callback IDs and internal object addresses remain explicitly unobservable.
- PS5 parser, R3 default-state-machine regression, fixed-order audit, one-restart ceiling and STATIC_NO_ADB checks pass.
- Audit-phase phone writes 0. A read-only current IIWlan dump was captured host-only to validate actual ROM field names.

NEXT_ACTION: use the separately authorized one reboot to establish CONTROL_A0_R4A, then run the frozen R4a series and stop at the first terminal failure.

## 2026-09-24 R4a v1 aborted at invalid producer evidence gate

- CONTROL_A0_R4A used the single authorized reboot and passed environment/F1/native gates.
- R0_NATIVE_READY passed without write. One exact qcrild2 restart changed PID 1988 -> 19229 while qcrild 1960, qtidataservices 3241, phone 3348 and pm-service 1239 stayed unchanged.
- IIWlan, DSD/WDS, IWLAN capability, modem capability and Java provider-service gates passed.
- Runner timed out because it searched logcat only for cold DataModule/NAH markers.
- Immediate read-only IIWlan history proves `performDataModuleInitialization` at 20:08:05.057 and `[NAH]constructor` at 20:08:05.453, inside the fixed window.
- Classification: `ABORTED_PRE_R3_INVALID_PRODUCER_EVIDENCE_GATE`, not R4a or producer falsification. R3/P/v2.6.2/SIM did not run; cycles 2/3 did not run.
- Phone write actions: reboot, airplane disable, Wi-Fi enable, one qcrild2 restart = 4.

NEXT_ACTION: preserve the clean airplane-OFF F1 scene. A corrected evidence adapter requires a separately authorized v2 series and new reboot baseline; do not resume v1 or escalate to R4b.

## 2026-09-24 R4a v2 evidence adapter ready

- User authorized a new independent `r4a_3cycle_v2` series and one reboot baseline.
- Only the producer evidence adapter changed: cold DataModule/NAH evidence is now accepted from the bounded union of logcat and timestamped IIWlan debug history.
- Current-restart device time is the lower bound; pre-restart IIWlan history is captured and identical historical lines are rejected.
- Every readiness field records source, raw evidence, timestamp and pass/fail in a host-only evidence manifest.
- Reset primitive/count/order, R3, A/P gates, timeout, v2.6.2 hash, SIM budget and health predicate are unchanged.
- PS5 parse, state-machine order, max-one restart, no-fallback, run-name binding and static no-phone-write audits passed.

NEXT_ACTION: checkpoint this frozen adapter, then use the single authorized reboot to establish `CONTROL_A0_R4A_V2` and execute the unchanged three-cycle v2 runner fail-closed.

## 2026-09-24 R4a v2 valid counterexample

- The one authorized reboot established `CONTROL_A0_R4A_V2` in F1 with all environment/native gates passing.
- Cycle 1: producer qcrild2 1875 -> 15426, phone 3466 -> 24403, qtidataservices 3373 unchanged, P canonical, M1-M7 complete, WFC HEALTHY after one SIM cycle.
- Cycle 2: fixed R0 normalized prior frozen ownership; R4a producer qcrild2 5785 -> 8932 passed; phone 24403 -> 19318 passed; qtidataservices remained 3373.
- Cycle 2 fixed P failed: Unknown/UNKNOWN/UNKNOWN/preferred=false. v2.6.2 and SIM cycle were not run. Cycle 3 was not run.
- Classification: `R4A_FALSIFIED_AT_P`, `FIRST_MISSING_MILESTONE=M1`.
- Old phone PID 24403 received fresh IMS->IWLAN before R3; new PID 19318 received no replay after R3. NRM was NOT_REG_OR_SEARCHING and SST consumed that negative result.
- No adaptive action or post-failure phone write occurred.

NEXT_ACTION: preserve the Cycle 2 P scene. R4b is eligible for static design around the qtidataservices/QNS provider epoch, but is not authorized for execution.

## 2026-09-24 R4b provider-lifecycle static design complete

- R4a remains frozen as `R4A_FALSIFIED_AT_P`, first missing milestone M1.
- Current-ROM read-only inventory confirms `.qtidataservices` is a zygote child/persistent ActivityManager process, not an init service. It uses shared UID 10104 and hosts QNS, IWLAN NetworkService/DataService, CneApp and CACertService for both slots.
- Current IWlanService APK inspection proves that a new slot provider actively calls `getAllQualifiedNetworks`, processes the response with `updateQualifiedNetworks`, and then registers for qualified-network changes.
- A process-cold epoch resets static IWlanProxy instances, production HIDL callbacks, registrants, request state and all co-hosted Java providers. Service rebind alone is incomplete.
- Minimum verified complete primitive for a future series is one exact verified PID TERM followed by ActivityManager persistent-process recreation. It was not executed.
- Frozen R4b dependency order is R0 -> qcrild2 producer -> PRODUCER_READY -> qtidataservices provider -> PROVIDER_READY -> exact R3 consumer -> A_READY -> fixed P -> unchanged v2.6.2 only after P passes.
- Reports: `experiment/reset-boundary-r4b-analysis/`. This phase used only read-only device inspection and host APK analysis. Phone writes 0.

NEXT_ACTION: preserve the Cycle 2 scene. R4b execution requires separate explicit authorization, a fresh one-reboot baseline and an implementation/static audit; do not run the designed primitive now.

## 2026-09-24 R4b v1 aborted in provider evidence adapter

- The authorized `CONTROL_A0_R4B_V1` reboot baseline passed.
- Cycle 1 R0 and PRODUCER_READY passed; qcrild2 changed `1980 -> 14590`.
- Exactly one audited `.qtidataservices` TERM changed PID `3366 -> 23798`.
- The PS5.1 evidence adapter then raised `PropertyNotFoundStrict` on scalar `.Count` before `PROVIDER_READY` could be decided.
- R3, A, P, v2.6.2, SIM cycle and M1-M7 were not run. Cycles 2/3 were not run. R4b/H3 was not falsified.
- Read-only freeze confirmed native-clean X55/PM state and F1. The scalar handling was corrected and statically audited only; no rerun occurred.

NEXT_ACTION: stop and preserve. A corrected device series needs a separate explicit authorization and a new baseline; never resume `r4b_3cycle_v1`.

## 2026-09-24 R4b v2 valid P counterexample

- A new one-reboot `CONTROL_A0_R4B_V2` baseline passed; v1 was not resumed.
- Cycle 1 producer qcrild2 `1961 -> 14682`, provider qtidataservices `3385 -> 23859`, and phone consumer `3448 -> 27795` all passed their frozen readiness gates.
- Provider response serial 0 was processed; at the time this checkpoint was written, a retained IMS EUTRAN/IWLAN history line was misclassified as contemporaneous cache state. Later target-native analysis proves the replacement handler's current caches were empty.
- Fixed P ended Unknown/UNKNOWN/UNKNOWN/preferred=false with no M1. v2.6.2 and SIM cycle did not run; Cycles 2/3 did not run.
- Classification: `R4B_FALSIFIED_AT_P`, `R4B_FALSIFIED_AT_CYCLE=1`, `FIRST_MISSING_MILESTONE=M1`.
- At this checkpoint the earliest interval was placed after serial 0; later native analysis moves it earlier to replacement-NAH population/publication. No workaround or adaptive action followed.

NEXT_ACTION: stop and preserve the P-failure scene. Do not add periodic QNS re-report, forced IMS/IWLAN, callback injection or another reset to this run.

## 2026-09-24 R4b order/callback counterexample analysis

- Frozen classification remains `R4B_FALSIFIED_AT_P`, Cycle 1, first missing M1.
- Target `framework.jar` confirms slot-keyed providers, existing-provider early return, callback-local cache replay, and remove-all-on-unbind.
- R4b's old phone owned the first callback, but new phone PID 27795 caused a fresh QNS Service, fresh slot1 provider, fresh callback and query serial 6. No `already existed` branch blocked it.
- Retained QNS debug history proves both serial 0 and serial 6 responses had zero QualifiedNetworks entries. The former `QUERY_RESPONSE_VALID` label meant response completion, not a non-empty payload.
- This checkpoint's claimed native-cache/GET mismatch is superseded: the IMS line was old-generation history, while current NAH state and GET were both empty. Specific `STALE_PROVIDER_CALLBACK_EPOCH` remains unsupported.
- Boot is consumer-driven provider construction: qtidataservices host starts first, then phone/ANM bind causes per-slot provider creation.
- Reports: `experiment/reset-boundary-r4b-analysis/{R4B_ORDER_COUNTEREXAMPLE_ANALYSIS,QNS_PROVIDER_CALLBACK_LIFECYCLE,BOOT_PROVIDER_CONSUMER_ORDER,NEXT_RESET_ORDER_CANDIDATES}.md`.
- Phone writes: 0.

NEXT_ACTION: static/read-only trace of native `IIWlan::getAllQualifiedNetworks` response construction versus `NetworkAvailabilityHandler::dumpCache`. Do not execute ORDER-B or R4c yet.

## 2026-09-24 native qualified-network boundary correction

- Target `/vendor/lib64/libril-qc-hal-qmi.so` proves `getAllQualifiedNetworks` directly copies `NetworkAvailabilityHandler`'s `LastReportedNetworkAvailability` container. Current dump and GET use the same data structure; there is no second query cache or GET filtering pass.
- R4b's retained IMS `[EUTRAN,IWLAN]` line belonged to the prior NAH generation in a process-level history buffer. After the new qtidataservices callback connected, `initializeIWLAN()` constructed a replacement NAH whose live working and last-reported caches were empty.
- Serial 0 was accepted before the replacement constructor and handled 24 ms after it. Its zero-entry response was correct. Serial 6 was also zero because no later current-generation publication was observed.
- Callback death clears response functions but does not call `iwlanDisabled`; explicit disable was not observed. The new enable handshake itself replaced the NAH.
- Frozen result remains `R4B_FALSIFIED_AT_P`, Cycle 1, first missing M1. H5 separate-cache mismatch is falsified; the surviving boundary is current-generation DSD/profile/NAH population and publication readiness.
- Reports: `experiment/native-qualified-network-boundary/`. Phone writes 0.

NEXT_ACTION: no reset. Design a separately authorized gate-only validation requiring current-generation live IMS cache, non-empty LastReported state and matching non-empty GET before R3/P. Do not execute R4c.

## 2026-09-24 R4b publication-gated v3 implementation

- User authorized a new independent `r4b_3cycle_v3` series and one reboot baseline.
- Reset order, reset counts, 120-second timeouts, fixed P, v2.6.2 hash, SIM cycle and health predicate remain unchanged.
- New pre-R3 gate binds to the latest post-qtidataservices NAH constructor and requires ten stable live samples with working IMS/EUTRAN plus LastReported IMS/EUTRAN. Old LocalLog history is rejected and no GET is injected.
- New post-R3 gate requires the same NAH generation, a natural fresh-provider serial newer than R3, a matched non-empty IMS response and normal QNS processing.
- PS5.1 parser/order/hash/no-write static audit passes. Static-phase phone writes 0.

NEXT_ACTION: establish the one authorized `CONTROL_A0_R4B_V3` reboot baseline, then execute the frozen v3 runner once and stop at the first valid failure.

## 2026-09-24 R4b v3 pre-gate observer abort

- `CONTROL_A0_R4B_V3` used the one authorized reboot and captured F1.
- Cycle 1 R0 passed; qcrild2 `1966 -> 14018` and qtidataservices `3348 -> 22991` each consumed exactly one authorized reset.
- The inherited v2 provider observer reached nine stable samples, then one-shot creation lines rolled out of its logcat evidence window and it timed out before `NATIVE_PUBLICATION_READY` ran.
- R3, P, v2.6.2, SIM cycle and Cycles 2/3 did not run. Phone remained PID 3423. No adaptive phone action followed.
- Latest NAH generation was 22:53:48.139; its live working and LastReported caches were empty more than 120 seconds later. This supports CASE 1 but cannot be promoted to a valid gate result because the new gate did not continuously adjudicate it.
- Classification: `ABORTED_PRE_NATIVE_PUBLICATION_GATE_LEGACY_PROVIDER_OBSERVER`; publication-gated candidate NOT TESTED / NOT FALSIFIED.
- A static-only `-EpochOnly` correction now leaves publication judgment solely to `NATIVE_PUBLICATION_READY`; it has not been run.
- Total phone writes/actions: 5.

NEXT_ACTION: stop and preserve. Do not resume v3, repeat a reset, or claim `NATIVE_PUBLICATION_NOT_READY`. Any corrected independent series requires a new explicit reboot authorization.

## 2026-09-24 R4b publication-gated v4 authorized

- v3 remains frozen as an invalid pre-gate observer abort.
- User authorized a new independent `r4b_3cycle_v4` series and exactly one reboot baseline.
- In `-EpochOnly` mode the inherited observer now proves only the qtidataservices PID epoch; transient service/query logs cannot PASS/FAIL publication or abort the lifecycle test.
- Dedicated publication timeout is anchored to the latest replacement NAH constructor G and remains exactly 120 seconds.
- Live working/LastReported cache samples and full native/DSD/qualification telemetry are retained host-only. No GET is injected.
- Static audit passes; phone writes for v4 remain 0 before baseline.

NEXT_ACTION: establish `CONTROL_A0_R4B_V4`, then run the v4 series once and stop at the first legal terminal classification.

## 2026-09-24 R4b v4 valid native-publication counterexample

- The independent v4 baseline used its one authorized reboot and captured airplane-OFF F1.
- Cycle 1 R0 passed; qcrild2 `1902 -> 14900` and qtidataservices `3303 -> 23716` each used exactly one frozen reset.
- Dedicated gate bound to replacement NAH generation `23:17:41.938` and its exact G+120 deadline.
- Across 39 samples, live current working IMS and LastReported IMS were absent 39/39; `globalPrefSys=UNKNOWN`; qcrild2/provider PIDs and X55/crash/PM ownership remained stable and clean.
- DSD/WDS/IWLAN/modem capability flags were ready, and framework NRM reported slot1 PS/WLAN HOME, but no current-generation NAH cache update or IMS publication occurred.
- Legal classification: `NATIVE_PUBLICATION_NOT_READY`; `FAIL_STAGE=INITIALIZE_IWLAN_TO_NAH_PUBLICATION`.
- R3, P, v2.6.2, SIM cycle and Cycles 2/3 did not run. Phone actions total 5; no adaptive action followed.

NEXT_ACTION: preserve the F1 scene. Perform read-only analysis of initializeIWLAN -> DSD/NAH input subscription/replay -> first working qualification -> LastReported publication. Do not expand to R4c.

## 2026-09-25 R_BIG_V1 five-cycle series stopped before candidate execution

- Exactly one reboot established CONTROL_A0 with pm-service native ownership, X55 ONLINE/crash zero, and expected airplane-OFF F1.
- Cycle 1 passed fixed P and the unchanged hash-locked v2.6.2 path. One SIM OFF/ON restored REGISTERED/WLAN and WFC in approximately 11 seconds; FREEZE retained holder PID 22768.
- Cycle 2 sent one identity-gated TERM to that holder. The holder exited and kernel X55 became OFFLINE with no owner and crash count zero, but the vendor peripheral property remained ONLINE through the frozen 20-second gate.
- The runner stopped at `HOLDER_RELEASE_NATIVE_OFFLINE_FAIL` before qcrild2 restart, P, v2.6.2, or any Cycle 2 SIM action.
- Cycles 3-5 and R_BIG_V1 were not run. The upper-bound candidate is NOT TESTED / NOT FALSIFIED; three-rescue support was not achieved.

NEXT_ACTION: preserve the stopped airplane-OFF F1 scene. Do not resume this series or execute an adaptive repair. A future experiment must separately decide whether the vendor/kernel OFFLINE disagreement is a stale observation or a required lifecycle condition.

## 2026-09-25 R_BIG_V1.1 gate correction and real Cycle 2 failure

- A separate V1.1 series changed only the holder-release hard gate: owner none + kernel X55 OFFLINE + crash zero. Vendor peripheral state remained telemetry only.
- The corrected gate passed with vendor ONLINE at release. One qcrild2 restart then changed `1964 -> 24725`, pm-service 24465 became sole owner, and kernel/vendor X55 naturally returned ONLINE with crash zero. The old vendor requirement was therefore an orchestrator gate defect.
- Cycle 1 passed WFC in approximately 8 seconds. Cycle 2 native normalization and fixed P passed.
- Cycle 2 unchanged v2.6.2 created a new PON_SUCCESS and used one SIM cycle, but produced no CNE request and no WFC within 30 seconds. Its unchanged failure cleanup retained holder 27699 because pm-service did not take ownership.
- The series stopped at `CYCLE2_V262_WFC_NO_CNE_REQUEST`. Cycles 3-5 and R_BIG_V1.1 were not run, so the upper-bound candidate is NOT TESTED / NOT FALSIFIED.

NEXT_ACTION: preserve the final airplane-ON F1 scene. Do not resume, clean up, or claim an R_BIG verdict without a new explicit experiment.

## 2026-09-25 Phase 1.5 profiling methodology audit

- Golden 6/6 per-run raw isub evidence is not repository-retained; W0/W1 snapshots omit protected-slot0 fields and later successes are aggregate-only.
- Repository continuity instead records single-SIM/slot0 ABSENT from 2026-09-20 through the golden period. The prior claim that the profiling run had a different physical start state is withdrawn.
- The 46-51 second snapshots and 38-41 second logcat scans were already in the golden preflight. Stopwatch instrumentation measured them; it did not add those calls. Their wall-clock delay can still perturb asynchronous recovery.
- `coreExit=30` means cleanup was not verified. A later wrapper health probe can observe WFC, but strong health alone does not prove a supported native freeze invariant.
- No recovery, timeout, slot0 contract, wait, mutation, or instrumentation code changed. Phone writes 0; ADB not used.

NEXT_ACTION: implement a separately reviewed low-perturbation profiling-only collector and prove offline classifier equivalence before any further phone-write run. Keep timeout accounting and exit-30 classification as separate future experiments.

## 2026-09-25 Phase 1.6 offline lightweight classifier complete

- Added isolated lightweight collector/classifier components; they are not connected to preflight or any recovery mutation path.
- Offline suite: 17 fixtures, 14 exact-equivalent, 3 more conservative, 0 unsafe old FAIL/UNKNOWN -> new PASS, 0 expected-result mismatches.
- Required fields include timestamps/epoch, fixed target, holder identity/fd9, exact native ownership, pm-service init/ps/exe identity, both QCRIL identities, X55/crash, current CNE IDs, and four-field health.
- Full logcat/dumpsys evidence remains available only as future failure/UNKNOWN diagnostics.
- PS5.1 parser and runtime suite pass. Phone writes 0; ADB not used.

NEXT_ACTION: review Phase 1.6. If approved, run one read-only collector benchmark only; do not connect the classifier to a write path or run recovery.
