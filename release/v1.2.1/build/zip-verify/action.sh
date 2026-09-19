#!/system/bin/sh

MODDIR=${0%/*}
CTL="$MODDIR/bin/wfcctl.sh"

echo "VOXI WFC Recovery v1.2.1"
"$CTL" auto-status
"$CTL" network-status
echo "Checking current state..."
echo
"$CTL" status
RC=$?

case "$RC" in
  0)
    echo; echo "VOXI WFC is healthy."; echo "No action required. Zero writes."; exit 0 ;;
  10)
    echo; echo "Validated VOXI inactive/apps-disabled state detected."
    echo "Starting Safe Recover..."; "$CTL" recover; exit $? ;;
  20)
    echo; echo "VOXI is active but IMS/WFC is not registered."
    echo "Safe network-aware recovery is available."
    echo "Run after UK VPN/location are ready: su -c '$CTL auto-run-now'"
    echo "Action did not perform any write."; exit 20 ;;
  *)
    echo; echo "Target identity or status could not be verified safely."
    echo "No write operation was executed."; exit "$RC" ;;
esac
