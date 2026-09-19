# VOXI slot / Radio / UIM / QMI mapping

## Result

The target mapping is confirmed without changing SIM, UICC, RIL or modem state.

| SIM | Android slot index | phoneId | subId | MCCMNC | Carrier ID | Display / SIM operator | Radio HAL | Qualcomm UIM | RIL/QMI path |
|---|---:|---:|---:|---:|---:|---|---|---|---|
| VOXI | **1** | **1** | **11** | **23415** | **28** | `voxi` / `vodafone UK` | **`IRadio/slot2`** | **`IUim/Uim1`** | **`vendor.qcrild2` (`qcrild -c 2`) / stack 1** |
| China Telecom | **0** | **0** | **1** | **46011** | **2237** | `中国电信` / `中国电信` | **`IRadio/slot1`** | **`IUim/Uim0`** | **`vendor.qcrild` / stack 0** |

Android slot and phone identifiers are zero-based. The standard HIDL Radio instance names on this ROM are one-based (`slot1`, `slot2`), while Qualcomm UIM and modem stack identifiers are zero-based (`Uim0`, `Uim1`, stack 0/1). Therefore Android slot index 1 correctly maps to Radio HAL `slot2`, not `slot1`.

## Privacy-preserving card identity

The collector located each card in the current `ActiveSubInfoList`, held its ICCID only in process memory, and hashed the exact ICCID bytes without a trailing newline. No complete ICCID is saved.

| SIM | ICCID SHA-256 |
|---|---|
| VOXI | `9aa5bd6adf03349dd9546b55e1abaab82c8f81e65531cb9f9991ae01b343c20f` |
| China Telecom | `2f7ecad7bbc8011968a2de41a10712b6185f196eb5dbbac331cd66ab409030d7` |

## Evidence chain

1. `dumpsys isub` reports `sSlotIndexToSubId[0]=[1]` and `sSlotIndexToSubId[1]=[11]`. Its active records map China Telecom to slot 0 and VOXI to slot 1.
2. `dumpsys telephony.registry` contains active listeners for `subId=1 phoneId=0` and `subId=11 phoneId=1`.
3. `dumpsys phone` contains IMS listeners `slotId=0/subId=1` and `slotId=1/subId=11`.
4. SIM properties are ordered by phone/slot: `gsm.sim.operator.numeric=[46011,23415]` and `gsm.sim.operator.alpha=[中国电信,vodafone UK]`.
5. `persist.vendor.radio.msim.stackid_0=0` and `stackid_1=1` preserve the zero-based Android slot-to-modem-stack mapping.
6. `lshal` exposes paired `IRadio/slot1`, `IRadio/slot2`, `IUim/Uim0`, `IUim/Uim1`, `IQtiRadio/slot1`, `IQtiRadio/slot2`, `oemhook0/1` and `imsradio0/1` instances.
7. Init properties identify primary `vendor.qcrild` and target `vendor.qcrild2`. The target cmdline is `/vendor/bin/hw/qcrild -c 2`; both processes load `libril-qc-hal-qmi.so`, `libqmi_client_qmux.so` and the Qualcomm Radio UIM library.
8. The existing read-only WFC probe independently confirms VOXI `slotId=1/phoneId=1/subId=11` and protected China Telecom `slotId=0/subId=1` with both mapping gates true.

The ordinary Binder `service list | grep -i uim` does not expose Qualcomm UIM because it is a vendor HIDL service; `lshal` is the authoritative inventory here. This ROM also has no service named `subscription`, so `dumpsys subscription` returns “Can't find service”; the actual subscription dump service is `isub` and both outputs are preserved.

## QMI qualification

The logical QMI routing boundary is confirmed as modem stack 1 inside `vendor.qcrild2` for VOXI. The target process loads the Qualcomm QMI transport and UIM HAL libraries and owns anonymous IPC sockets. A named QMI client ID or physical QRTR/QMUX endpoint is not exposed by the read-only `/proc` view, so the report does not invent one.

For the future SIM-power helper, the fixed target chain is therefore:

```text
VOXI MCCMNC 23415
  -> subId 11
  -> Android slotIndex/phoneId 1
  -> android.hardware.radio IRadio/slot2
  -> vendor.qti.hardware.radio.uim IUim/Uim1
  -> vendor.qcrild2 (/vendor/bin/hw/qcrild -c 2)
  -> modem/QMI stack 1
```

China Telecom must remain outside the write path:

```text
China Telecom MCCMNC 46011
  -> subId 1
  -> Android slotIndex/phoneId 0
  -> IRadio/slot1
  -> IUim/Uim0
  -> primary vendor.qcrild
  -> modem/QMI stack 0
```

## Conclusion

- **VOXI = Android slot 1 / phoneId 1 / subId 11.**
- **China Telecom = Android slot 0 / phoneId 0 / subId 1.**
- A future slot-scoped SIM-power experiment must target framework slot index `1`, which routes to Radio HAL `slot2`, Qualcomm UIM `Uim1`, qcrild2 and modem stack 1.
- No SIM power, UIM reset, qcrild action or other phone write was executed during this analysis.

Confidence: **HIGH** for subscription/slot/phone/Radio/UIM/qcrild/stack mapping; **MEDIUM** for the unnamed physical QMI transport endpoint, which remains intentionally unspecified.
