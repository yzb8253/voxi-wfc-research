# v2.7-alpha First Device Run Result

Date: 2026-09-23 20:37 Asia/Shanghai

Computer: B

Account: A

Baseline commit: `1949b6f90572e2b7eee60963cab8b18fc6b07591`

## Result

`BLOCKED_PRE_WRITE_PS51_INCOMPATIBILITY`

The first authorized launch used the repository-provided entry point exactly once:

```text
Run-X55-WFC-v2.7-alpha-native-handoff.cmd execute
```

The launcher selected Windows PowerShell 5.1. The state machine failed before its first ADB call because `System.Diagnostics.ProcessStartInfo` in that runtime does not expose the `ArgumentList` property used by `Invoke-ProcessCapture`.

```text
ERROR=The property 'ArgumentList' cannot be found on this object.
RECOVERY_RESULT=NOT_RUN
NATIVE_HANDOFF_RESULT=NOT_RUN
FINAL_WFC_RESULT=NOT_CHECKED
CLEANUP_RESULT=NOT_RUN
REVOTE_MECHANISM_LOG=NOT_CHECKED
PHONE_WRITE_ACTIONS=0
```

The complete host log remains outside Git at:

```text
C:\Users\TT\Desktop\platform-tools\voxi_wfc_local_runs\v27_alpha_native_handoff_20260923_203708\experiment.log
```

## Independent read-only entry gate

The immediately preceding independent read-only gate passed:

- ADB serial `fd0ff892`, state `device`;
- root UID 0, Xiaomi `cas`;
- airplane mode ON and Wi-Fi connected;
- `vendor.per_mgr`, `vendor.per_proxy`, `vendor.qcrild`, `vendor.qcrild2`, and `vendor.mdm_helper` running;
- pm-service PID 31818, init parent, sole FD9 owner of `/dev/subsys_esoc0`;
- X55 ONLINE and crash_count 0;
- no known holder PID file;
- qcrild2 PID 873;
- VOXI slot1/phoneId1/subId11/carrierId28/MCCMNC23415, subscription active and UICC applications enabled;
- slot0 confirmed absent;
- initial WFC state F1.

The script's internal entry gate was not reached because the host-process wrapper failed first.

## Post-failure read-only verification

- pm-service PID: 31818, still sole FD9 owner;
- qcrild2 PID: 873, unchanged;
- X55: ONLINE;
- crash_count: 0;
- holder: never created;
- holder files: absent;
- SIM OFF count: 0;
- SIM ON count: 0;
- WFC: unchanged F1;
- phone writes: 0.

## Classification

```text
ENTRY_GATE_RESULT=PASS_INDEPENDENT_PRECHECK_SCRIPT_GATE_NOT_REACHED
RUN_CLASSIFICATION=BLOCKED_PRE_WRITE_PS51_INCOMPATIBILITY
RECOVERY_RESULT=NOT_RUN
NATIVE_HANDOFF_RESULT=NOT_RUN
FINAL_WFC_RESULT=NOT_CHECKED
CLEANUP_RESULT=NATIVE_UNCHANGED
PHONE_WRITES=0
```

No retry was performed. The host compatibility defect was subsequently repaired and accepted through a Windows PowerShell 5.1 local-only self-test, with phone writes 0. The repaired state machine has not been run against the phone and requires fresh authorization.
