# X55 Native Ownership Handoff Precheck

Date: 2026-09-23
Result: `BLOCKED_PRE_WRITE / FAIL_SAFE`

## Requested experiment

Validate only the ownership transition:

`temporary holder -> native pm-service ownership of /dev/subsys_esoc0`

The requested sequence would stop and start `vendor.per_mgr`, keep one explicitly tracked temporary holder alive, terminate it normally, and restart only fixed-slot2 `vendor.qcrild2` to generate a new QCRIL Peripheral Manager registration/vote. No SIM cycle or WFC recovery test was requested.

## Git/source check

- Branch: `voxi-wfc-auto-recovery`
- Local and remote HEAD at precheck: `b513bd627da0c4476fc18012c318248b2c4d1d8c`
- All remote branches and repository history were searched.
- The repository contains no v2.6.2 X55 recovery source, holder implementation, ownership observer, or corresponding experiment record.
- Installed phone module reports v2.0, not v2.6.2.

The attachment supplied important prior findings, but GitHub is the declared source of truth. Those later artifacts are therefore missing from the durable project state.

## Device identity

- ADB serial: `fd0ff892`
- Device: `cas`, Android 13
- ADB shell: UID 2000
- Magisk root: UID 0, SELinux `u:r:magisk:s0`

## Read-only current scene

- `pm-service`: PID 13288, PPID 1, SELinux `u:r:vendor_per_mgr:s0`
- `pm-proxy`: PID 1699
- primary qcrild: PID 1926
- fixed-slot2 qcrild2: PID 13706, `/vendor/bin/hw/qcrild -c 2`, SELinux `u:r:rild:s0`
- `mdm_helper`: PID 1297
- No holder PID/state file was found in the checked VOXI/module temporary paths.
- `/dev/subsys_esoc0` exists as a system-owned character device.
- Init RC confirms `vendor.per_mgr -> /vendor/bin/pm-service`, class core, user/group system. `vendor.per_proxy` is started when `vendor.per_mgr` reaches running.
- VOXI mapping is subId 11, slot 1, phoneId 1, carrierId 28, MCCMNC 23415; subscription active and UICC applications enabled.
- Current IMS/WFC state is F1: IMS not registered, transport unknown, VOICE/IWLAN and WFC unavailable.
- The installed v2.0 status tool reports `UNSAFE` only because its old dual-SIM slot0 gate does not support the current physically absent China Telecom SIM.

## Unclosed safety gates

The available Magisk SELinux domain cannot independently confirm the required clean ownership baseline:

- `lsof /dev/subsys_esoc0` did not expose an owner.
- Reading `/proc/13288/fd` and `/proc/13288/fdinfo/9` was denied.
- Reading X55 `state` and `crash_count` under the modem subsystem sysfs node was denied.
- No retained recent Peripheral Manager log establishes the current owner or current crash count.
- The repository lacks the previously used/audited holder and ownership-capture implementation.

Consequently these mandatory current-state facts are unknown:

- pm-service is the present native owner of `/dev/subsys_esoc0`.
- X55 is currently ONLINE through the intended ownership path.
- `crash_count=0` at experiment entry.

## Decision

The entry gate did not pass. No phone write was executed:

- no `stop vendor.per_mgr`
- no holder creation
- no `start vendor.per_mgr`
- no qcrild2 restart
- no SIM/UICC operation
- no radio/modem operation

The ownership handoff experiment is `NOT_RUN`, not a failed handoff result.

## Required recovery of project state

Before execution, restore the missing v2.6.2/X55 artifacts to the authoritative Git branch, including the exact holder implementation and the read-only method previously used to prove pm-service FD ownership, X55 ONLINE, and crash count. Re-run this precheck with those audited tools. Do not synthesize a replacement holder during a live destructive run.

NEXT_ACTION: recover and review the missing v2.6.2/X55 source and observer artifacts; then repeat the read-only entry gate. Do not execute the ownership handoff until every gate is directly confirmed.
