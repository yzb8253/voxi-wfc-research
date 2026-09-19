# F6 Reconciliation Result

## Conclusion

`LEGACY F6 = HEALTHY DATA-PLANE VARIANT`

`F1_DEEP_RECOVERY = PASS`

## Direct Health Evidence

- IMS registration: REGISTERED (2).
- Registration transport: WLAN (2).
- MMTEL VOICE/IWLAN: available.
- `isWifiCallingAvailable(11)`: true.
- User-visible WFC icon: PRESENT.
- MMTEL feature: READY.
- PS/WLAN: HOME, access technology IWLAN, IWLAN preferred.

Thirty-one read-only samples over 301 seconds passed all four direct machine health conditions and protected China Telecom slot0. UDP/4500 was present in every sample.

## Data Plane

- Bidirectional ESP-in-UDP XFRM state existed between the phone and `198.18.1.101:4500`.
- XFRM policy bound inner address `10.32.101.171` to that tunnel.
- UDP/4500 NAT-T keepalive was continuously active on underlying Wi-Fi network 100.
- Therefore ePDG/IPsec was established despite the absence of a ConnectivityService IMS NetworkAgent.

## Golden Diff

Phase 5B Golden:

- Dedicated `MOBILE[IWLAN] CONNECTED extra: ims` NetworkAgent, network 101, `rmnet_data2`.
- qti.cne IMS request 263 satisfied as a non-null active request.
- UDP/4500 keepalive on underlying Wi-Fi network 100.

Current recovered state:

- No dedicated `MOBILE[IWLAN]` IMS NetworkAgent.
- qti.cne IMS callback request 296 registered but `activeRequest: null`.
- Live XFRM/ePDG tunnel and UDP/4500 keepalive on underlying Wi-Fi network 100.
- Direct IMS/WFC state and visible icon healthy.

`activeRequest: null` means ConnectivityService did not associate request 296 with a published matching NetworkAgent. It does not prove that Qualcomm IMS/ePDG has no working data plane.

## Classification Change

The dedicated IMS NetworkAgent and a satisfied qti.cne request are strong supporting evidence, not universal hard requirements on this ROM. Legacy F6 is invalid when all direct health conditions are true. F6 should be used only when direct health is false and network-demand/data-path evidence is also missing.
