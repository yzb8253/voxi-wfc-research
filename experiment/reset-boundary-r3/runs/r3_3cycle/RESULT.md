# R3 three-cycle falsification run

Date: 2026-09-24

Branch: `experiment/v263-repeatable-state-machine`

Starting baseline: `10284e6a69e1ee6084662c8d2340d64b323295ca`

Frozen v2.6.2 SHA-256: `445752BB49FB487850D0B1A1EFF4F0AA29D58C363C3A86E75BAA841E4CC08F75`

## Classification

The run did **not** produce three valid cycles. Cycle 1 is a valid PASS. Cycle 2 stopped before the `com.android.phone` TERM because the runner required the intermediate R0 snapshot to satisfy the full framework-level A-canonical predicate. R0 had restored native ownership correctly, but the old framework still reported `IWLAN` and `mIsIwlanPreferred=true` with airplane mode off. Those are the exact long-lived framework fields that R3 was designed to rebuild.

Therefore:

- `R3_NOT_FALSIFIED_3_CYCLES=NO`
- `R3_FALSIFIED_AT_CYCLE=NOT_ESTABLISHED`
- `EXPERIMENT_RESULT=ABORTED_PRE_R3_INVALID_INTERMEDIATE_GATE_CYCLE_2`
- Cycle 3 was not run.
- No SST workaround, extra wait, extra SIM cycle, CND fallback, IMS reset, or expanded reset was applied.

This is not counted as a valid R3 failure because the fixed R3 boundary was never applied in Cycle 2. It is also not evidence that R3 is sufficient. A new separately approved run must define the intermediate post-R0 gate as native-clean only and reserve framework canonicality for `R3_READY/A_READY`; that is a test-definition correction, not a phone-side workaround.

## CONTROL_A0

One and only one authorized AP reboot established the baseline. Airplane mode was disabled, Wi-Fi/VPN/AnyWhere were restored, and `CONTROL_A0.json` was captured. Native ownership was pm-service sole owner, X55 ONLINE, crash count zero, VOXI slot 1/subId 11 active with UICC applications enabled, and WFC F1.

## Cycle 1 — valid PASS

- R0: PASS. It removed one verified dead holder PID marker left across reboot; no live holder was touched.
- `com.android.phone`: exact main UID-1001/radio-domain PID `3472` received one TERM; ActivityManager recreated it as PID `17402`.
- R3_READY: PASS. Fresh Phone[0/1], SST, ANM, NRM and DNC construction markers appeared; qcrild `1963`, qcrild2 `2010`, qtidataservices `3397`, and org.codeaurora.ims `3458` remained unchanged.
- P: PASS.
- Frozen v2.6.2: exact canonical source hash passed. A host-only adapter changed only the obsolete Computer-A ADB path in memory and proved reverse substitution reproduced the canonical text.
- SIM cycle: OFF 1, ON 1.
- Direct health: REGISTERED/WLAN, VOICE/IWLAN available, WFC available, active qti.cne IMS request, IMS NetworkAgent, UDP/4500 and XFRM.
- Recovery result: `SIM_CYCLE_1_SUCCESS`.
- WFC elapsed: 11 seconds by the frozen script's health loop.
- Freeze-on-success: honored; no post-success cleanup.
- Slot0: physically absent throughout; no slot0 write path was used.

### Cycle 1 M1–M7

| Milestone | Timestamp | Evidence |
|---|---:|---|
| M1 ANM publishes IMS→IWLAN | 18:51:54.136 | `ANM-1 onQualifiedNetworkTypesChanged: apnTypes=[ims], networks=[IWLAN]` |
| M2 NRM returns IWLAN/HOME | 18:51:54.117; repeated 18:51:54.243 | First same-lifecycle NRM completion preceded the ANM callback by 19 ms; the post-M1 poll repeated IWLAN/HOME. |
| M3 SST consumes NRM result | 18:51:54.190 | `SST [1] handlePollStateResultMessage: PS IWLAN ... HOME` |
| M4 DNC transitions IWLAN/HOME | 18:51:54.294 | `DNC-1 ... WLAN: UNKNOWN->IWLAN, UNKNOWN->HOME` |
| M5 new qti.cne IMS request | 18:52:09.702 | TNF request 262 from `com.qualcomm.qti.cne`; DNC accepted it at 18:52:09.705. |
| M6 IMS REGISTERED over WLAN | 18:52:12.017 | `ImsPhone[1] handleImsRegistered ... imsRadioTech=WLAN` |
| M7 WFC HEALTHY | 18:52:12.086 | First `isWifiCallingEnabled=true`; frozen health loop confirmed at 18:52:16.603. |

## Cycle 2 — stopped before R3

- A_RAW: captured after the required airplane-OFF transition.
- Frozen residue: holder PID `21676` sole owner, per_mgr stopped, X55 ONLINE, crash count zero.
- Fixed R0 native normalization first attempted its make-before-break path. pm-service did not form exact dual ownership, so the already-fixed qcrild2 fallback ran.
- Fallback: exact holder TERM once; qcrild2 `2010 -> 29967`; pm-service `27719` became sole `/dev/subsys_esoc0` owner; per_mgr running; X55 ONLINE; crash count zero; holder absent.
- After the fixed 60-second settle, native state was clean and target mapping/UICC/VPN were intact.
- The intermediate snapshot still had `rilTechnology=IWLAN` and `preferred=true` while airplane mode was OFF. The full `A-Canonical` function consequently threw `R0_NOT_CANONICAL`.
- `com.android.phone` TERM count: 0.
- P creation count: 0.
- SIM OFF/ON: 0/0.
- Frozen v2.6.2 executions: 0.
- First missing experimental stage: `R3_READY` (R3 was not entered). M1–M7 are not applicable.

## Preserved phone state at stop

Airplane mode OFF; per_mgr running; pm-service PID 27719 sole native owner; qcrild 1963; qcrild2 29967; X55 ONLINE; crash count zero; holder and holder PID file absent; VOXI active/UICC enabled; F1. No cleanup or further recovery was run after the stop.

## Artifacts

- `snapshots/CONTROL_A0.json`
- `snapshots/R3_C1_A_RAW.json`
- `snapshots/R3_C1_R0_NORMALIZED.json`
- `snapshots/R3_C1_A_READY.json`
- `snapshots/R3_C1_P_CONTINUE.json`
- `snapshots/R3_C1_W_HEALTHY.json`
- `snapshots/R3_C2_A_RAW.json`
- `snapshots/R3_C2_R0_NORMALIZED.json`
- `logs/cycle_1_r3.log`
- `logs/cycle_2_r3.log`
- `logs/cycle_1_phone_rebuild_log.txt`
- `logs/X55-WFC-20260924_185105.log`
