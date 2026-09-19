#!/system/bin/sh

MODDIR=${0%/*}
exec "$MODDIR/wfcctl.sh" deep-recover
