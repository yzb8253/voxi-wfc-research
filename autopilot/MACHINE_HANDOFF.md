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

- Date: 2026-09-20, single-SIM simple reinsert complete.
- Exactly one fixed slot1 POWER_DOWN and one fixed slot1 POWER_UP returned callback 0. True ABSENT was confirmed and held 10 seconds; watchdog fallback count was zero.
- SIM READY/LOADED, subId11 mapping, UICC enabled, CarrierConfig change, and MMTEL READY returned.
- Final state through 120 seconds is ACTIVE + ENABLED + F1 with no native IMS demand, qti.cne/TNF/DNC IMS request, ePDG/XFRM, IMS registration, or WFC.
- slot0 remains ABSENT; wlan0/tun0 remain up. No soft-stack, process, modem, airplane, or reboot action was executed.
- Sanitized report: `experiments/sim_soft_reset/single_sim_isolation/SINGLE_SIM_SIMPLE_REINSERT_RESULT.md`.

NEXT_ACTION: stop. Do not repeat simple reinsert and do not automatically run soft-stack recovery. A distinct below-boundary hypothesis requires new explicit authorization and safety review.

## Earlier checkpoint: computer-B recovery

- Date: 2026-09-20, computer-B read-only recovery.
- USB ADB currently resolves one target: `fd0ff892`, Xiaomi 14 Pro, Magisk UID 0.
- VOXI remains subId11/slot1/phoneId1/carrierId28/MCCMNC23415, ACTIVE and UICC enabled.
- China SIM slot0 is ABSENT; the two-slot SIM-state property is `ABSENT,LOADED`.
- Current health is F1: IMS NOT_REGISTERED/UNKNOWN, VOICE-IWLAN unavailable, WFC unavailable; no qti.cne IMS request or ePDG tunnel.
- single-SIM helper source and reports are present; static audit passes. `device/*.sh` is now pinned to LF to make Windows checkouts safe.
- No device write was executed during this handoff.

NEXT_ACTION: preserve F1. Do not execute the single-SIM cycle merely because the computer changed; the latest completed experiment boundary still applies.

## Earlier checkpoint

- Date: 2026-09-20
- Branch: voxi-wfc-auto-recovery
- Device endpoint at last check: 192.168.1.106:41701; always rediscover after reconnect.
- Current kernel boot ID at last check: 8034952d-9ad8-4ccd-930a-c595cd7bcab4.
- The attempted Golden Boot baseline was rejected as a fresh-boot claim because kernel uptime was about 48 hours and telephony/framework PIDs were continuous with the prior run.
- Current state remains VOXI active/enabled F1; slot0 mapping is protected.
- Current-ROM restart-modem chain terminates in Radio HAL ResetNvType.RELOAD, not ERASE or FACTORY_RESET.
- The shell entry cannot execute on this production user build because TelephonyShellCommand requires UID0 and TelephonyUtils.IS_USER=false.
- No modem restart, direct Binder bypass, SIM power cycle, process kill, radio toggle, or AP reboot was executed in this phase.
- Sanitized report: experiments/sim_soft_reset/modem_only_restart/MODEM_ONLY_RECOVERY_RESULT.md.

NEXT_ACTION: preserve F1 and do not bypass the user-build shell gate. If a direct fixed-target ITelephony.rebootModem experiment is desired, obtain separate explicit authorization and repeat the complete dual-SIM/modem-wide risk review.

## Current checkpoint (2026-09-20T15:15:32+08:00)

- Branch: voxi-wfc-auto-recovery.
- Latest device endpoint: 192.168.1.106:41701; rediscover before use.
- Prepared and audited experiments/sim_soft_reset/L1_5_voxi_power_cycle/executor/stabilized_absent_second_reinsert/.
- No device write was used during preparation. Static audit and Android shell syntax checks pass.
- NEXT_ACTION: run the explicitly authorized bounded executor. Do not exceed two POWER_DOWN, two normal POWER_UP, one soft-stack rebuild, and never issue a third POWER_DOWN.

## Current checkpoint (2026-09-20 stabilized absent experiment complete)

- Branch: voxi-wfc-auto-recovery.
- Latest known online ADB alias: adb-fd0ff892-wZRh7k._adb-tls-connect._tcp; last discovered numeric endpoint was 192.168.1.106:41615. Always rediscover.
- Sanitized result: experiments/sim_soft_reset/L1_5_voxi_power_cycle/executor/stabilized_absent_second_reinsert/STABILIZED_ABSENT_SECOND_REINSERT_RESULT.md.
- Actual write accounting: two fixed slot1 POWER_DOWN callbacks, two fixed slot1 POWER_UP callbacks, one soft-stack rebuild, no third down.
- Final device state: VOXI ACTIVE + UICC ENABLED + IWLAN HOME + strict F1. China Telecom slot0 protected.
- NEXT_ACTION: stop. Do not repeat this experiment. New below-boundary work requires explicit authorization; otherwise use the known full reboot lifecycle for recovery.
