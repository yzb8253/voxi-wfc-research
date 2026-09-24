# R4b publication-gated v4 result

Date: 2026-09-24

## Final classification

`NATIVE_PUBLICATION_NOT_READY`

`FAIL_STAGE=INITIALIZE_IWLAN_TO_NAH_PUBLICATION`

This is a valid Cycle 1 native/lifecycle counterexample. The dedicated current-generation gate—not the legacy provider observer—ran to its fixed constructor-bound 120-second deadline and failed closed. The entire series stopped immediately.

## Baseline and fixed resets

- `CONTROL_A0_R4B_V4`: captured after the one authorized reboot; airplane OFF; Wi-Fi/VPN/location environment ready; VOXI ACTIVE/UICC ENABLED/F1.
- R0: PASS, no write.
- qcrild2: `1902 -> 14900`, exactly one frozen restart; PRODUCER_READY PASS.
- qtidataservices: `3303 -> 23716`, exactly one exact-PID TERM; process epoch verified.
- phone: PID `3437`, unchanged because R3 was prohibited after gate failure.

## Current NAH generation

- Replacement constructor G: `2026-09-24 23:17:41.938`.
- Hard deadline: `2026-09-24 23:19:41.938`.
- Dedicated samples: 39, from 23:18:00.617 through 23:19:44.478 (the final poll straddled the exact deadline).
- qcrild2 remained PID 14900 in every sample.
- qtidataservices remained PID 23716 in every sample.
- Native PM/X55 gate was clean in all 39 samples: X55 ONLINE, crash count 0, pm-service sole native owner.

## Working cache timeline

Every one of 39 samples reported:

- current `NetworkAvailabilityCache` IMS present: **false**;
- current IMS networks: empty;
- `globalPrefSys=UNKNOWN`.

There was no transient working-cache PASS and no accepted old-generation LocalLog line.

## LastReported timeline

Every one of 39 samples reported:

- current `LastReportedNetworkAvailability` IMS present: **false**;
- current reported IMS network: empty.

The final IIWlan dump still showed both current containers empty. Its current-generation NAH history contained only the constructor at 23:17:41.938 and `process get qualified networks` at 23:17:41.955; it contained no later working-cache update or `type=IMS` publication.

## Supporting telemetry

- `DsdServiceReady=true`
- `WdsServiceReady=true`
- `IWLANEnabled=true`
- `ModemCapability=true`
- Framework NRM independently reported slot1 PS/WLAN HOME immediately after qtidataservices rebinding.
- Despite those ready/supporting states, the replacement NAH never acquired an IMS working entry and never built a LastReported IMS entry.
- No artificial GET was issued. The provider's natural initial query was telemetry only and did not determine the result.
- Complete per-sample IIWlan dumps, JSONL cache timeline, bounded all-buffer logcat, DSD/NAH history and slot/sub dumps remain host-only because they may contain sensitive raw device data.

## Downstream stages

- NATIVE_PUBLICATION_READY: **FAIL** (`NATIVE_PUBLICATION_NOT_READY`).
- R3: not executed.
- Post-R3 natural GET: not executed.
- A_READY/P: not executed.
- v2.6.2: not executed.
- SIM OFF/ON: `0/0`.
- M1-M7: not run.
- Cycles 2/3: not run.

## Earliest valid boundary

`initializeIWLAN -> replacement NetworkAvailabilityHandler -> first current working IMS qualification / first LastReported IMS publication`

The evidence does not justify R4c or any workaround. The next phase is read-only analysis of why the replacement generation receives no replay/fresh DSD/NAH input despite ready DSD/WDS/IWLAN capability and framework PS/WLAN HOME.

## Phone actions

Five authorized actions were issued: baseline reboot, airplane disable, Wi-Fi enable, one qcrild2 restart, and one qtidataservices TERM. There was no R3, P, SIM action, cleanup, retry, extra GET, extra restart or timeout extension.

Final read-only state: airplane OFF, X55 ONLINE, crash count 0, pm-service native ownership clean, qcrild2 PID 14900, qtidataservices PID 23716, phone PID 3437, VOXI ACTIVE/UICC ENABLED/F1, IMS NOT_REGISTERED/UNKNOWN and WFC unavailable.
