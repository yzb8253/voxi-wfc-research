# R3_READY specification

`R3_READY` is a state predicate, not a sleep. The maximum wait is 120 seconds from the one exact TERM. A candidate state must remain true for five consecutive one-second samples after all creation markers have appeared.

## Required identity and creation gates

1. Exactly one main-user process matches UID 1001, SELinux `u:r:radio:s0`, name and argv `com.android.phone`.
2. New PID differs from old PID and its ActivityManager record is `*PERS*`, `persistent=true`, `removed=false`.
3. The new PID's post-TERM logs contain all of:
   - PhoneFactory creates phone 0;
   - PhoneFactory creates phone 1;
   - ANM-1 AP-assisted creation/bind;
   - slot1 QtiServiceStateTracker creation;
   - NRM-I-1 registration and IWlanNetworkService connection;
   - DNC-1 creation and WLAN DataService binding;
   - slot1 CarrierConfig reaches LOADED/current subscription update;
   - slot1 MMTEL reaches `connectionReady 11` / READY.

These logs prove new object construction. A steady-state dump from before process death cannot satisfy the gate.

## Required stable-state gates

- VOXI mapping is exactly subId 11 / slotId 1 / phoneId 1 / carrierId 28 / MCCMNC 23415.
- subscription is active and UICC applications are enabled.
- airplane mode is OFF.
- Wi-Fi/wlan0 is ready, VPN NetworkAgent/tun environment is present, location is enabled, and Anywhere mock-provider evidence is present.
- primary qcrild and qcrild2 retain their pre-R3 PIDs, exact argv, PPID 1 and running init states.
- `.qtidataservices` and `org.codeaurora.ims` retain their pre-R3 PIDs.
- vendor.per_mgr is running; native pm-service is the sole `/dev/subsys_esoc0` owner; X55 is ONLINE; crash_count is 0; no holder or holder PID file exists.
- CarrierConfig and MMTEL are current for subId 11.
- module lock is absent.

## Observable versus unobservable

| Item | Status | Evidence |
|---|---|---|
| New Phone[0]/Phone[1] | OBSERVABLE | fresh-PID PhoneFactory log markers |
| New ANM-1 | OBSERVABLE | fresh-PID constructor/bind log |
| New NRM-I-1 | OBSERVABLE | fresh-PID registration and service-connected logs |
| New QtiSST-1 | OBSERVABLE | fresh-PID creation log |
| New DNC-1 | OBSERVABLE | fresh-PID constructor and binding logs |
| Internal object identity/address | UNOBSERVABLE | no safe production API exposes Java object identity |
| Every pending Handler message cleared | UNOBSERVABLE directly | inferred from process death, not asserted as an individual PASS |
| CarrierConfig listener object identity | UNOBSERVABLE | readiness uses fresh process plus post-death slot1 config event |
| IMS feature binder object identity | Partially observable | fresh phone-process binding/connection logs; vendor binder internals remain opaque |

Unobservable fields are never fabricated as PASS. They are either structurally guaranteed by process death or left explicitly unobservable.

## Timeout and invalidation

- Maximum: 120 seconds.
- Any missing required marker or stable gate at timeout: `R3_READY_TIMEOUT` and fail closed.
- Any qcrild, qcrild2, qtidataservices, Qualcomm IMS, X55, PM owner or crash-count change: `R3_SCOPE_VIOLATION` and fail closed.
- No retry of TERM and no fallback restart.
