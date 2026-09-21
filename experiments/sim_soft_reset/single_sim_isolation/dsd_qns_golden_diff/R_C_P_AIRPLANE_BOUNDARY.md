# R/C/P Airplane Boundary

Date: 2026-09-21

## Scope and safety

- Compared one timestamp-aligned sequence on the same boot and device: R (airplane on, WFC healthy), C (airplane off), and P (airplane on again after Wi-Fi/VPN/location restoration).
- The same audited read-only snapshot script was used for all three states.
- No SIM operation, process restart, Binder/HIDL business method, QMI request, property change, setting change, or other phone write was performed by Codex.
- Raw captures remain host-only under the Git-ignored `captures/` directory.

## State summary

| Field | R: clean/WFC | C: cellular | P: poisoned pre-SIM |
|---|---|---|---|
| Subscription/UICC | ACTIVE / ENABLED | ACTIVE / ENABLED | ACTIVE / ENABLED |
| PS/WLAN | HOME / IWLAN | HOME / IWLAN (framework residual) | HOME / IWLAN |
| `mIsIwlanPreferred` | true | false | true |
| IMS registration | REGISTERED (2) | NOT_REGISTERED (0) | NOT_REGISTERED (0) |
| IMS transport | WLAN (2) | UNKNOWN (-1) | UNKNOWN (-1) |
| VOICE/IWLAN | available | unavailable | unavailable |
| WFC availability | true | false | false |
| qti.cne IMS request | active, request 267 | released during R->C | absent |
| IMS NetworkAgent | active, network 102 | absent | absent |
| UDP/4500 / XFRM | active / active | absent / absent | absent / absent |

## R -> C

- At 08:55:38 the existing IWLAN IMS data call is deactivated and Connectivity releases qti.cne request 267.
- TelephonyNetworkFactory and DNC remove the satisfied IMS request previously attached to `DN-102-I`.
- IMS registration, network 102, UDP/4500, and XFRM disappear.
- At 08:55:40 native `NetworkAvailabilityHandler` processes an intent-to-change indication, reports IMS as `[EUTRAN,UNKNOWN]`, and completes the IMS intent with `preferredRat=EUTRAN`.
- The retained `LastReportedNetworkAvailability` therefore records IMS as EUTRAN.

## C -> P

- At 08:58:47 the native per-APN lists are reset to UNKNOWN.
- At 08:58:50 IMS becomes `[UNKNOWN,IWLAN]`; this differs materially from the successful R history, where IMS became `[IWLAN,UNKNOWN]` and was followed by `type=IMS networks=[IWLAN,UNKNOWN]`.
- Existing static analysis established that `convertResultList` suppresses a list whose first entry is UNKNOWN. Consistent with that rule, no new outbound `type=IMS` IWLAN report is present in P.
- `LastReportedNetworkAvailability` remains IMS=EUTRAN from C. It is not replaced by an IWLAN report.
- Android nevertheless restores PS/WLAN from UNKNOWN to IWLAN/HOME and sets `mIsIwlanPreferred=true`.
- No new qti.cne IMS request reaches Connectivity, TelephonyNetworkFactory, or DNC; ePDG/XFRM and IMS registration therefore remain absent.

## Reboot boundary

The persistent R/P boundary is not basic readiness. In all states, `DsdServiceReady`, `WdsServiceReady`, `IWLANEnabled`, and `ModemCapability` are true; `globalPrefSys=IWLAN`; and native network-service registration is HOME.

- R success history: IMS `[IWLAN,UNKNOWN]` -> outbound IMS/IWLAN availability report -> qti.cne IMS request -> DNC IWLAN data call -> ePDG/XFRM -> IMS/WFC.
- P failure: IMS `[UNKNOWN,IWLAN]` -> no outbound IMS/IWLAN report -> no qti.cne IMS request -> no IMS data path.

Boot-only initialization was observed at 08:20 (`performDataModuleInitialization`, NetworkAvailabilityHandler construction, initial profile/qualified-network setup). None of those lifecycle entries reran during R->C->P. The captures do not prove which individual boot call fixes the ordering, but they do prove that airplane toggling only updates the existing session and does not recreate it.

## Candidate minimum boundary and experiment

Candidate subsystem: fixed slot2 QCRIL DataModule / IIWlan `NetworkAvailabilityHandler` and its modem-facing DSD AP-assist session.

Candidate minimum reset: recreate only that slot2 DSD/WDS indication-registration plus NetworkAvailabilityHandler/callback lifecycle, then require a fresh IMS list whose first usable transport is IWLAN. Do not reset the modem, radio, SIM, or Android framework.

NEXT_MINIMUM_EXPERIMENT: static-audit a single fixed-slot2 entry point that reinitializes the DSD AP-assist indication session and NetworkAvailabilityHandler without changing SIM/radio state. Only after that audit, run one separately authorized controlled invocation while recording whether `[UNKNOWN,IWLAN]` becomes `[IWLAN,UNKNOWN]` and produces a new qti.cne IMS request.

Confidence:

- Failure boundary: HIGH.
- Exact minimum reset mechanism: MEDIUM.