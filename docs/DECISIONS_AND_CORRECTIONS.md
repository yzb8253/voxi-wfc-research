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
