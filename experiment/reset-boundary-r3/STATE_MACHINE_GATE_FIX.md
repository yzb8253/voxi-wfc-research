# R3 state-machine gate correction

## Historical result remains unchanged

The first series remains:

- Cycle 1: `R3_VALID_SINGLE_CYCLE_PASS`.
- Cycle 2: `ABORTED_PRE_R3_INVALID_INTERMEDIATE_GATE`.
- Cycle 2 is not an R3 failure because no `com.android.phone` TERM occurred.

No old result, snapshot or log is reclassified.

## Defect

The original orchestrator used the full A-canonical predicate immediately after R0. That predicate included `rilTechnology == LTE`, `mIsIwlanPreferred == false` and no current qti.cne IMS request. These are framework lifecycle observations owned by the still-live Phone/SST/ANM/NRM/DNC graph.

R0 is only the native/modem ownership normalizer. It cannot be required to erase the exact framework residue that R3 is intended to test. Requiring framework canonicality before R3 made the state machine circular and stopped Cycle 2 before the candidate reset boundary ran.

## Correct separation

`R0_NATIVE_READY` checks only:

- fixed VOXI identity and active/enabled UICC mapping;
- valid qcrild and qcrild2 identities;
- valid pm-proxy and mdm_helper presence;
- vendor.per_mgr running;
- pm-service PID 1 child with exact command line;
- pm-service sole ownership of `/dev/subsys_esoc0`;
- no holder, holder PID file or module lock;
- vendor peripheral ONLINE;
- X55 ONLINE;
- crash_count zero.

It deliberately does not inspect LTE/IWLAN selection, `mIsIwlanPreferred`, SST/DNC terrestrial state or qti.cne IMS demand.

After `R0_NATIVE_READY`, the separately audited environment gate confirms airplane OFF, Wi-Fi, VPN, location and AnyWhere. The orchestrator then selects the exact UID-1001, `u:r:radio:s0`, persistent main `com.android.phone` PID and sends one TERM.

`R3_FRAMEWORK_READY / A_READY` is evaluated only after ActivityManager recreation, all Phone/SST/ANM/NRM/DNC/CarrierConfig/MMTEL creation markers, unchanged vendor scope and five stable one-second identity samples. It requires the complete native and environment gates plus LTE, `mIsIwlanPreferred=false`, and no current qti.cne IMS request. The timeout remains 120 seconds and fails closed.

## New independent series

The corrected run is isolated under `runs/r3_3cycle_v2/` with host evidence under `voxi_wfc_local_runs/reset_boundary_r3/r3_3cycle_v2/`. It uses a separate one-reboot marker and `CONTROL_A0_V2`; it never combines the old Cycle 1 with new results.

The frozen v2.6.2 source remains byte-identical with SHA-256 `445752BB49FB487850D0B1A1EFF4F0AA29D58C363C3A86E75BAA841E4CC08F75`.

