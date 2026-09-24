# Fifth v2.7-alpha Device Run Result

Experiment ID: `X55-V27-ALPHA-FIFTH-DEVICE-005`

Date: 2026-09-24 08:49 Asia/Shanghai  
Computer/account: Computer A / Account A  
Tested commit: `13d2969acbfe6e43171929583f40b18ed4ceb361`  
PowerShell: `5.1.19041.6456`

## Authorization and preflight

The exact paired launcher selftest passed immediately before execution. The production artifact gate accepted the fixed single-SIM helper SHA-256 `90D6F55FBE1F941C1E3EEE1AA1F93B569FA3AE4084B93C5560082A38AAAF5C39` using the internal .NET SHA-256 implementation.

Fresh external entry checks passed for USB serial `fd0ff892`: root UID 0; device/fingerprint `cas`; Android 13; airplane mode on; `vendor.per_mgr` running; pm-service PID 31818, PPID 1, sole `/dev/subsys_esoc0` owner; X55 ONLINE; crash_count 0; all holder files absent; qcrild2 PID 873, PPID 1, exact `qcrild -c 2` identity. VOXI was active and UICC-enabled at slot 1 / phoneId 1 / subId 11 / carrierId 28 / MCCMNC 23415. Slot0 was absent.

Initial WFC state was strict F1: IMS NOT_REGISTERED, transport UNKNOWN, VOICE/IWLAN unavailable, WFC unavailable, IWLAN HOME/preferred, no qti.cne request, no UDP/4500, and no XFRM tunnel.

## State-machine result

The launcher was executed exactly once.

1. `stop vendor.per_mgr` succeeded. pm-service disappeared, owner became NONE, X55 became OFFLINE, and crash_count remained 0.
2. Holder startup succeeded. Windows holder PID was 5632; Android holder PID was 22129. The holder became the unique owner, X55 returned ONLINE, crash_count remained 0, and a new `PON_SUCCESS` was captured.
3. `start vendor.per_mgr` succeeded while the holder remained alive. New pm-service PID 22536 appeared.
4. The contention invariant failed: both holder PID 22129 and pm-service PID 22536 held `/dev/subsys_esoc0`. The design required the holder to remain the unique owner at this stage.
5. The script set `NATIVE_HANDOFF_RESULT=BEHAVIOR_CHANGED` and stopped before holder release, qcrild2 restart, deployment, or SIM cycle.

The fail-safe attempted its holder safety check but refused to send TERM because `Test-OwnedHolder` requires unique ownership and pm-service was now a co-owner. The host-side holder process was stopped, but Android holder PID 22129 and `/data/local/tmp/x55_v27_holder.pid` remained. No manual cleanup or recovery action was performed.

## Preserved failure scene

Final read-only capture after launcher exit:

- `vendor.per_mgr`: running
- pm-service: PID 22536, PPID 1
- qcrild2: unchanged PID 873; no restart occurred
- `/dev/subsys_esoc0`: dual owner, holder PID 22129 plus pm-service PID 22536
- X55: ONLINE
- crash_count: 0
- v2.7 holder PID file: present, value 22129
- IMS: NOT_REGISTERED
- transport: UNKNOWN
- VOICE/IWLAN: unavailable
- WFC: unavailable
- qti.cne request: absent
- UDP/4500: absent
- XFRM: absent
- SIM OFF/ON: 0/0

The filtered log contains direct server-side mechanism evidence:

```text
PerMgrSrv: QCRIL registered
PerMgrSrv: QCRIL voting for SDX55M
PerMgrSrv: SDX55M new state: going on-line
PerMgrSrv: SDX55M new state: is on-line
```

The script's four-line evidence gate still reports `REVOTE_MECHANISM_LOG=UNPROVEN` because the two required `PerMgrLib` registration/vote strings were absent. Server-side register/vote is directly observed; full bilateral evidence is not claimed.

## Result

```text
RECOVERY_RESULT=X55_REBIRTH_SUCCESS
NATIVE_HANDOFF_RESULT=BEHAVIOR_CHANGED
FINAL_WFC_RESULT=NOT_CHECKED
CLEANUP_RESULT=NOT_RUN
REVOTE_MECHANISM_LOG=UNPROVEN
PHONE_WRITE_ACTIONS=3
SIM_OFF_COUNT=0
SIM_ON_COUNT=0
```

This is not a v2.7 recovery success. The preserved dual-owner/holder scene must not be altered or retried without separate explicit authorization.

## Host-only evidence

Local directory: `C:\Users\ZJH\Desktop\platform-tools\voxi_wfc_local_runs\v27_alpha_native_handoff_20260924_084936`

- `experiment.log`: SHA-256 `E7CBDF4C4DEFF69BE70AB86CECBBE0DB169327354BDA6F443E77ABDC2B4FE349`
- `logcat_all.raw.txt`: 23404871 bytes, SHA-256 `EEEE4D1BB512254729271053A20A21CB88D9EF3DCBEF1A5EE9A7657C70B49282`
- `logcat_filtered_sanitized.txt`: 821064 bytes, SHA-256 `9C35667F38CC807461B2E98A2929C0F564F5FF338469630E62B1296417CCEDFA`
- `native_holder_plus_per_mgr.txt`: SHA-256 `37BAFAAD38CF9AB2CC40EC99FCC0715363B4ED141B41CE6B23A209315990C103`
- `pon_success_holder.txt`: SHA-256 `DE21571FCB2435FBD33D9E4A87EC0C93E430D3A732C97948DEB5FF33D6CA19BB`
- `post_abort_readonly.txt`: SHA-256 `F5026351DD2E6CAE070A5EC7E7FE6B78F5EDF67104BB6AF2E40D3B7E615DAA02`

Large logs remain host-only and are not committed.
