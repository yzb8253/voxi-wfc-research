# Frozen known-good recovery source

The authoritative historical source for this experiment is:

- Path: `archive/computer_a_legacy/x55_wfc_oneclick/v2.6.2/X55-WFC-OneClick-v2.6.2-native-owner-restore.ps1`
- SHA-256: `0B83D687F354F1A6B920937E22ACF9D761BAC51E064C8D3CC14BDDAA51FE3CE7`
- Validated path: X55 clean rebirth, ten-second settle, X55-only check, then at most one fixed slot1 SIM OFF/ON cycle with a three-second OFF hold and a 30-second health window.

The v2.5 source previously selected here was incorrect for this experiment because it includes a CND fallback. Its run is retained and explicitly classified `WRONG_RECOVERY_SEQUENCE_CND_FALLBACK`.

The experimental copy `v262_freeze_run/X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1` preserves the v2.6.2 recovery path. Its only behavioral change is to skip transactional cleanup after direct WFC health succeeds.
