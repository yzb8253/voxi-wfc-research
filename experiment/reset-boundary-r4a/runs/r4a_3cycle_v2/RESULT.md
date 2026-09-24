# R4a three-cycle v2 result

Date: 2026-09-24

Evidence-adapter checkpoint tested: `5dd3fad`

## Classification

```text
CONTROL_A0_R4A_V2=PASS
CYCLE_1=PASS
CYCLE_2=R4A_FALSIFIED_AT_P
CYCLE_3=NOT_RUN
FIRST_MISSING_MILESTONE=M1
R4A_FALSIFIED=YES
R4A_NOT_FALSIFIED_3_CYCLES=NO
R4B_DESIGN_ELIGIBLE=YES
```

Cycle 2 is a valid counterexample. Producer readiness and the new framework epoch both passed before the fixed P transition. The runner stopped at the unchanged P gate, before v2.6.2 and before any Cycle 2 SIM write.

## Reboot baseline

- Exactly one authorized reboot established `CONTROL_A0_R4A_V2`.
- Airplane OFF, Wi-Fi/VPN/location/AnyWhere ready.
- WFC F1.
- Native ownership clean, X55 ONLINE, crash count zero.
- Baseline qcrild/qcrild2/phone/qtidataservices: 1859 / 1875 / 3466 / 3373.

## Cycle 1 — PASS

### Reset epochs

- R0_NATIVE_READY: PASS, no write.
- producer qcrild2: 1875 -> 15426.
- qtidataservices: 3373 unchanged.
- producer readiness: PASS for five consecutive samples.
- phone consumer: 3466 -> 24403.
- R3_FRAMEWORK_READY / A_READY: PASS.
- P_CANONICAL: PASS.
- v2.6.2 hash: `445752BB49FB487850D0B1A1EFF4F0AA29D58C363C3A86E75BAA841E4CC08F75`.
- SIM OFF/ON: 1 / 1.
- GOLDEN_STRONG: PASS; freeze-on-success retained.

### M1-M7

The device log clock and host recovery-log clock have a small offset, so absolute source timestamps are preserved instead of inventing sub-second cross-clock deltas.

| Milestone | Result | Timestamp and evidence |
|---|---|---|
| M1 ANM IMS -> IWLAN | PASS | device 20:30:16.432, `onQualifiedNetworkTypesChanged: apnTypes=[ims], networks=[IWLAN]` |
| M2 NRM IWLAN/HOME | PASS | device 20:30:16.441, WLAN `registrationState=HOME`, `accessNetworkTechnology=IWLAN` |
| M3 SST consumes NRM | PASS | device 20:30:16.458, slot1 `handlePollStateResultMessage: PS IWLAN ... HOME` |
| M4 DNC IWLAN/HOME | PASS | device 20:30:16.565, DNC `[WLAN: UNKNOWN->IWLAN, UNKNOWN->HOME]` |
| M5 qti.cne IMS request | PASS | device 20:30:31.755, TNF request id 283 from `com.qualcomm.qti.cne`, capability IMS, subId11 |
| M6 IMS REGISTERED/WLAN | PASS | device 20:30:33.731, `handleImsRegistered ... imsRadioTech=WLAN` |
| M7 WFC HEALTHY | PASS | host 20:30:38.407, direct health check; final sanitized snapshot F0/GOLDEN_STRONG |

## Cycle 2 — valid P counterexample

### Reset epochs

- A_RAW: airplane OFF, F1.
- R0 followed its pre-existing frozen-residue normalization path.
- R0 qcrild2 reacquire: 15426 -> 5785; native ownership clean, X55 ONLINE, crash zero.
- independent R4a producer qcrild2: 5785 -> 8932.
- qtidataservices: 3373 unchanged from baseline and Cycle 1.
- producer readiness: PASS for five consecutive samples.
- phone consumer: 24403 -> 19318.
- R3_FRAMEWORK_READY / A_READY: PASS.
- fixed P transition and fixed 60-second settle completed.
- P_CANONICAL: FAIL.
- v2.6.2 executions in Cycle 2: 0.
- SIM OFF/ON in Cycle 2: 0 / 0.

### P fingerprint

```text
airplaneMode=1
wlan0Up=true
vpnNetwork=true
rilTechnology=Unknown
PS/WLAN=UNKNOWN
accessNetwork=UNKNOWN
mIsIwlanPreferred=false
qti.cne IMS request=false
IMS=NOT_REGISTERED/UNKNOWN
WFC=false
```

### M1-M7

| Milestone | Result | Evidence |
|---|---|---|
| M1 ANM IMS -> IWLAN | MISSING | no fresh IMS->IWLAN callback to new phone PID 19318 after R3 and during fixed P window |
| M2 NRM IWLAN/HOME | MISSING | new consumer returned WLAN `NOT_REG_OR_SEARCHING` at 20:37:53.182, later snapshot UNKNOWN |
| M3 SST consumes HOME | MISSING | SST consumed the negative `NOT_REG_OR_SEARCHING` result at 20:37:53.183; no positive HOME consumption |
| M4 DNC IWLAN/HOME | MISSING | DNC ended WLAN UNKNOWN, not HOME |
| M5 qti.cne IMS request | NOT REACHED | stopped before v2.6.2 |
| M6 IMS REGISTERED/WLAN | NOT REACHED | stopped before v2.6.2 |
| M7 WFC HEALTHY | NOT REACHED | stopped before v2.6.2 |

## Earliest divergence and R4b eligibility

After the Cycle 2 producer restart, the **old** phone consumer PID 24403 received IMS->IWLAN callbacks at 20:35:34.484 and 20:35:36.226. This proves the new qcrild2 producer could feed the still-existing qtidataservices/QNS path before R3.

After R3 created phone PID 19318, no fresh M1 replay reached that new consumer. The earliest concrete divergence is therefore the qtidataservices/QNS provider epoch -> newly created framework consumer replay/binding boundary, not failure to create the qcrild2 producer epoch.

This valid R4a counterexample is sufficient to permit **static design** of R4b, whose candidate boundary may include rebuilding the qtidataservices/QNS provider epoch before the new framework consumer. It does not authorize executing R4b and does not prove that R4b will work.

## Cycle 3

`NOT_RUN`, as required after the first valid failure.

## Write discipline

- No adaptive or manual phone write was added.
- No qtidataservices/CND/IMS restart or workaround was executed.
- No timeout or reset order changed.
- Baseline reboot count: 1.
- R4a producer restart count: one in each executed cycle.
- R3 phone TERM count: one in each executed cycle.
- SIM cycle count: Cycle 1 one; Cycle 2 zero.
- Cycle 2 stopped with airplane ON and the P-failure scene preserved.

## Raw host evidence hashes

Raw logs remain host-only. SHA-256:

- `series.log`: `E0E950D1941A7A8B51C69CC740E3F0949F9D0DACD8387A105E8B25933AD717B6`
- `cycle_1_producer_evidence.json`: `6576E707D17EA56C6E59780B44A7EEF0DD093EE7E341F96E9F3FC8AA55BD4588`
- `cycle_1_r3.log`: `7AA66C0A6AFED4BD15B76FDB1DE18BD13A8DCE95ED6CB26E8DCDD25F6120A9DD`
- `cycle_2_producer_evidence.json`: `1CFCC9CD17F967A8F328A9120C80F3F114509DED814AB62279BB9FE3D53E928A`
- `cycle_2_r3.log`: `B313C1EB69AE37531F3C7DE9CCEEA11147976339776DB48D882F0B280F4A57D6`
