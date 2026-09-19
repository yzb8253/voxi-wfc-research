#!/system/bin/sh

MODDIR=${0%/*}
exec "$MODDIR/bin/voxi-auto-daemon.sh" >/dev/null 2>&1 &

