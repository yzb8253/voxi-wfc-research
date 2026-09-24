# R4a producer-gate postmortem

## Defect

`Invoke-Qcrild2ColdEpoch.ps1` obtained both a post-restart Android logcat window and a live `IIWlan/slot2` `IBase::debug` dump. It checked `performDataModuleInitialization` and NAH construction only in the logcat variable. On this run those internal QCRIL history lines were exposed in the HIDL debug dump, not in the selected logcat text.

All other producer fields passed, but the two false booleans held stability at zero until the fixed 120-second timeout.

## Why this is not R4A_FALSIFIED_PRODUCER

The frozen semantic gate required observable cold DataModule and NAH initialization. The post-stop dump contains timestamped, post-command proof for both, only 0.134 and 0.530 seconds after the restart command returned. The producer was ready; the host evidence adapter read the wrong source.

Classifying this as a producer failure would contradict the captured native evidence. Classifying it as an R4a success or continuing to R3 would also be invalid because the state machine had already terminated and its one-reset budget was consumed.

## Required future correction

A separately authorized v2 series should derive cold-init and NAH markers from the union of:

- bounded post-command logcat; and
- timestamped `DataModule` / `NetworkAvailability` histories in the same live IIWlan debug dump.

The event timestamp must be later than the recorded restart start time. All reset objects, ordering, timeouts and business gates remain unchanged. That correction requires a new reboot baseline and must not resume this v1 series.

## Current decision

- Do not run Cycle 2 or Cycle 3.
- Do not run R3, P, v2.6.2 or SIM recovery.
- Do not escalate to R4b.
- Preserve the clean airplane-OFF F1 scene.
