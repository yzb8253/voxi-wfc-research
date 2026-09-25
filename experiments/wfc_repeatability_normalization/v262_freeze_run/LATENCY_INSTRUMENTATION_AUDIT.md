# Latency instrumentation audit

Date: 2026-09-25  
Branch: `wfc-latency-study-20260925`  
Golden ancestor: `253ab93a2127806837cb472071846f568c811a34`

## Scope

This checkpoint adds wall-clock observation only. It does not reduce or move any wait, change a gate, add a phone mutation, change a target identifier, or change a success/failure predicate.

Machine-readable records use:

```text
TIMING name=<stage> ms=<elapsed-milliseconds>
```

Instrumentation covers:

- wrapper syntax and platform/target safety gates;
- Wi-Fi readiness, A settle, airplane transition, and P settle;
- initial and normalized preflight snapshots plus every major snapshot collection command;
- native fingerprint classification and the quick native-owner probe;
- holder TERM, owner-NONE/X55-OFFLINE, qcrild2 PID change, and pm-service/X55 reacquire;
- WFC and CNE probes;
- v2.6.2 preconditions, X55 OFFLINE, holder-to-ONLINE, PON_SUCCESS, fixed 10-second settle, X55-only health checks, SIM OFF request, fixed three-second OFF hold, SIM ON request, and SIM-ON-to-health result;
- v2.6.2 total and wrapper total.

## Frozen behavior

The following remain unchanged:

- A settle: 20 seconds;
- P settle: 20 seconds;
- post-PON settle: 10 seconds;
- SIM OFF hold: 3 seconds;
- post-SIM health window: 30 seconds with existing early exit;
- maximum normal attempts: 2;
- exact slot1/subId11 targeting and protected slot0 policy;
- frozen-holder success behavior;
- UICC deep-fallback trigger and bounds;
- native-owner safety fingerprint and qcrild2 fallback;
- all process/service mutation commands and their order.

## Static validation

- Windows PowerShell version: 5.1.19041.6456
- Parser errors in all five changed PowerShell files: 0
- `git diff --check`: PASS
- Phone writes during instrumentation development: 0

Real-device profiling must use this instrumentation checkpoint without further behavior edits.
