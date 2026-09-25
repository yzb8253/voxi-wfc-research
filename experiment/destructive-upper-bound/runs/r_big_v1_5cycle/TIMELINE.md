# R_BIG_V1 Five-Cycle Sanitized Timeline

All times are Asia/Shanghai on 2026-09-25. Raw child logs and logcat remain host-only.

| Time | Event |
|---|---|
| 08:31 | Exactly one AP reboot completed; CONTROL_A0 captured with qcrild 1923, qcrild2 1947, pm-service 1273, native ownership, X55 ONLINE/crash 0, airplane OFF, F1. |
| 08:32-08:33 | Fixed P established; C1_P passed with airplane ON and expected F1. |
| 08:33:31 | The unchanged v2.6.2 recovery started and confirmed the pm-service native baseline. It then stopped per_mgr and observed clean X55 OFFLINE. |
| 08:33:53-08:33:55 | Holder PID 22768 started, became sole `/dev/subsys_esoc0` owner, returned X55 ONLINE, and produced a new PON_SUCCESS. |
| 08:34:20 | Exactly one SIM2 POWER OFF was accepted after the fixed post-PON settle. |
| 08:34:25 | Exactly one SIM2 POWER ON was accepted after the fixed hold. |
| 08:34:48 | Direct health reached REGISTERED/WLAN, VOICE/IWLAN available, and WFC available at approximately 11 seconds. FREEZE skipped cleanup. |
| 08:35:34 | C1_W captured; Cycle 1 classified PASS_FREEZE. |
| 08:35:34 | Cycle 2 began and airplane mode returned OFF. |
| 08:36:01 | C2_MINIMAL_BEFORE captured: holder 22768 sole owner, per_mgr stopped, X55 ONLINE/crash 0, F1. |
| 08:36:05 | Exactly one identity-gated TERM sent to holder 22768. |
| 08:36:52 | Holder exit confirmed; exact stale holder pidfile removed. |
| 08:37:12 | Frozen 20-second native-offline gate expired because vendor X55 remained ONLINE while kernel X55 was OFFLINE. |
| 08:38:03 | Runner surfaced `HOLDER_RELEASE_NATIVE_OFFLINE_FAIL` and stopped without adaptive action. |
| 08:38:27 | C2_STOP_HOLDER_RELEASE_FAIL captured: no holder, no pm-service, no subsys_esoc0 owner, per_mgr stopped, vendor ONLINE, kernel OFFLINE, crash 0, qcrild2 still 1947, F1. |

No Cycle 2 qcrild2 restart, P, v2.6.2, or SIM action occurred. Cycles 3-5 and R_BIG_V1 did not execute.
