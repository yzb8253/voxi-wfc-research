# v2.7-alpha Second Device Run Result

Date: 2026-09-23 21:00:59 Asia/Shanghai  
Computer: B  
Account: A  
Branch: `voxi-wfc-auto-recovery`  
Commit tested: `cd222ea058dbb1f2b88905b99987885f3a9438ce`  
Windows PowerShell: `5.1.19041.6456`

## Classification

`BLOCKED_PRE_WRITE_PS51_MATCHES_COLLISION_AND_ANDROID_CRLF`

This is not an X55-rebirth, native-handoff, or WFC recovery result. The state machine did not pass its internal entry gate and performed zero phone writes.

## Fresh independent entry gate

- ADB serial: `fd0ff892`, state `device`
- Root: `uid=0(root)`
- Device: `cas` / `23116PN5BC`
- Airplane mode: `1`
- `vendor.per_mgr`: running
- pm-service: PID 31818, PPID 1
- `/dev/subsys_esoc0`: pm-service PID 31818, FD9, sole owner
- X55: ONLINE
- crash_count: 0
- holder files: absent
- qcrild2: PID 873, PPID 1, exact command `qcrild -c 2`
- VOXI: slot1 / phoneId1 / subId11 / carrierId28 / MCCMNC23415
- Subscription/UICC: ACTIVE / ENABLED
- Initial WFC: strict F1

## Single authorized launcher invocation

The repository launcher was invoked exactly once with `execute` under Windows PowerShell 5.1. It exited with code 1 after about two seconds:

```text
2026-09-23T21:00:59.587+08:00 version=v2.7-alpha-native-handoff execute=True
2026-09-23T21:01:00.393+08:00 ERROR=A hash table can only be added to another hash table.
RECOVERY_RESULT=NOT_RUN
NATIVE_HANDOFF_RESULT=NOT_RUN
FINAL_WFC_RESULT=NOT_CHECKED
CLEANUP_RESULT=NOT_RUN
REVOTE_MECHANISM_LOG=NOT_CHECKED
PHONE_WRITE_ACTIONS=0
```

## Exact blocker

In `Resolve-ExactProcess`, tested-script line 155 assigns `$matches = @()`. PowerShell variable names are case-insensitive, so this is the automatic `$Matches` variable. The regular-expression operations at lines 160-161 replace `$Matches` with a hashtable. The subsequent `$matches += $item` therefore attempts to add a process object to a hashtable and raises the exact observed exception: `A hash table can only be added to another hash table.` A local Windows PowerShell 5.1 reproduction confirmed the same type and message.

The saved `native_entry.txt` also proves a second host compatibility defect. `Capture-NativeState` builds a Windows CRLF here-string at lines 179-200 and passes it unchanged through `su -c`. Android `sh` received carriage returns in command tokens, producing `id\r: inaccessible or not found` and `2>&$'1\r': illegal file descriptor name`. This malformed the script's internal entry snapshot but did not execute a phone write.

## Preserved post-state

Fresh read-only verification after the failed invocation found:

- pm-service PID 31818 still the sole `/dev/subsys_esoc0` owner on FD9
- X55 ONLINE
- crash_count 0
- qcrild2 PID 873 unchanged
- all known holder PID files absent
- VOXI still ACTIVE + ENABLED + F1
- SIM OFF count 0
- SIM ON count 0
- phone writes 0

No retry, holder action, process restart, SIM cycle, or script-external recovery was performed.

## Raw evidence

Host-only directory:

`C:\Users\TT\Desktop\platform-tools\voxi_wfc_local_runs\v27_alpha_native_handoff_20260923_210059`

- `experiment.log` SHA256 `CF603F7CB11F7899C6EDCA0E4F17B7D3D78D42846A7251886C6E5805B481B6F3`
- `native_entry.txt` SHA256 `40840234D35819CBCCA191F0A9ED3CD02FD5EFB62303B9A1237CDA6F025D5E8D`

## Result fields

```text
ENTRY_GATE_RESULT=PASS_INDEPENDENT_READ_ONLY; SCRIPT_GATE_BLOCKED_PRE_WRITE
RECOVERY_RESULT=NOT_RUN
NATIVE_HANDOFF_RESULT=NOT_RUN
FINAL_WFC_RESULT=NOT_CHECKED
CLEANUP_RESULT=NATIVE_UNCHANGED (script reported NOT_RUN)
SIM_OFF_COUNT=0
SIM_ON_COUNT=0
PHONE_WRITES=0
```

Next action: repair and audit both blockers without changing the state machine, then require new explicit authorization before any further device execution.
