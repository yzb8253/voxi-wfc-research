#!/system/bin/sh

MODDIR=${0%/*}
exec "$MODDIR/bin/wfc-auto-recover.sh" boot
