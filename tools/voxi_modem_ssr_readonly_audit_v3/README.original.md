# VOXI modem SSR topology audit v3

Pure read-only follow-up.

v2 completed the device-side capture phase, then crashed only in local PowerShell
summary post-processing because `.Groups` was called on a Regex MatchCollection.
No modem/radio/SIM write occurred.

v3 fixes that local summary parser and keeps the same read-only topology checks.

Run:

    .\run_modem_ssr_topology_audit_v3.ps1

Send back:
- SUMMARY.txt
- remoteproc_detail.txt
- esoc_detail.txt
- subsys_detail.txt
- kernel_history.txt
