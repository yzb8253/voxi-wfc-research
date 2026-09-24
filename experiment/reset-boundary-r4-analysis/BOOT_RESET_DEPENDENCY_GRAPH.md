# Boot reset dependency graph for the current ROM

Date: 2026-09-24 (Asia/Shanghai)

Baseline: `73735fe1356276b64614f925dd7917073da3c0ee`

Mode: repository and existing-log analysis only. No ADB command was issued and phone writes were **0**.

## Scope and evidence standard

This is the current Xiaomi ROM's observed dependency graph, not a generic AOSP diagram. Current-ROM process/service inventory, APK analysis, QCRIL source-correlated analysis, the R3 phone-rebuild log, and prior controlled restart results are used together. Where the ROM does not expose an internal callback identity or object address, the field is marked unobservable rather than inferred as a pass.

The graph is a readiness partial order. Android init and ActivityManager start several branches concurrently, so it must not be read as a claim that every row starts strictly after the previous row.

## Boot/readiness graph

```text
Android init
  |
  +--> vendor.per_mgr --> pm-service --owns /dev/subsys_esoc0--> X55 ONLINE
  |                                                        |
  |                                                        +--> modem QMI services ready
  |
  +--> vendor.qcrild  (/vendor/bin/hw/qcrild) -------------+--> IRadio/slot1 + shared QtiBus/QMI
  |
  +--> vendor.qcrild2 (/vendor/bin/hw/qcrild -c 2) --------+--> IRadio/slot2
       |                                                        IIWlan/slot2
       |                                                        DataModule
       |                                                        DSD/WDS endpoints
       |                                                        NetworkAvailabilityHandler
       |
       +<-- HIDL setResponseFunctions(response, indication) -- IWlanProxy in .qtidataservices
       |         |
       |         +--> IWLANCapabilityHandshake(true)
       |                --> initializeIWLAN()
       |                --> AP-assist indication registration
       |
       +--> qualifiedNetworksChangeIndication ------------------------------+
       +--> dataRegistrationStateChangeIndication ---------------------+     |
                                                                         |     |
ActivityManager starts persistent .qtidataservices (UID 10104)           |     |
  +--> vendor.qti.iwlan/.QualifiedNetworksServiceImpl <------------------|-----+
  +--> vendor.qti.iwlan/.IWlanNetworkService <--------------------------+
  +--> vendor.qti.iwlan/.IWlanDataService
  +--> com.qualcomm.qti.cne/.CneApp <--> native vendor.cnd
  |                                      |
  |                                      +--> requestNetwork(IMS, slot1)
  |                                            --> DataCallAgent
  |                                            --> ConnectivityManager
  |                                            --> ConnectivityService
  |
ActivityManager starts persistent com.android.phone (UID 1001)
  +--> PhoneFactory --> Phone[0] / Phone[1]
       +--> ANM-1 --binds QNS----------------------------------------------+
       +--> SST-1 --> NRM-I-1 --binds IWlanNetworkService-----------------+
       +--> DNC-1 --binds IWlanDataService
       +--> ImsResolver --binds org.codeaurora.ims/.ImsService
       +--> CarrierConfig/subscription listeners

ConnectivityService receives CNE's IMS request
  --> TelephonyNetworkFactory[1]
  --> DNC-1 selects IMS APN/transport
  --> IWLAN data service / ePDG / XFRM
  --> Qualcomm IMS REGISTERED/WLAN
  --> VOICE/IWLAN and WFC available
```

`ANM -> NRM -> SST -> DNC -> qti.cne -> IMS` is therefore only a milestone shorthand. CNE originates the Android IMS `NetworkRequest` from a native `cnd` callback; DNC does not call CNE to create it.

## Current-ROM component table

| Component | Process / PID owner | Service or interface | Producer -> consumer / registration direction | Initial state publication | Death/rebind behavior |
|---|---|---|---|---|---|
| X55 / PM | init services `vendor.per_mgr`, `vendor.per_proxy`, `vendor.mdm_helper`; native `pm-service` owns `/dev/subsys_esoc0` | ESOC/peripheral-manager device and QMI transport | PM powers/monitors X55; qcrild processes consume modem services | X55 `ONLINE`, PON success and QMI service availability | init supervises services; R0 explicitly normalizes ownership and X55 epoch |
| Primary RIL | `vendor.qcrild`, `/vendor/bin/hw/qcrild`, UID radio, init-owned | `IRadio/slot1`, shared QtiBus/QMI infrastructure | modem/QMI -> RIL -> framework RIL client | radio/SIM/network unsolicited indications and query responses | init restarts process; clients reconnect; not recreated by R3 |
| Target RIL | `vendor.qcrild2`, `/vendor/bin/hw/qcrild -c 2`, UID radio, init-owned | `IRadio/slot2`; `vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot2` | DataModule/DSD -> IIWlan HIDL -> qtidataservices | HIDL indications plus explicit cache/registration queries | HIDL death recipient in qtidataservices reconnects; new `setResponseFunctions` creates a new native NAH epoch |
| Native IWLAN qualification | inside qcrild2 | DataModule, DSD/WDS endpoints, `NetworkAvailabilityHandler` | DSD system/APN status -> NAH -> `qualifiedNetworksChangeIndication` | Per-APN qualified-network indication; current cache can also be read explicitly | qcrild2 death recreates it. `initializeIWLAN()` replaces NAH but replays cached status unless a fresh DSD status path also runs |
| qtidataservices host | persistent `.qtidataservices`, UID 10104, SELinux `vendor_qtidataservices_app` | Shared process for QNS, IWLAN services, CNE and CA-cert service | Hosts the Java bridge between HIDL/native and framework | component-specific | ActivityManager restarts the process; individual bound Service objects may be destroyed/recreated without PID death |
| QNS provider | `.qtidataservices` | `vendor.qti.iwlan/.QualifiedNetworksServiceImpl`, `BIND_TELEPHONY_DATA_SERVICE` | native IIWlan indication -> provider `updateQualifiedNetworkTypes` -> ANM callback | Desired IMS->IWLAN state is delivered by qualified-network indication. Immediate replay on every new framework binding is not established | R3 log shows the QNS Service was created again in the same old PID and ANM rebound; it did **not** publish IMS->IWLAN in P |
| IWLAN NetworkService | `.qtidataservices` | `vendor.qti.iwlan/.IWlanNetworkService`, `BIND_TELEPHONY_NETWORK_SERVICE` | IIWlan registration-state response/indication -> NRM | New NRM makes explicit registration queries; current service returned IWLAN `NOT_REG_OR_SEARCHING` after R3 | bound service can recreate/rebind in same process; process death recreates its Java/static state |
| IWLAN DataService | `.qtidataservices` | `vendor.qti.iwlan/.IWlanDataService` | DNC/DataServiceManager -> vendor IWLAN data-call APIs | bind plus data-call list/indications | rebind on phone death; process death recreates service |
| CNE Java | `.qtidataservices` | `com.qualcomm.qti.cne/.CneApp`; private CNE HIDL callback | native `cnd` -> `NativeHalServerCallback.requestNetwork` -> `DataCallAgent` -> Android Connectivity | no public replay API; tracker/request creation follows native callback | `.qtidataservices` death recreates connector and trackers; prior isolated restart did not restore IMS demand |
| CNE native | `vendor.cnd`, init-owned, UID system | Qualcomm private CNE native/HIDL path | modem/native state -> CneApp callback | native request callback, including IMS demand | init restart reconnects Java CNE, but coordinated cnd/qtidataservices restart previously failed in a preserved F1 scene |
| Telephony process | persistent `com.android.phone`, UID 1001, SELinux `u:r:radio:s0` | framework telephony Binder services and internal object graph | consumes RIL, QNS, NetworkService, DataService, CarrierConfig and IMS services | builds Phone graph then queries/binds providers | ActivityManager recreates after exact PID death; this is R3 |
| PhoneFactory / Phone[0,1] | `com.android.phone` | internal factory/objects | constructs per-phone ANM, SST/NRM and DNC | constructor-driven registration and provider binds | destroyed with process; R3 log proves new objects |
| ANM-1 | `com.android.phone` | client of QualifiedNetworksService | QNS callback -> preferred-transport map -> DNC | depends on QNS publication; desired IMS->IWLAN was absent after R3 | new object on R3; provider death causes rebind, not Phone recreation |
| NRM-I-1 | `com.android.phone` | client of IWlanNetworkService | requests PS/WLAN registration and registers change callback -> SST | request/response plus provider change notification | new object on R3; after rebind it received `NOT_REG_OR_SEARCHING` |
| SST-1 | `com.android.phone` | `QtiServiceStateTracker` internal Handler | consumes WWAN/WLAN NRM results -> consolidated ServiceState | polling and NRM callbacks | new object on R3; no standalone supported re-arm API found |
| DNC-1 | `com.android.phone` | `DataNetworkController`, DataServiceManager, TNF | consumes ANM/SST and Connectivity requests; drives data network | current state plus callbacks/requests | new object on R3; binds old vendor DataService process |
| CarrierConfig | loader/controllers in `com.android.phone` plus carrier-config package/service | CarrierConfig Binder/listeners | SIM/subscription -> config loader -> telephony/IMS consumers | LOADED/current-subscription callbacks | R3 restored it for subId 11; not the first divergence |
| ImsResolver/MMTEL | resolver/controllers in `com.android.phone`; provider in persistent `org.codeaurora.ims` | protected `android.telephony.ims.ImsService` binding | framework binds vendor per-slot MMTEL; vendor reports feature/registration | feature READY and registration callbacks | R3 recreates resolver side and rebinds unchanged vendor IMS PID; R3 restored READY |
| IMS request/data path | native `cnd` + `.qtidataservices` + `system_server` ConnectivityService + `com.android.phone` TNF/DNC | CNE private HIDL; Android `ConnectivityManager.requestNetwork` | cnd -> CNE DataCallAgent -> ConnectivityService -> TNF/DNC -> IWLAN/ePDG | new IMS request is event-driven, not derived merely from MMTEL READY | process deaths rebind portions; no verified public request-replay API exists |

## Boot-created epochs

A full reboot creates at least four relevant epochs together:

1. **Modem/PM epoch:** X55 firmware and QMI services become available under a new boot/PON sequence.
2. **Native producer epoch:** qcrild/qcrild2, DataModule, DSD/WDS clients, NAH and IIWlan callback ownership are created from zero.
3. **Java provider epoch:** `.qtidataservices` creates its HIDL proxy/callback, QNS, NetworkService, DataService and CNE objects against that new producer.
4. **Framework consumer epoch:** `com.android.phone` creates Phone/ANM/NRM/SST/DNC and binds after providers become available.

R3 recreated only epoch 4. The R3 log additionally shows that QNS and NetworkService bound-Service instances were recreated inside the unchanged `.qtidataservices` PID, so “OLD provider + NEW framework” must be stated precisely: the old **process/static HIDL-proxy/native producer epoch** survived even where a Java Service instance was newly created.

## Evidence anchors

- `experiment/reset-boundary-r3/runs/r3_3cycle_v2/RESULT.md`
- host-only R3 rebuild log SHA-256 `46B77E0A7169C53F2C663F02CC6182D1C4C23AA69E092E702C0AD036ACAEE485`
- `experiments/sim_soft_reset/single_sim_isolation/dsd_qns_golden_diff/MINIMUM_QCRIL_REINIT_ENTRY_AUDIT.md`
- `experiments/sim_soft_reset/single_sim_isolation/dsd_qns_golden_diff/P_TO_R_QCRILD2_COLD_RESTART_RESULT.md`
- `autopilot/phase7_qcom_ims_cne/PHASE7_QCOM_IMS_CNE_RECOVERY_BOUNDARY.md`
- `autopilot/phase8b_restart_cne/PHASE8B_CNE_RESTART_RESULT.md`
- `autopilot/phase8d_coordinated_restart/PHASE8D_COORDINATED_RESTART_RESULT.md`
