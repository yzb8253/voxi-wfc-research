# WfcStateProbe Rules v1.1 Candidate

## Core Health

`directWfcHealthy` and `goldenStrong` require exactly:

```text
registrationStateRaw == 2
AND registrationTransportRaw == 2
AND voiceIwlanAvailable == true
AND wifiCallingAvailable == true
```

## Supporting Evidence

These fields remain valuable but do not veto direct health:

- Dedicated IMS IWLAN NetworkAgent and IMS network ID.
- qti.cne IMS request registration and satisfaction.
- UDP/4500 keepalive.
- XFRM/IPsec state and policy.
- PS/WLAN HOME and IWLAN preferred.
- MMTEL READY.
- User-visible WFC icon.

## qti.cne Parsing

- `qtiCneRequestRegistered`: matching request line exists.
- `qtiCneRequestActive`: `activeRequest` contains a numeric ID, not `null`.
- `qtiCneRequestId`: parse `NetworkRequest [ REQUEST id=...]` even when unsatisfied.
- `qtiCneSatisfiedRequestId`: numeric `activeRequest` value or null.

## Failure Classes

- F0: four direct health conditions pass.
- F1-F5: retain direct IMS/transport/capability/WFC failures.
- F6: direct health is false and IMS demand/NetworkAgent evidence is missing.
- Missing NetworkAgent with direct health true: F0 with reduced supporting evidence, not F6.

The local candidate JAR was built but not pushed or installed:

- `probe_v1_1_candidate/wfc-state-probe-v1.1-candidate.jar`
- SHA-256: `6B0517DF5EC0143DD290BFAF51BC46AB30246343BD359EAE3A46A683808D4CB0`
