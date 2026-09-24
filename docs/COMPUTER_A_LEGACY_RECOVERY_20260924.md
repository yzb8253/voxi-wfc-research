# Computer A Legacy Recovery Audit

Date: 2026-09-24

## Scope and method

The audit scanned the research-related contents of `D:\`, including the root and the X55/WFC tool, monitor, state-search, log, and modem-SSR directories. All 465 candidate files were indexed by absolute/relative path, size, last-write time, and SHA-256. Git tracked files were hashed for exact-content comparison. Fourteen ZIP files were inspected entry-by-entry without changing the originals.

The D: source tree was not modified, moved, deleted, or cleaned. No ADB, fastboot, service call, Android property write, phone operation, or experiment was used.

## Inventory summary

- Candidate files scanned: 465
- Candidate bytes scanned: 463169043
- Exact SHA-256 duplicates already tracked before import: 5
- Context-relevant same-name/different-hash source groups: 2
- Original files selected and copied with exact-byte verification: 81
- Unique ZIP entries extracted with exact-byte verification: 9
- Host-only raw/unselected evidence files: 353
- Host-only raw/unselected evidence bytes: 416795027
- Hash-indexed binaries and ZIP containers: 26
- ZIP entries: 303 redundant, 10 unique; nine safe unique entries imported and one precise-location entry left host-only for privacy

The complete D: inventory and disposition are in `COMPUTER_A_RAW_EVIDENCE_MANIFEST.csv`. Imported-file provenance is in `archive/computer_a_legacy/SOURCE_PROVENANCE.csv`.

## High-priority recovery

### v2.6.2

Exact v2.6.2 host script and launcher were recovered under `archive/computer_a_legacy/x55_wfc_oneclick/v2.6.2/`.

- PS1: 46169 bytes, SHA-256 `0B83D687F354F1A6B920937E22ACF9D761BAC51E064C8D3CC14BDDAA51FE3CE7`
- CMD: 419 bytes, SHA-256 `04C237093310639E8B65BC36F52C7F00C95F52A0057BDFA1FC0DBE605FD5685A`

This corrects the previous statement that exact historical v2.6.2 host source was missing. Historical raw-log completeness remains unresolved.

### PassiveMonitor

The exact v1.2 detector and launcher are canonical under `tools/x55_voxi_passive_monitor/`; v1.0 and v1.1 are under `legacy/`. The README records its read-only scope and heuristic limitations. Original v1.2 logic was not edited.

### StateSearcher

Exact v3.0 through v3.5 scripts and launchers are preserved under `tools/x55_wfc_state_searcher/`. v3.5 is labeled the latest historical timing sweeper, not a recovery success. Selected histories preserve the v3.4 12-round all-P0 and v3.5 16-round all-P0 results.

### SSR read-only audit

The audit script, original README, and small topology captures are under `tools/voxi_modem_ssr_readonly_audit_v3/`. Its redundant ZIP is hash-indexed only.

## Large evidence and binaries

Large logcat and raw captures were not added to ordinary Git. System/vendor APK, SO, kernel-header packages, and similar reproducible binaries are hash-indexed only.

Two local kernel modules have no matching source in the scanned Computer A assets. On 2026-09-24, exact copies were placed in the isolated historical binary archive at `archive/computer_a_legacy/unique_binaries/` to prevent loss of the only known local artifacts:

- `D:\x55_ssr.ko`: 54304 bytes, SHA-256 `8835F714725205C63201D9A88152EEF638B05F4BAA9CCFFFBA810A4C1A86145D`
- `D:\x55_test.ko`: 30152 bytes, SHA-256 `8565282386B0C0CF9F0A767525FB8E779828FB0C84AAA051AF9D3E0DA5FD1642`

The original Computer A files remain unchanged. Source code was not recovered, their exact purpose/history is not fully proven, and the archive explicitly prohibits loading or automatic execution.

## Validation

- Source-to-repository SHA-256 equality: PASS
- PowerShell parser-only validation: 20 PASS, 2 `FAIL_ORIGINAL`; the exact historical failures were not edited or executed. PassiveMonitor v1.2 and v2.6.2 both PASS.
- Canonical PassiveMonitor v1.2 script and launcher present: PASS
- Exact v2.6.2 script and launcher present: PASS
- Original D: files modified: NO
- ADB used: NO
- Phone writes: 0

## Remaining issues

- Historical raw logs are not complete in Git and remain host-only by design.
- Precise-location evidence from one ZIP entry remains host-only for privacy.
- The two unique kernel modules are isolated in the historical binary archive; matching source code remains unavailable.
- No recovered historical script is authorized for execution by this audit.

Per-file parser results are recorded in `COMPUTER_A_LEGACY_POWERSHELL_VALIDATION.csv`. The two original failures are StateSearcher v3.0 and one older OneClick script extracted from `X55-WFC-OneClick.zip`.
