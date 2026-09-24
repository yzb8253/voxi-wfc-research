# Fresh-boot repeatability run result

Date: 2026-09-24

Status: `WRONG_RECOVERY_SEQUENCE_CND_FALLBACK`

This run is retained as a failure sample only. It used the wrong historical source (`v2.5-single-on`) rather than the verified `v2.6.2-native-owner-restore` sequence. Its CND fallback proves it is not a valid known-good repeatability run. Do not use this run to judge v2.6.2 recovery or post-success residue.

## Source and boundaries

- Git baseline: `966f3bd665089efd20054160dd9730755cc0c269`
- Device: fixed validated `cas` / Android 13 build
- Recovery source: unchanged archived `v2.5-single-on`
- Recovery SHA-256: `CB4F9A3EA4F197FB6906FF562394C1BC8F9D5246A5BB7B93D63ECBC6979267A4`
- Raw captures and the full recovery log remain host-only.
- Recovery log SHA-256: `12834DB3B584C55E2FC4D35CD69783085EA7B6C6318EA5F8E20BFFE0C10F8D98`

## A0

`snapshot_A0_clean_boot_offline_airplane.json` was captured after a confirmed new boot and natural service stabilization.

- Airplane mode OFF; Wi-Fi ON; VPN network present.
- VOXI subId 11 / slot 1 / phoneId 1 / carrierId 28 / MCCMNC 23415.
- Subscription active and UICC applications enabled.
- vendor.per_mgr running.
- pm-service was the native `/dev/subsys_esoc0` owner.
- X55 ONLINE; crash count 0.
- No live holder. A stale cross-boot `x55_holder.pid` remained, pointing to a dead PID; it was present in both A0 and P0.
- IMS NOT_REGISTERED / transport UNKNOWN / WFC unavailable, as expected outside the WFC airplane-mode path.

## P0

Airplane mode was enabled once. Wi-Fi was re-enabled after Android lowered wlan0. After a 30-second settle, `snapshot_P0_first_airplane_polluted.json` was captured.

The machine diff against A0 contained only four expected fields:

- airplane mode: 0 -> 1
- Wi-Fi setting enumeration: 1 -> 2
- RIL data technology: LTE -> IWLAN
- IWLAN preferred: false -> true

Identity, subscription, UICC, QCRIL PIDs, PM/X55 ownership, X55 state, and residue fields matched A0.

## Recovery attempt

The unchanged known-good source completed these actions once:

1. Stopped vendor.per_mgr and confirmed X55 OFFLINE.
2. Started one owned holder and confirmed X55 ONLINE with a new `PON_SUCCESS`.
3. Executed one fixed slot1 SIM power OFF/ON cycle.
4. Waited 30 seconds for direct WFC health.
5. Because the historical primary path did not recover, executed its built-in single vendor.cnd fallback and waited another 30 seconds.

Observed result:

- X55 ONLINE; crash count 0.
- qcrild and qcrild2 PIDs unchanged.
- No native IMS demand surfaced through qti.cne.
- No qti.cne IMS request.
- No UDP/4500 or XFRM.
- IMS remained NOT_REGISTERED with transport UNKNOWN.
- VOICE/IWLAN and WFC remained unavailable.
- Final class remained F1.

The failed-state snapshot is `snapshot_W0_attempt_failed.json`. It is deliberately not named or accepted as W0.

## Stop decision

W0 was not established, so the run stopped without:

- A1 capture or A1/A0 normalization
- a second airplane-mode cycle
- P1 capture or P1/P0 normalization
- a second recovery attempt
- manual QCRIL, PM, IMS, IWLAN, SIM, radio, or modem cleanup

The preserved failed state has vendor.per_mgr stopped, the exact script holder owning `/dev/subsys_esoc0`, X55 ONLINE, and WFC F1. No claim about post-success residue can be made from this run because there was no success state.

## Conclusion

This run disproves the narrower assumption that a fresh reboot plus an A0-equivalent first P0 is sufficient for this historical recovery source to reproduce WFC every time. It does not yet identify the missing prerequisite, and it does not test the requested second-cycle residue hypothesis.
