#!/system/bin/sh
set -u

STATE_DIR=/data/local/tmp/voxi-single-sim
LOG_FILE=$STATE_DIR/userspace-rebuild.log
PROBE_JAR=/data/adb/modules/voxi_wfc_recovery/lib/wfc-probe.jar

now() { date '+%Y-%m-%dT%H:%M:%S%z'; }
log() { echo "$(now) $*" >> "$LOG_FILE"; }
fail() { log "ABORT $*"; exit 20; }
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
  found=
  for p in $(pidof "$pname" 2>/dev/null); do
    [ "$(proc_uid "$p")" = "$expected_uid" ] || continue
    [ "$(proc_cmdline "$p")" = "$pname" ] || continue
    [ -z "$found" ] || return 1
    found=$p
  done
  [ -n "$found" ] || return 1
  echo "$found"
}

wait_init_new() {
  svc=$1 old=$2 name=$3 domain=$4 cmd=$5
  end=$(( $(date +%s) + 20 ))
  while [ "$(date +%s)" -lt "$end" ]; do
    p=$(verify_init "$svc" "$name" "$domain" "$cmd" 2>/dev/null || true)
    [ -n "$p" ] && [ "$p" != "$old" ] && { echo "$p"; return 0; }
    sleep 1
  done
  return 1
}

restart_init_once() {
  svc=$1 name=$2 domain=$3 cmd=$4 label=$5
  old=$(verify_init "$svc" "$name" "$domain" "$cmd") || fail "$label pre-identity"
  start=$(date +%s)
  log "TERM $label old=$old startEpoch=$start"
  kill -TERM "$old" || fail "$label TERM"
  new=$(wait_init_new "$svc" "$old" "$name" "$domain" "$cmd") || fail "$label no-new-pid"
  sleep 2
  [ "$(verify_init "$svc" "$name" "$domain" "$cmd")" = "$new" ] || fail "$label unstable-new-pid"
  end=$(date +%s)
  log "RESTARTED $label old=$old new=$new elapsedSec=$((end-start))"
}

wait_app_new() {
  pname=$1 uid=$2 old=$3
  end=$(( $(date +%s) + 20 ))
  while [ "$(date +%s)" -lt "$end" ]; do
    p=$(find_exact_app "$pname" "$uid" 2>/dev/null || true)
    [ -n "$p" ] && [ "$p" != "$old" ] && { echo "$p"; return 0; }
    sleep 1
  done
  return 1
}

restart_app_once() {
  pname=$1 uid=$2 label=$3
  old=$(find_exact_app "$pname" "$uid") || fail "$label pre-identity"
  start=$(date +%s)
  log "TERM $label old=$old startEpoch=$start"
  kill -TERM "$old" || fail "$label TERM"
  new=$(wait_app_new "$pname" "$uid" "$old") || fail "$label no-new-pid"
  sleep 2
  [ "$(find_exact_app "$pname" "$uid")" = "$new" ] || fail "$label unstable-new-pid"
  end=$(date +%s)
  log "RESTARTED $label old=$old new=$new elapsedSec=$((end-start))"
}

wait_ims_service_bind() {
  end=$(( $(date +%s) + 20 ))
  while [ "$(date +%s)" -lt "$end" ]; do
    dumpsys activity services org.codeaurora.ims 2>/dev/null | grep -Fq 'org.codeaurora.ims/.ImsService' && return 0
    sleep 1
  done
  return 1
}

probe() { CLASSPATH="$PROBE_JAR" app_process /system/bin WfcStateProbe read-only-json; }

[ "$#" -eq 0 ] || fail arguments
[ "${SINGLE_SIM_USERSPACE_LAB_MODE:-0}" = 1 ] || fail lab-mode
[ "${SINGLE_SIM_USERSPACE_EXECUTE:-NO}" = YES ] || fail execute-lock
[ "$(id -u)" = 0 ] || fail uid0
[ "$(getprop gsm.sim.state)" = 'ABSENT,LOADED' ] || fail sim-state

pre=$(probe 2>&1) || fail probe
echo "$pre" | grep -Fq '"target":{"subId":11,"slotId":1,"phoneId":1,"carrierId":28,"mcc":234,"mnc":15,"mappingGate":true}' || fail target-map
echo "$pre" | grep -Fq '"protectedSlot0":{"subId":1,"slotId":null,"carrierId":null,"mcc":null,"mnc":null,"active":false' || fail slot0-absent
echo "$pre" | grep -Fq '"subscription":{"active":true,"areUiccApplicationsEnabled":true' || fail active-enabled
echo "$pre" | grep -Fq '"failureClass":"F1"' || fail strict-f1

QCRILD=$(verify_init vendor.qcrild main u:r:rild:s0 '/vendor/bin/hw/qcrild') || fail protected-qcrild
QCRILD2=$(verify_init vendor.qcrild2 main u:r:rild:s0 '-c 2') || fail protected-qcrild2
NETMGRD=$(verify_init vendor.netmgrd netmgrd u:r:vendor_netmgrd:s0 '/vendor/bin/netmgrd') || fail protected-netmgrd
PHONE=$(find_exact_app com.android.phone 1001) || fail protected-phone
SYSTEM=$(find_exact_app system_server 1000) || fail protected-system-server
log "PRE F1 slot0=ABSENT qcrild=$QCRILD qcrild2=$QCRILD2 netmgrd=$NETMGRD phone=$PHONE system_server=$SYSTEM"

IMSDATA_PRE=$(verify_init vendor.imsdatadaemon imsdatadaemon u:r:vendor_ims:s0 '/vendor/bin/imsdatadaemon') || fail pre-imsdata
IMSQMI_PRE=$(verify_init vendor.imsqmidaemon imsqmidaemon u:r:vendor_ims:s0 '/vendor/bin/imsqmidaemon') || fail pre-imsqmi
CND_PRE=$(verify_init vendor.cnd cnd u:r:vendor_cnd:s0 '/system/vendor/bin/cnd') || fail pre-cnd
QTIDATA_PRE=$(find_exact_app .qtidataservices 10104) || fail pre-qtidataservices
QCOMIMS_PRE=$(find_exact_app org.codeaurora.ims 10196) || fail pre-qcomims
log "TARGETS imsdata=$IMSDATA_PRE imsqmi=$IMSQMI_PRE cnd=$CND_PRE qtidataservices=$QTIDATA_PRE qcomims=$QCOMIMS_PRE"

restart_init_once vendor.imsdatadaemon imsdatadaemon u:r:vendor_ims:s0 '/vendor/bin/imsdatadaemon' IMSDATA
restart_init_once vendor.imsqmidaemon imsqmidaemon u:r:vendor_ims:s0 '/vendor/bin/imsqmidaemon' IMSQMI
restart_init_once vendor.cnd cnd u:r:vendor_cnd:s0 '/system/vendor/bin/cnd' CND
restart_app_once .qtidataservices 10104 QTIDATASERVICES
restart_app_once org.codeaurora.ims 10196 QCOMIMS
wait_ims_service_bind || fail qcomims-service-not-bound
log 'IMS_SERVICE_BOUND org.codeaurora.ims/.ImsService'

[ "$(verify_init vendor.qcrild main u:r:rild:s0 '/vendor/bin/hw/qcrild')" = "$QCRILD" ] || fail qcrild-changed
[ "$(verify_init vendor.qcrild2 main u:r:rild:s0 '-c 2')" = "$QCRILD2" ] || fail qcrild2-changed
[ "$(verify_init vendor.netmgrd netmgrd u:r:vendor_netmgrd:s0 '/vendor/bin/netmgrd')" = "$NETMGRD" ] || fail netmgrd-changed
[ "$(find_exact_app com.android.phone 1001)" = "$PHONE" ] || fail phone-changed
[ "$(find_exact_app system_server 1000)" = "$SYSTEM" ] || fail system-server-changed
[ "$(getprop gsm.sim.state)" = 'ABSENT,LOADED' ] || fail final-sim-state

log 'REBUILD_COMPLETE protected-processes-unchanged'
exit 0
