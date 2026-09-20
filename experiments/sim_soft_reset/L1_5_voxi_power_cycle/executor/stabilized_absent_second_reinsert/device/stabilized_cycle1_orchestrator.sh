#!/system/bin/sh
set -u
STATE_DIR=/data/local/tmp/voxi-l1_5-executor
HELPER_JAR=$STATE_DIR/slot1-sim-power-helper.jar
LOG_FILE=$STATE_DIR/stabilized-cycle1-orchestrator.log
READY_FILE=$STATE_DIR/stabilized-watchdog-cycle1.ready
EXPECTED_HELPER_SHA256=be877b6e9694b4100f2487dc892803de6399c89588f194a1e54d4c3ae3173a31
NORMAL_UP_LIMIT=180
now() { date '+%Y-%m-%dT%H:%M:%S%z'; }
log() { echo "$(now) $*" >> "$LOG_FILE"; }
helper() { LAB_MODE=1 LAB_EXECUTE=YES CLASSPATH="$HELPER_JAR" app_process /system/bin Slot1SimPowerHelper "$1"; }
fail_pre() { log "ABORT_PRE_DOWN $*"; exit 20; }
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
    echo "$p"; return 0
  done
  return 1
}
check_up_deadline() {
  [ "$(date +%s)" -lt "$UP_DEADLINE" ] || { log "NORMAL_POWER_UP_DEADLINE_EXCEEDED"; exit 60; }
}
wait_init_new() {
  svc=$1 old=$2 name=$3 domain=$4 cmd=$5
  end=$(( $(date +%s) + 15 ))
  while [ "$(date +%s)" -lt "$end" ]; do
    check_up_deadline
    p=$(verify_init "$svc" "$name" "$domain" "$cmd" 2>/dev/null || true)
    [ -n "$p" ] && [ "$p" != "$old" ] && { echo "$p"; return 0; }
    sleep 1
  done
  return 1
}
restart_init_live() {
  svc=$1 name=$2 domain=$3 cmd=$4 label=$5
  old=$(verify_init "$svc" "$name" "$domain" "$cmd") || return 1
  log "TERM $label exactPid=$old"
  kill -TERM "$old" || return 1
  new=$(wait_init_new "$svc" "$old" "$name" "$domain" "$cmd") || return 1
  eval "${label}_PID=$new"
  log "RESTARTED $label old=$old new=$new"
}
wait_app_new() {
  pname=$1 uid=$2 old=$3
  end=$(( $(date +%s) + 20 ))
  while [ "$(date +%s)" -lt "$end" ]; do
    check_up_deadline
    p=$(find_exact_app "$pname" "$uid" 2>/dev/null || true)
    [ -n "$p" ] && [ "$p" != "$old" ] && { echo "$p"; return 0; }
    sleep 1
  done
  return 1
}
restart_app_live() {
  pname=$1 uid=$2 label=$3
  old=$(find_exact_app "$pname" "$uid") || return 1
  log "TERM $label exactPid=$old"
  kill -TERM "$old" || return 1
  new=$(wait_app_new "$pname" "$uid" "$old") || return 1
  eval "${label}_PID=$new"
  log "RESTARTED $label old=$old new=$new"
}
service_found() { service check "$1" 2>/dev/null | grep -q 'found'; }
network_ready() { ip link show wlan0 2>/dev/null | grep -q '<[^>]*UP' && ip link show tun0 2>/dev/null | grep -q '<[^>]*UP'; }
app_is() { [ "$(find_exact_app "$1" "$2" 2>/dev/null || true)" = "$3" ]; }
init_is() { [ "$(verify_init "$1" "$2" "$3" "$4" 2>/dev/null || true)" = "$5" ]; }
stable_once() {
  init_is vendor.qcrild2 main u:r:rild:s0 '-c 2' "$QCRILD2_PID" || return 1
  init_is vendor.qcrild main u:r:rild:s0 '/vendor/bin/hw/qcrild' "$QCRILD_PID" || return 1
  init_is vendor.netmgrd netmgrd u:r:vendor_netmgrd:s0 '/vendor/bin/netmgrd' "$NETMGRD_PID" || return 1
  init_is vendor.imsqmidaemon imsqmidaemon u:r:vendor_ims:s0 '/vendor/bin/imsqmidaemon' "$IMSQMI_PID" || return 1
  init_is vendor.imsdatadaemon imsdatadaemon u:r:vendor_ims:s0 '/vendor/bin/imsdatadaemon' "$IMSDATA_PID" || return 1
  init_is vendor.cnd cnd u:r:vendor_cnd:s0 '/system/vendor/bin/cnd' "$CND_PID" || return 1
  app_is .qtidataservices 10104 "$QTIDATA_PID" || return 1
  app_is org.codeaurora.ims 10196 "$QCOMIMS_PID" || return 1
  app_is com.android.phone 1001 "$PHONE_PID" || return 1
  app_is system_server 1000 "$SYSTEM_PID" || return 1
  service_found phone && service_found isub && service_found connectivity || return 1
  network_ready || return 1
  services=$(dumpsys activity services vendor.qti.iwlan 2>/dev/null) || return 1
  echo "$services" | grep -q 'IWlanDataService' || return 1
  echo "$services" | grep -q 'IWlanNetworkService' || return 1
  echo "$services" | grep -q 'QualifiedNetworksServiceImpl' || return 1
  return 0
}

[ "$#" -eq 0 ] || fail_pre arguments
[ "${ABSENT_LAB_MODE:-0}" = 1 ] || fail_pre ABSENT_LAB_MODE
[ "${ABSENT_EXECUTE:-NO}" = YES ] || fail_pre ABSENT_EXECUTE
[ "$(id -u)" = 0 ] || fail_pre UID0
[ "$(sha256sum "$HELPER_JAR" | awk '{print $1}')" = "$EXPECTED_HELPER_SHA256" ] || fail_pre helper_hash
[ -f "$READY_FILE" ] && [ -f "$STATE_DIR/watchdog.ready" ] || fail_pre watchdog_ready
network_ready || fail_pre network
pre=$(CLASSPATH="$HELPER_JAR" app_process /system/bin Slot1SimPowerHelper DRY_RUN 2>&1) || fail_pre dry_run
printf '%s\n' "$pre" >> "$LOG_FILE"
echo "$pre" | grep -q 'before.strictGate=true' || fail_pre strict_gate
echo "$pre" | grep -q 'before.ims=registrationState=0 transport=-1' || fail_pre strict_F1
echo "$pre" | grep -q 'before.wfc=available=false' || fail_pre strict_F1_wfc

log "POWER_DOWN_START"
helper POWER_DOWN >> "$LOG_FILE" 2>&1 || { log "POWER_DOWN_FAILED"; exit 30; }
DOWN_EPOCH=$(stat -c %Y "$STATE_DIR/power_down.sent") || exit 31
UP_DEADLINE=$((DOWN_EPOCH + NORMAL_UP_LIMIT))
log "T0 POWER_DOWN callback accepted downEpoch=$DOWN_EPOCH normalUpDeadline=$UP_DEADLINE"

absent=0
end=$(( $(date +%s) + 30 ))
while [ "$(date +%s)" -lt "$end" ]; do
  state=$(CLASSPATH="$HELPER_JAR" app_process /system/bin Slot1SimPowerHelper DRY_RUN 2>&1 || true)
  target=$(echo "$state" | grep '^before.target=' | head -n 1)
  slot0=$(echo "$state" | grep '^before.slot0=' | head -n 1)
  echo "$slot0" | grep -q 'active=true.*simState=5.*mappingGate=true' || exit 32
  echo "$target" | grep -q 'active=false.*uiccEnabled=false.*simState=1.*mappingGate=false' && { absent=1; log "T1 TRUE_ABSENT $target"; break; }
  sleep 1
done
[ "$absent" -eq 1 ] || { log "TRUE_ABSENT_NOT_CONFIRMED"; exit 33; }
sleep 10
log "T2 SOFT_STACK_START after_exact_10s_absent_hold"

restart_init_live vendor.qcrild2 main u:r:rild:s0 '-c 2' QCRILD2 || exit 41
restart_init_live vendor.qcrild main u:r:rild:s0 '/vendor/bin/hw/qcrild' QCRILD || exit 42
restart_init_live vendor.netmgrd netmgrd u:r:vendor_netmgrd:s0 '/vendor/bin/netmgrd' NETMGRD || exit 43
restart_init_live vendor.imsqmidaemon imsqmidaemon u:r:vendor_ims:s0 '/vendor/bin/imsqmidaemon' IMSQMI || exit 44
restart_init_live vendor.imsdatadaemon imsdatadaemon u:r:vendor_ims:s0 '/vendor/bin/imsdatadaemon' IMSDATA || exit 45
restart_init_live vendor.cnd cnd u:r:vendor_cnd:s0 '/system/vendor/bin/cnd' CND || exit 46
restart_app_live .qtidataservices 10104 QTIDATA || exit 47
restart_app_live org.codeaurora.ims 10196 QCOMIMS || exit 48
restart_app_live com.android.phone 1001 PHONE || exit 49
restart_app_live system_server 1000 SYSTEM || exit 50
log "T3 SYSTEM_SERVER_NEW pid=$SYSTEM_PID"

stable_count=0
STABILITY_SINCE=$(date '+%m-%d %H:%M:%S.000')
while [ "$stable_count" -lt 15 ]; do
  check_up_deadline
  if stable_once; then stable_count=$((stable_count + 1)); else stable_count=0; fi
  sleep 1
done
log "T5 STABLE_GATE_15S_PASS"
sleep 20
check_up_deadline
stable_once || { log "EXTRA20_RECHECK_FAILED"; exit 51; }
logcat -b all -d -T "$STABILITY_SINCE" 2>/dev/null | grep -iE 'QtiBus.*serverDied|serverDied.*QtiBus' && { log "QTIBUS_SERVERDIED_DURING_STABLE_GATE"; exit 52; }
log "T6 EXTRA20_PASS services=phone,isub,connectivity iwlan=bound network=ready qtibus=no_serverDied"
check_up_deadline
log "NORMAL_POWER_UP_START"
helper POWER_UP >> "$LOG_FILE" 2>&1 || { log "NORMAL_POWER_UP_FAILED"; exit 53; }
[ -f "$STATE_DIR/power_up.confirmed" ] || { log "NORMAL_POWER_UP_NO_CALLBACK_MARKER"; exit 54; }
log "T7 NORMAL_POWER_UP_CALLBACK_CONFIRMED"
exit 0