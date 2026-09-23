# v2.7-alpha Fourth Device Run Result

- Experiment ID: `X55-V27-ALPHA-FOURTH-DEVICE-004`
- Date: 2026-09-23 21:48:13 Asia/Shanghai
- Computer: B
- Account: A
- Commit tested: `12e59b9b78589657f3f62938b957ba73ff9ee183`
- Windows PowerShell: `5.1.19041.6456`

## Classification

`BLOCKED_PRE_WRITE_PS51_FILEHASH_RESOLUTION`

This is not an X55 rebirth, native-handoff, or WFC recovery result. The launcher stopped at the local artifact hash operation before logcat startup or any phone write.

## Fresh precheck

- ADB serial `fd0ff892`, authorized and rooted
- Airplane mode `1`
- `vendor.per_mgr` running
- pm-service PID 31818, PPID 1, sole `/dev/subsys_esoc0` owner on FD9
- X55 ONLINE; crash_count 0
- holder files absent
- qcrild2 PID 873, PPID 1, exact command `qcrild -c 2`
- VOXI slot1 / phoneId1 / subId11 / carrierId28 / MCCMNC23415
- Subscription/UICC ACTIVE / ENABLED
- Initial WFC strict F1: IMS NOT_REGISTERED, transport UNKNOWN, qti.cne/ePDG/XFRM absent

## Single authorized invocation

```text
2026-09-23T21:48:13.642+08:00 version=v2.7-alpha-native-handoff execute=True
2026-09-23T21:48:17.321+08:00 ERROR=The term 'Get-FileHash' is not recognized as the name of a cmdlet, function, script file, or operable program.
RECOVERY_RESULT=NOT_RUN
NATIVE_HANDOFF_RESULT=NOT_RUN
FINAL_WFC_RESULT=NOT_CHECKED
CLEANUP_RESULT=NOT_RUN
REVOTE_MECHANISM_LOG=NOT_CHECKED
PHONE_WRITE_ACTIONS=0
```

## Exact blocker

`Assert-LocalArtifact` uses `Get-FileHash` at script line 351. The exact paired Windows PowerShell 5.1 launcher process did not resolve that cmdlet, so execution stopped before `ENTRY_GATE=PASS`, logcat startup, `Stop-PerMgr`, holder creation, qcrild2 restart, deployment, or SIM activity.

The earlier reported artifact gate ran in the parent shell after the PS5.1 audit/self-test, not inside the paired launcher path. A later isolated `powershell.exe` query could locate `Microsoft.PowerShell.Utility` 3.1.0.0 and `Get-FileHash`; that does not alter the captured launcher failure, and no rerun was attempted.

## Stages and post-state

- Holder Android/host PID: absent / absent
- Rebirth, pre-handoff, release, native reacquire: NOT_RUN
- qcrild2 old/new PID: 873 / 873
- SIM helper runtime hash gate: BLOCKED before completion
- SIM OFF/ON count: 0 / 0
- Final native state: pm-service PID 31818 sole FD9 owner; X55 ONLINE; crash_count 0; holder absent
- Final WFC: F1; IMS NOT_REGISTERED/UNKNOWN; qti.cne/ePDG/XFRM absent

No retry, host-script repair, process restart, holder, SIM cycle, or recovery action was performed.

## Raw evidence

Host-only directory:

`C:\Users\TT\Desktop\platform-tools\voxi_wfc_local_runs\v27_alpha_native_handoff_20260923_214813`

- `experiment.log` SHA256 `ECD8555B55B6C6DB2588BB367B196418658F32C81084DC199FC662A0B65633DE`
- `native_entry.txt` SHA256 `1089F9255E5C29928EE3F37686A3BFA4F24A3D0211025C7899D9ADE50EF2CE3C`
- `wfc_entry.txt` SHA256 `65353ED979093594685C28805894AD0707E88AB1D32AB100B8FF74F5E8FFC379`

```text
ENTRY_GATE=PASS_FRESH_EXTERNAL; SCRIPT_RESULT_NOT_EMITTED_LOCAL_HASH_COMMAND_BLOCK
RECOVERY_RESULT=NOT_RUN
NATIVE_HANDOFF_RESULT=NOT_RUN
FINAL_WFC_RESULT=NOT_CHECKED
CLEANUP_RESULT=NATIVE_UNCHANGED (script reported NOT_RUN)
SIM_OFF_COUNT=0
SIM_ON_COUNT=0
PHONE_WRITES=0
```

Next action: repair and exercise the actual artifact assertion through the exact Windows PowerShell 5.1 no-ADB launcher path. Require new explicit authorization before another device execution.
