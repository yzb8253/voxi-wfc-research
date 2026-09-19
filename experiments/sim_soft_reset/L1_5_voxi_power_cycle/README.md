# L1.5 VOXI slot-power-cycle probe

This directory contains the read-only discovery stage for a future VOXI slot power cycle. It does **not** contain or execute SIM power-down, SIM power-up, UIM reset, raw Binder/HIDL transactions, or qcrild control.

Fixed mapping:

- VOXI: Android slot/phone `1`, subId `11`, `IRadio/slot2`, `IUim/Uim1`, `vendor.qcrild2`.
- Protected China Telecom SIM: Android slot/phone `0`, subId `1`, `IRadio/slot1`, `IUim/Uim0`, primary `vendor.qcrild`.

Run the probe from a POSIX shell (for example Git Bash):

```sh
ADB_BIN=../../../../adb.exe \
SERIAL=192.168.1.25:42319 \
./run_l1_5_probe.sh
```

The script rejects arguments and `LAB_EXECUTE=YES`. Captures are written beneath `../runs/` and are intentionally ignored by Git because full telephony dumps may contain subscriber identifiers.

Read [`L1_5_INTERFACE_REPORT.md`](L1_5_INTERFACE_REPORT.md) before designing any write helper. The next write stage remains blocked pending an independently armed power-up rollback and final pre-write dual-SIM safety gate.

The source-only execution preparation is now under [`executor/`](executor/). It has not been built, deployed, or run in write mode; see its execution plan and code audit before any later authorization.
