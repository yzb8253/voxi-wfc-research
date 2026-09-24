# R3 three-cycle reset-boundary experiment

This directory defines the diagnostic `com.android.phone` lifecycle boundary. It does not modify or replace the proven v2.6.2 recovery.

Fixed cycle:

`A_RAW -> fixed R0 -> one exact main phone TERM -> R3_READY -> A_READY -> fixed P -> hash-locked v2.6.2 -> M1..M7 -> FREEZE`

Only a 3/3 result may be classified `R3_NOT_FALSIFIED_3_CYCLES`. Any valid failed cycle stops the experiment and is `R3_FALSIFIED_AT_CYCLE=N`.

The first formal run begins with one and only one AP reboot to establish CONTROL_A0. No reboot is permitted between cycles.

See `R3_SAFETY_DETERMINISM_AUDIT.md` and `R3_READY_SPEC.md` before any execution.
