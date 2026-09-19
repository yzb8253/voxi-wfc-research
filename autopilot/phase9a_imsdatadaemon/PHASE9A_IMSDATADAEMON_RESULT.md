# Phase 9A imsdatadaemon Restart Result

## Verdict

`IMSDATADAEMON_RESTART_RECOVERY = NOT EXECUTED — CURRENT-STATE SAFETY GATE FAILED`

No TERM or other state-changing operation was executed.

## Static target verification

- Exact process name: `imsdatadaemon`
- PID at verification: `1949`
- Command line/binary: `/vendor/bin/imsdatadaemon`
- Resolved executable: `/vendor/bin/imsdatadaemon`
- UID/GID: `radio` / 1001
- SELinux: `u:r:vendor_ims:s0`
- PPID: 1
- Init service: `vendor.imsdatadaemon`
- Init rc: `/vendor/etc/init/imsdatadaemon.rc`
- Current init state: `running`; init debug PID: 1949
- Start trigger: `vendor.ims.QMI_DAEMON_STATUS=1`
- Current trigger value: `1`

The service is `disabled` for class auto-start but is explicitly started by the QMI-daemon property trigger. It is not `oneshot`, `critical`, or equipped with an `onrestart` action. Standard Android init semantics therefore supervise and restart it after it has been started. This was established statically; no termination was used to test respawn.

The target is a Qualcomm IMS data/DCM process. It is not qcrild, a modem daemon, an SSR controller, or the complete radio stack.

## SSR/modem risk

Classification: `MEDIUM`.

Evidence against an automatic SSR side effect:

- The init service has no `onrestart`, `critical`, reboot, SSR, qcrild, or radio-power action.
- No init trigger consumes `vendor.ims.modemssr` in the searched vendor/odm init trees.
- The binary's crash string says `IMSDATAD Crash signal handler:nothing to recover`.
- No `qcrild`, `ctl.restart`, radio-power, or subsystem-restart command string was found.

Reasons risk is not called LOW:

- The daemon directly links QMI/DSI/CNE libraries and exchanges IMS DCM requests with the modem.
- It contains the property name `vendor.ims.modemssr` and handles modem-link-local/netmgr-restart conditions.
- A process restart would affect shared native IMS data state for both slots.

There is no clear static evidence that TERM would trigger modem SSR, qcrild restart, or radio power cycling, but the dependency is native and shared.

## Runtime safety gate

Target identity: PASS.

Protected slot 0 identity: PASS — subId 1, slot 0, carrierId 2237, MCCMNC 46011.

Wi-Fi: READY.

VPN/TUN: READY.

Required strict F1 state: FAIL.

Actual state before any write:

- VOXI subId 11 / slot 1 / phoneId 1 / carrierId 28 / MCCMNC 23415: PASS
- Subscription: ACTIVE
- UICC applications: ENABLED
- IMS: REGISTERED (2)
- Transport: WLAN (2)
- VOICE/IWLAN: AVAILABLE
- WFC: AVAILABLE
- PS/WLAN: IWLAN/HOME
- `mIsIwlanPreferred=true`
- qti.cne IMS request 268: registered
- UDP/4500: present
- XFRM: present
- Failure class: F0

The experiment required IMS NOT_REGISTERED, transport UNKNOWN, VOICE/IWLAN unavailable, WFC unavailable, and FailureClass F1. Those conditions were not present.

## Execution

- `kill -TERM 1949`: NOT EXECUTED
- New PID: N/A
- Restart result: NOT TESTED
- Slot 0 impact: NONE
- VPN/tun0 impact: NONE

## Next candidate

If a future naturally occurring strict F1 scene satisfies every gate, `imsdatadaemon` remains the Phase 9A candidate. `imsqmidaemon` is recorded only as the next candidate after a clean Phase 9A failure; it was not executed or prepared in this run.