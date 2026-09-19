#!/system/bin/sh

MODDIR=${0%/*}
CTL="$MODDIR/bin/wfcctl.sh"

echo "VOXI WFC Recovery v1.0"
echo "Checking current state..."
echo

"$CTL" status
RC=$?

case "$RC" in
  0)
    echo
    echo "VOXI WFC is healthy."
    echo "WFC already healthy."
    echo "No action required."
    exit 0
    ;;
  10)
    echo
    echo "Validated VOXI inactive candidate detected."
    echo "Starting safe recovery..."
    "$CTL" recover
    exit $?
    ;;
  20)
    echo
    echo "VOXI subscription is active but WFC is abnormal."
    echo "Automatic write blocked."
    echo "Use diagnose for details."
    exit 20
    ;;
  *)
    echo
    echo "Target identity or status could not be verified safely."
    echo "No write operation was executed."
    exit "$RC"
    ;;
esac
