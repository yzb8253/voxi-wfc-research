# R4b qtidataservices restart primitive audit

Date: 2026-09-24

Status: design only; no primitive was executed. Phone writes: **0**.

## Candidate comparison

| Candidate | Current-ROM support | Lifecycle coverage | Determinism / recovery | Verdict |
|---|---|---|---|---|
| `ctl.restart <qtidataservices>` | No matching init service, rc stanza or `init.svc` property exists | none | invalid target | REJECT |
| exact verified PID `TERM`, then ActivityManager recreation | Previously observed on this ROM | complete shared Java process/static epoch | persistent process was re-added and rebound automatically | **SELECTED FOR FUTURE DESIGN** |
| `am force-stop` a package | Package-manager mechanism exists, but the process is shared by three packages | changes stopped-package state; may suppress automatic restart and does not cleanly name the shared epoch | broader and recovery semantics are wrong for a persistent shared process | REJECT |
| unbind/rebind one IWLAN service | framework can rebind | only one Service/provider object; process statics and other shared providers survive | R3 already exercised this incomplete boundary | REJECT |
| external `IIWlan.setResponseFunctions` | HIDL method exists | replaces production callback but does not reset all Java/provider state | risks callback theft; prohibited and incomplete | REJECT |
| component stop/start or broadcast | no verified current-ROM API that atomically resets all hosted providers | partial/unknown | not deterministic | REJECT |

## Selected future primitive

The smallest verified complete provider-epoch primitive is:

1. resolve exactly one live `.qtidataservices` process dynamically;
2. verify cmdline `.qtidataservices`, UID 10104, exact SELinux domain, zygote parent, ActivityManager persistent record, and the expected three-package process list;
3. record its PID as `OldQtiDataServicesPid`;
4. send **one** `TERM` to that exact PID;
5. do not use `killall`, `pkill`, SIGKILL, force-stop, package clear, service stop/start, or a second signal;
6. let ActivityManager recreate the persistent process and then evaluate `PROVIDER_READY`.

This is **ActivityManager recreation, not init recreation**. The terminology is important: qcrild2 is an init service; `.qtidataservices` is a zygote child managed as a persistent Android application process.

Historical current-ROM evidence is precise: old PID 3170 died, ActivityManager scheduled the co-hosted services, logged `Re-adding persistent process`, started PID 25920, rebound the process, and recreated DataService, NetworkService and QualifiedNetworksService. That run did not recover WFC, but it validates the primitive's lifecycle semantics. It does not test or falsify R4b's producer -> provider -> consumer composition.

## Expected direct and indirect scope

| Component/state | Expected from one exact TERM | Required future verification |
|---|---|---|
| qtidataservices PID/static Java state | destroyed and recreated | old gone; new different PID and correct identity |
| QNS/NetworkService/DataService/CneApp/CACert | interrupted and recreated | all hosted records in new PID |
| framework ANM/NRM/DNC bindings | transient disconnect/rebind to new endpoints | observed disconnect/reconnect; phone PID unchanged until R3 |
| production IIWlan callbacks | old binder dies; new proxy installs new callbacks | new slot2 proxy/connect logs; no external client |
| qcrild/qcrild2 | **must not be restarted by this stage** | both PIDs unchanged from PRODUCER_READY |
| X55 / PM ownership | no intended effect | X55 ONLINE, crash_count 0, pm-service sole owner, no holder |
| native `vendor.cnd` | process must remain alive; Java CneApp reconnects | cnd PID unchanged and service healthy |
| `org.codeaurora.ims` | no intended process restart | PID unchanged |
| slot0 | shared QNS/IWLAN/CNE outage and callback rebinding are unavoidable | mapping/subscription remain correct; provider records for both slots return |
| default/active data and subscription mapping | no intentional write | IDs/mappings unchanged; any change is scope violation |

The prior isolated restart preserved slot0 mapping and normal network/VPN state, but future R4b must not assume that result. All scope fields are rechecked and any unexpected process, mapping, X55 or PM change invalidates the stage.

## Risks

- It is not slot1 scoped: the process hosts both-slot QNS, IWLAN NetworkService/DataService and CNE Java endpoints.
- Both slots briefly lose WLAN NetworkService/DataService bindings.
- CNE request trackers and CA-cert service also restart.
- `setResponseFunctions` is global per `IIWlan` instance; provider readiness must prove the production callback was reinstalled, never install a second test callback.
- The QNS constructor queries before registering for changes. The current cache query limits the lost-indication window, but an internal indication sequence number is not exposed.

## Fail-closed preconditions

The future primitive is forbidden unless:

- R0 and PRODUCER_READY already passed;
- exactly one expected `.qtidataservices` PID exists;
- all identity and hosted-package checks match;
- qcrild/qcrild2, X55, PM ownership, crash count and target mapping are clean;
- there is no unknown provider/HIDL client and no process crash loop;
- this series has not already used its one qtidataservices reset for the current cycle.

Any mismatch is `R4B_PROVIDER_SCOPE_PRECHECK_FAIL`, with no signal and no R3.

## Audit verdict

`R4B_RESTART_PRIMITIVE = EXACT_PID_TERM_PLUS_ACTIVITY_MANAGER_RECREATE`

It is the minimum **verified complete** qtidataservices process epoch on this ROM. It is high impact within telephony data services, but narrower than cnd, IMS, system_server or AP reboot and does not directly alter SIM, subscription, radio power, X55 or modem firmware.
