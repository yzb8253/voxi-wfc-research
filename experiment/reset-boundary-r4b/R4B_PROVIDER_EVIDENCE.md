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

## v2 observation extension

The reset and readiness semantics are unchanged. Observation now records T1-T10 separately and classifies the initial query as `QUERY_NOT_SENT`, `QUERY_SENT_NO_RESPONSE`, `QUERY_RESPONSE_EMPTY`, or `QUERY_RESPONSE_VALID`. Request and response serials and the IMS network list are separate fields. A missing log is `UNOBSERVABLE`; it is never converted into runtime proof.

The current-ROM implementation order is `getAllQualifiedNetworks()` followed by `registerForQualifiedNetworksChanged()`. The slot-level process-static `IWlanProxy` owns service/proxy state, pending requests, registrants, cookies and production response/indication objects. These facts support the reset boundary but do not prove a particular runtime payload.

User-supplied external MinQns evidence is retained only as corroboration that first-publication/replay races are a real problem class. Periodic re-report, forced IMS-to-IWLAN publication, callback injection and provider replacement remain explicitly forbidden and are absent from this implementation.
