#!/system/bin/sh

MODDIR=${0%/*}
exec "$MODDIR/bin/goldenctl.sh" recover
