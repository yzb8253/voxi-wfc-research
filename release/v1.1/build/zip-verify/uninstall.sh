#!/system/bin/sh

# External data belongs only to this module. Never touch telephony state here.
rm -rf /data/adb/voxi-wfc-recovery/logs
rm -rf /data/adb/voxi-wfc-recovery/state
rmdir /data/adb/voxi-wfc-recovery 2>/dev/null
exit 0
