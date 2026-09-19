# Phase 8B CNE/qtidataservices Restart Result

## Verdict

`CNE_RESTART_RECOVERY = FAIL`

## Target and Scope

- Old PID: 3170.
- Process: `.qtidataservices`.
- UID/domain: 10104 / `vendor_qtidataservices_app`.
- Hosted services: `com.qualcomm.qti.cne/.CneApp`, IWlanDataService, IWlanNetworkService, QualifiedNetworksServiceImpl, and CACertService.
- Excluded and untouched: PID3125 `.dataservices`, `org.codeaurora.ims`, `com.android.phone`, FlClash, system_server, radio/modem state.
- Restart method: exactly one `kill -TERM 3170` at 2026-09-18 09:21:00 +08:00.
- New PID: 25920.

## Restart Timeline

- 09:21:00.136: old PID 3170 died; IWLAN NetworkService disconnected and DNC-1 WLAN data service unbound.
- 09:21:00.141: ActivityManager scheduled CneApp and co-hosted IWLAN service restarts.
- 09:21:00.166: new PID 25920 started, about 30 ms after death.
- 09:21:00.210: new process bound, about 74 ms after death.
- 09:21:00.358-00.361: IWlanDataService/NetworkService rebound; DNC-1 WLAN data service bound.
- 09:21:00.418: slot1 PS/WLAN remained HOME/IWLAN.

## Outcome Through 120 Seconds

- New qti.cne IMS NetworkRequest: NO.
- IMS NetworkAgent: MISSING.
- UDP/4500: MISSING.
- XFRM: MISSING.
- IMS: NOT_REGISTERED (0).
- Transport: UNKNOWN (-1).
- VOICE/IWLAN: UNAVAILABLE.
- WFC: UNAVAILABLE.
- Failure class: F1.
- slot0 safety gate: PASS throughout.
- wlan0 and tun0: remained UP with unchanged addresses.

Restarting the Java CNE/qtidataservices process cleanly rebuilt CneApp and all co-hosted IWLAN services, but did not cause native cnd to replay an IMS demand.

## Phase 8C Qualification

Read-only inspection identified an eligible independent native daemon:

- init service: `vendor.cnd`
- binary: `/system/vendor/bin/cnd`
- observed PID: 1838
- PPID: 1
- UID: 1000
- SELinux: `vendor_cnd`
- init rc: `/vendor/etc/init/cnd.rc`
- not a qcrild/modem/SSR/radio-stack service

All technical FAST-FOLLOW prerequisites passed. The attempted Phase 8C execution request was rejected by the host safety reviewer before command launch, so native cnd was not terminated. No workaround or retry was attempted.
