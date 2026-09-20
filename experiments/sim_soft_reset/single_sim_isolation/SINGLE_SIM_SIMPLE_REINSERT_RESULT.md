# Single-SIM simple reinsert result

Date: 2026-09-20

Result: **FAIL — returned to ACTIVE + ENABLED + F1**

## Scope and safety

- Target was compile-time fixed to VOXI slot 1 / phoneId 1 / subId 11 / carrierId 28 / MCCMNC 23415.
- The protected slot0 gate required no active subscription and `SIM_STATE_ABSENT(1)`.
- Static audit passed immediately before execution: one fixed SIM-power API call site, no dynamic target, and no slot0 power path.
- Rebuilt Java class hashes exactly matched the committed audited class hashes. The rebuilt dex JAR SHA256 was `ae31b6893672d92851b1dd5e2ade98a27c5346d4470d1b5035e1fae486295a11`.
- An independent watchdog was ready before POWER_DOWN and had a fixed 90-second rollback deadline.
- No AP reboot, restart-modem, modem SSR, airplane toggle, process signal, system_server restart, or soft-stack action occurred.

## Exact operation

- 18:14:01.638: one `POWER_DOWN` request for fixed slot 1.
- 18:14:01.807: POWER_DOWN callback result `0`.
- 18:14:01.839: helper snapshot showed target inactive, UICC disabled, SIM state ABSENT, slot `-1`, and mapping gate false.
- 18:14:03: orchestrator independently confirmed true ABSENT.
- True ABSENT was held for 10 seconds.
- 18:14:13.418: one `POWER_UP` request for fixed slot 1.
- 18:14:13.466: POWER_UP callback result `0`; `power_up.confirmed` was written.
- 18:14:14: watchdog observed the confirmation and exited without fallback POWER_UP.

Actual SIM-power counts: one POWER_DOWN, one normal POWER_UP, zero watchdog POWER_UP.

## Reinsertion lifecycle

- SIM READY appeared at 18:14:14.202; SIM hot-plug-in was logged at 18:14:14.227.
- SIM LOADED appeared at 18:14:17.353.
- subId 11 / slot 1 / phoneId 1 / carrierId 28 / MCCMNC 23415 returned ACTIVE with UICC applications enabled.
- `ACTION_CARRIER_CONFIG_CHANGED phoneId:1 subId:11` appeared at 18:14:17.826.
- MMTEL returned READY and the slot1 callback mapping changed from subId `-1` to `11`; subId11 feature connectors were READY at 18:14:17.956.
- Qualcomm IMS reported `General_Error17-Unable to connect` at 18:14:19.565.

## Observation

Direct probes obtained from approximately +23 seconds onward, including the requested +30, +60, +90, and +120-second boundaries, were identical. The intended +5/+10/+20 host probes were delayed by tool handoff; radio/all-buffer logs cover that early interval and show READY, LOADED, CarrierConfig, MMTEL, and the IMS error timestamps above.

At +120 seconds:

- IMS registration: `NOT_REGISTERED(0)`.
- Registration transport: `UNKNOWN(-1)`.
- VOICE/IWLAN available: false.
- Wi-Fi Calling available: false.
- MMTEL: READY.
- PS/WLAN: HOME; IWLAN preferred: true.
- Native/qti.cne IMS request: absent.
- TelephonyNetworkFactory/DNC IMS request: absent; only unrelated INTERNET requests were replayed.
- IMS IWLAN NetworkAgent: absent.
- UDP/4500 keepalive: absent.
- XFRM tunnel: absent.

## Protection results

- slot0 stayed ABSENT throughout and had no power-write path.
- `wlan0` remained UP/LOWER_UP.
- `tun0` remained UP/LOWER_UP with its default route.

## Conclusion

A clean single-SIM physical-style slot1 power down, confirmed true ABSENT hold, and simple reinsert fully rebuilt SIM/subscription, CarrierConfig, and MMTEL state, but did not recreate the native Qualcomm IMS demand. The first missing recovery layer remains native IMS demand generation before qti.cne/TNF/DNC IMS request creation.

`SINGLE_SIM_SIMPLE_REINSERT = FAIL`

Do not repeat this candidate unchanged and do not fall through to soft-stack recovery.
