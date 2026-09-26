#!/system/bin/sh

MODDIR=${0%/*}; MODDIR=${MODDIR%/*}
. "$MODDIR/bin/common.sh" || exit 90
. "$MODDIR/bin/golden-preflight.sh" || exit 90

A_SETTLE_SECONDS=20
P_SETTLE_SECONDS=20
MAX_RECOVERY_ATTEMPTS=2
POST_PON_SETTLE_SECONDS=10
SIM_OFF_HOLD_SECONDS=3

ENVIRONMENT_TOUCHED=0
SIM_MAY_BE_OFF=0
FREEZE_ON_HEALTHY=0
HOLDER_PID_CREATED=
RUNNER_EXITING=0
FINAL_RESULT=NOT_COMPLETED
RECOVERY_RESULT=NOT_COMPLETED
START_MS=$(now_ms)

emergency_sim_on() {
  [ "$SIM_MAY_BE_OFF" = 1 ] || return 0
  log_line 'SIM_EMERGENCY_GUARD=START slot1 only'
  record_write "SIM_POWER_ON_EMERGENCY transaction=$SIM_POWER_TRANSACTION slot=1"
  service call phone "$SIM_POWER_TRANSACTION" i32 1 i32 1 >/dev/null 2>&1
  RC=$?
  SIM_MAY_BE_OFF=0
  log_line "SIM_EMERGENCY_GUARD_RC=$RC"
  return "$RC"
}

runner_exit_guard() {
  RC=$?
  trap - EXIT HUP INT TERM
  [ "$RUNNER_EXITING" = 0 ] || exit "$RC"
  RUNNER_EXITING=1
  emergency_sim_on || true
  if [ "$FREEZE_ON_HEALTHY" != 1 ] && [ "$ENVIRONMENT_TOUCHED" = 1 ]; then
    log_line 'EXIT_GUARD_NATIVE_CLEANUP=START'
    restore_native || log_line 'EXIT_GUARD_NATIVE_CLEANUP=FAILED holder preserved when required'
  fi
  log_line "PHONE_WRITE_COUNT=$PHONE_WRITE_COUNT"
  release_lock
  exit "$RC"
}

runner_signal() {
  FINAL_RESULT=INTERRUPTED
  log_line 'SIGNAL=INTERRUPTED'
  exit 130
}

trap runner_exit_guard EXIT
trap runner_signal HUP INT TERM

assert_clean_core_entry() {
  [ "$(get_airplane)" = 1 ] || return 1
  verify_native_fingerprint || return 1
  [ -z "$(saved_holder_pid 2>/dev/null || true)" ] || return 1
  return 0
}

core_recovery() {
  ATTEMPT=$1
  log_line "CORE_ATTEMPT=$ATTEMPT START"
  assert_clean_core_entry || { log_line 'CORE_ENTRY_GATE=FAIL'; return 30; }
  log_line "PRE_PER_MGR=$(get_per_mgr_state) PRE_PM_PID=$(get_per_mgr_pid) PRE_X55=$(get_x55_state)"

  if test_wfc_healthy; then
    RECOVERY_RESULT=ALREADY_HEALTHY
    return 0
  fi

  PRE_PON=$(get_last_pon)
  PRE_CRASH=$(get_crash_count)
  case "$PRE_CRASH" in ''|*[!0-9]*) log_line 'PRE_SHUTDOWN_CRASH_COUNT=INVALID'; return 30;; esac
  log_line "PRE_SHUTDOWN_CRASH_COUNT=$PRE_CRASH"

  record_write 'CTL_STOP vendor.per_mgr'
  setprop ctl.stop vendor.per_mgr || return 30
  ENVIRONMENT_TOUCHED=1
  sleep 2
  [ "$(get_per_mgr_state)" = stopped ] || { log_line 'PER_MGR_STOP=FAIL'; return 30; }

  SAVED=$(saved_holder_pid 2>/dev/null || true)
  if [ -n "$SAVED" ]; then
    if holder_process_identity_ok "$SAVED"; then
      log_line "STALE_ACTIVE_HOLDER=BLOCK pid=$SAVED"
      return 30
    fi
    rm -f "$HOLDER_PIDFILE"
  fi
  [ "$(owner_count)" -eq 0 ] || { log_line 'UNKNOWN_HOLDER=BLOCK'; return 30; }

  I=0
  while [ "$I" -lt 20 ] && [ "$(get_x55_state)" != OFFLINE ]; do sleep 1; I=$((I + 1)); done
  [ "$(get_x55_state)" = OFFLINE ] || { log_line 'X55_OFFLINE=NO'; return 30; }
  OFFLINE_CRASH=$(get_crash_count)
  case "$OFFLINE_CRASH" in ''|*[!0-9]*) return 30;; esac
  [ "$OFFLINE_CRASH" -ge "$PRE_CRASH" ] || return 30
  log_line "X55_OFFLINE=YES OFFLINE_CRASH_COUNT=$OFFLINE_CRASH delta=$((OFFLINE_CRASH - PRE_CRASH))"

  start_module_holder || { log_line 'HOLDER_START=FAIL'; return 30; }
  I=0
  while [ "$I" -lt 30 ] && [ "$(get_x55_state)" != ONLINE ]; do sleep 1; I=$((I + 1)); done
  [ "$(get_x55_state)" = ONLINE ] || { log_line 'X55_ONLINE=NO'; return 30; }
  POST_CRASH=$(get_crash_count)
  [ "$POST_CRASH" = "$OFFLINE_CRASH" ] || { log_line "POST_POWERUP_CRASH_COUNT_CHANGED=$POST_CRASH"; return 30; }
  holder_identity_ok "$HOLDER_PID_CREATED" || { log_line 'HOLDER_OWNS_ESOC=NO'; return 30; }
  log_line "X55_ONLINE=YES POST_POWERUP_CRASH_COUNT=$POST_CRASH HOLDER_PID=$HOLDER_PID_CREATED"

  POST_PON=
  I=0
  while [ "$I" -lt 15 ]; do
    POST_PON=$(get_last_pon)
    [ -n "$POST_PON" ] && [ "$POST_PON" != "$PRE_PON" ] && break
    sleep 1; I=$((I + 1))
  done
  [ -n "$POST_PON" ] && [ "$POST_PON" != "$PRE_PON" ] || { log_line 'PON_SUCCESS=NO SIM_CYCLE_BLOCKED'; return 30; }
  log_line 'PON_SUCCESS=YES new event observed'

  log_line "POST_PON_SETTLE=${POST_PON_SETTLE_SECONDS}s"
  sleep "$POST_PON_SETTLE_SECONDS"
  if wait_wfc_healthy 5 after_x55_only; then
    RECOVERY_RESULT=X55_ONLY_SUCCESS
    FREEZE_ON_HEALTHY=1
    FINAL_RESULT=WFC_HEALTHY_FREEZE
    log_line 'CLEANUP_RESULT=SKIPPED_FREEZE_ON_HEALTHY'
    return 0
  fi

  probe_refresh || return 30
  CNE_BASELINE_REQUEST=${QTI_REQUEST_ID:-null}
  log_line "CNE_BASELINE request=$CNE_BASELINE_REQUEST satisfied=${QTI_SATISFIED_ID:-null}"

  # Binder transaction 182 is validated ONLY on cas / Android 13 /
  # V816.0.4.0.TJJCNXM and is fixed to slot1. Slot0 has no write path.
  OFF_START=$(now_ms)
  record_write "SIM_POWER_OFF transaction=$SIM_POWER_TRANSACTION slot=1"
  service call phone "$SIM_POWER_TRANSACTION" i32 1 i32 0 >/dev/null 2>&1 || return 30
  SIM_MAY_BE_OFF=1
  log_line 'SIM_POWER_OFF=PASS slot1'
  sleep 1
  log_line "SIM_STATE_AFTER_OFF=$(getprop gsm.sim.state | tr -d '\r')"
  sleep 2
  OFF_END=$(now_ms)
  log_line "SIM_OFF_HOLD_MS=$((OFF_END - OFF_START))"

  ON_START=$(now_ms)
  record_write "SIM_POWER_ON transaction=$SIM_POWER_TRANSACTION slot=1"
  service call phone "$SIM_POWER_TRANSACTION" i32 1 i32 1 >/dev/null 2>&1 || return 30
  SIM_MAY_BE_OFF=0
  log_line 'SIM_POWER_ON=PASS slot1 duplicate_power_on=disabled'
  log_line "SIM_POWER_ON_REQUEST_MS=$(( $(now_ms) - ON_START ))"
  sleep 2

  if wait_wfc_healthy 30 after_sim_cycle_1; then
    RECOVERY_RESULT=SIM_CYCLE_1_SUCCESS
    FREEZE_ON_HEALTHY=1
    FINAL_RESULT=WFC_HEALTHY_FREEZE
    log_line 'CLEANUP_RESULT=SKIPPED_FREEZE_ON_HEALTHY'
    return 0
  fi

  probe_refresh || true
  AFTER_REQUEST=${QTI_REQUEST_ID:-null}
  if [ "$AFTER_REQUEST" = null ]; then CNE_FRESHNESS=NO_CNE_REQUEST
  elif [ "$CNE_BASELINE_REQUEST" != null ] && [ "$AFTER_REQUEST" = "$CNE_BASELINE_REQUEST" ]; then CNE_FRESHNESS=STALE_CNE_REQUEST
  else CNE_FRESHNESS=NEW_CNE_REQUEST
  fi
  log_line "CNE_AFTER_SIM request=$AFTER_REQUEST satisfied=${QTI_SATISFIED_ID:-null} freshness=$CNE_FRESHNESS"
  RECOVERY_RESULT=AUTO_RECOVERY_FAILED

  emergency_sim_on || true
  if restore_native; then
    log_line 'CLEANUP_RESULT=CLEAN_NATIVE_BASELINE'
    return 20
  fi
  log_line 'CLEANUP_RESULT=FAILED holder preserved for safety'
  return 30
}

print_success() {
  print_health
  echo '================================='
  echo ' ✅ VOXI Wi-Fi Calling 已恢复'
  echo '================================='
  echo 'IMS          : REGISTERED'
  echo 'Transport    : WLAN'
  echo 'VOICE/IWLAN  : AVAILABLE'
  echo 'WFC          : AVAILABLE'
  echo 'Golden State : FROZEN'
  echo "RECOVERY_RESULT=$RECOVERY_RESULT"
  echo 'CLEANUP_RESULT=SKIPPED_FREEZE_ON_HEALTHY'
  echo 'POST_CLEANUP_WFC=HEALTHY'
  echo 'FINAL_RESULT=WFC_HEALTHY_FREEZE'
  echo "PHONE_WRITE_COUNT=$PHONE_WRITE_COUNT"
  echo '如需恢复原生 X55 管理状态：'
  echo 'su -c /data/adb/modules/voxi_wfc_golden/bin/goldenctl.sh restore-native'
}

golden_runner_main() {
  require_root || return 40
  acquire_lock || return 50
  ensure_storage || return 40
  LOG_FILE="$LOG_DIR/golden-$(date '+%Y%m%d-%H%M%S').log"
  touch "$LOG_FILE" && chmod 0600 "$LOG_FILE"

  echo '================================='
  echo ' VOXI WFC GOLDEN 一键恢复'
  echo '================================='
  log_line "MODULE_VERSION=$MODULE_VERSION"
  log_line 'PORT_BASE=dfd82415073470691295547d39753f6172054748'
  log_line "ENTRY_AIRPLANE=$(get_airplane)"

  echo '[1/9] 检查当前 WFC 状态'
  if test_wfc_healthy; then
    echo 'WFC_ALREADY_HEALTHY'
    echo 'FINAL_RESULT=ALREADY_HEALTHY'
    echo 'PHONE_WRITE_COUNT=0'
    return 0
  fi

  echo '[2/9] 检查设备与 VOXI mapping'
  platform_gate || { log_line 'ENTRY_GATE=FAIL platform/target'; return 30; }
  log_line "DEVICE=$(getprop ro.product.device) BUILD=$(getprop ro.build.version.incremental)"
  log_line 'ENTRY_GATE=PASS'

  echo '[3/9] 检查 Wi-Fi / VPN'
  network_gate || { log_line 'NETWORK_GATE=FAIL Wi-Fi/tun0/VPN'; return 30; }
  log_line 'NETWORK_GATE=PASS WIFI=wlan0 VPN_TUN=tun0 (country not verified)'

  HPID=$(saved_holder_pid 2>/dev/null || true)
  if [ -n "$HPID" ]; then
    if [ ! -d "/proc/$HPID" ]; then
      rm -f "$HOLDER_PIDFILE"
      log_line "STALE_PIDFILE_REMOVED=$HPID"
    elif holder_process_identity_ok "$HPID"; then
      echo '[4/9] 恢复上一次 Golden holder 的原生 ownership'
      restore_native || { log_line 'PREVIOUS_HOLDER_RESTORE=FAIL'; return 30; }
    else
      log_line "UNKNOWN_OR_MISMATCHED_HOLDER=BLOCK pid=$HPID"
      return 30
    fi
  fi
  unknown_owner_present && { log_line 'UNKNOWN_ESOC_OWNER=BLOCK'; return 30; }

  ATTEMPT=1
  while [ "$ATTEMPT" -le "$MAX_RECOVERY_ATTEMPTS" ]; do
    echo "[4/9] 准备 A0（Attempt $ATTEMPT/$MAX_RECOVERY_ATTEMPTS）"
    prepare_a0 || { log_line "ATTEMPT_$ATTEMPT A0=FAIL"; break; }
    if test_wfc_healthy; then
      RECOVERY_RESULT=HEALTHY_IN_A
      FINAL_RESULT=WFC_HEALTHY
      echo 'FINAL_RESULT=WFC_HEALTHY'
      echo "PHONE_WRITE_COUNT=$PHONE_WRITE_COUNT"
      return 0
    fi

    echo '[5/9] 进入 Airplane ON / P state'
    prepare_p
    P_RC=$?
    if [ "$P_RC" -eq 2 ]; then
      RECOVERY_RESULT=HEALTHY_BEFORE_CORE
      FINAL_RESULT=WFC_HEALTHY
      echo 'FINAL_RESULT=WFC_HEALTHY'
      echo "PHONE_WRITE_COUNT=$PHONE_WRITE_COUNT"
      return 0
    fi
    if [ "$P_RC" -ne 0 ]; then
      log_line "ATTEMPT_$ATTEMPT P_GATE=FAIL"
      set_airplane 0 || true
      ATTEMPT=$((ATTEMPT + 1))
      continue
    fi

    echo '[6/9] 受控关闭并重建 X55'
    echo '[7/9] 等待 X55 ONLINE / PON_SUCCESS'
    echo '[8/9] 必要时执行一次 SIM2 software cycle'
    echo '[9/9] 等待 CNE / IMS / IWLAN / WFC'
    core_recovery "$ATTEMPT"
    CORE_RC=$?
    if [ "$CORE_RC" -eq 0 ]; then
      print_success
      log_line "RECOVERY_TIME_MS=$(( $(now_ms) - START_MS ))"
      return 0
    fi
    log_line "ATTEMPT_$ATTEMPT=FAILED core_rc=$CORE_RC recovery=$RECOVERY_RESULT"
    ATTEMPT=$((ATTEMPT + 1))
    if [ "$ATTEMPT" -le "$MAX_RECOVERY_ATTEMPTS" ]; then
      log_line 'BOUNDED_RETRY=RETURN_TO_A0'
      set_airplane 0 || break
    fi
  done

  log_line 'FINAL_SAFE_CLEANUP=START'
  emergency_sim_on || true
  set_airplane 0 || log_line 'FINAL_AIRPLANE_OFF=FAIL'
  if prepare_a0; then log_line 'FINAL_SAFE_A0_RESTORE=PASS'; else log_line 'FINAL_SAFE_A0_RESTORE=FAIL'; fi
  FINAL_RESULT=WFC_NOT_RECOVERED
  echo 'FINAL_RESULT=WFC_NOT_RECOVERED'
  echo "PHONE_WRITE_COUNT=$PHONE_WRITE_COUNT"
  log_line "RECOVERY_TIME_MS=$(( $(now_ms) - START_MS ))"
  return 20
}

golden_runner_main "$@"
exit $?
