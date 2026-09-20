# Absent-state Soft Reboot Result

Date: 2026-09-20
Result: `FAIL_PRE_POWER_DOWN` (safe pre-write abort; the absent-state experiment itself did not run)

## What happened

The dedicated watchdog emitted `absent-watchdog.ready`, but the previously audited Java helper requires the generic path `/data/local/tmp/voxi-l1_5-executor/watchdog.ready`. The helper therefore rejected POWER_DOWN before writing `power_down.sent` and before invoking `TelephonyManager.setSimPowerStateForSlot`.

The orchestrator obeyed its failure rule and skipped every process TERM. Its then-current failure path issued one POWER_UP while slot1 was already READY. The callback returned 0 and the live slot/subscription state remained unchanged. The watchdog later exited through its no-POWER_DOWN path and did not fire fallback POWER_UP.

## Requested result fields

- POWER_DOWN: REJECTED BEFORE API INVOCATION
- POWER_DOWN callback: NONE
- Confirmed card-down: NO
- Time: rejection at 2026-09-20T11:41:02+08:00
- Slot0 during attempt: active, subId1/slot0/carrier2237/MCCMNC46011, SIM READY
- qcrild2: 8330 -> 8330 (not signaled)
- qcrild: 9201 -> 9201 (not signaled)
- netmgrd: 1815 -> 1815 (not signaled)
- imsqmidaemon: 26664 -> 26664 (not signaled)
- imsdatadaemon: 26887 -> 26887 (not signaled)
- vendor.cnd: 27097 -> 27097 (not signaled)
- qtidataservices: 3532 -> 3532 (not signaled)
- org.codeaurora.ims: 3553 -> 3553 (not signaled)
- com.android.phone UID1001: 9164 -> 9164 (not signaled)
- system_server: 2267 -> 2267 (not signaled)
- Soft stack rebuild: NOT RUN
- POWER_UP: one already-up request; callback 0 at 2026-09-20T11:41:03+08:00
- Watchdog fallback used: NO
- SIM/UICC restored: YES, unchanged (never left READY)
- subId11 restored: YES, unchanged
- CarrierConfig lifecycle: NOT ENTERED
- Native IMS demand: NO NEW REQUEST
- qti.cne IMS request: NO
- ePDG/XFRM: absent before and after
- IMS: NOT_REGISTERED (0)
- Transport: UNKNOWN (-1)
- VOICE/IWLAN: unavailable
- WFC: unavailable
- slot0 final: PASS, active/READY and correctly mapped
- VPN/tun0 final: PASS, tun0 UP; wlan0 UP
- ABSENT_STATE_SOFT_REBOOT: FAIL_PRE_POWER_DOWN / NOT SUBSTANTIVELY TESTED
- Recovery time after POWER_UP: not applicable; card never powered down

## Safety outcome

- Actual POWER_DOWN API invocation count: 0
- Process TERM count: 0
- Modem SSR/radio toggle/airplane toggle/AP reboot count: 0
- Final strict dual-SIM gate: PASS
- Raw captures remain outside the Git repository.

## Corrective change

The dedicated watchdog now creates and cleans both its dedicated ready marker and the generic helper-ready marker. The orchestrator now avoids POWER_UP when POWER_DOWN is rejected before `power_down.sent` exists. Updated syntax and static audits pass.

NEXT_ACTION: do not retry automatically. A new explicit authorization is required for one real fixed-slot1 POWER_DOWN/soft-stack/POWER_UP attempt using the corrected scripts.
