# R4b provider evidence contract

`PROVIDER_READY` is not a PID-only gate. Every evidence record contains a source, timestamp, raw evidence and pass/fail value. The 120-second gate requires:

- old PID gone and a different audited persistent process PID;
- QNS, IWLAN NetworkService, IWLAN DataService and CneApp hosted by that PID;
- new-PID service-creation, slot-1 provider, static IWlanProxy and IIWlan/slot2 connection evidence;
- new-PID `QualifiedNetworksServiceImpl ... Response Processed` evidence for the constructor's initial `getAllQualifiedNetworks` request;
- live IIWlan cache content classified as A (IMS contains IWLAN), B (IMS empty/UNKNOWN/non-IWLAN), or C (query response/cache incomplete);
- audited constructor ordering as callback-registration evidence. The callback identity is not externally observable and is not fabricated as a direct runtime measurement;
- producer qcrild2 preserved, native IIWlan readiness preserved, no new fatal Binder/HIDL error, and five consecutive two-second stable samples.

Logcat evidence is bounded by the provider restart timestamp and the new PID. Old debug history is never accepted as lifecycle evidence.

