# ChatGPT to Codex Handoff

Updated: 2026-09-23 20:37 Asia/Shanghai

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

Labels: `DEVICE_CONFIRMED` was reproduced in this Codex/device session. `TRANSFERRED_VERIFIED` was verified in the cross-account handoff, but raw v2.6.2 artifacts still need import.

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
