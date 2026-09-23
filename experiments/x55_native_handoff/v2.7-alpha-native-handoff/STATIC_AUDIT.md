# v2.7-alpha Static Audit

Status: PASS — Windows PowerShell 5.1 compatibility repair verified

Scope: local source review plus an isolated `STATIC / NO-ADB / NO-PHONE-WRITE` Windows PowerShell 5.1 runtime self-test. No ADB invocation, no script execution against a phone, and no phone write.

## First device-launch incompatibility

The complete first-run host log recorded:

```text
2026-09-23T20:37:08.934+08:00 version=v2.7-alpha-native-handoff execute=True
2026-09-23T20:37:09.054+08:00 ERROR=The property 'ArgumentList' cannot be found on this object. Verify that the property exists.
```

The terminal surfaced the final rethrow at the original script line 482. The originating access in baseline commit `1949b6f90572e2b7eee60963cab8b18fc6b07591` was line 65:

```powershell
[void]$info.ArgumentList.Add($argument)
```

A second latent use existed at original line 224 in `Start-OwnedHolder`; it had not yet executed. The exact file was `X55-WFC-OneClick-v2.7-alpha-native-handoff.ps1`.

Root cause: the paired `.cmd` deliberately launches `powershell.exe`, which is Windows PowerShell 5.1 on Computer B. Its .NET Framework `System.Diagnostics.ProcessStartInfo` has the string `Arguments` property but not the .NET Core `ArgumentList` collection exposed to PowerShell 7. The same audit found two latent calls to the .NET Core `Process.Kill(bool)` overload; Windows PowerShell 5.1 exposes `Process.Kill()` without that Boolean overload.

Classification: `BLOCKED_PRE_WRITE_PS51_INCOMPATIBILITY`. The state machine never began and phone writes were 0; this is not a v2.7-alpha recovery failure.

## Compatibility repair

- Replaced both `ProcessStartInfo.ArgumentList` uses with a PS5.1-compatible `ProcessStartInfo.Arguments` string produced by a standard Windows command-line argument encoder.
- Replaced .NET Core-only `Process.Kill($true)` calls with an exact, script-owned host PID `taskkill /T /F` helper and a final `Process.Kill()` fallback, preserving process-tree cleanup under Windows PowerShell 5.1.
- Added `-StaticNoAdb` and the launcher command `selftest`. This branch requires Windows PowerShell major version 5, runs before run-directory/ADB initialization, and cannot be combined with `-Execute`.
- The self-test launches only a local child `powershell.exe` and verifies exact argv round trips for spaces, single and double quotes, trailing backslashes, `$`/`$$`, redirection symbols, `||`, semicolons, FD9 open syntax, traps, and the holder loop.
- The execute branch, phone state machine, gates, write budget, helper hashes, and fail-safe ordering were not changed.

## Results

- Windows PowerShell version: `5.1.19041.6456`
- Windows PowerShell 5.1 parser errors: `0`
- Paired `.cmd selftest`: PASS
- Windows argv round-trip: PASS
- PowerShell parser: PASS
- PS7-only syntax/cmdlet/variable scan: PASS
- `ProcessStartInfo.ArgumentList` dependency removed: PASS
- `Process.Kill(bool)` dependency removed: PASS
- Exact owned host process-tree cleanup retained: PASS
- ADB/su command quoting audit: PASS
- PID automatic-variable audit (`$PID`/`$Pid`/`$pid`): PASS
- Native state-machine order unchanged: PASS
- Reserved PID variable collision scan: PASS
- Launcher default dry-run: PASS
- Fixed execution confirmation token: PASS
- Fixed target slot 1 and protected slot 0 gates: PASS
- Fixed helper classes and SHA-256 pins: PASS
- Holder ownership/PID verification before TERM: PASS
- Exactly one qcrild2 restart call site: PASS
- Native reacquire required before SIM cycle: PASS
- Healthy state skips SIM cycle: PASS
- One POWER_DOWN and one POWER_UP call site per device orchestrator: PASS
- POWER_UP return-code preservation: PASS
- No automatic retry: PASS
- No modem/radio/IMS reset, reboot, broad kill, cnd restart, or primary qcrild restart path: PASS
- Distinct recovery/native-handoff/final-WFC/cleanup outputs: PASS
- v2.6.2 files modified: NO
- Phone writes during compatibility work and validation: `0`

## Residual risks

- Stopping Peripheral Manager intentionally transitions X55 OFFLINE before holder-controlled rebirth.
- Restarting qcrild2 can transiently disrupt slot2 radio/data framework state.
- Starting Peripheral Manager while holder owns the node is device-specific; unexpected behavior causes BEHAVIOR_CHANGED and abort.
- Fail-safe cleanup restores Peripheral Manager and releases only the script-owned holder, but does not escalate into extra qcrild2, cnd, modem, radio, or reboot actions.
- The internal QCRIL re-vote mechanism remains log-unproven even though native reacquire behavior was observed in 001B.

## Required acceptance block

```text
WINDOWS_POWERSHELL_VERSION=5.1.19041.6456
PS5.1_PARSE=PASS
CMD_WRAPPER_AUDIT=PASS
ADB_QUOTING_AUDIT=PASS
PID_VARIABLE_AUDIT=PASS
HOLDER_LIFECYCLE_AUDIT=PASS
FAIL_SAFE_AUDIT=PASS
STATE_MACHINE_UNCHANGED=YES
PHONE_WRITES=0
```

The repaired executable state machine has not been rerun against a phone. A new real run requires explicit approval.
