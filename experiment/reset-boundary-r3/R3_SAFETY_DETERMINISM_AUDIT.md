# R3 safety and determinism audit

Date: 2026-09-24 (Asia/Shanghai)

Baseline commit: `10284e6a69e1ee6084662c8d2340d64b323295ca`

Scope: static repository review plus read-only ADB inspection of the current Xiaomi ROM. No process signal, service restart, setting change, SIM action, airplane-mode change, or reboot was performed. `PHONE_WRITES=0`.

## Audit verdict

| Gate | Result | Basis |
|---|---|---|
| `R3_METHOD_SAFE` | **PASS_FOR_CONTROLLED_EXPERIMENT** | Exact main-user process identity is distinguishable from the user-999 process; one exact-PID `SIGTERM` is already proven on this ROM; no package stopped-state is introduced. |
| `R3_AUTO_RECREATE_CONFIRMED` | **PASS** | Current ActivityManager record is `*PERS*`, package flags include `PERSISTENT`, and the previous same-ROM C7 experiment measured a new main process 27 ms after death and binding 85 ms after death. |
| `R3_READY_GATE_DEFINED` | **PASS** | PID identity, fresh object-creation log markers, subscription/UICC, bindings, vendor PID stability, environment and native ownership all have fail-closed predicates below. |
| Current scene ready to execute R3 | **NO** | Airplane mode is ON and an old shell holder owns `/dev/subsys_esoc0`. This is expected pre-baseline residue, not an audit failure. The authorized one-time reboot must create CONTROL_A0 first. |

These PASS results authorize only the already requested controlled R3 experiment design. They do not establish R3 as a repair.

## Current-ROM process identity

Read-only current observations:

- Main telephony process: PID 3225, UID 1001 (`radio`), PPID 921 (zygote), name and argv `com.android.phone`, SELinux `u:r:radio:s0`.
- A second `com.android.phone` PID 13737 belongs to user 999 (`u999_radio` / UID 99901001). It must never be selected by name alone.
- ActivityManager describes the main process as `*PERS* UID 1001`, class `com.android.phone.PhoneApp`, `persistent=true`, package code `/system/priv-app/TeleService/TeleService.apk`.
- Its ProcessRecord hosts a shared package list including TeleService, TelephonyProvider, STK, ONS and CellBroadcastService components. R3 is therefore wider than one APK service.
- Package flags include `SYSTEM`, `PERSISTENT` and `KILL_AFTER_RESTORE`; user 0 currently has `stopped=false`, `enabled=0` (default enabled state).
- No independent init rc service for `com.android.phone` was found. ActivityManager starts and supervises the persistent application process through zygote.

Current vendor/native identities observed read-only:

- primary qcrild PID 1958; target `qcrild -c 2` PID 16258; both PPID 1 and `u:r:rild:s0`.
- `.qtidataservices` PID 3175, UID 10104, `u:r:vendor_qtidataservices_app:...`.
- `vendor.per_mgr=running`, X55 `ONLINE`, crash_count 0.
- The current `/dev/subsys_esoc0` owner is old shell holder PID 19581, not native pm-service. The formal run must not normalize this ad hoc; the one authorized baseline reboot clears it.

## Candidate action comparison

### Selected: exact main-user PID `SIGTERM`

Definition:

1. Resolve exactly one row with UID 1001, SELinux `u:r:radio:s0`, process name and argv exactly `com.android.phone`.
2. Confirm its ActivityManager record is the main `*PERS*` process and that user-0 package state is not stopped.
3. Send exactly one `kill -TERM <resolved-pid>`.
4. Never select the user-999 process, use a name-wide signal, retry a signal, or escalate to SIGKILL.

Why this is the minimum deterministic method on this ROM:

- The same exact method already produced process death and automatic persistent-process recreation on this ROM.
- It destroys the process and all Phone-owned Java objects without changing package stopped state.
- It does not request radio, RIL, QNS/IWLAN, IMS vendor, system_server or native X55 restart.

### Rejected: `am force-stop com.android.phone`

Force-stop has package stopped-state semantics. It can suppress normal component launches until an explicit package start and changes more state than process death. It is not equivalent to a lifecycle restart and would make automatic recreation non-deterministic. It is prohibited for R3.

### Rejected: `am kill com.android.phone`

The main process is persistent with a very low OOM adjustment. `am kill` is intended for killable/background processes and does not give a reliable promise that this persistent process will die. An ambiguous no-op is unsuitable for a falsifiable reset boundary.

### Rejected: UID/name-wide kill, `killall`, `pkill`, SIGKILL

UID 1001 and the process package list are shared, and another user has a same-name process. Wide selection can kill unintended processes. SIGKILL also removes the graceful exact-PID constraint and is unnecessary given the proven TERM behavior.

### Rejected: init service restart

No independent init service owns this app process. Fabricating a `ctl.*` path would not match the current ROM lifecycle.

## Automatic recreation and object construction

Current package/process records prove ActivityManager persistent supervision. The same-ROM C7 capture proves the concrete behavior:

- old PID 3333 died at 15:46:17.387;
- new main PID 14820 started at 15:46:17.414 (about 27 ms);
- the new application bound by 15:46:17.472 (about 85 ms).

The fresh PID then logged:

- `PhoneFactory: Creating Phone ... sub = 0` and `sub = 1`;
- `ANM-0/1 operates in AP-assisted mode`;
- `makeQtiServiceStateTracker` and `[0]/[1] QtiServiceStateTracker created`;
- `NRM-C/I-0/1 registerForNetworkRegistrationInfoChanged`;
- `DNC-0/1 DataNetworkController created` and QTI constructors;
- ANM binding to `vendor.qti.iwlan`;
- NRM-I-0/1 connection to IWlanNetworkService;
- WLAN DataService binding into DNC-0/1;
- subscription restoration, slot1 CarrierConfig load and MMTEL `connectionReady 11`.

This confirms fresh creation rather than mere dumpsys continuity.

## Vendor-side expectation

R3 intentionally leaves these processes alive:

- primary qcrild;
- target qcrild2;
- `.qtidataservices` containing QNS/IWLAN/CNE providers;
- `org.codeaurora.ims`;
- vendor.per_mgr / pm-service and X55.

Binder clients in the new phone process will reconnect to those existing providers. The experiment gates their PIDs before and after R3. Any unexpected vendor PID change makes the R3 trial invalid rather than broadening R3 silently.

## Slot0 impact

R3 is not slot scoped. Both Phone objects, SubscriptionInfoUpdater, framework data-service clients, CarrierConfig listeners and IMS framework clients live in the same main process. Expected transient effects include:

- both slot framework objects disappear and are recreated;
- transient SIM/subscription callback removal and re-add;
- temporary telephony Binder unavailability;
- data/IMS framework interruption and request re-evaluation;
- default-data/subscription mapping replay;
- possible UI “no service” or emergency-only transition.

R3 does not intentionally power either SIM, reset a UICC, restart qcrild, toggle radio power, or force a PLMN search. Nevertheless slot0 cannot be promised unaffected because its framework lifecycle is rebuilt. The current physical topology has slot0 absent; every run still records slot0 mapping and lifecycle events.

## Host artifact gate

The proven v2.6.2 Git content is unchanged, but Computer B had `core.autocrlf=true`; its CRLF worktree bytes hashed differently. In-memory CRLF-to-LF normalization yielded the exact audited SHA-256:

`445752BB49FB487850D0B1A1EFF4F0AA29D58C363C3A86E75BAA841E4CC08F75`

A path-specific `.gitattributes` rule now requires LF for this one frozen artifact. The experiment must verify the exact hash before the baseline reboot and again before every delegated recovery. This is a checkout integrity repair, not a v2.6.2 logic change.

The frozen source also contains one Computer-A-specific absolute ADB path. Account B cannot create the old user-profile path because Windows denies access. `Invoke-FrozenV262Portable.ps1` therefore verifies the canonical hash, changes exactly that one host binding in memory, proves reversing that one substitution reproduces the exact canonical text, and writes the derived launcher only to host-local logs. No recovery statement, timing, safety gate, SIM rule or phone command is changed. Both the canonical and derived hashes are recorded. An attempt that stops at the missing old ADB path is pre-recovery invalid and is not a WFC/R3 failure.

## Safety invariants

- one authorized AP reboot only, before CONTROL_A0;
- exactly one TERM of the exact main UID-1001 phone PID per valid cycle;
- no force-stop, second signal, SIGKILL, system_server action or vendor restart inside R3;
- no adaptive wait extension or fallback;
- vendor PIDs unchanged across R3;
- timeout is an invalid/failing boundary and stops the whole run;
- any valid WFC failure stops the remaining cycles;
- no post-success cleanup before the next cycle's airplane-off transition and fixed R0.

## Conclusion

`R3_METHOD_SAFE=PASS_FOR_CONTROLLED_EXPERIMENT`

`R3_AUTO_RECREATE_CONFIRMED=PASS`

`R3_READY_GATE_DEFINED=PASS`

`PHONE_WRITES=0`

The formal experiment may proceed only through the audited runner and the one-time reboot baseline.
