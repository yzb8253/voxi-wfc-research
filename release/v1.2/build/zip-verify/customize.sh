#!/system/bin/sh

SKIPMOUNT=true
PROPFILE=false
POSTFSDATA=false
LATESTARTSERVICE=true

ui_print "*******************************"
ui_print " VOXI WFC Recovery v1.2"
ui_print "*******************************"

ABI="$(getprop ro.product.cpu.abi)"
case "$ABI" in
  arm64-v8a) ;;
  *) abort "Unsupported ABI: $ABI (arm64-v8a required)" ;;
esac

if [ -z "$MAGISK_VER" ] && [ -z "$MAGISK_VER_CODE" ]; then
  abort "Magisk environment not detected"
fi

for FILE in \
  module.prop \
  action.sh \
  service.sh \
  bin/wfcctl.sh \
  bin/wfc-deep-recover.sh \
  lib/wfc-probe.jar \
  lib/wfc-recovery-helper.jar \
  lib/wfc-deep-remove-helper.jar \
  README.md; do
  [ -f "$MODPATH/$FILE" ] || abort "Missing module file: $FILE"
done

mkdir -p /data/adb/voxi-wfc-recovery/logs
mkdir -p /data/adb/voxi-wfc-recovery/logs/boot
mkdir -p /data/adb/voxi-wfc-recovery/state
chmod 0700 /data/adb/voxi-wfc-recovery
chmod 0700 /data/adb/voxi-wfc-recovery/logs
chmod 0700 /data/adb/voxi-wfc-recovery/logs/boot
chmod 0700 /data/adb/voxi-wfc-recovery/state
if [ ! -f /data/adb/voxi-wfc-recovery/config.conf ]; then
  printf 'AUTO_RECOVER_BOOT=0\n' > /data/adb/voxi-wfc-recovery/config.conf
fi
chmod 0600 /data/adb/voxi-wfc-recovery/config.conf

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/customize.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/bin/wfcctl.sh" 0 0 0755
set_perm "$MODPATH/bin/wfc-deep-recover.sh" 0 0 0755
set_perm "$MODPATH/lib/wfc-probe.jar" 0 0 0644
set_perm "$MODPATH/lib/wfc-recovery-helper.jar" 0 0 0644
set_perm "$MODPATH/lib/wfc-deep-remove-helper.jar" 0 0 0644

ui_print "Boot Auto Recover is installed but disabled by default."
ui_print "The boot service runs once and exits; no daemon or periodic watcher is installed."
ui_print "Use the Magisk Action button or: su -c '<module>/bin/wfcctl.sh status'"
