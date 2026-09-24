# R4a v2 counterexample analysis

R4a is falsified at Cycle 2 P, with M1 as the first missing milestone.

The counterexample is valid because both lifecycle resets completed first:

1. qcrild2 formed a fresh, fully ready producer epoch;
2. qtidataservices intentionally remained in its old PID 3373 epoch;
3. exact R3 created a new phone/framework consumer epoch;
4. A_READY passed;
5. the fixed airplane transition and 60-second P window ran unchanged.

Before R3, old phone PID 24403 received fresh IMS->IWLAN callbacks from the new producer/provider chain. After R3, new phone PID 19318 received no corresponding replay. NRM returned `NOT_REG_OR_SEARCHING`, SST consumed that negative result, and DNC finished UNKNOWN.

This narrows the counterexample from the broad qcrild2-to-framework chain to the retained qtidataservices/QNS provider epoch and its relationship with a newly created framework consumer. It qualifies R4b for design review, not execution.
