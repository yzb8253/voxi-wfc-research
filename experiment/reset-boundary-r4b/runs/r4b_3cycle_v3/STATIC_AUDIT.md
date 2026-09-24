# R4b three-cycle v3 static audit

Date: 2026-09-24

## Scope

This independent series changes only readiness evidence. The frozen reset and recovery sequence remains:

`R0 -> one qcrild2 cold epoch -> one qtidataservices exact-PID TERM -> one exact R3 phone TERM -> fixed P -> hash-locked v2.6.2`.

The new gates are:

- `NATIVE_PUBLICATION_READY`: latest post-provider NAH generation only; live working IMS/EUTRAN and live LastReported IMS/EUTRAN; ten stable samples; producer/provider PIDs and native PM/X55 state unchanged.
- `POST_R3_QUERY_READY`: no NAH constructor change across R3; natural fresh-provider GET serial newer than R3; matched non-empty response containing IMS/network content; normal QNS processing.

No diagnostic GET is injected. No timeout, reset primitive, P transition, SIM budget, recovery hash or health predicate changed.

## Static result

- Windows PowerShell 5.1 parse: PASS
- Gate order: PASS
- Exact qtidataservices TERM sites: 1
- qcrild2 restart ceiling: unchanged, 1/cycle
- phone TERM ceiling: unchanged, 1/cycle
- frozen v2.6.2 SHA-256: `445752BB49FB487850D0B1A1EFF4F0AA29D58C363C3A86E75BAA841E4CC08F75`
- readiness scripts contain no phone-write function/path: PASS
- active GET injection: NO
- stale LocalLog generation accepted: NO
- fail closed on `NATIVE_PUBLICATION_NOT_READY`: YES
- fail closed on `NAH_GENERATION_CHANGED_DURING_R3`: YES
- fail closed on `CURRENT_GENERATION_QUERY_CONTRADICTION`: YES
- static-phase phone writes: 0

## Execution contract

One new reboot baseline is authorized. Cycles 1-3 have no reboot between them. The series stops at the first terminal gate, P, recovery or health failure without adaptive action.
