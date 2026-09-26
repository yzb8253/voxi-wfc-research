# Experiment Protocol

## Before a run

1. Pin and record the exact Git commit and launcher hash.
2. Record device model, codename, ROM build, boot ID, uptime, SIM topology and target mapping. Use placeholders such as `<ADB_SERIAL>` in shared reports.
3. Capture a read-only baseline: airplane/Wi-Fi/VPN, subscription/UICC, WFC direct health, native ownership, X55 state, crash count and relevant PIDs.
4. Confirm rollback behavior and the maximum count of every write.
5. Stop if an identity, mapping or parser field is missing or contradictory.

## During a run

- Timestamp every transition and phone write.
- Count SIM OFF/ON, UICC false/true, service starts/stops and signals.
- Preserve current-state evidence separately from historical logs.
- Do not add ad-hoc recovery actions after a failure.
- Stop on a new failure class or a failed safety gate.
- Keep control and observation changes separate.

## Required milestones

Where applicable record: native baseline, X55 OFFLINE/ONLINE, PON success, UICC/SIM transition, fresh CNE request, IMS NetworkAgent, ePDG/XFRM, IMS registration/transport, MMTEL voice availability and direct WFC availability.

## Result labels

- `PASS`: the declared predicate is met with all gates satisfied.
- `FAIL`: a valid experiment reached its falsification point.
- `BLOCKED_PRE_WRITE`: the experiment never began because a gate or host prerequisite failed.
- `INVALID`: orchestration, parser or evidence failure prevents inference.

Never relabel an invalid/pre-write abort as a lifecycle failure.

## Repetition

Use a fixed reset `R`, preparation `P`, source hash, write count, wait budget and health predicate across a series. Any valid failure stops the series. A finite pass series means “not falsified in N cycles,” not “proven.”

## Sharing evidence

Redact ADB serials, ICCID/IMSI/IMEI, phone numbers, email/account identifiers, MiPush/device tags, MAC/BSSID, public/private IP addresses, SSIDs, VPN endpoints, local usernames and tokens. Keep raw evidence private unless an explicit publication audit clears it.
