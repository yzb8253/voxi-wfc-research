#!/system/bin/sh

SKIPMOUNT=true
PROPFILE=false
POSTFSDATA=false
LATESTARTSERVICE=true

ui_print "********************************"
ui_print " VOXI WFC Auto Recover v0.1.0"
ui_print "********************************"

[ "$(getprop ro.product.cpu.abi)" = arm64-v8a ] || abort "arm64-v8a is required"

for FILE in module.prop service.sh action.sh bin/voxi-auto-daemon.sh bin/voxi-autoctl.sh lib/wfc-probe.jar lib/wfc-recovery-helper.jar; do
  [ -f "$MODPATH/$FILE" ] || abort "Missing module file: $FILE"
done

DATA=/data/adb/voxi-wfc-auto-recover
mkdir -p "$DATA/logs" "$DATA/state" || abort "Unable to create module data directory"
if [ ! -e "$DATA/config.conf" ]; then
  {
    echo 'ENABLED=0'
    echo 'POLL_SECONDS=60'
    echo 'FAILURE_CONFIRMATIONS=2'
    echo 'RECOVERY_COOLDOWN_SECONDS=21600'
    echo 'MAX_RECOVERIES_PER_BOOT=1'
  } > "$DATA/config.conf"
  ui_print "Created default configuration (automatic recovery disabled)."
else
  ui_print "Preserved existing configuration."
fi
chmod 0700 "$DATA" "$DATA/logs" "$DATA/state"
chmod 0600 "$DATA/config.conf"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/customize.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/bin/voxi-auto-daemon.sh" 0 0 0755
set_perm "$MODPATH/bin/voxi-autoctl.sh" 0 0 0755

ui_print "Automatic writes are OFF by default."
ui_print "Only the validated fixed subId 11 F8 true-only recovery is automatic."
ui_print "IMS/RIL restarts and airplane toggles are intentionally excluded."

