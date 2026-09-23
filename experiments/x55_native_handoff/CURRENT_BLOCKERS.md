# Current Blockers

Updated: 2026-09-23

Only active blockers belong here. Historical blockers belong in the experiment log or decisions file.

## 1. Preserved device scene requires a new decision

Fail-safe cleanup left per_mgr running as PID 31818 with no `/dev/subsys_esoc0` owner, X55 OFFLINE, crash_count 0, holder absent, and qcrild2 unchanged at PID 13706. No further phone write is authorized from this scene.

Resolution: obtain an explicit recovery or experiment decision. Do not automatically rerun the probe or restart qcrild2.

## 2. Defining experiment phases were not reached

The holder-alone phase succeeded, but a PowerShell `$Pid`/`$PID` collision aborted before per_mgr was started under contention. The qcrild2 re-vote phase was therefore also not run.

Resolution: treat the result as inconclusive. The source bug is fixed and audited, but the experiment must not be rerun without fresh authorization and a new entry scene.

## 3. Historical artifact provenance remains incomplete

The exact historical v2.6.2 source and raw evidence are still absent from GitHub. This is a provenance gap, not a blocker for the new independent probe, whose direct read gates and sanitized run evidence are now preserved.

## Current disposition

- `ABORTED_BEFORE_CONTENDED_PHASE / INCONCLUSIVE`
- Entry gate: `PASS`
- Phone writes: 5
- Detailed evidence: `X55_OWNERSHIP_HANDOFF_001_ABORTED.md`

NEXT_ACTION: preserve the OFFLINE/no-owner scene and wait for a new explicit decision.
