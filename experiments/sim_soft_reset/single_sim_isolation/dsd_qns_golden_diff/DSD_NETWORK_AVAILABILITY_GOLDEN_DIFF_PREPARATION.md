# DSD / Network Availability Golden-Diff Preparation

Date: 2026-09-20

Target: fixed VOXI slot 1 / `IIWlan/slot2`

Mode: read-only; phone writes: **0**

## Current F1 native bad snapshot

The current state was captured with the already-audited HIDL `IBase::debug` path. No IIWlan business method or response-function setter was called.

```text
NetworkAvailabilityHandler:
    globalPrefSys= IWLAN
    NetworkAvailabilityCache ==>
    apn=sos hasPendingIntent=false
         apn types=[EMERGENCY|] networks=[]
    apn=ims hasPendingIntent=false
         apn types=[IMS|] networks=[]
    apn=wap.vodafone.co.uk hasPendingIntent=false
         apn types=[DEFAULT|MMS|SUPL|HIPRI|] networks=[]
    LastReportedNetworkAvailability ==>

NetworkServiceHandler:
    RegistrationState=REG_HOME

InitTracker:
    AuthServiceReady=true
    DsdServiceReady=true
    WdsServiceReady=true
    IWLANEnabled=true
    ModemCapability=true
    IWlanHandshakeMsgToken=-1
    CurrentDDS=1
```

The framework-side read-only probe simultaneously reports PS/WLAN HOME, radio technology IWLAN, and `mIsIwlanPreferred=true`, while IMS is NOT_REGISTERED, VOICE/IWLAN is unavailable, and WFC is unavailable (F1).

## Per-APN field matrix

| Field | IMS | DEFAULT | EIMS |
|---|---|---|---|
| APN name | `ims` | `wap.vodafone.co.uk` | `sos` |
| APN type mask | `IMS` | `DEFAULT\|MMS\|SUPL\|HIPRI` | `EMERGENCY` |
| `hasPendingIntent` | `false` | `false` | `false` |
| Cached qualified networks | `[]` | `[]` | `[]` |
| Per-APN preferred system | `UNKNOWN` (not exposed by current dump with no pending intent) | `UNKNOWN` | `UNKNOWN` |
| Per-APN available systems, raw QMI | `UNKNOWN` (not retained/exposed by dump) | `UNKNOWN` | `UNKNOWN` |
| Converted available-system vector | `[]` | `[]` | `[]` |
| Valid/sequence/version field | `UNKNOWN`; no such field is exposed by this dump | `UNKNOWN` | `UNKNOWN` |

The raw QMI `dsd_apn_avail_sys_info` and `dsd_apn_pref_sys` payloads are not present in the current dump. They must remain unknown until a dump/log source exposes them; `globalPrefSys=IWLAN` is not a substitute for those per-APN fields.

## Exact cache writers

Static analysis of the current-ROM `libril-qc-hal-qmi.so` establishes these paths.

### Profile rebuild path

```text
DataModule setDataProfile handling
  -> NetworkAvailabilityHandler::processSetDataProfileRequest(message)
  -> NetworkAvailabilityHandler::updateNetworkAvailabilityCache(message)
     -> clear/rebuild APN-name map from the supplied profiles
     -> populate APN-type vectors
     -> initialize/preserve no qualified network unless one is already available in the same rebuild
```

The implementation clears the handler's APN map before rebuilding it. Newly inserted `ConsolidatedNetwork_t` entries have `hasPendingIntent=false` and an empty network vector. This explains why an IMS profile can be present while `networks=[]`; profile presence alone is not qualification.

### Per-APN available-system path

```text
QMI DSD per-APN system-status indication
  -> DSDModemEndPointModule
  -> DsdSystemStatusPerApnMessage
  -> DataModule::handleDsdSystemStatusPerApn(message)
  -> NetworkAvailabilityHandler::processQmiDsdSystemStatusInd(entries, length)
  -> updateNetworkAvailabilityCache(dsd_apn_avail_sys_info_type_v01*, length)
```

For each indication entry, the implementation:

1. lowercases and validates a non-empty APN name;
2. matches the APN-name map, or creates an entry and resolves its APN types through `WDSModemEndPoint::getApnTypesForName`;
3. reads `avail_sys_len`; zero takes the explicit `no available system for apn` branch;
4. converts every DSD system-status entry through `convertToRadioAccessNetworkList`;
5. maps the DSD IWLAN system enum to internal access-network value `5` (`IWLAN`), maps unsupported values to `0` (`UNKNOWN`), and deduplicates the vector;
6. compares the converted vector with the cached per-APN vector and suppresses an unchanged update;
7. if a pending intent exists, completes it only when the actual available-system result matches the pending preferred RAT, then clears `hasPendingIntent`;
8. calls `convertResultList`, broadcasts `QualifiedNetworksChangeIndMessage` only when the converted/reportable result is non-empty and changed.

### Intent-to-change path

```text
QMI DSD intent-to-change APN preferred-system indication
  -> DSDModemEndPointModule::processIntentToChangeApnPrefSysInd(...)
  -> IntentToChangeApnPreferredSystemMessage
  -> DataModule::handleIntentToChangeInd(message)
  -> NetworkAvailabilityHandler::processQmiDsdIntentToChangeApnPrefSysInd(...)
  -> updateNetworkAvailabilityCache(dsd_apn_pref_sys_type_ex_v01*, length)
```

For each entry, the implementation lowercases the APN name, requires an existing APN cache entry, converts the preferred system, moves/inserts that RAT at the front of the per-APN network vector, sets `hasPendingIntent=true`, and generates a changed qualified-network result. A preferred-system value of `2` is converted directly to internal access-network `5` (`IWLAN`). If the APN name is absent, it logs `cannot find entry with apn name` and does not create the preferred-system result.

## Result conversion and suppression

`NetworkAvailabilityHandler::convertResultList` is not the source of an IWLAN qualification. It converts already-populated per-APN cache entries into APN-type results and applies reporting rules.

The decisive empty-result branch is explicit:

```text
if network_vector.empty() || network_vector.front() == UNKNOWN:
    log "Skipping UNKNOWN or empty network for APN type ..."
    do not emit that APN type
```

It also consolidates duplicate APN types, compares preferred RATs against previously reported/global state, and suppresses unchanged results. Those later suppression rules cannot turn the raw cache dump's `networks=[]` into IWLAN; the raw vector is already empty before conversion.

## Why `globalPrefSys=IWLAN` is insufficient

`setGlobalPreferredSystem` writes a separate handler-level field from a general DSD system-status value. It does not populate every APN's network vector.

IMS becomes `[IWLAN]` only when its own `ConsolidatedNetwork_t.networks` vector receives IWLAN from either:

- a per-APN `dsd_apn_avail_sys_info` entry with a convertible IWLAN available system; or
- a per-APN intent-to-change entry whose preferred system converts to IWLAN.

The current IMS entry is:

```text
apnName = ims
apnTypes = IMS
hasPendingIntent = false
perApnPreferredSystem = UNKNOWN
rawAvailableSystems = UNKNOWN
convertedNetworks = []
convertedResult = skipped
```

The direct reason for `IMS networks=[]` is therefore known: the current per-APN network vector is empty, and `convertResultList` skips it. The raw upstream reason remains **UNKNOWN** because the dump does not show whether an IMS per-APN DSD indication was absent, carried `avail_sys_len=0`, contained only invalid/UNKNOWN systems, or was lost before the handler. The internal history shows no later IMS network-list population after the last profile rebuild, but that is evidence of the missing cache update, not proof of which upstream QMI field failed.

No sequence number, generation, version, or validity flag governing this cache was identified in these three update functions. If such gating exists earlier in `DSDModemEndPointModule`, it remains outside the proven handler-local boundary.

## Golden capture script

`capture_qns_native_snapshot.ps1` performs the same fixed-slot2 read-only capture for both BAD and future GOLDEN states:

- ADB device and root identity;
- fixed `IIWlan/slot2` service inventory;
- `IBase::debug` native cache and bounded internal history;
- direct IMS/WFC health probe;
- telephony registry, phone/ANM/DNC, telephony IMS, and connectivity/CNE dumps;
- wlan0/tun0, routes, rules, UDP/4500, and XFRM;
- relevant process identity and recent DSD/QNS/ANM/DNC logs;
- host/device timestamps.

It writes only the host-side `native_qns_snapshot_<timestamp>.txt` file under the ignored `captures/` directory. It never calls `setResponseFunctions`, `getAllQualifiedNetworks`, a QMI method, a settings/property mutation, a SIM operation, or a process-control command.

Validation on the current F1 scene: **PASS**. PowerShell parsing succeeded, all 12 capture sections completed with ADB exit code 0, and the final ignored BAD snapshot contained the direct-health JSON and complete slot2 native cache. The local capture SHA-256 was `31727FD5AAC506D429BB14DFD205280ED0B5A2D90BC411253A9982E1189B5687`; the raw capture is intentionally not committed.

## Required result block

```text
=== F1 NATIVE DSD/QNS SNAPSHOT ===

IMS cache:
apn=ims, types=IMS, hasPendingIntent=false, networks=[]

DEFAULT cache:
apn=wap.vodafone.co.uk, types=DEFAULT|MMS|SUPL|HIPRI, hasPendingIntent=false, networks=[]

EIMS cache:
apn=sos, types=EMERGENCY, hasPendingIntent=false, networks=[]

globalPrefSys:
IWLAN

per-APN IMS preferred system:
UNKNOWN (not exposed by current dump)

per-APN IMS available systems:
raw UNKNOWN; converted cache vector []

Why IMS networks=[]:
The APN profile exists, but its per-APN network vector is empty. convertResultList explicitly skips an empty vector or one beginning with UNKNOWN. globalPrefSys does not populate this vector.

Exact cache update functions:
processSetDataProfileRequest/updateNetworkAvailabilityCache(message);
processQmiDsdSystemStatusInd/updateNetworkAvailabilityCache(dsd_apn_avail_sys_info...);
processQmiDsdIntentToChangeApnPrefSysInd/updateNetworkAvailabilityCache(dsd_apn_pref_sys...);
convertToRadioAccessNetworkList;
convertResultList.

Missing/invalid field:
Proven missing state: per-APN IMS qualified-network vector. Raw DSD preferred/available-system field and its validity are UNKNOWN in this dump.

Golden capture script:
PASS

Phone writes:
0

NEXT_ACTION:
Wait for user-provided real WFC Golden state, then run exactly the same snapshot and diff.
```
