# R3 three-cycle v2 result

Date: 2026-09-24

Gate-fix commit tested: `fa58b336b6763b1ed056a44de8d5524bb1c893d7`

Frozen v2.6.2 SHA-256: `445752BB49FB487850D0B1A1EFF4F0AA29D58C363C3A86E75BAA841E4CC08F75`

## Final classification

- `R3_FALSIFIED_AT_CYCLE=1`
- `FIRST_MISSING_MILESTONE=M1`
- `CYCLE_2=NOT_RUN`
- `CYCLE_3=NOT_RUN`
- `R3_NOT_FALSIFIED_3_CYCLES=NO`

This is a valid counterexample to the fixed R3 pipeline. R0 native readiness passed, the exact audited R3 ran once, R3 framework readiness/A_READY passed, and then the fixed P transition failed to reach its frozen canonical fingerprint. The failure is therefore downstream of R3 execution, not a pre-R3 orchestrator abort.

No recovery code or timeout was changed. No workaround, qtidataservices/CND restart, IMS reset, second P attempt, SIM cycle or additional cycle followed.

## Independent baseline

The new series used one and only one full AP reboot. After boot, airplane mode was disabled, Wi-Fi/VPN/location/AnyWhere readiness passed, and `CONTROL_A0_V2` was captured as F1 with native pm-service ownership clean and X55 ONLINE/crash_count zero.

The old series remains separately classified as Cycle 1 valid PASS / Cycle 2 aborted before R3. No old cycle is counted here.

## Cycle 1

### R0_NATIVE_READY

PASS with no write:

- fixed VOXI slot 1 / phoneId 1 / subId 11 mapping active;
- UICC applications enabled;
- qcrild PID 1906 and qcrild2 PID 1927 valid;
- per_mgr running;
- pm-service PID 1292 sole `/dev/subsys_esoc0` owner;
- holder and holder PID file absent;
- X55 ONLINE;
- crash_count zero;
- no module lock.

No LTE/IWLAN, SST, DNC, preferred-transport or qti.cne field participated in this gate.

### R3_FRAMEWORK_READY / A_READY

PASS:

- exact audited main `com.android.phone` PID 3425 received one TERM;
- ActivityManager recreated main phone as PID 17756;
- fresh Phone[0], Phone[1], SST[1], ANM-1, NRM-I-1 and DNC-1 markers observed;
- CarrierConfig LOADED and MMTEL subId 11 readiness observed;
- qcrild 1906, qcrild2 1927, qtidataservices 3319 and org.codeaurora.ims 3332 remained unchanged;
- five consecutive one-second process/scope samples were stable;
- airplane OFF, Wi-Fi/VPN/location/AnyWhere ready;
- LTE, `mIsIwlanPreferred=false`, no current qti.cne IMS request;
- native ownership clean, X55 ONLINE, crash_count zero.

### Fixed P transition

The frozen P creation performed exactly one airplane-mode enable, one Wi-Fi enable and the unchanged 60-second settle. `V1_P_RAW` then failed `P-Canonical`:

- airplane mode: 1;
- Wi-Fi: UP;
- VPN: present;
- target mapping/UICC: valid;
- native ownership: clean;
- `rilTechnology=Unknown` (required IWLAN);
- `PS/WLAN=UNKNOWN` (required HOME);
- `accessNetwork=UNKNOWN` (required IWLAN);
- `mIsIwlanPreferred=false` (required true);
- qti.cne IMS request absent.

Key transition evidence:

- 19:22:20.900 — NRM-I-1 returned IWLAN `NOT_REG_OR_SEARCHING`, not HOME.
- 19:22:20.903 — SST[1] consumed that non-home IWLAN result.
- 19:22:20.950 — DNC[1] remained WLAN IWLAN / `NOT_REG_OR_SEARCHING` and had no request reevaluation.
- 19:22:21.350 — DNC[1] moved WLAN IWLAN→UNKNOWN and `NOT_REG_OR_SEARCHING`→UNKNOWN.
- No `ANM-1 onQualifiedNetworkTypesChanged: [ims] -> [IWLAN]` appeared in the P window.
- At 19:23:25, after the full fixed settle, P remained noncanonical.

The state machine stopped at `UNKNOWN_P_FINGERPRINT V1` before invoking the portable/frozen v2.6.2 launcher.

## M1–M7

No SIM ON occurred, so relative-to-SIM-ON time is not applicable. The first required milestone was absent.

| Milestone | Result | Timestamp / relative time | Evidence |
|---|---|---|---|
| M1 ANM IMS→IWLAN | MISSING | none / N/A | No matching ANM callback in the fixed P window. |
| M2 NRM IWLAN/HOME | MISSING | none / N/A | NRM returned IWLAN `NOT_REG_OR_SEARCHING` at 19:22:20.900, not HOME. |
| M3 SST consumes successful NRM result | MISSING | none / N/A | SST consumed the non-home result at 19:22:20.903; no HOME result existed. |
| M4 DNC IWLAN/HOME | MISSING | none / N/A | DNC became UNKNOWN rather than HOME. |
| M5 new qti.cne IMS request | MISSING | none / N/A | Snapshot and logs show no current request. |
| M6 IMS REGISTERED/WLAN | MISSING | none / N/A | IMS remained NOT_REGISTERED/UNKNOWN. |
| M7 WFC HEALTHY | MISSING | none / N/A | WFC remained unavailable/F1. |

SIM OFF count: 0

SIM ON count: 0

Frozen v2.6.2 execution count: 0

## Stop state

Airplane ON; Wi-Fi/VPN present; per_mgr running; pm-service 1292 sole native owner; X55 ONLINE; crash_count zero; no holder; qcrild/qcrild2 unchanged; VOXI active/UICC enabled; IMS NOT_REGISTERED; transport UNKNOWN; WFC unavailable. No post-failure phone action was performed.

## Evidence

Sanitized committed evidence:

- `snapshots/CONTROL_A0_V2.json`
- `snapshots/R3V2_C1_A_RAW.json`
- `snapshots/R3V2_C1_A_READY.json`
- `snapshots/V1_A_RAW.json`
- `snapshots/V1_P_RAW.json`
- `logs/cycle_1_r3.log`
- `logs/V1_timeline.log`

The full phone-rebuild log remains host-only under `voxi_wfc_local_runs` because repository policy forbids raw telephony dumps. Its SHA-256 is `46B77E0A7169C53F2C663F02CC6182D1C4C23AA69E092E702C0AD036ACAEE485`.

## Interpretation

R3 reliably recreated the framework object graph once, but did not make the subsequent airplane-mode P transition deterministic. The counterexample occurs before recovery/SIM insertion and at the QNS/ANM qualification boundary: NRM/SST observed only non-home IWLAN and ANM never published the IMS→IWLAN qualified network.

Per protocol, this result does not authorize an SST/QNS workaround or a larger reset in the preserved scene. A future experiment requires a separately designed candidate boundary and fresh approval.
