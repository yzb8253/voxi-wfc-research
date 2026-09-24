#!/system/bin/sh
set -u
V27_DIR=/data/local/tmp/voxi-x55-v27-alpha
STATE_DIR=/data/local/tmp/voxi-l1_5-executor
HELPER_JAR="$V27_DIR/slot1-sim-power-helper.jar"
HELPER_CLASS=Slot1SimPowerHelper
READY_FILE="$STATE_DIR/watchdog.ready"
DOWN_FILE="$STATE_DIR/power_down.sent"
RESULT_FILE="$V27_DIR/cycle.result"
DONE_FILE="$V27_DIR/cycle.done"
LOG_FILE="$V27_DIR/cycle.log"
UP_STARTED=0
PER_MGR_START_REQUESTED=0
now(){ date '+%Y-%m-%dT%H:%M:%S%z'; }
log(){ echo "$(now) $*" >> "$LOG_FILE"; }
helper(){ LAB_MODE=1 LAB_EXECUTE=YES CLASSPATH="$HELPER_JAR" app_process /system/bin "$HELPER_CLASS" "$1" >> "$LOG_FILE" 2>&1; }
power_up_once(){
  [ "$UP_STARTED" -eq 0 ] || return 0
  UP_STARTED=1
  log "POWER_UP_START reason=$1"
  helper POWER_UP
  rc=$?
  log "POWER_UP_EXIT rc=$rc"
  return "$rc"
}
start_per_mgr_once(){
  [ "$PER_MGR_START_REQUESTED" -eq 0 ] || return 0
  PER_MGR_START_REQUESTED=1
  log "PER_MGR_START_START reason=$1"
  setprop ctl.start vendor.per_mgr
  rc=$?
  state="$(getprop init.svc.vendor.per_mgr)"
  log "PER_MGR_START_EXIT rc=$rc state=$state"
  return "$rc"
}
cleanup(){
  rm -f "$READY_FILE"
  if [ -f "$DOWN_FILE" ] && [ "$UP_STARTED" -eq 0 ]; then
    power_up_once trap_cleanup
    trap_up_rc=$?
    if [ "$trap_up_rc" -eq 0 ] && [ "${X55_V27_START_PER_MGR_AFTER_POWER_UP:-}" = YES ]; then
      start_per_mgr_once trap_cleanup
    fi
  fi
  echo "done=$(now)" > "$DONE_FILE"
}
[ "$#" -eq 0 ] || exit 10
[ "$X55_V27_MODE" = 1 ] || exit 11
[ "$X55_V27_EXECUTE" = YES ] || exit 12
[ "${X55_V27_START_PER_MGR_AFTER_POWER_UP:-}" = YES ] || exit 15
[ "$(id -u)" = 0 ] || exit 13
[ -f "$HELPER_JAR" ] || exit 14
trap cleanup EXIT HUP INT TERM
echo "ready=$(now) pid=$$" > "$READY_FILE"
log POWER_DOWN_START
helper POWER_DOWN
down_rc=$?
log "POWER_DOWN_EXIT rc=$down_rc"
if [ "$down_rc" -ne 0 ]; then echo "RESULT=POWER_DOWN_FAILED rc=$down_rc" > "$RESULT_FILE"; exit 20; fi
sleep 3
power_up_once normal_three_second_hold
up_rc=$?
if [ "$up_rc" -ne 0 ]; then echo "RESULT=POWER_UP_FAILED rc=$up_rc" > "$RESULT_FILE"; exit 21; fi
start_per_mgr_once immediately_after_power_up
pm_rc=$?
if [ "$pm_rc" -ne 0 ]; then echo "RESULT=PER_MGR_START_FAILED rc=$pm_rc" > "$RESULT_FILE"; exit 22; fi
echo "RESULT=SUCCESS PER_MGR_START=REQUESTED" > "$RESULT_FILE"
exit 0
