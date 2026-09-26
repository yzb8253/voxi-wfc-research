# Research History

## Phase 1 — State and safe recovery

The project established direct WFC health, strict F1/F8 classifications, fixed VOXI mapping and bounded UICC recovery. It discovered that broad connectivity dumps contain historical request records and therefore cannot be naively parsed as current state.

## Phase 2 — Failure preservation and layer isolation

Preserved Active+Enabled F1 scenes showed UICC, CarrierConfig, ImsResolver and MMTEL could recover while Qualcomm IMS/CNE failed to create a new IMS request. Scoped IMS, CNE, userspace and framework restarts were tested and documented.

## Phase 3 — Native/modem boundary

RIL-pair recovery restored native services without proving WFC recovery. Standard modem SSR interfaces were investigated but no verified safe trigger was available, so guessed writes were rejected.

## Phase 4 — SIM lifecycle and QNS

Single-SIM slot mapping, SIM power experiments and UICC false/F8/true behavior were studied. Successful traces narrowed the critical path to QNS/IWLAN qualification, CNE demand, IMS NetworkAgent and ePDG.

## Phase 5 — X55 native handoff

Controlled ownership handoff around `/dev/subsys_esoc0`, `pm-service`, holders and qcrild2 produced a repeatable Golden path. The stable wrapper was validated in a 6/6 series and anchored at commit `dfd8241`.

## Phase 6 — Reset-boundary falsification

R3/R4 experiments separated native-ready gates from framework canonicality, reconstructed provider/consumer epochs and rejected several too-small reset boundaries. Failures were kept as falsification evidence rather than patched during a series.

## Phase 7 — Latency and observability

Profiling found that large read-only snapshots can perturb asynchronous timing. Lightweight classifiers and current-table CNE parsing reduced observation overhead. FAST-holder work identified foreground sleep as a release-latency cause, but not as a WFC-success determinant.

## Current phase

Current work compares exact UICC transaction/observer behavior and seeks a minimal deterministic CNE regeneration boundary while preserving Golden provenance and publication safety.
