# Contributing

Thank you for helping investigate VOXI Wi-Fi Calling recovery. This is safety-sensitive, device-specific research; reproducibility and evidence matter more than the size of a change.

## Before contributing

1. Read `README.md`, `docs/SAFETY.md` and `docs/EXPERIMENT_PROTOCOL.md`.
2. Search existing issues and experiment reports.
3. Classify the work as GOLDEN, STABLE, EXPERIMENTAL, PROFILING or HISTORICAL.
4. Never modify or relabel the Golden commit. Derivatives must cite it and list every difference.

## Reports must include

- Exact commit and launcher.
- Device model/codename, ROM build and Android version.
- Carrier, SIM topology and target slot/phone/subscription mapping (redacted where identifying).
- Pre-state and declared success/failure predicate.
- All phone writes and their maximum counts.
- Timestamps for important milestones.
- Raw evidence location and a redaction statement.
- Whether the result is a single observation, repeated series or falsification.

## Safety and privacy

Do not submit secrets or unredacted ADB serials, ICCID, IMSI, IMEI, EID, phone numbers, email/account tags, MiPush tags, MAC/BSSID, SSID, public/private IP addresses, VPN endpoints or local usernames. Use placeholders such as `<ADB_SERIAL>`, `<ICCID_HASH>` and `<LOCAL_USER>`.

Do not add unverified modem, Binder, HIDL or QMI writes. Every write must have a static provenance, exact target, bounded count and rollback story. A missing/unknown field must fail closed.

## Pull requests

- Keep one conceptual change per PR.
- Do not combine observation changes with recovery changes.
- Add offline fixtures for parsers and classifiers.
- State `PHONE_WRITES=0` for static-only work.
- Include PowerShell 5.1 parser/test results where relevant.
- Preserve line endings required by Android payloads.
- Explain why the change does not weaken safety gates.

## Commit messages

Use a short imperative subject and describe the experiment boundary in the body. Do not call an experiment “proven”; use precise language such as “not falsified in 3 cycles.”
