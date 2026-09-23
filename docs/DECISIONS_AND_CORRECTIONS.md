# Decisions and Corrections

Append only. Remove obsolete wording from current-state files, but preserve its correction here.

## 2026-09-23 15:30 - pm-service ownership is not boot-only

Previous belief:
pm-service could acquire `/dev/subsys_esoc0` only during complete AP boot.

Evidence:
In a clean native scene, PID 1232 held the node and X55 was ONLINE. After per_mgr stop/start, new PID 13288 reacquired it before qcrild2 restart; X55 was ONLINE.

Correction:
Reject the absolute boot-only statement.

Current conclusion:
Without holder contention, per_mgr stop/start can restore native ownership.

Impact:
Distinguish clean and holder-contended reacquisition; AP reboot is not required solely for pm-service ownership.

## 2026-09-23 15:31 - holder contention is a separate state

Previous belief:
Holder-contended behavior could be generalized to every pm-service restart.

Evidence:
Clean stop/start reacquired ownership, while v2.6.2 started pm-service with the holder alive and pm-service did not acquire.

Correction:
Do not combine these states.

Current conclusion:
Holder-first startup can create a missed-acquisition state. Post-release reacquisition is unverified.

Impact:
The next test isolates ownership transitions and does not test WFC.

## 2026-09-23 15:32 - qcrild2 is a verified Peripheral Manager voter

Previous belief:
qcrild2 participation was inferred from linkage and topology.

Evidence:
Device logs explicitly showed QCRIL registration, successful SDX55M registration, voting, and voter count two.

Correction:
Promote the relationship from inference to verified behavior.

Current conclusion:
Fixed-slot2 qcrild2 registers and votes through `libperipheral_client`.

Impact:
One qcrild2 re-registration is a justified handoff trigger candidate, with transient slot2 radio/IMS impact.

## 2026-09-23 15:33 - ownership experiment blocked before write

Previous belief:
The cross-account narrative alone was enough to resume the live holder experiment.

Evidence:
GitHub lacked v2.6.2 holder/observer artifacts; SELinux denied pm-service FD and X55 state/crash_count reads.

Correction:
Matching PIDs and narrative history are insufficient for a destructive gate.

Current conclusion:
The experiment is `BLOCKED_PRE_WRITE / NOT_RUN` until exact artifacts return and all gates pass.

Impact:
Phone writes stayed zero; restore provenance and observation tooling first.
## 2026-09-23 16:10 - direct ownership reads work with correct ADB quoting

Previous belief:
Enforcing SELinux prevented the available Magisk root client from reading pm-service FDs, X55 state, and crash_count.

Evidence:
The independent probe sent the complete escaped `su -c` command as one remote shell string. It read UID 0, pm-service FD9 ownership of `/dev/subsys_esoc0`, X55 ONLINE, and crash_count 0 while SELinux remained enforcing.

Correction:
The earlier denials were caused by host-to-ADB command quoting/context, not an inherent read prohibition for this root path.

Current conclusion:
The independent probe can enforce the native owner, ONLINE, crash-count, no-holder, and qcrild2 entry gates directly.

Impact:
The missing historical observer is no longer an execution blocker. Probe correctness and fail-safe behavior remain mandatory; `X55-OWNERSHIP-HANDOFF-001` was aborted before its contended phase and remains inconclusive.

## 2026-09-23 16:25 - native reacquisition is not proof of a logged QCRIL re-vote

Previous belief:
A fresh fixed-slot2 qcrild2 registration/vote was the leading trigger for pm-service to retry native node acquisition.

Evidence:
In 001B, exactly one qcrild2 restart changed PID 13706 -> 873 and pm-service reacquired FD9 while X55 returned ONLINE. However, the complete captured logcat contained none of the required PerMgrLib/PerMgrSrv QCRIL register/vote messages.

Correction:
Do not label the ownership transition as a verified QCRIL re-vote.

Current conclusion:
qcrild2 restart is correlated with native reacquisition in this preserved scene, but the precise trigger is unverified.

Impact:
Use the predefined result `QCRILD2_RESTART_NO_VALID_REVOTE`; do not promote the re-vote hypothesis without direct evidence.

## 2026-09-23 20:37 - static syntax audit did not prove launcher runtime compatibility

Previous belief:
The passing PowerShell parser/static policy audit was sufficient to establish that the paired Windows launcher could reach the device entry gate.

Evidence:
The first authorized launch used `Run-X55-WFC-v2.7-alpha-native-handoff.cmd execute`. Its `powershell.exe` process was Windows PowerShell 5.1, whose `ProcessStartInfo` lacks the `ArgumentList` property used by the state machine. Execution stopped before the first ADB call with phone writes 0.

Correction:
Separate language parsing/static safety from runtime API compatibility. A script can parse successfully yet fail under the exact runtime selected by its launcher.

Current conclusion:
v2.7-alpha remains untested on the phone. The first launch is `BLOCKED_PRE_WRITE`, not a recovery or native-handoff failure.

Impact:
The host wrapper must support Windows PowerShell 5.1 or the paired launcher must select a verified compatible runtime. The audit must execute at least a dry-run through the exact launcher/runtime before another authorized real run.

Resolution:
Both `ProcessStartInfo.ArgumentList` uses were replaced by an audited `ProcessStartInfo.Arguments` encoder, both .NET Core-only `Process.Kill(bool)` uses were removed, and the exact `.cmd selftest` path passed under Windows PowerShell 5.1.19041.6456 without initializing ADB. Parser errors were 0, argument round-trip and static safety audits passed, and phone writes remained 0. No real rerun is authorized by this repair.

## 2026-09-23 21:01 - PS5.1 parser and argv self-test did not cover automatic-variable or Android newline semantics

Previous belief:
The repaired launcher self-test was sufficient to establish that the script could complete its device entry gate under Windows PowerShell 5.1.

Evidence:
The second authorized launch reached its first read-only device capture, then stopped with `A hash table can only be added to another hash table.` Tested-script line 155 used `$matches`; case-insensitive PowerShell treated it as automatic `$Matches`, and the `-match` predicates at lines 160-161 replaced it with a hashtable before the script appended a process object. Independently, `native_entry.txt` showed CRLF from the multiline PowerShell here-string embedded in Android command tokens (`id\r`, `2>&$'1\r'`).

Correction:
PowerShell safety audits must reject all collisions with automatic variables case-insensitively, not only `$PID`. Any multiline Android shell payload must normalize host newlines to LF before it reaches ADB, and the no-ADB test must verify the normalized byte/string form.

Current conclusion:
The second launch is `BLOCKED_PRE_WRITE_HOST_SCRIPT_COMPATIBILITY`, not a native-handoff or recovery failure. The internal entry gate was not completed and phone writes were 0.

Impact:
Do not rerun. Repair and audit both blockers first, preserve the state-machine ordering and safety gates, and require new explicit authorization for another device execution.

Resolution:
The custom collection is now `$resolvedProcesses`. A single `Normalize-AndroidShellText` helper normalizes every `Invoke-Root` payload and the direct holder command. The exact Windows PowerShell 5.1 host-only path reports parser PASS, automatic-variable audit PASS, Android LF normalization PASS, payload CR count 0, command-build PASS, and static no-ADB PASS. The state machine is unchanged and phone writes during repair were 0.

## 2026-09-23 21:24 - static source audit did not prove required ignored binary availability

Previous belief:
Hash-pinned helper references plus source/build reports were sufficient preparation for a fresh-computer device launch.

Evidence:
The third authorized launcher invocation passed current device/native checks but `Assert-LocalArtifact` rejected the absent single-SIM helper JAR. The expected `build/*.jar` is ignored by Git and was not present on Computer B.

Correction:
Runtime preflight must verify or reproducibly build every hash-pinned local binary before device execution authorization. Static string/hash checks alone do not prove artifact availability.

Current conclusion:
The third launch is `BLOCKED_PRE_WRITE_MISSING_AUDITED_SINGLE_SIM_HELPER`, not a recovery failure. The state machine did not perform a phone write.

Impact:
Do not substitute or rebuild during the failed run and do not rerun automatically. Restore the exact audited artifact through a reproducible static build, verify its pinned SHA-256, then obtain fresh authorization.

## 2026-09-23 21:48 - parent-shell artifact validation did not exercise launcher hash resolution

Previous belief:
The host-only artifact gate had proven that the exact Windows PowerShell 5.1 launcher could hash and accept the tracked helper.

Evidence:
The fourth launcher invocation stopped at script line 351 because `Get-FileHash` was not resolved. The previous artifact check ran in the parent shell after the PS5.1 audit/self-test rather than inside the paired launcher path.

Correction:
Artifact presence/hash verification must execute through the same Windows PowerShell 5.1 code path used by the real launcher.

Current conclusion:
The fourth launch is `BLOCKED_PRE_WRITE_PS51_FILEHASH_RESOLUTION`, not a recovery failure. Phone writes remained 0.

Impact:
Add a PS5.1-compatible hashing implementation or explicit module import and exercise the actual `Assert-LocalArtifact` path in `selftest`. Do not rerun automatically.
