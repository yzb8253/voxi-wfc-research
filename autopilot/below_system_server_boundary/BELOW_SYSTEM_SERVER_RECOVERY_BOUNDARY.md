# VOXI WFC — Below-system_server Recovery Boundary

Date: 2026-09-18 (Asia/Shanghai)

Target: Xiaomi 14 Pro, wireless ADB `192.168.1.25:41201`

Mode: read-only analysis. No process/service restart, radio operation, modem SSR, setting change, property write, route change, or reboot was performed.

## Executive conclusion

The no-reboot experiments have eliminated the Android framework and the previously selected IMS/CNE userspace stack as sufficient recovery boundaries. `system_server` reconstruction restored the framework's PS/WLAN view to `IWLAN/HOME` and `mIsIwlanPreferred=true`, but did not recreate an IMS data demand. The first missing transition is below that framework state:

`QMI IMSS enable accepted` → **missing IMS DSI/QMI data-demand indication/client transition** → `cnd/CNE IMS NetworkRequest` → ePDG/XFRM → IMS registration.

The relevant state is split across three native layers:

1. `imsdatadaemon` owns an IMS-side DSI/QMI/CNE client stack (`libdsi_netctrl`, `libqmi_cci`, QTI data factory, CNE API/client).
2. `netmgrd` owns the lower data/rmnet/QMI control plane and QTI data factory/CNE interfaces.
3. `qcrild`/`qcrild -c 2` own radio HAL plus Qualcomm data, IWLAN, IMS and DSI/QMI modules. The target-slot RIL maps `vendor.qti.hardware.radio.ims`, `vendor.qti.hardware.data.connection`, `vendor.qti.hardware.data.iwlan`, `libdsi_netctrl`, `libqmi_cci`, and `libril-qc-hal-qmi` in one process.

Therefore an IMS-app/CNE-only restart cannot guarantee reconstruction of the lower QMI/DSI client graph. The smallest untested boundary is the lower data control plane (`netmgrd` followed by `imsdatadaemon` reacquisition). The strongest non-SSR boundary is the coordinated RIL pair, because the primary RIL owns shared Xiaomi/QtiBus initialization while the secondary RIL owns the target slot.

## Confirmed inherited state

- Full userspace sequence already tested: `imsqmidaemon` → `imsdatadaemon` → `vendor.cnd` → `.qtidataservices` → `org.codeaurora.ims` → `com.android.phone`.
- Result: no new native IMS demand, no qti.cne IMS request, no UDP/4500, no XFRM, no IMS registration, no WFC.
- `system_server` restart rebuilt ConnectivityService and telephony services.
- It restored target-slot PS/WLAN to `IWLAN/HOME` and `mIsIwlanPreferred=true`.
- It did not create an IMS request in qti.cne/DNC and did not recover ePDG/XFRM/IMS/WFC through 180 seconds.
- No qcrild, netmgrd, DPM or modem/SSR reset was part of those experiments.

## Successful full-lifecycle sequence

The saved successful reboot/enable log provides this observable order:

1. Cold boot starts primary RIL0 and secondary RIL1. Both initially report `qcril_data_get_dds_sub_info: DSD Client unavailable` at 22:27:14, showing that the RIL/data client graph is being constructed asynchronously.
2. RIL1 later reports the target UICC application ready.
3. At 22:28:42.157–22:28:42.159, RIL1 calls `qcril_qmi_radio_config_imss_set_ims_new_config` and successfully sends the IMSS QMI request.
4. At 22:28:44.863 and 22:28:44.866, RIL1 receives successful `qcril_qmi_imss_set_ims_service_enable_config` responses (`ril_err=0`, `qmi res=0`).
5. At 22:29:01.577, qti.cne's IMS `NetworkRequest` for subId 11 appears and reaches TelephonyNetworkFactory/DNC.
6. The request attaches to the Vodafone UK IMS profile, followed by ePDG/XFRM and IMS registration activity.

The first boot-only prerequisite is not an Android `mIsIwlanPreferred` flag. It is the cold reconstruction of RIL/QMI/DSD/DSI clients before the later IMSS enable acknowledgement can produce an IMS data demand.

## Failed soft-lifecycle comparison

After the full userspace stack and `system_server` recovery:

- Framework state was valid: `IWLAN/HOME`, `mIsIwlanPreferred=true`, MMTEL READY.
- The RIL/modem accepted IMS enable configuration: the saved system_server experiment contains successful IMSS enable responses at 16:35:25.692 and 16:35:25.706.
- No subsequent IMS data demand appeared in `imsdatadaemon`/`cnd`/qti.cne.
- Consequently no qti.cne IMS request, DNC request, ePDG, XFRM or IMS registration followed.

This rules out “framework never requested IMS enable” as the primary explanation. The earliest observable divergence is immediately after the successful IMSS enable response: the modem/native data side does not emit or reconstruct the IMS data-call demand that would feed `imsdatadaemon`/CNE.

## Current live read-only finding

During this analysis, the initial process snapshot showed both RIL processes. A later read-only snapshot showed the primary `qcrild` absent and only `qcrild -c 2` present. The secondary process then repeatedly aborted approximately every 101 seconds:

- 20:23:11: PID 1965 aborts in `QtiBusSocketTransport::serverDied()`.
- 20:24:52: replacement PID 4673 aborts in `QtiBusSocketTransport::clientLoop()`.
- 20:26:33: replacement PID 5220 aborts in the same QtiBus monitor path.
- Each replacement logs `qcril_data_get_dds_sub_info: DSD Client unavailable`.
- Tombstone backtraces show `SIGABRT` in the `QtiBus-MON` thread, not a modem SSR.
- Xiaomi RIL logs explicitly state that Xiaomi QMI/common/MBN work is initialized only in the primary RIL.

Inference: the missing primary RIL was the QtiBus/shared-QMI side needed by the secondary RIL. Its absence causes the target-slot RIL to lose its server and crash-loop. This is a newly observed live fault and must not be silently conflated with the earlier system_server experiment, where both RILs were still present. It does, however, independently prove that the primary and target-slot RILs are coupled and that a target-slot-only RIL restart is not a complete boundary on this ROM.

Because the current live state is no longer a stable two-RIL baseline, no lower-layer experiment should be interpreted unless a precheck first establishes the intended baseline or explicitly defines restoration of the primary RIL as the experiment.

## Component boundary map

| Layer | Exact process/service | Confirmed responsibility on this ROM | Already restarted? |
|---|---|---|---|
| IMS control QMI | `vendor.imsqmidaemon` / `/vendor/bin/imsqmidaemon` | QMI CCI/services for IMS control | Yes; insufficient |
| IMS data client | `vendor.imsdatadaemon` / `/vendor/bin/imsdatadaemon` | DSI, QMI, QTI data factory, CNE API/client | Yes; insufficient alone/in userspace sequence |
| CNE native | `vendor.cnd` / `/vendor/bin/cnd` | Native CNE policy/callback path | Yes; insufficient |
| Data control plane | `vendor.netmgrd` / `/vendor/bin/netmgrd` | rmnet, QMI data control, QTI data factory/CNE interfaces | No |
| Data port mapping | `dpmQmiMgr` / `/vendor/bin/dpmQmiMgr` | QMI Data Port Mapper HAL | No |
| Primary radio HAL | `vendor.qcrild` / `/vendor/bin/hw/qcrild` | Slot0 HAL plus shared QtiBus/Xiaomi QMI/common/MBN initialization | No; currently absent in live snapshot |
| Target radio HAL | `vendor.qcrild2` / `/vendor/bin/hw/qcrild -c 2` | Slot1 IRadio, IMS, data connection, IWLAN, DSI/QMI modules | No; currently QtiBus crash-looping |
| Modem subsystem | `esoc0` at `/sys/devices/platform/soc/soc:qcom,mdm0/subsys10` | External MDM/baseband SSR boundary; state observed `ONLINE` | No |

`dpmQmiMgr` alone is not the preferred first test: it is below multiple data clients, can disturb every modem data port, and there is no evidence that merely rebinding the DPM HAL will regenerate the missing IMS demand. It should be grouped with a broader data-plane test only if M1 shows that netmgr/DSI cannot reacquire the modem path.

## Candidate M1 — coordinated lower data-client reconstruction

**Exact boundary:** `vendor.netmgrd` (`/vendor/bin/netmgrd`), then after it is stable, `vendor.imsdatadaemon` (`/vendor/bin/imsdatadaemon`) so the IMS process reacquires DSI/QMI against a freshly initialized netmgr/rmnet control plane. Do not include qcrild, radio power, DPM, CNE app, or modem SSR in the first M1 definition.

**Why this is the smallest new boundary:** `imsdatadaemon` alone was already disproved, but `netmgrd` was not restarted. Their maps meet at QMI/QTI data-factory/CNE interfaces, and only `imsdatadaemon` holds the IMS-side `libdsi_netctrl` client. A coordinated reconstruction tests the missing DSI/QMI client handshake without cycling the radio HAL or modem firmware.

**Expected effect:** possible re-creation of the IMS data demand and CNE request if stale netmgr/DSI client state is the blocker.

**Cellular impact:** all active cellular data bearers may drop briefly; this is not safely slot1-scoped.

**Dual-SIM impact:** both slots share netmgr/rmnet; voice/RF should remain up, but packet data for both SIMs can be disrupted.

**Airplane-mode equivalence:** no. RF and modem registration are not intentionally powered down.

**Network search:** normally no full PLMN search, but packet data reattachment/setup is expected.

**VPN impact:** a VPN whose underlay is Wi-Fi should normally remain, but routes/network validation may flap; a cellular-underlay VPN will drop.

**Brick/EFS risk:** low persistent-storage risk. Operational risk is medium because netmgr is shared and a failed restart can leave rmnet/data unavailable until a broader radio recovery or reboot.

**Current-state caveat:** do not run M1 while primary qcrild is absent and qcrild2 is crash-looping; the result would not test the intended boundary.

## Candidate M2 — coordinated RIL/radio-HAL reconstruction

**Exact boundary:** primary `vendor.qcrild` first, then target `vendor.qcrild2` (`qcrild -c 2`) as a coordinated RIL-pair recovery. A target-only `qcrild2` restart is not sufficient on the currently observed ROM state because it depends on the primary QtiBus/shared-QMI server and repeatedly aborts when that server is absent.

**Why it is the strongest non-SSR candidate:** the target RIL process directly hosts radio IMS, data connection, IWLAN, DSI/QMI and the large `libril-qc-hal-qmi` state machine. The primary RIL performs shared Xiaomi QMI/common/MBN initialization. Rebuilding both processes is the narrowest boundary that reconstructs all these clients while leaving modem firmware running.

**Expected effect:** re-register radio HAL services and callbacks, rebuild RIL QMI/DSD/DSI clients, replay IMS/IWLAN configuration, and potentially restore the missing IMS data demand without modem SSR.

**Cellular impact:** definite short radio-service outage; calls and cellular data can be interrupted.

**Dual-SIM impact:** high. The coordinated pair affects both slots; slot0 cannot be guaranteed untouched even if slot1 is the target.

**Airplane-mode equivalence:** no. The modem is not intentionally powered off, but Android will observe `RADIO_NOT_AVAILABLE`/HAL death and rebind; user-visible interruption can resemble a radio toggle.

**Network search:** likely. SIM/radio callbacks, attach state and registration may be replayed; both slots may re-register.

**VPN impact:** Wi-Fi/TUN processes are not intentionally restarted, but route/default-network churn can interrupt the tunnel; ePDG will be rebuilt if recovery works.

**Brick/EFS risk:** low brick risk and low but non-zero persistent-modem risk. Primary RIL startup re-runs PDC/MBN/NV inspection and possibly configuration checks, so this is materially riskier than M1 even without explicit NV writes.

## Candidate M3 — external modem SSR

**Exact boundary:** external modem subsystem `esoc0`, exposed at `/sys/devices/platform/soc/soc:qcom,mdm0/subsys10` and observed `ONLINE`. This is the baseband/MDM subsystem restart boundary, not an AP/Android reboot.

**Expected effect:** reset modem firmware and all QMI services/clients, force RIL, netmgr, DPM, IMS-QMI/data and IWLAN paths to reconnect, and most closely reproduce the radio half of a successful full reboot.

**Cellular impact:** complete cellular outage during SSR.

**Dual-SIM impact:** complete impact to both SIMs because they share the external modem.

**Airplane-mode equivalence:** no. It is deeper than airplane mode: modem firmware is restarted rather than only RF/service policy being toggled.

**Network search:** mandatory full modem boot, SIM discovery, network registration and data reattachment.

**VPN impact:** Wi-Fi/TUN userspace may remain alive, but IMS/ePDG tunnels are destroyed; network validation/routing can change during reattachment.

**Brick/EFS risk:** normal SSR is designed to recover, so permanent damage is not expected, but operational risk is high. Manual/repeated SSR can leave the baseband unavailable, trigger watchdog/AP reboot, or fail during modem persistent-state work. EFS/NV corruption risk is low but not zero and is higher than M1/M2.

## Recommended next controlled experiment

**Preferred boundary: M2, specifically restoration/reconstruction of the coordinated RIL pair, not target-only qcrild2.**

Reason: the current live evidence contains an objective primary-RIL/QtiBus failure and a qcrild2 crash loop. Testing netmgr/IMS data clients while their upstream RIL/QtiBus provider is absent would be uninterpretable. The next experiment should first be written as a separate, explicit safety-controlled protocol that:

1. Captures the current crash-loop and slot mappings.
2. Treats primary-RIL restoration and target-RIL stabilization as the only write boundary.
3. Expects both slots to lose radio service and therefore does not claim slot0 isolation.
4. Observes QtiBus stability, disappearance of `DSD Client unavailable`, successful IMSS replay, first IMS data demand, CNE request, ePDG/XFRM and WFC.
5. Stops without M3 if the RIL pair stabilizes but no IMS demand appears.

If a fresh precheck instead finds both RILs stably present again without intervention, M1 becomes the preferred smaller experiment before M2. M3 remains the last resort.

## Confidence

- Boundary below framework/system_server: **HIGH**.
- First missing transition after IMSS enable and before CNE request: **HIGH**.
- M1 recovering the path: **MEDIUM-LOW** (smallest untested data-plane boundary, but IMS daemon restart alone already failed).
- M2 recovering the path: **MEDIUM-HIGH** (directly rebuilds the proven hosting process and current failed QtiBus relationship).
- M3 approximating reboot's radio-side recovery: **HIGH**, with the highest operational risk.

## Stop condition

Analysis only. No candidate was executed.
