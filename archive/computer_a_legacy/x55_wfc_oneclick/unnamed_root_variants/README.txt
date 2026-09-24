X55 + VOXI WFC One-Click Recovery v2.5

Validated target
- Xiaomi Mi 10 Ultra (cas)
- Android 13 / V816.0.4.0.TJJCNXM
- Qualcomm SDX55M
- Magisk root
- VOXI slot 1 / phoneId 1 / subId 11

v2.5 flow
1. Controlled X55 OFF/ON
2. Confirm NEW PON_SUCCESS
3. Wait 10 seconds
4. Record baseline qti.cne registered/active/request/satisfied
5. Perform ONE software SIM2 cycle:
   OFF -> 3s -> ON -> 2s -> ON again
6. Poll WFC up to 30 seconds

If WFC is still unhealthy:
7. Record qti.cne again
8. Classify request freshness:
   - STALE_CNE_REQUEST
   - NEW_CNE_REQUEST
   - NO_CNE_REQUEST
9. ALWAYS restart vendor.cnd once
   - registered=YES is not trusted by itself
   - a prior request ID can be stale
10. Poll WFC up to 30 seconds
11. Record post-cnd request freshness

If still unhealthy:
12. Stop automatic recovery
13. Do NOT restart .qtidataservices
14. Do NOT perform a second software SIM cycle
15. Fallback to physical VOXI SIM reinsertion

Important v2.5 changes
- Removed .qtidataservices restart completely.
- vendor.cnd restart now runs after every failed first SIM cycle, regardless of qti.cne YES/NO.
- CNE request/satisfied IDs are logged before SIM cycle, after SIM cycle, and after vendor.cnd restart.
- Stale request detection added.
- Windows PowerShell 5.1 ProcessStartInfo ADB execution from v2.4.2 retained.
