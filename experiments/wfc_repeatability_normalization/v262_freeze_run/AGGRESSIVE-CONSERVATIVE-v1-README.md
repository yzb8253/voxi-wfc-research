# AGGRESSIVE_CONSERVATIVE_v1

This experiment changes only A-state preflight latency. The validated v2.6.2
core, PON/SIM timing, recovery attempts, mutation order, and health predicate
remain frozen.

## Fast path

The lightweight collector may return `FROZEN_SPLIT_RESIDUE` only when every
fixed target, subscription, UICC, qcrild identity, holder PID/cmdline/FD9,
owner, pm-service identity, X55 split, crash-count, and current-CNE evidence
field is present and exact. This class is **not** general write eligibility.
Its sole permitted action is the existing audited qcrild2 reacquire
normalization.

After normalization, one lightweight capture must report exact `A0_READY`.
Any incomplete, active-CNE, unknown-owner, identity, mapping, or other mismatch
falls back to the old full **read-only** A0 verification. It never causes a
second normalization.

The expensive historical logcat evidence therefore leaves the normal exact
split critical path, but remains available in the old full fallback for
failure/unknown forensics.

## Holder decision

v1 does not change the holder. The command opens FD9 and then repeatedly runs
`sleep 60`; authorized historical evidence observed the holder still alive
after TERM with a live `sleep 60` child. The measured 5/34/53/58-second exits
are consistent with the remaining time in that 60-second cycle. Historical
captures do not contain enough boot-id/uptime/process-tree data to prove that
latency grows monotonically with recovery ordinal, so a holder implementation
change remains a separate experiment.

Run the offline audit first:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\audit_aggressive_conservative_v1.ps1
```

The real-device entry point is `RUN-X55-WFC-AGGRESSIVE-CONSERVATIVE-v1.cmd`.
