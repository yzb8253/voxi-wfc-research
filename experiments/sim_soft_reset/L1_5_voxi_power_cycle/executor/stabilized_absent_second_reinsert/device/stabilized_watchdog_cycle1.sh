#!/system/bin/sh
set -u
STATE_DIR=/data/local/tmp/voxi-l1_5-executor
HELPER_JAR=$STATE_DIR/slot1-sim-power-helper.jar
LOG_FILE=$STATE_DIR/stabilized-watchdog-cycle1.log
READY_FILE=$STATE_DIR/stabilized-watchdog-cycle1.ready
GENERIC_READY_FILE=$STATE_DIR/watchdog.ready
DOWN_FILE=$STATE_DIR/power_down.sent
UP_FILE=$STATE_DIR/power_up.confirmed
LOCK_DIR=$STATE_DIR/stabilized-watchdog-cycle1.lock
ROLLBACK_AFTER_DOWN=300
now() { date '+%Y-%m-%dT%H:%M:%S%z'; }
log() { echo "$(now) $*" >> "$LOG_FILE"; }
helper() { LAB_MODE=1 LAB_EXECUTE=YES CLASSPATH="$HELPER_JAR" app_process /system/bin Slot1SimPowerHelper "$1" >> "$LOG_FILE" 2>&1; }
cleanup() { rm -f "$READY_FILE" "$GENERIC_READY_FILE"; rmdir "$LOCK_DIR" 2>/dev/null || true; }
[ "$#" -eq 0 ] || exit 10
[ "${ABSENT_LAB_MODE:-0}" = 1 ] || exit 11
[ "${ABSENT_EXECUTE:-NO}" = YES ] || exit 12
[ "$(id -u)" = 0 ] || exit 13
[ -f "$HELPER_JAR" ] || exit 14
mkdir "$LOCK_DIR" 2>/dev/null || exit 15
trap cleanup EXIT
trap 'exit 129' HUP INT TERM
helper CHECK_ROLLBACK || exit 16
echo "ready=$(now) pid=$$ deadlineFromDown=${ROLLBACK_AFTER_DOWN}s" > "$READY_FILE"
echo "ready=$(now) pid=$$ owner=stabilized-cycle1" > "$GENERIC_READY_FILE"
log "READY fixed-slot1 cycle1"
end=$(( $(date +%s) + 90 ))
while [ ! -f "$DOWN_FILE" ] && [ "$(date +%s)" -lt "$end" ]; do sleep 1; done
[ -f "$DOWN_FILE" ] || { log "EXIT no POWER_DOWN marker"; exit 0; }
down_epoch=$(stat -c %Y "$DOWN_FILE") || exit 17
deadline=$((down_epoch + ROLLBACK_AFTER_DOWN))
log "POWER_DOWN observed epoch=$down_epoch absoluteDeadline=$deadline"
while [ "$(date +%s)" -lt "$deadline" ]; do
  [ -f "$UP_FILE" ] && { log "EXIT callback-confirmed POWER_UP"; exit 0; }
  sleep 1
done
[ -f "$UP_FILE" ] && { log "EXIT callback-confirmed POWER_UP at deadline"; exit 0; }
log "FALLBACK fixed-slot1 POWER_UP"
helper POWER_UP
rc=$?
log "FALLBACK exit=$rc"
exit "$rc"