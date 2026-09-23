# v2.7-alpha Third Device Run Result

- Experiment ID: `X55-V27-ALPHA-THIRD-DEVICE-003`
- Date: 2026-09-23 21:24:13 Asia/Shanghai
- Computer: B
- Account: A
- Branch: `voxi-wfc-auto-recovery`
- Commit tested: `e279af23770c7fd37562f3589095429380dd44eb`
- Windows PowerShell: `5.1.19041.6456`

## Classification

`BLOCKED_PRE_WRITE_MISSING_AUDITED_SINGLE_SIM_HELPER`

This is not an X55 rebirth, native-handoff, or WFC recovery result. The script completed its current device/native checks but stopped at the local fixed-artifact gate before logging `ENTRY_GATE=PASS` and before any phone write.

## Fresh independent precheck

- ADB: serial `fd0ff892`, state `device`
- Root: `uid=0(root)`
- Airplane mode: `1`
- `vendor.per_mgr`: running
- pm-service: PID 31818, PPID 1
- `/dev/subsys_esoc0`: pm-service PID 31818, FD9, sole owner
- X55: ONLINE
- crash_count: 0
- holder PID files: absent
- qcrild2: PID 873, PPID 1, exact command `qcrild -c 2`
- VOXI: slot1 / phoneId1 / subId11 / carrierId28 / MCCMNC23415
- Subscription/UICC: ACTIVE / ENABLED
- Initial WFC: strict F1

## Single authorized invocation

The repository launcher was executed exactly once with `execute` under Windows PowerShell 5.1:

```text
2026-09-23T21:24:13.805+08:00 version=v2.7-alpha-native-handoff execute=True
2026-09-23T21:24:17.473+08:00 ERROR=Missing local audited artifact: C:\Users\TT\Desktop\platform-tools\voxi_wfc_research_computer_b\experiments\sim_soft_reset\single_sim_isolation\build\single-sim-slot1-power-helper.jar
RECOVERY_RESULT=NOT_RUN
NATIVE_HANDOFF_RESULT=NOT_RUN
FINAL_WFC_RESULT=NOT_CHECKED
CLEANUP_RESULT=NOT_RUN
REVOTE_MECHANISM_LOG=NOT_CHECKED
PHONE_WRITE_ACTIONS=0
```

## Exact blocker

Single-SIM topology selected the fixed helper at script lines 503-504. `Assert-LocalArtifact` at line 506 rejected the missing JAR before `ENTRY_GATE=PASS` at line 509, before logcat startup at line 517, and before the first state-machine write at line 519.

The expected path is excluded by repository `.gitignore` rule `*.jar`. The source and build script exist, but the fixed helper binary was not present on Computer B. It was not rebuilt or substituted during this experiment.

## State-machine stages

- Rebirth: NOT_RUN
- Holder stage: NOT_RUN; Android/host holder PID absent
- Pre-handoff: NOT_RUN
- Holder release: NOT_RUN
- qcrild2 restart: NOT_RUN; PID remained 873
- Native reacquire: NOT_RUN
- SIM cycle required/executed: NO / NO
- SIM OFF count: 0
- SIM ON count: 0

## Preserved post-state

Fresh read-only verification found the phone unchanged:

- `vendor.per_mgr` running
- pm-service PID 31818 still sole FD9 owner
- X55 ONLINE
- crash_count 0
- qcrild2 PID 873 unchanged
- all holder PID files absent
- VOXI ACTIVE + ENABLED + F1
- IMS NOT_REGISTERED / transport UNKNOWN
- VOICE/IWLAN unavailable; WFC unavailable
- qti.cne request absent; ePDG UDP/4500 absent; XFRM absent

No retry, helper build/substitution, holder action, process restart, SIM action, or recovery action was performed.

## Raw evidence

Host-only directory:

`C:\Users\TT\Desktop\platform-tools\voxi_wfc_local_runs\v27_alpha_native_handoff_20260923_212413`

- `experiment.log` SHA256 `A4D6478F4B5807422399F6212CEA1033F15AD2D619B8FF85A33625B3E65B3FBB`
- `native_entry.txt` SHA256 `1089F9255E5C29928EE3F37686A3BFA4F24A3D0211025C7899D9ADE50EF2CE3C`
- `wfc_entry.txt` SHA256 `508312E21AC2173D5F7C37EF2A03A79955174770F4011C073FD3B98F4A2BD8A4`

## Result fields

```text
ENTRY_GATE=PASS_DEVICE_NATIVE_CHECKS; SCRIPT_RESULT_NOT_EMITTED_ARTIFACT_GATE
RECOVERY_RESULT=NOT_RUN
NATIVE_HANDOFF_RESULT=NOT_RUN
FINAL_WFC_RESULT=NOT_CHECKED
CLEANUP_RESULT=NATIVE_UNCHANGED (script reported NOT_RUN)
SIM_OFF_COUNT=0
SIM_ON_COUNT=0
PHONE_WRITES=0
```

Next action: statically rebuild and hash-verify the exact single-SIM helper artifact, improve preflight packaging/audit, and require new explicit authorization before another device execution.
