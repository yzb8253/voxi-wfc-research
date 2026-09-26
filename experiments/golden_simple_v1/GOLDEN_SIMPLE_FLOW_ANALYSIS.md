# GOLDEN_SIMPLE_V1 flow analysis

## Decision

`GOLDEN_SIMPLE_V1` tests one deliberately narrow hypothesis: a clean airplane-OFF A0, followed by the exact audited `UICC false(11) -> verified F8 -> true(11)` lifecycle, is sufficient preparation for a normal airplane-ON/IWLAN state and at most one established SIM2 software cycle. Normal execution does not stop `vendor.per_mgr`, create a holder, restart X55, restart qcrild2, or use a deep fallback.

This is a test candidate, not a claim that UICC prime is universally deterministic. Three historical successes directly associate the sequence with fresh CNE requests (360 at +10.093 s, 374 at +12.053 s, and 380 at +34.337 s), while later repetitions include failures. The experiment therefore preserves a 45-second, early-success CNE ceiling and requires an observed fresh request before declaring success.

## Historical sequence and the nine required answers

1. **Safest location for false/F8/true:** airplane OFF, after the existing repeatability preflight has either proved native-clean A0 or normalized only a recognized legacy holder/native residue. The current physical configuration is single-SIM: slot0 must remain `ABSENT` with no subscription mapped to it, while `subId11 -> slot1/carrier28/23415/apps=true` is rechecked. A dedicated single-SIM helper preserves the audited sub11 Binder sequence, 30-second F8 gate, 60-second reinsert gate, and emergency TRUE rollback without modifying the historical dual-SIM helper.

2. **Earliest safe airplane-ON point:** after the helper reports `UICC_REINSERT_CONFIRMED` and revalidates both subscription rows. Fresh CNE/IMS is not an airplane-OFF exit gate: the direct fresh-request timing captures were obtained in an IWLAN/P-like state, so requiring CNE in A0 would add a condition not established by the historical evidence.

3. **Real pre-SIM readiness:** exact VOXI mapping and enabled/active UICC; physical slot0 still `ABSENT` and unmapped; airplane ON; Wi-Fi and the existing UK VPN/TUN route ready; MMTEL `READY`; PS/WLAN `HOME`; and IWLAN preferred. This is a predecessor gate, not a success gate.

4. **CNE/IMS before the SIM cycle:** not proven mandatory. The script first gives the primed lifecycle a 45-second natural CNE/WFC observation window. If strict WFC health is already reached with a fresh request, it exits with zero SIM cycles. Otherwise the predecessor gate above authorizes one SIM cycle. It does not pretend that MMTEL or IWLAN preference is equivalent to an actual CNE request.

5. **Normal post-SIM sequence:** mapping/UICC return, then a current-table CNE request different from the immediate pre-cycle baseline (or non-null when baseline was null), then IMS `REGISTERED(2)` on `WLAN(2)`, `VOICE/IWLAN AVAILABLE`, and WFC `AVAILABLE`. Historical successful samples put fresh CNE at roughly 10.1, 12.1, and 34.3 seconds after UICC TRUE; hence the 45-second ceiling and early exit.

6. **State-driven waits:** A0 classification/normalization, verified F8, UICC reinsert, P predecessor, fresh CNE, and strict WFC health are all state driven. The only fixed lifecycle delay retained is the already validated three-second SIM-OFF hold. Polling stops immediately on success.

7. **Second automatic SIM cycle:** not authorized. Same-device automation tested repeated cycles without demonstrating a dependable second-cycle recovery (`stabilized_absent_second_reinsert` and the single-SIM reinsert experiment both failed). `MAX_SIM_CYCLES=1` is fixed.

8. **Wi-Fi/VPN/AnyWhere:** Wi-Fi and an active VPN/TUN route are reproducibility prerequisites in the validated China/UK environment and are checked. Wi-Fi may be enabled using the existing approved command. No controlled evidence proves that a specific VPN application or AnyWhere/location application is itself the causal recovery primitive, so this version only observes VPN/TUN and never changes VPN, route, location, or AnyWhere.

9. **Can normal X55 restart be removed:** yes for this isolated experiment. X55 rebirth is not part of the main path. The only native/qcrild2 work permitted is the unchanged legacy-residue normalization invoked by the existing preflight when its exact recognized fingerprint is present. Unknown native state fails closed.

## Why STABLE_CNE_V1 is frozen

Both retained runs reached SIM2 POWER ON and then called the altered UICC helper while subscription mapping was transient. They also exposed an inherited, invalid dual-SIM assumption: the real device has physical slot0 empty (`ABSENT,LOADED`), not a protected China Telecom subscription. The new helper therefore requires slot0 to remain physically absent and unmapped; it never writes slot0.

## Frozen control boundaries

- UICC transaction and rollback: independent `uicc_apps_single_sim_prime.ps1`, mechanically preserving the audited sub11 false/F8/true and emergency-TRUE behavior while replacing the historical subId1 assertion with a read-only slot0-ABSENT assertion. The original helper remains unchanged.
- Current CNE semantics: connectivity current table only, truncated before `mNetworkRequestInfoLogs`.
- SIM power: transaction 182, fixed slot 1, one OFF, three-second hold, one ON, emergency ON only if OFF was sent and normal ON was not completed.
- Success: fresh CNE plus strict IMS/WLAN/VOICE-IWLAN/WFC health.
- No resetIms, CND/qtidataservices/IMS restart, qcrild2 main-path restart, active X55 lifecycle, second SIM cycle, or deep fallback.

## Expected first-device-test interpretation

The first run answers only whether this simpler lifecycle can reach `fresh CNE -> IMS REGISTERED/WLAN -> WFC AVAILABLE`. A failure must be localized to A0, F8, reinsert, P predecessor, fresh CNE, or strict WFC. It must not be followed by an improvised recovery action.
