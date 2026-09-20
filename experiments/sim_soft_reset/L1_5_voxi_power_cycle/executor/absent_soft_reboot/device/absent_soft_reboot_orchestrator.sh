#!/system/bin/sh
set -u

STATE_DIR=/data/local/tmp/voxi-l1_5-executor
HELPER_JAR=$STATE_DIR/slot1-sim-power-helper.jar
LOG_FILE=$STATE_DIR/absent-orchestrator.log
READY_FILE=$STATE_DIR/absent-watchdog.ready
DOWN_FILE=$STATE_DIR/power_down.sent
EXPECTED_HELPER_SHA256=be877b6e9694b4100f2487dc892803de6399c89588f194a1e54d4c3ae3173a31
HOST_SOFT_DEADLINE=75
START_EPOCH=0
POWER_UP_STARTED=0

now() { date '+%Y-%m-%dT%H:%M:%S%z'; }
log() { echo "$(now) $*" >> "$LOG_FILE"; }
fail_pre_down() { log "ABORT_PRE_DOWN $*"; exit 20; }
helper() {
  LAB_MODE=1 LAB_EXECUTE=YES CLASSPATH="$HELPER_JAR" \
    app_process /system/bin Slot1SimPowerHelper "$1"
}

[ "$#" -eq 0 ] || fail_pre_down "arguments forbidden"
[ "${ABSENT_LAB_MODE:-0}" = 1 ] || fail_pre_down "ABSENT_LAB_MODE"
[ "${ABSENT_EXECUTE:-NO}" = YES ] || fail_pre_down "ABSENT_EXECUTE"
[ "$(id -u)" = 0 ] || fail_pre_down "UID0"
[ "$(sha256sum "$HELPER_JAR" | awk '{print $1}')" = "$EXPECTED_HELPER_SHA256" ] || fail_pre_down "helper hash"
[ ! -e "$STATE_DIR/power_down.sent" ] || fail_pre_down "stale power_down marker"
ip link show wlan0 2>/dev/null | grep -q '<[^>]*UP' || fail_pre_down "wlan0"
ip link show tun0 2>/dev/null | grep -q '<[^>]*UP' || fail_pre_down "tun0"

preflight=$(CLASSPATH="$HELPER_JAR" app_process /system/bin Slot1SimPowerHelper DRY_RUN 2>&1) || fail_pre_down "helper DRY_RUN"
echo "$preflight" >> "$LOG_FILE"
echo "$preflight" | grep -q 'before.strictGate=true' || fail_pre_down "strict gate"
echo "$preflight" | grep -q 'result=DRY_RUN_ZERO_WRITE' || fail_pre_down "dry-run result"

proc_cmdline() { tr '\000' ' ' < "/proc/$1/cmdline" 2>/dev/null | sed 's/[[:space:]]*$//'; }
proc_uid() { awk '/^Uid:/{print $2}' "/proc/$1/status" 2>/dev/null; }
proc_ppid() { awk '/^PPid:/{print $2}' "/proc/$1/status" 2>/dev/null; }
proc_domain() { cat "/proc/$1/attr/current" 2>/dev/null; }
init_pid() { getprop "init.svc_debug_pid.$1"; }

verify_init() {
  svc=$1 expected_name=$2 expected_domain=$3 expected_cmd=$4
  p=$(init_pid "$svc")
  [ -n "$p" ] && [ -d "/proc/$p" ] || return 1
  [ "$(getprop "init.svc.$svc")" = running ] || return 1
  [ "$(awk '/^Name:/{print $2}' "/proc/$p/status")" = "$expected_name" ] || return 1
  [ "$(proc_ppid "$p")" = 1 ] || return 1
  echo "$(proc_domain "$p")" | grep -q "^${expected_domain}" || return 1
  proc_cmdline "$p" | grep -Fq -- "$expected_cmd" || return 1
  echo "$p"
}

find_exact_app() {
  pname=$1 expected_uid=$2
  for p in $(pidof "$pname" 2>/dev/null); do
    [ "$(proc_uid "$p")" = "$expected_uid" ] || continue
    [ "$(proc_cmdline "$p")" = "$pname" ] || continue
    echo "$p"
    return 0
  done
  return 1
}

record_fixed_targets() {
  QCRILD2_OLD=$(verify_init vendor.qcrild2 main u:r:rild:s0 '-c 2') || fail_pre_down qcrild2
  QCRILD_OLD=$(verify_init vendor.qcrild main u:r:rild:s0 '/vendor/bin/hw/qcrild') || fail_pre_down qcrild
  proc_cmdline "$QCRILD_OLD" | grep -Fq -- '-c 2' && fail_pre_down "primary qcrild is slot2"
  NETMGRD_OLD=$(verify_init vendor.netmgrd netmgrd u:r:vendor_netmgrd:s0 '/vendor/bin/netmgrd') || fail_pre_down netmgrd
  IMSQMI_OLD=$(verify_init vendor.imsqmidaemon imsqmidaemon u:r:vendor_ims:s0 '/vendor/bin/imsqmidaemon') || fail_pre_down imsqmidaemon
  IMSDATA_OLD=$(verify_init vendor.imsdatadaemon imsdatadaemon u:r:vendor_ims:s0 '/vendor/bin/imsdatadaemon') || fail_pre_down imsdatadaemon
  CND_OLD=$(verify_init vendor.cnd cnd u:r:vendor_cnd:s0 '/system/vendor/bin/cnd') || fail_pre_down cnd
  QTIDATA_OLD=$(find_exact_app .qtidataservices 10104) || fail_pre_down qtidataservices
  QCOMIMS_OLD=$(find_exact_app org.codeaurora.ims 10196) || fail_pre_down qcom_ims
  PHONE_OLD=$(find_exact_app com.android.phone 1001) || fail_pre_down com_android_phone
  SYSTEM_OLD=$(find_exact_app system_server 1000) || fail_pre_down system_server
  log "TARGETS qcrild2=$QCRILD2_OLD qcrild=$QCRILD_OLD netmgrd=$NETMGRD_OLD imsqmidaemon=$IMSQMI_OLD imsdatadaemon=$IMSDATA_OLD cnd=$CND_OLD qtidataservices=$QTIDATA_OLD qcomims=$QCOMIMS_OLD phone=$PHONE_OLD system_server=$SYSTEM_OLD"
}
record_fixed_targets

if [ "${ABSENT_PREFLIGHT_ONLY:-NO}" = YES ]; then
  log "PREFLIGHT_ONLY_PASS"
  exit 0
fi
[ "${ABSENT_PREFLIGHT_ONLY:-NO}" = NO ] || fail_pre_down "ABSENT_PREFLIGHT_ONLY must be NO or YES"
[ -f "$READY_FILE" ] || fail_pre_down "watchdog.ready"

normal_power_up() {
  reason=$1
  [ "$POWER_UP_STARTED" -eq 0 ] || return 0
  POWER_UP_STARTED=1
  log "POWER_UP_START reason=$reason"
  echo "normal_power_up=$(now) reason=$reason" > "$STATE_DIR/normal-power-up.attempted"
  helper POWER_UP >> "$LOG_FILE" 2>&1
  rc=$?
  log "POWER_UP_EXIT rc=$rc"
  return "$rc"
}

check_deadline() {
  if [ "$START_EPOCH" -gt 0 ] && [ "$(date +%s)" -ge $((START_EPOCH + HOST_SOFT_DEADLINE)) ]; then
    log "SOFT_DEADLINE reached; aborting remaining restarts"
    normal_power_up soft_deadline || true
    exit 40
  fi
}

wait_init_new() {
  svc=$1 old=$2 expected_name=$3 expected_domain=$4 expected_cmd=$5
  end=$(( $(date +%s) + 8 ))
  while [ "$(date +%s)" -lt "$end" ]; do
    check_deadline
    new=$(verify_init "$svc" "$expected_name" "$expected_domain" "$expected_cmd" 2>/dev/null || true)
    if [ -n "$new" ] && [ "$new" != "$old" ]; then echo "$new"; return 0; fi
    sleep 1
  done
  return 1
}

restart_init() {
  svc=$1 old=$2 expected_name=$3 expected_domain=$4 expected_cmd=$5 label=$6
  check_deadline
  current=$(verify_init "$svc" "$expected_name" "$expected_domain" "$expected_cmd") || return 1
  [ "$current" = "$old" ] || return 1
  log "TERM $label old=$old"
  kill -TERM "$old" || return 1
  new=$(wait_init_new "$svc" "$old" "$expected_name" "$expected_domain" "$expected_cmd") || return 1
  log "RESTARTED $label old=$old new=$new"
  eval "${label}_NEW=$new"
}

wait_app_new() {
  pname=$1 uid=$2 old=$3
  end=$(( $(date +%s) + 8 ))
  while [ "$(date +%s)" -lt "$end" ]; do
    check_deadline
    new=$(find_exact_app "$pname" "$uid" 2>/dev/null || true)
    if [ -n "$new" ] && [ "$new" != "$old" ]; then echo "$new"; return 0; fi
    sleep 1
  done
  return 1
}

restart_app() {
  pname=$1 uid=$2 old=$3 label=$4
  check_deadline
  current=$(find_exact_app "$pname" "$uid") || return 1
  [ "$current" = "$old" ] || return 1
  log "TERM $label old=$old"
  kill -TERM "$old" || return 1
  new=$(wait_app_new "$pname" "$uid" "$old") || return 1
  log "RESTARTED $label old=$old new=$new"
  eval "${label}_NEW=$new"
}

START_EPOCH=$(date +%s)
log "POWER_DOWN_START"
helper POWER_DOWN >> "$LOG_FILE" 2>&1
DOWN_RC=$?
log "POWER_DOWN_EXIT rc=$DOWN_RC"
if [ "$DOWN_RC" -ne 0 ]; then
  if [ -f "$DOWN_FILE" ]; then
    normal_power_up power_down_failed_after_marker || true
  else
    log "POWER_DOWN_REJECTED_BEFORE_MARKER; no POWER_UP needed"
  fi
  exit 30
fi

down_ok=0
end=$(( $(date +%s) + 20 ))
while [ "$(date +%s)" -lt "$end" ]; do
  check_deadline
  state=$(CLASSPATH="$HELPER_JAR" app_process /system/bin Slot1SimPowerHelper DRY_RUN 2>&1 || true)
  target=$(echo "$state" | grep '^before.target=' | head -n 1)
  slot0=$(echo "$state" | grep '^before.slot0=' | head -n 1)
  echo "$slot0" | grep -q 'active=true.*simState=5.*mappingGate=true' || { log "slot0 gate failed during down"; normal_power_up slot0_gate_failed || true; exit 31; }
  echo "$target" | grep -Eq 'active=false|uiccEnabled=false|simState=(0|1|2|3|4|6|7|8|9)|mappingGate=false' && { down_ok=1; log "CARD_DOWN_CONFIRMED $target"; break; }
  sleep 1
done
if [ "$down_ok" -ne 1 ]; then
  log "CARD_DOWN_NOT_CONFIRMED"
  normal_power_up down_not_confirmed || true
  exit 32
fi

restart_init vendor.qcrild2 "$QCRILD2_OLD" main u:r:rild:s0 '-c 2' QCRILD2 || { log "FAIL qcrild2"; normal_power_up qcrild2_failed || true; exit 41; }
restart_init vendor.qcrild "$QCRILD_OLD" main u:r:rild:s0 '/vendor/bin/hw/qcrild' QCRILD || { log "FAIL qcrild"; normal_power_up qcrild_failed || true; exit 42; }
QCRILD2_FINAL=$(verify_init vendor.qcrild2 main u:r:rild:s0 '-c 2') || { log "FAIL qcrild2_after_primary"; normal_power_up qcrild_pair_failed || true; exit 43; }
log "QCRILD_PAIR_STABLE primary=$QCRILD_NEW target=$QCRILD2_FINAL"
restart_init vendor.netmgrd "$NETMGRD_OLD" netmgrd u:r:vendor_netmgrd:s0 '/vendor/bin/netmgrd' NETMGRD || { log "FAIL netmgrd"; normal_power_up netmgrd_failed || true; exit 44; }
restart_init vendor.imsqmidaemon "$IMSQMI_OLD" imsqmidaemon u:r:vendor_ims:s0 '/vendor/bin/imsqmidaemon' IMSQMI || { log "FAIL imsqmidaemon"; normal_power_up imsqmidaemon_failed || true; exit 45; }
restart_init vendor.imsdatadaemon "$IMSDATA_OLD" imsdatadaemon u:r:vendor_ims:s0 '/vendor/bin/imsdatadaemon' IMSDATA || { log "FAIL imsdatadaemon"; normal_power_up imsdatadaemon_failed || true; exit 46; }
restart_init vendor.cnd "$CND_OLD" cnd u:r:vendor_cnd:s0 '/system/vendor/bin/cnd' CND || { log "FAIL cnd"; normal_power_up cnd_failed || true; exit 47; }
restart_app .qtidataservices 10104 "$QTIDATA_OLD" QTIDATA || { log "FAIL qtidataservices"; normal_power_up qtidataservices_failed || true; exit 48; }
restart_app org.codeaurora.ims 10196 "$QCOMIMS_OLD" QCOMIMS || { log "FAIL qcomims"; normal_power_up qcomims_failed || true; exit 49; }
restart_app com.android.phone 1001 "$PHONE_OLD" PHONE || { log "FAIL phone"; normal_power_up phone_failed || true; exit 50; }
restart_app system_server 1000 "$SYSTEM_OLD" SYSTEM || { log "FAIL system_server"; normal_power_up system_server_failed || true; exit 51; }

end=$(( $(date +%s) + 12 ))
while [ "$(date +%s)" -lt "$end" ]; do
  check_deadline
  service check phone 2>/dev/null | grep -q 'found' && break
  sleep 1
done
log "SOFT_STACK_REBUILT"
normal_power_up soft_stack_complete
rc=$?
log "ORCHESTRATOR_DONE rc=$rc"
exit "$rc"
