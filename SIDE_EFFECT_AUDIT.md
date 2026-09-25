# VOXI WFC profiling side-effect audit

Date: 2026-09-25

## Result

The instrumentation itself caused zero phone writes. The real profiling invocation used only the pre-existing verified wrapper actions. It did not recover WFC in the single-SIM physical state, and the optional UICC fallback stopped fail-closed at its protected-slot0 gate. Read-only instrumentation is not automatically behavior-neutral: the golden preflight's pre-existing full snapshots add tens of seconds to asynchronous state transitions.

## Protected slot0

- The first core precondition, before the first SIM2 power cycle, already reported protected subId1 fields as null and gate FAIL.
- Final `dumpsys isub` shows subId1 in the database with `simSlotIndex=-1`, not active in slot0.
- No slot0 SIM power, enable/disable, reset, or configuration write was issued.
- The guarded UICC fallback detected this mismatch and performed zero UICC writes.
- Per-run golden slot0 dumps are not retained. Repository continuity indicates the golden period was also single-SIM/slot0-absent, so the current absence must not be called a newly different start state. Further recovery profiling remains paused for methodology review, not because a golden/current physical mismatch was proven.

## VOXI slot1

- Final mapping: slot1 / phoneId1 / subId11 / carrierId28 / MCCMNC 23415.
- Final subscription: ACTIVE.
- Final UICC applications: ENABLED.
- SIM2 software cycle count: OFF=2, ON=2 across two bounded core attempts; exactly one OFF/ON per attempt.
- No emergency or duplicate POWER ON occurred.
- Final health: F1, IMS NOT_REGISTERED, transport UNKNOWN, VOICE/IWLAN unavailable, WFC unavailable.

## X55 and ownership

- Entry: holder PID 9993 sole owner, vendor.per_mgr stopped, X55 ONLINE, crash_count 1.
- Final: pm-service PID 13861 sole owner, holder absent, pid file absent, X55 ONLINE, crash_count 3.
- Every qcrild2 reacquire required owner NONE and X55 OFFLINE before restart, then exact pm-service ownership and X55 ONLINE.
- Each ONLINE reacquire kept crash_count stable relative to its immediately preceding OFFLINE state.
- Cumulative crash_count growth occurred across controlled shutdown/normalization epochs; no unexplained increment was observed during an ONLINE reacquire.

## QCRIL

- Primary qcrild remained PID 1971 from entry to final readback.
- qcrild2 epochs: 4234 -> 28713 -> 23036 -> 16115.
- Three targeted qcrild2 restarts occurred only in validated normalization.
- No primary qcrild restart was issued or observed.

## Airplane, Wi-Fi, VPN

- Entry: airplane OFF, Wi-Fi ON; connectivity dump reported a VPN network, while no `tun`/`wg` interface matched the snapshot's narrow interface regex.
- Existing wrapper issued four airplane transitions: ON, OFF, ON, OFF.
- Existing wrapper issued five idempotent Wi-Fi enable requests.
- Final: airplane OFF, Wi-Fi setting ON.
- No location, VPN profile, route, or proxy setting was intentionally modified.
- The profiling run did not establish a strong final VPN-path equivalence check; this remains an uncertainty.

## Crash, tombstone, and ANR review

- Crash buffer contained older FlClash/Clash foreground-service exceptions, the newest at 16:54, before the 18:12 profiling start.
- No new crash-buffer entry was observed during the profiling window.
- Latest tombstones were dated 2026-09-21, not this run.
- `dumpsys activity lastanr` reported no ANR since boot.

## Audit findings

| Area | Finding | Assessment |
|---|---|---|
| Health race / exit mismatch | Wrapper accepts `coreExit=30` and retries after reclassifying the retained-holder state. | Known-path behavior but worth an explicit contract; no change in profiling phase. |
| Cross-epoch snapshots | Snapshot labels and qcrild2 PID epochs were distinct. | PASS |
| Stale qti.cne evidence | Snapshot truncates connectivity before request history and core compares before/after request IDs. | PASS for observed `null -> null` |
| Holder PID reuse | Identity uses pid file plus live cmdline, fd9 target, and lsof owner. | PASS |
| Ownership transient | Exact owner count, executable, vendor/kernel state, and crash_count are gated. | PASS |
| qcrild2 epoch | Old/new PID change is required. | PASS |
| crash_count semantics | Relative OFFLINE-to-ONLINE stability is enforced; cumulative count is allowed. | PASS |
| Airplane async | Only setting convergence after a fixed three-second wait is checked. | Observable weakness; no change yet. |
| Wi-Fi readiness | Gate checks `wifi_on`, not full WLAN/VPN route readiness. | Observable weakness; no change yet. |
| Health false positive | Requires REGISTERED(2), WLAN(2), VOICE/IWLAN available, and WFC available. | PASS |
| Post-health stability | Wrapper freezes immediately on health; no separate stability interval. | Existing golden behavior; do not change during profiling. |
| Cleanup pollution | Both failed cores retained the holder because native takeover failed; next preflight safely recognized and normalized it. | Fail-safe worked, but cost was large. |
| Slot0 null-output gate | Deep fallback rejected absent/null slot0 and did not write UICC. | PASS / blocked further tests |
| Nominal 30-second window | Probe execution time is excluded from the logical counter, producing ~62 seconds wall time. | Confirmed latency/accounting defect; not fixed yet. |

## Phone-write inventory

Only existing wrapper actions were used:

- airplane transitions: 4;
- idempotent Wi-Fi enable requests: 5;
- targeted qcrild2 restarts: 3;
- slot1 SIM OFF: 2;
- slot1 SIM ON: 2;
- guarded UICC false/true: 0;
- slot0 writes: 0;
- main qcrild restarts: 0;
- vendor.cnd/qtidataservices/IMS restarts: 0;
- reboot: 0.

Native holder and vendor.per_mgr lifecycle actions followed the unchanged golden wrapper and ended native-clean.
