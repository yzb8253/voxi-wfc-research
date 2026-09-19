# VOXI WFC Validation Report

VALIDATION: 3/3 PASS

| Cycle | Persistent F8 | First GOLDEN_STRONG | Continuous healthy | Replacement CNE request | IMS NetworkAgent | Slot0 impact |
|---|---:|---:|---:|---:|---:|---:|
| 1 | Yes | 10 s | 300 s | 360 | 102 | None |
| 2 | Yes | 18 s | 302 s | 374 | 103 | None |
| 3 | Yes | 37 s | 302 s | 380 | 104 | None |

Every cycle began at GOLDEN_STRONG with all safety gates passing, used exactly one fixed false call to produce persistent F8, and exactly one fixed true call to recover. Every final state had REGISTERED(2), WLAN(2), VOICE/IWLAN available, Wi-Fi Calling available, and an active IMS IWLAN NetworkAgent.

China Telecom slot0/subId1/MCCMNC46011 remained active and correctly mapped throughout. No cycle used resetIms, IMS enable/disable, airplane mode, reboot, physical SIM removal, radio reset, CarrierConfig writes, or process termination.

The validated automatic repair is true-only recovery from verified inactive/apps-disabled F8. No automatic repair has been approved for active-subscription WFC failures.
