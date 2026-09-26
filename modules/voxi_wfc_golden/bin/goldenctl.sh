#!/system/bin/sh

CTL_SHELL_FLAGS_INITIAL=$-
set +e
set +u
set +x
CTL_SHELL_FLAGS_EFFECTIVE=$-

MODDIR=${0%/*}; MODDIR=${MODDIR%/*}
if [ ! -r "$MODDIR/bin/common.sh" ]; then exit 90; fi
. "$MODDIR/bin/common.sh"
SOURCE_RC=$?
if [ "$SOURCE_RC" -ne 0 ]; then exit 90; fi

status_command() {
  require_root
  RC=$?
  if [ "$RC" -ne 0 ]; then return 40; fi
  probe_refresh
  RC=$?
  if [ "$RC" -ne 0 ]; then
    echo 'PROBE=FAIL'
    return 40
  fi
  echo '================================='
  echo ' VOXI WFC Golden Recovery RC1'
  echo '================================='
  echo "MODULE_VERSION=$MODULE_VERSION"
  echo "DEVICE=$(getprop ro.product.device)"
  echo "BUILD=$(getprop ro.build.version.incremental)"
  echo "AIRPLANE=$(get_airplane)"
  collect_network_status
  RC=$?
  if [ "$RC" -ne 0 ]; then return 40; fi
  print_network_status
  RC=$?
  if [ "$RC" -ne 0 ]; then return 40; fi
  if is_wifi_ready_now; then echo 'NETWORK_PREFLIGHT=PASS'; else echo 'NETWORK_PREFLIGHT=FAIL'; fi
  echo "VOXI slot=$TARGET_SLOT phoneId=$TARGET_PHONE subId=$TARGET_SUB carrierId=$TARGET_CARRIER MCCMNC=${TARGET_MCC}${TARGET_MNC} active=$SUB_ACTIVE apps=$UICC_ENABLED"
  print_health
  if is_wfc_healthy; then
    echo 'RESULT=HEALTHY'
    return 0
  fi
  echo "RESULT=UNHEALTHY failureClass=${FAILURE_CLASS:-UNKNOWN}"
  return 20
}

status_json_command() {
  require_root
  RC=$?
  if [ "$RC" -ne 0 ]; then return 40; fi
  run_probe
  RC=$?
  if [ "$RC" -ne 0 ]; then return 40; fi
  printf '%s\n' "$PROBE_JSON"
  return 0
}

selftest_command() {
  if [ ! -r "$MODDIR/bin/golden-selftest.sh" ]; then
    echo 'SELFTEST_RESULT=ERROR'
    echo 'READY_FOR_RECOVERY=NO'
    echo 'EXIT_REASON=SELFTEST_RUNTIME_MISSING'
    return 90
  fi
  . "$MODDIR/bin/golden-selftest.sh"
  RC=$?
  if [ "$RC" -ne 0 ]; then return 90; fi
  pre_recovery_self_test
  RC=$?
  case "$RC" in
    0|30|40|90) return "$RC" ;;
    *)
      echo 'SELFTEST_RESULT=ERROR'
      echo 'READY_FOR_RECOVERY=NO'
      echo 'EXIT_REASON=INTERNAL_UNCLASSIFIED_RC'
      print_write_counters
      return 40
      ;;
  esac
}

logs_command() {
  echo "LOG_DIR=$LOG_DIR"
  ls -1t "$LOG_DIR"/*.log 2>/dev/null | head -n 20
  return 0
}

usage() {
  echo 'Usage: goldenctl.sh {self-test|status|status-json|logs|version}'
  return 0
}

COMMAND=${1:-}
case "$COMMAND" in
  self-test) selftest_command; PUBLIC_RC=$? ;;
  status) status_command; PUBLIC_RC=$? ;;
  status-json) status_json_command; PUBLIC_RC=$? ;;
  logs) logs_command; PUBLIC_RC=$? ;;
  version) echo "VOXI WFC Golden Recovery $MODULE_VERSION"; PUBLIC_RC=0 ;;
  recover|restore-native)
    echo 'RC1_READ_ONLY=YES'
    echo 'READY_FOR_RECOVERY=NO'
    echo 'EXIT_REASON=WRITABLE_COMMAND_DISABLED_IN_RC1'
    PUBLIC_RC=30
    ;;
  *) usage; PUBLIC_RC=40 ;;
esac

case "$PUBLIC_RC" in
  0|10|20|30|40|50|60|70|90) ;;
  *)
    echo "PUBLIC_RC_SANITIZED_FROM=$PUBLIC_RC"
    echo 'EXIT_REASON=INTERNAL_UNCLASSIFIED_RC'
    PUBLIC_RC=40
    ;;
esac
exit "$PUBLIC_RC"
