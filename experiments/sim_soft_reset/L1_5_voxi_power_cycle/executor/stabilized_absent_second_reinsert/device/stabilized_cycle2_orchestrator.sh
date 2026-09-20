#!/system/bin/sh
set -u
STATE_DIR=/data/local/tmp/voxi-l1_5-executor
HELPER_JAR=$STATE_DIR/slot1-sim-power-helper.jar
LOG_FILE=$STATE_DIR/stabilized-cycle2-orchestrator.log
READY_FILE=$STATE_DIR/stabilized-watchdog-cycle2.ready
EXPECTED_HELPER_SHA256=be877b6e9694b4100f2487dc892803de6399c89588f194a1e54d4c3ae3173a31
now() { date '+%Y-%m-%dT%H:%M:%S%z'; }
log() { echo "$(now) $*" >> "$LOG_FILE"; }
helper() { LAB_MODE=1 LAB_EXECUTE=YES CLASSPATH="$HELPER_JAR" app_process /system/bin Slot1SimPowerHelper "$1"; }
fail_pre() { log "ABORT_PRE_DOWN $*"; exit 20; }
[ "$#" -eq 0 ] || fail_pre arguments
[ "${ABSENT_LAB_MODE:-0}" = 1 ] || fail_pre ABSENT_LAB_MODE
[ "${ABSENT_EXECUTE:-NO}" = YES ] || fail_pre ABSENT_EXECUTE
[ "$(id -u)" = 0 ] || fail_pre UID0
[ "$(sha256sum "$HELPER_JAR" | awk '{print $1}')" = "$EXPECTED_HELPER_SHA256" ] || fail_pre helper_hash
[ -f "$READY_FILE" ] && [ -f "$STATE_DIR/watchdog.ready" ] || fail_pre watchdog_ready
ip addr show wlan0 2>/dev/null | grep -q '<[^>]*UP' || fail_pre wlan0
ip addr show tun0 2>/dev/null | grep -q '<[^>]*UP' || fail_pre tun0
pre=$(CLASSPATH="$HELPER_JAR" app_process /system/bin Slot1SimPowerHelper DRY_RUN 2>&1) || fail_pre dry_run
printf '%s\n' "$pre" >> "$LOG_FILE"
echo "$pre" | grep -q 'before.strictGate=true' || fail_pre strict_gate
echo "$pre" | grep -q 'before.ims=registrationState=0 transport=-1' || fail_pre strict_F1
echo "$pre" | grep -q 'before.wfc=available=false' || fail_pre strict_F1_wfc
log "T12 SECOND_AND_FINAL_POWER_DOWN"
helper POWER_DOWN >> "$LOG_FILE" 2>&1 || exit 30
absent=0
end=$(( $(date +%s) + 30 ))
while [ "$(date +%s)" -lt "$end" ]; do
  state=$(CLASSPATH="$HELPER_JAR" app_process /system/bin Slot1SimPowerHelper DRY_RUN 2>&1 || true)
  target=$(echo "$state" | grep '^before.target=' | head -n 1)
  slot0=$(echo "$state" | grep '^before.slot0=' | head -n 1)
  echo "$slot0" | grep -q 'active=true.*simState=5.*mappingGate=true' || exit 31
  echo "$target" | grep -q 'active=false.*uiccEnabled=false.*simState=1.*mappingGate=false' && { absent=1; log "T13 TRUE_ABSENT $target"; break; }
  sleep 1
done
[ "$absent" -eq 1 ] || { log "TRUE_ABSENT_NOT_CONFIRMED"; exit 32; }
sleep 10
log "T14 SECOND_AND_FINAL_POWER_UP"
helper POWER_UP >> "$LOG_FILE" 2>&1 || exit 33
[ -f "$STATE_DIR/power_up.confirmed" ] || exit 34
log "T15 SECOND_POWER_UP_CALLBACK_CONFIRMED"
exit 0