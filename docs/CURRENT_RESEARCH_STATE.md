# Project Goal

Develop a repeatable, fail-safe VOXI WFC recovery for Xiaomi 10/cas with Qualcomm SDX55M, with GitHub as the durable evidence source.

# Device / Environment

Windows; Xiaomi 10 (`cas`), Android 13, Magisk; SDX55M. VOXI uses physical slot2 / Android slot index 1 and phoneId 1, commonly subId 11, MCCMNC 23415, carrierId 28. Rediscover ADB serials and PIDs.

# Verified Architecture

Peripheral Manager uses Binder `vendor.qcom.PeripheralManager` / `vendor.qcom.IPeripheralManager`; `vendor.per_mgr` runs `/vendor/bin/pm-service`; `vendor.per_proxy` runs `/vendor/bin/pm-proxy`; external-modem node is `/dev/subsys_esoc0`. `libperipheral_client.so` exports client register, connect, disconnect, unregister, and event acknowledgement. Known loaders include pm-service, pm-proxy, qcrild/qcrild2, GNSS, CNSS, and xtra-daemon.

# Verified Recovery Path

Transferred experiments establish: stop per_mgr -> X55 OFFLINE -> holder opens `/dev/subsys_esoc0` -> X55 ONLINE/new PON_SUCCESS -> one fixed SIM2 OFF, 3-second wait, ON -> WFC HEALTHY. It succeeded in at least two key runs. Raw v2.6.2 artifacts are pending import.

# Verified Peripheral Manager Behavior

In clean native state without a holder, pm-service held the node (typically FD9) and X55 was ONLINE. After per_mgr stop/start, new pm-service PID 13288 reacquired it before qcrild2 restart; X55 was ONLINE. Ownership is not boot-only.

# QCRIL / Peripheral Manager Relationship

Primary RIL is `/vendor/bin/hw/qcrild`; fixed-slot2 RIL is `/vendor/bin/hw/qcrild -c 2`. Transferred logs showed:

```text
PerMgrSrv: SDX55M state: is on-line, add client QCRIL
PerMgrSrv: QCRIL registered
PerMgrLib: QCRIL successfully registered for SDX55M
PerMgrLib: QCRIL voting for SDX55M
PerMgrSrv: QCRIL voting for SDX55M
PerMgrSrv: SDX55M num voters is 2
```

Thus `qcrild2 -> libperipheral_client -> register -> connect/vote -> Peripheral Manager` is verified behavior.

# X55 State Model

- Clean native: pm-service owner, no holder, X55 ONLINE.
- Rebirth: native owner removed, X55 OFFLINE, holder opens node, X55 ONLINE/PON_SUCCESS.
- Contended cleanup: holder owns node while pm-service starts; pm-service cannot acquire.
- Desired handoff: holder exits, owner briefly empty, native client vote prompts pm-service acquisition.

# WFC Recovery Results

X55 rebirth plus one fixed SIM2 cycle restored WFC HEALTHY. qcrild2 restart can cause transient RADIO_NOT_AVAILABLE and DSD/IMS reconstruction. WFC is not an ownership-test success criterion.

# Native Ownership Findings

Clean stop/start reacquisition is verified by transferred evidence. Holder-contended reacquisition is unresolved. Automatic retry after holder release is unknown; a fresh qcrild2 QCRIL vote is the leading trigger hypothesis.

# Current Open Questions

1. Does pm-service automatically reacquire after holder exit?
2. If not, does one qcrild2 restart/vote cause it?
3. Can a smaller official client action trigger the vote?

# Current Best Hypothesis

Starting pm-service while a holder owns the node misses acquisition. After release, a new fixed-slot2 QCRIL vote may cause retry. This remains a hypothesis.

# Latest Ownership Experiment

`X55-OWNERSHIP-HANDOFF-001` passed its direct entry gate and proved that correctly quoted root reads can observe the native owner, X55 state, and crash count under enforcing SELinux. The run stopped before holder-plus-pm-service contention because a PowerShell parameter named `$Pid` collided with the automatic `$PID` variable.

The holder-alone phase succeeded: holder PID 31163 was the sole `/dev/subsys_esoc0` owner and X55 was ONLINE with crash_count 0. Fail-safe cleanup removed the holder and restarted per_mgr, but the final preserved scene is pm-service PID 31818 running with no node owner, X55 OFFLINE, crash_count 0, and qcrild2 unchanged at PID 13706. No qcrild2 re-vote occurred, so the handoff hypothesis remains untested.

# Next Experiments

001B is complete. No additional recovery or process action is automatically authorized; obtain a new explicit decision.

# Safety Constraints

GitHub only; no guessed PID/raw transaction/unverified holder/SELinux bypass; no SIM cycle in this test, physical SIM action, radio/modem reset, unrelated restart ladder, or environment toggle. Every write needs PRE/POST evidence and fail-safe cleanup.

# Follow-up 001B

From the preserved no-owner/X55-OFFLINE scene, the read-only entry gate passed and exactly one fixed-slot2 qcrild2 restart changed PID 13706 to 873. pm-service PID 31818 then became sole FD9 owner and X55 became ONLINE with crash_count 0.

The complete 15-second logcat captured qcrild2/RIL initialization but none of the four required PerMgrLib/PerMgrSrv QCRIL register/vote messages. Therefore native reacquisition is device-confirmed, while the proposed QCRIL re-vote mechanism is not log-confirmed. The predefined result is `QCRILD2_RESTART_NO_VALID_REVOTE`.


# v2.7-alpha Engineering State

001B proved the externally observable native reacquisition result: after one fixed-slot2 qcrild2 restart, the existing pm-service acquired /dev/subsys_esoc0 and X55 returned ONLINE with crash_count 0. The exact QCRIL re-vote mechanism was not directly logged and remains unproven.

A new, non-replacing v2.7-alpha implementation now orders recovery as native owner -> controlled holder rebirth -> start per_mgr under contention -> release holder -> one qcrild2 restart -> native reacquire -> WFC check -> optional one fixed SIM2 cycle. Native reacquire failure forbids SIM power. Healthy WFC skips SIM power. No retry exists.

Build status: PowerShell syntax PASS, Android shell syntax PASS, static safety audit PASS, phone execution NOT RUN, phone writes 0.

The first authorized device launch was attempted from Computer B at commit `1949b6f90572e2b7eee60963cab8b18fc6b07591`. The independent read-only entry gate passed, but the paired `.cmd` launcher selected Windows PowerShell 5.1 and the script failed before its first ADB call because `ProcessStartInfo.ArgumentList` is unavailable in that runtime.

Result: `BLOCKED_PRE_WRITE_PS51_INCOMPATIBILITY`; phone writes 0. No holder, ownership transition, qcrild2 restart, or SIM cycle occurred. Post-check state remained pm-service PID 31818 sole FD9 owner, qcrild2 PID 873, X55 ONLINE, crash_count 0, and WFC F1.

Windows PowerShell 5.1 compatibility is now statically repaired and accepted: version 5.1.19041.6456, parser errors 0, exact launcher self-test PASS, Windows argv/holder payload round-trip PASS, and full static safety audit PASS. The phone state machine and safety logic are unchanged; phone writes during the repair were 0.

Next action: stop and obtain fresh authorization before another real execution. Do not treat the failed host launch as a native-handoff result and do not automatically rerun the repaired script.
