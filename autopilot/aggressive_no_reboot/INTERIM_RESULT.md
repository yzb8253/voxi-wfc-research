# Aggressive No-Reboot Recovery Search - Interim Result

## State

- Controlled F1 creation: PASS on cycle 1.
- Exactly one fixed `false,11` was followed by persistent F8 confirmation at 2/5/10 seconds.
- Exactly one fixed `true,11` restored ACTIVE/ENABLED mapping but remained strict F1 through 120 seconds.
- China Telecom slot0 remained correctly mapped throughout.

## Candidate results

- C1 `imsdatadaemon`: FAIL. PID 1949 -> 28722; no new IMS demand, CNE request, ePDG, registration, or WFC in 60 seconds.
- C2 `imsqmidaemon`: FAIL. PID 1805 -> 31349; no recovery signal in 60 seconds.
- C3 native IMS pair: NOT_RUN. C1 and C2 had already restarted both members in this experiment stage; immediate repeat TERM was prohibited.
- C4 `org.codeaurora.ims`: FAIL. PID 3313 -> 2449; no recovery signal in 60 seconds.
- C5 `vendor.cnd`: FAIL. PID 1797 -> 6825; PS/WLAN changed from residual HOME/true to UNKNOWN/false, with no IMS demand or WFC recovery.
- C6 `.qtidataservices`: FAIL. PID 3298 -> 10140; hosted CneApp/IWLAN services restarted, but no IMS demand or WFC recovery.
- C7 `com.android.phone`: NOT_RUN. The host safety reviewer rejected the exact TERM before execution and requires renewed explicit approval after disclosure of dual-SIM telephony framework impact.
- Full soft stack: NOT_RUN.

## Current preserved scene

ACTIVE + UICC ENABLED + strict F1; IMS NOT_REGISTERED, transport UNKNOWN, VOICE/IWLAN unavailable, WFC unavailable, no qti.cne IMS request, no UDP/4500. wlan0 and tun0 remained up. slot0 identity remained protected.

No modem reset, SSR, qcrild restart, radio power cycle, airplane toggle, reboot, SIGKILL, killall, pkill, or extra UICC write was executed.