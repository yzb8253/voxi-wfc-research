# M2 Coordinated RIL Pair Recovery

Date: 2026-09-18 (Asia/Shanghai)  
Device: Xiaomi 14 Pro (`23116PN5BC`)  
ADB target: `192.168.1.25:41201`  
Result: **FAIL**

## Safety and scope

- Device was online and root was available (`uid=0`, Magisk context).
- The only phone-state write was one init start of the verified primary service: `start vendor.qcrild`.
- No target TERM was sent because `vendor.qcrild2` stabilized by itself after primary recovery.
- No modem SSR, esoc reset, radio power cycle, airplane toggle, reboot, EFS/NV/PDC/MBN write, telephony database deletion, `killall`, `pkill`, or SIGKILL was performed.

## Verified service definitions

From `/vendor/etc/init/qcrild.rc`:

- Primary: init service `vendor.qcrild`, executable `/vendor/bin/hw/qcrild`.
- Target: init service `vendor.qcrild2`, executable `/vendor/bin/hw/qcrild -c 2`.
- Both are init-managed radio services. Runtime processes used UID `radio`, SELinux domain `u:r:rild:s0`, and PPID 1.

## Pre-state

- Primary `vendor.qcrild`: absent.
- Target `vendor.qcrild2`: PID 8330, in the previously established approximately 101-second QtiBus `serverDied`/`clientLoop` crash cycle.
- Immediately before the M2 action the replacement target process logged `DSD Client unavailable`.
- Telephony binder state was incomplete (`isub` unavailable), consistent with the missing primary RIL.
- `tun0` and `wlan0` were up; ePDG UDP/4500 and XFRM were absent.

## Controlled action and RIL recovery

- Primary start time: approximately `20:36:33` local device time.
- New primary PID: **9201**.
- Primary remained stable for the complete observation window.
- Existing target PID: **8330**.
- Target PID remained unchanged and stable beyond its previous crash interval, so the conditional exact-PID TERM was not needed.
- After primary start, there were no further `serverDied`, `clientLoop`, or fatal-signal events in the captured observation window.
- The only post-start `DSD Client unavailable` line was a transient primary initialization event at `20:36:33.986`; it did not recur.

## Rebuilt control plane

- Qualcomm/Xiaomi RIL initialization completed.
- `TelephonyNetworkFactory[1]` registered and changed subId from `-1` to `11`.
- `DNC-1` was created and connected to ExtTelephonyService.
- Slot1 IMSS service-enable replay completed successfully:
  - `20:36:40.104 ... qcril_qmi_imss_set_ims_service_enable_config_resp_hdlr: ril_err: 0, qmi res: 0`
  - `20:36:40.106 ... qcril_qmi_imss_set_ims_service_enable_config_resp_ims_reg_change_hdlr: ril_err: 0, qmi res: 0`
- Slot1 returned to PS/WLAN `HOME`, data technology `IWLAN`, with `mIsIwlanPreferred=true`.

## Missing recovery chain

Across more than 180 seconds after primary recovery:

- No native IMS data demand appeared.
- No slot1 IMS request reached `TelephonyNetworkFactory[1]` or `DNC-1`.
- No `qti.cne` IMS NetworkRequest appeared.
- No ePDG UDP/4500 flow appeared.
- No XFRM state/policy appeared.
- IMS remained `NOT_REGISTERED (0)` with transport `UNKNOWN (-1)`.
- VOICE/IWLAN and WFC remained unavailable.

The generic INTERNET NetworkRequests emitted while the phone framework rebuilt are not IMS NetworkRequests and were not counted as recovery.

## Final safety gates

- VOXI: subId 11, slot 1, phoneId 1, carrierId 28, MCCMNC 23415.
- VOXI subscription: ACTIVE.
- VOXI UICC applications: ENABLED.
- Failure class: F1.
- Protected China Telecom mapping: subId 1, slot 0, carrierId 2237, MCCMNC 46011 — PASS.
- `tun0`: remained UP/LOWER_UP with its route present.

## Conclusion

M2 restored the missing primary RIL, stopped the target-RIL QtiBus crash loop, rebuilt the Android telephony control plane, and successfully replayed slot1 IMSS enable configuration. It did **not** regenerate the native IMS data demand that must precede the CNE request and ePDG bring-up. Therefore:

`M2_RIL_PAIR_RECOVERY = FAIL`

The next recorded candidate is **M3 modem SSR**. It was not executed.

## Evidence

- `m2_logcat_full.txt` — continuous full logcat covering the pre-action state, controlled primary start, and the complete observation period.
