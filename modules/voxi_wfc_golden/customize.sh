#!/system/bin/sh

SKIPMOUNT=true
PROPFILE=false
POSTFSDATA=false
LATESTARTSERVICE=true

ui_print '*********************************'
ui_print ' VOXI WFC Golden Recovery v1.1.0-rc4'
ui_print '*********************************'
ui_print 'STATUS: WRITABLE DEVICE VALIDATION REQUIRED'

[ -n "$MAGISK_VER" ] || [ -n "$MAGISK_VER_CODE" ] || abort 'Magisk environment not detected'
[ "$(getprop ro.product.cpu.abi)" = arm64-v8a ] || abort 'Unsupported ABI (arm64-v8a required)'

for FILE in \
  module.prop customize.sh action.sh service.sh uninstall.sh README.md \
  bin/common.sh bin/goldenctl.sh bin/golden-selftest.sh bin/golden-runner.sh bin/golden-preflight.sh bin/x55-holder.sh \
  lib/wfc-probe.jar; do
  [ -f "$MODPATH/$FILE" ] || abort "Missing module file: $FILE"
done

PROBE_HASH=$(sha256sum "$MODPATH/lib/wfc-probe.jar" 2>/dev/null | awk '{print toupper($1)}')
[ "$PROBE_HASH" = AC46E9F62DB88C043DA08E4D5BB1D100EA8AC10EF2A74838F99C2237C2B9A91D ] || abort 'wfc-probe.jar hash mismatch'

mkdir -p /data/adb/voxi-wfc-golden/logs /data/adb/voxi-wfc-golden/state
chmod 0700 /data/adb/voxi-wfc-golden /data/adb/voxi-wfc-golden/logs /data/adb/voxi-wfc-golden/state
if [ ! -f /data/adb/voxi-wfc-golden/config.conf ]; then
  printf 'AUTO_RECOVERY=0\n' > /data/adb/voxi-wfc-golden/config.conf
fi
chmod 0600 /data/adb/voxi-wfc-golden/config.conf

set_perm_recursive "$MODPATH" 0 0 0755 0644
for FILE in customize.sh action.sh service.sh uninstall.sh bin/common.sh bin/goldenctl.sh bin/golden-selftest.sh bin/golden-runner.sh bin/golden-preflight.sh bin/x55-holder.sh; do
  set_perm "$MODPATH/$FILE" 0 0 0755
done
set_perm "$MODPATH/lib/wfc-probe.jar" 0 0 0644

ui_print '安装完成。重启一次后，在模块页面点击“操作”执行 Golden recovery。'
ui_print '模块不会在开机时自动执行 recovery。'
