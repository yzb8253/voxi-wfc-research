# R4a implementation audit

Date: 2026-09-24

Baseline: `baccb5c6f04605704e802be5ec73bca484beda51`

## Exact meaning of qcrild2 cold epoch

The reset primitive is exactly the already verified init operation:

```text
setprop ctl.restart vendor.qcrild2
```

It is sent once to the fixed init service whose executable is `/vendor/bin/hw/qcrild -c 2`. “Cold epoch” does not name a new vendor API. It means that this existing process-level restart satisfies both destruction and construction evidence below.

| Required property | Status / evidence |
|---|---|
| old qcrild2 exits | OBSERVABLE: old `/proc/<pid>` gone |
| old DataModule destroyed | STRUCTURAL: it is process-local, so process death removes it; destructor log is UNOBSERVABLE |
| old DSD/WDS client objects destroyed | STRUCTURAL in AP process; modem/server-side session teardown acknowledgement is UNOBSERVABLE |
| old NAH destroyed | STRUCTURAL: unique_ptr is process-local; destructor is empty and has no marker |
| old IIWlan/slot2 instance disappears | STRUCTURAL with service-process death; the brief removal may be missed by polling and is UNOBSERVABLE as a required transient |
| modem endpoint teardown | UNOBSERVABLE; no claim of modem-side session purge is made |
| new PID | OBSERVABLE and must differ from old PID |
| new DataModule cold initialization | OBSERVABLE: post-command `performDataModuleInitialization` marker |
| DSD/WDS bind/readiness | OBSERVABLE in IIWlan `IBase::debug`: both readiness fields true |
| new NAH initialization | OBSERVABLE: new-window `NetworkAvailabilityHandler`/`[NAH]constructor` marker |
| IIWlan/slot2 registered again | OBSERVABLE in HIDL service inventory and successful fixed-instance debug |
| provider serviceability | OBSERVABLE: QNS, IWlanNetworkService and IWlanDataService hosted; production debug path succeeds; no hard service error |

The gate intentionally does not claim a callback registration ID, Binder object address, modem endpoint generation number, or a fresh DSD sequence number because the ROM exposes none safely.

## Comparison with historical qcrild2 restarts

The low-level restart operation is **identical** to the previous one-shot `vendor.qcrild2` restart. R4a is not presented as a newly discovered lower reset primitive.

What differs is the frozen lifecycle composition and precondition:

| Dimension | Historical P-to-R test | R0 ownership fallback | R4a |
|---|---|---|---|
| primitive | init restart `vendor.qcrild2` | same init restart | same init restart |
| airplane/framework state | already poisoned P/F1 | holder released, owner NONE/OFFLINE transition | terrestrial A, R0 native clean |
| X55/PM precondition | X55 remained online; no R0 sequence | restart used to recover PM ownership after X55/holder handoff | X55 ONLINE, crash 0, pm-service sole owner before and after |
| producer evidence | new DataModule/NAH/DSD observed | focused on PM reacquire, not full producer readiness | PID death plus cold init, DSD/WDS, NAH, IIWlan and provider gate |
| consumer reset afterward | none | none in the fallback helper | exact R3 after producer is ready |
| hypothesis | qcrild2 alone repairs poisoned P | restore native ownership | producer-first epoch followed by new consumer epoch |

Therefore R4a's novelty is the ordered boundary `R0 -> qcrild2 epoch -> producer ready -> R3`, not the restart command. If this ordered composition fails, it is falsified; the historical restart must not be relabeled as a different mechanism.

## Safety and scope

- Fixed target: init service `vendor.qcrild2`, exact `qcrild -c 2`; no arbitrary process/service parameter.
- Primary qcrild, qtidataservices and phone PIDs must remain unchanged during producer construction.
- X55 must remain ONLINE, crash count zero, and native pm-service sole owner.
- No qtidataservices/CND/IMS restart, SIM operation, radio toggle or second producer restart exists in the producer script.
- qcrild2 is slot2/RIL-instance-1 on the AP side, but DSD/QMI/shared-QtiBus effects cannot be proven slot1-only.
- Raw device logs remain host-only.

## Audit conclusion

`R4A_IMPLEMENTATION_AUDIT=PASS` means the candidate is accurately defined and falsifiable. It does not predict success and does not convert H2 into a proven root cause.

