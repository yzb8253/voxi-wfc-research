#!/usr/bin/env sh

set -u
ADB=${ADB:-adb}
SERIAL=${1:-${ANDROID_SERIAL:-}}
STAMP=$(date '+%Y%m%d-%H%M%S')
OUT=${2:-"voxi-logs-$STAMP"}

if [ -n "$SERIAL" ]; then
  set -- "$ADB" -s "$SERIAL"
else
  set -- "$ADB"
fi

"$@" get-state >/dev/null 2>&1 || { echo "ADB device is not online" >&2; exit 2; }
mkdir -p "$OUT" || exit 3

run() {
  NAME=$1
  shift
  "$@" > "$OUT/$NAME" 2>&1 || true
}

run device.txt "$@" shell getprop ro.product.model
run getprop.txt "$@" shell getprop
run processes.txt "$@" shell su -c 'ps -A -o USER,PID,PPID,NAME,CMDLINE'
for SERVICE in isub phone telephony.registry telephony_ims ims carrier_config connectivity; do
  run "dumpsys-$SERVICE.txt" "$@" shell su -c "dumpsys $SERVICE"
done
run routes.txt "$@" shell su -c 'ip link; ip route show table all; ip rule; ip xfrm state; ip xfrm policy'
run services.txt "$@" shell su -c 'service list'
run logcat-full.txt "$@" shell su -c 'logcat -d -v threadtime'
run logcat-ims-qcril.txt "$@" shell su -c "logcat -d -v threadtime | grep -Ei 'ims|iwlan|epdg|wfc|vowifi|qcril|qti.cne|cnd|DSD|QMI'"

echo "Collected read-only VOXI diagnostics: $OUT"

