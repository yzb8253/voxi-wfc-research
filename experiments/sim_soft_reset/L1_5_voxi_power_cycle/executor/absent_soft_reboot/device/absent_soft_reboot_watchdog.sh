#!/system/bin/sh
set -u

STATE_DIR=/data/local/tmp/voxi-l1_5-executor
HELPER_JAR=$STATE_DIR/slot1-sim-power-helper.jar
LOG_FILE=$STATE_DIR/absent-watchdog.log
READY_FILE=$STATE_DIR/absent-watchdog.ready
GENERIC_READY_FILE=$STATE_DIR/watchdog.ready
DOWN_FILE=$STATE_DIR/power_down.sent
UP_FILE=$STATE_DIR/power_up.confirmed
LOCK_DIR=$STATE_DIR/absent-watchdog.lock
MAX_WAIT_FOR_DOWN=75
ROLLBACK_AFTER_DOWN=120

now() { date '+%Y-%m-%dT%H:%M:%S%z'; }
log() { echo "$(now) $*" >> "$LOG_FILE"; }
helper() {
  LAB_MODE=1 LAB_EXECUTE=YES CLASSPATH="$HELPER_JAR" \
    app_process /system/bin Slot1SimPowerHelper "$1" >> "$LOG_FILE" 2>&1
}

[ "$#" -eq 0 ] || { log "REFUSED arguments"; exit 10; }
[ "${ABSENT_LAB_MODE:-0}" = 1 ] || { log "REFUSED ABSENT_LAB_MODE"; exit 11; }
[ "${ABSENT_EXECUTE:-NO}" = YES ] || { log "REFUSED ABSENT_EXECUTE"; exit 12; }
[ "$(id -u)" = 0 ] || { log "REFUSED uid=$(id -u)"; exit 13; }
[ -f "$HELPER_JAR" ] || { log "REFUSED helper missing"; exit 14; }
mkdir "$LOCK_DIR" 2>/dev/null || { log "REFUSED watchdog already running"; exit 15; }
cleanup() {
  rm -f "$READY_FILE" "$GENERIC_READY_FILE"
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 129' HUP INT TERM

helper CHECK_ROLLBACK || { log "REFUSED rollback arm invalid"; exit 16; }
echo "ready=$(now) pid=$$ rollbackAfterDown=$ROLLBACK_AFTER_DOWN" > "$READY_FILE"
echo "ready=$(now) pid=$$ owner=absent-state" > "$GENERIC_READY_FILE"
log "READY absent-state watchdog fixed-slot1 rollback=${ROLLBACK_AFTER_DOWN}s"

deadline=$(( $(date +%s) + MAX_WAIT_FOR_DOWN ))
while [ ! -f "$DOWN_FILE" ] && [ "$(date +%s)" -lt "$deadline" ]; do
  sleep 1
done
if [ ! -f "$DOWN_FILE" ]; then
  log "EXIT no POWER_DOWN marker within ${MAX_WAIT_FOR_DOWN}s"
  exit 0
fi

log "POWER_DOWN marker observed"
deadline=$(( $(date +%s) + ROLLBACK_AFTER_DOWN ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if [ -f "$UP_FILE" ]; then
    log "EXIT POWER_UP callback-confirmed"
    exit 0
  fi
  sleep 1
done
if [ -f "$UP_FILE" ]; then
  log "EXIT POWER_UP callback-confirmed at deadline"
  exit 0
fi

log "FALLBACK fixed-slot1 POWER_UP firing"
echo "watchdog_fallback=$(now)" > "$STATE_DIR/watchdog-power-up.attempted"
helper POWER_UP
rc=$?
log "FALLBACK POWER_UP exit=$rc"
exit "$rc"
