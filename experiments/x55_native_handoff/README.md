# X55 Native Ownership Handoff

## Goal

Determine whether native pm-service can take `/dev/subsys_esoc0` after a temporary holder releases it, using one fixed-slot2 qcrild2 registration/vote if needed. This tests ownership only: no SIM cycle and no WFC success criterion.

## Preconditions

All must be directly verified immediately before the first write:

- per_mgr running with dynamically resolved pm-service PID;
- per_proxy, primary qcrild, qcrild2, and mdm_helper identities recorded;
- pm-service is native owner of `/dev/subsys_esoc0`;
- X55 ONLINE; `crash_count=0`;
- no holder or stale holder file;
- VOXI identity correct for slot2;
- exact holder and observer present in and audited from GitHub.

Any unknown means `BLOCKED_PRE_WRITE`, phone writes 0.

## Phases

### Phase 1: holder scene

Stop per_mgr once; verify native owner gone; start one fixed PID-recording holder opening only `/dev/subsys_esoc0`; verify holder is sole owner, X55 ONLINE, crash_count zero.

### Phase 2: contended cleanup

Keep holder alive; start per_mgr once; verify pm-service runs but has no node FD, holder remains sole owner, X55 ONLINE, crash_count zero.

### Phase 3: native handoff

Record time; normally terminate holder; verify PID gone and owner temporarily empty; restart only dynamically resolved qcrild2 once via native init; verify new PID, QCRIL register/vote logs, pm-service ownership, X55 ONLINE, crash_count zero.

No retry or wider restart ladder.

## Success criteria

Holder dead; no holder state; pm-service owns node; X55 ONLINE; crash_count zero; qcrild2 new PID; QCRIL registration/vote evidence. WFC is diagnostic only.

## Risks

Stopping per_mgr can take X55 OFFLINE. A malformed/orphan holder can block ownership. qcrild2 restart can transiently cause RADIO_NOT_AVAILABLE and DSD/IMS rebuilding. Do not begin without audited holder, owner observer, and cleanup path. No SIGKILL unless separately authorized for evidence-backed manual recovery.
