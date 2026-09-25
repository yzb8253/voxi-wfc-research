# AGGRESSIVE_CONSERVATIVE_v1.2H-r1 identity audit

## Confirmed cause

The v1.2H lightweight collector stored holder `cmdline` from `ps ... ARGS`. The split preparer independently read `/proc/<pid>/cmdline`, replaced NUL separators with spaces, and required case-sensitive string equality. The FAST command contains quoting and shell metacharacters; `ps ARGS` rendered `trap "exit 0"` as `trap exit 0`, while `/proc` preserves the actual argv element. The two detectors therefore described the same PID differently.

The wrapper's `ENTRY_HOLDER_IMPL=FAST` detector searched only the lossy `psArgs` text for `sleep 3600` and `9<&-`; it never performed the preparer's cross-source equality check. That explains why it reported FAST while the preparer rejected identity.

## r1 contract

- `holder.psArgs`: retained for diagnostics only.
- `holder.procArgv`: authoritative argv array, collected by converting the NUL-separated `/proc/<pid>/cmdline` into discrete array elements.
- Observation and pre-write live check both read `/proc/<pid>/cmdline` and compare every argv element case-sensitively.
- PID/pidfile equality, live PID, PPID, process name, FD9, sole ownership, QCRIL identity, X55 state, crash_count, mapping/UICC, schema completeness, and current-table CNE gates remain mandatory.
- A second semantic gate accepts only the known FAST or legacy OLD holder grammar. FAST requires the fixed pidfile/device markers plus `trap`, `TERM`, `sleep 3600`, `9<&-`, child capture, and `wait`. This semantic gate supplements exact argv equality; it does not replace it.

Existing v1.2H, FAST holder implementation, split definition, write authorization, qcrild2 reacquire, core timing, golden/stable, and original v2.6.2 files are unchanged.

## Fixtures

1. FAST holder with different `psArgs` rendering but identical `/proc` argv: PASS.
2. Same PID with changed live argv: FAIL-CLOSED.
3. PID/pidfile mismatch: FAIL-CLOSED.
4. Wrong FD9: FAIL-CLOSED.
5. Non-sole owner: FAIL-CLOSED.
6. Missing FAST semantic marker: FAIL-CLOSED.
7. Legal OLD holder: existing `FROZEN_RESIDUE` behavior retained.

Unsafe promotions: 0.
