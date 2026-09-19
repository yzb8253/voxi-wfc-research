# Recovery Candidates

No candidate is approved for execution yet. Every candidate requires a passing safety gate and current-ROM static proof of scope before testing.

## Candidate 1: CNE IMS Demand Re-request

- Target layer: the missing `com.qualcomm.qti.cne` IMS NetworkRequest for subId 11.
- Evidence: current-ROM CneApp code exposes the internal native-to-Java chain `requestNetwork(true, {rat,slot}) -> DataCallAgent.startDataCall -> ConnectivityManager.requestNetwork`; the strong Golden contains request 263 from qti.cne.
- Expected effect: recreate only the IMS demand that was released, allowing DNC-1/IWLAN to rebuild the IMS APN NetworkAgent and ePDG path.
- Scope: conceptually slot scoped, but no safe external/public invocation point has been found.
- Write level: undetermined; direct invocation of private native/HIDL control is not authorized.
- Rollback: matching internal unrequest would be required, which increases risk.
- Success signal: qti.cne IMS request for subId 11, IMS/IWLAN NetworkAgent, REGISTERED/WLAN, voice IWLAN available.
- Static validation: layer match is strong; callable interface and permission/scope proof are incomplete.
- Experiment status: not executable.

## Candidate 2: ITelephony.resetIms(1)

- Target layer: ImsResolver/IMS feature lifecycle for slot 1.
- Evidence: corrected current-ROM DEX analysis shows `PhoneInterfaceManager.resetIms(int)` enforces MODIFY permission, clears Binder identity, and invokes both `ImsResolver.disableIms(int)` and `enableIms(int)` in one call.
- Expected effect: slot 1 IMS registration disable/enable; whether this causes qti.cne to issue a fresh IMS demand remains experimental.
- Scope: source confirms the integer is a slotId. `ImsResolver` selects controllers for that slot, maps that slot to its subId, and calls the IMS service controller with `(slotId, subId)`.
- Write level: Level 1 only after static proof required by the autopilot policy.
- Qualcomm implementation: `org.codeaurora.ims.ImsService.disableIms(slotId)`/`enableIms(slotId)` select `ImsServiceSub` for the slot. `turnOffIms()` and `turnOnIms()` send registration-change requests to the IMS radio; turn-on also queries registration state after 1500 ms.
- Rollback: the reset operation itself contains the paired disable and enable; no separate manual rollback call is expected.
- Success signal: fresh qti.cne request and strong-Golden fingerprint, without slot0 lifecycle changes.
- Failure signal: feature READY returns but IMS demand/NetworkAgent remains absent.
- Static validation: passed for slot semantics and paired Qualcomm turn-off/turn-on chain. CNE re-request effect is unconfirmed.
- Helper dry-run: UID 0, ISub/ITelephony descriptors, target slot 1, and protected slot 0 gates all PASS.
- Experiment status: eligible as the first recovery candidate after a captured failure fingerprint.

## Candidate 3: Slot-Scoped disableIms(1) / enableIms(1)

- Target layer: IMS feature lifecycle.
- Evidence: methods exist in current-ROM ITelephony/PhoneInterfaceManager surfaces.
- Expected effect: remove and recreate slot 1 IMS features; CNE demand recreation is unproven.
- Scope: intended slot parameter, but implementation and side effects need current-ROM proof.
- Write level: Level 1, explicitly not the first candidate.
- Rollback: paired enable only after captured disable result and safety gate.
- Static validation: incomplete.
- Experiment status: prohibited pending proof.

## Candidate 4: Reversible VOXI WFC Setting Nudge

- Target layer: framework/vendor registration trigger while preserving subscription.
- Evidence: none yet that this ROM's setter triggers CNE native `requestNetwork(true, slot)` rather than only updating IMS configuration.
- Scope: potentially subId 11 only.
- Write level: Level 1 only with exact old-value snapshot, rollback, and static trigger evidence.
- Static validation: insufficient.
- Experiment status: prohibited.

## Candidate 5: Restart org.codeaurora.ims Once (Phase 8A)

- Target layer: Qualcomm IMS service/radio process lifecycle upstream of IMS registration, while leaving CNE/qtidataservices, Phone, UICC, radio, and network settings untouched.
- Preserved failure evidence: ACTIVE + UICC enabled + F1; MMTEL READY and PS/WLAN HOME; no qti.cne IMS request, UDP/4500, XFRM, direct IMS registration, VOICE/IWLAN, or WFC availability.
- Process scope proof: current PID 3184 is exactly `org.codeaurora.ims`, UID 10196, SELinux `u:r:vendor_qtelephony:s0:c196,c256,c512,c768`; it is distinct from `com.android.phone`, `.dataservices`, and `.qtidataservices` processes.
- Device/safety gate: serial fd0ff892 at `192.168.137.211:41111`; VOXI subId11/slot1/phoneId1/carrier28/MCCMNC23415; protected China Telecom subId1/slot0/carrier2237/MCCMNC46011; gate PASS.
- Allowed operation: one exact `kill 3184` (TERM) only after an immediate `/proc/3184/cmdline` and PID recheck. `kill -9` is reserved only if that exact process survives TERM; no fuzzy matching, force-stop, or other process restart.
- Expected effect: Android restarts and rebinds Qualcomm ImsService; the experiment tests whether that indirectly recreates native cnd/CNE IMS demand and the qti.cne NetworkRequest.
- Success signal: REGISTERED(2) + WLAN(2) + VOICE/IWLAN true + WFC true. New qti.cne request, UDP/4500, and XFRM are supporting evidence.
- Failure signal: target process restarts but remains strict F1 or no new qti.cne IMS request within 180 seconds.
- Slot0 observation: record any transient IMS loss and final protected mapping; never operate on slot0.
- Rollback: none required for a normally auto-restarted service process; no secondary recovery operation is authorized in this experiment.
- Experiment status: explicitly authorized for one execution in the preserved F1 scene.

## Candidate 6: Restart Shared CNE/qtidataservices Process Once (Phase 8B)

- Target layer: the missing native CNE callback/DataCallAgent IMS demand and the co-hosted Qualcomm IWLAN service lifecycle.
- Exact process: PID 3170, cmdline `.qtidataservices`, UID 10104, SELinux `u:r:vendor_qtidataservices_app:s0:c104,c256,c512,c768`.
- Ownership proof: ActivityManager shows `com.qualcomm.qti.cne/.CneApp` with `processName=.qtidataservices` in PID 3170. The same persistent process also hosts `vendor.qti.iwlan/.QualifiedNetworksServiceImpl`, `.IWlanNetworkService`, `.IWlanDataService`, and the CACert service.
- Excluded processes: PID 3125 `.dataservices` (radio UID), `org.codeaurora.ims`, `com.android.phone`, FlClash, and system_server are separate and must not be signaled.
- Preserved failure evidence: ACTIVE + UICC enabled + strict F1; no qti.cne IMS request, UDP/4500, or XFRM; MMTEL READY; wlan0 and tun0 UP.
- Safety gate: VOXI subId11/slot1/phoneId1/carrier28/MCCMNC23415 and protected China Telecom subId1/slot0/carrier2237/MCCMNC46011 all PASS.
- Allowed operation: one exact `kill -TERM 3170` after an immediate repeat of PID/cmdline/UID/SELinux and F1 gates. No fuzzy kill, force-stop, or second TERM.
- Expected effect: restart CneApp, reconnect NativeHalServerCallback, recreate DataCallAgent trackers, and rebind co-hosted IWLAN services; a new IMS NetworkRequest should then drive ePDG and IMS registration.
- Success signal: REGISTERED(2) + WLAN(2) + VOICE/IWLAN true + WFC true, stable for at least 60 seconds.
- Partial signal: new subId11 IMS request appears but ePDG/direct health does not.
- Failure signal: no new qti.cne IMS request by 120 seconds.
- Experiment status: explicitly authorized for one execution in the preserved F1 scene.

## Candidate 7: Restart Native cnd Once (Phase 8C Fast-Follow)

- Entry condition: Phase 8B failed with no qti.cne IMS request through 120 seconds; strict F1, protected slot0, wlan0, and tun0 remained unchanged.
- Exact init service: `vendor.cnd`.
- Exact binary: `/system/vendor/bin/cnd` (same inode exposed at `/vendor/bin/cnd`).
- Exact process: PID 1838, PPID 1, cmdline `/system/vendor/bin/cnd`, UID 1000, SELinux `u:r:vendor_cnd:s0`.
- Init definition: `/vendor/etc/init/cnd.rc`; class main, user system, groups system/wifi/inet/radio/wakelock/net_admin; no `oneshot` or modem/radio-stack service grouping.
- Scope determination: independent native CNE daemon supervised directly by init. It is not qcrild, a modem daemon, SSR, radio reset, or the full vendor radio stack.
- Allowed operation: one exact `kill -TERM 1838` after immediate PID/cmdline/UID/SELinux, strict-F1, slot0, wlan0, and tun0 checks.
- Expected effect: init restarts only native cnd; HIDL callback reconnect should cause CneApp/DataCallAgent to recreate slot1 IMS demand.
- Success signal: new qti.cne IMS request followed by REGISTERED(2), WLAN(2), VOICE/IWLAN true, and WFC true, stable for at least 60 seconds.
- Partial signal: new IMS request appears but ePDG/direct health does not.
- Failure signal: no new IMS request by 120 seconds.
- Experiment result: executed once after renewed explicit authorization. Init restarted cnd from PID1838 to PID909, but no CNE callback replay, qti.cne IMS request, ePDG/XFRM, or direct IMS/WFC recovery appeared through 120 seconds. Slot1 IWLAN/HOME fell to UNKNOWN; slot0 and the network/VPN environment remained protected. `CND_RESTART_RECOVERY=FAIL`; no further write was executed.

## Candidate 8: Coordinated cnd then CNE/IWLAN Restart (Phase 8D)

- Hypothesis: a fresh cnd must exist before CneApp starts so the Java side can register a new native callback and replay IMS demand.
- Sequence tested: one TERM of verified cnd PID909, wait for init to start PID7716, then one TERM of verified shared `.qtidataservices` PID25920, which restarted as PID7876.
- Rebuilt state: CneApp and all three IWLAN services rebound; generic qti.cne INTERNET and listener requests were recreated.
- Missing state: no observable native IMS callback replay, IMS NetworkRequest, DNC-1 IMS demand, ePDG/XFRM, or direct IMS/WFC recovery.
- Result: FAIL through 122.6 seconds. No partial criterion was reached; slot1 remained IWLAN UNKNOWN and not preferred.
- Protected scope: slot0 identity and wlan0/tun0/VPN/airplane environment remained intact.
- Experiment status: completed once; do not repeat in the unchanged environment.
