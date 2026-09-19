# VOXI WFC Autopilot Rules

## Goal

Find, explain, and validate a minimal software-only recovery for VOXI Wi-Fi Calling on this Xiaomi 14 Pro without rebooting or physically removing the SIM. Final success requires 3/3 identical recovery cycles, no slot0 damage, and one-click status/recovery tooling.

## Fixed Device Mapping

- slot0 / phoneId0: China Telecom, subId=1, MCCMNC=46011, carrierId=2237.
- slot1 / phoneId1: VOXI, subId=11, MCCMNC=23415, carrierId=28.
- Writes must never accept arbitrary subId, slotId, or phoneId. Targets are compile-time fixed.

## GOLDEN_STRONG

All must be true:

- IMS registration state is REGISTERED (raw 2).
- IMS registration transport is WLAN (raw 2).
- MMTEL VOICE over IWLAN is available.
- Wi-Fi Calling is available for subId 11.

Supporting evidence, not hard health requirements: IMS IWLAN NetworkAgent, VOICE/IWLAN capable, MMTEL READY, active qti.cne IMS request, UDP/4500 keepalive, XFRM tunnel, PS/WLAN HOME, and IWLAN preferred.

## Failure Classes

- F0: GOLDEN_STRONG.
- F1: IMS_NOT_REGISTERED.
- F2: IMS_REGISTERING_STUCK.
- F3: IMS_WRONG_TRANSPORT.
- F4: MMTEL_VOICE_UNAVAILABLE.
- F5: WFC_AVAILABILITY_FALSE.
- F6: IMS_NETWORK_REQUEST_MISSING, only when direct IMS/WFC core health is also abnormal.
- F7: EPDG_DATA_PATH_MISSING.
- F8: FRAMEWORK_REBUILD_INCOMPLETE.
- F9: UNKNOWN.

## Level 0: Automatic Read-Only Work

Allowed without further approval: dumpsys/getprop/logcat/proc/service/package reads, read-only Binder/framework/root helpers, decompilation and binary inspection, local scripts and builds, pushing read-only helpers, state comparisons, and Golden/Failure analysis.

## Level 1: Pre-authorized Reversible Experiments

Allowed only after the safety gate passes and static scope is confirmed:

- Fixed call `ISub.setUiccApplicationsEnabled(false, 11)` for fault injection.
- Fixed call `ISub.setUiccApplicationsEnabled(true, 11)` only if runtime evidence shows UICC apps remain disabled.
- `ITelephony.resetIms(1)` only after current-ROM proof that 1 is slotId 1 and the call cannot widen to all slots or alter slot0 subscription.
- slot-scoped `disableIms(1)` / `enableIms(1)` only after static proof, and not as the first recovery attempt.
- A reversible subId11 WFC-setting nudge only after snapshot, exact rollback proof, and static evidence that it targets the relevant failure layer.

## Mandatory Safety Gate Before Every Level 1 Write

Confirm all:

- VOXI subId=11, slot=1, phoneId=1, carrierId=28, MCC=234, MNC=15.
- slot0 subId is not 11.
- slot0 is China Telecom subId=1 MCCMNC=46011.
- The helper has fixed targets and accepts no arbitrary target identifiers.

Any mismatch means ABORT WRITE and return to read-only analysis.

## Write Budget

- MAX_FAULT_INJECTIONS=4.
- MAX_LEVEL1_WRITE_EXPERIMENTS=10.
- Do not repeat an identical failed operation more than twice unless the environment or hypothesis materially changes.
- Log time, API/command, arguments, pre-state, return/exception, post-state, outcome, and slot0 impact in `autopilot/EXPERIMENTS.jsonl` and `autopilot/COMMAND_AUDIT.log`.

## Level 2: Escalation Required

Do not automatically kill/restart phone, IMS, qcrild, IWLAN, or CNE processes/services; force-stop system packages; change radio power, airplane mode, SIM state, default data SIM, APN, CarrierConfig, or databases. If all Level 0/1 routes are exhausted and one is uniquely justified, record `WRITE_ESCALATION_REQUIRED` and stop.

## Level 3: Absolutely Forbidden

Never make SELinux permissive, modify sepolicy/EFS/NV/QCN/persist/baseband/firmware/SIM/eSIM/system APK/framework/boot/vendor_boot, clear telephony databases, factory reset, or change China Telecom slot0 configuration.

## Experiment Discipline

- Preserve valuable failure scenes before recovery.
- Every candidate must first be documented in `autopilot/RECOVERY_CANDIDATES.md` with target layer, evidence, effect, scope, level, rollback, success, and failure signals.
- Recovery success requires GOLDEN_STRONG, not IWLAN HOME or MMTEL READY alone.
- Validate a successful identical recovery sequence in at least three complete fault/recovery cycles, each stable for at least 60 seconds.

## Stop Conditions

Continue autonomously until either `FINAL_GOAL=ACHIEVED` or a real HARD_BLOCKER: physical interaction is required; ADB cannot be restored automatically; Level 2/3 is required; unavailable user-only information is required; or all allowed recovery actions fail and further work raises risk.

## Resume Protocol

At every resume, read this file, `autopilot/AUTOPILOT_STATE.md`, and `autopilot/AUTOPILOT_FINDINGS.md`, then continue from `NEXT_ACTION`.
