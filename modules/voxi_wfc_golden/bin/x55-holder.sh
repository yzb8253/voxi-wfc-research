#!/system/bin/sh

set +e
set +u
set +x

PIDFILE=${1:-/data/adb/voxi-wfc-golden/state/x55_holder.pid}
ESOC=/dev/subsys_esoc0
umask 077

cleanup_holder() {
  SAVED=$(cat "$PIDFILE" 2>/dev/null)
  [ "$SAVED" = "$$" ] && rm -f "$PIDFILE"
  exit 0
}

trap cleanup_holder HUP INT TERM
printf '%s\n' "$$" > "$PIDFILE" || exit 90
chmod 0600 "$PIDFILE" 2>/dev/null

exec 9<"$ESOC" || { rm -f "$PIDFILE"; exit 91; }

while true; do
  sleep 60
done
