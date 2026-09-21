# One-Shot QCRIL Slot2 Reinit Preparation

Date: 2026-09-21

## Scope and outcome

This phase attempted only build-time and runtime-resolution preparation for a fixed RIL-instance-1 diagnostic hook. It did not invoke any of the four target functions, replace the production IIWlan callbacks, attach a debugger, inject code, restart a process, or change phone state.

The preparation stopped before building an executable hook. The current-ROM library base, exact function addresses, live `DataModule` pointer, and live `DSDModemEndPoint` pointer cannot be obtained through the available non-invasive read paths. The user's mandatory rule therefore applies: stop rather than guess an address.

Phone writes: 0.

## Runtime target verification

| Field | Result | Evidence |
|---|---|---|
| Process | PASS | `/vendor/bin/hw/qcrild -c 2` |
| PID | PASS | `1919` at dry-run time; must always be resolved again immediately before any future test |
| PPID | PASS | `1` |
| UID | PASS | `radio` |
| SELinux domain | PASS | `u:r:rild:s0` |
| Target library dependency | PASS | qcrild declares `libril-qc-hal-qmi.so` |
| Library runtime base | FAIL | `/proc/1919/maps` is denied even from the available Magisk context |
| Current-ROM library bytes/symbol table | FAIL | SELinux denies reading `/vendor/lib64/libril-qc-hal-qmi.so`; no bypass was attempted |

Kernel boot ID at dry run: `d5226877-9ac1-48b7-8ad3-2da783d6f6b0`.

## Target functions

The source-correlated four-step sequence remains:

1. `DSDModemEndPoint::sendAPAssistIWLANSupportedSync()`
2. `DSDModemEndPoint::registerForSystemStatusSync()`
3. `DataModule::initializeIWLAN()`
4. `DSDModemEndPoint::generateDsdSystemStatusInd()`

Source reference: Qualcomm `qcril-data-hal`, revision `36fc163a534963a5b3af52186af5efcc63401ad2`.

| Function | Source ABI shape | Current-ROM runtime address | Safe object source |
|---|---|---|---|
| `sendAPAssistIWLANSupportedSync()` | non-static C++ member; requires live DSD endpoint `this` | UNRESOLVED | UNRESOLVED |
| `registerForSystemStatusSync()` | non-static C++ member; requires live DSD endpoint `this` | UNRESOLVED | UNRESOLVED |
| `initializeIWLAN()` | non-static C++ member; requires live DataModule `this` | UNRESOLVED | UNRESOLVED |
| `generateDsdSystemStatusInd()` | non-static C++ member; requires live DSD endpoint `this` | UNRESOLVED | UNRESOLVED |

The source ABI shape is not a substitute for the exact current-ROM ABI. Hidden/stripped symbols, compiler layout, return convention, and object layout have not been byte-for-byte verified against the loaded image.

## Object ownership

- `DataModule` is a process-local module singleton/registered module owned inside qcrild2. Its live address is not exported by a safe read-only interface.
- `DataModule` owns the live `DSDModemEndPoint` through its endpoint acquisition path. Constructing or acquiring an endpoint from a separate process would not produce the existing qcrild2 object.
- No safe public getter was found that returns either live pointer to an external diagnostic process.
- Memory scanning, ptrace, debuggerd attachment, Frida-style injection, or guessed singleton offsets were not used. Those approaches would be invasive and would not satisfy this phase's safety contract.

## Calling-thread requirement

Calling the four methods from an arbitrary injected thread is unsafe.

`DataModule::initializeIWLAN()` replaces the `NetworkAvailabilityHandler` unique pointer, consumes cached status, registers indications, and calls datactl. The surrounding production paths execute from the DataModule message/looper context. The synchronous DSD endpoint methods also participate in the module/message framework. No source evidence establishes that these mutations are safe from an unrelated thread.

The only acceptable future strategy is a custom, fixed one-shot message handled on the existing DataModule looper. The handler would obtain the endpoint from the live DataModule context and execute the four fixed calls there. No existing exported message performs the complete sequence, and adding such a handler requires a verified in-process integration mechanism. That mechanism is not presently available without modifying or injecting into qcrild2.

## Fixed-instance proof

- AP-side instance binding: PASS. `/vendor/bin/hw/qcrild -c 2` is RIL instance 1 and publishes `IIWlan/slot2`; its DataModule and NetworkAvailabilityHandler are the slot2 process-local path.
- Dynamic target input: prohibited. A future hook must accept no slot, phone, subId, transaction, address, or numeric state argument.
- Modem-side isolation: UNKNOWN. The audited QMI DSD capability and indication-registration messages contain no explicit slot field. AP-side fixed process selection alone does not prove that the modem-side DSD session cannot affect shared data-policy state.

## One-shot protection design

A future implementation must require all of the following before it can dispatch its single DataModule-looper message:

- exact cmdline `/vendor/bin/hw/qcrild -c 2` and SELinux domain `u:r:rild:s0`;
- current PID re-resolution and loaded-image identity verification;
- boot-ID token equal to the token captured when the operation is armed;
- compile-time fixed RIL instance 1 / IIWlan slot2;
- invocation counter initialized to zero and atomically changed to one before dispatch;
- before snapshot proving VOXI slot1 identity and protected slot0 identity;
- bounded handler completion timeout;
- independent crash watchdog that observes only and never retries;
- after snapshot and immediate termination;
- no retry loop and no automatic fallback.

These guards constrain a valid hook; they do not compensate for unresolved addresses, object pointers, ABI, or thread integration.

## Future success criteria

If a later build becomes safe and receives separate execution authorization, record the P baseline and observe for at most 90 seconds:

- `SUCCESS_A`: IMS qualified list changes to `[IWLAN,UNKNOWN]`.
- `SUCCESS_B`: outbound IMS/IWLAN qualified-network publication appears.
- `SUCCESS_C`: a new qti.cne IMS request appears.
- `SUCCESS_D`: IMS enters REGISTERING on WLAN.
- `SUCCESS_E`: IMS reaches REGISTERED/WLAN and WFC becomes available.

If only A or B occurs, stop without a SIM cycle or fallback action.

## Dry-run result

The dry run resolved the fixed qcrild2 process and its identity, then failed closed at runtime image resolution:

- qcrild2 PID: `1919`
- module base: UNRESOLVED
- four function addresses: UNRESOLVED
- DataModule pointer: UNRESOLVED
- DSDModemEndPoint pointer: UNRESOLVED
- calling-thread strategy: identified, but no safe dispatch entry exists
- target calls executed: 0

Verdict: `FAIL_SAFE`. No deployable hook was built or pushed to the phone.

## Readiness decision

Can execute one-shot safely enough for a controlled test: **NO**.

The blockers are concrete, not merely missing confidence: no verified current-ROM offsets, no live object pointers, and no non-invasive route onto the DataModule looper. Execution must remain blocked until all three are resolved without callback replacement, process restart, debugger attachment, or guessed addresses.
