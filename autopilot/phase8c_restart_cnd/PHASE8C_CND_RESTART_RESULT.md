# Phase 8C Native CND Restart Result

## Scope and Safety

- Test time: 2026-09-18 10:05:29 +08:00
- Authorized write: exactly one `kill -TERM 1838`
- Write result: return code 0; no SIGKILL or other state-changing command was used.
- Target proof: init service `vendor.cnd`, `/system/vendor/bin/cnd`, PPID 1, UID 1000, SELinux `u:r:vendor_cnd:s0`, definition `/vendor/etc/init/cnd.rc`.
- Exclusions confirmed: the target was not qcrild, a modem daemon, SSR, or the radio stack.
- Pre-write gates: strict F1, VOXI subId 11/slot 1/phoneId 1/carrierId 28/MCCMNC 23415, and China Telecom subId 1/slot 0/MCCMNC 46011 all passed.
- Environment before the write: wlan0 `192.168.137.211/24`, tun0 `172.19.0.1/30`, airplane mode on, FlClash PID 5080.

## Process Restart

- Old PID: 1838
- New PID: 909
- The first new-process evidence is at 10:05:29.431, effectively immediate after the TERM.
- PID 909 remained running through the 120-second observation.
- A SELinux denial was logged for new `cnd` access to the vendor diag character device. This is recorded as evidence, but it does not prove the recovery failure because the denied diag access may be diagnostic-only.

## Recovery Chain

- CNE HIDL/callback reconnect: no observable `NativeHalServerCallback` or equivalent replay.
- New qti.cne IMS request: absent through 120 seconds.
- TelephonyNetworkFactory/DNC slot1 demand: no new IMS request was delivered.
- UDP/4500 NAT-T: absent.
- XFRM/ePDG: absent.
- IMS: `NOT_REGISTERED (0)`.
- Registration transport: `UNKNOWN (-1)`.
- VOICE over IWLAN: unavailable.
- WFC availability: false.

At 10:05:30.458-10:05:30.487, slot1 PS/WLAN changed from IWLAN/HOME to UNKNOWN and `mIsIwlanPreferred` changed from true to false. DNC-1 explicitly logged that evaluating network requests was not needed. The final probe retained UNKNOWN IWLAN state, so the restart removed the residual IWLAN registration indication without regenerating IMS demand.

## Protected State

- China Telecom final identity gate: PASS; subId 1 remained active and mapped to slot 0.
- The log contains ordinary slot0 IMS/WFC false notifications around the restart, but no slot0 subscription remap or identity loss. Final slot0 impact: no mapping impact confirmed.
- wlan0, tun0, their addresses, airplane mode, and the FlClash process remained unchanged.

## Conclusion

`vendor.cnd` restarted successfully, but native CNE demand was not replayed. No new IMS request, ePDG/XFRM path, or direct IMS/WFC health appeared within 120 seconds. The preserved state is strict F1, now also with slot1 IWLAN UNKNOWN.

`CND_RESTART_RECOVERY = FAIL`

No additional recovery or broader write was executed.
