# R_BIG_V1 Destructive Non-Reboot Upper Bound

Status: frozen implementation candidate for the authorized five-cycle series.

## Purpose

Establish a repeatable non-AP-reboot recovery upper bound before attempting any minimization. Cycles 3, 4, and 5 execute the same actions, order, gates, and timeouts.

## Fixed sequence

1. Airplane mode OFF and exact temporary-holder release.
2. Confirm owner NONE, X55 OFFLINE, crash count zero.
3. Start `vendor.per_mgr` only when the frozen v2.6.2 state left it stopped. This creates the required running/non-owner PM precondition; it is not treated as a recovery result.
4. Restart exact init service `vendor.qcrild2` once (generation A); require a new exact `qcrild -c 2` PID, native pm-service sole ownership, X55 ONLINE, DSD/WDS ready.
5. TERM the exact `.qtidataservices` PID once; require ActivityManager recreation with a new exact PID.
6. Restart `vendor.qcrild2` exactly once again (generation B); require `GEN_B != GEN_A`, native ownership, X55, DSD/WDS.
7. Bind to the latest post-generation-B NAH constructor and require ten stable samples of non-UNKNOWN `globalPrefSys`, working IMS with terrestrial qualification, LastReported IMS, stable generation B/provider PID, DSD/WDS, X55 and PM ownership.
8. TERM exact persistent `com.android.phone` PID once; require ActivityManager reconstruction and fresh Phone/SST/ANM/NRM/DNC/CarrierConfig/MMTEL markers.
9. Reconfirm generation B, provider PID and NAH generation/publication are unchanged.
10. Enter the same fixed P and invoke the hash-locked v2.6.2 recovery.

No adaptive restart, retry, timeout extension, CND/IMS reset, extra SIM cycle, modem reset, or extra reboot is permitted.

## Series

- CONTROL_A0: exactly one AP reboot for the entire series.
- Cycle 1: fixed P -> v2.6.2.
- Cycle 2: historical holder release + one qcrild2 native reacquire -> fixed P -> v2.6.2.
- Cycles 3-5: identical R_BIG_V1 -> fixed P -> v2.6.2.

Any failure stops the series at its first stage.

