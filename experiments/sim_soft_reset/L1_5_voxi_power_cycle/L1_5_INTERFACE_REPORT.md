# L1.5 interface report — VOXI slot power cycle

- Date: 2026-09-19
- Device: Xiaomi 14 Pro (`23116PN5BC`)
- ROM: `V816.0.4.0.TJJCNXM` / Android 13
- ADB target used: `192.168.1.25:42319`

Mode: **read-only interface discovery; zero phone writes**

## Result

The closest verified software equivalent of removing and reinserting the VOXI SIM is the standard slot-scoped Android telephony path:

```text
TelephonyManager.setSimPowerStateForSlot(slot=1, state)
  -> ITelephony.setSimPowerStateForSlot(int slotIndex, int state)
  -> PhoneInterfaceManager.getPhone(1)
  -> Phone[1].setSimPowerState(...)
  -> CommandsInterface / RIL[1].setSimCardPower(...)
  -> RadioSimProxy
  -> IRadio/slot2.setSimCardPower_1_1(serial, CardPowerState)
  -> vendor.qcrild2 / modem stack 1 / QMI UIM
```

This stage did not invoke that chain. Direct `IUim/Uim1` is **not** a card-power interface on this ROM; its exported vendor methods are for callbacks, remote SIM-lock, and (in later versions) GBA/IMPI. `RadioConfig` also has no SIM-card-power method.

## Preserved pre-state

The existing read-only probe at `2026-09-19T22:57:11.138+08:00` reported:

- VOXI mapping gate: PASS — subId `11`, slot/phone `1`, carrierId `28`, MCCMNC `23415`.
- China Telecom protection gate: PASS — subId `1`, slot/phone `0`, carrierId `2237`, MCCMNC `46011`.
- VOXI subscription ACTIVE; UICC applications ENABLED.
- PS/WLAN `HOME`, `mIsIwlanPreferred=true`.
- IMS `NOT_REGISTERED(0)`, transport `UNKNOWN(-1)`, VOICE/IWLAN unavailable, WFC unavailable.
- Failure class `F1`; combined safety gate true.

No SIM power, UIM reset, qcrild action, Binder write, or HIDL write was executed.

## Current-ROM evidence

The analysis used byte-for-byte pulls of the running ROM artifacts:

| Artifact | SHA-256 |
|---|---|
| `/system/framework/framework.jar` | `2F6AA4B89B86DE5E0E80DEC7FB8E6AE2D69F73AF73E2C51776F7B64E58C9C4D1` |
| `/system/framework/telephony-common.jar` | `BD0D407BB7A47A41BD923F79F9713174D43C3E7D98C53DFF97B226B1F8141B57` |
| `/system/priv-app/TeleService/TeleService.apk` | `C79ED4719BEA37125F3EB02943B051D6AA762F7D93481389C790F029399116A7` |

DEX tracing established:

- `TelephonyManager.setSimPowerStateForSlot(int,int)` calls `ITelephony.setSimPowerStateForSlot(int,int)`.
- `ITelephony` also defines `setSimPowerStateForSlotWithCallback(int,int,IIntegerConsumer)`.
- The current generated Binder constants are 182 and 183 respectively. They are recorded for provenance only; the lab does not issue raw `service call` transactions.
- `PhoneInterfaceManager.setSimPowerStateForSlot` first calls `enforceModifyPermission()`, whose implementation enforces `android.permission.MODIFY_PHONE_STATE`.
- It then calls `PhoneFactory.getPhone(slotIndex)` once. For slot 1 it invokes only that `Phone` object's `setSimPowerState`; there is no all-phone loop.
- `Phone.setSimPowerState` dispatches to its own `mCi.setSimCardPower`.
- `RIL.setSimCardPower` allocates RIL request `140` and calls `RadioSimProxy.setSimCardPower`.
- On an HIDL Radio HAL at least 1.1 and below 1.6, `RadioSimProxy` calls `IRadio.setSimCardPower_1_1(int serial,int state)`. This device publishes `IRadio/slot2` through HIDL 1.5, so that is its selected branch.
- Current framework constants are `CARD_POWER_DOWN=0`, `CARD_POWER_UP=1`, `CARD_POWER_UP_PASS_THROUGH=2`. Result constants are success `0`, already-in-state `1`, modem error `2`, SIM error `3`, not supported `4`.

The live service inventory reconfirmed:

- `phone: [com.android.internal.telephony.ITelephony]`.
- `IRadio/slot1` and `IRadio/slot2` published through HIDL 1.5.
- `IRadioConfig/default` published through HIDL 1.1.
- `IUim/Uim0` and `IUim/Uim1` published through vendor HIDL 1.2.
- `vendor.qcrild2` is `/vendor/bin/hw/qcrild -c 2`, UID `radio`, SELinux domain `u:r:rild:s0`.

## Interface matrix

| Layer / interface | Verified signature or command | Callable from this lab? | Permission / caller requirement | Risk | Probe conclusion |
|---|---|---:|---|---|---|
| `cmd phone` | `cmd phone help` | Read-only help: YES | shell/root | LOW | No SIM-power command exists. `restart-modem` and physical-subscription commands exist but are different write paths and remain forbidden. |
| `service call phone` | Current Binder methods 182: `(int slotIndex,int state)`; 183: `(int,int,IIntegerConsumer)` | Mechanically possible but **not approved** | `MODIFY_PHONE_STATE`; exact current Binder ABI; callback Binder for method 183 | HIGH | `service call phone` without a transaction was used only to print usage. Raw transactions are deliberately excluded from the next design. |
| `TelephonyManager` hidden/System API | `setSimPowerStateForSlot(int,int)` and callback overload `(int,int,Executor,Consumer<Integer>)` | YES from a purpose-built privileged/root helper; not invoked | `MODIFY_PHONE_STATE`; non-SDK/API access context | MEDIUM-HIGH | Preferred entry point because it preserves slot routing and framework error semantics. Callback overload is preferred for an experiment helper. |
| `TelephonyManager` convenience API | `setSimPowerState(int)` | Exists, not approved | Same permission; depends on the manager object's current slot | HIGH | Rejected for the experiment because implicit slot selection is weaker than fixed slot 1. |
| `TelephonyManager.refreshUiccProfile()` | public symbol; ITelephony receiver is `refreshUiccProfile(int subId)` | Exists, not a power cycle | privileged telephony permission | MEDIUM | Reloads the framework UICC profile; it is not proven to produce a modem card removal/insertion lifecycle. |
| `IRadio/slot2` HIDL 1.0 | `setSimCardPower(int32 serial,bool powerUp)` | HAL supports it; direct call not approved | radio HAL client identity/SELinux; response serial management | HIGH | Legacy fallback only. Current ROM should select the 1.1 form. |
| `IRadio/slot2` HIDL 1.1 inherited by 1.5 | `setSimCardPower_1_1(int32 serial,CardPowerState state)` | HAL supports it; direct call not approved | radio HAL client identity/SELinux; registered response callback; serial lifecycle | HIGH | This is the actual HAL operation selected by current framework routing. Use it only indirectly through TelephonyManager/ITelephony. |
| `RadioConfig/default` | Slot mapping, modem configuration/capability APIs; no `setSimCardPower` | NO power method | radio-config HAL client identity/SELinux | HIGH if misused | Not a SIM power-cycle interface. |
| Qualcomm `IUim/Uim1` 1.0–1.2 | callbacks, remote-SIM-lock; later GBA/IMPI calls | NO verified power/reset method | vendor HIDL client identity/SELinux | VERY HIGH | Exported symbols contain no card-power or UIM-reset method. Do not invent a transaction. |
| `vendor.qcrild2` | `/vendor/bin/hw/qcrild -c 2`; internal RIL request 140 reaches its slot2 radio path | No public command; process action forbidden | UID `radio`, `u:r:rild:s0`; init supervision | VERY HIGH | It is transport/implementation, not the desired public control surface. Restart is not equivalent to card removal. |
| QMI UIM | Internal modem protocol below qcrild2 | NO verified userspace endpoint | proprietary message definitions, QMI client/session and modem permissions | VERY HIGH | No exact standalone request/argument/callback contract was verified. Direct QMI stays blocked. |

## Failure reasons by requested path

- **`cmd phone`:** command parser has no SIM power subcommand on this ROM.
- **Raw `service call phone`:** method/signature and current transaction constants are known, but callback construction, rollback reliability, and ABI drift make the CLI path unsuitable. It was not called.
- **Ordinary third-party `TelephonyManager`:** blocked by privileged `MODIFY_PHONE_STATE` and non-SDK/System API access. A root `app_process` helper can be built later, but none exists in this stage.
- **Direct `IRadio/slot2`:** the method exists, but a correct HAL client must own serial/response handling and satisfy SELinux. Bypassing telephony would lose framework coordination.
- **`RadioConfig`:** wrong interface; it does not own card power.
- **Direct `IUim/Uim1`:** no exported card-power/reset method exists in the current 1.0–1.2 interface libraries.
- **Direct QMI UIM:** no ROM-proven external client method, request structure, or response contract was recovered; guessing is prohibited.

## Risk assessment

`setSimPowerStateForSlot(1, CARD_POWER_DOWN/UP)` is slot-scoped at the framework dispatch point, but it intentionally causes a real loss of the VOXI card state. Expected effects include slot1 subscription disappearance/recreation, carrier-config reload, IMS teardown/rebind, and temporary loss of VOXI service. It should not directly power slot0, but shared modem/vendor behavior still makes live dual-SIM verification mandatory.

The callback overload provides a result code but not a guarantee that the card has reached READY. A future helper therefore needs two independent completion checks:

1. callback result for each requested state; and
2. observed slot1 UICC state transition with the fixed mapping restored.

## Recommended next controlled experiment

Build—but do not yet auto-run—a fixed root helper that exposes only two internally hard-coded operations for Android slot `1`: power down and power up via the callback form of `TelephonyManager.setSimPowerStateForSlot`. The helper must reject any caller-provided slot, subId, transaction code, or state outside `CARD_POWER_DOWN(0)` and `CARD_POWER_UP(1)`.

Before the first write:

1. Re-run `run_l1_5_probe.sh` and require both fixed mapping gates.
2. Arm an **independent** power-up rollback process before power-down; it must not depend on the initiating helper surviving.
3. Record full logcat and WFC probes before the write.
4. Execute one slot1 down request, wait for its callback and observed slot1 non-ready/absent transition, then one slot1 up request.
5. Observe SIM READY/LOADED, subscription/UICC restoration, CarrierConfig, IMS, qti.cne, ePDG/XFRM, and WFC for at least 240 seconds.
6. Abort without escalation if slot0 mapping changes, power-down callback fails, or slot1 does not reappear. Do not restart qcrild or invoke direct IUim/QMI in the same experiment.

Status: **INTERFACE PATH VERIFIED; REAL POWER CYCLE NOT EXECUTED**.
