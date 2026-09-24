# R4a three-cycle v1 result

Date: 2026-09-24

Implementation commit initially tested: `0359648e`

Host path-binding correction: `ea4bb3a4dbe91a328557d80923e4694caed43320`

## Classification

```text
SERIES_RESULT=ABORTED_PRE_R3_INVALID_PRODUCER_EVIDENCE_GATE
R4A_FALSIFIED=NO
R4A_FALSIFIED_PRODUCER=NO
R4A_NOT_FALSIFIED_3_CYCLES=NO
CYCLE_2=NOT_RUN
CYCLE_3=NOT_RUN
```

The process-level producer reset actually completed, but the runner did not recognize two cold-epoch markers that were present in the same native IIWlan debug history. The timeout was therefore an evidence-parser defect, not failure of the producer to become ready.

The run remains terminal. It was not resumed after discovering the parser defect because the one permitted producer reset for Cycle 1 had already been consumed. Fixing the gate and sending another restart would change the frozen cycle.

## Baseline

- One and only one authorized reboot established `CONTROL_A0_R4A`.
- Airplane OFF; Wi-Fi/VPN/location/AnyWhere gate passed.
- F1; WFC unavailable.
- qcrild PID 1960; qcrild2 PID 1988; pm-service PID 1239; native ownership clean; X55 ONLINE; crash count zero.

An initial host-only attempt stopped before R0 evaluation because the parameterized R3 capture reader still used the old run-name path. No qcrild2 restart, R3 TERM or SIM operation occurred. Commit `ea4bb3a` corrected and regression-tested only that host path binding before the formal attempt.

## Cycle 1 stages

### R0_NATIVE_READY

PASS with no write. Target mapping/UICC, qcrild identities, PM sole ownership, X55 ONLINE, crash zero and residue gates passed.

### qcrild2 process epoch

- exact write: one `setprop ctl.restart vendor.qcrild2`;
- old PID 1988 gone;
- new PID 19229 stable;
- primary qcrild remained 1960;
- qtidataservices remained PID 3241;
- phone remained PID 3348;
- pm-service remained PID 1239 and sole owner;
- X55 ONLINE; crash count zero.

### Native producer evidence

The runtime loop correctly saw on every sample:

- IIWlan/slot2 present and debug-callable;
- `DsdServiceReady=true`;
- `WdsServiceReady=true`;
- `IWLANEnabled=true`;
- `ModemCapability=true`;
- QualifiedNetworksServiceImpl, IWlanNetworkService and IWlanDataService present.

It incorrectly reported `coldInit=false` and `nah=false` because those booleans were derived only from the `logcat -T` text variable.

The immediate post-stop read-only IIWlan dump proves both events occurred well inside the 120-second window:

- `20:08:05.057 [RIL1][DataModule]: performDataModuleInitialization`;
- `20:08:05.453 [NAH]constructor`;
- current native registration state `REG_HOME`.

Therefore the defined process-local DataModule/DSD/NAH cold epoch **did occur**. What remains unobservable is modem-server teardown acknowledgement and an explicit callback generation ID.

### R3 / A / P / recovery

- R3 phone TERM: 0
- A_R4A_READY: NOT REACHED
- P transition: NOT RUN
- P canonical: N/A
- v2.6.2 executions: 0
- SIM OFF: 0
- SIM ON: 0
- M1-M7: N/A

## Post-stop state

Read-only snapshot at 20:10:29:

- airplane OFF;
- F1, IMS NOT_REGISTERED/UNKNOWN, WFC unavailable;
- qcrild2 19229 stable;
- target active/UICC enabled;
- LTE with PS/WLAN HOME, preferred false;
- pm-service 1239 sole owner;
- X55 ONLINE, crash count zero;
- no holder or module lock.

No cleanup or further recovery action was performed.

## Raw host evidence

Raw logs remain host-only under the run workspace; only their hashes are recorded in Git:

- `series.log`: `0ECFAE183AC80BF7E37EA620F8CD34FC5335AC05CEC5777E49BE16C78372E85D`
- `cycle_1_producer.log`: `E0D4E39118ECDC68A72EDC0F9511EC05C73666E989E94F4BAF99DA7E0EBB83D3`
- `cycle_1_r3.log` (R0/preparation only; R3 TERM count remained zero): `2DB21976E67B0F23F503613AF2ADC88B54F5ECD29B530859A495CBDA5A76F89A`
- post-stop native QNS snapshot: `27FBE861076BA886EE84854FA61FA47462308531A06D4152134D8D88EBF01C2A`

## Research interpretation

1. qcrild2 cold epoch produced a new DataModule/DSD/NAH generation: **YES**, at the process-local level.
2. qtidataservices kept its old process epoch: **YES**, PID 3241 unchanged.
3. New framework consumers bound to the new producer: **NOT TESTED**, because R3 did not run.
4. M1 returned: **NOT TESTED**.
5. Earliest qcrild2-to-qtidataservices divergence after R4a: **NOT ESTABLISHED**.
6. Evidence sufficient to escalate to R4b: **NO**. R4a's complete producer-first/consumer-second causal sequence was never executed.

## Phone-write accounting

- baseline AP reboot: 1
- baseline airplane disable: 1
- baseline Wi-Fi enable: 1
- qcrild2 restart: 1
- R3 TERM: 0
- P airplane enable: 0
- SIM writes: 0

Total phone write actions: **4**.
