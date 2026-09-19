# M3 Modem SSR Controlled Test — Static Gate Stop

Date: 2026-09-18 (Asia/Shanghai)  
Device: Xiaomi 14 Pro (`23116PN5BC`)  
ADB target: `192.168.1.25:41201`  
Execution status: **NOT EXECUTED**

## Outcome

The mandatory static safety gate failed before any modem write.

The external modem was positively identified as `esoc0` at:

`/sys/devices/platform/soc/soc:qcom,mdm0/subsys10`

Its state was `ONLINE`, restart level was `RELATED`, crash count was `0`, the platform driver was `ext-mdm`, and the subsystem bus was `msm_subsys`.

The kernel has both `CONFIG_MSM_SUBSYSTEM_RESTART=y` and `CONFIG_DEBUG_FS=y`, but the standard Qualcomm SSR debugfs control directory `/sys/kernel/debug/msm_subsys` was absent. Consequently, the expected one-shot control file `/sys/kernel/debug/msm_subsys/esoc0` was also absent.

`restart_level` was not treated as a trigger: it only configures the restart scope. `/dev/subsys_esoc0` was not treated as a trigger because its file operations implement subsystem get/put on open/close. `/dev/esoc-0` was not used because it is an ESOC ioctl control-link device and this ROM exposes no verified userspace contract proving that any guessed ioctl or command performs exactly one standard SSR rather than a different power/debug/error path.

The user protocol explicitly required STOP if the detected interface was not a confirmed standard SSR entry. No fallback trigger was guessed.

## Preserved state

- Modem remained `ONLINE`.
- AP boot ID remained `8034952d-9ad8-4ccd-930a-c595cd7bcab4`; no AP reboot occurred.
- Primary qcrild PID remained `9201`.
- Target qcrild2 PID remained `8330`.
- VOXI remained ACTIVE, UICC ENABLED, strict F1.
- Slot0 mapping remained subId 1 / slot 0 / carrierId 2237 / MCCMNC 46011, gate PASS.
- `wlan0` and `tun0` remained up with their routes present.

## Safety accounting

- SSR count executed: **0**
- Modem-facing writes: **0**
- AP reboot: **NO**
- Prohibited actions: **NONE**

Because M3 was not executed, `M3_MODEM_SSR_RECOVERY` cannot truthfully be classified PASS or FAIL. The correct result is **NOT TESTED — STATIC GATE STOP**. The prior conclusion that a full AP reboot is the only *proven* recovery remains unchanged, but this run does not prove that modem SSR would fail.
