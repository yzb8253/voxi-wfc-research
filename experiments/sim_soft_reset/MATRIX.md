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
| L2-01 | 2 | `setSimPowerStateForSlot(1, POWER_DOWN)` then `POWER_UP` | Standard Radio HAL SIM-card power cycle; should generate ABSENT/NOT_READY/READY and UIM re-init | Target slot only by API contract; temporary slot1 loss | Slot mapping proven: framework slot 1 -> `IRadio/slot2` -> `IUim/Uim1` -> qcrild2/stack 1. Method chain, constants, callback and rollback remain to prove | Preferred next static-analysis target; blocked by script |
| L2-02 | 2 | Restart target `vendor.qcrild2` only | Rebuild slot1 RIL/UIM clients | Earlier qcrild2 depended on primary QtiBus and crash-looped; can interrupt slot1 cellular | Exact init service known; old M2 result failed after coordinated pair recovery | Quarantined; script requires an extra override |
| L3-01 | 3 | Direct Qualcomm `IUim/Uim1` card reset/power method | Closest vendor UIM reset below Android telephony | Method/transaction mistakes can wedge slot1 UIM until modem/AP reboot | HAL instance verified, callable reset method not verified | Blocked; no raw transaction is encoded |
| L3-02 | 3 | `cmd phone restart-modem` | Reinitialize the whole baseband and both UIM clients | Both SIMs drop and rescan; cellular data interruption; not AP reboot | ROM command verified; implementation still needs source audit for AP-reboot fallback | Quarantined high risk |
| L4-01 | 4 | Reload `com.android.phone` | Rebuild UiccController, SubscriptionController, registry and telephony framework clients | Both slots; prior broader userspace reconstruction failed | Two live `com.android.phone` PIDs require ownership mapping | Blocked by script |
| L4-02 | 4 | Coordinated RIL pair restart | Rebuild Radio HAL/QtiBus/QMI clients | Both SIMs and cellular data; prior M2 failed | Previously executed and failed | Quarantined; not a next candidate |

## Recommended route

1. Preserve the current active/enabled F1 scene with L0-00.
2. Slot-to-Radio/UIM/QMI mapping is complete in `SLOT_MAPPING/VOXI_SLOT_MAPPING.md`. Continue static tracing of `setSimPowerStateForSlot(1, state)` through `ITelephony`, `PhoneInterfaceManager` and `CommandsInterface`, then prove constants, callback and rollback behavior.
3. Build a fixed-target helper accepting only `dry-run`, `power-down` and `power-up`; prove that slot argument 1 maps to physical slot1/Radio `slot2` and that no slot0 loop exists.
4. Run L2-01 once with a mandatory finally-path power-up and 180-second observation. This is a materially different hypothesis from restarting RIL/IMS processes: it asks the modem UIM stack to emit a real card lifecycle.
5. Use L1-01 only as the established framework baseline/control. Do not repeat failed RIL/process experiments before L2-01 evidence is available.
6. Consider L3-01 only if the standard Radio SIM-power path cannot create READY events. Never guess raw HIDL/QMI transaction IDs.

## Per-test questions

Every run report must answer:

- Did slot1 emit ABSENT/NOT_READY followed by READY/LOADED?
- Did subId 11 disappear and return, or only its UICC applications change?
- Was a fresh Qualcomm IMS/CNE NetworkRequest created?
- Did UDP/4500 and bidirectional XFRM return?
- Did the four-part WFC health rule pass, and at what time?
- Did slot0 return with subId 1/MCCMNC 46011 and retain ordinary service?
