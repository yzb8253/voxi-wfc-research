# Real holder-only run 001: pre-FAST gate failure

Date: 2026-09-25 21:47 CST  
Candidate commit: `b5366df855ad8b5bcfca25edf01b0d9b5c15b200`  
Classification: `BLOCKED_PRE_FAST_STALE_VENDOR_PROPERTY_GATE`

The exact entry gate passed with old holder 17267 as sole esoc owner,
`vendor.per_mgr=stopped`, X55 ONLINE/ONLINE, crash_count 3, primary qcrild
1971, and qcrild2 12314. One exact TERM was sent to the old holder; it exited
in 5,501 ms.

After release, ownership was NONE and kernel X55 was OFFLINE, but
`vendor.peripheral.SDX55M.state` remained ONLINE while its owning per_mgr
service was stopped. The script incorrectly required both vendor and kernel
properties to be OFFLINE, so it stopped before payload push/start. The FAST
holder was never created and no FAST release timing was measured.

Rollback started native `vendor.per_mgr`. pm-service PID 27267 appeared but
did not reacquire from the owner-NONE/OFFLINE epoch by itself. After a 20-second
read-only wait, one exact `ctl.restart vendor.qcrild2` was used solely for
rollback. qcrild2 changed 12314 -> 27832; pm-service 27267 became the sole
owner; X55 returned ONLINE/ONLINE; crash_count remained 3; primary qcrild 1971
did not change.

Writes in this blocked run:

- old holder exact TERM: 1;
- FAST holder starts: 0;
- SIM writes: 0;
- airplane writes: 0;
- primary qcrild operations: 0;
- native rollback per_mgr start: 1;
- native rollback qcrild2 restart: 1;
- SIGKILL: 0.

Correction required before a new candidate: when per_mgr is stopped, its
vendor property is not a trustworthy live state signal. The pre-FAST release
gate must require owner NONE, kernel OFFLINE, and unchanged numeric
crash_count, while recording the vendor property diagnostically. Every
post-mutation exit path must also restore native pm-service ownership, using
at most one exact qcrild2 restart if starting per_mgr alone does not reacquire.
