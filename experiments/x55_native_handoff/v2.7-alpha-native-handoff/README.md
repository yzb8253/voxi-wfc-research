# VOXI WFC v2.7-alpha Native Handoff

This directory contains a build-only alpha implementation of the native X55 ownership handoff. It does not replace v2.6.2 and has not been executed on a phone.

## Evidence basis

Experiment 001B established the behavioral result:

- one restart of fixed vendor.qcrild2 changed PID 13706 to 873;
- the existing pm-service process acquired /dev/subsys_esoc0;
- X55 returned ONLINE with crash_count=0.

Classification:

- VERIFIED_NATIVE_REACQUIRE_AFTER_QCRILD2_RESTART
- REVOTE_MECHANISM_LOG_UNPROVEN

The expected PerMgrLib/PerMgrSrv register/vote strings were not captured, so the internal re-vote mechanism is not claimed as directly proven.

## State machine

1. Entry gate requires root, airplane mode, native pm-service ownership, X55 ONLINE, zero crash count, no holder, fixed VOXI mapping, and active/enabled UICC applications. Initial WFC F1 is allowed.
2. Stop vendor.per_mgr; require pm-service exit, owner NONE, X55 OFFLINE, and zero crash count.
3. Start the script-owned holder; require its exact PID to be sole node owner, X55 ONLINE, and a new PON_SUCCESS.
4. Start vendor.per_mgr while holder remains alive. Unexpected ownership/state behavior aborts.
5. TERM only the verified owned holder. Require holder exit, PID-file removal, and owner NONE.
6. Restart only fixed vendor.qcrild2 once. Require PID change, native pm-service ownership, X55 ONLINE, and zero crash count. Register/vote logs are supporting evidence only.
7. Wait ten seconds and check WFC. If healthy, finish without a SIM cycle.
8. If unhealthy, run exactly one audited fixed-slot1 SIM cycle, then observe for at most 30 seconds. No retry follows failure.

## Safety properties

- Default launch is read-only dry-run.
- Real execution requires both -Execute and the fixed confirmation token.
- The launcher runs dry-run unless its first argument is exactly execute.
- No slot, phone, subId, transaction number, or numeric power state is accepted from the command line.
- Dual-SIM and single-SIM paths select separate fixed, hash-pinned helper artifacts.
- No modem reset, AP reboot, radio reset, IMS reset, cnd restart, or broad process kill exists.
- Native reacquire failure forbids the SIM cycle.
- Holder cleanup uses TERM only after PID and ownership revalidation.
- Failure after one SIM cycle preserves native pm-service ownership and does not retry qcrild2.
- Raw runtime captures are written outside the repository.

## Files

- X55-WFC-OneClick-v2.7-alpha-native-handoff.ps1: host state machine.
- Run-X55-WFC-v2.7-alpha-native-handoff.cmd: dry-run default and explicit execute launcher.
- device/v27_sim_cycle_dual.sh: fixed dual-SIM one-shot orchestrator.
- device/v27_sim_cycle_single.sh: fixed single-SIM one-shot orchestrator.
- audit_v2_7_alpha.ps1: local static policy audit.
- STATIC_AUDIT.md: audit record.

## Current status

The first authorized launcher invocation was classified `BLOCKED_PRE_WRITE_PS51_INCOMPATIBILITY`: Windows PowerShell 5.1 stopped on `ProcessStartInfo.ArgumentList` before the first ADB call, with phone writes 0. It is not a recovery failure because the state machine never started.

The host wrapper is now Windows PowerShell 5.1 compatible. `Run-X55-WFC-v2.7-alpha-native-handoff.cmd selftest` provides a strict local-only validation path; it exits before ADB initialization and verifies the exact Windows argv quoting used for `adb shell` and the holder payload. Windows PowerShell 5.1 parser, self-test, command-wrapper, PID-variable, quoting, holder-lifecycle, fail-safe, and unchanged-state-machine audits pass.

The repaired version has not been run against the phone. Do not automatically execute it; wait for explicit approval.
