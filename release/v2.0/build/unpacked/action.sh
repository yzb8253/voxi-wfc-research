#!/system/bin/sh

MODDIR=${0%/*}
CTL="$MODDIR/bin/wfcctl.sh"

echo "VOXI WFC Recovery v2.0"
"$CTL" full-status
echo
"$CTL" auto-status
"$CTL" network-status
echo "Checking current state..."
echo
"$CTL" status
RC=$?
echo
echo "Magisk Action is status-only. ZERO WRITE."
echo "Manual recovery commands are available through wfcctl.sh."
exit 0