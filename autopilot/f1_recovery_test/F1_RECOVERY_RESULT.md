# F1 Active-Broken Recovery Result

## Final Outcome

`F1_DEEP_RECOVERY = PASS`

The initial legacy-probe result was F6 because no dedicated `MOBILE[IWLAN] extra: ims` NetworkAgent appeared. Reconciliation proved that this was not a WFC failure: direct IMS/WFC APIs, the user-visible WFC icon, ePDG/IPsec data plane, and a 301-second stability run all remained healthy.

## Initial F1

- VOXI subId11 / slot1 / phoneId1 / carrierId28 / MCCMNC23415.
- Subscription active and UICC applications enabled.
- IMS NOT_REGISTERED (0), transport UNKNOWN (-1).
- VOICE/IWLAN unavailable and WFC unavailable; the initial machine gate did not depend on status-bar icon inspection.
- IMS NetworkAgent and ePDG keepalive absent.
- China Telecom slot0/subId1/MCCMNC46011 gate PASS.

## Authorized Writes

- 15:50:37.136 +08:00: exactly one `ISub.setUiccApplicationsEnabled(false,11)`, return 1, no exception.
- Persistent F8 confirmed twice.
- 15:50:45.314 +08:00: exactly one `ISub.setUiccApplicationsEnabled(true,11)`, return 1, no exception.
- No second false/true, resetIms, or other state-changing operation.

## Recovery

- 27 s: REGISTERING/WLAN and UDP/4500 keepalive.
- 30 s: REGISTERED(2), WLAN(2), VOICE/IWLAN available, WFC available, MMTEL READY.
- User confirmed the visible WFC status-bar icon was present.
- 31 samples over 301 seconds all retained the four direct health conditions; slot0 remained protected.

## Network Reconciliation

Phase 5B exposed a dedicated IMS agent on `rmnet_data2` and a satisfied qti.cne request. The current recovered path did not expose that agent: request 296 remained registered as a callback with `activeRequest: null`.

Despite that presentation difference, the current device had a live bidirectional ESP-in-UDP XFRM tunnel between `192.168.137.134:44974` and ePDG `198.18.1.101:4500`, with inner policy for `10.32.101.171`, a continuous UDP/4500 keepalive, direct IMS registration over WLAN, voice capability, WFC availability, and the visible icon. There was no actual data-plane failure.

The old NetworkAgent detection correctly reported that the old-style agent was absent; the false negative came from treating that supporting signal as an absolute health requirement. The old qti.cne parser also incorrectly called a registered `activeRequest: null` callback active.

## Decision

Reclassify the final state from legacy F6 to `F0_DIRECT_WFC_HEALTHY`. A manual, separately invoked F1 Deep Recover may be designed for v1.1, but it must remain opt-in and must not replace or broaden v1.0 Safe Recover.
