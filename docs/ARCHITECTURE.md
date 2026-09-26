# Architecture

## Recovery stack

```text
Windows launcher / wrapper
  -> ADB + root safety gates
  -> X55 ownership and power lifecycle
  -> Qualcomm RIL/QMI data state
  -> slot-1 SIM/UICC lifecycle
  -> QNS / IWLAN qualification
  -> qti.cne IMS NetworkRequest
  -> Android DataNetworkController / IMS NetworkAgent
  -> ePDG + IPsec/XFRM
  -> IMS REGISTERED over WLAN
  -> direct WFC availability
```

## Major boundaries

### Host orchestration

PowerShell 5.1 scripts classify state, enforce exact-device gates, record timestamps, perform bounded writes and preserve raw evidence. CMD files are launchers only.

### Native X55 lifecycle

`vendor.per_mgr`, `pm-service`, `/dev/subsys_esoc0`, holder processes, X55 ONLINE/OFFLINE state, PON success and crash count define the modem ownership epoch. Ownership must be unambiguous before writes.

### Radio and data producer

`vendor.qcrild`/`vendor.qcrild2`, QMI data services and the IIWlan producer expose modem-facing data availability. A healthy process is not proof that an IMS demand has been regenerated.

### Provider and framework consumer

`qtidataservices`/IWlanProxy and QualifiedNetworksService bridge qualified networks into Android. ANM, NRM, SST and DNC consume this state. Process/provider epochs and initial-query replay have been recurring research boundaries.

### IMS and WFC

Qualcomm IMS, MMTEL, CNE, an IMS NetworkAgent, ePDG and XFRM support registration. Only the four-part direct health predicate declares success.

## State labels

Repository experiments use labels such as `A0_READY`, `P0_READY`, strict F1, F8, frozen residue and healthy freeze. Their definitions are experiment-specific. Never reuse a label as a write authorization unless the exact classifier, schema and commit are cited.

## Evidence layers

1. Direct API health: authoritative success.
2. Current connectivity table: authoritative for current CNE request identity in audited experiments.
3. Process/owner/state: lifecycle safety.
4. Logs and historical request tables: diagnostic only; they can contain stale events.
