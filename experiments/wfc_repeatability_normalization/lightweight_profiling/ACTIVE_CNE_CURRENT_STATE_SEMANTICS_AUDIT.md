# Active CNE current-state semantics audit

Date: 2026-09-25  
Branch baseline: `4d94cf249e5e0bef26004a7940f8b9ed6c5d240e`  
Phone writes: 0

## Short observation epoch

Only `LIGHT_A -> dumpsys connectivity -> LIGHT_B` was captured. No full
snapshot, logcat, process operation, SIM operation, or state change was used.

| Sample | Host/device time | qcrild2 | request / satisfied |
|---|---|---:|---|
| LIGHT_A | host 21:00:42.104–21:00:45.742; device 1790341241648–1790341244958 | 25719 | 1518 / 1518 |
| RAW connectivity | device 1790341245372–1790341245680 | 25719 before and after | current null / null; history RELEASE 1518 / 1518 |
| LIGHT_B | host 21:00:46.885–21:00:50.371; device 1790341246408–1790341249582 | 25719 | 1518 / 1518 |

The device span from LIGHT_A start through LIGHT_B end was 7,934 ms. qcrild2
did not change. This is not a state-drift case.

## Raw result

`1518` exists in the raw dump only below `mNetworkRequestInfoLogs`, in this
historical row:

```text
2026-09-25T20:36:54.274129 - RELEASE ... activeRequest: 1518 ...
NetworkRequest [ REQUEST id=1518 ... Capabilities: IMS ...
mSubId = 11 ... RequestorPkg: com.qualcomm.qti.cne ... ]
```

The live section before `mNetworkRequestInfoLogs` contains no VOXI IMS CNE
request 1518 and no other current CNE IMS request for sub 11. Consequently it
also contains no current satisfied network/NetworkAgent relation for request
1518. The current qti.cne INTERNET request is unrelated.

```text
RAW_CONNECTIVITY_HAS_1518=HISTORY_ONLY
RAW_CURRENT_CONNECTIVITY_HAS_1518=NO
RAW_HISTORY_HAS_RELEASE_1518=YES
WFCCTL_REQUEST_ID_LIGHT_A=1518
WFCCTL_SATISFIED_ID_LIGHT_A=1518
OLD_PROJECTED_REQUEST_ID=null
OLD_PROJECTED_SATISFIED_ID=null
WFCCTL_REQUEST_ID_LIGHT_B=1518
WFCCTL_SATISFIED_ID_LIGHT_B=1518
```

This is case B: the wfcctl/WfcStateProbe projection was stale. The old full
current projection was correct.

## Root cause

`WfcStateProbe.java` calls `firstLineContainingAll(connectivityText, ...)` on
the entire ConnectivityService dump. It does not cut the dump at
`mNetworkRequestInfoLogs`. Therefore a released historical row satisfies all
four search terms and is returned as if it were current.

The old full/shadow parser first takes the text before
`mNetworkRequestInfoLogs`; its null result is correct. This was not a regex,
line-wrap, package, capability, or satisfied-ID failure in the old parser.

The earlier observational label remains non-authoritative:
`FROZEN_ONLINE_ACTIVE_CNE_OBSERVED`. After this audit, the precise meaning is
"frozen online state with active CNE *reported by the stale probe*." It has no
write eligibility and is not merged into `FROZEN_SPLIT_RESIDUE`.

## Scoped fix

Only the lightweight current-CNE projection changed. It now performs a small
read-only `dumpsys connectivity`, truncates at `mNetworkRequestInfoLogs`, and
extracts request/satisfied IDs only from the current table. It retains the
wfcctl values as `probeReportedRequestId` and
`probeReportedSatisfiedId` for diagnostics. Missing current/history boundary
is fail-closed.

Neither the recovery algorithm nor the installed phone helper was changed.
The old full parser was not changed because it was correct.

Offline real-format fixtures prove:

- current active request 262 -> request 262 / satisfied 262;
- current null plus historical RELEASE 1518 -> null / null;
- the legacy unbounded scan reproduces stale 1518;
- a missing history boundary is invalid/fail-closed;
- classifier equivalence: 17/17, unsafe promotions: 0.

The active fixture comes from the current table of historical healthy capture
`R3_C1_W_HEALTHY/network.txt`. The null/stale-history fixture is reduced from
the 2026-09-25 21:00 short epoch.

## Recommendation

The parser defect that caused exit 81 is understood and the lightweight
projection is corrected without changing recovery behavior. A new v1 real run
is reasonable only after the updated collector passes its static audit. The
run must still start from its naturally observed state; no classifier should
promote the ONLINE/ONLINE, per_mgr-stopped residue into the split class.
