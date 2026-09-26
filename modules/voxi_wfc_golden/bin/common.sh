#!/system/bin/sh

# Shared read-only probes and exact-device safety gates for the dfd8241 port.

MODULE_VERSION=v1.1.0-rc6
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
STATE_WRITE_COUNT=${STATE_WRITE_COUNT:-0}
MODEM_WRITE_COUNT=${MODEM_WRITE_COUNT:-0}
SIM_WRITE_COUNT=${SIM_WRITE_COUNT:-0}
FILESYSTEM_WRITE_COUNT=${FILESYSTEM_WRITE_COUNT:-0}
LOCK_OWNED=${LOCK_OWNED:-0}
LOG_FILE=${LOG_FILE:-}

ensure_storage() {
  umask 077
  mkdir -p "$LOG_DIR" "$STATE_DIR" || return 40
  chmod 0700 "$DATA_DIR" "$LOG_DIR" "$STATE_DIR" 2>/dev/null || return 40
  return 0
}

require_root() {
  if [ "$(id -u)" != 0 ]; then
    echo 'ERROR: 必须由 Magisk root 执行。' >&2
    return 40
  fi
  return 0
}

now_iso() {
  VALUE=$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)
  if [ -n "$VALUE" ]; then printf '%s\n' "$VALUE"; else date; fi
  return 0
}
now_ms() { awk '{printf "%.0f\n", $1 * 1000}' /proc/uptime 2>/dev/null; }

log_line() {
  LINE="[$(date '+%H:%M:%S' 2>/dev/null)] $*"
  echo "$LINE"
  if [ -n "$LOG_FILE" ]; then
    printf '%s\n' "$LINE" >> "$LOG_FILE"
  fi
  return 0
}

record_write() {
  PHONE_WRITE_COUNT=$((PHONE_WRITE_COUNT + 1))
  STATE_WRITE_COUNT=$((STATE_WRITE_COUNT + 1))
  case "$*" in
    SIM_POWER_*) SIM_WRITE_COUNT=$((SIM_WRITE_COUNT + 1)) ;;
    *vendor.per_mgr*|*vendor.qcrild2*|HOLDER_*) MODEM_WRITE_COUNT=$((MODEM_WRITE_COUNT + 1)) ;;
  esac
  log_line "PHONE_WRITE_$PHONE_WRITE_COUNT=$*"
  return 0
}

fail() {
  log_line "FAIL=$*"
  return 1
}

acquire_lock() {
  ensure_storage
  RC=$?
  if [ "$RC" -ne 0 ]; then return 40; fi
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo 'RECOVERY_ALREADY_RUNNING'
    return 50
  fi
  LOCK_OWNED=1
  printf '%s\n' "$$" > "$LOCK_DIR/pid"
  chmod 0600 "$LOCK_DIR/pid" 2>/dev/null
  return 0
}

release_lock() {
  if [ "$LOCK_OWNED" = 1 ]; then
    rm -rf "$LOCK_DIR"
    LOCK_OWNED=0
  fi
  return 0
}

run_probe() {
  PROBE_RAW=$(CLASSPATH="$PROBE_JAR" app_process /system/bin WfcStateProbe read-only-json 2>&1)
  PROBE_RC=$?
  PROBE_JSON=$(printf '%s\n' "$PROBE_RAW" | sed -n '/^{/p' | tail -n 1)
  if [ "$PROBE_RC" -ne 0 ] || [ -z "$PROBE_JSON" ]; then
    return 40
  fi
  return 0
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
  return 0
}

probe_refresh() {
  run_probe
  RC=$?
  if [ "$RC" -ne 0 ]; then
    log_line 'PROBE=FAIL'
    return 40
  fi
  load_probe_fields
  RC=$?
  if [ "$RC" -ne 0 ]; then return 40; fi
  return 0
}

is_wfc_healthy() {
  probe_refresh
  RC=$?
  if [ "$RC" -ne 0 ]; then return 1; fi
  if [ "$IMS_STATE_RAW" = 2 ] && [ "$IMS_STATE" = REGISTERED ] &&
     [ "$IMS_TRANSPORT_RAW" = 2 ] && [ "$IMS_TRANSPORT" = WLAN ] &&
     [ "$VOICE_IWLAN" = true ] && [ "$WFC_AVAILABLE" = true ]; then
    return 0
  fi
  return 1
}

test_wfc_healthy() { if is_wfc_healthy; then return 0; fi; return 1; }

print_health() {
  echo "IMS=${IMS_STATE:-UNKNOWN} raw=${IMS_STATE_RAW:-UNKNOWN}"
  echo "TRANSPORT=${IMS_TRANSPORT:-UNKNOWN} raw=${IMS_TRANSPORT_RAW:-UNKNOWN}"
  echo "VOICE_IWLAN=${VOICE_IWLAN:-UNKNOWN}"
  echo "WFC=${WFC_AVAILABLE:-UNKNOWN}"
  echo "CNE registered=${QTI_REGISTERED:-UNKNOWN} active=${QTI_ACTIVE:-UNKNOWN} request=${QTI_REQUEST_ID:-null} satisfied=${QTI_SATISFIED_ID:-null}"
  echo "IMS_NETWORK_AGENT=${IMS_AGENT:-UNKNOWN} UDP4500=${EPDG_KEEPALIVE:-UNKNOWN} XFRM=${XFRM_TUNNEL:-UNKNOWN} MMTEL=${MMTEL_READY:-UNKNOWN}"
  return 0
}

is_target_mapping_valid() {
  if [ "$TARGET_GATE" = true ] && [ "$TARGET_SUB" = 11 ] && [ "$TARGET_SLOT" = 1 ] &&
     [ "$TARGET_PHONE" = 1 ] && [ "$TARGET_CARRIER" = 28 ] &&
     [ "$TARGET_MCC" = 234 ] && [ "$TARGET_MNC" = 15 ] &&
     [ "$SUB_ACTIVE" = true ] && [ "$UICC_ENABLED" = true ]; then
    return 0
  fi
  return 1
}

target_gate() {
  probe_refresh
  RC=$?
  if [ "$RC" -ne 0 ]; then return 1; fi
  if is_target_mapping_valid; then return 0; fi
  return 1
}

collect_platform_status() {
  PLATFORM_DEVICE=$(getprop ro.product.device 2>/dev/null)
  PLATFORM_ANDROID=$(getprop ro.build.version.release 2>/dev/null)
  PLATFORM_BUILD=$(getprop ro.build.version.incremental 2>/dev/null)
  PLATFORM_FINGERPRINT=$(getprop ro.build.fingerprint 2>/dev/null)
  PLATFORM_SUBSYSTEM=$(cat "$SUBSYS_PATH/name" 2>/dev/null)
  PLATFORM_MODEM=$(cat /sys/bus/esoc/devices/esoc0/esoc_name 2>/dev/null)
  return 0
}

is_platform_supported() {
  if [ "$PLATFORM_DEVICE" = "$EXPECTED_DEVICE" ] &&
     [ "$PLATFORM_ANDROID" = "$EXPECTED_ANDROID" ] &&
     [ "$PLATFORM_BUILD" = "$EXPECTED_BUILD" ] &&
     [ "$PLATFORM_FINGERPRINT" = "$EXPECTED_FINGERPRINT" ] &&
     [ "$PLATFORM_SUBSYSTEM" = esoc0 ] &&
     [ "$PLATFORM_MODEM" = "$EXPECTED_MODEM" ]; then
    return 0
  fi
  return 1
}

platform_gate() {
  collect_platform_status
  if ! is_platform_supported; then return 1; fi
  if target_gate; then return 0; fi
  return 1
}

is_wifi_ready_now() {
  WIFI_SETTING=$(settings get global wifi_on 2>/dev/null | tr -d '\r')
  WIFI_LINK=$(ip link show wlan0 2>/dev/null)
  if [ "$WIFI_SETTING" != 0 ] && [ -n "$WIFI_LINK" ] && printf '%s\n' "$WIFI_LINK" | grep -q 'UP'; then
    return 0
  fi
  return 1
}

wifi_ready_now() { if is_wifi_ready_now; then return 0; fi; return 1; }

collect_network_status() {
  WIFI_SETTING=$(settings get global wifi_on 2>/dev/null | tr -d '\r')
  WIFI_LINK=$(ip link show wlan0 2>/dev/null)
  if [ -z "$WIFI_LINK" ]; then WIFI_INTERFACE=MISSING
  elif printf '%s\n' "$WIFI_LINK" | grep -q 'UP'; then WIFI_INTERFACE=UP
  else WIFI_INTERFACE=DOWN
  fi

  CONN_TEXT=$(dumpsys connectivity 2>/dev/null)
  WIFI_CONNECTED=UNVERIFIED
  if printf '%s\n' "$CONN_TEXT" | grep -Eqi 'Transports:.*WIFI' &&
     printf '%s\n' "$CONN_TEXT" | grep -qi 'CONNECTED'; then
    WIFI_CONNECTED=YES
  elif ip addr show wlan0 2>/dev/null | grep -q 'inet '; then
    WIFI_CONNECTED=LIKELY
  fi

  VPN_TEXT=$(dumpsys vpn 2>/dev/null)
  VPN_DETECTED=NO
  VPN_INTERFACE=UNKNOWN
  VPN_ROUTE_HINT=NONE
  VPN_DETECTION_METHOD=NONE

  if printf '%s\n' "$CONN_TEXT" | grep -Eqi 'TRANSPORT_VPN|Transports:.*VPN|VpnTransportInfo|type:[[:space:]]*VPN|VPN.*CONNECTED|CONNECTED.*VPN'; then
    VPN_DETECTED=YES
    VPN_DETECTION_METHOD=CONNECTIVITY
  fi
  if printf '%s\n' "$VPN_TEXT" | grep -Eqi 'NetworkInfo.*CONNECTED|VpnConfig|mConfig=.*user='; then
    VPN_DETECTED=YES
    if [ "$VPN_DETECTION_METHOD" = NONE ]; then VPN_DETECTION_METHOD=VPN_DUMPSYS; else VPN_DETECTION_METHOD="${VPN_DETECTION_METHOD}+VPN_DUMPSYS"; fi
  fi

  VPN_INTERFACE=$(printf '%s\n' "$VPN_TEXT" | sed -n -E 's/.*(mInterface|interface|InterfaceName)[=: ]+([^, }]+).*/\2/p' | head -n 1)
  if [ -z "$VPN_INTERFACE" ]; then
    VPN_INTERFACE=$(ip -o link show 2>/dev/null | awk -F': ' '$2 ~ /^(tun|tap|wg|ppp|clash)/ {sub(/@.*/,"",$2); print $2; exit}')
    if [ -n "$VPN_INTERFACE" ]; then
      VPN_DETECTED=YES
      if [ "$VPN_DETECTION_METHOD" = NONE ]; then VPN_DETECTION_METHOD=IP_LINK; else VPN_DETECTION_METHOD="${VPN_DETECTION_METHOD}+IP_LINK"; fi
    fi
  fi
  if [ -z "$VPN_INTERFACE" ]; then VPN_INTERFACE=UNKNOWN; fi

  if ip rule show 2>/dev/null | grep -Eqi 'fwmark|lookup.*(vpn|tun)'; then
    VPN_ROUTE_HINT=POLICY_ROUTING_PRESENT
  elif [ "$VPN_INTERFACE" != UNKNOWN ] && ip route show table all 2>/dev/null | grep -F "dev $VPN_INTERFACE" >/dev/null; then
    VPN_ROUTE_HINT=INTERFACE_ROUTE_PRESENT
  fi
  return 0
}

print_network_status() {
  echo "WIFI_SETTING=${WIFI_SETTING:-UNKNOWN}"
  echo "WIFI_INTERFACE=${WIFI_INTERFACE:-UNKNOWN}"
  echo "WIFI_CONNECTED=${WIFI_CONNECTED:-UNVERIFIED}"
  echo "VPN_DETECTED=${VPN_DETECTED:-NO}"
  echo "VPN_INTERFACE=${VPN_INTERFACE:-UNKNOWN}"
  echo "VPN_ROUTE_HINT=${VPN_ROUTE_HINT:-NONE}"
  echo "VPN_DETECTION_METHOD=${VPN_DETECTION_METHOD:-NONE}"
  return 0
}

network_preflight() {
  MAX_WAIT=${1:-20}
  ELAPSED=0
  while ! is_wifi_ready_now; do
    if [ "$ELAPSED" -ge "$MAX_WAIT" ]; then break; fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
  done
  collect_network_status
  print_network_status
  if ! is_wifi_ready_now; then
    echo 'WIFI=NOT_READY'
    echo 'NETWORK_PREFLIGHT=FAIL'
    return 30
  fi
  echo 'WIFI=READY'
  if [ "$VPN_DETECTED" = YES ]; then
    echo 'VPN=DETECTED'
  else
    echo 'VPN=UNVERIFIED'
    echo 'WARNING=Please confirm UK full-tunnel VPN is connected'
  fi
  echo 'NETWORK_PREFLIGHT=PASS'
  return 0
}

get_airplane() { settings get global airplane_mode_on 2>/dev/null | tr -d '\r'; }
set_airplane() {
  WANT=$1
  if [ "$(get_airplane)" = "$WANT" ]; then return 0; fi
  if [ "$WANT" = 1 ]; then ACTION=enable; else ACTION=disable; fi
  record_write "AIRPLANE_$ACTION"
  cmd connectivity airplane-mode "$ACTION" >/dev/null 2>&1
  RC=$?
  if [ "$RC" -ne 0 ]; then return 60; fi
  sleep 3
  if [ "$(get_airplane)" = "$WANT" ]; then return 0; fi
  return 60
}

ensure_wifi_on() {
  WIFI_ENSURE_MODE=${1:-normal}
  if [ "$WIFI_ENSURE_MODE" != force ] && is_wifi_ready_now; then
    log_line 'WIFI_ENSURE=ALREADY_READY'
    return 0
  fi

  if [ "$WIFI_ENSURE_MODE" = force ]; then
    log_line 'WIFI_ENSURE=FORCE_AFTER_AIRPLANE'
    record_write 'WIFI_ENABLE_AFTER_AIRPLANE'
  else
    log_line 'WIFI_ENSURE=ENABLE'
    record_write 'WIFI_ENABLE'
  fi

  svc wifi enable >/dev/null 2>&1
  RC=$?
  if [ "$RC" -ne 0 ]; then
    log_line "WIFI_ENABLE_CMD=FAIL rc=$RC"
    return 60
  fi

  WIFI_WAIT=0
  while [ "$WIFI_WAIT" -lt 15 ]; do
    if is_wifi_ready_now; then
      log_line "WIFI_ENSURE=READY elapsed=${WIFI_WAIT}s"
      return 0
    fi
    sleep 1
    WIFI_WAIT=$((WIFI_WAIT + 1))
  done

  log_line 'WIFI_ENSURE=FAIL wlan0_not_ready_after_15s'
  return 60
}

get_x55_state() { cat "$SUBSYS_PATH/state" 2>/dev/null; }
get_vendor_x55_state() { getprop vendor.peripheral.SDX55M.state; }
get_crash_count() { cat "$SUBSYS_PATH/crash_count" 2>/dev/null; }
get_last_pon() { grep PON_SUCCESS "$ESOC_LOG" 2>/dev/null | tail -n 1; }
get_per_mgr_state() { getprop init.svc.vendor.per_mgr; }
get_per_mgr_pid() { getprop init.svc_debug_pid.vendor.per_mgr; }
get_per_mgr_exe() {
  PID=$(get_per_mgr_pid)
  if [ -n "$PID" ]; then readlink "/proc/$PID/exe" 2>/dev/null; fi
  return 0
}

owner_lines() {
  lsof "$ESOC_DEVICE" 2>/dev/null | grep "$ESOC_DEVICE"
  return 0
}
owner_count() { owner_lines | awk 'NF {n++} END {print n+0}'; }
owner_has_pid() { OWNER_PID=$1; owner_lines | awk -v p="$OWNER_PID" '$2==p {found=1} END {exit !found}'; }

snapshot_owner_has_pid() {
  OWNER_PID=$1
  printf '%s\n' "$ESOC_OWNER_LINES_SNAPSHOT" | awk -v p="$OWNER_PID" '$2==p {found=1} END {exit !found}'
}

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
  if [ ! -r "$HOLDER_PIDFILE" ]; then return 1; fi
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
  ESOC_UNKNOWN_OWNER_LINES=$(owner_lines)
  if [ -z "$ESOC_UNKNOWN_OWNER_LINES" ]; then return 1; fi
  PM_PID=$(get_per_mgr_pid)
  HPID=$(saved_holder_pid 2>/dev/null || true)
  printf '%s\n' "$ESOC_UNKNOWN_OWNER_LINES" | awk -v pm="$PM_PID" -v hp="$HPID" '$2!=pm && $2!=hp {bad=1} END {exit !bad}'
  UNKNOWN_OWNER_RC=$?
  if [ "$UNKNOWN_OWNER_RC" -eq 0 ]; then return 0; fi
  return 1
}

collect_owner_entry_status() {
  PER_MGR_STATE=$(get_per_mgr_state)
  PER_MGR_PID=$(get_per_mgr_pid)
  PER_MGR_EXE=$(get_per_mgr_exe)
  X55_STATE=$(get_x55_state)
  ESOC_OWNER_LINES_SNAPSHOT=$(owner_lines)
  ESOC_OWNER_COUNT=$(printf '%s\n' "$ESOC_OWNER_LINES_SNAPSHOT" | awk 'NF {n++} END {print n+0}')
  MODULE_HOLDER_PIDFILE_PRESENT=NO
  MODULE_HOLDER_PID=NONE
  MODULE_HOLDER_ALIVE=NO
  MODULE_HOLDER_IDENTITY=NO
  STALE_PIDFILE=NO

  if [ -r "$HOLDER_PIDFILE" ]; then
    MODULE_HOLDER_PIDFILE_PRESENT=YES
    MODULE_HOLDER_PID=$(cat "$HOLDER_PIDFILE" 2>/dev/null)
    case "$MODULE_HOLDER_PID" in
      ''|*[!0-9]*)
        MODULE_HOLDER_PID=INVALID
        MODULE_HOLDER_IDENTITY=MISMATCH
        ;;
      *)
        if [ -d "/proc/$MODULE_HOLDER_PID" ]; then
          MODULE_HOLDER_ALIVE=YES
          if [ "$(readlink "/proc/$MODULE_HOLDER_PID/fd/9" 2>/dev/null)" = "$ESOC_DEVICE" ]; then
            CMDLINE=$(tr '\000' ' ' < "/proc/$MODULE_HOLDER_PID/cmdline" 2>/dev/null)
            if printf '%s\n' "$CMDLINE" | grep -F "$MODDIR/bin/x55-holder.sh" >/dev/null; then
              MODULE_HOLDER_IDENTITY=EXACT
            else
              MODULE_HOLDER_IDENTITY=MISMATCH
            fi
          else
            MODULE_HOLDER_IDENTITY=MISMATCH
          fi
        else
          STALE_PIDFILE=YES
        fi
        ;;
    esac
  fi

  return 0
}

classify_owner_entry_status() {
  if [ "$MODULE_HOLDER_ALIVE" = YES ] && [ "$MODULE_HOLDER_IDENTITY" != EXACT ]; then
    ESOC_OWNER_CLASS=UNKNOWN_OWNER
  elif [ "$ESOC_OWNER_COUNT" -gt 1 ]; then
    ESOC_OWNER_CLASS=MULTIPLE_OWNERS
  elif [ "$ESOC_OWNER_COUNT" -eq 0 ]; then
    ESOC_OWNER_CLASS=NO_OWNER
  elif [ "$PER_MGR_STATE" = running ] && [ "$X55_STATE" = ONLINE ] &&
       [ -n "$PER_MGR_PID" ] && [ "$PER_MGR_EXE" = /vendor/bin/pm-service ] &&
       snapshot_owner_has_pid "$PER_MGR_PID"; then
    ESOC_OWNER_CLASS=NATIVE_PM_SERVICE
  elif [ "$MODULE_HOLDER_ALIVE" = YES ] && [ "$MODULE_HOLDER_IDENTITY" = EXACT ] && snapshot_owner_has_pid "$MODULE_HOLDER_PID"; then
    ESOC_OWNER_CLASS=MODULE_GOLDEN_HOLDER
  else
    ESOC_OWNER_CLASS=UNKNOWN_OWNER
  fi
  return 0
}

print_owner_entry_status() {
  echo "PER_MGR_STATE=${PER_MGR_STATE:-UNKNOWN}"
  echo "PER_MGR_PID=${PER_MGR_PID:-NONE}"
  echo "PER_MGR_EXE=${PER_MGR_EXE:-NONE}"
  echo "X55_STATE=${X55_STATE:-UNKNOWN}"
  echo "ESOC_OWNER_COUNT=${ESOC_OWNER_COUNT:-UNKNOWN}"
  echo "MODULE_HOLDER_PID=${MODULE_HOLDER_PID:-NONE}"
  echo "MODULE_HOLDER_ALIVE=${MODULE_HOLDER_ALIVE:-NO}"
  echo "MODULE_HOLDER_IDENTITY=${MODULE_HOLDER_IDENTITY:-NO}"
  echo "STALE_PIDFILE=${STALE_PIDFILE:-NO}"
  echo "ESOC_OWNER_CLASS=${ESOC_OWNER_CLASS:-UNKNOWN_OWNER}"
  return 0
}

wait_value() {
  COMMAND=$1 EXPECTED=$2 MAX=$3
  I=0
  while [ "$I" -lt "$MAX" ]; do
    if [ "$(eval "$COMMAND")" = "$EXPECTED" ]; then return 0; fi
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
    if [ "$ELAPSED" -ge "$MAX" ]; then return 1; fi
    LEFT=$((MAX - ELAPSED))
    if [ "$LEFT" -gt 3 ]; then SLEEP_FOR=3; else SLEEP_FOR=$LEFT; fi
    if [ "$SLEEP_FOR" -le 0 ]; then return 1; fi
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
