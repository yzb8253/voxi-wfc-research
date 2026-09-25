# X55 WFC aggressive conservative v0

Experimental manual entry only. The golden and stable entry points remain unchanged.

## Fixed behavior

- Uses the existing proven v2.6.2 freeze-on-success core without modifying it.
- Maximum recovery attempts: 2.
- A settle sleep budget: dynamic 5-20 seconds.
- P settle sleep budget: dynamic 5-20 seconds.
- Post-PON settle: 10 seconds.
- SIM OFF hold: 3 seconds.
- SIM ON health window: unchanged 30-second sleep budget plus probe runtime.
- Deep fallback, qcrild2 reacquire, normalization order, mutation order, and health predicate are inherited unchanged.

## Fast path

The lightweight result is accepted only for phase-appropriate `A0_READY`, `P0_READY`, or `HEALTHY_FREEZE` with a complete capture, no structural errors, exact identities/ownership, and null current CNE request/satisfied IDs.

`FROZEN_RESIDUE`, `UNKNOWN`, active CNE, missing/schema/capture fields, unexpected owner, identity contradiction, or any structural uncertainty immediately selects the existing full snapshot and old authoritative classifier.

## Entry points

- Golden/stable: `RUN-X55-WFC-STABLE-v1.cmd`
- Experimental: `RUN-X55-WFC-AGGRESSIVE-CONSERVATIVE-v0.cmd`

Start the experimental entry with airplane mode OFF, the same as the stable wrapper.
