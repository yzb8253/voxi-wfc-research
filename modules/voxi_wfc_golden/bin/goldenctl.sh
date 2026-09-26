#!/system/bin/sh

MODDIR=${0%/*}; MODDIR=${MODDIR%/*}
. "$MODDIR/bin/common.sh" || exit 90
. "$MODDIR/bin/golden-preflight.sh" || exit 90

status_command() {
  require_root || return 40
  if ! probe_refresh; then
    echo 'PROBE=FAIL'
    return 40
  fi
  echo '================================='
  echo ' VOXI WFC Golden Recovery'
  echo '================================='
  echo "MODULE_VERSION=$MODULE_VERSION"
  echo "DEVICE=$(getprop ro.product.device)"
  echo "BUILD=$(getprop ro.build.version.incremental)"
  echo "AIRPLANE=$(get_airplane)"
  echo "WIFI=$(settings get global wifi_on 2>/dev/null)"
  collect_network_status
  print_network_status
  if wifi_ready_now; then echo 'NETWORK_PREFLIGHT=PASS'; else echo 'NETWORK_PREFLIGHT=FAIL'; fi
  echo "VOXI slot=$TARGET_SLOT phoneId=$TARGET_PHONE subId=$TARGET_SUB carrierId=$TARGET_CARRIER MCCMNC=${TARGET_MCC}${TARGET_MNC} active=$SUB_ACTIVE apps=$UICC_ENABLED"
  print_health
  echo "PER_MGR=$(get_per_mgr_state)"
  echo "PM_SERVICE_PID=$(get_per_mgr_pid)"
  echo "PM_OWNS_ESOC=$(pm_owns_esoc && echo YES || echo NO)"
  echo "X55=$(get_x55_state)"
  echo "CRASH_COUNT=$(get_crash_count)"
  HPID=$(saved_holder_pid 2>/dev/null || true)
  echo "MODULE_HOLDER=${HPID:-NONE}"
  if test_wfc_healthy; then echo 'RESULT=HEALTHY'; return 0; fi
  echo "RESULT=UNHEALTHY failureClass=${FAILURE_CLASS:-UNKNOWN}"
  return 20
}

restore_command() {
  require_root || return 40
  acquire_lock || return 50
  trap 'release_lock' EXIT HUP INT TERM
  platform_gate || { echo 'RESTORE_NATIVE=BLOCKED_PLATFORM_OR_TARGET_GATE'; return 30; }
  PHONE_WRITE_COUNT=0
  ENVIRONMENT_TOUCHED=1
  if restore_native; then
    echo 'RESTORE_NATIVE=PASS'
    echo "PHONE_WRITE_COUNT=$PHONE_WRITE_COUNT"
    return 0
  fi
  echo 'RESTORE_NATIVE=FAIL'
  echo '模块 holder 在需要时被保留；请不要手工 kill。必要时完整 reboot。'
  echo "PHONE_WRITE_COUNT=$PHONE_WRITE_COUNT"
  return 30
}

logs_command() {
  require_root || return 40
  ensure_storage || return 40
  echo "LOG_DIR=$LOG_DIR"
  ls -1t "$LOG_DIR"/*.log 2>/dev/null | head -n 20
}

usage() {
  echo 'Usage: goldenctl.sh {status|status-json|recover|restore-native|logs|version}'
}

case "${1:-}" in
  status) status_command ;;
  status-json) require_root && run_probe && printf '%s\n' "$PROBE_JSON" ;;
  recover) exec "$MODDIR/bin/golden-runner.sh" ;;
  restore-native) restore_command ;;
  logs) logs_command ;;
  version) echo "VOXI WFC Golden Recovery $MODULE_VERSION" ;;
  *) usage; exit 2 ;;
esac
