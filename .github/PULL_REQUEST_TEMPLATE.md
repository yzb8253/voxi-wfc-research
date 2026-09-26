## Summary

Describe the single conceptual change and its classification (STABLE / EXPERIMENTAL / PROFILING / HISTORICAL).

## Baseline and evidence

- Base commit:
- Tested commit:
- Platform/ROM:
- Test type and repetitions:
- Evidence location:

## Safety

- Phone writes during static tests: `0`
- Phone writes during device tests (enumerate):
- Rollback behavior:
- Safety gates changed: yes/no (explain)
- Golden files changed: no (required unless explicitly justified)

## Validation

- [ ] PowerShell 5.1 parser passes where applicable
- [ ] Offline fixtures pass
- [ ] No unsafe classifier promotion
- [ ] New documentation links resolve
- [ ] Logs and fixtures are redacted
- [ ] No secrets, raw SIM/device IDs, MAC/BSSID, IP/VPN endpoints, or local usernames added
- [ ] Result wording distinguishes pass, falsification, invalid run, and pre-write block

## Golden compatibility

State whether this is an exact Golden reproduction, a derivative, or unrelated. List every behavioral difference from Golden.
