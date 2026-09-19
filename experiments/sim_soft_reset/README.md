# VOXI SIM soft-reset lab

This lab studies a no-AP-reboot equivalent of physical VOXI SIM removal and insertion. It does not replace or modify the existing auto-recovery module.

The scripts are host-side POSIX shell programs. Every executable experiment is inert unless `LAB_EXECUTE=YES` is set. The shared runner verifies root, the fixed dual-SIM mapping, records full before/after snapshots, streams full logcat, samples the existing read-only WFC probe, and generates a result summary.

## Fixed scope

- Target: VOXI subId 11, slot 1, phoneId 1, carrierId 28, MCCMNC 23415.
- Protected: China Telecom subId 1, slot 0, carrierId 2237, MCCMNC 46011.
- Forbidden: AP reboot, boot modification, flashing, EFS/NV/PDC/MBN writes, persistent dual-SIM damage, arbitrary target identifiers.
- No experiment is automatically chained to the next level.

## Quick start

Read-only baseline:

```sh
ADB_BIN=../../../adb.exe SERIAL=192.168.1.25:42319 ./scripts/00_read_only_baseline.sh
```

Print a candidate plan without executing it:

```sh
ADB_BIN=../../../adb.exe SERIAL=192.168.1.25:42319 ./scripts/01_framework_uicc_cycle.sh
```

Execute only after reviewing `MATRIX.md`, reconnecting ADB, and preserving the current failure scene:

```sh
LAB_EXECUTE=YES ADB_BIN=../../../adb.exe SERIAL=192.168.1.25:42319 ./scripts/01_framework_uicc_cycle.sh
```

Results are created under `runs/<timestamp>-<experiment-id>/`. Raw captures can contain subscriber information and are intentionally ignored by Git.

## Result rule

A test only recovers WFC when all four direct conditions are true:

1. IMS `REGISTERED(2)`.
2. Registration transport `WLAN(2)`.
3. VOICE/IWLAN available.
4. `isWifiCallingAvailable(11)=true`.

SIM READY, a replacement qti.cne request, UDP/4500 and XFRM are separately reported as causal/supporting observations.
