# VOXI WFC Phase 7 — Qualcomm IMS/CNE Minimal Recovery Boundary

Date: 2026-09-18 (Asia/Shanghai)  
Device: Xiaomi 14 Pro, serial `fd0ff892`  
Target: VOXI slot 1 / phoneId 1 / subId 11 / carrierId 28 / MCC-MNC 234-15  
Protected: China Telecom slot 0 / subId 1 / carrierId 2237 / MCC-MNC 460-11

## Scope and safety

Phase 7 was read-only on the phone. No process or service was killed or restarted, and no IMS, subscription, UICC, radio, network, property, setting, or CarrierConfig write was performed. The only newly written material is this local analysis and its local static-analysis helper.

The preserved incident remains the Phase 6 terminal state: ACTIVE + UICC ENABLED + F1, with slot-1 `resetIms(1)` already attempted once and failed. No second reset was attempted.

## Executive result

The Android `NetworkRequest` is constructed and submitted by **CNE itself**, specifically `com.qualcomm.qti.cne.datacall.DataCallAgent$Tracker`. However, CNE does so only after the native Qualcomm CNE service (`cnd`) invokes the private vendor HIDL callback `IServiceCallback.requestNetwork(boolean, NetRequestInfo)`.

Therefore the precise answer is:

- request creator at the Android Connectivity API boundary: **B — CNE**;
- upstream demand/trigger: **D — native daemon (`cnd`)**;
- `org.codeaurora.ims` does not directly invoke CNE or Android `requestNetwork()` in the inspected APK.

The minimum unresolved boundary is now narrower than “Qualcomm IMS → CNE”: after framework `turnOnIms`, the required native `cnd` → CNE `requestNetwork(true, IMS, slot1)` callback is either not emitted, not delivered, or not dispatched by CNE. The available vendor logs do not distinguish those three sub-cases, but the failure is before `DataCallAgent` submits an IMS request to ConnectivityService.

## 1. Process, UID, SELinux, package, and component map

Snapshot PIDs are evidence-time values and must not be reused as future command targets.

| Process | PID | UID | SELinux domain | Package / role | Scope |
|---|---:|---|---|---|---|
| `cnd` | 1838 | `system` | `u:r:vendor_cnd:s0` | Native Qualcomm CNE daemon | Device-wide native CNE state |
| `imsqmidaemon` | 1846 | `radio` | `u:r:vendor_ims:s0` | Native IMS QMI daemon | Vendor IMS, both slots |
| `imsdatadaemon` | 2016 | `radio` | `u:r:vendor_ims:s0` | Native IMS data daemon | Vendor IMS/data, both slots |
| `ims_rtp_daemon` | 2498 | `radio` | `u:r:vendor_hal_imsrtp:s0` | IMS RTP daemon | IMS media, both slots |
| `.qtidataservices` | 3170 | `u0_a104` / 10104 | `u:r:vendor_qtidataservices_app:s0:c104,c256,c512,c768` | Shared Java process | CNE + IWLAN + CA certificate services |
| `org.codeaurora.ims` | 3184 | `u0_a196` / 10196 | `u:r:vendor_qtelephony:s0:c196,c256,c512,c768` | Qualcomm IMS Java service | One process hosting IMS for both slots |

### `org.codeaurora.ims`

- Standalone UID 10196; `packageList={org.codeaurora.ims}`.
- Persistent process (`*PERS*`, `persistent=true`, OOM adjustment -800).
- Hosts both `org.codeaurora.ims/.ImsService` and `.QtiImsExtService`.
- `.ImsService` is bound by `com.android.phone` through the protected `android.telephony.ims.ImsService` interface and `BIND_IMS_SERVICE` permission.
- One process and one service implementation create the per-slot `ImsServiceSub` objects. Killing it cannot be slot-1-only: slot 0 IMS is interrupted too.

### `.qtidataservices`

- Shared UID name: `com.qualcomm.qti.qtidataservices`, UID 10104.
- Persistent process (`*PERS*`, `persistent=true`, OOM adjustment -800).
- Package group:
  - `com.qualcomm.qti.cne`
  - `vendor.qti.iwlan`
  - `vendor.qti.hardware.cacert.server`
- Components simultaneously hosted in the process:
  - `com.qualcomm.qti.cne/.CneApp`
  - `vendor.qti.iwlan/.IWlanDataService`
  - `vendor.qti.iwlan/.IWlanNetworkService`
  - `vendor.qti.iwlan/.QualifiedNetworksServiceImpl`
  - `vendor.qti.hardware.cacert.server/.CACertService`
- `CneApp` is start-requested, `stopIfKilled=false`, and started at locked boot by `CneAppReceiver`.

This proves that a PID/name-level restart of `.qtidataservices` cannot restart only CNE. It also drops the IWLAN DataService, IWLAN NetworkService, QualifiedNetworksService, and CA certificate service in the same process.

## 2. CNE decompilation: actual request creator

The following chain is directly established from current-ROM `CneApp.apk` DEX:

```text
native cnd
  -> vendor.qti.hardware.data.cne.internal.server@1.0::IServiceCallback
  -> NativeHalServerCallback.requestNetwork(bringUp, NetRequestInfo{rat, slot})
  -> dispatchRatRequested(rat, slot)                       [command 5]
  -> DataCallAgent$4.onCommand(Bundle{rat, slot})          [handler message 2]
  -> DataCallAgent.startDataCall(netType, slotIndex)
  -> resolve slot 1 to subId 11
  -> new DataCallAgent$Tracker(subId=11, slot=1, netType=11)
  -> Tracker.getNetworkCapability(11) = 4 (IMS)
  -> NetworkRequest.Builder
       .addCapability(4 /* IMS */)
       .addTransportType(0 /* CELLULAR */)
       .setNetworkSpecifier("11")
       .build()
  -> ConnectivityManager.requestNetwork(request, callback, handler)
  -> TelephonyNetworkFactory[1]
  -> DNC-1 / Vodafone IMS profile
  -> vendor.qti.iwlan
  -> ePDG / XFRM
  -> IMS registration over WLAN
```

Specific static findings:

- `CneApp.onCreate()` initializes and starts `NativeConnector`, network relays, `DataCallAgent`, NAT keepalive, and RSSI offload agents.
- `NativeHalConnector.connect()` creates the private CNE HIDL service, registers `NativeHalServerCallback`, and links binder death.
- `NativeHalServerCallback.requestNetwork(true, ...)` translates native RAT/slot values and dispatches `RatRequested`.
- The `RatRequested` listener posts handler message 2; that message invokes `startDataCall`.
- `startDataCall` stores one tracker per network type and slot. If subscription information is not ready it queues the network type and `updateSubInfoReady()` later replays it.
- Network type 11 maps explicitly to Android network capability 4 (`NET_CAPABILITY_IMS`).
- Slot 1 uses the overload that adds the subId string as the network specifier.
- The successful ConnectivityService record attributes the request to UID 10104 and package `com.qualcomm.qti.cne`, exactly matching this code.

This is code-level proof that `org.codeaurora.ims` is not the Java creator of the Android request.

## 3. `org.codeaurora.ims` role and its relation to CNE

The current-ROM IMS APK establishes this separate path:

```text
framework ImsManager.turnOnIms(slot 1)
  -> org.codeaurora.ims.ImsService.enableIms(1)
  -> ImsServiceSub.turnOnIms()
  -> ImsSenderRxr.sendImsRegistrationState(1, response)
  -> Qualcomm ImsRadio / native IMS stack
  -> native registration/network demand
  -> cnd callback into CNE (required downstream boundary)
```

Related behavior:

- `disableIms/enableIms` select an `ImsServiceSub` by slot ID.
- `turnOffIms/turnOnIms` send the vendor radio registration-state command; `turnOnIms` also schedules a later action.
- `ImsRegistrationController.requestImsRegistrationState()` only calls `ImsSenderRxr.getImsRegistrationState()`; it queries state and does not create a Connectivity request.
- `ImsServiceSub.registerForImsEvents()` registers for radio indications and queries service status. It does not call CNE.
- `onRegistered`, `onRegistering`, and `onDeregistered` propagate vendor registration results to Android framework callbacks.

An exhaustive method-reference scan across `ims.apk` found **zero** references to:

- `com.qualcomm.qti.cne`
- `vendor.qti.hardware.data.cne`
- `android.net.ConnectivityManager`
- `android.net.NetworkRequest`
- `requestNetwork`

The IMS APK does contain IWLAN status and radio-tech handling, but that is indication/reporting logic, not creation of the IMS Android `NetworkRequest`.

## 4. Successful chain versus the preserved failure

### Successful Deep Recover at 22:28

Reference: `true,11` at 22:28:42.

| Time | Event |
|---:|---|
| 22:28:42.291 | subId 11 active again |
| 22:28:42.632 | TelephonyNetworkFactory[1] returns to subId 11 |
| 22:28:42.867-42.924 | essential records and essential CarrierConfig callbacks complete |
| 22:28:44.749-44.753 | final MMTEL remove/add/rebind completes; feature READY |
| 22:28:44.817 | first preserved Qualcomm/framework IMS trigger: `ImsManager [1] ... turnOnIms` |
| 22:29:00.687 | first probe that sees UDP/4500 and XFRM |
| 22:29:01.244-01.310 | CneApp dump history records RSSI profiles and `Wifi is good` |
| 22:29:01.576 | first decisive new CNE request: IMS request id 265, subId 11, UID 10104, package `com.qualcomm.qti.cne` |
| 22:29:01.577-01.579 | TelephonyNetworkFactory accepts it and DNC-1 adds it |
| 22:29:04.034 | probe sees request active and IMS REGISTERING/WLAN |
| 22:29:06.934 | REGISTERED/WLAN + VOICE/IWLAN + WFC available |

The stored log buffer does not contain a `QCNEJ/NativeHalServerCallback` line for the successful instant. Consequently the private HIDL callback itself is established by the code path and downstream request, not by a retained vendor log line. The `Wifi is good` CNE dump entry is the first retained CNE-internal timestamp, but it is an RSSI state event and should not be mislabeled as the IMS request command.

### Failed Deep Recover and Phase 6 reset

The failed 22:39 Deep Recover contains the same framework trigger:

- final MMTEL READY/rebind at about 22:39:24.535;
- `ImsManager [1] ... turnOnIms` at 22:39:24.629;
- no CNE-owned IMS request follows.

Phase 6 proves the slot-scoped Java/vendor command path itself ran:

- `ImsService.disableIms :: slotId=1`;
- `REQUEST_IMS_REG_STATE_CHANGE`, RegState 2;
- `ImsService.enableIms :: slotId=1`;
- `REQUEST_IMS_REG_STATE_CHANGE`, RegState 1;
- both vendor radio responses returned;
- the subsequent registration query returned `General_Error17-Unable to connect`, radioTech IWLAN;
- no CNE IMS request, ePDG, XFRM, or registration followed.

Thus `turnOnIms` is not the missing event. The first missing **required** internal event is:

> native CNE service → `NativeHalServerCallback.requestNetwork(true, IMS/netType 11, slot 1)`, or its immediate `RatRequested` dispatch into `DataCallAgent`.

The evidence cannot separate “`cnd` never emitted the callback” from “callback reached the Java endpoint but was not dispatched,” because QCNEJ logging for that interval is absent. It does prove that `DataCallAgent` never produced the downstream Android request.

## 5. Non-kill retrigger search

Result: **NO externally callable non-kill retrigger was found.**

- `CneApp.onBind()` returns `null`; it exposes no app Binder control API.
- `CneAppReceiver` handles only `LOCKED_BOOT_COMPLETED` and `BOOT_COMPLETED` and starts the service. It is not an IMS-request refresh API.
- The CneApp dump implementation provides diagnostics only; the current service dump shows Wi-Fi quality history and no command parser.
- `DataCallAgent.onSubscriptionsChanged()` refreshes slot/subscription readiness and only replays network types already in its private pending list. It does not synthesize a new native IMS demand.
- Native-service reconnect invokes internal callback/listener setup and `postCndUpInit()`. That method reports existing tracker results; it is not a public request-regeneration call.
- Carrier-config and ICC handlers in the IMS APK update IMS feature/config state but expose no CNE request refresh.
- `requestImsRegistrationState()` is a query, while `turnOnIms` is the path already exercised and failed.

The private HIDL `IServiceCallback.requestNetwork()` is callback direction (`cnd` → CneApp), not a safe shell/public API that can be invoked to request a retry.

## 6. Candidate recovery boundaries — analysis only

### Candidate A: restart `org.codeaurora.ims`

**Scope**

- One standalone persistent Java process, one package.
- Drops/recreates `.ImsService` and `.QtiImsExtService`.
- Rebuilds both slot-0 and slot-1 `ImsServiceSub`, radio indication registrations, service-status queries, and framework IMS binder connections.

**Risk**

- Not slot-scoped: temporarily interrupts China Telecom slot-0 IMS/VoLTE as well as VOXI slot 1.
- Active IMS calls would be at risk.
- Does not directly restart `cnd`, `imsdatadaemon`, `imsqmidaemon`, CNE, or IWLAN services.
- No direct reason to stop Wi-Fi, the VPN app, `tun0`, or routing.

**Expected effect**

- Framework ImsResolver should observe binder death and rebind automatically because the process/service is persistent and actively bound by `com.android.phone`.
- Reconstructing Qualcomm IMS Java state is stronger than `resetIms(1)` and may cause the vendor IMS/native stack to re-announce its IMS network demand to `cnd`.
- Expected recovery probability is moderate, not high: the APK has no direct CNE call, and Phase 6 already proved an off/on command reached ImsRadio without restoring the CNE request.

### Candidate B: restart `.qtidataservices` / CNE process

**Scope**

- Recreates CneApp, `NativeHalConnector`, `NativeHalServerCallback`, and all `DataCallAgent` trackers.
- Also restarts `IWlanDataService`, `IWlanNetworkService`, `QualifiedNetworksServiceImpl`, and `CACertService` because all share UID 10104 and one process.
- Services are persistent/start-requested or framework-bound and are expected to restart/rebind, but this must not be treated as slot-specific.

**Risk**

- Affects both SIM slots' IWLAN service plumbing.
- Can temporarily withdraw PS/WLAN registration and all active IMS data networks.
- May briefly disturb cellular data network qualification/selection; ordinary Wi-Fi and the third-party VPN/TUN process are separate and should remain up, but WFC traffic and an existing ePDG tunnel would drop.
- CA certificate service is collateral even though unrelated to the failure.

**Expected effect**

- Directly rebuilds the stale boundary identified in this phase: CNE's HIDL connection/callback registration and Java tracker table.
- A reconnect to `cnd` is the most direct way to solicit/replay native CNE state, so it has a stronger causal link to restoring the missing request than Candidate A.
- It has a materially broader blast radius than Candidate A because vendor IWLAN is in the same process.

## 7. Restart mechanism comparison — not executed

| Mechanism | Practical scope | Automatic recovery | Risk assessment |
|---|---|---|---|
| Kill exact app PID | One process, but all packages/components inside it | Likely for these persistent, start-requested/bound services | Narrowest process-level mechanism; PID must be freshly resolved and verified |
| Binder death/rebind | Same process death from framework perspective | IMS framework should rebind `ImsService` | Conceptually clean for A, but no public API selectively induces only that binder death |
| `killall` by name | Name-matched process(es) | Similar to PID kill | Less precise than verified PID; avoid |
| `am force-stop <package>` | Package stopped-state plus component teardown | Not reliably automatic until an allowed explicit trigger clears stopped state | Poor candidate; CNE package shares a live process/UID and force-stop semantics are broader and harder to reverse |
| Package restart command | Usually implemented with force-stop/start behavior | Depends on explicit restart target | Broader and less deterministic than a verified process death |
| `stop/start` init service | Native daemon (`cnd`, IMS QMI/data/RTP), not the Java app process | Init-controlled | Broadest; device-wide vendor IMS/CNE impact and highest slot-0 risk |

If a later phase authorizes a process experiment, `force-stop`, `killall`, and native init-service cycling should not be the first mechanism.

## 8. Preferred next controlled experiment

**Candidate A first**, solely as the minimum-blast-radius process-level diagnostic boundary.

Rationale:

1. A is one standalone package/process; B necessarily restarts CNE, IWLAN DataService, IWLAN NetworkService, QualifiedNetworksService, and CA certificate service together.
2. A is expected to trigger framework binder death/rebind and rebuild Qualcomm IMS Java/radio-indication state while leaving normal data, Wi-Fi, VPN, and CNE/IWLAN processes running.
3. A still affects slot 0 IMS and therefore requires a separately authorized, tightly observed experiment; it is not “safe” or slot-1-only.
4. If A fails with the CNE request still absent, B becomes the more causally direct but broader boundary test.

No candidate was executed in Phase 7.

## Final classification

- **IMS NetworkRequest creator:** B — CNE `DataCallAgent$Tracker`; D/native `cnd` supplies the upstream request trigger.
- **org.codeaurora.ims role:** framework/vendor IMS control, ImsRadio commands, per-slot feature and registration reporting; no direct Android network request creation.
- **qti.cne role:** native-CNE callback bridge and actual Android IMS request owner/submitter.
- **First missing internal event:** `cnd` → CNE `requestNetwork(true, IMS/netType 11, slot 1)` callback or immediate RatRequested dispatch.
- **Non-kill retrigger API:** NO externally callable candidate found.
- **Preferred next controlled experiment:** A, then B only if separately authorized and A fails.
- **Confidence:** HIGH for request ownership/process scope; MEDIUM for whether the missing callback is not emitted by `cnd` or is lost inside CNE before `DataCallAgent`.

## Evidence used

- Current read-only `ps -A` with UID/SELinux labels.
- Current `dumpsys activity processes`, service records, and package records.
- Current CneApp diagnostic dump.
- Current-ROM `CneApp.apk`, `ims.apk`, and `IWlanService.apk` static analysis.
- Phase 5 full logcat and success/failure timelines.
- Phase 6 controlled `resetIms(1)` log and probes.
- Prior full Connectivity, Telephony, ImsResolver, CarrierConfig, VPN/TUN, ePDG, and XFRM captures.
