# Aggressive Final No-Reboot Experiment

## Initial state

Strict F1 with VOXI subId 11 active, UICC applications enabled, IMS NOT_REGISTERED, transport UNKNOWN, VOICE/IWLAN unavailable, WFC unavailable. China Telecom slot0 mapping and wlan0/tun0 passed.

## Phase A - Full userspace stack

- imsqmidaemon: 31349 -> 26664
- imsdatadaemon: 28722 -> 26887
- vendor.cnd: 6825 -> 27097
- .qtidataservices: 10140 -> 27335; CneApp/IWLAN/QNS rebound
- org.codeaurora.ims: 2449 -> 27710; MMTEL returned READY
- main com.android.phone: 14820 -> 28053; Phone/Subscription gate returned

Result after 120 seconds: FAIL. No new IMS demand, qti.cne IMS request, UDP/4500, XFRM, registration, or WFC.

## Phase B - system_server soft restart

- system_server: 1633 -> 2267
- Wireless ADB reappeared as 192.168.137.18:40527.
- New app/framework PIDs after framework restart: .qtidataservices 3532, org.codeaurora.ims 3553, main com.android.phone 3601.
- ConnectivityService Binder and phone/isub/carrier_config/telephony.registry/telephony_ims services were recreated.
- Telephony services and subscription mappings returned.
- PS/WLAN changed from UNKNOWN to IWLAN/HOME and mIsIwlanPreferred changed false -> true.
- No IMS demand, qti.cne IMS request, DNC IMS request, UDP/4500, XFRM, IMS registration, VOICE/IWLAN availability, or WFC appeared through 180 seconds.

Result: SYSTEM_SERVER_SOFT_RECOVERY = FAIL.

## Final state

VOXI remains active/enabled strict F1: IMS NOT_REGISTERED (0), transport UNKNOWN (-1), VOICE/IWLAN unavailable, WFC unavailable. MMTEL is READY and PS/WLAN is IWLAN/HOME, proving those states are insufficient without the missing IMS demand/data path.

China Telecom remains subId 1 / slot 0 / MCCMNC 46011. wlan0 and tun0 are UP. No XFRM state or UDP/4500 keepalive exists.

No modem reset, SSR, qcrild restart, radio power cycle, EFS/NV change, airplane toggle, UICC write, or device reboot was executed.

Conclusion: NO-REBOOT PATH NOT FOUND ABOVE MODEM/SSR BOUNDARY.