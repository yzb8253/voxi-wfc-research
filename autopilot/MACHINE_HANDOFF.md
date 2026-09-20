# VOXI WFC Machine Handoff

## Purpose

This file is the durable cross-computer resume contract for the VOXI WFC project.

When the user changes computers, Codex should not ask them to reconstruct Git state, rerun completed experiments, or remember an old wireless ADB endpoint. Sync from GitHub, verify the current device, read the latest checkpoints, and continue from the recorded next action.

## Repository

- Repository: `yzb8253/voxi-wfc-research`
- Working branch: `voxi-wfc-auto-recovery`
- Remote: `origin`
- Remote branch HEAD is authoritative.

## New-computer bootstrap

If the repository already exists:

```powershell
git fetch origin
git checkout voxi-wfc-auto-recovery
git pull --ff-only origin voxi-wfc-auto-recovery
git rev-parse HEAD
git rev-parse origin/voxi-wfc-auto-recovery
```

The two commit IDs must match before continuing.

If the local repository is absent, clone the repository first, then switch to `voxi-wfc-auto-recovery`.

After sync:

1. Read `AGENTS.md`.
2. Read `autopilot/AUTOPILOT_STATE.md`.
3. Read `autopilot/AUTOPILOT_FINDINGS.md`.
4. Read this file.
5. Run `adb devices` and resolve the current device endpoint.
6. Confirm the Xiaomi target and root access.
7. Continue from the latest `NEXT_ACTION`.

Never reuse a previous computer's wireless ADB IP:port without resolving it again.

## Automatic Git checkpointing

After each meaningful completed unit of work:

- update the state/finding/handoff summaries;
- stage source, scripts, plans, sanitized reports, audits, and other non-sensitive project artifacts;
- commit;
- push to `origin/voxi-wfc-auto-recovery`;
- verify the remote commit;
- leave the worktree clean when practical.

Do not upload raw run captures or telephony dumps containing subscriber identifiers. Do not upload secrets, tokens, ICCID, IMSI, MSISDN, or similarly sensitive artifacts. Summarize/sanitize them first.

If a push cannot be completed, record the exact blocker instead of reporting success.

## User-facing handoff convention

The user's intended workflow is:

1. They paste the last Codex output when useful.
2. They say “换电脑了” / “I changed computers”.
3. Codex automatically performs Git sync, state recovery, ADB rediscovery, identity/root checks, and resumes from the latest checkpoint.
4. The user should not need to type Git synchronization commands manually.

## Current checkpoint

At the time this protocol file was created, the repository already contained the guarded L1.5 slot1 SIM-power-cycle executor preparation and watchdog work. Always trust the latest remote branch state over this prose snapshot.
