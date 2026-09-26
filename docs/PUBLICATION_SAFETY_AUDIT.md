# Publication Safety Audit

## Decision

**Result: BLOCKED — repository must remain private.**

Audit date: 2026-09-26. Scope: current tracked tree, all reachable Git history and the local untracked Golden archive. No phone was accessed and no phone writes were performed.

## Checks completed

| Category | Result |
| --- | --- |
| Private-key material | No matches |
| GitHub-style tokens | No matches |
| AWS access-key patterns | No matches |
| Bearer/password/cookie assignments | No credible secrets found |
| Unredacted ICCID/IMSI/IMEI in contextual scan | No matches |
| ADB serials/local user paths | Present in historical evidence; expected but not suitable for new public docs |
| Persistent Xiaomi MiPush tag | Present in two tracked historical snapshots and their Git history |
| MAC/BSSID and IP/network identifiers | Present across raw historical captures |

Exact sensitive values are intentionally omitted from this report.

## Blocking paths

- `autopilot/deep_recover_failure_latest/getprop.txt`
- `golden_state/cleaned/01_getprop.txt`
- Multiple raw connectivity/Wi-Fi/telephony captures containing network identifiers

The same classes also exist in the local untracked `voxi_wfc_golden_6of6/` archive, which was not added to Git.

## Why visibility was not changed

Removing current files would not remove their historical blobs. Rewriting history would change commit identities, including research provenance, and was explicitly out of scope. Therefore public visibility cannot be enabled safely under the current constraints.

## Safe remediation choices

1. Keep this provenance repository private and publish a new sanitized mirror containing source, selected redacted evidence and links to immutable internal hashes; or
2. Obtain explicit authorization for a coordinated history rewrite, accept changed commit IDs, rotate any credential later found and re-run the complete audit.

The first option best preserves the existing Golden commit identity. No remediation was performed automatically.
