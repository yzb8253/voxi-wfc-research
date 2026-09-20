# BAD vs GOLDEN Native DSD/QNS Diff

Date: 2026-09-20

Target: fixed VOXI slot 1 / `IIWlan/slot2`

Mode: read-only; phone writes: **0**

## Capture integrity

- BAD snapshot SHA-256: `31727FD5AAC506D429BB14DFD205280ED0B5A2D90BC411253A9982E1189B5687`
- GOLDEN snapshot SHA-256: `602E81EA342A7185BDA3000CCCDF406C77354878D17DD7BF253B28361E371CB6`
- Both snapshots were produced by the same audited `capture_qns_native_snapshot.ps1` command set.
- `GET_ALL_QUALIFIED_NETWORKS_CALLED=NO` and `SET_RESPONSE_FUNCTIONS_CALLED=NO` in the GOLDEN capture.
- Raw captures remain in the ignored local `captures/` directory and are not committed because they contain full device dumps.

## GOLDEN validity gate

The direct probe at `2026-09-20T23:00:22.272+08:00` reported:

| Gate | GOLDEN value | Result |
|---|---|---|
| IMS registration | `REGISTERED (2)` | PASS |
| IMS transport | `WLAN (2)` | PASS |
| VOICE/IWLAN | available | PASS |
| WFC | available | PASS |
| PS/WLAN | `HOME`, technology `IWLAN` | PASS |
| `mIsIwlanPreferred` | `true` | PASS |
| qti.cne IMS request | active, request ID 263 | PASS |
| IMS IWLAN NetworkAgent | present, network ID 102 | PASS |
| UDP/4500 | present, 20-second keepalive | PASS |
| XFRM | present | PASS |

The script's shell-context `ip xfrm` section could not open the netlink socket. A separate root **read-only** validation immediately afterward showed two live ESP tunnel SAs with UDP encapsulation, one inbound and one outbound, including UDP/4500. No state was changed.

Result: `GOLDEN_CAPTURE_VALID`.

## Current field-level diff

| Field | BAD/F1 | GOLDEN/F0 | Difference |
|---|---|---|---|
| IMS APN | `ims`, type `IMS` | `ims`, type `IMS` | none |
| IMS qualified networks | `[]` | `[]` | none |
| IMS `hasPendingIntent` | `false` | `false` | none |
| DEFAULT APN | `wap.vodafone.co.uk`, types `DEFAULT|MMS|SUPL|HIPRI` | same | none |
| DEFAULT qualified networks | `[]` | `[]` | none |
| DEFAULT `hasPendingIntent` | `false` | `false` | none |
| EIMS APN | `sos`, type `EMERGENCY` | same | none |
| EIMS qualified networks | `[]` | `[]` | none |
| EIMS `hasPendingIntent` | `false` | `false` | none |
| `globalPrefSys` | `IWLAN` | `IWLAN` | none |
| `LastReportedNetworkAvailability` | empty | empty | none |
| Per-APN IMS preferred system | not exposed / `UNKNOWN` | not exposed / `UNKNOWN` | unknown |
| Per-APN IMS available systems | not exposed / `UNKNOWN` | not exposed / `UNKNOWN` | unknown |
| Raw validity/sequence fields | not exposed | not exposed | unknown |

The current `NetworkAvailabilityCache` fields are therefore semantically identical for IMS, DEFAULT, and EIMS. In particular, GOLDEN does **not** retain `IMS -> [IWLAN]` in the current table.

## Lifecycle evidence and cache semantics

The GOLDEN dump's bounded internal history does show transient native qualification before WFC came up:

```text
22:58:07.845  ims networks=[UNKNOWN,IWLAN]
22:58:47.118  ims networks=[IWLAN,UNKNOWN]
22:58:47.299  type=IMS networks=[IWLAN,UNKNOWN]
```

By capture time, however, the current APN cache and `LastReportedNetworkAvailability` were empty even though IMS was registered over WLAN and the CNE/ePDG/XFRM path was alive. A later profile/cache lifecycle can therefore clear this dump table without tearing down an already-established IMS data path.

This is **CASE B** from the experiment plan:

```text
BAD:    IMS -> [] and WFC unavailable
GOLDEN: IMS -> [] and WFC available
```

Consequently, the current `dumpCache` table is a transient input/reporting cache, not a durable representation of the active IMS network or the full decision state. A single late snapshot cannot establish `per-APN DSD availability -> cache` as the root boundary.

## First concrete difference

There is no concrete difference in the current native APN-cache fields exposed by this dump. The first concrete **live-state** difference is downstream: GOLDEN has an active qti.cne IMS request and IMS IWLAN NetworkAgent, followed by UDP/4500, XFRM, and REGISTERED/WLAN; BAD has none of them.

The transient GOLDEN history proves that an IMS/IWLAN qualified-network update occurred during successful establishment, but the BAD dump's retained history spans earlier lifecycles too. It is not a synchronized event-by-event pair and cannot by itself identify the missing upstream per-APN QMI field.

## Verdict

- Native cache case: `CASE_B`
- `ROOT_BOUNDARY`: **NOT CONFIRMED BY CURRENT DUMPCACHE**
- Revised boundary: between the transient DSD/QNS qualification event and creation/persistence of the CNE IMS demand; the exact minimum state remains unknown.
- Confidence: **HIGH** that the current cache table is insufficient as a state discriminator; **MEDIUM** that the decisive lifecycle boundary remains DSD/QNS-to-CNE demand delivery.

## Required result block

```text
=== BAD VS GOLDEN NATIVE DSD/QNS DIFF ===

BAD SHA256:
31727FD5AAC506D429BB14DFD205280ED0B5A2D90BC411253A9982E1189B5687

GOLDEN SHA256:
602E81EA342A7185BDA3000CCCDF406C77354878D17DD7BF253B28361E371CB6

BAD IMS:
apn=ims, types=IMS, hasPendingIntent=false, networks=[]

GOLDEN IMS:
apn=ims, types=IMS, hasPendingIntent=false, networks=[]

BAD DEFAULT:
apn=wap.vodafone.co.uk, types=DEFAULT|MMS|SUPL|HIPRI, hasPendingIntent=false, networks=[]

GOLDEN DEFAULT:
same as BAD; networks=[]

BAD EIMS:
apn=sos, types=EMERGENCY, hasPendingIntent=false, networks=[]

GOLDEN EIMS:
same as BAD; networks=[]

globalPrefSys BAD:
IWLAN

globalPrefSys GOLDEN:
IWLAN

per-APN IMS preferred:
BAD: UNKNOWN / not exposed
GOLDEN: UNKNOWN / not exposed

per-APN IMS available:
BAD: raw UNKNOWN; current converted vector []
GOLDEN: raw UNKNOWN; current converted vector []

hasPendingIntent:
BAD: false
GOLDEN: false

IMS health GOLDEN:
REGISTERED(2), WLAN(2), VOICE/IWLAN available, WFC available, PS/WLAN HOME, mIsIwlanPreferred=true

CNE:
active IMS request 263; IMS IWLAN NetworkAgent 102 present

UDP4500:
present; 20-second keepalive

XFRM:
present; inbound and outbound ESP-in-UDP tunnel SAs confirmed read-only

First concrete native difference:
None in the current dumpCache fields. GOLDEN history transiently contains IMS->[IWLAN,UNKNOWN], but the current GOLDEN table has already returned to [].

ROOT_BOUNDARY:
NOT CONFIRMED BY CURRENT DUMPCACHE. The dump is a transient qualification/report cache and is not the durable active IMS decision state.

Confidence:
HIGH for CASE B and dump-semantic insufficiency; MEDIUM for the remaining DSD/QNS-to-CNE lifecycle boundary.

NEXT_SAFE_ACTION:
Candidate only: perform a read-only, timestamp-aligned lifecycle capture during a future real insert/recovery, preserving native NAH/DSD history plus ANM callback, CNE request creation, and IMS tunnel events in one clock domain. Do not invoke refresh/query/write APIs.

Phone writes performed:
0
```
