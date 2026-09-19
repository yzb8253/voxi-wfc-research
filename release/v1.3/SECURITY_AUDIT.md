# Security Audit

## Fixed scope

- Target: VOXI subId11, slot1, phoneId1, carrierId28, MCCMNC23415.
- Protected: China Telecom subId1, slot0, carrierId2237, MCCMNC46011.
- No command accepts arbitrary subscription, slot, or phone identifiers.

## Write boundary

The only packaged Telephony writes are the fixed helper calls below:

- Safe Recover: `setUiccApplicationsEnabled(true,11)` once from verified F8/inactive.
- Deep Recover: `setUiccApplicationsEnabled(false,11)` once, then only after two persistent F8 samples, `setUiccApplicationsEnabled(true,11)` once.

HEALTHY is always zero-write. Deep failure is terminal for that invocation; no false/true retry is possible.

## Concurrency and attempts

- Safe and Deep Recover share an atomic `mkdir` lock.
- Boot mode uses a boot-ID marker and allows at most one automatic Deep Recover per boot.
- Manual Deep Recover, Recover Hard, and Auto Run Now ignore and do not create the boot marker.
- Manual paths still use the recovery lock, fresh probe, fixed identities, and complete dual-SIM gate.

## Network and configuration

Wi-Fi/VPN/TUN readiness uses read-only connectivity and interface/route inspection. The module never starts or changes Wi-Fi, VPN, location, routes, airplane mode, or default data selection.

`customize.sh` initializes `AUTO_RECOVER_BOOT=0` only when external `config.conf` is absent. Existing configuration is preserved on upgrade.

## Forbidden paths

The packaged executable tree contains no callable path for resetIms, disableIms/enableIms, process kill, qcrild/radio/modem reset, SSR, reboot, airplane toggle, CarrierConfig write, settings write/delete, setprop, SELinux changes, or vendor-process restart.

Magisk Action is status-only. Uninstall deletes only module-owned external logs/state/config and performs no Telephony operation.
