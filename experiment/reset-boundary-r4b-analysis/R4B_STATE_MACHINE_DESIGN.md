# R4b producer/provider/consumer state-machine design

Date: 2026-09-24

Status: static design only. Execution is not authorized. Phone writes: **0**.

## Hypothesis

`H3`: an old `.qtidataservices` process/static provider epoch can continue delivering live qualification to an old framework consumer, but cannot reliably provide the required current-state publication to a new framework consumer. A new native producer, then a new Java provider, then a new framework consumer should recreate the boot-like dependency pairing.

H3 is supported by the R4a Cycle 2 counterexample and remains falsifiable. It is not a claim that qtidataservices restart will recover WFC.

## Frozen order

```text
series-start reboot (once)
  -> CONTROL_A0_R4B

Cycle N:
  A_RAW
  -> fixed R0 normalization
  -> R0_NATIVE_READY
  -> exactly one qcrild2 cold epoch
  -> PRODUCER_READY
  -> exactly one .qtidataservices cold epoch
  -> PROVIDER_READY
  -> exactly one exact R3 com.android.phone consumer reset
  -> R3_FRAMEWORK_READY / A_READY
  -> fixed P
  -> P_CANONICAL or R4B_FALSIFIED_AT_P
  -> unchanged hash-locked v2.6.2 only if P passed
  -> M1-M7 / GOLDEN_STRONG
  -> FREEZE or next cycle
```

The qcrild2, qtidataservices and phone restart counts are each exactly one per valid cycle. Their order is part of the hypothesis and cannot be changed mid-series.

## Why the order is causal

1. **Producer first:** qcrild2 constructs DataModule, DSD/WDS clients, NetworkAvailabilityHandler and `IIWlan/slot2`. It must own the authoritative current cache before any new Java callback attaches.
2. **Provider second:** the fresh qtidataservices proxy connects to that already-new IIWlan service, installs the production callbacks, and its new slot1 QNS provider queries the new producer's current cache.
3. **Consumer third:** the new phone/ANM/NRM/SST/DNC graph binds only after the provider is proven structurally ready. This removes the old-provider/new-consumer pairing seen in R4a.

Reverse orders create the exact ambiguities under test:

- phone before provider can bind to an old provider, consume old/empty state, then depend on death/rebind replay;
- provider before producer can query the old cache, register callbacks that die during qcrild2 restart, and rely on reconnect timing;
- producer after consumer can emit its first current-state indication before the final consumer/provider generation is attached;
- provider and phone concurrently make the initial GET response versus framework callback registration ordering non-deterministic.

## PROVIDER_READY gate

Deadline: 120 seconds after the one exact PID TERM. Poll state; do not replace this with a fixed sleep. After all fields first pass, require ten consecutive one-second stable samples.

### Required structural fields

- old `.qtidataservices` PID is gone;
- exactly one new PID exists and differs from old;
- new process identity is `.qtidataservices`, UID 10104, expected SELinux domain, zygote parent and ActivityManager `PERS` record;
- process package list is exactly the expected qtidataservices shared group;
- CneApp, CACertService, QualifiedNetworksServiceImpl, IWlanNetworkService and IWlanDataService are hosted by the new PID;
- slot1 `NetworkAvailabilityProviderImpl`, NetworkServiceProvider and DataServiceProvider creation/binding evidence is present;
- a new process-static slot1 `IWlanProxy` is observed;
- the proxy connects to production `IIWlan/slot2`, links its death recipient and installs its own production response/indication callbacks;
- a provider-originated `getAllQualifiedNetworks` completes and the result reaches `updateQualifiedNetworks`; result content is recorded but not forced to IMS -> IWLAN before P;
- the provider is capable of serving a current slot1 network-registration query without fatal/Binder exception;
- no proxy death loop, repeated provider crash, request timeout storm, unknown IIWlan client or callback replacement is present.

### Required preserved-scope fields

- qcrild2 PID remains the exact PRODUCER_READY PID; primary qcrild PID remains unchanged;
- `IRadio/slot2` and `IIWlan/slot2` remain registered;
- qcrild2 DSD/WDS/NAH/IWLAN readiness remains true;
- native `vendor.cnd` and `org.codeaurora.ims` PIDs remain unchanged;
- phone PID remains unchanged during the provider stage;
- X55 ONLINE, crash_count 0, pm-service sole `/dev/subsys_esoc0` owner, no holder or holder pid file;
- VOXI slot1 mapping/UICC remain valid; slot0/default/active-data mapping remains unchanged;
- no unexpected SIM, radio, airplane, VPN, location or process-control action occurred.

### Explicitly unobservable fields

The following are recorded as `UNOBSERVABLE`, never converted to PASS:

- Java/native callback object generation IDs;
- native indication subscription generation number;
- complete Binder callback table inside framework/vendor base classes;
- guarantee that no indication occurred between GET and registrant installation;
- modem-side object addresses.

### Terminal gate labels

- Deadline without full structural readiness: `R4B_PROVIDER_READY_TIMEOUT`.
- Identity, PID-count, process-change, mapping, X55/PM or callback-scope violation: `R4B_PROVIDER_SCOPE_VIOLATION`.
- Either label is fail-closed: no R3, no P, no v2.6.2 and no fallback.

## A_READY and P

After PROVIDER_READY, execute the unchanged exact R3 main-phone TERM once. Existing R3 identity, creation and 120-second framework readiness gates remain unchanged. They must establish new Phone/ANM/NRM/SST/DNC, current CarrierConfig/MMTEL, valid mapping/UICC, terrestrial A canonicality, stable environment and preserved producer/provider/native scope.

Fixed P is then the first causal falsification point. Its required observations remain:

- M1: ANM publishes IMS -> IWLAN;
- M2: NRM reports IWLAN/HOME;
- M3: SST consumes the NRM WLAN result;
- supporting canonical fields: PS/WLAN HOME, access network IWLAN, `mIsIwlanPreferred=true`.

If P fails, emit:

```text
R4B_FALSIFIED_AT_P
FIRST_MISSING_MILESTONE=Mx
```

Stop the entire series immediately. Do not run v2.6.2.

## Recovery phase and result labels

Only a canonical P may enter the unchanged, hash-locked v2.6.2 recovery. It retains one SIM OFF and one SIM ON maximum and the existing health predicate. Record:

- M1 ANM IMS -> IWLAN;
- M2 NRM IWLAN/HOME;
- M3 SST consumes WLAN result;
- M4 DNC IWLAN/HOME;
- M5 new qti.cne IMS request;
- M6 IMS REGISTERED/WLAN;
- M7 WFC HEALTHY.

Any valid failure stops all remaining cycles. No CND/IMS restart, second provider/producer restart, second SIM cycle, timeout extension, SST/ANM injection, fallback or reset reorder is permitted.

Three consecutive valid passes may be labelled only `R4B_NOT_FALSIFIED_3_CYCLES`, never proven. The first valid failed cycle is `R4B_FALSIFIED_AT_CYCLE=N` with the first missing milestone.

## Falsifiable prediction

If H3 is correct at this scope, each valid R4b cycle will naturally restore M1 and M2 during fixed P because the new provider queries the new producer and the new consumer binds after that provider epoch is ready. If a valid cycle still lacks M1 at P, the complete qcrild2-producer + qtidataservices-provider + phone-consumer lifecycle hypothesis is falsified at this boundary. R4c would require a separate analysis, approval, reboot baseline and series; it is not an in-run fallback.

## Smaller reset decision

No smaller verified operation creates an equally complete provider epoch. A QNS Service-only rebind leaves the static IWlanProxy, callbacks, registrants, request state, CNE trackers and sibling provider services alive; R3 already demonstrated that this partial reset can fail. R4b therefore uses the whole shared process, despite its broader both-slot interruption.

## Static design verdict

`R4B_DESIGN_AUDIT = PASS`

The design is causal, ordered, bounded and falsifiable. It does not patch SST/ANM, inject qualified networks, replay setDataProfile, replace callbacks with an external client, or adapt after failure. Execution remains unauthorized.
