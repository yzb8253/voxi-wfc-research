# Phase 8A QCOM IMS Process Restart Result

## Verdict

`QCOM_IMS_RESTART_RECOVERY = FAIL`

Restarting only `org.codeaurora.ims` successfully rebuilt the Qualcomm IMS service and both slots' MMTEL feature connections, but it did not recreate the missing CNE IMS demand. VOXI remained strict F1 through the exact 180-second sample and a final 195.7-second sample.

## Safety Gate

- Device: Xiaomi 14 Pro, serial `fd0ff892`, ADB `192.168.137.211:41111`.
- VOXI: subId11, slot1, phoneId1, carrierId28, MCCMNC23415, ACTIVE, UICC apps ENABLED.
- China Telecom: subId1, slot0, carrierId2237, MCCMNC46011.
- Initial state: IMS NOT_REGISTERED(0), transport UNKNOWN(-1), VOICE/IWLAN false, WFC false, qti.cne request absent, UDP/4500 absent, XFRM absent, MMTEL READY.
- Target process: exactly `org.codeaurora.ims`, PID 3184, UID 10196, SELinux `u:r:vendor_qtelephony:s0:c196,c256,c512,c768`.
- Process separation: target was distinct from `com.android.phone`, `.dataservices`, and `.qtidataservices`.
- Network environment stayed unchanged: wlan0 `192.168.137.211/24` and tun0 `172.19.0.1/30` remained UP.

## Execution

- The first command attempt stopped at its cmdline verification with rc=82; it exited before `kill`, so it performed no write.
- The corrected immediate gate revalidated F1, both SIM identities, PID, raw cmdline prefix, UID, and SELinux domain.
- Actual restart method: exactly one `kill -TERM 3184`.
- Kill time: 2026-09-18 09:08:07 +08:00.
- Kill return: 0.
- No SIGKILL, killall, pkill, force-stop, resetIms, UICC false/true, CNE restart, radio operation, or network-setting change was performed.

## Lifecycle Timeline

- 09:08:07.364: ImsResolver removed slot1 MMTEL controller.
- 09:08:07.368: old PID 3184 reported dead.
- 09:08:07.380-07.383: slot0 MMTEL/emergency and slot1 emergency controllers removed.
- 09:08:07.392: persistent process restart created PID 23125, 24 ms after process death.
- 09:08:07.395-07.396: slot1 and slot0 MMTEL callbacks reported DISCONNECTED.
- 09:08:07.426: PID 23125 reported bound, 58 ms after death.
- 09:08:09.552-09.555: ImsResolver put both slots' MMTEL/emergency controllers and slot1 feature connectors were recreated.
- 09:08:09.612: slot0 MMTEL connectionReady.
- 09:08:09.615: slot1 MMTEL connectionReady.
- 09:08:09.880: slot1 remained unregistered with `General_Error17-Unable to connect`.
- 09:08:11.388-11.405: repeated slot1 unregistered state; PS/WLAN remained HOME and IWLAN preferred.
- 51.5, 60, 90, 120, 180, and 195.7 seconds: direct probe remained F1 with no qti.cne request, UDP/4500, or XFRM.

## Requested Result

```text
=== PHASE 8A QCOM IMS PROCESS RESTART ===

Target process:
org.codeaurora.ims (UID 10196, vendor_qtelephony)

Old PID:
3184

Restart method:
kill -TERM 3184, exactly once

New PID:
23125

Process restart:
PASS

ImsService rebind:
YES, process bound in 58 ms; ImsResolver controller/features restored in about 2.19 seconds

slot1 ImsServiceSub rebuilt:
YES, slot1 FeatureConnector/MMTEL objects recreated and connectionReady at 09:08:09.615

New cnd/CNE IMS trigger:
UNKNOWN at the native callback boundary; no observable downstream requestNetwork event

New qti.cne IMS request:
NO

ePDG/XFRM:
MISSING / MISSING

IMS:
NOT_REGISTERED (0)

Transport:
UNKNOWN (-1)

VOICE/IWLAN:
UNAVAILABLE

WFC:
UNAVAILABLE

slot0 transient impact:
MMTEL service connection was DISCONNECTED for about 2.216 seconds, then connectionReady. Both slots are hosted by this process. Active VoLTE registration was not established in the pre-state under airplane mode, so a separate VoLTE deregistration duration cannot be claimed.

slot0 final state:
subId1/slot0/carrierId2237/MCCMNC46011 intact; MMTEL listener READY; safety gate PASS

Recovery time:
N/A; no recovery through 180 seconds (still F1 at 195.7 seconds)

QCOM_IMS_RESTART_RECOVERY:
FAIL
```

## Interpretation

The process restart is sufficient to rebuild `org.codeaurora.ims`, ImsResolver bindings, ImsServiceSub/feature objects, and MMTEL readiness. It is not sufficient to recreate the missing upstream cnd/CNE IMS demand. This cleanly separates IMS service lifecycle recovery from CNE network-demand recovery and strengthens the Phase 7 causal hypothesis.

Per the stop rule, Candidate B is only the next research candidate: `qti.cne/qtidataservices restart`. It was not executed.
