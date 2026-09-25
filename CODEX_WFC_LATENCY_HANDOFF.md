# Codex Handoff — VOXI WFC latency optimization, stability first

## Mission

Take over the current VOXI Wi-Fi Calling recovery project and reduce end-to-end recovery time **without lowering the observed recovery stability** and without introducing new phone/system regressions.

This is NOT a shortest-path challenge. The optimization target is:

1. Preserve the current known-good recovery behavior.
2. Reduce obviously redundant waiting, repeated diagnostics, and expensive observation work.
3. Keep generous safety margins.
4. Change one thing at a time.
5. Prove every accepted change on the real phone through repeated runs.
6. Verify side effects before accepting an optimization.

The user's priority order is:

**stability / no new bugs > safety / reversibility > repeatability > time reduction > shortest possible time**

## Golden baseline — DO NOT MODIFY

Repository:
`yzb8253/voxi-wfc-research`

Golden stable branch:
`wfc-stable-wrapper-20260925`

Golden stable commit:
`253ab93a2127806837cb472071846f568c811a34`

Optimization branch:
`wfc-latency-study-20260925`

All experimental changes must stay on the optimization branch or child branches. Do not move or rewrite the stable branch.

Local repo:
`C:\Users\ZJH\Desktop\platform-tools\voxi_wfc_research`

ADB:
`C:\Users\ZJH\Desktop\platform-tools\adb.exe`

Device serial:
`fd0ff892`

Validated device:
- Xiaomi 10 / `cas`
- Android 13
- build `V816.0.4.0.TJJCNXM`
- fingerprint `Xiaomi/cas/cas:13/TKQ1.221114.001/V816.0.4.0.TJJCNXM:user/release-keys`
- rooted
- Qualcomm X55 / SDX55M

VOXI target:
- slotId=1
- phoneId=1
- subId=11
- carrierId=28
- MCC=234
- MNC=15

Protected domestic SIM:
- slot0
- subId=1
- MUST NOT be intentionally power-cycled, disabled, reset, or reconfigured.

## Current observed stability

The user has now run the current stable path six consecutive times successfully.

The latest observed run:
- frozen-holder normalization quick path triggered correctly
- `QUICK_FALLBACK_SPLIT=PASS`
- `NORMALIZATION=QUICK_FALLBACK_TO_QCRILD2`
- `PREFLIGHT_FAST_PATH=NATIVE_DUAL_SKIPPED_TO_QCRILD2`
- qcrild2 reacquire passed
- final A0 normalized
- P state clean
- v2.6.2 recovered WFC on attempt 1
- WFC became healthy about 11 seconds after SIM2 POWER ON
- final state: airplane ON + WFC healthy + freeze-on-success holder preserved

However the total run still took about 4m40s.

In that latest run:
- wrapper start: ~16:48:47
- preflight normalization start: ~16:49:14
- preflight normalization pass: ~16:51:47
- v2.6.2 start: ~16:52:24
- WFC healthy / wrapper completed: ~16:53:27

The largest remaining latency is therefore still around preflight / snapshot / normalization work, not the actual final WFC registration.

Historically successful post-SIM2 POWER ON WFC registration has sometimes taken well beyond 12 seconds, including roughly 17s, 22.4s, and 23s. Therefore the current 30-second post-SIM maximum window must NOT be shortened merely to make the script appear faster.

## Current stable architecture

Stable wrapper:
`experiments/wfc_repeatability_normalization/v262_freeze_run/X55-WFC-STABLE-v1.ps1`

Launcher:
`experiments/wfc_repeatability_normalization/v262_freeze_run/RUN-X55-WFC-STABLE-v1.cmd`

Core:
`experiments/wfc_repeatability_normalization/v262_freeze_run/X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1`

Preflight:
`experiments/wfc_repeatability_normalization/v262_freeze_run/repeatability_preflight.ps1`

Normalization:
- `normalize_a1_native_owner.ps1`
- `normalize_a1_qcrild2_reacquire.ps1`

Deep fallback:
`uicc_apps_deep_fallback.ps1`

Current wrapper defaults:
- A settle: 20s
- P settle: 20s
- max normal recovery attempts: 2
- post-SIM WFC recovery window: ~30s
- freeze-on-success: enabled

## Proven recovery core — treat as protected

The v2.6.2 core sequence is considered proven and should not be edited during initial latency profiling:

1. exact platform / target safety gates
2. stop `vendor.per_mgr`
3. confirm X55 OFFLINE
4. create temporary holder for `/dev/subsys_esoc0`
5. X55 ONLINE
6. confirm new PON_SUCCESS
7. 10s settle
8. X55-only WFC probes
9. if still unhealthy, exactly one slot1 SIM2 software power cycle
10. wait up to ~30s for WFC
11. on success: FREEZE, do not cleanup

Known successful final health:
- IMS REGISTERED raw2
- Transport WLAN raw2
- VOICE/IWLAN AVAILABLE
- WFC AVAILABLE

Do not remove freeze-on-success.

## Important normalization fact

On repeated runs after a successful frozen state, the native-owner dual-ownership route is normally not useful on this ROM.

A quick bounded normalization path was added at the golden commit:
- up to 3 dual-owner probes
- restart vendor.per_mgr once
- up to 3 more dual-owner probes
- verify the exact known split fingerprint
- then directly use the validated qcrild2 reacquire fallback

Do not remove its safety fingerprint.

## Main suspicion for remaining latency

Do not assume sleeps are the dominant cost.

The latest quick-path run still spent roughly 153 seconds from:

`PREFLIGHT_APPLY_NORMALIZATION=START`

to:

`PREFLIGHT_APPLY_NORMALIZATION=PASS`

even though the quick qcrild2 path succeeded.

This strongly suggests that full diagnostic snapshot generation and/or repeated ADB/dumpsys collection may now be a major latency source.

Your first job is to instrument, not optimize blindly.

## Required optimization methodology

### Phase 0 — preserve baseline

Before changing behavior:

1. checkout `wfc-latency-study-20260925`
2. verify it starts from golden commit `253ab93...`
3. inspect all relevant scripts and logs
4. do NOT change behavior yet
5. add timing instrumentation only
6. commit instrumentation separately

Measure wall-clock duration of at least these sections:

- syntax gate
- platform/target safety gate
- Ensure-WifiOn
- A_SETTLE
- initial preflight snapshot
- NativeClean/FrozenResidue classification
- quick native-owner probe
- qcrild2 reacquire:
  - holder TERM latency
  - owner NONE / X55 OFFLINE latency
  - qcrild2 restart latency
  - pm-service reacquire / X55 ONLINE latency
- post-normalization snapshot
- Get-WfcStatusText
- Get-CneSnapshot
- airplane OFF -> ON
- P_SETTLE
- v2.6.2:
  - preconditions
  - X55 OFFLINE
  - holder start -> ONLINE
  - PON_SUCCESS
  - 10s settle
  - X55-only health checks
  - SIM2 OFF
  - 3s OFF hold
  - SIM2 ON -> HEALTHY

Emit machine-readable timing lines such as:

`TIMING name=preflight_snapshot_initial ms=...`

Do not change the success/failure decisions while instrumenting.

### Phase 1 — identify actual expensive steps

Run enough real-phone cycles to classify costs for both:

A. clean native A0 entry  
B. next run after successful frozen-holder state

Do not optimize from one sample.

Produce a table:
- step
- min
- median
- max
- percentage of end-to-end time
- whether step is safety-critical
- whether step changes phone state
- candidate optimization
- risk level

### Phase 2 — optimize only high-value low-risk costs

Preferred first candidates:

#### Candidate A — diagnostic snapshot cost

If full `capture_snapshot.ps1` is the main cost, design a lightweight preflight gate that reads ONLY fields actually required to decide:

- exact target mapping
- UICC enabled state
- airplane mode
- holder PID/identity
- pm-service state/PID/ownership
- X55 vendor state
- X55 kernel state
- crash_count
- qcrild/qcrild2 identity
- WFC golden health
- qti.cne request presence if required

Possible safe design:
- lightweight gate on every normal run
- full snapshot only:
  - on unexpected state
  - on failure
  - before a new experimental mutation
  - optionally sampled periodically for diagnostics

Do NOT remove safety gates; remove diagnostic redundancy only.

#### Candidate B — redundant repeated probes

If the same ADB/dumpsys command is run many times back-to-back, cache one observation for a very short bounded interval only when it is logically safe.

Never cache across a state-changing command.

#### Candidate C — A/P settle windows

Only study these AFTER preflight overhead is understood.

Current:
- A=20s
- P=20s

Test reductions conservatively and one at a time.

Suggested study ladder:
- 20 -> 17 -> 15 seconds
- only go lower if repeated evidence supports it

Do NOT jump directly to the shortest value.

Acceptance must include repeated success and no new state anomalies.

#### Candidate D — ordering

You may reorder read-only checks when doing so cannot alter the state observed by later safety gates.

Do not reorder state-changing commands unless you first document:
- why the original order exists
- what invariant the new order preserves
- rollback path
- exact experiment to prove equivalence

### Phase 3 — do not optimize the wrong window

The ~30s post-SIM2 POWER ON window is not currently a good latency target because:
- successful registration has been observed after >20s
- the script already exits early on HEALTHY
- reducing the cap mainly increases false failures

If detection latency itself is slow, optimize probe cost/frequency only after proving that the probe does not load or perturb telephony.

## Side-effect validation — mandatory

Before accepting any optimization, compare before/after state.

At minimum verify:

### Protected slot0
- still subId1
- still slot0
- still enabled
- identity/carrier fields unchanged
- no intentional software power cycle/reset/disable

### VOXI slot1
- subId11 returns to slot1 when appropriate
- carrierId28
- MCC/MNC 234/15
- UICC applications enabled at stable A0 and normal entry
- no residual F8/apps-disabled state

### X55 / native ownership
At native A0:
- vendor.per_mgr running
- pm-service executable correct
- pm-service sole owner of `/dev/subsys_esoc0`
- X55 ONLINE
- no stale holder

At successful frozen WFC:
- expected temporary holder is preserved
- do NOT treat this expected frozen holder as a leak

### QCRIL
- primary qcrild must not unexpectedly restart
- slot2 qcrild2 restart only where explicitly expected
- record old/new PID

### crash_count
Use current relative semantics:
- cumulative value is allowed
- controlled shutdown may increment it
- no unexplained extra increment during ONLINE reacquire/powerup

### system health
Capture and compare where practical:
- `logcat -b crash`
- recent tombstones / ANRs if available
- unexpected service crashes/restart loops
- radio/telephony exceptions
- repeated kernel subsystem failures
- ADB stability
- Wi-Fi state
- final airplane mode
- final WFC health

Do not claim "no side effects" merely because WFC works.

## UICC deep fallback rules

The UICC Apps false -> true deep fallback is not a normal optimization tool.

Only use it under the existing guarded repeated-NO_CNE condition.

It is hard-targeted to VOXI subId11.

Never use it to save a few seconds.

Never touch protected subId1/slot0.

## Known ineffective / low-value directions

Do not re-enter these randomly unless new evidence specifically justifies them:
- org.codeaurora.ims restart
- qtidataservices restart
- vendor.cnd restart
- cnd + qtidataservices restart
- random IMS resets
- random service restart combinations

The historical problem was spending time "fixing a bug" every time one recovery attempt failed. Do not repeat that mistake.

## Experiment discipline

For every behavior change:

1. create one commit containing one conceptual change
2. record baseline timing
3. run real-phone validation
4. save raw logs under a clearly named experiment directory
5. record result in a summary CSV/Markdown table
6. if any new failure class appears, revert the change immediately before exploring anything else
7. never stack multiple unvalidated optimizations
8. never rewrite the golden stable branch

For each candidate change, run:
- at least 5 quick exploratory cycles
- if clean, at least 10 consecutive validation cycles
- before calling it a candidate for merge, target 20 consecutive successful cycles across relevant start states with zero new failure class

This does not mathematically prove 100% reliability; it is an operational acceptance gate for "no observed regression".

## Required start-state matrix

Do not only test the easiest state.

Validate at least:

1. native-clean A0
2. frozen-holder state from previous successful WFC, then user turns airplane OFF
3. A0 where CNE request has reappeared while airplane OFF
4. first normal attempt succeeds
5. first attempt NO_CNE_REQUEST -> second attempt path
6. repeated NO_CNE_REQUEST -> existing guarded deep fallback, only if it naturally occurs

Do not deliberately force dangerous failure states unless necessary.

## Forbidden / out-of-scope actions

Do not:
- flash modem/firmware
- use fastboot/EDL
- modify EFS/NV
- wipe partitions/data
- alter persistent modem provisioning
- intentionally mutate protected slot0/subId1
- disable safety gates to gain speed
- kill the frozen holder after successful WFC
- shorten timeouts simply because a recent sample was fast
- use reboot as the normal optimization path
- introduce uncontrolled high-frequency service restart loops

## Local workflow

At the start of every Codex session:

1. identify current PC and repo path
2. `git fetch --all --prune`
3. checkout `wfc-latency-study-20260925`
4. pull/rebase only from that experimental branch as appropriate
5. verify golden base commit ancestry
6. inspect working tree; preserve untracked user result files
7. never delete experiment logs unless explicitly authorized
8. run syntax checks before phone mutation

At the end of every meaningful step:
- commit
- push
- write a concise experiment summary
- include exact commit SHA
- include whether phone state was mutated
- include rollback commit/command

GitHub is the source of truth because the user switches computers/accounts.

## What you are authorized to do on the phone

For this optimization project, you may run ADB/root read-only diagnostics freely.

You may perform the already validated recovery mutations needed by the existing scripts, including:
- airplane mode OFF/ON
- Wi-Fi enable
- vendor.per_mgr lifecycle used by the existing core
- existing X55 holder lifecycle
- targeted slot2 qcrild2 restart in the validated normalization path
- existing SIM2 software power cycle
- existing guarded VOXI subId11 UICC Apps false->true fallback only under its current trigger

Do not invent additional write actions merely to reduce latency without first documenting and isolating them.

## Stop conditions

Stop the experiment and restore the golden path if any of these appear:

- protected slot0 mapping/state changes
- VOXI subId11 does not return to enabled slot1 state
- primary qcrild unexpectedly restarts
- new repeated ADB loss correlated with a code change
- X55 does not return to expected state
- unexplained crash_count growth during ONLINE recovery
- new failure class not present in the baseline
- WFC success rate drops
- script parser/runtime error
- state cannot be cleanly classified by known fingerprints

## Deliverables

Do not just "make it faster".

Produce:

1. `LATENCY_BASELINE.md`
   - timing profile of current golden path
   - breakdown of where time is actually spent

2. `LATENCY_EXPERIMENTS.md`
   - each candidate optimization
   - evidence
   - pass/fail/reverted status

3. `SIDE_EFFECT_AUDIT.md`
   - phone/system effects before vs after
   - slot0 protection
   - qcrild/qcrild2 behavior
   - X55 ownership/crash behavior
   - crashes/ANRs/logcat observations

4. optimized scripts only after validation

5. final recommendation:
   - exact commit proposed for merge
   - measured median and worst-case time improvement
   - number of successful validation cycles
   - any remaining uncertainty
   - explicit rollback commit

## First concrete task

Start with instrumentation only.

Do NOT reduce A_SETTLE, P_SETTLE, 10s X55 settle, SIM OFF hold, or post-SIM maximum window yet.

Find exactly why the latest quick-normalization run still spent roughly 153 seconds inside preflight.

Instrument:
- initial full snapshot
- quick native-owner probe
- qcrild2 reacquire subphases
- normalized full snapshot

Then run the phone from a frozen-holder previous-success state and report the timing decomposition before making any behavioral optimization.
