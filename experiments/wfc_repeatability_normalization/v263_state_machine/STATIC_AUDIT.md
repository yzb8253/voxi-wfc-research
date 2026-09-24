# v2.6.3 state-machine static audit

Status: `PASS_PENDING_DEVICE_VALIDATION`

Base commit: `89f2c86d48c91a974988d9bf67415f592da6f50d`

## Reused verified artifacts

- Snapshot collector: `capture_snapshot.ps1`.
- Recovery: the unmodified validated experimental file `v262_freeze_run/X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1`.
- Recovery SHA-256 gate: `445752BB49FB487850D0B1A1EFF4F0AA29D58C363C3A86E75BAA841E4CC08F75`.
- A normalization helpers: the exact two helpers recorded in the successful v2.6.2 repeatability run.

## State-machine boundaries

- Fixed ADB serial `fd0ff892` and fixed VOXI identity; no arbitrary slot/subId/phoneId input.
- Unknown A or P fingerprints fail closed before recovery.
- A normalization is available only for the exact frozen-success residue.
- P has no speculative repair path.
- Recovery is delegated to the hash-locked verified v2.6.2 file; it is not reimplemented.
- W is judged only by the verified direct health predicate and never normalized.
- Successful W immediately returns frozen.
- The three-cycle driver disables airplane mode only between successful cycles 1/2 and waits 60 seconds before the next A capture.
- After cycle 3 it performs no further phone write.

## Write surfaces

State-machine orchestration adds only:

- `cmd connectivity airplane-mode enable` once per started cycle;
- `svc wifi enable` once per started cycle;
- `cmd connectivity airplane-mode disable` after successful cycles 1 and 2 only.

Exact frozen-residue normalization may invoke the already recorded helpers:

- start/restart vendor.per_mgr while preserving the exact holder;
- TERM the exact verified holder;
- if dual ownership did not form, restart vendor.qcrild2 once only after owner-NONE/X55-OFFLINE/crash-zero is proven.

The delegated v2.6.2 path performs its proven X55 rebirth and at most one fixed SIM2 OFF/ON cycle.

No CND fallback, qtidataservices restart, second SIM cycle, IMS reset, radio reset, modem reset, AP reboot, qcrild-primary restart, or arbitrary process kill was added.

## Failure behavior

Any gate, child script, or post-recovery health failure aborts the driver and prevents later cycles. There is no retry loop or alternate recovery path. Raw logs remain host-only.

