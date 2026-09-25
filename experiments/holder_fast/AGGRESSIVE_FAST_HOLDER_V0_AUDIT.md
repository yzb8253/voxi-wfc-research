# AGGRESSIVE_FAST_HOLDER_V0 static audit

## Scope

This is an independent, not-yet-run recovery entry created only after the holder-only real-device test passed.

- New core copy: `X55-WFC-OneClick-v2.6.2-fast-holder-exp.ps1`
- New engine copy: `X55-WFC-AGGRESSIVE-FAST-HOLDER-engine-v0.ps1`
- New aggregate entry: `X55-WFC-AGGRESSIVE-FAST-HOLDER-v0.ps1`
- New command entry: `RUN-X55-WFC-AGGRESSIVE-FAST-HOLDER-v0.cmd`

## Frozen behavior

The new core differs from `X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1` at exactly one source line and one concept: the Android holder implementation.

Unchanged behavior includes X55 shutdown/PON, 10-second settle, SIM OFF hold, SIM ON observation, health predicate, freeze behavior, cleanup, and attempt logic. The aggressive-conservative engine differs only in the recovery script path. The aggregate entry differs only in the engine path and its independent mode/log labels.

The original v2.6.2 core, aggressive-conservative v0/v1.1 scripts, command entry, stable version, and golden commit were not modified.

## FAST holder properties

- Main Android shell opens and owns FD9.
- Background `sleep 3600` explicitly closes FD9 before exec.
- Main shell installs TERM/INT/HUP trap before opening the device.
- PID file continues to identify the actual FD9-owning shell.
- No SIGKILL, killall, pkill, or broad process-tree kill was added.

## Static result

- Windows PowerShell parser: PASS for new core, engine, and aggregate entry.
- Core semantic diff: PASS; one holder-command line only.
- Original-file immutability versus branch start `2e73647d196f9a8e117e42e579e12587890f5be5`: PASS.
- Full recovery run: NOT RUN.
