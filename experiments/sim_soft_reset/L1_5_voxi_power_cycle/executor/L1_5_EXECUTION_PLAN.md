# L1.5 controlled slot1 power-cycle execution plan

Status: **PREPARED AND STATICALLY AUDITED — NOT EXECUTED**

## Fixed scope

- Target: VOXI subId 11, Android slot/phone 1, carrierId 28, MCCMNC 23415.
- Radio route: `Phone[1]` → RIL request 140 → `IRadio/slot2.setSimCardPower_1_1` → `vendor.qcrild2`.
- Protected: China Telecom subId 1, slot/phone 0, carrierId 2237, MCCMNC 46011.
- Permitted power states: `CARD_POWER_DOWN(0)` and `CARD_POWER_UP(1)` only.
- Forbidden: caller-selected target identifiers, raw Binder/HIDL transaction numbers, qcrild action, radio reset, airplane toggle, modem restart, AP reboot, settings/property changes, and direct QMI UIM calls.

## Pre-execution gate

`Slot1SimPowerHelper DRY_RUN` must record and pass all of the following immediately before arming:

1. helper UID is 0;
2. VOXI maps to subId 11 / slot 1 / phoneId 1 / carrierId 28 / MCCMNC 23415;
3. VOXI UICC applications are enabled and slot1 SIM state is READY;
4. China Telecom maps to subId 1 / slot 0 / carrierId 2237 / MCCMNC 46011 and slot0 SIM state is READY;
5. current IMS registration state and transport are captured;
6. current VOICE/IWLAN and WFC availability are captured.

Any missing value or mismatch blocks POWER_DOWN.

## Execution sequence

The future controlled run is intentionally one shot:

```text
full before snapshot
  ↓
DRY_RUN strict gate
  ↓
ARM_ROLLBACK writes a same-boot token valid for five minutes
  ↓
start independent device watchdog
  ↓
wait until watchdog.ready exists
  ↓
POWER_DOWN callback request for fixed slot 1
  ↓
hold 5 seconds
  ↓
POWER_UP callback request for fixed slot 1
  ↓
after snapshot and observation
```

Both normal requests use:

```text
TelephonyManager.setSimPowerStateForSlot(
    1,
    CARD_POWER_DOWN or CARD_POWER_UP,
    direct Executor,
    Consumer<Integer> callback)
```

Callback results `SUCCESS(0)` and `ALREADY_IN_STATE(1)` are accepted. Modem error `2`, SIM error `3`, not supported `4`, timeout, exception, or any other value fails that command and remains logged.

## Independent rollback

The rollback watchdog is launched on the phone before POWER_DOWN and is independent of the host shell after startup.

- It takes an atomic single-instance lock, then verifies UID 0, both execution environment locks, the fixed helper path, the same-boot rollback token, and the protected slot0 gate.
- It writes `watchdog.ready`; POWER_DOWN refuses to run without that marker.
- It waits for the helper-owned `power_down.sent` marker. The 30-second deadline begins only after that marker appears.
- If `power_up.confirmed` is absent at the deadline, it invokes fixed `POWER_UP` itself—without waiting for user input.
- `power_up.confirmed` is written by the helper only after callback result 0 or 1.
- If no POWER_DOWN marker appears within 60 seconds, the watchdog exits without sending a power request.

The arm token contains the boot ID, fixed target/protected identities, strict pre-gate result, creation time, and five-minute expiry. It allows rollback POWER_UP when either live subscription row has temporarily disappeared during the card lifecycle, but it never changes the fixed target slot. Without that valid token, POWER_UP requires both live mapping gates.

## Evidence and logging

Each run directory must contain:

- timestamped metadata;
- `before-wfc-probe.json` and full before telephony snapshot;
- helper dry-run output;
- rollback-arm output;
- command start/end time, API and fixed arguments;
- callback time/result or exception;
- independent watchdog log;
- full logcat covering the transition;
- `after-wfc-probe.json` and full after telephony snapshot.

Raw run data remains Git-ignored because telephony dumps may contain subscriber identifiers.

## Expected event chain

The experiment is intended to produce the closest supported software equivalent of physical slot1 removal/reinsertion:

```text
slot1 SIM non-ready/absent
→ slot1 subscription/UICC teardown
→ slot1 POWER_UP
→ UIM discovery
→ SIM READY/LOADED
→ subId 11 and CarrierConfig restored
→ IMS demand / qti.cne request
→ ePDG and XFRM
→ IMS REGISTERED over WLAN
→ VOICE/IWLAN and WFC available
```

## Success criteria

The direct success rule is unchanged:

```text
registrationState = REGISTERED(2)
AND registrationTransport = WLAN(2)
AND VOICE/IWLAN available = true
AND isWifiCallingAvailable(11) = true
```

Supporting evidence includes a new qti.cne IMS request, DNC/TNF IMS demand, UDP/4500, XFRM, MMTEL READY, SIM READY/LOADED, and restored CarrierConfig. IMS NetworkAgent is not a hard success condition.

Slot0 must finish with subId 1 / slot 0 / carrierId 2237 / MCCMNC 46011 and SIM READY. Any persistent slot0 mapping, UICC, service, or IMS damage makes the experiment fail regardless of VOXI recovery.

## Risks and stop conditions

- VOXI service and any slot1 cellular state will intentionally disappear temporarily.
- Shared vendor/modem behavior may briefly affect slot0 even though the framework write is slot1-scoped.
- A process crash or ADB loss after POWER_DOWN is mitigated by the independent device watchdog, but cannot eliminate modem firmware failure risk.
- A successful callback confirms request handling, not final SIM READY or WFC health.

Stop after the single down/up sequence. Do not retry POWER_DOWN, restart qcrild, call direct IUim/QMI, toggle airplane mode, or escalate to modem/AP restart in the same run.

## Explicit non-execution statement

This preparation phase performed only source creation, shell/static audit, and documentation. `LAB_MODE=1 LAB_EXECUTE=YES` was not used, no executor artifact was deployed, no watchdog was started, and no RIL request was sent.
