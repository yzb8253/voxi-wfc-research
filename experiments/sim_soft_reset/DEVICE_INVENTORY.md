# Current-ROM SIM/UICC/Radio inventory

Captured read-only on 2026-09-19 from Xiaomi 14 Pro build `V816.0.4.0.TJJCNXM`.

## Framework surfaces

- Binder `phone`: `com.android.internal.telephony.ITelephony`.
- Binder `isub`: `com.android.internal.telephony.ISub`.
- Binder `telephony.registry`: `ITelephonyRegistry`.
- Binder `telephony_ims`: `IImsRcsController`.
- Existing framework scan contains public `TelephonyManager.refreshUiccProfile()` and `setSimPowerStateForSlot(int,int)`.
- `cmd phone` exposes `disable-physical-subscription SUB_ID`, `enable-physical-subscription SUB_ID`, `restart-modem`, slot-scoped IMS commands and Radio test-service selection. It exposes no SIM refresh or SIM power subcommand.

`refreshUiccProfile()` should not be assumed to produce a modem card event merely because its name contains “refresh”. Its implementation and receiver must be traced before use.

## RIL and QMI-facing processes

The init definitions are:

```text
service vendor.qcrild /vendor/bin/hw/qcrild
service vendor.qcrild2 /vendor/bin/hw/qcrild -c 2
```

Both are disabled-class services started by platform properties and run as radio with `NET_ADMIN`/`NET_RAW`. Both were running during inventory. Supporting QMI/data services included `qmipriod`, `dpmQmiMgr`, `netmgrd`, `imsqmidaemon`, `imsdatadaemon` and `vendor.cnd`.

Earlier M2 evidence showed that qcrild2 depends on the primary qcrild/QtiBus side. A qcrild2-only restart is therefore not equivalent to a slot-local card reset and remains quarantined.

## Radio and UIM HAL

Registered services include:

- `android.hardware.radio@1.0` through `1.5` `IRadio/slot1` and `IRadio/slot2`.
- `android.hardware.radio.config` default.
- Qualcomm `vendor.qti.hardware.radio.uim@1.0` through `1.2`, instances `Uim0` and `Uim1`.
- Qualcomm `IQtiRadio/slot1` and `slot2`, `IQtiOemHook/oemhook0` and `oemhook1`.
- IMS radio instances `imsradio0` and `imsradio1`.

The presence of `IUim/Uim1` proves a service boundary, not a reset method. No direct IUim/QMI call is approved until its interface definition and qcrild handler are recovered. The standard framework SIM-power API is preferred because it should traverse the supported Radio HAL and preserve result/error semantics.

## Current state

The live probe at 22:19:56 +08:00 reported:

- VOXI fixed mapping gate PASS, active, UICC applications enabled.
- IMS `NOT_REGISTERED(0)`, transport unknown, VOICE/IWLAN unavailable, WFC unavailable.
- MMTEL READY and IWLAN preferred/HOME.
- No qti.cne IMS request, UDP/4500 or XFRM.
- China Telecom slot0 fixed mapping gate PASS.

This is a valuable active/enabled F1 baseline. Matrix creation and validation performed no SIM, radio, process or modem write.

