#!/system/bin/sh
set -u
STATE_DIR=/data/local/tmp/voxi-single-sim
HELPER_JAR=$STATE_DIR/single-sim-slot1-power-helper.jar
LOG_FILE=$STATE_DIR/simple-cycle.log
now(){ date '+%Y-%m-%dT%H:%M:%S%z'; }
log(){ echo "$(now) $*" >> "$LOG_FILE"; }
helper(){ LAB_MODE=1 LAB_EXECUTE=YES CLASSPATH="$HELPER_JAR" app_process /system/bin SingleSimSlot1PowerHelper "$1"; }
fail(){ log "ABORT $*";exit 20; }
[ "$#" -eq 0 ]||fail args
[ "${SINGLE_SIM_LAB_MODE:-0}" = 1 ]||fail mode
[ "${SINGLE_SIM_EXECUTE:-NO}" = YES ]||fail execute
[ "$(id -u)" = 0 ]||fail uid
[ -f "$STATE_DIR/watchdog.ready" ]||fail watchdog
pre=$(CLASSPATH="$HELPER_JAR" app_process /system/bin SingleSimSlot1PowerHelper DRY_RUN 2>&1)||fail gate
printf '%s\n' "$pre" >> "$LOG_FILE"
echo "$pre"|grep -q 'before.strictGate=true'||fail strict
log 'POWER_DOWN #1'
helper POWER_DOWN >> "$LOG_FILE" 2>&1||exit 30
absent=0
end=$(( $(date +%s)+30 ))
while [ "$(date +%s)" -lt "$end" ];do
 s=$(CLASSPATH="$HELPER_JAR" app_process /system/bin SingleSimSlot1PowerHelper DRY_RUN 2>&1||true)
 target=$(echo "$s"|grep '^before.target='|head -1)
 slot0=$(echo "$s"|grep '^before.slot0='|head -1)
 echo "$slot0"|grep -q 'active=false.*simState=1.*mappingGate=true'||exit 31
 echo "$target"|grep -q 'active=false.*uiccEnabled=false.*simState=1.*mappingGate=false'&&{ absent=1;log "TRUE_ABSENT $target";break;}
 sleep 1
done
[ "$absent" -eq 1 ]||exit 32
sleep 10
log 'POWER_UP #1'
helper POWER_UP >> "$LOG_FILE" 2>&1||exit 33
[ -f "$STATE_DIR/power_up.confirmed" ]||exit 34
log DONE