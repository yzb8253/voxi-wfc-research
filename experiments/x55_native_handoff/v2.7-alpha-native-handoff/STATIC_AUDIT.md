# v2.7-alpha Static Audit

Status: PASS — make-before-break native-handoff redesign verified statically

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

## Second device-launch incompatibilities

The second authorized launch of commit `cd222ea058dbb1f2b88905b99987885f3a9438ce` stopped before any phone write with:

```text
ERROR=A hash table can only be added to another hash table.
```

Exact cause one: `Resolve-ExactProcess` used `$matches` as a collection at tested lines 155, 160, 161, 163, and 164. PowerShell variables are case-insensitive; each `-match` operation replaced automatic `$Matches` with a hashtable before `$matches += $item` attempted to append a process object.

Exact cause two: the only Android multiline payload, the `Capture-NativeState` here-string at tested lines 179-200, retained Windows CRLF. Android `sh` saw carriage returns in `id` and `2>&1`. The direct holder payload was single-line and was not observed contaminated, but it now passes through the same explicit normalizer.

Classification: `BLOCKED_PRE_WRITE_HOST_SCRIPT_COMPATIBILITY`. This is not a recovery failure. Recovery/native-handoff remained NOT_RUN, SIM OFF/ON remained 0/0, and phone writes were 0.

## Compatibility repair

- Replaced both `ProcessStartInfo.ArgumentList` uses with a PS5.1-compatible `ProcessStartInfo.Arguments` string produced by a standard Windows command-line argument encoder.
- Replaced .NET Core-only `Process.Kill($true)` calls with an exact, script-owned host PID `taskkill /T /F` helper and a final `Process.Kill()` fallback, preserving process-tree cleanup under Windows PowerShell 5.1.
- Added `-StaticNoAdb` and the launcher command `selftest`. This branch requires Windows PowerShell major version 5, runs before run-directory/ADB initialization, and cannot be combined with `-Execute`.
- The self-test launches only a local child `powershell.exe` and verifies exact argv round trips for spaces, single and double quotes, trailing backslashes, `$`/`$$`, redirection symbols, `||`, semicolons, FD9 open syntax, traps, and the holder loop.
- The execute branch, phone state machine, gates, write budget, helper hashes, and fail-safe ordering were not changed.
- Renamed the process-result collection to `$resolvedProcesses`; no custom `$matches`/`$Matches` variable remains in executable source.
- Added one `Normalize-AndroidShellText` helper. Every `Invoke-Root` command is normalized to LF before quoting, and the direct holder launch is normalized before its ADB argument is built.
- Expanded the no-ADB self-test to build the read-only state probe, holder launch/PID/identity/termination payloads, owner/X55 probes, and SIM helper/orchestrator commands. All final payloads are checked for carriage returns without invoking ADB.
- Added a case-insensitive automatic-variable assignment audit covering PID, Matches, Error, Args, Input, Home, Host, Null, True, and False.

## Results

- Windows PowerShell version: `5.1.19041.6456`
- Windows PowerShell 5.1 parser errors: `0`
- Automatic-variable audit: PASS
- Custom Matches variables: `0`
- Android LF normalization: PASS
- Android payload CR count: `0`
- Holder/SIM command construction: PASS
- Paired `.cmd selftest`: PASS
- Windows argv round-trip: PASS
- PowerShell parser: PASS
- PS7-only syntax/cmdlet/variable scan: PASS
- `ProcessStartInfo.ArgumentList` dependency removed: PASS
- `Process.Kill(bool)` dependency removed: PASS
- Exact owned host process-tree cleanup retained: PASS
- ADB/su command quoting audit: PASS
- PID automatic-variable audit (`$PID`/`$Pid`/`$pid`): PASS
- Make-before-break state-machine order: PASS
- Reserved PID variable collision scan: PASS
- Launcher default dry-run: PASS
- Fixed execution confirmation token: PASS
- Fixed target slot 1 and protected slot 0 gates: PASS
- Fixed helper classes and SHA-256 pins: PASS
- Exact Android holder PID-file/PID/cmdline/FD9 verification before TERM: PASS
- Holder identity independent of Windows host-process lifetime: PASS
- Exact holder-sole, holder+pm-service dual-owner, and pm-service-sole models: PASS
- Unknown third owner rejection: PASS
- qcrild2 restart call sites in the redesigned path: `0`
- Exact pm-service sole ownership required before SIM cycle: PASS
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
- Starting Peripheral Manager while the exact holder owns the node must form exactly two owners: that holder and one exact init-owned pm-service. Missing dual ownership or any third owner aborts before TERM.
- After exact holder TERM, pm-service must be the sole owner and X55 must remain ONLINE with crash_count 0. Failure forbids the SIM cycle.
- A stale holder PID file is reported and preserved; the script does not delete it to manufacture a clean gate.
- Cleanup 006 validates native ownership transfer only. WFC remained F1, so the redesigned complete recovery path still requires a separately authorized device run.

## Fourth-launch hash blocker resolution

The fourth launch was correctly classified as `BLOCKED_PRE_WRITE_PS51_FILEHASH_RESOLUTION`. The production script now uses an internal .NET `SHA256` implementation with explicit stream and hash-object disposal. Both the artifact gate and orchestrator deployment use this implementation; the main script has zero `Get-FileHash` dependencies.

The exact paired launcher command `Run-X55-WFC-v2.7-alpha-native-handoff.cmd selftest` ran under Windows PowerShell `5.1.19041.6456`. It invoked production `Assert-LocalArtifact` against the fixed single-SIM helper, verified the known `abc` SHA-256 vector, hashed the single-SIM orchestrator, and exited before run-directory or ADB initialization. Result: PASS. The phone had not yet been rerun at this audit checkpoint; the later fifth run is documented separately.

## Required acceptance block

```text
WINDOWS_POWERSHELL_VERSION=5.1.19041.6456
PS5.1_PARSE=PASS
AUTO_VARIABLE_AUDIT=PASS
CUSTOM_MATCHES_VARIABLES=0
ANDROID_LF_NORMALIZATION=PASS
ANDROID_PAYLOAD_CR_COUNT=0
DOTNET_SHA256_KNOWN_VECTOR=PASS
LOCAL_HASH_ENGINE=DOTNET_SHA256
GET_FILE_HASH_DEPENDENCY_COUNT=0
SINGLE_SIM_HELPER_HASH_MATCH=YES
ARTIFACT_GATE=PASS
STATIC_NO_ADB=PASS
CMD_WRAPPER_AUDIT=PASS
ADB_QUOTING_AUDIT=PASS
PID_VARIABLE_AUDIT=PASS
HOLDER_IDENTITY_MODEL=PASS
HOLDER_SOLE_MODEL=PASS
DUAL_OWNER_MODEL=PASS
PM_SOLE_MODEL=PASS
UNKNOWN_THIRD_OWNER_REJECTED=PASS
HOST_PROCESS_ABSENT_IDENTITY_MODEL=PASS
MAKE_BEFORE_BREAK_STATE_MACHINE=PASS
QCRILD2_RESTARTS_IN_NEW_PATH=0
SIM_OFF_MAX=1
SIM_ON_MAX=1
PHONE_WRITES=0
```

The redesigned executable state machine was not run against the phone. Any new device run requires explicit approval.
