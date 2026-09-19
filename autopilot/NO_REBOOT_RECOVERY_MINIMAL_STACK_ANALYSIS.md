# NO-REBOOT RECOVERY MINIMAL STACK ANALYSIS

## Scope

Read-only synthesis of existing evidence. No device command, process signal, service restart, SIM/UICC write, radio action, or new fault injection was performed.

## Evidence boundary

### Confirmed successful path

The rebooted Golden capture rebuilt the boot process set, then recorded:

- 07:53:29: `com.android.phone` bound fresh `vendor.qti.iwlan` DataService and NetworkService connections for both phones.
- 08:00:37: slot 1 PS/WLAN changed `UNKNOWN -> IWLAN/HOME`; DNC-1 evaluated requests.
- 08:01:40.437: `com.qualcomm.qti.cne` created IMS request 263 for subId 11.
- 08:01:40.446: DNC-1 accepted it and selected the Vodafone UK IMS profile over IWLAN.
- 08:01:42.152 onward: IMS registered over WLAN; VOICE/IWLAN and WFC became available.

The private native callback immediately before the Android request was not retained in logcat. Current-ROM code proves the required path is `cnd -> NativeHalServerCallback.requestNetwork(true, IMS, slot1) -> DataCallAgent -> ConnectivityManager.requestNetwork`.

### Confirmed failed partial rebuilds

- `resetIms(1)` reached Qualcomm ImsRadio off/on and registration query, but produced no CNE IMS request.
- Restarting `org.codeaurora.ims` rebuilt both slots' ImsServiceSub/MMTEL features and READY state, but no CNE IMS request.
- Restarting `.qtidataservices` rebuilt CneApp, NativeHalConnector, IWlanDataService, IWlanNetworkService, and QualifiedNetworksService, but no native IMS replay.
- Restarting `vendor.cnd` cleared residual IWLAN/HOME to UNKNOWN but did not replay IMS demand.
- Restarting `vendor.cnd` then `.qtidataservices` rebuilt the native/Java CNE boundary and created ordinary INTERNET/listener requests 563/564/565, but not an IMS-capability request.

This excludes simple Java IMS rebind, Java CNE tracker reconstruction, IWLAN service rebind, cnd restart, and cnd/CNE restart order as sufficient repairs.

## Reboot delta

| Component/state | Rebuilt by full reboot | Rebuilt in Phase 8 | Relevance |
|---|---|---|---|
| `com.android.phone` | Yes; new Phone/ImsPhone, DNC, TelephonyNetworkFactory and IWLAN client bindings | No | Important untested framework cache/binding boundary; affects both slots |
| `system_server` / ConnectivityService | Yes; request/provider tables start empty | No | Broad, but downstream of missing CNE request; not first candidate |
| `org.codeaurora.ims` | Yes | Yes, Phase 8A | Insufficient alone |
| `.qtidataservices` / CneApp / vendor IWLAN services | Yes | Yes, Phases 8B/8D | Insufficient alone or after cnd |
| `vendor.cnd` | Yes | Yes, Phases 8C/8D | Insufficient alone or before CNE Java restart |
| `imsdatadaemon` | Yes; PID 1 child, `init.svc.vendor.imsdatadaemon=running` | No | Most direct untested native IMS/data boundary upstream of cnd demand |
| `imsqmidaemon` | Yes; PID 1 child, `init.svc.vendor.imsqmidaemon=running` | No | Untested native IMS/QMI state; likely paired with IMS data control |
| `ims_rtp_daemon` | Yes | No | Media-plane component; downstream of registration, low causal fit |
| `.dataservices` | Yes | No | Not shown to own CNE IMS demand or IWLAN service; low initial priority |
| `netd`, keystore, IPsec/IKE | Yes | No | Downstream tunnel support; no IMS demand existed, so not the first failed layer |
| `qcrild`, modem/radio | Yes | No | Broad/high-risk and explicitly outside the requested candidate envelope |

Reboot also clears process-local caches that software remove/insert does not necessarily clear: Phone/ImsPhone objects, DNC request evaluation state, TelephonyNetworkFactory state, ConnectivityService request ownership, CNE tracker/callback state, IMS-radio client registrations, and native IMS/QMI data state. Device logs directly confirm fresh process creation and fresh bindings; the exact cache variables are inferred from component ownership.

## Missing from previous restart experiments

The important omissions were:

1. Native IMS control/data daemons: `imsdatadaemon` and `imsqmidaemon`.
2. Telephony framework process: `com.android.phone`, including Qti phone objects, DNC-1, TelephonyNetworkFactory[1], Phone/ImsPhone and all IWLAN client bindings.
3. ConnectivityService/system_server request tables.
4. `.dataservices`, netmgrd and the radio/modem stack.

Items 3 and 4 should not be promoted merely because they were omitted: the observed failure occurs before ConnectivityService receives an IMS request, and no evidence implicates WWAN data, netd, RTP, or modem reset.

## First reboot-only event before IMS request

The earliest retained relevant event is the fresh `com.android.phone -> vendor.qti.iwlan` DataService/NetworkService binding at 07:53:29. The first state transition closer to demand is slot-1 PS/WLAN `UNKNOWN -> IWLAN/HOME` at 08:00:37. The first decisive downstream event is CNE IMS request 263 at 08:01:40.437.

The logically required event between IMS enable and request 263 is the private `cnd -> NativeHalServerCallback.requestNetwork(true, netType 11, slot1)` callback or its immediate dispatch. It is source-confirmed but not directly retained in the reboot log. Phase 8D proves that restarting cnd and its Java callback endpoint is not enough to synthesize that callback; an upstream producer/state input remains stale.

## Candidate stacks

### Candidate A: native IMS-data source only

- `imsdatadaemon`

Rationale: smallest untested component on the upstream side of the missing cnd IMS demand. It is a PID-1 child and has an init service state, but the exact init rc/restart policy must be captured before any experiment; automatic respawn after TERM is expected, not yet proven from the saved rc text.

Expected effect: rebuild native IMS data state and its connection toward CNE without resetting subscription, UICC, modem, Android telephony, Wi-Fi, or VPN.

Risk: device-wide vendor IMS-data interruption for both slots; active IMS calls/WFC would drop. Not slot scoped. Lower blast radius than restarting `com.android.phone`, but still a native shared service.

### Candidate B: native IMS control pair

1. `imsqmidaemon`
2. `imsdatadaemon`
3. if both respawn and reconnect, rebind `org.codeaurora.ims` only if no IMS demand appears naturally

Rationale: rebuilds the QMI/control and data portions that full reboot resets but Phases 8A-D left untouched. The Java IMS service is last because restarting it alone already failed; after fresh native state it may re-register radio callbacks and replay `turnOnIms` in a meaningfully different environment.

Risk: both-slot IMS interruption and native vendor scope. It does not intentionally reset qcrild/modem/SSR, but dependencies and init behavior must be verified first.

### Candidate C: framework-inclusive soft boot stack

1. native `vendor.cnd`, `imsqmidaemon`, `imsdatadaemon`
2. `.qtidataservices` (CneApp plus all vendor IWLAN services)
3. `org.codeaurora.ims`
4. `com.android.phone` last, so it recreates Phone/ImsPhone, DNC, TelephonyNetworkFactory and binds to already-fresh vendor services

Rationale: closest no-reboot approximation to the observed boot ordering while excluding qcrild, modem, SSR, netd, system_server and radio power changes.

Risk: high. This is device-wide telephony/IMS framework reconstruction, interrupts both SIMs, and can transiently remove all telephony Binder services and data-service bindings. It is still narrower than a full reboot but is not slot-1 scoped.

## Components not recommended in the minimal stack

- `ims_rtp_daemon`: registration/media consumer, not IMS demand producer.
- netd, keystore, IPsec/IKE: tunnel/data-plane services downstream of the missing request.
- ConnectivityService/system_server: broad and downstream; no request reached it.
- `.dataservices`: no evidence it owns the Qualcomm CNE IMS request path.
- qcrild, modem, SSR, radio power: excessive risk and no evidence they are required.

## Recommended controlled experiment

Candidate A is the next minimal diagnostic experiment, not an established repair:

1. Preserve strict F1 and verify both SIM identities, Wi-Fi/VPN/TUN, and absence of IMS request/ePDG.
2. Statistically locate the current ROM init definition for `vendor.imsdatadaemon`; prove TERM causes init respawn and does not invoke modem SSR or qcrild restart.
3. Resolve and verify the exact current PID, PPID 1, UID `radio`, SELinux `vendor_ims`, binary name and init service.
4. Permit exactly one graceful TERM only after a separate explicit approval.
5. Observe new PID, native/CNE callback registration, a new subId-11 IMS request, DNC-1 acceptance, ePDG/XFRM and direct WFC health for 120 seconds.
6. On failure, stop. Do not automatically add `imsqmidaemon`, `com.android.phone`, or another restart in the same experiment.

If Candidate A fails cleanly, Candidate B is the next evidence-driven boundary. Candidate C should be reserved for a later, separately approved experiment because of dual-SIM telephony impact.

## Confidence

- Location of first divergence, before CNE submits the IMS request: HIGH.
- Exclusion of RTP/netd/IPsec/keystore as the first repair layer: HIGH.
- `imsdatadaemon` as the smallest useful next experiment: MEDIUM.
- Exact minimal no-reboot stack that will recover WFC: LOW until a controlled native-IMS experiment succeeds.