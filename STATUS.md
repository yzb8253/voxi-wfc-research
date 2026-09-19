# Current Project Status

## Goal
Investigate and stabilize VOXI UK Wi-Fi Calling (WFC) behavior on the target Android device, especially IMS re-registration, modem/radio reset behavior, and WFC persistence after airplane mode changes.

## Handoff rule
Before new work, read `AGENTS.md`, `README.md`, `STATUS.md`, and the latest Git commits.
Do not repeat documented failed experiments unless new evidence justifies it.

## Known findings
- WFC can be triggered under some conditions.
- WFC persistence after leaving airplane mode remains unresolved.
- Expected Qualcomm `msm_subsys` debugfs modem restart entry was unavailable.
- `/dev/subsys_esoc0` open/close is not equivalent to subsystem restart.
- qcrild/qcrild2 restart alone is not a full modem restart.
- Avoid whole-device reboot approaches unless explicitly requested.

## Next tasks
- Investigate vendor/Qualcomm radio reset interfaces without AP reboot.
- Investigate IMS re-registration/recovery without full modem restart.
- Investigate WFC persistence after airplane mode is disabled.
- Reuse previous captures/conclusions before collecting duplicate logs.

## Cross-account workflow
At the end of each session:
- update `STATUS.md`;
- record successful and failed experiments;
- commit changes;
- push to the shared repository.
