# HOLDER A/B DIFF AUDIT

## Scope

Baseline: `3c4362795e201b4aaecf103d0b12a32046fe38a4`.

Both commands invoke `X55-WFC-HOLDER-AB-r2.ps1`, which invokes the same
`X55-WFC-AGGRESSIVE-CONSERVATIVE-v1.2H-r2-engine.ps1` with
`MaxRecoveryAttempts=1`. The only selector is `ABVariant=OLD|FAST`; it selects
one of the two already-audited v2.6.2 core copies.

## Only behavioral difference

The two core files have equal line counts and exactly one differing line:

- OLD: FD9 holder with `while true; do sleep 60; done`.
- FAST: TERM/INT/HUP trap, FD9 held by the main shell, `sleep 3600 9<&-` in a
  child, and main-shell `wait`.

After replacing that one line with `__HOLDER_IMPLEMENTATION__`, the complete
core texts are byte-identical under the audit's LF-normalized representation.
Any second differing line makes the static audit fail.

Audited SHA256 values:

- OLD core: `70C81B1CC2F69F80540CB08DDD0C4F16FF2871B48D9D46E25F72C0F66CE51E76`
- FAST core: `0876285019658EC56BE4964B76A5FE807CE2FCDA237CC891CC9BE347E6725F22`
- normalized core: `9747AE0089AE76A3C7E3293CC1358238ECC5647E0FB6A0D1874E5913E5C1153A`

## Frozen behavior

The shared r2 engine keeps current-table-only CNE write decisions, identical
A0/P logic and safety gates, identical X55/PON/SIM timing and ordering, and the
same health predicate. The A/B wrapper fixes the attempt count at one. The
existing deep fallback requires at least two NO_CNE attempts, so it is
unreachable in this harness.

## Telemetry

The shared engine projects the same core log fields for both variants. This is
post-action telemetry only; it does not alter core control flow. Failure CNE
classification uses the audited connectivity current-table parser.

Run `test_holder_ab_r2_static.ps1` for parser, hash, normalized-diff, variant
binding, single-attempt, and deep-fallback reachability checks.

Static acceptance on Windows PowerShell 5.1:

- parser: PASS
- classifier fixtures: 17/17 PASS
- current-table CNE gate fixtures: 5/5 PASS
- holder identity fixtures: 7/7 PASS
- unsafe promotion: 0
- baseline OLD/FAST core files modified: NO
- phone writes during static validation: 0
