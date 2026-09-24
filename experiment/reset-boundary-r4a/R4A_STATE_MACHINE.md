# R4a fixed state machine

## Frozen order

```text
one series-start reboot
  -> CONTROL_A0_R4A

Cycle N:
A_RAW
  -> fixed R0 normalization
  -> R0_NATIVE_READY
  -> exactly one vendor.qcrild2 init restart
  -> PRODUCER_READY
  -> exactly one audited main com.android.phone TERM
  -> R3_FRAMEWORK_READY / A_READY
  -> A_R4A_READY
  -> airplane ON once + Wi-Fi enable + fixed 60-second settle
  -> P_CANONICAL
  -> unchanged hash-locked v2.6.2
  -> at most one SIM OFF / 3 seconds / ON
  -> M1..M7 / GOLDEN_STRONG
  -> FREEZE
```

Between successful cycles only, the series runner disables airplane mode once and begins the next identical cycle. There is no success cleanup or provider reset.

## PRODUCER_READY

Timeout: 120 seconds, fail closed.

Required:

- old qcrild2 PID gone;
- new exact qcrild2 PID and identity;
- primary qcrild, qtidataservices and phone PIDs unchanged;
- IIWlan/slot2 present and debug-callable;
- post-reset cold DataModule initialization marker;
- post-reset NAH construction marker;
- DSD and WDS ready;
- modem capability true and IWLAN enabled in terrestrial A;
- QNS, IWlanNetworkService and IWlanDataService hosted without hard error;
- X55 ONLINE, crash count zero, pm-service sole owner, no holder/lock;
- five consecutive successful two-second samples.

Missing fields produce `R4A_PRODUCER_READY_TIMEOUT`; R3 is not executed.

## Framework and P gates

R3 uses the existing audited exact UID-1001/radio-domain main-phone TERM and 120-second fresh-object readiness gate. Default R3 behavior is unchanged; a host-only stop-after-R0 orchestration hook allows the producer step to be inserted in the required order.

P remains the prior frozen 60-second predicate:

- airplane ON, Wi-Fi/VPN present;
- target mapping/UICC correct;
- native ownership clean;
- `rilTechnology=IWLAN`;
- PS/WLAN HOME;
- access network IWLAN;
- `mIsIwlanPreferred=true`;
- no pre-recovery qti.cne IMS request.

Failure at P stops before v2.6.2 and is `R4A_FALSIFIED_AT_P`, first missing M1 when ANM IMS->IWLAN is absent.

## Recovery invariants

- canonical v2.6.2 SHA-256: `445752BB49FB487850D0B1A1EFF4F0AA29D58C363C3A86E75BAA841E4CC08F75`;
- no source or wait change;
- no second SIM cycle, qtidataservices/CND restart, IMS reset or adaptive fallback;
- any child failure stops the whole series immediately;
- 3/3 permits only `R4A_NOT_FALSIFIED_3_CYCLES`, never `R4A_PROVEN`.

