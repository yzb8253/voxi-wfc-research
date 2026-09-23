# ChatGPT to Codex Handoff

Updated: 2026-09-23 15:30 Asia/Shanghai

## Session identity

- Computer: Computer A
- Account: Account A
- Branch: `voxi-wfc-auto-recovery`
- Synchronized baseline: `12ffbdf79d45b1b61ee67ae317a67b2608ffc5d9`
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

- Ownership handoff: `BLOCKED_PRE_WRITE / NOT_RUN`; latest precheck phone writes: 0.
- GitHub lacks the v2.5/v2.6.1/v2.6.2 source, holder, and owner observer.
- SELinux blocks direct pm-service FD and X55 state/crash_count reads.
- Last check 2026-09-23 15:06:53: pm-service 13288, pm-proxy 1699, qcrild 1926, qcrild2 13706, mdm_helper 1297; no holder PID file.
- VOXI identity correct, active, UICC apps enabled; IMS NOT_REGISTERED, transport UNKNOWN, VOICE/IWLAN and WFC unavailable (F1).
- China Telecom SIM absent; the installed v2.0 dual-SIM gate therefore reports UNSAFE.
- Native owner, X55 ONLINE, and crash_count are unverified. Never reuse recorded PIDs.

## Unique next action

Restore the exact v2.6.2 holder and read-only owner observer to GitHub, audit them, and repeat the read-only entry gate. Run the handoff only after owner, X55 ONLINE, no-holder, and `crash_count=0` all pass.

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
