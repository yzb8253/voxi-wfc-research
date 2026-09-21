# QCRIL Patch Deployment Feasibility

Date: 2026-09-21

Scope: static implementation and deployment audit only. No device write, HIDL business method, process restart, injection, ptrace, SELinux change, or binary patch was performed.

## Verdict

The proposed `IBase::debug()` control path is technically suitable for a tightly constrained source-level hook. A dedicated message can move execution from the HIDL binder thread onto the existing DataModule looper, where the four fixed operations can run against the live `DataModule` and `DSDModemEndPoint` objects.

It is not currently possible to build a replacement `libril-qc-hal-qmi.so` that is demonstrated to be ABI-compatible with this ROM. The exact on-device ELF dynamic metadata and symbols remain unavailable, and the available Qualcomm mirror does not include the exact Xiaomi vendor build inputs. The correct release decision is STOP before prototype build or deployment.

## Current ROM Library Evidence

| Item | Result | Evidence / limitation |
|---|---|---|
| Load path | Confirmed | `rild.libpath=/vendor/lib64/libril-qc-hal-qmi.so`; saved qcrild2 maps show the same path. |
| Consumer | Confirmed | Saved command line is `/vendor/bin/hw/qcrild -c 2`; both qcrild instances map the same library. |
| ELF architecture | AArch64 / ELF64 confirmed indirectly | Device kernel is `aarch64`, the process uses `/vendor/lib64`, and the captured mappings are from 64-bit qcrild. |
| Mapped image shape | Confirmed | qcrild2 maps offsets `0`, `0x00acb000`, `0x01e78000`, and `0x01f19000`; this is a large monolithic QCRIL library. |
| SONAME | Unknown | The build module name predicts the filename, but current `DT_SONAME` could not be read. |
| Build ID | Unknown | Current library bytes are SELinux-protected from the available Magisk context. No bypass was attempted. |
| Exact `DT_NEEDED` | Unknown | Loaded maps and source build files are correlated evidence, not the current dynamic table. |
| Exports / symbol versions | Unknown | Current dynamic symbol/version tables could not be read. |
| Vendor ABI | Not verified | Class layout, feature macros, compiler flags, generated QMI headers, and proprietary archives cannot be matched exactly. |

The mirror builds `libril-qc-hal-qmi` as a proprietary shared library and whole-archives Android, voice, NAS, UIM, IMS, DataModule, OEM Hook, and other QCRIL modules. It also links many versioned HIDL, QMI, data, diag, binder, and vendor libraries. A small source edit still requires rebuilding the whole ABI-sensitive shared object.

## Source-Mirror Fit

Source mirror revision: `36fc163a534963a5b3af52186af5efcc63401ad2` (2023-07-24).

Strong correlation:

- ROM services expose `vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot1` and `/slot2`, matching the mirror.
- Source registers `slot(instanceId + 1)`, matching qcrild2/RIL instance 1 to `IIWlan/slot2`.
- Current logs/dumps contain matching IWLAN capability, DataModule, DSD, NetworkAvailabilityHandler, and diagnostic strings.
- The ROM uses VNDK 30 vendor binaries, matching the source generation's radio HIDL family.

Insufficient for an ABI replacement:

- The Android 13 Xiaomi `cas` ROM uses a VNDK 30 vendor image, but the mirror is not an identified tree for build `V816.0.4.0.TJJCNXM`.
- Current `DT_SONAME`, build ID, `DT_NEEDED`, exports, symbol versions, and C++ layout cannot be compared.
- Exact board macros, generated QMI inputs, proprietary archives, compiler revision, linker flags, and Xiaomi modifications are absent.
- Both qcrild instances load the same library, so loader/ABI failure is not slot2-scoped.

The mirror is sufficient to design the patch, not to produce a verified replacement.

## Existing Debug Control Path

`IWlanImpl` overrides inherited `IBase::debug(handle, options)`. The mirror implementation ignores options and calls `getDataModule().dump(fd)`. Existing read-only `lshal debug ...IIWlan/slot2` captures prove that current HIDL transport reaches this implementation.

This path does not call `setResponseFunctions()`, does not replace production callbacks, and supplies a debug FD/options through normal HIDL transport. It initially executes on a HIDL binder thread, so the four operations must not execute directly there.

## Minimal Patch Design

Preserve normal dump behavior unless the option vector contains exactly one value: `voxi_reinit_once`. Fail closed unless:

1. `qmi_ril_get_process_instance_id() == QCRIL_SECOND_INSTANCE_ID` (instance 1).
2. The registered service is `IIWlan/slot2`.
3. Current boot ID matches the host/module invocation token; unreadable or mismatched is failure.
4. An atomic process-local invocation counter changes from 0 to 1 exactly once.
5. DataModule and its live DSD endpoint are ready.

Dispatch a new compile-time-fixed `SolicitedMessage`. Register it in DataModule's `mMessageHandler`, which executes the handler on the established DataModule looper. Accept no slot, subId, phoneId, address, function name, transaction number, power state, QMI payload, or retry parameter.

The handler performs only:

1. `sendAPAssistIWLANSupportedSync()`
2. `registerForSystemStatusSync()`
3. `initializeIWLAN()`
4. `generateDsdSystemStatusInd()`

It records bounded before/after diagnostics to a duplicated debug FD and returns structured status. The binder thread may wait with a fixed timeout; the DataModule looper never waits on it. Timeout or any failed precondition causes no retry.

No modem reset, radio/SIM/UICC operation, PDC/MBN/NV/EFS access, process restart, generic function call, or generic QMI passthrough is included.

## Safety Boundaries

- AP-side fixed slot2: strong; qcrild2 is `qcrild -c 2`, process instance 1, service `slot2`.
- Slot0 dispatch exclusion: strong; instance 0 is rejected before message creation.
- Modem-side isolation: not proven; audited DSD capability/registration requests have no explicit slot field.
- Thread safety: acceptable only via the dedicated MessageBus handler.
- One-shot: atomic maximum one per process/boot, timeout, no loop, no retry.

## Deployment Options

### A. Magisk bind-mount replacement

Mechanically possible without changing `/vendor`, disabling AVB, or disabling SELinux. It must be mounted before qcrild loads it and preserve path, ownership, mode, and label. Activation requires AP reboot: an already loaded library cannot be changed, and qcrild restart is outside this design.

It is not presently safe because ABI compatibility cannot be proven. A bad library can prevent both qcrild instances from loading.

### B. Companion library

No sanctioned companion load point exists. `LD_PRELOAD`, ptrace/injection, or forcing `dlopen()` violates the constraints and SELinux boundary. A companion cannot register the live DataModule handler without changing the main library or an existing loader.

Result: not viable.

### C. Other overlays

Replacing only the generated HIDL interface library does not change `IWlanImpl`. Overlaying qcrild or patching machine code has equal or greater risk and is excluded. No safe property, init, plugin, or external trigger exists.

Result: no safer alternative.

## Final Feasibility

Existing debug control path: **YES**

Can add safe one-shot debug token: **YES, at source level with an exact matching vendor build**

Can build ABI-compatible replacement: **NO with currently available artifacts**

Can deploy via Magisk without modifying vendor: **YES mechanically, but not safely until ABI compatibility is proven**

Requires phone reboot for installation: **YES**

Main blocker: exact Xiaomi/Qualcomm vendor source/build inputs and verifiable current ELF ABI metadata are unavailable. Source similarity cannot establish compatibility for this monolithic library shared by both qcrild processes.

Recommended implementation: obtain the exact vendor tree or an authorized matching build artifact, reproduce and compare the original ABI first, then add only the fixed token and DataModule message. Do not binary-patch or deploy the present mirror build.

Risk: **HIGH** for deployment; **LOW/MEDIUM** for the bounded handler if built in the exact tree and independently reviewed.

NEXT: **STOP**

Phone writes: **0**
