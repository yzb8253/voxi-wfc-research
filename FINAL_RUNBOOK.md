# VOXI WFC Final Runbook

STATUS: VALIDATED 3/3 PASS

## Status

Run `.\voxi_wfc_research\voxi_wfc_status.ps1`.

Accept healthy state only when `goldenStrong=true`, which requires direct IMS REGISTERED(2), WLAN(2), VOICE/IWLAN availability, Wi-Fi Calling availability, and an active IMS IWLAN NetworkAgent.

## Recovery

Run `.\voxi_wfc_research\voxi_wfc_recover.ps1`.

- A: If VOXI subId 11 is inactive, its slot mapping is lost, and UICC applications are disabled, the tool revalidates VOXI identity and China Telecom slot0, then performs exactly one `ISub.setUiccApplicationsEnabled(true,11)`.
- B: If WFC is already healthy, the tool performs no write.
- C: If subscription is active but WFC is abnormal, the tool prints the complete diagnostic state and `FAILURE_CLASS`, performs no false call, and does not call resetIms.

The recovery tool is fixed to the tested device serial, VOXI subId 11/slot1/phoneId1/carrierId28/MCCMNC23415, and protected China Telecom slot0/subId1/MCCMNC46011. Stop and revalidate the tooling if those identities change.

## Excluded Actions

Automatic recovery does not toggle airplane mode, change default data, reset radio, modify CarrierConfig or settings, kill processes, reboot, or call IMS reset/enable/disable.
