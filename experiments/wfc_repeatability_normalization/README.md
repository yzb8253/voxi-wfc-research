# WFC Repeatability and State Normalization

This experiment establishes three canonical states with one uniform read-only collector:

- `A0`: clean boot, airplane mode off.
- `P0`: first airplane-mode-on state before recovery.
- `W0`: first stable WFC healthy state after the already validated recovery.

Later cycles must compare `A1` with `A0`, and `P1` with `P0`, before recovery. Only an exact, evidenced residue may receive a minimal targeted correction. A healthy WFC state is frozen: no telephony, modem, IMS, IWLAN, SIM, Peripheral Manager, or QCRIL cleanup follows success.

Complete raw captures remain under the host-only `voxi_wfc_local_runs` directory. Git receives only sanitized, machine-comparable JSON summaries and reports. This avoids publishing raw subscriber records while preserving the state fields needed for comparison.

`capture_snapshot.ps1` is read-only. It does not change airplane mode, Wi-Fi, VPN, SIM, radio, IMS, processes, services, properties, or files on the phone.

## Current run status

The fresh-boot run on 2026-09-24 established A0 and P0, but the frozen historical recovery did not establish W0. The experiment stopped at that boundary. A1, P1, and W1 were not attempted, and no residue normalization was performed. See `RUN_20260924_RESULT.md`.
