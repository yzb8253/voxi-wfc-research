# Phase 8D Coordinated cnd + CNE Restart Result

## Safety Gate

- Concrete device: `192.168.137.211:41111`.
- VOXI: subId 11, slot 1, phoneId 1, carrierId 28, MCCMNC 23415, active, UICC applications enabled.
- China Telecom: subId 1, slot 0, MCCMNC 46011, active; protected mapping gate passed throughout.
- Initial state: F1, IMS NOT_REGISTERED, transport UNKNOWN, VOICE/IWLAN unavailable, WFC unavailable, no qti.cne IMS request, no UDP/4500, and slot1 PS/WLAN UNKNOWN.
- Environment: wlan0 `192.168.137.211/24`, tun0 `172.19.0.1/30`, airplane mode on, FlClash PID 5080.

## Authorized Operations

1. `vendor.cnd`: PID 909 was verified as `/system/vendor/bin/cnd`, PPID 1, UID 1000, SELinux `u:r:vendor_cnd:s0`. Exactly one root-delivered TERM succeeded at 10:25:21. Init restarted it as PID 7716.
2. `.qtidataservices`: after cnd stabilized, PID 25920 was re-resolved and confirmed to host CneApp, IWlanDataService, IWlanNetworkService, and QualifiedNetworksServiceImpl. Exactly one root-delivered TERM succeeded. ActivityManager recorded its death at 10:27:04.081 and restarted it as PID 7876 at 10:27:04.105.

An earlier cnd TERM attempt ran under shell UID 2000 because of host argument quoting and returned `Operation not permitted`; PID 909 remained alive and no signal was delivered. It was not a state-changing operation. No SIGKILL or other write was executed.

## Reconnect Evidence

- CneApp and all three expected IWLAN services rebound in PID 7876.
- The new process registered a generic INTERNET request 563 and Wi-Fi/cellular listener requests 564/565.
- No explicit `NativeHalServerCallback`/HIDL IMS-demand replay was observed.
- The new qti.cne requests were generic INTERNET/listener requests, not an IMS capability request.
- No request reached TelephonyNetworkFactory/DNC-1 as a new slot1 IMS demand.

## 120-Second Result

- PS/WLAN: remained UNKNOWN.
- `mIsIwlanPreferred`: remained false.
- New IMS request: no.
- UDP/4500 NAT-T: absent.
- XFRM/ePDG: absent.
- IMS: NOT_REGISTERED (0).
- Registration transport: UNKNOWN (-1).
- VOICE/IWLAN: unavailable.
- WFC availability: false.
- MMTEL feature: READY, without registration.
- Final classification: F1.

The probes remained unchanged from the first available sample through 122.6 seconds. No success or partial-recovery criterion was reached.

## Protected State

- slot0 identity and active mapping passed every probe; no subscription remap was observed.
- The shared IWLAN services necessarily restarted and therefore created a transient shared-service interruption, but no final slot0 identity impact was detected.
- wlan0, tun0, their addresses, airplane mode, and FlClash remained unchanged.

## Conclusion

The coordinated order successfully restarted both layers, and Java CNE/IWLAN service bindings were rebuilt, but the missing native IMS demand was not recreated. Restart order alone does not repair this preserved active/enabled F1 state.

`COORDINATED_CND_CNE_RESTART = FAIL`

No radio/modem/SSR or further recovery operation was executed.
