# Slot mapping capture

This directory contains a read-only, privacy-filtered mapping of Android subscription/phone identifiers to Radio and Qualcomm UIM instances.

Run from PowerShell:

```powershell
.\collect_slot_mapping.ps1 -Serial 192.168.1.25:42319 -Adb C:\Users\TT\Desktop\platform-tools\adb.exe
```

The collector never changes phone state. ICCIDs are extracted from the active subscription records only in process memory and immediately hashed with SHA-256. Saved dumps replace ICCID, card string, phone number, IMEI, MEID, and other long numeric identifiers.
