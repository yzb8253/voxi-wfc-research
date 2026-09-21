# Autopilot Findings

## Single-SIM simple reinsert finding (2026-09-20)

- A fixed slot1 Radio SIM-power cycle produced the intended physical-card lifecycle: callback-successful POWER_DOWN, true ABSENT with inactive subId11/UICC disabled/lost mapping, a 10-second absent hold, then callback-successful POWER_UP.
- Reinsertion restored READY/LOADED, subId11, CarrierConfig change notification, and MMTEL READY without any process restart.
- Qualcomm IMS then reported `General_Error17-Unable to connect`; no IMS-capability demand reached qti.cne, TelephonyNetworkFactory, or DNC.
- No UDP/4500, XFRM, REGISTERED/WLAN, VOICE/IWLAN availability, or WFC appeared through 120 seconds.
- This shows that a clean single-SIM hot-remove/hot-insert lifecycle alone is insufficient. The missing state remains below or before native IMS demand generation rather than subscription, CarrierConfig, or MMTEL reconstruction.
- slot0 remained ABSENT and wlan0/tun0 remained intact. Do not repeat this candidate unchanged.

## Modem-only Restart Static Finding (2026-09-20)

- The current-ROM restart-modem shell command is hard-disabled on production user builds, even for Magisk UID0.
- Its underlying framework operation is not an AP reboot: it reaches RIL request 121 and HAL nvResetConfig with ResetNvType.RELOAD.
- Current-ROM conversion proves Java value 1 maps to HAL value 0 (RELOAD); ERASE and FACTORY_RESET are separate values 1 and 2.
- The framework route contains no PDC/MBN/EFS/persist/firmware/factory-reset call and no AP-reboot fallback. Vendor execution would nevertheless disrupt the shared modem and both SIMs.
- The connected device had about 48 hours of kernel uptime, so the claimed fresh reboot could not be established from machine evidence. It remained the prior active/enabled F1 scene.
- No restart-modem or other write was executed; recovery effectiveness remains NOT_TESTED.


## Corrected Absent-state Retry Finding (2026-09-20)

- The corrected run substantively tested the hypothesis: one callback-successful slot1 POWER_DOWN produced an inactive, unmapped, UICC-disabled ABSENT state.
- The selected qcrild/netmgr/IMS/CNE/phone/system_server stack was rebuilt. system_server returned, although Telephony Binder readiness missed the orchestrator's normal-power-up deadline.
- The independent watchdog's only fallback POWER_UP returned callback 0 and restored slot1/subId11/UICC state.
- CarrierConfig reproduced ABSENT -> CLEAR_CONFIG -> no-SIM -> ESSENTIAL_LOADED -> LOADED.
- ImsResolver/MMTEL reproduced slot1 subId -1/UNAVAILABLE -> subId11/READY.
- Despite those matches, no new qti.cne IMS request, IMS IWLAN NetworkAgent, UDP/4500, XFRM, REGISTERED/WLAN, VOICE/IWLAN, or WFC appeared.
- The final state was active/enabled F1 with IWLAN/HOME and MMTEL READY. This strengthens the finding that framework lifecycle reconstruction alone is insufficient; the full reboot restores an additional native/modem demand condition not recreated by this stack.
- Do not repeat this candidate unchanged.


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

## Stabilized absent experiment design (2026-09-20T15:15:32+08:00)

- The prior absent-state soft reboot was inconclusive because normal POWER_UP ran before Telephony Binder and the rebuilt framework graph were stable.
- The corrected hypothesis specifically tests whether preserving true ABSENT through the full stack rebuild, then requiring stable system_server/phone/isub/connectivity, stable exact process PIDs, rebound IWLAN services, network readiness, and no QtiBus serverDied event before insertion changes the result.
- If the first insertion returns only to strict F1, one final remove/10-second absent/reinsert without another process restart tests whether a second UICC lifecycle is needed after the rebuilt stack is stable.

## Stabilized absent and second reinsert finding (2026-09-20)

- True ABSENT plus a full userspace stack rebuild and stable Binder/IWLAN service window is still insufficient to recreate the native IMS data demand.
- A second clean remove/reinsert after the rebuilt stack is stable is also insufficient: subscription and IWLAN recover, but CNE IMS request, ePDG, IMS registration, and WFC remain absent.
- This materially narrows the reboot delta. The successful full AP reboot depends on a boot-only initialization/order boundary below or outside the tested qcrild/netmgrd/native IMS/CNE/IWLAN/phone/system_server restart set.
- Safety engineering finding: a watchdog deadline at 300 seconds is incompatible with the helper's five-minute rollback-arm lifetime when the arm precedes POWER_DOWN. Future tooling must make arm lifetime strictly longer than watchdog deadline plus launch margin.

## Single-SIM full userspace rebuild finding (2026-09-20)

- Rebuilding imsdatadaemon, imsqmidaemon, cnd, qtidataservices, and Qualcomm IMS in strict order does not recreate the missing native IMS demand even with slot0 physically absent.
- Qualcomm ImsService and slot1 MMTEL rebind successfully, but the initial status update fails and no qti.cne/TNF/DNC IMS request follows.
- Rebuilding cnd clears residual IWLAN/HOME and changes PS/WLAN to UNKNOWN without triggering network-request reevaluation.
- This independently excludes dual-SIM contention and the tested AP userspace IMS/data subset as sufficient recovery boundaries.

## QCRIL setDataProfile race finding (2026-09-20)

- Both physical insertion windows generated the same IMS-bearing three-profile list and completed multiple slot1 `SET_DATA_PROFILE` transactions successfully.
- First insertion: IWLAN/HOME at 20:51:04.777, but no IMS qualified-network callback before removal.
- Second insertion: IWLAN/HOME at 20:52:24.821 and `IMS -> IWLAN` qualified networks at 20:52:24.825.
- The second insertion's first new `SET_DATA_PROFILE` was later, at 20:52:25.166. It cannot be the direct cause of the callback that preceded it by 341 ms.
- The visible Java QNS was already AP-assisted before both insertions. Internal QCRIL ProfileHandler/NetworkAvailabilityHandler and DSD registration branches are not logged, so those sub-branches remain unproven rather than assumed.
- The leading missing component moves from framework profile dispatch to DSD APN availability/preferred-system indication or synchronization/replay of the native NetworkAvailability cache.
- A future discriminator is the read-semantics slot1 `IIWlan.getAllQualifiedNetworks(serial)` cache query, after static scope/safety review. It reads cache; it is not a DSD refresh or modem re-evaluation API.

## QCRIL IIWLAN cache snapshot finding (2026-09-20)

- `NetworkAvailabilityHandler::getQualifiedNetworks` is a cache-copy operation; no QMI request or cache mutation was found in its call path.
- Because a solicited HIDL result is sent to the single already registered `IWlanResponse`, no second-client callback was installed and the business method was not invoked.
- The existing HAL `IBase::debug` path safely exposed `NetworkAvailabilityHandler::dumpCache`: IMS, DEFAULT, and EIMS APNs exist, but every qualified-network list is currently empty and `LastReportedNetworkAvailability` is empty.
- This is not a missing-IMS-profile condition. It is a stale APN-level native qualified-network cache despite `globalPrefSys=IWLAN`, `DsdServiceReady=true`, `IWLANEnabled=true`, `RegistrationState=REG_HOME`, and framework `mIsIwlanPreferred=true`.
- The same internal history proves that the successful second insertion previously populated IMS with `[IWLAN,UNKNOWN]`; that qualification is absent now.
- Verdict: `NATIVE_QNS_CACHE=STALE`. Move the fault boundary to DSD APN preferred-system/availability indication or its synchronization into NetworkAvailabilityHandler.

## DSD/QNS cache-writer finding (2026-09-20)

- `updateNetworkAvailabilityCache(message)` clears and rebuilds the APN-name map during setDataProfile processing. APN types are restored, but new per-APN network vectors begin empty.
- `updateNetworkAvailabilityCache(dsd_apn_avail_sys_info...)` is the actual-system writer: it requires a non-empty APN name, maps the APN, requires at least one available system, converts supported DSD system enums (including IWLAN) and updates only when the vector changes.
- `updateNetworkAvailabilityCache(dsd_apn_pref_sys...)` is the intent writer: it requires an existing APN entry, promotes the converted preferred RAT, and sets `hasPendingIntent=true`; a later matching actual-system indication completes and clears the pending intent.
- `convertResultList` filters an empty vector or a vector beginning with UNKNOWN and cannot synthesize IWLAN from `globalPrefSys`.
- Therefore the direct current cause is an empty IMS per-APN network vector. The earlier raw DSD cause remains UNKNOWN because current dumps do not expose whether the indication was absent, zero-length, unsupported/UNKNOWN, or lost upstream.
- A fixed read-only BAD/GOLDEN capture script now records the native cache, framework health, CNE, ePDG/XFRM, and relevant logs with identical commands.

## BAD vs GOLDEN native DSD/QNS diff (2026-09-20)

- The exact same audited snapshot script captured a valid real-WFC GOLDEN state. Direct gates passed: REGISTERED(2), WLAN(2), VOICE/IWLAN available, WFC available, PS/WLAN HOME, IWLAN preferred, active qti.cne IMS request/NetworkAgent, UDP/4500, and XFRM.
- BAD SHA-256: `31727FD5AAC506D429BB14DFD205280ED0B5A2D90BC411253A9982E1189B5687`; GOLDEN SHA-256: `602E81EA342A7185BDA3000CCCDF406C77354878D17DD7BF253B28361E371CB6`.
- Current native cache fields are identical: IMS, DEFAULT, and EIMS all have `networks=[]`, all have `hasPendingIntent=false`, `LastReportedNetworkAvailability` is empty, and `globalPrefSys=IWLAN` in both captures.
- GOLDEN history did transiently contain IMS `[IWLAN,UNKNOWN]` before WFC establishment, but the current table was later empty while the established IMS path remained healthy.
- Verdict: CASE B. The current `dumpCache` table is a transient qualification/report cache, not a durable active-IMS decision state. `NATIVE_QNS_CACHE=STALE` is not a sufficient BAD/GOLDEN discriminator and the per-APN cache root boundary is not confirmed.
- The first concrete live-state difference is downstream: GOLDEN has active CNE IMS demand/NetworkAgent and ePDG/XFRM; BAD does not. The precise minimum upstream lifecycle state remains unknown.
- Phone writes: 0. No active IIWlan query, callback replacement, QMI request, SIM action, restart, or recovery action occurred.
- Sanitized report: `experiments/sim_soft_reset/single_sim_isolation/dsd_qns_golden_diff/BAD_VS_GOLDEN_NATIVE_DSD_QNS_DIFF.md`.

NEXT_ACTION: candidate only—capture a future real insert/recovery as a timestamp-aligned, read-only lifecycle trace spanning native DSD/NAH updates, ANM delivery, CNE request creation, and IMS tunnel establishment. Do not invoke refresh/query/write APIs.


## R/C/P airplane boundary finding (2026-09-21)

- A same-boot, same-command-set R/C/P capture isolated the airplane-toggle failure without a SIM operation or any Codex phone write.
- R's successful native history contains `IMS [IWLAN,UNKNOWN]`, followed by an outbound `type=IMS networks=[IWLAN,UNKNOWN]`, qti.cne request 267, DNC IWLAN setup, ePDG/XFRM, and IMS registration.
- Airplane OFF tears down request 267 and completes the native IMS intent with `preferredRat=EUTRAN`; `LastReportedNetworkAvailability` records IMS=EUTRAN.
- Airplane ON restores the native IMS cache only as `[UNKNOWN,IWLAN]`. Earlier static analysis proves `convertResultList` suppresses a list beginning with UNKNOWN, and no new outbound IMS/IWLAN report is observed.
- Framework PS/WLAN still reaches IWLAN/HOME and `mIsIwlanPreferred=true`, proving those states are downstream-insufficient. The missing event is earlier than CNE demand creation.
- DSD/WDS endpoint-ready flags, modem capability, IWLAN enablement, global IWLAN preference, and network-service HOME state are unchanged between R and P. Their boolean readiness is not the discriminator.
- The strongest reboot boundary is now the slot2 QCRIL DataModule/IIWlan NetworkAvailabilityHandler DSD APN qualification ordering/replay session, specifically IWLAN-first publication for IMS.
- `performDataModuleInitialization` and NetworkAvailabilityHandler construction occur only in boot history and do not rerun during R->C->P. The exact minimum reinitialization call remains inferred, not yet source-confirmed or tested.
- Evidence for the failure boundary is HIGH; confidence that a targeted DSD/NAH session recreation is sufficient is MEDIUM.

NEXT_ACTION: static-only audit of a fixed-slot2 DSD AP-assist indication-session and NetworkAvailabilityHandler lifecycle reinitialization entry point. Do not invoke it in the current phase.

## Minimum QCRIL reinit entry finding (2026-09-21)

- `NetworkAvailabilityHandler` has no reset API. `DataModule::initializeIWLAN()` replaces its unique_ptr, which clears per-APN and last-reported maps; `deinitializeIWLAN()` resets it but also disables IWLAN through datactl.
- A fixed-slot2 IIWlan `setResponseFunctions()` dispatches `IWLANCapabilityHandshake(true)`, which reaches `initializeIWLAN()` after readiness gates. This recreates NAH and re-registers AP-assist indications.
- That handshake path does not request a fresh DSD system-status snapshot. It immediately replays `mCachedSystemStatus`, so `[UNKNOWN,IWLAN]` can be restored into the new handler.
- `generateDsdSystemStatusInd()` performs the missing fresh DSD GET and broadcasts both global and per-APN results, but it does not recreate NAH or register indications.
- The minimum complete internal sequence is: reassert AP-assist capability, register system status, initialize IWLAN/recreate NAH, then generate a fresh DSD status indication.
- `performDataModuleInitialization()` is not a suitable narrow entry: its cold branch is broad and one-shot, while its post-ready branch does not recreate NAH.
- AP-side scope is fixed qcrild2/RIL instance 1. The QMI DSD capability and indication-registration requests contain no slot field, so modem-side isolation from slot0 is not source-proven.
- This sequence does not reset modem/radio/SIM or reboot AP, but it is state-changing QMI/datactl work and requires separate authorization.

NEXT_ACTION: candidate only. Build no executor until a fixed-instance in-process hook can be statically proven to expose exactly the four calls and no broader data/radio action.