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
  echo ' VOXI WFC Golden Recovery RC4'
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

recover_command() {
  selftest_command
  SELFTEST_RC=$?
  if [ "$SELFTEST_RC" -ne 0 ] || [ "$READY_FOR_RECOVERY" != YES ]; then
    echo 'RECOVERY_GATE=BLOCKED'
    echo "STATE_WRITE_COUNT=${STATE_WRITE_COUNT:-0}"
    echo "MODEM_WRITE_COUNT=${MODEM_WRITE_COUNT:-0}"
    echo "SIM_WRITE_COUNT=${SIM_WRITE_COUNT:-0}"
    case "$SELFTEST_RC" in 30|40|90) return "$SELFTEST_RC";; *) return 40;; esac
  fi
  if [ ! -r "$MODDIR/bin/golden-runner.sh" ]; then
    echo 'RECOVERY_GATE=BLOCKED'
    echo 'EXIT_REASON=RUNNER_RUNTIME_MISSING'
    return 90
  fi
  export PRE_RECOVERY_GATE_PASSED=YES
  exec "$MODDIR/bin/golden-runner.sh"
}

restore_native_command() {
  if [ ! -r "$MODDIR/bin/golden-preflight.sh" ]; then echo 'EXIT_REASON=PREFLIGHT_RUNTIME_MISSING'; return 90; fi
  . "$MODDIR/bin/golden-selftest.sh"
  SOURCE_RC=$?
  if [ "$SOURCE_RC" -ne 0 ]; then return 90; fi
  step_root_gate; RC=$?; if [ "$RC" -ne 0 ]; then return 40; fi
  step_module_runtime_gate; RC=$?; if [ "$RC" -ne 0 ]; then return "$RC"; fi
  step_platform_gate_readonly; RC=$?; if [ "$RC" -ne 0 ]; then return 30; fi
  # Native ownership cleanup must remain usable when Wi-Fi/VPN or the target
  # subscription is temporarily unavailable. It therefore does not invoke
  # target/network/probe gates; it still requires exact supported platform and
  # an exact module holder, never an unknown owner.
  . "$MODDIR/bin/golden-preflight.sh"
  SOURCE_RC=$?
  if [ "$SOURCE_RC" -ne 0 ]; then return 90; fi
  collect_owner_entry_status; RC=$?; if [ "$RC" -ne 0 ]; then return 40; fi
  classify_owner_entry_status; RC=$?; if [ "$RC" -ne 0 ]; then return 40; fi
  print_owner_entry_status
  case "$ESOC_OWNER_CLASS" in
    NATIVE_PM_SERVICE) echo 'RESTORE_NATIVE=ALREADY_NATIVE'; return 0 ;;
    MODULE_GOLDEN_HOLDER) restore_native; RC=$?; case "$RC" in 0|30|40|60|70) return "$RC";; *) return 40;; esac ;;
    *) echo "RESTORE_NATIVE=BLOCK owner=$ESOC_OWNER_CLASS"; return 30 ;;
  esac
}

logs_command() {
  echo "LOG_DIR=$LOG_DIR"
  ls -1t "$LOG_DIR"/*.log 2>/dev/null | head -n 20
  return 0
}

usage() {
  echo 'Usage: goldenctl.sh {self-test|recover|restore-native|status|status-json|logs|version}'
  return 0
}

COMMAND=${1:-}
case "$COMMAND" in
  self-test) selftest_command; PUBLIC_RC=$? ;;
  status) status_command; PUBLIC_RC=$? ;;
  status-json) status_json_command; PUBLIC_RC=$? ;;
  logs) logs_command; PUBLIC_RC=$? ;;
  version) echo "VOXI WFC Golden Recovery $MODULE_VERSION"; PUBLIC_RC=0 ;;
  recover) recover_command; PUBLIC_RC=$? ;;
  restore-native) restore_native_command; PUBLIC_RC=$? ;;
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
