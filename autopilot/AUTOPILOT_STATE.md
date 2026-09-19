# Autopilot State

## 2026-09-19 phase handoff

- New active workstream: `experiments/sim_soft_reset/`.
- Goal: emulate physical VOXI SIM remove/insert through a reversible slot1 UICC/Radio/UIM lifecycle without AP reboot.
- Current live serial: `192.168.1.25:42319` (mDNS alias also visible).
- Current preserved state: ACTIVE + UICC ENABLED + F1; direct IMS/WFC unhealthy, slot0 mapping gate PASS.
- Matrix and independent scripts created; L0 read-only capture passed.
- No new phone write was executed.
- Preferred next work: statically prove and build fixed `setSimPowerStateForSlot(1, POWER_DOWN/POWER_UP)` helper. Raw QMI/HIDL calls stay blocked.
- Existing auto-recovery module is unchanged.

UPDATED: 2026-09-18T10:30:40+08:00
STATUS: PHASE8D_COMPLETE_FAILED_PRESERVED
FINAL_GOAL: ACHIEVED
HARD_BLOCKER: NONE
VALIDATION: 3/3 PASS

CURRENT_DEVICE_SERIAL: 192.168.137.211:41111
CURRENT_EXPECTED_STATE: ACTIVE_ENABLED_F1_PRESERVED
CURRENT_FAILURE_CLASS: F1_IMS_NOT_REGISTERED

PHASE 8A QCOM IMS PROCESS RESTART:
- Exactly one `kill -TERM 3184` targeted the verified `org.codeaurora.ims` process at 2026-09-18T09:08:07+08:00.
- Persistent process restarted as PID 23125 within 24 ms and rebound within 58 ms.
- Both slot MMTEL features were recreated and READY after about 2.2 seconds.
- No new qti.cne IMS request, UDP/4500, XFRM, IMS registration, VOICE/IWLAN, or WFC appeared through 180 seconds; final 195.7-second sample remained F1.
- China Telecom mapping remained protected; its shared MMTEL service connection was transiently unavailable for about 2.216 seconds and then READY.
- Result: `QCOM_IMS_RESTART_RECOVERY=FAIL`. Candidate B was not executed.

PHASE 8B CNE/QTIDATASERVICES RESTART:
- Exactly one `kill -TERM 3170` targeted the verified shared `.qtidataservices` process at 2026-09-18T09:21:00+08:00.
- Process restarted as PID25920 in about 30 ms; CneApp and co-hosted IWLAN services rebound within about 225 ms.
- No new qti.cne IMS request, ePDG, XFRM, IMS registration, VOICE/IWLAN, or WFC appeared through 120 seconds.
- slot0 safety gate and wlan0/tun0 remained intact. Result: `CNE_RESTART_RECOVERY=FAIL`.

PHASE 8C FAST-FOLLOW:
- All technical and dual-SIM gates passed for independent init service `vendor.cnd`.
- Exactly one `kill -TERM 1838` was executed at 2026-09-18T10:05:29+08:00; init restarted cnd as PID909.
- No observable CNE callback replay, qti.cne IMS request, ePDG/XFRM, IMS registration, VOICE/IWLAN, or WFC appeared through 120 seconds.
- Slot1 residual IWLAN/HOME fell to UNKNOWN after the restart. slot0 mapping and wlan0/tun0 remained protected.
- Result: `CND_RESTART_RECOVERY=FAIL`. No additional write is authorized or pending.

PHASE 8D COORDINATED CND + CNE RESTART:
- Safety gates passed in the preserved active/enabled F1 state.
- One root TERM restarted cnd from PID909 to PID7716; after stabilization, one root TERM restarted `.qtidataservices` from PID25920 to PID7876.
- CneApp and all co-hosted IWLAN services rebound. Generic qti.cne INTERNET/listener requests were recreated, but no IMS capability request or observable native IMS-demand callback replay appeared.
- PS/WLAN remained UNKNOWN, IWLAN preferred remained false, and no ePDG/XFRM or direct IMS/WFC health appeared through 122.6 seconds.
- slot0 and wlan0/tun0/VPN/airplane state remained protected. Result: `COORDINATED_CND_CNE_RESTART=FAIL`.
- No further radio/modem/SSR experiment is authorized or pending.

WRITE_BUDGET:
- fault_injections_used: 4 / 4
- level1_write_experiments_used: 10 / 10

VALIDATED RECOVERY CONTRACT:
- A: If subId 11 is inactive, slot mapping is lost, and UICC applications are disabled, execute exactly one hard-coded `ISub.setUiccApplicationsEnabled(true,11)` after all VOXI and protected-slot0 gates pass.
- B: If `goldenStrong=true`, perform no write.
- C: If subscription is active but WFC is unhealthy, perform no automatic write, do not call false, and do not call resetIms; report the probe state and `failureClass`.

HISTORICAL 3/3 CHECKPOINT:
- Target: subId 11 / slot 1 / phoneId 1 / carrierId 28 / MCCMNC 23415.
- IMS: REGISTERED (2), WLAN (2).
- MMTEL VOICE/IWLAN: available and capable.
- WFC availability: true.
- IMS IWLAN NetworkAgent: 104.
- qti.cne IMS request: 380.
- UDP/4500 NAT-T keepalive: present.
- China Telecom slot0/subId1/MCCMNC46011: protected and active.
- `ITelephony.resetIms(1)` was never executed and is not part of automatic recovery.

CURRENT RECONCILED CHECKPOINT:
- Direct IMS/WFC: REGISTERED(2), WLAN(2), VOICE/IWLAN true, WFC availability true.
- User-visible WFC icon: PRESENT.
- ePDG: UDP/4500 keepalive and bidirectional XFRM tunnel present.
- Dedicated IMS IWLAN NetworkAgent: absent supporting signal, not a direct-health failure.
- Stability: 31/31 direct-health samples passed over 301 seconds; slot0 protected.

LATEST F1 EXPERIMENT:
- Real active/enabled F1 -> one false -> persistent F8 -> one true.
- Partial recovery reached REGISTERED(2), WLAN(2), VOICE/WFC true, MMTEL READY, and UDP/4500 keepalive.
- IMS IWLAN NetworkAgent remained absent, but user-visible WFC, direct IMS/WFC APIs, UDP/4500, and bidirectional XFRM/ePDG were healthy.
- Reconciliation observed 31/31 passing direct-health samples over 301 seconds with slot0 protected.
- Final result PASS; no resetIms was executed and no further F1 experiment is permitted.

PHASE 6 RESETIMS SLOT1 CONTROLLED TEST:
- Current-ROM scope and fixed target safety gate passed.
- Exactly one `ITelephony.resetIms(1)` was executed at 2026-09-17T23:01:55.429+08:00.
- Qualcomm IMS received paired slot1 disable/enable registration-change requests and returned both Binder/radio responses.
- The follow-up registration query returned `General_Error17-Unable to connect` on IWLAN.
- No new qti.cne IMS request, ePDG UDP/4500, XFRM, IMS registration, VOICE/IWLAN, or WFC appeared through 120 seconds.
- Slot0 remained protected. Result: `RESETIMS_RECOVERY=FAIL`; no second write was executed.
