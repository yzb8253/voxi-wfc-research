# v2.6.3 three-cycle validation

This directory contains sanitized snapshots and reports for the repeatable state-machine candidate based on commit `89f2c86d48c91a974988d9bf67415f592da6f50d`.

Raw capture output and timelines remain under the Git-ignored host-only `voxi_wfc_local_runs` tree.

## Current execution

The first authorized execution stopped during V1 A normalization because the host wrapper promoted the expected nonzero result from the make-before-break helper to a terminating PowerShell error. After an explicit resume, the corrected wrapper completed A normalization and canonical P creation, but the unchanged v2.6.2 recovery produced no CNE request or WFC within thirty seconds. Cycles 2 and 3 were not run. See `RESULT.md`.
