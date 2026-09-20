# SIM soft-reset experiment matrix

## Live read-only inventory (2026-09-19)

- Device: Xiaomi `23116PN5BC`, build `Xiaomi/cas/cas:13/TKQ1.221114.001/V816.0.4.0.TJJCNXM:user/release-keys`.
- Current scene: VOXI active, UICC apps enabled, F1; IMS not registered, transport unknown, no CNE IMS request, no ePDG/XFRM.
- `vendor.qcrild` and `vendor.qcrild2` are running from `/vendor/bin/hw/qcrild` and `qcrild -c 2`.
- Standard radio HAL exposes `IRadio/slot1` and `IRadio/slot2`; Qualcomm exposes `IUim/Uim0` and `IUim/Uim1` through vendor radio UIM 1.0-1.2.
- Framework scan confirms public `TelephonyManager.refreshUiccProfile()` and `setSimPowerStateForSlot(int,int)` on this ROM.
- `cmd phone` exposes physical-subscription enable/disable and `restart-modem`; it does not expose a UICC refresh or slot power command.

## Ordered matrix

| ID | Level | Candidate | Expected physical-SIM-like boundary | Scope/risk | Static status | Execution status |
|---|---:|---|---|---|---|---|
| L0-00 | 0 | Read-only baseline | None | None | Verified | Ready |
| L1-01 | 1 | Fixed `setUiccApplicationsEnabled(false,11)` then, only after F8, fixed `true,11` | Framework subscription removal/insertion, CarrierConfig and IMS feature rebuild | Slot1 logical subscription; previously protected slot0 | Fully verified and previously 3/3 successful, with later one failed run | Ready; do not run on this preserved F1 until explicitly chosen |
| L1-02 | 1 | `TelephonyManager.refreshUiccProfile()` | Reload UICC profile objects without powering the card | Likely slot/sub scoped but exact current-ROM receiver and downstream RIL behavior unproven | API exists; invocation scope not yet proven | Blocked by script |
| L1.5-01 | 1.5 | Read-only `setSimPowerStateForSlot` interface probe | Prove the slot1 framework -> RIL -> `IRadio/slot2` path without a write | None; capture only | PASS: current-ROM DEX proves fixed-slot dispatch, `MODIFY_PHONE_STATE`, RIL request 140, and HIDL 1.1 power method; direct IUim/RadioConfig are not power interfaces | Complete; see `L1_5_voxi_power_cycle/L1_5_INTERFACE_REPORT.md` |
| L2-01 | 2 | `setSimPowerStateForSlot(1, POWER_DOWN)` then `POWER_UP` | Standard Radio HAL SIM-card power cycle; generates ABSENT/READY/LOADED and UIM re-init | Fixed slot1 only; slot0 protection gate adapted for the single-SIM ABSENT configuration | Source, rebuilt classes, DEX write surface, callback, and 90-second watchdog audited | Executed once in the single-SIM scene: FAIL; subscription/CarrierConfig/MMTEL restored but no IMS demand, ePDG, registration, or WFC. Do not repeat unchanged |
| L2-02 | 2 | Restart target `vendor.qcrild2` only | Rebuild slot1 RIL/UIM clients | Earlier qcrild2 depended on primary QtiBus and crash-looped; can interrupt slot1 cellular | Exact init service known; old M2 result failed after coordinated pair recovery | Quarantined; script requires an extra override |
| L3-01 | 3 | Direct Qualcomm `IUim/Uim1` card reset/power method | Closest vendor UIM reset below Android telephony | Method/transaction mistakes can wedge slot1 UIM until modem/AP reboot | HAL instance verified, callable reset method not verified | Blocked; no raw transaction is encoded |
| L3-02 | 3 | `cmd phone restart-modem` | Reinitialize the whole baseband and both UIM clients | Both SIMs drop and rescan; cellular data interruption; not AP reboot | Current-ROM chain is HAL RELOAD with no AP-reboot fallback; shell entry is blocked on user builds | Blocked before write |
| L4-01 | 4 | Reload `com.android.phone` | Rebuild UiccController, SubscriptionController, registry and telephony framework clients | Both slots; prior broader userspace reconstruction failed | Two live `com.android.phone` PIDs require ownership mapping | Blocked by script |
| L4-02 | 4 | Coordinated RIL pair restart | Rebuild Radio HAL/QtiBus/QMI clients | Both SIMs and cellular data; prior M2 failed | Previously executed and failed | Quarantined; not a next candidate |

## Recommended route

1. Preserve the current active/enabled F1 scene with L0-00.
2. L2-01 is complete and failed despite confirmed ABSENT/READY/LOADED. Do not repeat it unchanged or automatically fall through to a process/soft-stack action.
3. The earliest missing layer remains native Qualcomm IMS demand generation before qti.cne/TNF/DNC IMS request creation.
4. Any experiment below this boundary requires a new hypothesis, explicit authorization, and separate safety review. Never guess raw HIDL/QMI transaction IDs.

## Per-test questions

Every run report must answer:

- Did slot1 emit ABSENT/NOT_READY followed by READY/LOADED?
- Did subId 11 disappear and return, or only its UICC applications change?
- Was a fresh Qualcomm IMS/CNE NetworkRequest created?
- Did UDP/4500 and bidirectional XFRM return?
- Did the four-part WFC health rule pass, and at what time?
- Did slot0 return with subId 1/MCCMNC 46011 and retain ordinary service?
