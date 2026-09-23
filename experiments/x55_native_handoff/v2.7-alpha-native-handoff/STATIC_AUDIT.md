# v2.7-alpha Static Audit

Status: PASS

Scope: local source review only. No ADB wait, no script execution against a phone, and no phone write.

## Results

- PowerShell parser: PASS
- Reserved PID variable collision scan: PASS
- Launcher default dry-run: PASS
- Fixed execution confirmation token: PASS
- Fixed target slot 1 and protected slot 0 gates: PASS
- Fixed helper classes and SHA-256 pins: PASS
- Holder ownership/PID verification before TERM: PASS
- Exactly one qcrild2 restart call site: PASS
- Native reacquire required before SIM cycle: PASS
- Healthy state skips SIM cycle: PASS
- One POWER_DOWN and one POWER_UP call site per device orchestrator: PASS
- POWER_UP return-code preservation: PASS
- No automatic retry: PASS
- No modem/radio/IMS reset, reboot, broad kill, cnd restart, or primary qcrild restart path: PASS
- Distinct recovery/native-handoff/final-WFC/cleanup outputs: PASS
- v2.6.2 files modified: NO

## Residual risks

- Stopping Peripheral Manager intentionally transitions X55 OFFLINE before holder-controlled rebirth.
- Restarting qcrild2 can transiently disrupt slot2 radio/data framework state.
- Starting Peripheral Manager while holder owns the node is device-specific; unexpected behavior causes BEHAVIOR_CHANGED and abort.
- Fail-safe cleanup restores Peripheral Manager and releases only the script-owned holder, but does not escalate into extra qcrild2, cnd, modem, radio, or reboot actions.
- The internal QCRIL re-vote mechanism remains log-unproven even though native reacquire behavior was observed in 001B.

The executable state machine has not been run in this build phase.
