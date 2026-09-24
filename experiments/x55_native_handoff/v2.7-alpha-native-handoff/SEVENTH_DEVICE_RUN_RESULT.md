# X55-V27-ALPHA-MAKE-BEFORE-BREAK-007

Date: 2026-09-24 09:20 Asia/Shanghai

Commit tested: `9ccf2eeeac9b4f14b5b662e4a8b076a1552695d4`

## Entry

The worktree was clean and local/remote HEAD matched the required commit. The fresh gate confirmed USB serial `fd0ff892`, root UID 0, airplane mode on, per_mgr running, pm-service PID 22536 as sole `/dev/subsys_esoc0` owner, X55 ONLINE, crash_count 0, no holder files, and fixed qcrild2 PID 873. VOXI was active/enabled at slot1/subId11 and WFC was strict F1. Slot0 was confirmed absent, so the fixed single-SIM slot1 path applied.

The exact paired Windows PowerShell 5.1 selftest passed before execution.

## Execution

The launcher was run exactly once. per_mgr stopped, the exact Android holder PID 27125 became sole owner, X55 returned ONLINE, and a new `PON_SUCCESS` appeared. Starting per_mgr formed the expected exact dual-owner state with holder 27125 and new pm-service PID 28220.

The script then sent exactly one TERM to holder 27125. TERM returned successfully, but the holder did not disappear within the fixed 10-second wait. The script stopped with `Holder did not exit`. No qcrild2 restart, SIM cycle, retry, or manual recovery action occurred.

## Preserved Scene

The immediate read-only post-check found holder 27125 still alive with child `sleep 60`, its PID file still present, and holder 27125 plus pm-service 28220 still co-owning `/dev/subsys_esoc0`. per_mgr was running, X55 remained ONLINE, crash_count remained 0, and qcrild2 remained PID 873. WFC remained F1: IMS NOT_REGISTERED, IMS transport UNKNOWN, voice over IWLAN unavailable, WFC unavailable, qti.cne request absent, UDP/4500 absent, and XFRM absent. Framework IWLAN remained IWLAN/HOME and preferred.

The strongest current explanation is that the shell deferred its TERM trap while waiting for the `sleep 60` child, making the 10-second exit deadline too short. This is an inference from the live process tree, not yet a device-tested fix.

## Result

```text
ENTRY_GATE=PASS
X55_REBIRTH=PASS
NEW_PON_SUCCESS=YES
DUAL_OWNER_FORMED=YES
EXACT_HOLDER_TERM=SENT_ONCE_EXIT_TIMEOUT
PM_SOLE_AFTER_TERM=NO
SIM_OFF_COUNT=0
SIM_ON_COUNT=0
RECOVERY_RESULT=X55_REBIRTH_SUCCESS
NATIVE_HANDOFF_RESULT=NOT_RUN
FINAL_WFC_RESULT=NOT_CHECKED
CLEANUP_RESULT=NOT_RUN
PHONE_WRITE_ACTIONS=4
```

Classification: `HOLDER_TERM_DEFERRED_TIMEOUT / PRESERVED_DUAL_OWNER`. This is not a native-handoff success and not a WFC recovery result. Raw logs remain outside Git.

