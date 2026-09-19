#!/system/bin/sh

MODDIR=${0%/*}
PENDING=/data/adb/voxi-wfc-recovery/state/full_recover_pending

if [ -e "$PENDING" ]; then
  exec "$MODDIR/bin/wfc-full-lifecycle.sh" resume
fi
exec "$MODDIR/bin/wfc-auto-recover.sh" boot