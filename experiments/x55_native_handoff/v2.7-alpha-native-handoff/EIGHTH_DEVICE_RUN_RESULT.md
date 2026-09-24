# Eighth v2.7-alpha Device Run Result

Experiment ID: `X55-V27-ALPHA-EIGHTH-DEVICE-008`

Date: 2026-09-24 09:40-09:43 Asia/Shanghai  
Computer/account: Computer A / Account A  
Tested commit: `81b5de257941f7bad9183cc4e9ec7b241de7b63e`  
PowerShell: `5.1.19041.6456`

## Entry and selftest

Fresh entry was native-clean F1:

- `vendor.per_mgr=running`
- pm-service PID 28220 sole `/dev/subsys_esoc0` owner
- X55 ONLINE
- crash_count 0
- v2.7 holder absent
- qcrild2 PID 873 unchanged
- IWLAN HOME / preferred
- IMS NOT_REGISTERED
- WFC unavailable
- qti.cne request absent
- ePDG/XFRM absent

The exact paired `.cmd selftest` passed before the single authorized execute.

## Production path

The redesigned make-before-break native path completed successfully:

1. per_mgr stop: PASS
2. exact holder sole ownership: PASS
3. X55 ONLINE after holder rebirth: PASS
4. new PON_SUCCESS: observed by the production gate
5. per_mgr contended start: PASS
6. exact holder + pm-service dual ownership: PASS
7. exact holder TERM and exit: PASS
8. pm-service sole native ownership: PASS
9. qcrild2 restart: 0

Production results:

```text
RECOVERY_RESULT=X55_REBIRTH_SUCCESS
NATIVE_HANDOFF_RESULT=MAKE_BEFORE_BREAK_NATIVE_HANDOFF_SUCCESS
FINAL_WFC_RESULT=FAILED_AFTER_ONE_SIM_CYCLE
CLEANUP_RESULT=NATIVE_CLEAN
REVOTE_MECHANISM_LOG=UNPROVEN
PHONE_WRITE_ACTIONS=11
```

## SIM cycle evidence

The one-shot single-SIM helper reported `RESULT=SUCCESS`.

POWER_DOWN:

- fixed target slot 1 / phoneId 1 / subId 11
- callbackResult 0
- target became inactive / UICC disabled / mapping false

POWER_UP:

- same fixed target
- callbackResult 0
- the SIM/UICC stack subsequently rebuilt and the target returned active

The software SIM power cycle therefore executed, rather than merely returning a host-side success code.

## WFC outcome

After the cycle, the bounded 0-30 second samples stayed non-healthy:

- IMS NOT_REGISTERED
- IWLAN HOME / preferred
- WFC unavailable
- qti.cne request absent
- UDP/4500 absent
- XFRM absent

The filtered log contains QIms service-status activity including `networkMode = 19` markers and registration errors, but no captured `qualifiedNetworks`, `RatRequested`, or `StartDataCall` marker in this evidence set. The exact meaning of `networkMode = 19` remains heuristic and is not promoted to an official IWLAN definition.

## Interpretation

This run proves the native handoff itself is no longer the active blocker. The important ordering difference versus the previously successful v2.5/v2.6.2 recovery scene is that run 008 restored native pm-service ownership before executing the SIM cycle.

The next implementation should preserve the empirically successful recovery window:

```text
stop per_mgr
-> holder sole owner
-> X55 rebirth / new PON_SUCCESS
-> settle
-> optional one SIM OFF/ON cycle while holder remains sole owner and per_mgr remains stopped
-> evaluate WFC
-> only then run make-before-break native cleanup
-> verify whether WFC survives cleanup
```

This is an ordering hypothesis to test, not yet a recovery proof.

## Host-only evidence

Directory:

`C:\Users\ZJH\Desktop\platform-tools\voxi_wfc_local_runs\v27_alpha_native_handoff_20260924_094051`

A compact evidence archive was separately preserved from that directory; the full raw logcat remains host-only.
