# R4b three-cycle v1 result

## Classification

`R4B_SERIES_ABORTED_PROVIDER_ADAPTER_PS51_SCALAR_COUNT`

This is not `R4B_FALSIFIED`. Cycle 1 did not reach `PROVIDER_READY`, R3, A, P or the frozen v2.6.2. The series stopped immediately and no second provider reset or continuation was attempted.

## Baseline

- Starting commit: `bf4ac6d85d017ac6021cb34af8d2b34bb822677e`.
- `CONTROL_A0_R4B_V1`: PASS after the one authorized reboot.
- Initial qcrild/qcrild2/qtidataservices/phone/pm-service: `1940 / 1980 / 3366 / 3460 / 1305`.
- pm-service sole owner, X55 ONLINE, crash_count 0, terrestrial LTE, IWLAN preferred false, VOXI active/UICC enabled, F1.

## Cycle 1 completed stages

- R0_NATIVE_READY: PASS, no write.
- Producer reset: exactly one `ctl.restart vendor.qcrild2`, PID `1980 -> 14590`.
- PRODUCER_READY: PASS with fresh DataModule/NAH, DSD/WDS, modem capability, IWLAN and five stable samples.
- Provider primitive: exactly one TERM to fully audited `.qtidataservices` PID `3366`; ActivityManager recreated it as PID `23798`.

Immediately after the write, the evidence adapter evaluated `.Count` on a scalar string returned by `New-PidLine`. Windows PowerShell 5.1 with strict mode raised `PropertyNotFoundStrict`. This was a host/orchestrator defect, not a provider lifecycle verdict.

## Read-only frozen post-abort observation

- New PID 23798 is the expected UID 10104 persistent process with the audited SELinux domain and package group.
- ActivityManager hosts QualifiedNetworksServiceImpl, IWlanDataService, IWlanNetworkService and CneApp in PID 23798.
- New-PID logcat shows process recreation and generic NetworkService/QNS/DataService creation at 21:14:31.842-31.848.
- No slot1 provider creation, static IWlanProxy connection, or `QualifiedNetworksServiceImpl ... Response Processed` line was observed in the retained post-abort log.
- Live native producer cache remained ready and included `IMS networks=[EUTRAN,IWLAN]` from the current producer epoch. This is not a completed provider initial-query result.
- Final read-only snapshot: airplane OFF, qcrild2 14590, pm-service 1305 sole owner, X55 ONLINE, crash_count 0, IMS NOT_REGISTERED/UNKNOWN, F1.

Provider initial cache query classification: `C_QUERY_INCOMPLETE / NOT_OBSERVED`. Because the adapter had exited, this is post-abort observation and not a formal `PROVIDER_READY_TIMEOUT` verdict.

## Stages not run

- qtidataservices second TERM: 0.
- com.android.phone R3: 0; phone PID stayed 3460.
- A_READY: NOT RUN.
- fixed P: NOT RUN.
- v2.6.2: NOT RUN.
- SIM OFF/ON: `0 / 0`.
- M1-M7: NOT RUN.
- Cycles 2 and 3: NOT RUN.

H3/R4b status: `NOT_TESTED_TO_FALSIFICATION_POINT`.

The PS5.1 scalar handling is corrected offline by array-wrapping every `New-PidLine` result. The corrected code was statically audited only and was not rerun on the phone.
