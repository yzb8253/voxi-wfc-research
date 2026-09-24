# R4b frozen state machine

R4a remains falsified at fixed P with M1 missing. R4b does not amend that history.

Each cycle uses exactly one qcrild2 restart, exactly one `.qtidataservices` exact-PID TERM and exactly one audited main `com.android.phone` TERM. The provider must be ready before the consumer is created. The fixed P and frozen v2.6.2 hash, SIM write counts, timing and health predicate remain unchanged.

Failure classes are producer, provider, A, P, or cycle/WFC. Any failure stops the series without reset reordering, timeout extension, workaround, second SIM cycle or fallback. Three passes mean only `R4B_NOT_FALSIFIED_3_CYCLES`, never proof.

The central prediction is explicit: R4a's old-provider/new-consumer pairing missed M1; if a new-provider/new-consumer pairing still misses M1, H3 is falsified at this reset boundary.

