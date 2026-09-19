#!/system/bin/sh

MODDIR=${0%/*}
CTL="$MODDIR/bin/voxi-autoctl.sh"

echo "VOXI WFC Auto Recover"
echo
"$CTL" config
echo
"$CTL" status
echo
echo "Action is read-only. Use the WebUI or 'voxi-autoctl.sh recover-now' for a guarded manual recovery."

