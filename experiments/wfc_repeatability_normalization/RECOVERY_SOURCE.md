# Frozen known-good recovery source

This experiment uses the archived, unchanged `v2.5-single-on` recovery source:

- Path: `archive/computer_a_legacy/x55_wfc_oneclick/unnamed_root_variants/X55-WFC-OneClick (6).ps1`
- SHA-256: `CB4F9A3EA4F197FB6906FF562394C1BC8F9D5246A5BB7B93D63ECBC6979267A4`
- Historical behavior: controlled X55 rebirth followed by one fixed slot1 SIM OFF/ON cycle.
- Provenance: project records state that this recovery sequence restored WFC HEALTHY in at least two key runs.

Selection rationale:

- The source is not modified for this experiment.
- Its successful path leaves the X55 holder alive and does not perform native-owner cleanup after WFC recovery.
- This matches the experiment rule: once direct WFC health is reached, freeze telephony/modem/IMS/IWLAN state and collect snapshots only.
- The newer recovery-before-cleanup v2.7 source is not used here because its post-recovery native cleanup would alter W0.

The fallback path in the historical source may restart `vendor.cnd` only after the primary recovery fails. A successful primary path must finish before that fallback. Any fallback activation is recorded as a deviation and does not qualify as canonical W0.
