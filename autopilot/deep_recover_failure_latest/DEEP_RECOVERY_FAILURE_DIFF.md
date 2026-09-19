# VOXI WFC Deep Recover Failure Differential Analysis

Date: 2026-09-17 (Asia/Shanghai)  
Device: Xiaomi 14 Pro, serial `fd0ff892`  
Target: slot 1 / phoneId 1 / subId 11 / carrierId 28 / MCC-MNC 234-15  
Protected: China Telecom slot 0 / subId 1 / carrierId 2237 / MCC-MNC 460-11

## Scope and preservation

This investigation was read-only on the phone. No recovery command, UICC write, IMS reset, radio reset, network change, reboot, process kill, or fault injection was performed. Files were written only to this local evidence directory.

The current failure scene was preserved with full, unfiltered service dumps and logcat buffers. `dumpsys telephony_ims` returned no text on this build even though the service is listed; `dumpsys phone` contains the useful ImsResolver/feature history and is used below.

The device contains two consecutive failed Deep Recover logs after the approximately 30-second successful run:

- `deep-recovery-20260917-223704.log`
- `deep-recovery-20260917-223916.log`

The latest run (22:39) is the primary subject. The immediately preceding 22:37 run has the same missing-qti.cne signature and is corroborating evidence.

## Current preserved state

- Subscription 11: ACTIVE
- UICC applications: ENABLED
- IMS: NOT_REGISTERED (0)
- IMS transport: UNKNOWN (-1)
- VOICE/IWLAN: UNAVAILABLE
- Wi-Fi calling: UNAVAILABLE
- Failure class: F1
- MMTEL feature: READY
- IMS NetworkAgent: MISSING
- qti.cne IMS request: registered=NO, active=NO, request=null, satisfied=null
- ePDG UDP/4500: MISSING
- XFRM: MISSING
- Safety Gate: PASS
- China Telecom slot 0: still active/mapped correctly; no adverse state observed

## Exact operation times

| Run | false call | confirmed F8 | true call | result |
|---|---:|---:|---:|---|
| Success 19 s | 21:01:28 | 21:01:30.204 | 21:01:34 | F0 at probe elapsed 19 s |
| Success 50 s | 21:51:45 | 21:51:47.171 | 21:51:51 | F0 at probe elapsed 50 s |
| Success ~30 s (logged 28 s) | 22:28:37 | 22:28:40 | 22:28:42 | F0 at probe elapsed 28 s |
| Failure 1 | 22:37:06 | 22:37:07.426 | 22:37:11 | remained F1 through 60 s |
| Failure 2/latest | 22:39:17 | 22:39:19.098 | 22:39:22 | remained F1 through 60 s |

The shell log records process exit status `0`; the Android binder result described by the operator was `1`. Both runs clearly reached F8 before the one corresponding enable operation.

## Latest failed run: millisecond timeline

Reference point: `true,11` at 22:39:22.

| Time | Relative | Layer | Event |
|---:|---:|---|---|
| 22:39:17.000-17.045 | -5.0 s | Subscription/MMTEL | Disable transition begins; MMTEL reports NOT_READY/connection unavailable. |
| 22:39:17.309 | -4.691 s | ImsResolver | Slot 1 MMTEL and RCS listeners change subId 11 -> -1. |
| 22:39:17.554-17.572 | -4.446 s | ImsResolver/MMTEL/RCS | Slot-1 controllers are removed/re-added for subId -1; MMTEL is UNAVAILABLE. |
| 22:39:19.098 | -2.902 s | Probe | Strict F8 confirmed: subscription absent, slotId -1. |
| 22:39:22.000 | 0 | Operation | Single enable (`true,11`) invocation. |
| 22:39:22.124 | +0.124 s | MMTEL | Feature reports READY while still on transitional subId -1. This is not final recovery. |
| 22:39:22.321 | +0.321 s | Subscription | subId 11 is re-added active on slot 1 with UICC applications enabled. |
| 22:39:22.382 | +0.382 s | ImsResolver | MMTEL and RCS listeners change subId -1 -> 11. |
| 22:39:22.693 | +0.693 s | Carrier records | `QtiDNC setEssentialRecordsLoaded to true`. |
| 22:39:22.747 | +0.747 s | CarrierConfig | Qti phone/DNC/DCM receive `onCarrierConfigLoadedForEssentialRecords`. |
| 22:39:24.364 | +2.364 s | CarrierConfig/IMS | `onCarrierConfigChanged slotId=1`; RCS state is UNAVAILABLE with `NO_IMS_SERVICE_CONFIGURED`, exactly as in the successful run. |
| 22:39:24.478-24.483 | +2.478 s | ImsResolver | Slot-1 MMTEL and RCS controllers are actually removed and re-added for subId 11. Qualcomm IMS service remains bound. |
| 22:39:24.534 | +2.534 s | CarrierConfig/Data | Carrier-specific data config applied with `mSimState=LOADED`. |
| 22:39:24.535-24.539 | +2.535 s | MMTEL | MMTEL connection cycles DISCONNECTED -> READY for subId 11; state/provisioning/SMS/call tracker clients receive a fresh READY feature. |
| 22:39:24.632 | +2.632 s | IWLAN | PS/WLAN remains HOME/IWLAN; vendor qti IWLAN service is already bound. |
| +4 s through +60 s | | Recovery probes | ACTIVE + ENABLED + MMTEL READY, but IMS stays NOT_REGISTERED/UNKNOWN; qti.cne request stays null; UDP/4500 and XFRM stay absent. |
| Current dump | | Qualcomm/CNE | `org.codeaurora.ims`, `imsdatadaemon`, `imsqmidaemon`, and `ims_rtp_daemon` are alive. qti.cne still owns normal Wi-Fi/cellular listener requests, but owns no IMS request for subId 11. |

## Common successful pre-branch sequence

The 22:28 successful run and both failed runs match through all of these stages:

1. Subscription 11 disappears and strict F8 is reached.
2. Enable restores the active subscription/UICC mapping.
3. TelephonyNetworkFactory[1] changes back from subId -1 to subId 11.
4. Essential records become true and CarrierConfig callbacks are delivered.
5. Carrier-specific data config reaches SIM `LOADED`.
6. ImsResolver changes slot 1 from subId -1 to subId 11.
7. MMTEL is removed, re-added, and reaches READY for subId 11.
8. RCS follows the same listener transition. In both success and failure it reports `NO_IMS_SERVICE_CONFIGURED`, so that RCS condition is not the discriminator.
9. PS/WLAN reports HOME/IWLAN.

Therefore Subscription, UICC, CarrierConfig, TelephonyNetworkFactory subscription matching, ImsResolver reassignment, and basic MMTEL binder readiness are not the first failed stage.

## Successful-run branch

For the 22:28 successful run (`true` at 22:28:42):

- 22:28:42.291: subscription 11 becomes active.
- 22:28:42.632: TelephonyNetworkFactory[1] is back on subId 11.
- 22:28:42.867: essential records true.
- 22:28:42.924: essential CarrierConfig callbacks complete.
- 22:28:44.748: carrier-specific data config is loaded.
- 22:28:44.749-44.753: final MMTEL remove/add/rebind completes and READY is delivered for subId 11.
- 22:29:00.687: first recovery probe that distinguishes the successful path sees UDP/4500 and XFRM present.
- **22:29:01.576: first new logged qti.cne event — TelephonyNetworkFactory[1] receives NetworkRequest id 265, capability IMS, subId 11, requestor `com.qualcomm.qti.cne`.**
- 22:29:01.577: TelephonyNetworkFactory accepts it (`shouldApply true`).
- 22:29:01.579: DNC-1 adds the IMS request.
- 22:29:04.034 probe: qti.cne request 265 is registered and IMS is REGISTERING over WLAN.
- 22:29:06.934 probe: IMS is REGISTERED over WLAN and VOICE/IWLAN plus WFC are available.

The other successful logs show the same state progression at different latency:

| Success log | First ePDG/XFRM probe | First qti.cne request probe | Registered probe |
|---|---:|---:|---:|
| 19 s | 12 s | 15 s, request 106 | 19 s |
| 50 s | 36 s | 36 s, request 277 | 50 s |
| ~30 s (28 s logged) | 21 s | 24 s, request 265 | 28 s |

Thus variable delay is normal, but every successful recovery eventually creates a new qti.cne IMS request and an ePDG/XFRM path before registration.

## Failed-run branch and first divergence

Both failed runs complete the common sequence by roughly true+2.5 s. They then remain silent at the step where the successful run enters IMS network acquisition:

- no `com.qualcomm.qti.cne` IMS NetworkRequest reaches TelephonyNetworkFactory[1];
- no DNC-1 `onAddNetworkRequest` for IMS/subId 11 occurs;
- no ePDG UDP/4500 keepalive appears;
- no XFRM state appears;
- no IMS REGISTERING/WLAN transition occurs;
- IMS remains NOT_REGISTERED/UNKNOWN through the 60-second observation window.

The first observable success-only state is ePDG/XFRM in the 22:29:00.687 probe. The first decisive logged qti.cne event is the request at 22:29:01.576. The failed run lacks both.

This is **not** a TelephonyNetworkFactory matching rejection: in the successful run it accepts the request, while in the failed runs no equivalent request arrives for it to evaluate. It is also not a missing subscription-change delivery: qti.cne UID 10104 retains a phone-state listener for subId 11, and the subscription/IMS framework histories show the 11 -> -1 -> 11 transition.

## Component findings

### Subscription and UICC

PASS. The enable operation restores the exact slot 1/subId 11/carrier 28 mapping, ACTIVE state, and UICC applications enabled state. The same restoration occurs in successful and failed runs.

### CarrierConfig

PASS / downgraded as a cause. In both success and failure, essential records become true, the three Qualcomm essential-record callbacks fire, `onCarrierConfigChanged slotId=1` occurs, and carrier-specific data config reaches SIM `LOADED`. Current config also exposes VOXI WFC availability. No missing CarrierConfig milestone was found.

### ImsResolver

PASS at framework/controller level. `dumpsys phone` proves slot 1 goes 11 -> -1 -> 11, and shows real remove/put controller operations. `org.codeaurora.ims/.ImsService` remains bound with MMTEL and emergency MMTEL features on both slots.

### MMTEL/RCS

MMTEL framework reconstruction PASS, IMS functional recovery FAIL. MMTEL is not merely displaying a stale READY: it is removed, re-added with subId 11, and its clients receive a fresh READY feature. However, READY only proves binder/feature availability, not IMS registration or network acquisition.

RCS also transitions -1 -> 11. Its `NO_IMS_SERVICE_CONFIGURED` state occurs in both the successful and failed runs, so it is not the first divergence and is not a credible root cause for this WFC failure.

### Qualcomm IMS

Partially alive, but the post-rebind network-start sequence is missing. `org.codeaurora.ims`, `imsdatadaemon`, and `imsqmidaemon` remain running; the Qualcomm IMS service is bound and provides a READY MMTEL binder. The available log buffers contain no post-true `turnOnIms`, registration-state-query, or vendor callback-registration event that can prove the internal trigger advanced. Absence of those log lines alone is not proof because vendor logging is sparse, but the missing downstream qti.cne request is objective.

### qti.cne

First confirmed failed layer. qti.cne is not wholly dead: UID 10104 retains ordinary Wi-Fi and cellular INTERNET listeners and a subId-11 phone-state listener. What is absent is specifically a new IMS-capability request for subId 11. This favors a stuck/missed Qualcomm IMS-to-CNE request-generation trigger or stale CNE IMS state over a lost generic Connectivity callback registration.

The evidence cannot distinguish with high confidence between:

- Qualcomm IMS did not re-issue the request/registration trigger after MMTEL rebind; and
- qti.cne received the upstream change but its IMS request state machine did not create the request.

It does distinguish both from TelephonyNetworkFactory rejection, because no request reached that layer.

### IWLAN/ePDG

IWLAN data-service readiness is present (`PS/WLAN HOME`, vendor qti IWLAN bound), but IMS tunnel establishment never starts/completes. ePDG UDP/4500 and XFRM are absent throughout both failed observation windows. This is downstream of, or parallel to, the missing qti.cne IMS acquisition trigger—not evidence that subscription or CarrierConfig failed.

### VPN/TUN and location-visible state

At evidence collection:

- Wi-Fi is connected, validated, and usable on `wlan0`.
- FlClash VPN is connected and validated with `TRANSPORT_VPN`, interface `tun0`, underlying Wi-Fi, and an IPv4 default route through tun0.
- `tun0` is UP/LOWER_UP with 172.19.0.1/30.
- The VPN service remains active in logcat before, during, and after the successful and failed recoveries; no VPN disconnect/reconnect or Wi-Fi loss event was found around either failed `true` call.
- Location service history continues to show permitted CountryDetector activity after the failures.

This strongly rules out a missing Wi-Fi/VPN/TUN structure or a contemporaneous network-interface switch. It does **not** prove that the public egress IP/geolocation was identical, because no historical public-IP sample was recorded for the successful and failed instants. Therefore “same UK exit IP” cannot be asserted retrospectively; it remains an unverified environmental variable, but it is less likely than the directly observed missing qti.cne request.

## Root-cause assessment

The enable operation successfully rebuilds Subscription/UICC, CarrierConfig, ImsResolver, MMTEL, and IWLAN framework state. Recovery then stalls at the Qualcomm IMS/CNE network-acquisition boundary: no new qti.cne IMS NetworkRequest is generated for subId 11, so TelephonyNetworkFactory/DNC never receive an IMS demand, ePDG/XFRM never materialize, and IMS never transitions to REGISTERING/WLAN.

Most precise conclusion supported by the evidence:

> A stale or missed post-rebind trigger inside the Qualcomm IMS-to-CNE path prevented creation of the subId-11 IMS NetworkRequest. The failure is upstream of TelephonyNetworkFactory request matching and downstream of successful subscription/CarrierConfig/MMTEL reconstruction.

Confidence is HIGH for the location of the first divergence (missing qti.cne IMS request / missing ePDG start), and MEDIUM for assigning the internal defect specifically to Qualcomm IMS versus the qti.cne IMS request state machine because vendor-private callback logs are absent.

## Recommended next action

**READ-ONLY.** Preserve the ACTIVE + ENABLED + F1 scene. Do not repeat false/true and do not execute resetIms now.

If a later, separately authorized write experiment is accepted after preservation, `resetIms(1)` is the narrow candidate because the framework rebuild is complete while the Qualcomm IMS/CNE request-generation stage is stuck. This report does not execute or recommend immediate execution of that candidate.

## Evidence inventory

- `wfc_probe_raw.txt`
- `wfcctl_status.txt`
- `dumpsys_isub.txt`
- `dumpsys_phone.txt`
- `dumpsys_telephony_registry.txt`
- `dumpsys_connectivity.txt`
- `dumpsys_carrier_config.txt`
- `dumpsys_wifi.txt`
- `dumpsys_vpn_management.txt`
- `dumpsys_location.txt`
- `ip_link.txt`, `ip_addr.txt`, `ip_route_all.txt`, `ip_rule.txt`
- `getprop.txt`, `ps_full.txt`, `dumpsys_services.txt`
- `logcat_full_threadtime.txt`
- `logcat_all_buffers_threadtime.txt`
- all five listed Deep Recover logs and the boot-auto log
- three millisecond-sorted filtered timeline files

