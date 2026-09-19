# VOXI WFC Recovery v1.0 Security Audit

## Fixed Scope

- Protected card: slot0 / phoneId0 / subId1 / carrierId2237 / MCCMNC46011.
- Recovery target: slot1 / phoneId1 / subId11 / carrierId28 / MCCMNC23415.
- Neither CLI arguments nor environment variables can select another subId, slot, or phoneId.

## State Machine

- Healthy `GOLDEN_STRONG`: zero writes.
- Active subscription with UICC apps enabled but abnormal WFC: report `FAILURE_CLASS`, return nonzero, zero writes.
- Inactive/apps-disabled candidate: require protected-slot evidence, then execute the helper's full frozen safety gate using historical subscription metadata.
- Unsafe, unknown, concurrent, or gate-failed state: zero writes.

## Only Permitted Telephony Write

The sole Telephony state-changing invocation in the frozen Java source is:

```java
invoke(isub, "setUiccApplicationsEnabled",
        new Class<?>[] {boolean.class, int.class}, true, TARGET_SUB_ID);
```

`TARGET_SUB_ID` is compile-time fixed to `11`. The call is reachable only in helper mode `recover`, after UID 0, VOXI inactive/apps-disabled identity, slot mapping loss, and protected China Telecom slot0 all pass. The shell controller invokes this mode once and has no retry path.

The recovery helper DEX contains `setUiccApplicationsEnabled`; the read-only probe DEX does not. The module JARs exactly match the frozen reference JAR hashes.

## Forbidden Operations Audit

Executable shell files and helper DEX/source were checked for prohibited behavior. No implementation was found for:

- `setUiccApplicationsEnabled(false, ...)`
- IMS reset, disable, or enable
- Radio reset or radio-power change
- Airplane-mode change
- Reboot
- Telephony/IMS process termination
- CarrierConfig write
- `settings put/delete`
- `setprop`
- system or vendor file modification
- SELinux policy modification

Forbidden writes found: NONE.

## Concurrency

Recovery uses an atomic directory lock under `/data/adb/voxi-wfc-recovery/state/recover.lock`. A second request exits with `Recovery already running.` and cannot invoke the helper.

## Recovery Failure

After the one permitted write, the controller observes for at most 60 seconds. Success requires REGISTERED(2), WLAN(2), VOICE/IWLAN availability, WFC availability, active IMS IWLAN NetworkAgent, and protected slot0. It then waits five additional seconds and reconfirms. Failure generates a redacted diagnostic bundle and performs no further write.

## Privacy

Logs use mode 0700 directories and umask 077. Diagnostic output redacts ICCID, card string, phone number, IMSI, subscriber ID, and remaining 12-or-more-digit sequences. No log intentionally stores a full ICCID, IMSI, or phone number.

## Lifecycle

- No `service.sh`, daemon, watch mode, scheduled task, or boot recovery exists.
- Installation changes no system partition, property, or SELinux policy.
- Uninstall removes only this module's external logs and state. It never changes SIM/UICC or Telephony state.
- Optional WebUI: NOT INCLUDED.
