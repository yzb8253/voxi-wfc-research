# Dummy holder results

Date: 2026-09-25  
Target: `/dev/null` only; esoc touched: NO

The OLD candidate retained the production foreground `sleep 60` structure.
The FAST candidate installed a TERM/INT/HUP trap, started a background
`sleep 3600` with FD9 explicitly closed, and waited for that child.

| implementation | TERM phase | main gone | child gone | FD9 owner gone | child inherited FD9 |
|---|---:|---:|---:|---:|---|
| OLD | 2 s | 56,852 ms | 56,852 ms | 56,852 ms | NO |
| OLD | 15 s | 43,799 ms | 43,799 ms | 43,799 ms | NO |
| OLD | 30 s | 28,872 ms | 28,872 ms | 28,872 ms | NO |
| OLD | 50 s | 9,014 ms | 9,014 ms | 9,014 ms | NO |
| OLD | 58 s | 971 ms | 971 ms | 971 ms | NO |
| FAST | 2 s | 232 ms | residual | 232 ms | NO |
| FAST | 15 s | 233 ms | residual | 234 ms | NO |
| FAST | 30 s | 242 ms | residual | 242 ms | NO |
| FAST | 50 s | 248 ms | residual | 248 ms | NO |
| FAST | 58 s | 261 ms | residual | 261 ms | NO |

FD release summary:

- OLD: min 971 ms, median 28,872 ms, P95/max 56,852 ms.
- FAST: min 232 ms, median 242 ms, P95/max 261 ms.

The OLD results track approximately `60 seconds - TERM phase`; this directly
confirms that the outer Android shell defers exit while waiting for foreground
`sleep 60`. The sleep child did not inherit FD9 in these tests, so inherited
FD9 is not the root cause on this ROM.

The FAST outer shell's `wait` is interrupted by TERM, its trap executes, and
the shell closes FD9 immediately. The background sleep can remain alive, but
it has no FD9 and therefore cannot retain target ownership. The test harness
then sends TERM to that exact dummy child only, for cleanup; it never uses
SIGKILL or a broad process match.

Raw sanitized timing CSV remains outside Git under
`voxi_wfc_local_runs/holder_fast_dummy/20260925_213655/samples.csv`.
