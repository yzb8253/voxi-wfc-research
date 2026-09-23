# X55 Ownership Handoff 001 - Aborted

Date: 2026-09-23
Experiment ID: `X55-OWNERSHIP-HANDOFF-001`
Result: `ABORTED_BEFORE_CONTENDED_PHASE / INCONCLUSIVE`

## Entry gate

`PASS` after a zero-write dry run.

- UID 0 in Magisk context; SELinux enforcing.
- per_mgr running, pm-service PID 13288.
- pm-service FD9 was the sole `/dev/subsys_esoc0` owner.
- X55 ONLINE; crash_count 0.
- No holder files.
- qcrild2 running at PID 13706.

The earlier read denials were caused by incorrect host-to-ADB `su -c` quoting, not an inherent SELinux inability to read these fields. The probe now sends the entire escaped root command as one remote shell string.

## Executed path

1. Cleared logcat.
2. Stopped `vendor.per_mgr` once.
3. Verified per_mgr stopped, owner empty, X55 OFFLINE, crash_count 0.
4. Started one persistent host-managed holder.
5. Android holder PID 31163 wrote the fixed PID file and became the sole owner with FD9.
6. Manual fail-safe evidence confirmed holder PID 31163, X55 ONLINE, crash_count 0.

Before Phase 2 could start per_mgr while the holder was alive, PowerShell raised a case-insensitive reserved-variable collision: function parameter `$Pid` attempted to overwrite read-only automatic variable `$PID`.

## Fail-safe cleanup

- Sent one TERM to the script-owned PID 31163 after PID-file and lsof confirmation.
- Holder died and its PID file disappeared.
- Started `vendor.per_mgr` once during fail-safe cleanup.
- New pm-service PID 31818 remained running but did not acquire `/dev/subsys_esoc0`.
- After an additional read-only wait, X55 remained OFFLINE and crash_count remained 0.
- qcrild2 was not restarted and retained PID 13706.
- No QCRIL register/vote test occurred.

The explicit stop rule for final X55 OFFLINE with no native owner was honored. No further radio/IMS/process write was performed.

## Phone-write ledger

Five top-level state-changing actions were completed:

1. clear all logcat buffers;
2. stop `vendor.per_mgr`;
3. create the fixed holder (PID file plus node open);
4. TERM the script-owned holder;
5. start `vendor.per_mgr` for fail-safe cleanup.

No SIM power action, qcrild2 restart, primary qcrild action, vendor.cnd action, VPN/location change, physical SIM action, reboot, or SIGKILL occurred.

## Evidence

- Zero-write passing dry run: `logs/20260923_155633/`
- Executed run and sanitized evidence: `logs/20260923_155655/`
- Complete raw logcat is retained host-only at `voxi_wfc_local_runs/x55_ownership_handoff_20260923_155655/logcat_all.raw.txt` and is not committed because it may contain sensitive unrelated system data.

## Interpretation

The holder power-up portion was observed, but the defining holder-plus-pm-service contention phase and the qcrild2 re-vote phase were not reached. This run does not answer whether a qcrild2 vote causes native reacquisition.

The probe source has been corrected by renaming the conflicting parameter to `$ProcessId`. It was syntax and write-surface audited but was not rerun on the preserved OFFLINE scene.

NEXT_ACTION: preserve the current per_mgr-running/no-owner/X55-OFFLINE scene. Do not automatically rerun the probe or restart qcrild2. A new explicit recovery/experiment decision is required.
