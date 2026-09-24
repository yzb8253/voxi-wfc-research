X55 + VOXI WFC One-Click Recovery v2.4.1

This is a clean rebuild from the known-working v2.3 script.

Flow
1. Controlled X55 OFF/ON
2. Confirm NEW PON_SUCCESS
3. Wait 10 seconds
4. ONE software SIM2 cycle:
   OFF -> 3s -> ON -> 2s -> ON again
5. Poll WFC for up to 30 seconds

If still unhealthy:
6. Read qti.cne state
7. If qti.cne registered=NO:
   restart vendor.cnd once
   then poll WFC for up to 30 seconds
8. If still unhealthy:
   send SIGTERM once to persistent .qtidataservices
   wait for Android to respawn it
   then poll WFC for up to 30 seconds
9. If still unhealthy:
   stop automatic recovery and use physical SIM reinsertion

v2.4.1 fixes
- Rebuilt from v2.3 instead of patching the broken v2.4 file.
- Restored the original outer try/catch/finally structure.
- Restored the SIM POWER-ON recovery guard.
- Removed invalid Get-WfcHealth calls.
- Removed the second automatic SIM cycle.
- Added vendor.cnd and .qtidataservices recovery stages.

Static validation
- Required main catch/finally blocks present
- Balanced {}, (), []
- No stale second SIM cycle
- No Get-WfcHealth reference
- No reserved $PID collision
