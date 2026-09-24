# R3 three-cycle run record

The authorized run started on 2026-09-24. Cycle 1 is a valid PASS. Cycle 2 stopped before R3 because an invalid intermediate post-R0 gate required framework canonicality before the framework reset. Cycle 3 was not run. See `RESULT.md`.

Required retained fields per cycle:

- old/new main `com.android.phone` PID;
- fresh Phone/SST/ANM/NRM/DNC construction evidence;
- qcrild/qcrild2 and shared vendor PIDs;
- X55/PM ownership and crash_count;
- subscription/UICC and slot0 observations;
- M1 through M7 timestamps;
- v2.6.2 SHA-256;
- SIM OFF/ON count;
- WFC elapsed time and final classification.

Current classification: `ABORTED_PRE_R3_INVALID_INTERMEDIATE_GATE_CYCLE_2`. This is neither `R3_FALSIFIED_AT_CYCLE=2` nor `R3_NOT_FALSIFIED_3_CYCLES`.
