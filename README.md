# VOXI WFC Recovery Tools

This workspace contains the 3/3-validated status and inactive-subscription recovery tools for VOXI on the tested Xiaomi 14 Pro.

## Commands

Read-only status:

```powershell
.\voxi_wfc_research\voxi_wfc_status.ps1
```

Controlled recovery:

```powershell
.\voxi_wfc_research\voxi_wfc_recover.ps1
```

The recovery command writes only in the verified F8 condition where VOXI subId 11 is inactive, slot mapping is absent, and UICC applications are disabled. It then performs one fixed `ISub.setUiccApplicationsEnabled(true,11)` call. Healthy and active-but-unhealthy states receive no write.

See `VALIDATION_REPORT.md` for evidence and `FINAL_RUNBOOK.md` for the operating boundary.
