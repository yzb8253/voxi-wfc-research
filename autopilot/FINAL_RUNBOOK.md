# Final Runbook

STATUS: VALIDATED 3/3 PASS

## Read-Only Status

```powershell
.\voxi_wfc_research\voxi_wfc_status.ps1
```

Healthy means `goldenStrong=true`: REGISTERED(2), WLAN(2), VOICE/IWLAN available, Wi-Fi Calling available, and an active subId11 IMS IWLAN NetworkAgent.

## Controlled Recovery

```powershell
.\voxi_wfc_research\voxi_wfc_recover.ps1
```

- A, inactive/apps disabled: after all hard-coded VOXI and protected-slot0 gates pass, execute exactly one `ISub.setUiccApplicationsEnabled(true,11)` and require stable GOLDEN_STRONG.
- B, already healthy: print status and execute no write.
- C, subscription active but WFC abnormal: print status and `FAILURE_CLASS`, then stop without false, resetIms, or another write.

The tools never change airplane mode, radio, CarrierConfig, settings, IMS enablement, or processes. `ITelephony.resetIms(1)` is excluded from automatic recovery.
