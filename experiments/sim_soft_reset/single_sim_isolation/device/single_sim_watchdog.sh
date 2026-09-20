#!/system/bin/sh
set -u
STATE_DIR=/data/local/tmp/voxi-single-sim
HELPER_JAR=$STATE_DIR/single-sim-slot1-power-helper.jar
LOG_FILE=$STATE_DIR/watchdog.log
READY_FILE=$STATE_DIR/watchdog.ready
DOWN_FILE=$STATE_DIR/power_down.sent
UP_FILE=$STATE_DIR/power_up.confirmed
LOCK_DIR=$STATE_DIR/watchdog.lock
ROLLBACK_AFTER_DOWN=90
now(){ date '+%Y-%m-%dT%H:%M:%S%z'; }
log(){ echo "$(now) $*" >> "$LOG_FILE"; }
helper(){ LAB_MODE=1 LAB_EXECUTE=YES CLASSPATH="$HELPER_JAR" app_process /system/bin SingleSimSlot1PowerHelper "$1" >> "$LOG_FILE" 2>&1; }
cleanup(){ rm -f "$READY_FILE"; rmdir "$LOCK_DIR" 2>/dev/null||true; }
[ "$#" -eq 0 ]||exit 10
[ "${SINGLE_SIM_LAB_MODE:-0}" = 1 ]||exit 11
[ "${SINGLE_SIM_EXECUTE:-NO}" = YES ]||exit 12
[ "$(id -u)" = 0 ]||exit 13
mkdir "$LOCK_DIR" 2>/dev/null||exit 14
trap cleanup EXIT
trap 'exit 129' HUP INT TERM
helper CHECK_ROLLBACK||exit 15
echo "ready=$(now) pid=$$" > "$READY_FILE"
log READY
end=$(( $(date +%s)+45 ))
while [ ! -f "$DOWN_FILE" ] && [ "$(date +%s)" -lt "$end" ];do sleep 1;done
[ -f "$DOWN_FILE" ]||{ log 'EXIT no down';exit 0;}
down=$(stat -c %Y "$DOWN_FILE")||exit 16
deadline=$((down+ROLLBACK_AFTER_DOWN))
while [ "$(date +%s)" -lt "$deadline" ];do [ -f "$UP_FILE" ]&&{ log 'EXIT up confirmed';exit 0;};sleep 1;done
[ -f "$UP_FILE" ]&&exit 0
log 'FALLBACK POWER_UP'
helper POWER_UP