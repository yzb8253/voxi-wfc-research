# WFC Repeatability and State Normalization

This experiment establishes three canonical states with one uniform read-only collector:

- `A0`: clean boot, airplane mode off.
- `P0`: first airplane-mode-on state before recovery.
- `W0`: first stable WFC healthy state after the already validated recovery.

Later cycles must compare `A1` with `A0`, and `P1` with `P0`, before recovery. Only an exact, evidenced residue may receive a minimal targeted correction. A healthy WFC state is frozen: no telephony, modem, IMS, IWLAN, SIM, Peripheral Manager, or QCRIL cleanup follows success.

Complete raw captures remain under the host-only `voxi_wfc_local_runs` directory. Git receives only sanitized, machine-comparable JSON summaries and reports. This avoids publishing raw subscriber records while preserving the state fields needed for comparison.

`capture_snapshot.ps1` is read-only. It does not change airplane mode, Wi-Fi, VPN, SIM, radio, IMS, processes, services, properties, or files on the phone.

## Current run status

The first 2026-09-24 attempt used the wrong v2.5 source and is retained as `WRONG_RECOVERY_SEQUENCE_CND_FALLBACK`; see `RUN_20260924_RESULT.md`.

The corrected v2.6.2 freeze-on-success run completed two full cycles: A0 -> P0 -> W0, native residue normalization, P1 equivalent to P0, and W1 equivalent to W0. See `runs/v262_freeze_run/RESULT.md`.
