# VOXI WFC deterministic reset-boundary analysis

Date: 2026-09-24 (Asia/Shanghai)

Repository baseline: `b3547a32c2a74b2eb60d943e5f006efe9cb72d9c`

Mode: host-only static analysis. ADB was not invoked. Phone writes: **0**.

## Question and falsifiability rule

The working hypothesis is no longer “SST is broken, therefore patch SST.” The testable hypothesis is:

> A successful WFC cycle can leave process-local telephony lifecycle residue. A deterministic reset boundary `R`, followed by an unchanged preparation `P` and the byte-identical v2.6.2 recovery, should restore an initial-equivalent lifecycle and produce WFC repeatedly.

The experiment contract is therefore `fixed R -> fixed P -> unchanged v2.6.2`, for at least three consecutive cycles. One failed cycle falsifies that `R`. A failure must not be followed by an in-run workaround, SST nudge, extra service restart, or other patch.

## Evidence already established

The frozen two-cycle run proved that native ownership residue can be detected and normalized: X55/holder/per_mgr ownership was returned from A1 to an A0-equivalent state, P1 matched P0 on the functional fields, and the unchanged v2.6.2 recovered W1.

The later V1 run is the important counterexample. A normalization and P canonical gates passed, and the same v2.6.2 produced both ANM `ims -> [IWLAN]` and NRM IWLAN/HOME after SIM ON. W1 then delivered the NRM result into slot-1 SST, broadcast the new service state, updated DNC, and created qti.cne IMS request 293. V1 stopped before SST consumed the returned NRM result. This makes the NRM-to-SST delivery/liveness boundary the first confirmed consequential fork, not a justification for an SST-specific patch.

Prior broad rebuild failures remain relevant negative evidence but are not identical repeatability experiments: a full userspace sequence including `com.android.phone`, and later a `system_server` restart, failed in an older strict-F1 scene. They show that process restart is not an established repair. They do not replace a fixed-R/fixed-P/unchanged-v2.6.2 multi-cycle test against the newly identified cross-cycle residue hypothesis.

## Lifecycle ownership map

The arrow `ANM -> NRM -> SST -> DNC -> qti.cne -> IMS` is an observation-oriented shorthand, not a literal single call chain. ANM and NRM publish different inputs; SST consumes registration results and publishes service state; DNC consumes service/transport state and network requests; CNE independently originates the Android IMS-capability NetworkRequest after its native callback.

| Layer | Process | Service / binding | Object lifetime and owner | Creation | Destruction | What really rebuilds it |
|---|---|---|---|---|---|---|
| ANM | `com.android.phone` | Client of `vendor.qti.iwlan/.QualifiedNetworksServiceImpl` in `.qtidataservices` | One `AccessNetworksManager` per `GsmCdmaPhone` | `GsmCdmaPhone` constructor through `TelephonyComponentFactory` | Phone-object/process lifetime; vendor service death only causes rebind | Recreate the owning Phone object or restart `com.android.phone`; restarting QNS only rebinds the existing ANM |
| NRM | `com.android.phone` | Client of WWAN/WLAN `NetworkService`; WLAN provider is vendor IWLAN in `.qtidataservices` | `NetworkRegistrationManager` instances owned by slot SST, one per transport | SST initialization for the Phone/transport; binds the configured NetworkService | SST/Phone/process lifetime; provider death clears/rebinds the remote service, not the NRM object | Recreate SST/Phone or restart `com.android.phone`; provider restart only rebinds |
| SST | `com.android.phone` | Internal telephony handler, QTI subclass on this ROM (`QtiServiceStateTracker`) | One per `GsmCdmaPhone`; owns registration polling/callback generation and consolidated `ServiceState` | `TelephonyComponentFactory.makeServiceStateTracker()` during `GsmCdmaPhone` construction | Phone/process lifetime. AOSP explicitly says `GsmCdmaPhone.dispose()` is currently never called | A genuine Phone-object reconstruction or `com.android.phone` process restart; no supported shell/Binder “re-arm SST listener” boundary was found |
| DNC | `com.android.phone` | Internal data stack; owns WLAN/WWAN `DataServiceManager` clients and TelephonyNetworkRequest evaluation | One `DataNetworkController` per Phone/SIM | `GsmCdmaPhone` constructor when the new data stack is enabled | Phone/process lifetime | Recreate Phone or restart `com.android.phone`; DataService/provider rebind does not recreate DNC state |
| qti.cne | `.qtidataservices` | `com.qualcomm.qti.cne.CneApp`, native `cnd` HIDL callback endpoint | Process-global CNE app plus trackers; shared with vendor IWLAN/QNS components and both slots | Android app/process startup; `DataCallAgent` trackers created by CNE | `.qtidataservices` process death | Restart `.qtidataservices` recreates CNE, QNS and IWLAN together; it is not slot scoped |
| IMS framework client | `com.android.phone` | `ImsResolver`/feature controllers bind protected vendor ImsService | Framework-side resolver/controllers, shared process with Phone objects | Telephony process startup | `com.android.phone` death | Restart `com.android.phone` |
| Qualcomm IMS service | `org.codeaurora.ims` | `.ImsService`; per-slot `ImsServiceSub`/MMTEL feature objects | One persistent vendor process serving both slots | Vendor process startup and framework binding | Vendor IMS process death | Restart vendor IMS process, or rebind after framework death; earlier isolated restart/resetIms was insufficient |

Primary source anchors:

- AOSP constructs ANM, SST and DNC in the `GsmCdmaPhone` constructor: https://android.googlesource.com/platform/frameworks/opt/telephony/+/3266b0d6084489e78702dbd517ed091414f02c59/src/java/com/android/internal/telephony/GsmCdmaPhone.java#288
- ANM binds QualifiedNetworksService from its constructor and reports preferred-transport changes to DNC: https://android.googlesource.com/platform/frameworks/opt/telephony/+/cdda0a04effd123f29deba83e515458ab6af32b0/src/java/com/android/internal/telephony/data/AccessNetworksManager.java#450
- NRM is the binding layer between NetworkService and SST: https://android.googlesource.com/platform/prebuilts/fullsdk/sources/android-30/+/refs/heads/androidx-appcompat-release/com/android/internal/telephony/NetworkRegistrationManager.java#50
- DNC is explicitly per-SIM and runs on the phone process main thread: https://android.googlesource.com/platform/frameworks/opt/telephony/+/3266b0d6084489e78702dbd517ed091414f02c59/src/java/com/android/internal/telephony/data/DataNetworkController.java#101
- AOSP states that `GsmCdmaPhone.dispose()` is currently never called: https://android.googlesource.com/platform/frameworks/opt/telephony/+/3266b0d6084489e78702dbd517ed091414f02c59/src/java/com/android/internal/telephony/GsmCdmaPhone.java#883

## R0: currently covered native normalization

R0 is the already defined combination of controlled X55 rebirth, PM ownership normalization, and one qcrild2 restart.

| State | R0 coverage |
|---|---|
| X55 | **Covered.** New external-modem power epoch / PON success can be established without AP reboot. |
| PM | **Covered.** Holder/per_mgr ownership and native pm-service reacquisition can be normalized and gated. |
| qcrild2 | **Covered.** Target RIL process and its native QCRIL DataModule/IIWlan side are reconstructed once. |
| qcrild primary | **Not recreated by the defined R0.** It is only gated, not reset. |
| Telephony Phone[1] | **Not covered.** Existing object survives. |
| QNS Java provider | **Not deterministically recreated.** It may observe native reconnection, but `.qtidataservices` is not destroyed. |
| ANM / NRM / SST / DNC | **Not covered.** All remain the same `com.android.phone` objects and registrations. |
| Framework ImsResolver | **Not covered.** Same process-local resolver/controllers survive. |
| Qualcomm IMS service | **Not covered.** Existing `org.codeaurora.ims` process survives unless independently restarted. |

R0 therefore normalizes the modem/ownership/RIL side but cannot erase the exact framework object residue implicated by the W1/V1 fork.

## Uncovered state after R0

- **QNS:** vendor provider, its provider ID/callback registrations, and per-slot Java-side provider state remain alive unless `.qtidataservices` dies. Native IIWlan reconstruction alone is not provider-object reconstruction.
- **ANM:** the same Phone[1]-owned client, qualified-network maps, callback and service connection survive.
- **NRM:** the same per-transport manager, callback table, request generation and NetworkService connection survive; a provider reconnect is not object recreation.
- **SST:** the same slot1 Handler, poll generation, pending messages, registration-result callback relationship and consolidated ServiceState survive.
- **DNC:** the same per-SIM controller, cached ServiceState, transport state, registrations and request evaluation survive.
- **IMS:** framework ImsResolver/controllers and Qualcomm vendor service are not reset by R0.

## Candidate boundaries

### R0 — native ownership/RIL normalization only

- **Coverage:** X55 rebirth, PM ownership normalization, qcrild2 process reconstruction.
- **Risk:** already characterized native handoff/radio interruption risk; no new framework reset.
- **slot0:** shared modem/PM effects are possible; no direct slot0 SIM write.
- **Automation:** yes, existing bounded state machine and gates.
- **Reversible:** operationally yes if native ownership returns clean; not a framework lifecycle reset.
- **Verdict:** already insufficient as a general repeatability boundary because V1 passed A/P canonical gates yet retained the NRM-to-SST failure.

### R1 — slot1 Phone/SST lifecycle reconstruction

- **Coverage intended:** recreate Phone[1]-owned ANM, both NRMs, QtiSST and DNC while preserving Phone[0] and shared vendor processes.
- **Risk:** conceptually the smallest boundary matching the fork; would transiently remove slot1 telephony/data/IMS state.
- **slot0:** ideally none, if a real slot-scoped factory/dispose API existed.
- **Automation:** **not currently available.** No verified public Binder, `cmd`, shell, broadcast, or hidden API atomically disposes and reconstructs only Phone[1]. SIM power/subscription reloads refresh inputs but do not destroy these Phone-owned objects. “Re-arm SST listener” would be a point workaround, not a lifecycle reset.
- **Reversible:** unknown because no supported production entry exists.
- **Verdict:** theoretical minimum, but not an executable experiment on the evidence available. Do not invent a private call or patch SST to simulate it.

### R2 — vendor QNS/IWLAN provider lifecycle reconstruction

- **Concrete executable subset:** R0 plus one bounded `.qtidataservices` reconstruction, which recreates QualifiedNetworksServiceImpl, IWlanNetworkService, IWlanDataService and CNE together. Existing ANM/NRM/DataServiceManager clients should observe Binder death and rebind.
- **Coverage:** vendor provider objects and CNE trackers; forces client rebind/re-registration.
- **Not covered:** Phone[1], ANM object, NRM object, SST, DNC and their process-local generations/caches. A true “DNC lifecycle rebuild” collapses into R3 because DNC is Phone-owned.
- **Risk:** both-slot IWLAN/QNS/CNE interruption; active WFC/data handover can drop. Earlier isolated/full-stack rebuilds failed in other scenes.
- **slot0:** yes; `.qtidataservices` is shared by both slots.
- **Automation:** yes in principle with exact-PID/identity/respawn gates, but it is only a provider-rebind experiment.
- **Reversible:** normally auto-respawn/rebind, but recovery is not guaranteed.
- **Verdict:** smaller than R3 but does not cross the first confirmed stale-object boundary (SST). A PASS would be useful; a FAIL would remain ambiguous between stale client objects and unrelated residue.

### R3 — `com.android.phone` process boundary (diagnostic)

- **Coverage:** recreates PhoneFactory/Phone[0..n], Phone[1]-owned ANM, NRM, QtiSST, DNC/TNF, framework ImsResolver/controllers and all their callback generations; rebinds to existing Radio, QNS/IWLAN and Qualcomm IMS services.
- **Risk:** high, device-wide telephony-framework outage; transient subscription, Binder service, IMS and cellular-data loss. Prior broad tests prove it is not a guaranteed repair.
- **slot0:** yes. Both slots live in the process, so slot0 cannot be claimed isolated.
- **Automation:** yes only after a separate static executor/safety audit with exact process identity, automatic init/package recovery, readiness gates, bounded timeout and no fallback.
- **Reversible:** the persistent package should respawn and rebind, but a failed restart can require a later broader recovery; therefore diagnostic only.
- **Verdict:** first currently identifiable boundary that deterministically destroys every framework object spanning the observed NRM-to-SST-to-DNC fork.

## Minimum candidate and recommended first validation

There are two meanings of “minimum”:

1. **Minimum causal boundary:** R1, a slot1 Phone/SST lifecycle reconstruction.
2. **Minimum verified executable object-recreation boundary:** R3, restart of `com.android.phone` after R0 normalization.

R1 is not currently exposed on this ROM and must not be approximated by a listener poke or SST patch. R2 is executable but only recreates the provider side; it does not destroy the suspected stale SST/DNC objects. Therefore the recommended first diagnostic is **R3**, explicitly to falsify or support the framework-lifecycle hypothesis, not as a production solution.

The older com.android.phone/full-stack failure lowers prior confidence that R3 will recover WFC. It does not make a new fixed-R repeatability experiment invalid: that older run did not use the same A/R/P contract, the same frozen v2.6.2 path, or the newly observed W1/V1 residue transition. Expected information gain, rather than expected success, is the reason to test R3 first.

## Falsifiable R3 experiment design (not executed)

### Frozen variables

- `R = R0 normalization + exactly one audited com.android.phone lifecycle restart`.
- `P = the already frozen canonical preparation; no added wait or state repair after seeing results`.
- Recovery = exact provenance/hash-locked v2.6.2; no source change.
- Same SIM topology, VOXI mapping, Wi-Fi/VPN/location prerequisites, observation windows and health rule for every cycle.
- Minimum three consecutive cycles, including a post-success cycle where cross-cycle residue would be expected.

### Pre-write design gates for a future separately authorized executor

1. Prove the exact main-user `com.android.phone` PID, UID, SELinux domain, package and automatic respawn mechanism on the current ROM.
2. Record both-slot mapping and forbid execution during calls/emergency state.
3. Complete R0 and require native-clean ownership/X55/crash-count gates before R3.
4. Allow one graceful exact-PID termination only; no force-stop, killall, SIGKILL, system_server action, or secondary process restart.
5. Require a different `com.android.phone` PID and fresh creation logs for Phone[1], ANM-1, NRM-I-1, QtiSST-1, DNC-1 and ImsResolver/MMTEL bindings.
6. Require stable VOXI/UICC mapping and all framework services before entering fixed P. Do not use desired WFC/SST state as a gate that repairs the trial.

### Per-cycle decision

After fixed R and fixed P, run unchanged v2.6.2 once and observe the complete chain:

`ANM IMS->IWLAN -> NRM IWLAN/HOME callback -> SST consumption -> DNC WLAN transition -> qti.cne IMS request -> IMS NetworkAgent -> REGISTERED/WLAN -> VOICE/IWLAN -> WFC`

- Three consecutive healthy cycles: `R3_REPEATABILITY_SUPPORTED`, not yet a minimal production boundary. Then design a fresh comparison between R2 and a genuinely slot-scoped R1 implementation if one is discovered.
- Any failed cycle after R3 readiness gates pass: `R3_FALSIFIED`. Stop. Do not add an SST workaround, qtidataservices restart, extra wait, extra SIM cycle, or other fallback.
- If com.android.phone does not reconstruct cleanly: `R3_EXECUTION_INVALID`, preserve evidence and stop; do not classify WFC.

### Interpretation matrix

| Result | Meaning |
|---|---|
| R3 passes 3/3 | Strong support for process-local telephony lifecycle residue; R1/R2 narrowing becomes justified. |
| R3 fails at the same NRM-to-SST edge | The residue is not eliminated by telephony process reconstruction; H1 at this boundary is falsified and investigation must move outside that object graph. |
| R3 changes the first divergence but WFC still fails | R3 reset the identified residue but is not sufficient; still a fail for the proposed R, with no in-run enlargement. |
| R3 cannot restore stable framework readiness | Invalid trial; executor/lifecycle mechanism must be redesigned before any WFC conclusion. |

## Final conclusion

- R0 resets the native X55/PM/qcrild2 side but leaves the entire framework object graph alive.
- A true slot1-only R1 would be the causal minimum, but no supported reconstruction entry exists.
- R2 reconstructs vendor providers and CNE, not SST/DNC; it is a rebind boundary rather than the required framework object boundary.
- R3 is the smallest presently verified boundary that deterministically destroys and recreates ANM, NRM, SST and DNC together. It is broad, affects both slots, and is recommended only as the first falsifiable diagnostic.
- No phone operation was performed. The current airplane-mode state was not read or changed.
