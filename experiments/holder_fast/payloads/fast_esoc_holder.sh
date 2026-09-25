#!/system/bin/sh
pidfile="$1"
childfile="$2"

cleanup() {
    rm -f "$pidfile" "$childfile"
    exit 0
}

trap cleanup TERM INT HUP
echo $$ >"$pidfile"
exec 9</dev/subsys_esoc0 || exit 71
echo FAST_HOLDER_READY pid=$$ fd=9

while :; do
    sleep 3600 9<&- &
    child=$!
    echo "$child" >"$childfile"
    wait "$child"
done
