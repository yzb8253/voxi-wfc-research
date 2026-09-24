# R4 reset-boundary candidates

Date: 2026-09-24

Status: design only. No R4 operation was executed. Phone writes: **0**.

## Experimental invariant

Every candidate is a complete, frozen reset boundary followed by the same fixed P, hash-locked unchanged v2.6.2, one allowed SIM cycle inside that recovery, the same M1-M7 telemetry, and the same health predicate. A candidate is run for up to three cycles after one series-start reboot. Any valid failure is `R4x_FALSIFIED_AT_CYCLE=N`; no in-run reset enlargement, retry, extra wait, ANM/NRM/SST workaround, extra SIM cycle or fallback is allowed.

R0 remains the fixed native X55/PM ownership normalization. R3 remains one exact audited main `com.android.phone` TERM followed by its existing 120-second fail-closed framework readiness gate. R3 alone remains falsified.

## R4a — native IIWlan producer epoch + framework consumer epoch

### Reset set and order

1. Complete fixed R0 and pass `R0_NATIVE_READY`.
2. Restart exactly `vendor.qcrild2` once through its verified init service; no primary qcrild, qtidataservices, cnd or IMS restart.
3. Wait for `R4A_PROVIDER_READY`.
4. Execute exact R3 once.
5. Wait for existing `R3_FRAMEWORK_READY / A_READY`.
6. Enter fixed P without an additional repair or adaptive delay.

The order is provider first, consumer last. Reversing it is a different hypothesis and is not permitted within the series.

### Provider readiness gate

Maximum 120 seconds; then ten consecutive one-second stable samples:

- new qcrild2 PID differs from old, exact `/vendor/bin/hw/qcrild -c 2`, PPID 1, UID radio and expected SELinux domain;
- primary qcrild PID/identity unchanged and stable;
- `IRadio/slot2` and `IIWlan/slot2` registered;
- qtidataservices has reconnected its existing production callbacks; no second client and no external `setResponseFunctions` call;
- new DataModule cold initialization and new NAH construction observed;
- DSD and WDS endpoints ready, IWLAN enabled, modem capability enabled;
- target mapping/UICC valid; X55 ONLINE, crash_count 0, pm-service sole owner, no holder;
- no qcrild2 crash loop, QtiBus `serverDied`, unknown process change or slot remap.

Failure is `R4A_PROVIDER_READY_TIMEOUT` or `R4A_SCOPE_VIOLATION`, with no R3 or fallback.

### Coverage and prediction

- **Covers:** R0; qcrild2 DataModule/DSD/WDS/NAH/IIWlan producer epoch; subsequent new framework Phone/ANM/NRM/SST/DNC epoch.
- **Does not process-reset:** qtidataservices static state, primary qcrild, cnd, Qualcomm IMS or system_server.
- **Why causal:** qcrild2 is the earliest surviving producer that supplies both QNS qualification and IWLAN registration state. R3 already proved the consumers can be recreated.
- **Falsifiable prediction:** if mismatch resides in the old qcrild2 native producer versus new framework generation, fixed P naturally reaches M1 IMS->IWLAN and M2 IWLAN/HOME. A valid repeat of the M1/M2 failure falsifies R4a.
- **Prior evidence constraint:** isolated qcrild2 restart previously failed in an already-poisoned P scene. R4a is not a repeat of that test: it freezes provider-first restart followed by consumer recreation before P. That difference is the hypothesis and must not be changed mid-series.
- **slot0 impact:** target process is slot2/RIL instance 1, but QMI DSD and shared QtiBus/modem effects cannot be proven slot1-only; transient both-slot radio impact is possible.
- **X55 impact:** no intentional X55 reset beyond R0; any X55 state/crash-count change after provider stage invalidates the trial.
- **Automation:** high using verified init identity, HIDL inventory and existing R3 gates.
- **Risk:** medium-high; target RIL restart causes slot1 radio/UICC rediscovery and may interact with shared QtiBus.

## R4b — complete Java/native IWLAN provider chain + framework consumer epoch

### Reset set and order

1. Fixed R0 -> `R0_NATIVE_READY`.
2. Restart exactly `vendor.qcrild2` once and pass the same native provider gate as R4a.
3. Restart exactly the verified persistent `.qtidataservices` PID once with TERM; wait for ActivityManager recreation.
4. Pass `R4B_JAVA_PROVIDER_READY`.
5. Execute exact R3 once and pass `R3_FRAMEWORK_READY / A_READY`.
6. Enter fixed P.

### Java-provider readiness gate

Maximum 120 seconds; then ten stable one-second samples:

- new `.qtidataservices` PID, UID 10104 and expected SELinux domain;
- CneApp, QualifiedNetworksServiceImpl, IWlanNetworkService, IWlanDataService and CACertService are hosted in that PID;
- new process connects to the already-new `IIWlan/slot2` and installs the production response/indication callbacks;
- handshake/NAH readiness, DSD/WDS readiness and IWLAN enablement remain present;
- native cnd is connected to new CneApp; no callback replacement by an external client;
- qcrild/qcrild2 stable; X55/PM ownership clean; target mapping/UICC valid;
- no provider crash loop, unknown process death or slot remap.

Failure is fail-closed; R3 does not run.

### Coverage and prediction

- **Covers:** R4a plus the entire shared Java QNS/IWLAN/CNE provider process/static epoch, followed by new framework consumers.
- **Why causal:** it recreates all three generations in dependency order: native producer -> Java bridge/provider -> framework consumer.
- **Falsifiable prediction:** if R4a fails because the old qtidataservices HIDL proxy/provider/static state survives, R4b should restore natural M1/M2. If R4b still fails at M1/M2, the combined IIWlan/QNS provider-generation hypothesis is falsified at this scope.
- **slot0 impact:** definite shared-service interruption; qtidataservices hosts both-slot QNS/IWLAN/CNE services.
- **X55 impact:** no intentional new X55 reset; any change invalidates the stage.
- **Automation:** medium-high; exact process and hosted-service gates exist, but callback registration IDs remain unobservable.
- **Risk:** high; interrupts QNS, IWLAN DataService/NetworkService and CNE for both slots, and restarts unrelated CA-cert service.
- **Negative prior evidence:** qtidataservices alone and coordinated cnd->qtidataservices failed in older F1 scenes. Those results lower expected success but did not use a new qcrild2 producer followed by new phone consumers, so they do not pre-falsify this exact fixed boundary.

## R4c — boot-like telephony userspace producer stack + framework consumer epoch

### Reset set and order

1. Fixed R0 -> `R0_NATIVE_READY`.
2. Recreate the primary RIL first and wait for exact primary `vendor.qcrild` readiness/QtiBus server stability.
3. Recreate target `vendor.qcrild2` and pass native IIWlan/DSD/WDS/NAH readiness.
4. Recreate native `vendor.cnd`; wait for its service and private native endpoint readiness.
5. Recreate `.qtidataservices`; wait for QNS/IWLAN/CNE bridge readiness.
6. Recreate `org.codeaurora.ims`; wait for stable vendor ImsService availability, but do not call resetIms.
7. Execute exact R3 last and pass `R3_FRAMEWORK_READY / A_READY`.
8. Enter fixed P.

This is the widest proposed R4 and the closest userspace approximation to boot. It still excludes system_server restart, AP reboot, modem SSR, radio power toggle, SIM operation outside v2.6.2, and any NV/EFS/PDC change.

### Readiness and timeout

- 120 seconds per process stage, 600 seconds overall.
- each new process must have a different PID, exact argv/UID/SELinux/parent, stable for ten seconds;
- primary QtiBus must be stable before target qcrild2 starts its accepted epoch;
- target must publish IRadio/slot2 and IIWlan/slot2 with DSD/WDS ready;
- cnd/CneApp connection, all qtidataservices hosted services, and Qualcomm ImsService availability must be present;
- final R3 gate retains fresh Phone/ANM/NRM/SST/DNC, current CarrierConfig/MMTEL, mapping/UICC, native ownership/X55/crash zero and stable environment;
- any unexpected process, X55, holder, mapping or crash-count change fails closed with no continuation.

### Coverage and prediction

- **Covers:** R0 plus both RIL/QtiBus epochs, native DSD/IIWlan, native CNE, Java QNS/IWLAN/CNE, vendor IMS, then framework consumers.
- **Why causal:** these are the telephony producer processes reboot recreates before/alongside the phone consumer graph. It tests whether a boot-equivalent *userspace* producer order is sufficient.
- **Falsifiable prediction:** if R4c validly fails to make P canonical, the missing boot boundary is not contained in this telephony userspace set; system_server/AP boot or a deeper modem epoch becomes the remaining class.
- **slot0 impact:** high and unavoidable; both RILs, CNE, IWLAN and vendor IMS serve both slots.
- **X55 impact:** R0 supplies the fixed X55 epoch; later stages must not change X55/crash count. A change invalidates, rather than repairs, the trial.
- **Automation:** medium; many exact readiness gates are possible, but the larger stage count increases invalid-run probability.
- **Risk:** very high; temporary loss of both-slot radio, IMS and data-service continuity. Still less broad than system_server/AP reboot.

## Comparison

| Candidate | Native producer reset | Java provider reset | Framework consumer reset | Both-slot scope | Information gained on failure |
|---|---:|---:|---:|---:|---|
| R4a | qcrild2/IIWlan/DSD/NAH | no process reset | yes | possible/shared QMI | tests earliest native-producer epoch |
| R4b | same as R4a | full qtidataservices QNS/IWLAN/CNE | yes | yes | tests complete IIWlan producer/bridge/consumer chain |
| R4c | both RILs + DSD + cnd | qtidataservices + vendor IMS | yes | yes, broad | tests boot-like telephony userspace as a class |

## Recommended first candidate

**R4a** is the minimum causal candidate.

It is not an ANM/NRM workaround: it does not inject a preferred transport, force a registration result, replay a callback, modify a cache, or alter the fixed P/recovery. It destroys the earliest preserved producer object graph that supplies the missing M1/M2 inputs, waits for that producer to become independently ready, and only then destroys/recreates its framework consumers. The expected outcome is natural publication through the original unmodified interfaces.

R4a also has a sharp falsification result. If a fully valid R4a cycle again reaches `UNKNOWN_P_FINGERPRINT` with M1/M2 absent, stop and record `R4A_FALSIFIED_AT_CYCLE=1`; do not add qtidataservices or continue remaining cycles. R4b would then require a new series, new approval and a new reboot baseline.

## Required future result labels

- Three valid consecutive passes: `R4A_NOT_FALSIFIED_3_CYCLES`, never `PROVEN`.
- First valid failure: `R4A_FALSIFIED_AT_CYCLE=N`, plus `FIRST_MISSING_MILESTONE=Mx`.
- Provider readiness failure: `R4A_EXECUTION_INVALID`, not a WFC falsification.
- No adaptive action after any terminal label.
