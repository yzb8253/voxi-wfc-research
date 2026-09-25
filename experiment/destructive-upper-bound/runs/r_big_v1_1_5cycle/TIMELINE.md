# R_BIG_V1.1 Five-Cycle Sanitized Timeline

All times are Asia/Shanghai on 2026-09-25. Raw logs remain host-only.

| Time | Event |
|---|---|
| 08:50-08:57 | Exactly one AP reboot completed; environment gate passed and CONTROL_A0 was captured. |
| 08:57-08:58 | Cycle 1 fixed P passed. |
| 08:59:01 | Cycle 1 unchanged v2.6.2 started from pm-service native ownership. |
| 08:59:14-08:59:21 | X55 OFFLINE, holder 19306 created, X55 ONLINE, new PON_SUCCESS. |
| 08:59:47 / 08:59:51 | One SIM OFF / one SIM ON accepted. |
| 09:00:08 | Cycle 1 WFC healthy at approximately 8 seconds; FREEZE retained holder 19306. |
| 09:01:28 | Cycle 2 began; airplane mode returned OFF. |
| 09:01:59 | One exact TERM sent to holder 19306. |
| 09:02:23 | Corrected holder gate passed: owner none, kernel OFFLINE, crash 0, vendor ONLINE telemetry-only. |
| 09:02:25-09:02:28 | Existing sequence started per_mgr; pm-service 24465 entered running/non-owner precondition. |
| 09:02:30-09:02:43 | One qcrild2 restart changed PID 1964 -> 24725. pm-service 24465 became sole owner; kernel/vendor X55 ONLINE, crash 0. |
| 09:03-09:04 | Cycle 2 fixed P passed. |
| 09:04:09 | Cycle 2 unchanged v2.6.2 started from the clean native baseline. |
| 09:04:22-09:04:29 | X55 OFFLINE, holder 27699 created, X55 ONLINE, new PON_SUCCESS. |
| 09:04:55 / 09:04:59 | One SIM OFF / one SIM ON accepted. |
| 09:06:03 | WFC remained unhealthy through 30 seconds. |
| 09:06:06 | CNE freshness classified `NO_CNE_REQUEST`. |
| 09:06-09:08 | Unchanged v2.6.2 failure cleanup could not establish native pm-service ownership and retained holder 27699. |
| 09:09 | Outer runner stopped on v2.6.2 exit 30; final read-only snapshot captured. |

No Cycle 3, 4, or 5 R_BIG_V1.1 action executed.
