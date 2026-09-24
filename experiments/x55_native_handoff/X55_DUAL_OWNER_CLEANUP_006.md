# X55 Dual-Owner Holder Cleanup 006

Experiment ID: `X55-V27-DUAL-OWNER-CLEANUP-006`

Date: 2026-09-24 08:58-08:59 Asia/Shanghai

## Objective

Test only whether a strictly identified v2.7 holder can receive one TERM while holder and pm-service both own `/dev/subsys_esoc0`, leaving pm-service as the sole native owner without restarting qcrild2, per_mgr, radio, SIM, or the phone.

## Entry identity gate

All checks used fresh device reads:

- `/data/local/tmp/x55_v27_holder.pid`: exactly `22129`
- `/proc/22129`: present; root-owned `/system/bin/sh`
- cmdline: exact fifth-run holder command, including the v2.7 PID file, EXIT cleanup trap, FD9 open on `/dev/subsys_esoc0`, TERM trap, and sleep loop
- `/proc/22129/fd/9`: `/dev/subsys_esoc0`
- pre-owner set: holder PID 22129 plus pm-service PID 22536, exactly two owners
- pm-service: PPID 1, executable `/vendor/bin/pm-service`
- `vendor.per_mgr`: running
- X55: ONLINE
- crash_count: 0
- qcrild2: PID 873, PPID 1, exact `qcrild -c 2` identity

Result: `ENTRY_GATE=PASS`.

## Authorized action

At `2026-09-24T08:59:17.5243165+08:00`, exactly one command was sent:

```text
kill -TERM 22129
```

ADB returned exit code 0. No second TERM, SIGKILL, process/service restart, SIM action, or other recovery write occurred.

The intended per-second process probe had a shell quoting error, so it did not provide an exact exit second. After the 15-second observation window, direct read-only checks confirmed the final state.

## Result

- holder PID 22129: absent
- v2.7 holder PID file: absent; the holder EXIT trap removed it
- owner set: pm-service PID 22536 only
- pm-service: PPID 1, executable `/vendor/bin/pm-service`
- `vendor.per_mgr`: running
- X55: ONLINE
- crash_count: 0
- qcrild2: unchanged PID 873

WFC remained unchanged: IMS NOT_REGISTERED, transport UNKNOWN, VOICE/IWLAN unavailable, WFC unavailable, IWLAN HOME/preferred, no qti.cne request, no UDP/4500, and no XFRM tunnel.

```text
RESULT=MAKE_BEFORE_BREAK_NATIVE_HANDOFF_SUCCESS
ALIAS=DUAL_OWNER_BREAK_BEFORE_MAKE_HANDOFF_SUCCESS
PHONE_WRITE_ACTIONS=1
TERM_COUNT=1
```

The observed transition was holder + pm-service dual ownership, followed by safe holder release, followed by pm-service sole ownership with uninterrupted X55 ONLINE/crash_count 0. This validates the cleanup phenomenon only; it does not validate v2.7 WFC recovery.

## Host-only evidence

Directory: `C:\Users\ZJH\Desktop\platform-tools\voxi_wfc_local_runs\X55-V27-DUAL-OWNER-CLEANUP-006`

- `cleanup_before.txt`: SHA-256 `2C4E7C56E36DCE5316F753D11BFE47336D7B878C112F6F2FCCB1B4B8BA18A1E5`
- `cleanup_after.txt`: SHA-256 `E8C3DFE9B9EC68548CA08DB4E571B13372F0A50FF408B49F70566D6D4446ED47`
