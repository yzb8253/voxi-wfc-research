#!/system/bin/sh

# Independent device-side rollback watchdog. It has no slot argument.
set -u

STATE_DIR=/data/local/tmp/voxi-l1_5-executor
HELPER_JAR=$STATE_DIR/slot1-sim-power-helper.jar
LOG_FILE=$STATE_DIR/watchdog.log
READY_FILE=$STATE_DIR/watchdog.ready
DOWN_FILE=$STATE_DIR/power_down.sent
UP_FILE=$STATE_DIR/power_up.confirmed
LOCK_DIR=$STATE_DIR/watchdog.lock
MAX_WAIT_FOR_DOWN=60
ROLLBACK_AFTER_DOWN=30

timestamp() { date '+%Y-%m-%dT%H:%M:%S%z'; }
log() { echo "$(timestamp) $*" >> "$LOG_FILE"; }
helper() {
  LAB_MODE=1 LAB_EXECUTE=YES CLASSPATH="$HELPER_JAR" \
    app_process /system/bin Slot1SimPowerHelper "$1" >> "$LOG_FILE" 2>&1
}

[ "${LAB_MODE:-0}" = 1 ] || { log "REFUSED LAB_MODE=${LAB_MODE:-0}"; exit 10; }
[ "${LAB_EXECUTE:-NO}" = YES ] || { log "REFUSED LAB_EXECUTE=${LAB_EXECUTE:-NO}"; exit 11; }
[ "$(id -u)" = 0 ] || { log "REFUSED uid=$(id -u)"; exit 12; }
[ -f "$HELPER_JAR" ] || { log "REFUSED helper missing"; exit 13; }
mkdir "$LOCK_DIR" 2>/dev/null || { log "REFUSED another watchdog lock exists"; exit 15; }
cleanup() {
  rm -f "$READY_FILE"
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 129' HUP INT TERM

helper CHECK_ROLLBACK || { log "REFUSED rollback arm invalid"; exit 14; }
echo "ready=$(timestamp) pid=$$" > "$READY_FILE"
log "READY fixed-slot1 watchdog"

deadline=$(( $(date +%s) + MAX_WAIT_FOR_DOWN ))
while [ ! -f "$DOWN_FILE" ] && [ "$(date +%s)" -lt "$deadline" ]; do
  sleep 1
done

if [ ! -f "$DOWN_FILE" ]; then
  log "EXIT no POWER_DOWN marker within ${MAX_WAIT_FOR_DOWN}s"
  exit 0
fi

log "POWER_DOWN marker observed; rollback deadline=${ROLLBACK_AFTER_DOWN}s"
deadline=$(( $(date +%s) + ROLLBACK_AFTER_DOWN ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if [ -f "$UP_FILE" ]; then
    log "EXIT POWER_UP already callback-confirmed"
    exit 0
  fi
  sleep 1
done

if [ -f "$UP_FILE" ]; then
  log "EXIT POWER_UP callback-confirmed at deadline"
  exit 0
fi

log "ROLLBACK firing fixed POWER_UP after ${ROLLBACK_AFTER_DOWN}s"
helper POWER_UP
rc=$?
log "ROLLBACK POWER_UP exit=$rc"
exit "$rc"
