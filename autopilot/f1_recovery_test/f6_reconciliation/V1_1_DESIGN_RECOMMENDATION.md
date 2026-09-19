# VOXI WFC Recovery v1.1 Design Recommendation

## Preserve Safe Recover

The existing default Action and `recover` command remain unchanged in scope:

- Healthy: zero write.
- Inactive/apps disabled plus full historical identity and slot0 gate: one fixed true call.
- Active but unhealthy: zero write.

## Add Explicit Deep Recover

Provide a separate manual `deep-recover` command. Do not invoke it automatically from the Magisk Action default path.

Preconditions:

- Full VOXI and China Telecom dual-SIM safety gate PASS.
- VOXI subscription ACTIVE and UICC apps ENABLED.
- Direct WFC health false.
- Failure class exactly F1, or a separately confirmed equivalent with IMS/ePDG absent.
- Explicit user confirmation and exclusive recovery lock.

Sequence:

1. Capture diagnostics.
2. Execute one fixed false call.
3. Require persistent inactive/F8 evidence.
4. Execute one fixed true call.
5. Wait for direct WFC health using the four v1.1 core conditions.
6. Observe stability; record NetworkAgent/qti.cne/UDP4500/XFRM only as supporting diagnostics.
7. Never retry false or true automatically and never fall through to resetIms.

The present experiment is one successful real F1 recovery. Deep Recover should initially be labeled manual/experimental rather than becoming the default automatic path.
