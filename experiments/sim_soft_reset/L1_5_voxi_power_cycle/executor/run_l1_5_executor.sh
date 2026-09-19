#!/usr/bin/env sh

# Host-side orchestration. Default is read-only. This file was not executed in
# write mode during the preparation phase.
set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LAB_ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
. "$LAB_ROOT/lib/common.sh"

LAB_MODE=${LAB_MODE:-0}
STATE_DIR=/data/local/tmp/voxi-l1_5-executor
HELPER_JAR=$STATE_DIR/slot1-sim-power-helper.jar
WATCHDOG=$STATE_DIR/l1_5_rollback_watchdog.sh
HOLD_SECONDS=5

[ "$#" -eq 0 ] || die "executor accepts no arguments or target identifiers"
require_device

STAMP=$(date '+%Y%m%d-%H%M%S')
RUN_DIR="$LAB_ROOT/runs/$STAMP-L1_5-executor"
mkdir -p "$RUN_DIR"

helper() {
  MODE=$1
  root_shell "LAB_MODE=$LAB_MODE LAB_EXECUTE=${LAB_EXECUTE:-NO} CLASSPATH=$HELPER_JAR app_process /system/bin Slot1SimPowerHelper $MODE"
}

snapshot() {
  LABEL=$1
  probe_json > "$RUN_DIR/$LABEL-wfc-probe.json" 2>&1 || true
  root_shell 'dumpsys isub; dumpsys phone; dumpsys telephony.registry' \
    > "$RUN_DIR/$LABEL-telephony.txt" 2>&1 || true
}

{
  echo "started=$(date -Iseconds)"
  echo "LAB_MODE=$LAB_MODE"
  echo "LAB_EXECUTE=${LAB_EXECUTE:-NO}"
  echo "fixed_target=slot1/phone1/sub11"
  echo "protected=slot0/sub1"
} > "$RUN_DIR/metadata.txt"

snapshot before
helper DRY_RUN > "$RUN_DIR/helper-dry-run.txt" 2>&1 || die "helper dry-run or safety gate failed"

if [ "$LAB_MODE" != 1 ] || [ "${LAB_EXECUTE:-NO}" != YES ]; then
  {
    echo "completed=$(date -Iseconds)"
    echo "device_ril_write_count=0"
    echo "result=DRY_RUN_ONLY"
  } >> "$RUN_DIR/metadata.txt"
  echo "L1.5 DRY RUN complete: $RUN_DIR"
  echo "No RIL request sent. Real execution requires LAB_MODE=1 and LAB_EXECUTE=YES."
  exit 0
fi

# Execution branch is deliberately unreachable without both explicit flags.
# Deployment is manual and separate; this runner never pushes binaries.
root_shell "test -f $HELPER_JAR && test -f $WATCHDOG" \
  || die "audited helper/watchdog are not deployed"
root_shell "mkdir -p $STATE_DIR; chmod 0700 $STATE_DIR; rm -f $STATE_DIR/watchdog.ready $STATE_DIR/power_down.sent $STATE_DIR/power_up.confirmed"

helper ARM_ROLLBACK > "$RUN_DIR/arm-rollback.txt" 2>&1 || die "rollback arm failed"
root_shell "LAB_MODE=1 LAB_EXECUTE=YES nohup $WATCHDOG >/dev/null 2>&1 &"

ready=0
for second in 1 2 3 4 5; do
  if root_shell "test -f $STATE_DIR/watchdog.ready" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
[ "$ready" = 1 ] || die "watchdog did not confirm ready; POWER_DOWN forbidden"

adb_cmd logcat -v threadtime > "$RUN_DIR/logcat-full.txt" 2>&1 &
LOGCAT_PID=$!
trap 'kill "$LOGCAT_PID" 2>/dev/null || true' EXIT HUP INT TERM

action_rc=0
{
  echo "power_down_start=$(date -Iseconds)"
  helper POWER_DOWN
  down_rc=$?
  echo "power_down_exit=$down_rc time=$(date -Iseconds)"
  if [ "$down_rc" -ne 0 ]; then
    action_rc=$down_rc
    echo "normal POWER_UP skipped; independent watchdog remains armed"
  else
    sleep "$HOLD_SECONDS"
    echo "power_up_start=$(date -Iseconds)"
    helper POWER_UP
    action_rc=$?
    echo "power_up_exit=$action_rc time=$(date -Iseconds)"
  fi
} > "$RUN_DIR/command.txt" 2>&1

sleep 10
snapshot after
root_shell "cat $STATE_DIR/watchdog.log 2>/dev/null" > "$RUN_DIR/watchdog.log" 2>&1 || true
kill "$LOGCAT_PID" 2>/dev/null || true
wait "$LOGCAT_PID" 2>/dev/null || true
trap - EXIT HUP INT TERM

{
  echo "completed=$(date -Iseconds)"
  echo "action_exit=$action_rc"
  echo "result=EXECUTION_CAPTURED"
} >> "$RUN_DIR/metadata.txt"

echo "L1.5 execution capture: $RUN_DIR"
exit "$action_rc"
