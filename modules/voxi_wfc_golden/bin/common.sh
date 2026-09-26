#!/system/bin/sh

# Shared read-only probes and exact-device safety gates for the dfd8241 port.

MODULE_VERSION=v1.0.0
DATA_DIR=/data/adb/voxi-wfc-golden
LOG_DIR="$DATA_DIR/logs"
STATE_DIR="$DATA_DIR/state"
CONFIG_FILE="$DATA_DIR/config.conf"
LOCK_DIR="$STATE_DIR/recovery.lock.d"
HOLDER_PIDFILE="$STATE_DIR/x55_holder.pid"
PROBE_JAR="$MODDIR/lib/wfc-probe.jar"
SUBSYS_PATH=/sys/bus/msm_subsys/devices/subsys10
ESOC_DEVICE=/dev/subsys_esoc0
ESOC_LOG=/sys/kernel/debug/ipc_logging/esoc-mdm/log

EXPECTED_DEVICE=cas
EXPECTED_ANDROID=13
EXPECTED_BUILD=V816.0.4.0.TJJCNXM
EXPECTED_FINGERPRINT='Xiaomi/cas/cas:13/TKQ1.221114.001/V816.0.4.0.TJJCNXM:user/release-keys'
EXPECTED_MODEM=SDX55M
SIM_POWER_TRANSACTION=182

PHONE_WRITE_COUNT=${PHONE_WRITE_COUNT:-0}
LOCK_OWNED=${LOCK_OWNED:-0}
LOG_FILE=${LOG_FILE:-}

ensure_storage() {
  umask 077
  mkdir -p "$LOG_DIR" "$STATE_DIR" || return 1
  chmod 0700 "$DATA_DIR" "$LOG_DIR" "$STATE_DIR" 2>/dev/null
}

require_root() {
  [ "$(id -u)" = 0 ] || { echo 'ERROR: 必须由 Magisk root 执行。' >&2; return 40; }
}

now_iso() { date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date; }
now_ms() { awk '{printf "%.0f\n", $1 * 1000}' /proc/uptime 2>/dev/null; }

log_line() {
  LINE="[$(date '+%H:%M:%S' 2>/dev/null)] $*"
  echo "$LINE"
  [ -n "$LOG_FILE" ] && printf '%s\n' "$LINE" >> "$LOG_FILE"
}

record_write() {
  PHONE_WRITE_COUNT=$((PHONE_WRITE_COUNT + 1))
  log_line "PHONE_WRITE_$PHONE_WRITE_COUNT=$*"
}

fail() {
  log_line "FAIL=$*"
  return 1
}

acquire_lock() {
  ensure_storage || return 1
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo 'RECOVERY_ALREADY_RUNNING'
    return 1
  fi
  LOCK_OWNED=1
  printf '%s\n' "$$" > "$LOCK_DIR/pid"
  chmod 0600 "$LOCK_DIR/pid" 2>/dev/null
}

release_lock() {
  if [ "$LOCK_OWNED" = 1 ]; then
    rm -rf "$LOCK_DIR"
    LOCK_OWNED=0
  fi
}

run_probe() {
  PROBE_RAW=$(CLASSPATH="$PROBE_JAR" app_process /system/bin WfcStateProbe read-only-json 2>&1)
  PROBE_RC=$?
  PROBE_JSON=$(printf '%s\n' "$PROBE_RAW" | sed -n '/^{/p' | tail -n 1)
  [ "$PROBE_RC" -eq 0 ] && [ -n "$PROBE_JSON" ]
}

json_object() { printf '%s\n' "$PROBE_JSON" | sed -n "s/.*\"$1\":{\([^}]*\)}.*/\1/p"; }
json_field() { printf '%s\n' "$1" | sed -n "s/.*\"$2\":\([^,}]*\).*/\1/p" | sed 's/^"//;s/"$//'; }
json_root_field() { printf '%s\n' "$PROBE_JSON" | sed -n "s/.*\"$1\":\([^,}]*\).*/\1/p" | sed 's/^"//;s/"$//'; }

load_probe_fields() {
  TARGET_OBJ=$(json_object target)
  SUB_OBJ=$(json_object subscription)
  IMS_OBJ=$(json_object ims)
  MMTEL_OBJ=$(json_object mmtel)
  WFC_OBJ=$(json_object wfc)
  CONN_OBJ=$(json_object connectivity)
  EPDG_OBJ=$(json_object epdg)

  TARGET_SUB=$(json_field "$TARGET_OBJ" subId)
  TARGET_SLOT=$(json_field "$TARGET_OBJ" slotId)
  TARGET_PHONE=$(json_field "$TARGET_OBJ" phoneId)
  TARGET_CARRIER=$(json_field "$TARGET_OBJ" carrierId)
  TARGET_MCC=$(json_field "$TARGET_OBJ" mcc)
  TARGET_MNC=$(json_field "$TARGET_OBJ" mnc)
  TARGET_GATE=$(json_field "$TARGET_OBJ" mappingGate)
  SUB_ACTIVE=$(json_field "$SUB_OBJ" active)
  UICC_ENABLED=$(json_field "$SUB_OBJ" areUiccApplicationsEnabled)
  IMS_STATE=$(json_field "$IMS_OBJ" registrationStateName)
  IMS_STATE_RAW=$(json_field "$IMS_OBJ" registrationStateRaw)
  IMS_TRANSPORT=$(json_field "$IMS_OBJ" registrationTransportName)
  IMS_TRANSPORT_RAW=$(json_field "$IMS_OBJ" registrationTransportRaw)
  VOICE_IWLAN=$(json_field "$MMTEL_OBJ" voiceIwlanAvailable)
  MMTEL_READY=$(json_field "$MMTEL_OBJ" featureState)
  WFC_AVAILABLE=$(json_field "$WFC_OBJ" wifiCallingAvailable)
  IMS_AGENT=$(json_field "$CONN_OBJ" imsIwlanNetworkAgent)
  QTI_REGISTERED=$(json_field "$CONN_OBJ" qtiCneRequestRegistered)
  QTI_ACTIVE=$(json_field "$CONN_OBJ" qtiCneRequestActive)
  QTI_REQUEST_ID=$(json_field "$CONN_OBJ" qtiCneRequestId)
  QTI_SATISFIED_ID=$(json_field "$CONN_OBJ" qtiCneSatisfiedRequestId)
  EPDG_KEEPALIVE=$(json_field "$EPDG_OBJ" udp4500Keepalive)
  XFRM_TUNNEL=$(json_field "$EPDG_OBJ" xfrmTunnel)
  DIRECT_HEALTH=$(json_root_field directWfcHealthy)
  FAILURE_CLASS=$(json_root_field failureClass)
}

probe_refresh() {
  run_probe || { log_line 'PROBE=FAIL'; return 1; }
  load_probe_fields
}

test_wfc_healthy() {
  probe_refresh || return 1
  [ "$IMS_STATE_RAW" = 2 ] && [ "$IMS_STATE" = REGISTERED ] &&
  [ "$IMS_TRANSPORT_RAW" = 2 ] && [ "$IMS_TRANSPORT" = WLAN ] &&
  [ "$VOICE_IWLAN" = true ] && [ "$WFC_AVAILABLE" = true ]
}

print_health() {
  probe_refresh || return 1
  echo "IMS=${IMS_STATE:-UNKNOWN} raw=${IMS_STATE_RAW:-UNKNOWN}"
  echo "TRANSPORT=${IMS_TRANSPORT:-UNKNOWN} raw=${IMS_TRANSPORT_RAW:-UNKNOWN}"
  echo "VOICE_IWLAN=${VOICE_IWLAN:-UNKNOWN}"
  echo "WFC=${WFC_AVAILABLE:-UNKNOWN}"
  echo "CNE registered=${QTI_REGISTERED:-UNKNOWN} active=${QTI_ACTIVE:-UNKNOWN} request=${QTI_REQUEST_ID:-null} satisfied=${QTI_SATISFIED_ID:-null}"
  echo "IMS_NETWORK_AGENT=${IMS_AGENT:-UNKNOWN} UDP4500=${EPDG_KEEPALIVE:-UNKNOWN} XFRM=${XFRM_TUNNEL:-UNKNOWN} MMTEL=${MMTEL_READY:-UNKNOWN}"
}

target_gate() {
  probe_refresh || return 1
  [ "$TARGET_GATE" = true ] && [ "$TARGET_SUB" = 11 ] && [ "$TARGET_SLOT" = 1 ] &&
  [ "$TARGET_PHONE" = 1 ] && [ "$TARGET_CARRIER" = 28 ] &&
  [ "$TARGET_MCC" = 234 ] && [ "$TARGET_MNC" = 15 ] &&
  [ "$SUB_ACTIVE" = true ] && [ "$UICC_ENABLED" = true ]
}

platform_gate() {
  [ "$(getprop ro.product.device)" = "$EXPECTED_DEVICE" ] || return 1
  [ "$(getprop ro.build.version.release)" = "$EXPECTED_ANDROID" ] || return 1
  [ "$(getprop ro.build.version.incremental)" = "$EXPECTED_BUILD" ] || return 1
  [ "$(getprop ro.build.fingerprint)" = "$EXPECTED_FINGERPRINT" ] || return 1
  [ "$(cat "$SUBSYS_PATH/name" 2>/dev/null)" = esoc0 ] || return 1
  [ "$(cat /sys/bus/esoc/devices/esoc0/esoc_name 2>/dev/null)" = "$EXPECTED_MODEM" ] || return 1
  target_gate
}

network_gate() {
  ip link show wlan0 2>/dev/null | grep -q 'UP' || return 1
  ip link show tun0 2>/dev/null | grep -q 'UP' || return 1
  ip route show table all 2>/dev/null | grep -E '^default([[:space:]]|$).*([[:space:]])dev[[:space:]]+tun0([[:space:]]|$)' >/dev/null || return 1
  CONN_TEXT=$(dumpsys connectivity 2>/dev/null)
  printf '%s\n' "$CONN_TEXT" | grep -qi 'VPN' || return 1
  printf '%s\n' "$CONN_TEXT" | grep -qi 'CONNECTED' || return 1
  printf '%s\n' "$CONN_TEXT" | grep -Eqi 'Transports:.*WIFI.*VPN|Transports:.*VPN.*WIFI' || return 1
}

get_airplane() { settings get global airplane_mode_on 2>/dev/null | tr -d '\r'; }
set_airplane() {
  WANT=$1
  [ "$(get_airplane)" = "$WANT" ] && return 0
  if [ "$WANT" = 1 ]; then ACTION=enable; else ACTION=disable; fi
  record_write "AIRPLANE_$ACTION"
  cmd connectivity airplane-mode "$ACTION" >/dev/null 2>&1 || return 1
  sleep 3
  [ "$(get_airplane)" = "$WANT" ]
}

ensure_wifi_on() {
  record_write 'WIFI_ENABLE'
  svc wifi enable >/dev/null 2>&1 || return 1
  sleep 3
  [ "$(settings get global wifi_on 2>/dev/null)" != 0 ]
}

get_x55_state() { cat "$SUBSYS_PATH/state" 2>/dev/null; }
get_vendor_x55_state() { getprop vendor.peripheral.SDX55M.state; }
get_crash_count() { cat "$SUBSYS_PATH/crash_count" 2>/dev/null; }
get_last_pon() { grep PON_SUCCESS "$ESOC_LOG" 2>/dev/null | tail -n 1; }
get_per_mgr_state() { getprop init.svc.vendor.per_mgr; }
get_per_mgr_pid() { getprop init.svc_debug_pid.vendor.per_mgr; }
get_per_mgr_exe() { PID=$(get_per_mgr_pid); [ -n "$PID" ] && readlink "/proc/$PID/exe" 2>/dev/null; }

owner_lines() { lsof "$ESOC_DEVICE" 2>/dev/null | grep "$ESOC_DEVICE" || true; }
owner_count() { owner_lines | awk 'NF {n++} END {print n+0}'; }
owner_has_pid() { OWNER_PID=$1; owner_lines | awk -v p="$OWNER_PID" '$2==p {found=1} END {exit !found}'; }

pm_owns_esoc() {
  PM_PID=$(get_per_mgr_pid)
  case "$PM_PID" in ''|*[!0-9]*) return 1;; esac
  [ "$(readlink "/proc/$PM_PID/exe" 2>/dev/null)" = /vendor/bin/pm-service ] && owner_has_pid "$PM_PID"
}

native_clean() {
  [ "$(get_per_mgr_state)" = running ] && pm_owns_esoc &&
  [ "$(owner_count)" -eq 1 ] && [ "$(get_x55_state)" = ONLINE ] &&
  case "$(get_crash_count)" in ''|*[!0-9]*) false;; *) true;; esac
}

saved_holder_pid() {
  [ -r "$HOLDER_PIDFILE" ] || return 1
  PID=$(cat "$HOLDER_PIDFILE" 2>/dev/null)
  case "$PID" in ''|*[!0-9]*) return 1;; esac
  echo "$PID"
}

holder_process_identity_ok() {
  HPID=$1
  case "$HPID" in ''|*[!0-9]*) return 1;; esac
  [ -d "/proc/$HPID" ] || return 1
  [ "$(readlink "/proc/$HPID/fd/9" 2>/dev/null)" = "$ESOC_DEVICE" ] || return 1
  CMDLINE=$(tr '\000' ' ' < "/proc/$HPID/cmdline" 2>/dev/null)
  printf '%s\n' "$CMDLINE" | grep -F "$MODDIR/bin/x55-holder.sh" >/dev/null || return 1
  owner_has_pid "$HPID"
}

holder_identity_ok() {
  HPID=$1
  holder_process_identity_ok "$HPID" && [ "$(owner_count)" -eq 1 ]
}

unknown_owner_present() {
  LINES=$(owner_lines)
  [ -z "$LINES" ] && return 1
  PM_PID=$(get_per_mgr_pid)
  HPID=$(saved_holder_pid 2>/dev/null || true)
  printf '%s\n' "$LINES" | awk -v pm="$PM_PID" -v hp="$HPID" '$2!=pm && $2!=hp {bad=1} END {exit !bad}'
}

wait_value() {
  COMMAND=$1 EXPECTED=$2 MAX=$3
  I=0
  while [ "$I" -lt "$MAX" ]; do
    [ "$(eval "$COMMAND")" = "$EXPECTED" ] && return 0
    sleep 1; I=$((I + 1))
  done
  return 1
}

wait_wfc_healthy() {
  MAX=$1 TAG=$2
  if [ "$MAX" -le 8 ]; then ELAPSED=3; else ELAPSED=5; fi
  sleep "$ELAPSED"
  CHECK=0
  while :; do
    CHECK=$((CHECK + 1))
    if test_wfc_healthy; then
      log_line "WFC_HEALTHY tag=$TAG elapsed=${ELAPSED}s check=$CHECK"
      return 0
    fi
    log_line "WFC_WAIT tag=$TAG elapsed=${ELAPSED}s ims=${IMS_STATE:-UNKNOWN}/${IMS_STATE_RAW:-UNKNOWN} transport=${IMS_TRANSPORT:-UNKNOWN}/${IMS_TRANSPORT_RAW:-UNKNOWN} wfc=${WFC_AVAILABLE:-UNKNOWN} cne=${QTI_REQUEST_ID:-null}"
    [ "$ELAPSED" -ge "$MAX" ] && return 1
    LEFT=$((MAX - ELAPSED)); [ "$LEFT" -gt 3 ] && SLEEP_FOR=3 || SLEEP_FOR=$LEFT
    [ "$SLEEP_FOR" -le 0 ] && return 1
    sleep "$SLEEP_FOR"; ELAPSED=$((ELAPSED + SLEEP_FOR))
  done
}

sanitize_stream() {
  sed -E \
    -e 's/(iccId=)[^ ,}]*/\1[REDACTED]/gI' \
    -e 's/(cardString=)[^ ,}]*/\1[REDACTED]/gI' \
    -e 's/(mNumber=)[^ ,}]*/\1[REDACTED]/gI' \
    -e 's/(imsi=)[^ ,}]*/\1[REDACTED]/gI' \
    -e 's/(subscriberId=)[^ ,}]*/\1[REDACTED]/gI' \
    -e 's/[0-9]{12,}/[REDACTED]/g'
}
