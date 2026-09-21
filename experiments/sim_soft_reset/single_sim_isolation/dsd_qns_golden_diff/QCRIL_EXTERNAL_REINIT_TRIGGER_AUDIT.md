# QCRIL External Reinit Trigger Audit

Date: 2026-09-21

## Scope

Static analysis only. No HIDL business method, OEM hook, socket command, DIAG command, property write, process restart, or phone-state operation was executed.

The audit asks whether an existing external control surface can make fixed qcrild2 (`/vendor/bin/hw/qcrild -c 2`, RIL instance 1, `IIWlan/slot2`) execute the known minimum internal sequence on its own framework threads:

1. `DSDModemEndPoint::sendAPAssistIWLANSupportedSync()`
2. `DSDModemEndPoint::registerForSystemStatusSync()`
3. `DataModule::initializeIWLAN()`
4. `DSDModemEndPoint::generateDsdSystemStatusInd()`

Source correlation uses Qualcomm revision `36fc163a534963a5b3af52186af5efcc63401ad2` and current-ROM exported service inventories. Current-ROM evidence confirms `IQtiOemHook/oemhook0`, `oemhook1`, `IIWlan/slot1`, and `IIWlan/slot2`. The protected current qcrild2 implementation binary was not bypass-read.

## Candidate 1: IIWlan callback handshake

External interface:

`vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot2.setResponseFunctions(response, indication)`

Exact call chain:

`IIWlan::setResponseFunctions`
`-> IWlanImpl::setResponseFunctions_nolock`
`-> replace mIWlanResponse/mIWlanIndication and death recipient`
`-> IWLANCapabilityHandshake(true)`
`-> Message::dispatch()`
`-> DataModule mMessageHandler`
`-> DataModule::handleIWLANCapabilityHandshake()`
`-> DataModule::initializeIWLAN()`
`-> registerForAPAsstIWlanIndsSync(true)`
`-> replace NetworkAvailabilityHandler unique_ptr`
`-> replay mCachedSystemStatus`
`-> datactlEnableIWlan()`

Runs on DataModule looper: YES.

Recreates NAH: YES.

Refreshes DSD status: NO. It never calls `generateDsdSystemStatusInd()` or `registerForSystemStatusSync()`.

Touches modem reset/radio/SIM: no reset or power operation; it sends AP-assist indication registration and enables IWLAN through datactl.

Risk: HIGH. A second client replaces the production callbacks and death recipient. It can break qtidataservices/QNS ownership and is explicitly prohibited. It is incomplete for the known fault.

Verdict: closed partial chain, rejected as an experiment candidate.

Related methods do not close the gap:

- `iwlanDisabled()` dispatches `IWLANCapabilityHandshake(false)`, deregisters AP-assist indications, destroys NAH, and disables IWLAN. It has no safe re-enable/fresh-status transaction.
- `getAllQualifiedNetworks()` reads the cache only.
- `IBase::debug()` only calls `getDataModule().dump(fd)`.
- The interface has no reset, refresh, reinit, DSD-status, or standalone capability-handshake method.

## Candidate 2: DSD endpoint recovery/SSR path

External input:

A real QMI DSD endpoint transition from non-operational to operational.

Exact call chain:

`QMI endpoint lifecycle`
`-> EndpointStatusIndMessage(DSDModemEndPoint_ENDPOINT_STATUS_IND)`
`-> DataModule mMessageHandler`
`-> DataModule::handleQmiDsdEndpointStatusIndMessage()`
`-> mInitTracker.setDsdServiceReady(true)`
`-> DataModule::performDataModuleInitialization()`
`-> post-SSR branch`
`-> setV2Capabilities()`
`-> generateDsdSystemStatusInd()`
`-> registerForSystemStatusSync()`
`-> sendAPAssistIWLANSupportedSync()`
`-> datactlEnableIWlan()`
`-> registerForAPAsstIWlanIndsSync(true)`

Runs on DataModule looper: YES.

Recreates NAH: NO. The post-SSR branch retains the existing handler and does not call `initializeIWLAN()`.

Refreshes DSD status: YES.

Touches modem reset/radio/SIM: the handler itself does not request them, but no narrow external API can synthesize the endpoint transition. Deliberately inducing it enters a prohibited DSD/modem service-loss or SSR boundary.

Risk: HIGH.

Verdict: closed partial chain, not an independently callable safe trigger.

## Qualcomm OEM Hook / QcRilHook

Current ROM exposes fixed `IQtiOemHook/oemhook0` and `oemhook1`. The interface contains only `setCallback()` and `oemHookRawRequest()`.

The parser validates the Qualcomm header and command ID, then uses a fixed switch table or maps the ID through `qcril_qmi_oem_eventlist` and `qcril_dispatch_event()`. The audited tables include UICC, PDC/MBN, NAS, data-enable/roaming, data-subscription, dormancy, eMBMS, and IMS-presence operations. They contain no IWLAN, AP-assist, DSD-status generation, DataModule reinit, NAH reset, or `IWLANCapabilityHandshake` request.

`HOOK_DATA_GO_DORMANT`, `HOOK_SET_IS_DATA_ENABLED`, and `HOOK_SET_DATA_SUBSCRIPTION` terminate in unrelated handlers. Similar names do not reach the target functions.

Result: no closed OEM Hook/QcRilHook chain.

## HIDL/AIDL control surfaces

The source-correlated `IIWlan@1.0` methods are callback registration, data-call setup/deactivation/list, registration-state read, qualified-network cache read, acknowledgement, and `iwlanDisabled()`.

No debug/test/vendor method exposes AP-assist capability, DSD indication registration, fresh system-status generation, or DataModule reinitialization. No audited AIDL interface maps to the four internal methods.

Result: no complete HIDL/AIDL trigger.

## Unix/local sockets and QtiBus

The legacy OEM socket and HIDL OEM service share the same fixed command/event dispatcher. An unknown command is request-not-supported; the socket is not an arbitrary MessageBus injector.

QtiBus uses `/dev/socket/qmux_radio/ril_ipc`, but DataModule registers only `DDSSwitchIPCMessage` and `IAInfoIPCMessage` constructors for remote transport. Neither reaches the target lifecycle. `IWLANCapabilityHandshake` and endpoint sync messages are process-local and are not registered for QtiBus deserialization.

The settings daemon command socket has no command registration linked to DataModule/IWLAN/DSD reinitialization.

Result: no closed socket path.

## DIAG

The data sources reference DIAG for logging/LSM support. No DIAG packet handler or command registration reaches DataModule, `IWLANCapabilityHandshake`, `initializeIWLAN()`, AP-assist sync messages, or `generateDsdSystemStatusInd()`.

Result: no QCRIL DataModule/IWLAN diagnostic command. Modem DIAG/NV/RF controls are outside scope.

## Android properties and init

Relevant properties are startup/configuration reads such as `ro.telephony.iwlan_operation_mode`, retry controls, and data-profile behavior. No property-change callback dispatches a DataModule reinit message.

Init rules define qcrild/qcrild2 services and a board-specific startup assignment for legacy IWLAN mode. No property trigger reinitializes DSD/AP-assist or NAH without restarting a process.

Result: no property/init trigger.

## Conclusion

No existing external trigger closes:

`external input -> parser/dispatcher -> DataModule looper -> capability/status registration -> NAH recreation -> fresh DSD status`

The two partial paths split the needed behavior:

- `IIWlan.setResponseFunctions()` recreates NAH but does not fetch fresh status and replaces production callbacks.
- DSD endpoint recovery refreshes DSD registration/status but does not recreate NAH and cannot be safely induced without entering an SSR/service-loss boundary.

`NO_EXISTING_EXTERNAL_TRIGGER`

## Minimum alternative

The narrowest alternative is a vendor-built, compile-time fixed `IIWlan/slot2` diagnostic method that dispatches one new `SolicitedMessage` to the existing DataModule looper. Its handler would execute exactly the four audited calls once, accept no target or numeric arguments, and enforce boot-ID/invocation-count guards.

This is a source-level vendor rebuild/instrumentation requirement, not a runtime injection plan. It must not be implemented by replacing callbacks, ptrace, function-pointer calls, SELinux changes, or a generic OEM-hook command.

Phone writes: 0.
