# Single-SIM full userspace rebuild result

Date: 2026-09-20

Result: **FAIL — no IMS demand was recreated**

## Initial gate

- Device: Xiaomi 14 Pro (`23116PN5BC`), ADB serial `fd0ff892`.
- VOXI mapping: slot 1 / phoneId 1 / subId 11 / carrierId 28 / MCCMNC 23415.
- slot0: ABSENT; two-slot state was exactly `ABSENT,LOADED`.
- VOXI was ACTIVE with UICC applications enabled and strict F1.
- IMS was NOT_REGISTERED, transport UNKNOWN, VOICE/IWLAN unavailable, and WFC unavailable.
- Residual PS/WLAN was IWLAN/HOME with `mIsIwlanPreferred=true`.
- `wlan0` and `tun0` were UP/LOWER_UP.

The static audit passed immediately before execution. The device executor repeated the fixed mapping, slot0-ABSENT, ACTIVE+ENABLED, strict-F1, process-identity, UID, SELinux-domain, PPID, and exact-command gates before sending a signal.

## Exact bounded execution

Only the five authorized current PIDs received one SIGTERM each, in the required order:

| Target | Old PID | New PID | New-PID stability time |
|---|---:|---:|---:|
| `vendor.imsdatadaemon` | 1994 | 27336 | 2 s |
| `vendor.imsqmidaemon` | 1849 | 27428 | 2 s |
| `vendor.cnd` | 1845 | 27487 | 2 s |
| `.qtidataservices` | 3151 | 27579 | 3 s |
| `org.codeaurora.ims` | 3169 | 27660 | 4 s |

`org.codeaurora.ims/.ImsService` rebound successfully. The protected `vendor.qcrild` PID 1931, `vendor.qcrild2` PID 1985, `vendor.netmgrd` PID 1856, selected `com.android.phone` PID 3208, and `system_server` PID 1643 were unchanged when the executor completed. No forbidden action was executed.

## Observation

The direct probes remained strict F1 throughout the required stabilization window and the final sample at 20:39:47.

- New native IMS data demand: NO positive evidence.
- qti.cne IMS NetworkRequest: NO.
- TelephonyNetworkFactory/DNC IMS request: NO.
- IMS IWLAN NetworkAgent: absent.
- UDP/4500: absent.
- XFRM: absent.
- IMS: NOT_REGISTERED(0).
- Registration transport: UNKNOWN(-1).
- VOICE/IWLAN available: false.
- WFC available: false.
- MMTEL feature state: READY.

The Qualcomm IMS process did rebuild both slot service objects. Slot1 became the active IMS stack and ImsResolver restored MMTEL, but the initial `EVENT_GET_STATUS_UPDATE` failed and no downstream IMS demand followed.

Restarting `vendor.cnd` also removed the residual IWLAN/HOME framework state: DNC recorded WLAN `IWLAN -> UNKNOWN` and `HOME -> UNKNOWN`, with network-request evaluation not needed. Final PS/WLAN was UNKNOWN and `mIsIwlanPreferred=false`. This is a degradation of residual state, not recovery.

## Protection results

- slot0 remained ABSENT and received no write.
- VOXI remained ACTIVE with UICC applications enabled and its fixed mapping intact.
- `wlan0` remained UP/LOWER_UP.
- `tun0` remained UP/LOWER_UP.
- qcrild, qcrild2, netmgrd, phone, and system_server were not signaled or restarted.

## Conclusion

In the single-SIM scene, rebuilding the complete permitted AP userspace IMS/data subset is insufficient to regenerate the missing native IMS demand. It also clears the otherwise residual IWLAN/HOME state when cnd is rebuilt. Do not repeat this sequence unchanged and do not append phone, system_server, RIL, modem, SIM-power, or resetIms actions to this run.

`SINGLE_SIM_FULL_USERSPACE_RECOVERY = FAIL`
