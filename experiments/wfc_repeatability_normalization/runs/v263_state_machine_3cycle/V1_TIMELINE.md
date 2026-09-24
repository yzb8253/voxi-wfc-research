# V1 timeline

Date: 2026-09-24, Asia/Shanghai

- 16:35:35: resumed Cycle 1; expected-nonzero boundary self-test passed with exit 23.
- 16:35:53: `V1_A_RAW` confirmed the preserved qcrild2 fallback precondition.
- 16:36:45: exact holder 31050 release and one qcrild2 restart completed; qcrild2 changed 27223 -> 16258; pm-service 11529 became sole owner; X55 ONLINE/crash zero.
- 16:37:45: canonical A snapshot started after the fixed sixty-second settle.
- 16:38:07: `V1_A_NORMALIZED` passed; airplane mode enabled.
- 16:38:10: Wi-Fi enable issued; canonical P settle began.
- 16:39:11: `V1_P_RAW` capture started.
- 16:39:33: P passed on first check; hash-locked v2.6.2 recovery started.
- Recovery: per_mgr stopped; clean X55 OFFLINE; holder 19581 created; X55 ONLINE/crash zero; new PON_SUCCESS; ten-second settle completed.
- Recovery: X55-only health remained false; exactly one SIM2 OFF/ON cycle ran with a three-second OFF hold.
- Recovery: ten health checks through elapsed thirty seconds remained unhealthy; no current qti.cne request appeared.
- Recovery failure cleanup: per_mgr start and one restart did not obtain native ownership; holder was preserved.
- 16:43:39: recovery returned exit 30 (`AUTO_RECOVERY_FAILED`).
- 16:44:03: `V1_FAILURE` captured; driver stopped. Cycles 2 and 3 did not start.

The recovery child buffered its console output until exit, so individual internal events are ordered by the script's own elapsed counters rather than host receipt timestamps.
