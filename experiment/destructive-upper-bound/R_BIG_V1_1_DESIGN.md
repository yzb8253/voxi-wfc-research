# R_BIG_V1.1 Destructive Non-Reboot Upper Bound

Status: frozen implementation for the independently authorized five-cycle series.

R_BIG_V1.1 is identical to R_BIG_V1 except for the holder-release readiness gate. The prior series proved that an exact holder can exit with no `/dev/subsys_esoc0` owner, kernel X55 OFFLINE, and crash count zero while `vendor.peripheral.SDX55M.state` temporarily remains ONLINE.

## Holder-release gate

Hard requirements:

1. the exact verified holder is gone;
2. `/dev/subsys_esoc0` has no owner;
3. kernel X55 is OFFLINE;
4. crash count is zero.

`vendor.peripheral.SDX55M.state` is still captured before the qcrild2 restart and after the restart, but is telemetry only at holder release. Its value cannot extend the timeout, trigger another action, or fail the release gate.

## Frozen recovery sequence

Cycle 1 and Cycle 2 retain the original fixed sequences. Cycles 3-5 retain the exact R_BIG_V1 order:

`holder release -> qcrild2 GEN_A -> qtidataservices TERM -> qcrild2 GEN_B -> NATIVE_READY -> phone TERM -> A_READY -> fixed P -> hash-locked v2.6.2 -> WFC`

No action count, ordering, timeout, stable-sample requirement, health predicate, or v2.6.2 artifact changed.
