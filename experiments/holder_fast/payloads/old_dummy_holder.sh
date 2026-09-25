#!/system/bin/sh
pidfile="$1"
echo $$ >"$pidfile"
exec 9</dev/null || exit 71
while true; do
    sleep 60
done
