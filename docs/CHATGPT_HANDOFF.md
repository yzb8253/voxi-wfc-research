# ChatGPT to Codex Handoff

Updated: 2026-09-23 16:10 Asia/Shanghai

## Session identity

- Computer: Computer A
- Account: Account A
- Branch: `voxi-wfc-auto-recovery`
- Synchronized baseline before the latest experiment: `56bd01aff49b79ba3bd751ad5939ce8d37c8a8e7`
- Current commit: resolve with `git rev-parse HEAD`; this file is authoritative from its containing commit.
- GitHub is the only durable source of truth.

## Device / ADB

- Windows; ADB `C:\Users\ZJH\Desktop\platform-tools\adb.exe`
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

- `X55-OWNERSHIP-HANDOFF-001`: `ABORTED_BEFORE_CONTENDED_PHASE / INCONCLUSIVE`.
- A new independent probe passed its direct entry gate under enforcing SELinux. Correctly quoted root reads verified pm-service PID 13288 as sole FD9 owner, X55 ONLINE, crash_count 0, no holder, and qcrild2 PID 13706.
- per_mgr was stopped once and a fixed holder was started. Android holder PID 31163 became the sole node owner and X55 became ONLINE.
- Before per_mgr could be started under holder contention, a PowerShell `$Pid`/`$PID` name collision aborted the run. The probe source is corrected but has not been rerun.
- Fail-safe cleanup TERM'd only the owned holder and restarted per_mgr. Current preserved scene: per_mgr running as PID 31818, no `/dev/subsys_esoc0` owner, X55 OFFLINE, crash_count 0, holder absent, qcrild2 unchanged at PID 13706.
- Holder-plus-pm-service contention and qcrild2 re-vote were not tested. Phone-write count: 5. Never reuse recorded PIDs.

## Unique next action

Preserve the current per_mgr-running/no-owner/X55-OFFLINE scene. Do not rerun the probe or restart qcrild2 automatically. A new explicit recovery or experiment decision is required.

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
