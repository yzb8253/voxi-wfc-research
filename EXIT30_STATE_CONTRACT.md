# EXIT30_STATE_CONTRACT TODO

Status: documented only; wrapper behavior is unchanged.

- `coreExit=0` plus strong health is the ordinary success candidate, subject to the existing supported freeze invariant.
- `coreExit=30` plus strong wrapper health is `LATE_HEALTH_CLEANUP_FAILED_EXCEPTION`, not automatically an ordinary native-safe success.
- Before that exceptional state can be accepted in a future contract, a read-only check must prove exact holder identity, holder sole ownership of `/dev/subsys_esoc0`, X55 ONLINE, crash-count invariant, target ACTIVE/UICC enabled, and no unknown owner.
- `coreExit=30` plus unhealthy wrapper health remains failure.

This TODO does not alter the wrapper's current post-core probe or exit handling.

The separate post-SIM timing contract also remains unchanged: 30 seconds of sleep budget plus probe runtime. `TIMEOUT_ACCOUNTING_DEFECT / CONTRACT_AMBIGUITY` remains a future independent experiment.
