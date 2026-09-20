# Autopilot Findings

## Absent-state Attempt Finding (2026-09-20)

- A dedicated watchdog marker is not sufficient by itself: the audited Java helper independently gates POWER_DOWN on the exact generic `watchdog.ready` path.
- The mismatch caused a safe pre-API rejection. No `power_down.sent` marker, card teardown, or process TERM occurred, so this run says nothing about whether absent-state soft reboot can restore WFC.
- Failure handling must distinguish rejection before the helper's down marker from failure after marker creation. Only the latter needs immediate POWER_UP.
- The corrected watchdog bridges and cleans both ready markers; the corrected orchestrator does not issue POWER_UP for a pre-marker rejection.

## L1.5 Executor Pre-execution Findings (2026-09-20)

- The generated DEX resolves only the callback overload of `TelephonyManager.setSimPowerStateForSlot`.
- DEX disassembly proves the reflected invocation's slot argument is compile-time constant 1; state is restricted to 0 or 1.
- Slot0 appears only in protected-state verification and has no power invocation path.
- The helper accepts only closed command tokens and no numeric target or transaction arguments.
- Device DRY_RUN validated VOXI sub11/slot1/phone1/carrier28/MCCMNC23415 and China Telecom sub1/slot0/carrier2237/MCCMNC46011, both SIM READY.
- The independent watchdog successfully validated the same-boot rollback arm and emitted `watchdog.ready`.
- With no POWER_DOWN marker, the watchdog exited at its absolute 60-second deadline and never invoked POWER_UP.
- This checkpoint validates preparation only. No evidence about the effect of real slot1 SIM power cycling has been produced yet.

## Confirmed Good Fingerprint

- VOXI is subId 11, slot 1, phoneId 1, carrierId 28, MCCMNC 23415.
- Direct IMS state is REGISTERED (2).
- Registration transport is WLAN (2).
- MMTEL VOICE over IWLAN is available and capable.
- VoWiFi setting and Wi-Fi Calling availability are true.
- `MOBILE[IWLAN] CONNECTED extra: ims` exists with IMS/MMTEL/VALIDATED and subId 11.
- qti.cne owns an active IMS request for subId 11.
- UDP/4500 NAT-T keepalive is STARTED.
- PS/WLAN is HOME and IWLAN preferred is true.

## Historical Fault Injection

Phase 4D-2 `ISub.setUiccApplicationsEnabled(false, 11)` reproduced a transient software-remove lifecycle:

- subId and activeDataSubId 11 -> -1 -> 11.
- CarrierConfig CLEAR_CONFIG -> no-SIM -> ESSENTIAL_LOADED -> LOADED.
- ImsResolver 11 -> -1 -> 11.
- MMTEL/RCS remove/add/rebind and UNAVAILABLE -> READY.
- IWLAN exited and later returned superficially.
- qti.cne released its IMS request at 2026-09-16T16:44:16.414441.

The user later observed WFC was lost despite IWLAN HOME and MMTEL READY. Compared with today's true Golden, the historical after-state lacked the active subId11 IMS IWLAN NetworkAgent and showed the qti.cne request RELEASED.

## Leading Causal Hypothesis

The earliest likely decisive divergence is not subscription or feature readiness but loss of the IMS network demand/data path. A restored IWLAN service state can coexist with missing qti.cne IMS demand, absent IMS NetworkAgent/ePDG data path, and failed true IMS-over-WLAN registration.

## Good-State Causal Timing

- 08:01:40.437: qti.cne creates IMS NetworkRequest 263 for subId 11.
- 08:01:40.446: DNC-1 accepts it as a restricted IMS request and selects the Vodafone UK IMS profile over IWLAN.
- 08:01:40.475: DN-101 begins connecting over IWLAN.
- 08:01:42.152: IMS registration for slot 1 becomes true.
- 08:01:42.249: MMTEL for subId 11 is READY and PS/WLAN is HOME.

This observed ordering supports demand/data-path creation as a prerequisite for true IMS registration, not merely a byproduct of MMTEL readiness.

## Current-ROM CNE Behavior

- Native CNE requests a RAT/slot; CneApp's `NativeHalServerCallback` dispatches it to `DataCallAgent`.
- `DataCallAgent` maps slot to active subId and issues a Connectivity request. IMS netType 11 maps to IMS capability 4.
- The unrequest path removes the Tracker and unregisters the callback.
- Subscription recovery replays pending requests, but an explicitly removed request is not proven to remain pending.
- This provides a concrete race mechanism for `subId restored + MMTEL READY + IWLAN HOME` without an IMS NetworkAgent.

## resetIms Static Result

- The earlier Phase 3 report that saw only `disableIms` was caused by an incorrect DEX instruction-size table in the local scanner.
- After correcting the scanner, `PhoneInterfaceManager.resetIms(slotId)` is confirmed to call both `ImsResolver.disableIms(slotId)` and `enableIms(slotId)`.
- `ImsResolver` resolves the slot's subId and passes `(slotId, subId)` to the slot's IMS service controller.
- Qualcomm `ImsService` resolves `ImsServiceSub` by slot. Turn-off/turn-on send IMS registration-change requests to the IMS radio; turn-on schedules a registration-state query 1500 ms later.
- CneApp has no usable external Binder from `onBind`; its receiver handles only boot actions. No safe direct CNE re-request entry point has been found.
- A hard-coded root helper dry-run passed all VOXI and protected-slot0 gates. The only write path in that helper is `ITelephony.resetIms(1)` and it has not yet been executed.

## Evidence Standard

Recovery is accepted only when direct IMS state, transport, MMTEL voice availability, WFC availability, and the subId11 IMS IWLAN NetworkAgent are all healthy.

## Cycle 1 Experimental Result

- A single false call produced persistent F8 for at least 300 seconds; it did not auto-enable the UICC applications.
- The stored VOXI row explicitly showed `simSlotIndex=-1` and `areUiccApplicationsEnabled=false` while preserving carrierId 28 and MCCMNC 23415.
- qti.cne request 263 remained visible through 300 seconds but was eventually cleaned up before the later live probe.
- A single symmetric true call restored subId 11 mapping almost immediately, MMTEL/RCS mapping next, then created a new CNE IMS request 360 and NetworkAgent 102.
- GOLDEN_STRONG was reached by 10 seconds and remained stable through 300 seconds.
- The replacement request proves CNE can reissue demand after a complete software insert; resetIms was not needed.
- Default/active data remained subId 1 after recovery, while VOXI WFC was fully healthy. WFC recovery therefore did not require changing the default data subscription.

## Cycles 2 and 3 Validation

- Cycle 2 passed every pre-write gate, entered persistent F8 after exactly one false call, and recovered after exactly one true call. GOLDEN_STRONG first appeared at 18 seconds and remained continuous for 302 seconds. The replacement path used qti.cne request 374 and IMS NetworkAgent 103.
- Cycle 3 repeated the same controlled sequence. GOLDEN_STRONG first appeared at 37 seconds and remained continuous for 302 seconds. The replacement path used qti.cne request 380 and IMS NetworkAgent 104.
- Both cycles ended with REGISTERED (2), WLAN (2), VOICE/IWLAN available, WFC available, and an active IMS IWLAN NetworkAgent.
- China Telecom slot0/subId1 remained active and correctly mapped throughout all three cycles.
- Validation is 3/3 PASS. No cycle required resetIms, process termination, airplane-mode changes, radio reset, reboot, or CarrierConfig writes.

## Final Recovery Boundary

- The experimentally validated automatic write is true-only recovery from a verified inactive/apps-disabled F8 state.
- A healthy F0 state requires no write.
- An active-subscription WFC failure is outside the validated automatic repair envelope. It must be diagnosed and classified without injecting false or resetIms.

## Phase 8A Qualcomm IMS Process Restart

- One exact TERM of verified `org.codeaurora.ims` PID 3184 caused the persistent process to restart as PID 23125 in 24 ms and bind in 58 ms.
- ImsResolver removed and restored both slots' MMTEL/emergency feature controllers. Slot0 and slot1 MMTEL callbacks were DISCONNECTED for about 2.2 seconds, then READY.
- Slot1 immediately returned `General_Error17-Unable to connect`; MMTEL READY did not produce a CNE IMS request.
- No qti.cne IMS NetworkRequest, UDP/4500, XFRM, REGISTERED/WLAN, VOICE/IWLAN, or WFC appeared through 180 seconds. Final 195.7-second state remained F1.
- This proves that rebuilding the Qualcomm IMS service process and feature objects alone does not replay the missing native cnd/CNE network demand in this scene.
- China Telecom subscription identity remained intact. Candidate B, a qti.cne/qtidataservices restart, is only recommended for a separately authorized future test and was not executed.

## Phase 8B CNE/qtidataservices Restart

- PID3170 `.qtidataservices` was proven to host CneApp plus Qualcomm IWlanDataService, IWlanNetworkService, and QualifiedNetworksServiceImpl.
- One exact TERM restarted it as PID25920 in about 30 ms; all co-hosted services rebound within about 225 ms.
- Despite the clean restart, native cnd did not produce an observable new IMS demand and CneApp did not create a subId11 IMS NetworkRequest through 120 seconds.
- VOXI remained strict F1 with no ePDG/XFRM. slot0 and the external Wi-Fi/VPN environment remained intact.
- This moves the earliest unreplayed state boundary below the Java CNE/IWLAN process, toward native `vendor.cnd` or its upstream modem-facing input.
- `vendor.cnd` was identified as an independent init-supervised daemon, but Phase 8C was not executed because host safety approval rejected the TERM request.

## Phase 8C Native cnd Restart

- A renewed explicit authorization allowed one exact `kill -TERM 1838` after all process, strict-F1, dual-SIM, wlan0, tun0, VPN, and airplane-mode gates passed.
- Init restarted `/system/vendor/bin/cnd` as PID909 immediately, and it remained running through 120 seconds.
- No observable native callback replay or new qti.cne IMS NetworkRequest reached CneApp/TelephonyNetworkFactory. UDP/4500, XFRM, IMS registration, VOICE/IWLAN, and WFC all remained absent.
- Slot1's residual PS/WLAN IWLAN/HOME state changed to UNKNOWN and `mIsIwlanPreferred=false`; DNC-1 logged that network-request evaluation was not needed.
- China Telecom subscription identity remained protected, and wlan0/tun0/VPN/airplane state did not change.
- The restarted daemon logged a vendor-diag SELinux denial. Its causal relevance is unproven and must not be inferred from this test alone.
- Result: `CND_RESTART_RECOVERY=FAIL`. Restarting cnd alone does not reconstruct the missing IMS demand in this preserved F1 scene.

## Phase 8D Coordinated Native cnd + Java CNE Restart

- cnd was restarted first (PID909 -> PID7716), followed after stabilization by the shared `.qtidataservices` process (PID25920 -> PID7876).
- The coordinated order rebuilt CneApp, IWlanDataService, IWlanNetworkService, and QualifiedNetworksServiceImpl bindings.
- New qti.cne generic INTERNET request 563 and listener requests 564/565 prove the Java process initialized and re-registered ordinary connectivity callbacks.
- No IMS-capability NetworkRequest, DNC-1 IMS demand, UDP/4500, XFRM, or IMS registration followed. No explicit NativeHalServerCallback IMS-demand replay was visible.
- Slot1 PS/WLAN remained UNKNOWN and `mIsIwlanPreferred=false`; the result therefore did not even meet the defined PARTIAL criterion.
- slot0 mapping and the external Wi-Fi/VPN environment remained intact. `COORDINATED_CND_CNE_RESTART=FAIL`.
- Combined with Phases 8B and 8C, this shows the missing IMS demand is not restored by restarting either side of the cnd/CneApp boundary separately or in this restart order.

## F1 Active-Broken Experiment

- A real post-reboot F1 state was confirmed with subscription active/apps enabled, IMS NOT_REGISTERED, WFC unavailable, and no IMS NetworkAgent/ePDG.
- One false produced persistent F8; one true restored the subscription and CarrierConfig/IMS lifecycle.
- REGISTERING/WLAN and ePDG keepalive appeared by 27 seconds. REGISTERED/WLAN, VOICE/IWLAN, WFC availability, and MMTEL READY appeared by 30 seconds.
- A new qti.cne IMS callback request 296 existed but remained `activeRequest: null`; no IMS IWLAN NetworkAgent or IMS network ID appeared by 60 seconds or the final check around 110 seconds.
- The initial strict result was legacy F6 only because the dedicated IMS NetworkAgent was absent. User-visible WFC, direct IMS/WFC APIs, UDP/4500, and XFRM/ePDG proved the data plane healthy.
- A 301-second reconciliation produced 31/31 passing direct-health samples with slot0 intact. Final result: F1_DEEP_RECOVERY PASS and reconciled class F0_DIRECT_WFC_HEALTHY.
- NetworkAgent/qti.cne satisfaction are now supporting evidence. v1.0 remains unchanged; v1.1 may add a separate manual/experimental Deep Recover without altering default Safe Recover.
