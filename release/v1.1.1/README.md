# VOXI WFC Recovery v1.1.1 Release

Install `VOXI-WFC-Recovery-v1.1.1.zip` through Magisk. The module is fixed to the validated Xiaomi 14 Pro dual-SIM identity documented in `module/README.md`.

This hotfix replaces the incompatible Toybox `flock` file-descriptor lock with an atomic `mkdir` lock. Safe Recover, Deep Recover, the four-condition direct health rule, and every dual-SIM safety gate are unchanged from v1.1.

The corrected v1.1 script was validated on the target device from a preserved strict F1 scene. One Deep Recover reached F8 after one fixed `false,11`, performed one fixed `true,11`, restored direct WFC health in 19 seconds, and remained healthy in 7/7 samples over approximately 79 seconds. China Telecom slot0 remained protected.

The v1.1.1 ZIP was built but was not installed automatically.
