# Cycle 1 Result

## Writes

- 2026-09-17 09:34:55.923 +08:00: exactly one `ISub.setUiccApplicationsEnabled(false,11)`, returned 1.
- 2026-09-17 13:40:16.027 +08:00: exactly one symmetric `ISub.setUiccApplicationsEnabled(true,11)`, returned 1.
- `ITelephony.resetIms(1)` was not executed.

## Fault State

- F8 persisted at 5, 15, 30, 60, 120, and 300 seconds.
- subId 11 was inactive; slot mapping was -1 and phoneId invalid.
- The stored VOXI row remained identifiable as carrierId 28, MCCMNC 23415, with `areUiccApplicationsEnabled=false`.
- IMS was NOT_REGISTERED, transport unknown, voice/IWLAN unavailable, WFC unavailable.
- IMS IWLAN NetworkAgent and UDP/4500 keepalive were absent.
- qti.cne request 263 remained visible through 300 seconds, but was gone by the later live probe at 13:35.
- China Telecom stayed active as subId 1, slot 0, MCCMNC 46011.

## Symmetric True Recovery Timeline

- 13:40:16.027: true call starts.
- 13:40:16.064: true call returns 1.
- 13:40:16.473: UiccProfile receives RECORDS_LOADED for phoneId 1.
- 13:40:16.479: subId 11 is added to the active subscription list with slot 1 and UICC apps enabled.
- 13:40:16.593: slot 1 MMTEL subId changes to 11.
- 13:40:16.594: slot 1 RCS subId changes to 11.
- 13:40:18.424: slot 1 SIM records become LOADED.
- 13:40:18.665: ImsStateCallbackController receives CarrierConfig changed for slot 1.
- 13:40:26.097: QCNEJ DataCallAgent starts net type 11 for its slot index 2.
- 13:40:26.099: CNE resolves the request to subId 11.
- 13:40:26.120: ConnectivityService creates qti.cne IMS NetworkRequest 360.
- 13:40:26.129: TelephonyNetworkFactory[1] accepts request 360.
- 13:40:27.768: slot 1 IMS registration becomes true.
- 13:40:28.009: DNC-1 selects Vodafone UK IMS APN over IWLAN.
- 13:40:28.013: IMS IWLAN NetworkAgent 102 is registered.
- 13:40:28.611: IWLAN data setup succeeds with PCSCF addresses.
- 13:40:28.619: DN-102-I reaches ConnectedState.
- 13:40:28.671: CNE receives network 102 available.
- By the 10-second probe: GOLDEN_STRONG is true.

## Stability

GOLDEN_STRONG remained true at 10, 15, 30, 60, 90, 120, 180, and 300 seconds. Request 360, NetworkAgent 102, REGISTERED/WLAN, voice-over-IWLAN, WFC availability, and UDP/4500 keepalive remained present. The protected slot0 gate passed at every probe.

## Conclusion

For an intentionally disabled physical subscription, the minimum recovery is the symmetric true call. It naturally rebuilds subscription, CarrierConfig consumers, MMTEL/RCS mapping, CNE IMS demand, IWLAN data path, ePDG/NAT-T, and IMS registration. `resetIms(1)` is unnecessary for this cycle and remains an untested candidate only for a future active-subscription failure where true recovery does not reach GOLDEN_STRONG.

This is one successful cycle, not the required 3/3 validation.
