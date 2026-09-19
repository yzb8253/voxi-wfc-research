# Good WFC Causal Map

## Scope

Target: VOXI subId 11, slot 1, phoneId 1. Protected: China Telecom subId 1, slot 0.

## Confirmed Runtime Sequence

1. `[DEVICE CONFIRMED]` `vendor.qti.iwlan` is bound for WLAN transport on phoneId 1.
2. `[DEVICE CONFIRMED]` At 08:01:40.437, UID 10104/package `com.qualcomm.qti.cne` created NetworkRequest id 263 with CELLULAR transport, IMS capability, and `TelephonyNetworkSpecifier mSubId=11`.
3. `[DEVICE CONFIRMED]` At 08:01:40.446, DNC-1 evaluated request 263 as `NEW_REQUEST`, selected the Vodafone UK IMS APN (`23415`, APN `ims`), IWLAN, and `RESTRICTED_REQUEST` allowance.
4. `[DEVICE CONFIRMED]` At 08:01:40.447, DNC-1 began setup; at 08:01:40.475, DN-101 entered ConnectingState with `accessNetwork=IWLAN`.
5. `[DEVICE CONFIRMED]` At 08:01:42.152, slot 1 changed to IMS `registered=true`; registration technology subsequently reported `1` (IWLAN in this ROM/API context).
6. `[DEVICE CONFIRMED]` At 08:01:42.249, MMTEL feature for subId 11 was READY and PS/WLAN registration was HOME/IWLAN.
7. `[DEVICE CONFIRMED]` In the stable state, NetworkAgent 101 is `MOBILE[IWLAN] CONNECTED extra: ims`, subId 11, IMS/MMTEL/VALIDATED, interface `rmnet_data2`, with PCSCF addresses.
8. `[DEVICE CONFIRMED]` The underlying Wi-Fi network has an active UDP/4500 NAT-T keepalive. Direct APIs return REGISTERED(2), WLAN(2), voice-over-IWLAN available/capable, and Wi-Fi Calling available.

## Current-ROM Static Chain

1. `[SOURCE CONFIRMED]` Native CNE calls `IServiceCallback.requestNetwork(true, NetRequestInfo{rat, slot})`.
2. `[SOURCE CONFIRMED]` `NativeHalServerCallback.requestNetwork(true, ...)` dispatches a RAT-requested event to `DataCallAgent`.
3. `[SOURCE CONFIRMED]` `DataCallAgent.startDataCall(netType, slot)` maps slot to the active subId and creates a Tracker.
4. `[SOURCE CONFIRMED]` For slot 1, Tracker builds a request using CELLULAR transport, the mapped capability, and a subId network specifier, then calls `ConnectivityManager.requestNetwork`.
5. `[SOURCE CONFIRMED]` netType 11 maps to IMS capability 4. The observed runtime request exactly matches this shape and is owned by `com.qualcomm.qti.cne`.
6. `[DEVICE+SOURCE CONFIRMED]` Connectivity routes the request to TelephonyNetworkFactory/DNC-1, which selects the IMS APN and IWLAN data service.
7. `[INFERRED]` IWLAN/ePDG/IKE creates the IMS data path and NAT-T keepalive; Qualcomm IMS then registers MMTEL over WLAN.

## Release Path and Failure Hypothesis

1. `[SOURCE CONFIRMED]` Native `requestNetwork(false, ...)` dispatches RAT-unrequested; `DataCallAgent.tearDownDataCall` removes the Tracker and unregisters its Connectivity callback.
2. `[DEVICE CONFIRMED]` Phase 4D-2 logged qti.cne releasing its subId 11 IMS request during software removal.
3. `[DEVICE CONFIRMED]` Subscription, CarrierConfig, ImsResolver, MMTEL READY, PS/WLAN HOME, and IWLAN preference later returned, but the active qti.cne IMS request/IMS NetworkAgent was absent and the user observed WFC loss.
4. `[SOURCE CONFIRMED]` Subscription-change handling replays requests stored in `mPendingNetworkRequests`; an explicitly unrequested Tracker is removed rather than necessarily retained as pending.
5. `[INFERRED]` A race or missing native CNE re-request can therefore leave a superficially healthy framework state without IMS demand, IMS APN NetworkAgent, ePDG data path, or true MMTEL registration.

## Minimum Strong-Golden Fingerprint

- Safety mapping gate passes for both slots.
- subId 11 is active and UICC applications are enabled.
- IMS registration state is REGISTERED(2).
- IMS transport is WLAN(2).
- MMTEL voice over IWLAN is available and capable.
- Wi-Fi Calling availability is true.
- Active qti.cne IMS request exists for subId 11.
- Active IMS/IWLAN NetworkAgent exists for subId 11.
- UDP/4500 NAT-T keepalive exists.

`IWLAN HOME` plus `MMTEL READY` alone is not a valid WFC success condition.
