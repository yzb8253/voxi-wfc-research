#!/system/bin/sh

# Writable RC4 runner. It runs only after goldenctl exported the frozen
# pre_recovery_self_test result. Public returns use documented codes.
RUNNER_SHELL_FLAGS_INITIAL=$-
set +e
set +u
set +x
RUNNER_SHELL_FLAGS_EFFECTIVE=$-
if [ -z "${MODDIR:-}" ]; then MODDIR=${0%/*}; MODDIR=${MODDIR%/*}; fi
if [ ! -r "$MODDIR/bin/common.sh" ] || [ ! -r "$MODDIR/bin/golden-preflight.sh" ]; then exit 90; fi
. "$MODDIR/bin/common.sh"
SOURCE_RC=$?
if [ "$SOURCE_RC" -ne 0 ]; then exit 90; fi
. "$MODDIR/bin/golden-preflight.sh"
SOURCE_RC=$?
if [ "$SOURCE_RC" -ne 0 ]; then exit 90; fi

A_SETTLE_SECONDS=20
P_SETTLE_SECONDS=20
MAX_RECOVERY_ATTEMPTS=2
POST_PON_SETTLE_SECONDS=10
SIM_OFF_HOLD_SECONDS=3
ENVIRONMENT_TOUCHED=0
SIM_MAY_BE_OFF=0
FREEZE_ON_HEALTHY=0
HEALTHY_CANDIDATE=0
FREEZE_COMMIT_FAILED=0
HOLDER_PID_CREATED=
RUNNER_EXITING=0
FINAL_RESULT=NOT_COMPLETED
RECOVERY_RESULT=NOT_COMPLETED
CURRENT_STAGE=INIT
EXIT_REASON=NOT_SET
START_MS=$(now_ms)

print_runtime_counters() {
  echo "STATE_WRITE_COUNT=${STATE_WRITE_COUNT:-0}"
  echo "MODEM_WRITE_COUNT=${MODEM_WRITE_COUNT:-0}"
  echo "SIM_WRITE_COUNT=${SIM_WRITE_COUNT:-0}"
  echo "PHONE_WRITE_COUNT=${PHONE_WRITE_COUNT:-0}"
  return 0
}

stage_run() {
  STAGE_NAME=$1
  shift
  CURRENT_STAGE=$STAGE_NAME
  log_line "RECOVERY_STAGE_BEGIN=$STAGE_NAME"
  "$@"
  STAGE_RC=$?
  log_line "RECOVERY_STAGE_END=$STAGE_NAME RC=$STAGE_RC"
  return "$STAGE_RC"
}

emergency_sim_on() {
  if [ "$SIM_MAY_BE_OFF" != 1 ]; then return 0; fi
  log_line "SIM_EMERGENCY_GUARD=START context=${EMERGENCY_SIM_CONTEXT:-UNSPECIFIED} slot1 only"
  record_write "SIM_POWER_ON_EMERGENCY transaction=$SIM_POWER_TRANSACTION slot=1"
  service call phone "$SIM_POWER_TRANSACTION" i32 1 i32 1 >/dev/null 2>&1
  RC=$?
  if [ "$RC" -eq 0 ]; then
    SIM_MAY_BE_OFF=0
    log_line 'SIM_EMERGENCY_GUARD=PASS'
    return 0
  fi
  SIM_MAY_BE_OFF=1
  log_line "SIM_EMERGENCY_GUARD=FAIL rc=$RC"
  return 60
}

runner_exit_guard() {
  RC=$?
  trap - EXIT HUP INT TERM
  if [ "$RUNNER_EXITING" != 0 ]; then exit "$RC"; fi
  RUNNER_EXITING=1
  EMERGENCY_SIM_CONTEXT=EXIT_GUARD
  emergency_sim_on
  GUARD_SIM_RC=$?
  if [ "$GUARD_SIM_RC" -ne 0 ]; then log_line 'EXIT_GUARD_EMERGENCY_SIM_ON=FAILED'; fi
  if [ "$FREEZE_ON_HEALTHY" != 1 ] && [ "$ENVIRONMENT_TOUCHED" = 1 ]; then
    log_line 'EXIT_GUARD_NATIVE_CLEANUP=START'
    restore_native
    CLEANUP_RC=$?
    if [ "$CLEANUP_RC" -ne 0 ]; then log_line 'EXIT_GUARD_NATIVE_CLEANUP=FAILED holder preserved when required'; fi
  fi
  if [ "$RC" -ne 0 ] && { [ -z "$EXIT_REASON" ] || [ "$EXIT_REASON" = NOT_SET ]; }; then EXIT_REASON=INTERNAL_UNCLASSIFIED_RC; fi
  log_line "EXIT_RC=$RC"
  log_line "EXIT_STAGE=$CURRENT_STAGE"
  log_line "EXIT_REASON=$EXIT_REASON"
  print_runtime_counters
  release_lock
  exit "$RC"
}

runner_signal() {
  FINAL_RESULT=INTERRUPTED
  EXIT_REASON=SIGNAL_INTERRUPTED
  log_line 'SIGNAL=INTERRUPTED'
  exit 40
}

trap runner_exit_guard EXIT
trap runner_signal HUP INT TERM

point_of_use_x55_gate() {
  if [ "$(get_airplane)" != 1 ]; then return 30; fi
  if ! verify_native_fingerprint; then return 30; fi
  if [ -n "$(saved_holder_pid 2>/dev/null || true)" ]; then return 30; fi
  if [ "$(get_per_mgr_state)" != running ] || [ "$(get_per_mgr_exe)" != /vendor/bin/pm-service ]; then return 30; fi
  if [ "$(owner_count)" -ne 1 ] || [ "$(get_x55_state)" != ONLINE ]; then return 30; fi
  return 0
}

step_x55_shutdown() {
  point_of_use_x55_gate
  RC=$?
  if [ "$RC" -ne 0 ]; then log_line 'CORE_ENTRY_GATE=FAIL'; return 30; fi
  PRE_PON=$(get_last_pon)
  PRE_CRASH=$(get_crash_count)
  case "$PRE_CRASH" in ''|*[!0-9]*) log_line 'PRE_SHUTDOWN_CRASH_COUNT=INVALID'; return 30;; esac
  log_line "PRE_SHUTDOWN_CRASH_COUNT=$PRE_CRASH"
  record_write 'CTL_STOP vendor.per_mgr'
  setprop ctl.stop vendor.per_mgr
  RC=$?
  if [ "$RC" -ne 0 ]; then return 60; fi
  ENVIRONMENT_TOUCHED=1
  sleep 2
  if [ "$(get_per_mgr_state)" != stopped ]; then log_line 'PER_MGR_STOP=FAIL'; return 30; fi
  I=0
  while [ "$I" -lt 20 ] && [ "$(get_x55_state)" != OFFLINE ]; do sleep 1; I=$((I + 1)); done
  if [ "$(get_x55_state)" != OFFLINE ]; then log_line 'X55_OFFLINE=NO'; return 30; fi
  OFFLINE_CRASH=$(get_crash_count)
  case "$OFFLINE_CRASH" in ''|*[!0-9]*) return 30;; esac
  if [ "$OFFLINE_CRASH" -lt "$PRE_CRASH" ]; then return 30; fi
  log_line "X55_OFFLINE=YES OFFLINE_CRASH_COUNT=$OFFLINE_CRASH delta=$((OFFLINE_CRASH - PRE_CRASH))"
  return 0
}

step_holder_start() {
  SAVED=$(saved_holder_pid 2>/dev/null || true)
  if [ -n "$SAVED" ]; then
    if holder_process_identity_ok "$SAVED"; then log_line "STALE_ACTIVE_HOLDER=BLOCK pid=$SAVED"; return 30; fi
    rm -f "$HOLDER_PIDFILE"
  fi
  if [ "$(owner_count)" -ne 0 ]; then log_line 'UNKNOWN_HOLDER=BLOCK'; return 30; fi
  start_module_holder
  RC=$?
  if [ "$RC" -ne 0 ]; then log_line 'HOLDER_START=FAIL'; return 60; fi
  sleep 2
  if ! holder_identity_ok "$HOLDER_PID_CREATED"; then log_line 'HOLDER_OWNS_ESOC=NO'; return 30; fi
  log_line 'HOLDER_START=PASS'
  log_line "HOLDER_PID=$HOLDER_PID_CREATED"
  log_line "HOLDER_FD9=$(readlink /proc/$HOLDER_PID_CREATED/fd/9 2>/dev/null)"
  log_line 'HOLDER_OWNS_ESOC=YES'
  return 0
}

step_x55_powerup() {
  I=0
  while [ "$I" -lt 30 ] && [ "$(get_x55_state)" != ONLINE ]; do sleep 1; I=$((I + 1)); done
  if [ "$(get_x55_state)" != ONLINE ]; then log_line 'X55_ONLINE=NO'; return 30; fi
  POST_CRASH=$(get_crash_count)
  if [ "$POST_CRASH" != "$OFFLINE_CRASH" ]; then log_line "POST_POWERUP_CRASH_COUNT_CHANGED=$POST_CRASH"; return 30; fi
  if ! holder_identity_ok "$HOLDER_PID_CREATED"; then log_line 'HOLDER_OWNS_ESOC=NO'; return 30; fi
  log_line "X55_ONLINE=YES POST_POWERUP_CRASH_COUNT=$POST_CRASH HOLDER_PID=$HOLDER_PID_CREATED"
  return 0
}

step_pon_success() {
  POST_PON=
  I=0
  while [ "$I" -lt 15 ]; do
    POST_PON=$(get_last_pon)
    if [ -n "$POST_PON" ] && [ "$POST_PON" != "$PRE_PON" ]; then break; fi
    sleep 1; I=$((I + 1))
  done
  if [ -z "$POST_PON" ] || [ "$POST_PON" = "$PRE_PON" ]; then log_line 'PON_SUCCESS=NO SIM_CYCLE_BLOCKED'; return 30; fi
  log_line 'PON_SUCCESS=YES new event observed'
  log_line "POST_PON_SETTLE=${POST_PON_SETTLE_SECONDS}s"
  sleep "$POST_PON_SETTLE_SECONDS"
  return 0
}

step_sim_cycle_and_wfc() {
  if wait_wfc_healthy 5 after_x55_only; then
    RECOVERY_RESULT=X55_ONLY_SUCCESS
    HEALTHY_CANDIDATE=1
    log_line 'HEALTHY_CANDIDATE=YES source=X55_ONLY'
    return 0
  fi
  probe_refresh
  RC=$?
  if [ "$RC" -ne 0 ]; then return 40; fi
  CNE_BASELINE_REQUEST=${QTI_REQUEST_ID:-null}
  log_line "CNE_BASELINE request=$CNE_BASELINE_REQUEST satisfied=${QTI_SATISFIED_ID:-null}"
  OFF_START=$(now_ms)
  record_write "SIM_POWER_OFF transaction=$SIM_POWER_TRANSACTION slot=1"
  service call phone "$SIM_POWER_TRANSACTION" i32 1 i32 0 >/dev/null 2>&1
  RC=$?
  if [ "$RC" -ne 0 ]; then return 60; fi
  SIM_MAY_BE_OFF=1
  log_line 'SIM_POWER_OFF=PASS slot1'
  sleep 1
  log_line "SIM_STATE_AFTER_OFF=$(getprop gsm.sim.state | tr -d '\r')"
  sleep 2
  OFF_END=$(now_ms)
  log_line "SIM_OFF_HOLD_MS=$((OFF_END - OFF_START))"
  ON_START=$(now_ms)
  record_write "SIM_POWER_ON transaction=$SIM_POWER_TRANSACTION slot=1"
  service call phone "$SIM_POWER_TRANSACTION" i32 1 i32 1 >/dev/null 2>&1
  RC=$?
  if [ "$RC" -ne 0 ]; then return 60; fi
  SIM_MAY_BE_OFF=0
  log_line 'SIM_POWER_ON=PASS slot1 duplicate_power_on=disabled'
  log_line "SIM_POWER_ON_REQUEST_MS=$(( $(now_ms) - ON_START ))"
  sleep 2
  stage_run WFC_WAIT wait_wfc_healthy 30 after_sim_cycle_1
  RC=$?
  if [ "$RC" -eq 0 ]; then
    RECOVERY_RESULT=SIM_CYCLE_1_SUCCESS
    HEALTHY_CANDIDATE=1
    log_line 'HEALTHY_CANDIDATE=YES source=SIM_CYCLE_1'
    return 0
  fi
  probe_refresh
  AFTER_PROBE_RC=$?
  if [ "$AFTER_PROBE_RC" -eq 0 ]; then
    AFTER_REQUEST=${QTI_REQUEST_ID:-null}
    if [ "$AFTER_REQUEST" = null ]; then CNE_FRESHNESS=NO_CNE_REQUEST
    elif [ "$CNE_BASELINE_REQUEST" != null ] && [ "$AFTER_REQUEST" = "$CNE_BASELINE_REQUEST" ]; then CNE_FRESHNESS=STALE_CNE_REQUEST
    else CNE_FRESHNESS=NEW_CNE_REQUEST
    fi
    log_line "CNE_AFTER_SIM request=$AFTER_REQUEST satisfied=${QTI_SATISFIED_ID:-null} freshness=$CNE_FRESHNESS"
  fi
  RECOVERY_RESULT=AUTO_RECOVERY_FAILED
  return 20
}

commit_freeze_success() {
  if [ "$HEALTHY_CANDIDATE" != 1 ]; then return 70; fi
  case "$HOLDER_PID_CREATED" in ''|*[!0-9]*) log_line 'FREEZE_COMMIT=FAIL holder pid invalid'; return 70;; esac
  if ! holder_identity_ok "$HOLDER_PID_CREATED"; then log_line 'FREEZE_COMMIT=FAIL holder identity/fd9/owner'; return 70; fi
  if [ "$(owner_count)" -ne 1 ]; then log_line 'FREEZE_COMMIT=FAIL owner count'; return 70; fi
  if [ "$(get_x55_state)" != ONLINE ]; then log_line 'FREEZE_COMMIT=FAIL X55 not online'; return 70; fi
  if [ "$(get_per_mgr_state)" != stopped ]; then log_line 'FREEZE_COMMIT=FAIL per_mgr not stopped'; return 70; fi
  if ! test_wfc_healthy; then log_line 'FREEZE_COMMIT=FAIL strict health recheck'; return 70; fi
  FREEZE_ON_HEALTHY=1
  FINAL_RESULT=WFC_HEALTHY_FREEZE
  log_line 'FREEZE_COMMIT=PASS'
  log_line 'CLEANUP_RESULT=SKIPPED_FREEZE_ON_HEALTHY'
  return 0
}

attempt_failure_cleanup() {
  SIM_GUARD_FAILED=0
  if [ "$SIM_MAY_BE_OFF" = 1 ]; then
    EMERGENCY_SIM_CONTEXT=ATTEMPT_FAILURE_CLEANUP
    emergency_sim_on
    SIM_GUARD_RC=$?
    if [ "$SIM_GUARD_RC" -ne 0 ]; then SIM_GUARD_FAILED=1; fi
  fi
  if [ "$ENVIRONMENT_TOUCHED" = 1 ]; then
    restore_native
    RESTORE_RC=$?
    if [ "$RESTORE_RC" -ne 0 ]; then
      if [ "$SIM_GUARD_FAILED" = 1 ]; then log_line 'CLEANUP_RESULT=SIM_EMERGENCY_ON_FAILED_NATIVE_TAKEOVER_FAILED'; else log_line 'CLEANUP_RESULT=NATIVE_TAKEOVER_FAILED'; fi
      return 70
    fi
    if ! verify_native_fingerprint; then
      if [ "$SIM_GUARD_FAILED" = 1 ]; then log_line 'CLEANUP_RESULT=SIM_EMERGENCY_ON_FAILED_POSTCONDITION_FAILED'; else log_line 'CLEANUP_RESULT=POSTCONDITION_FAILED'; fi
      return 70
    fi
    ENVIRONMENT_TOUCHED=0
    log_line 'NATIVE_BASELINE=RESTORED'
  else
    log_line 'CLEANUP_NATIVE=NOT_NEEDED'
  fi
  if [ "$SIM_GUARD_FAILED" = 1 ]; then
    log_line 'CLEANUP_RESULT=SIM_EMERGENCY_ON_FAILED_NATIVE_RESTORED'
    return 70
  fi
  if [ "$SIM_MAY_BE_OFF" != 0 ]; then log_line 'CLEANUP_RESULT=SIM_STATE_NOT_CONFIRMED_ON'; return 70; fi
  log_line 'CLEANUP_RESULT=CLEAN_NATIVE_BASELINE'
  return 0
}

core_recovery() {
  ATTEMPT=$1
  HEALTHY_CANDIDATE=0
  log_line "CORE_ATTEMPT=$ATTEMPT START"
  if test_wfc_healthy; then RECOVERY_RESULT=ALREADY_HEALTHY; return 0; fi
  stage_run X55_SHUTDOWN step_x55_shutdown; RC=$?
  if [ "$RC" -ne 0 ]; then return "$RC"; fi
  stage_run HOLDER_START step_holder_start; RC=$?
  if [ "$RC" -ne 0 ]; then return "$RC"; fi
  stage_run X55_POWERUP step_x55_powerup; RC=$?
  if [ "$RC" -ne 0 ]; then return "$RC"; fi
  stage_run PON_SUCCESS step_pon_success; RC=$?
  if [ "$RC" -ne 0 ]; then return "$RC"; fi
  stage_run SIM_CYCLE step_sim_cycle_and_wfc
  return $?
}

print_success() {
  if [ "$FREEZE_ON_HEALTHY" != 1 ]; then return 70; fi
  log_line 'FROZEN_HOLDER_ALIVE=YES'
  log_line 'FROZEN_HOLDER_OWNS_ESOC=YES'
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
  print_runtime_counters
  return 0
}

prepare_a0_step() { prepare_a0; RC=$?; if [ "$RC" -eq 0 ]; then return 0; fi; return 30; }
prepare_p_step() { prepare_p; RC=$?; case "$RC" in 0|10) return "$RC";; *) return 30;; esac; }

golden_runner_main() {
  if [ "$PRE_RECOVERY_GATE_PASSED" != YES ]; then
    echo 'RECOVERY_GATE=BLOCKED'
    echo 'EXIT_REASON=PRE_RECOVERY_SELFTEST_REQUIRED'
    print_runtime_counters
    return 30
  fi
  require_root; RC=$?
  if [ "$RC" -ne 0 ]; then return 40; fi
  acquire_lock; RC=$?
  if [ "$RC" -ne 0 ]; then return "$RC"; fi
  ensure_storage; RC=$?
  if [ "$RC" -ne 0 ]; then return 40; fi
  LOG_FILE="$LOG_DIR/golden-$(date '+%Y%m%d-%H%M%S').log"
  touch "$LOG_FILE"
  LOG_CREATE_RC=$?
  if [ "$LOG_CREATE_RC" -eq 0 ]; then chmod 0600 "$LOG_FILE"; fi
  echo '================================='
  echo ' VOXI WFC GOLDEN 一键恢复 RC4'
  echo '================================='
  log_line "MODULE_VERSION=$MODULE_VERSION"
  log_line 'PORT_BASE=dfd82415073470691295547d39753f6172054748'
  log_line "ENTRY_AIRPLANE=$(get_airplane)"
  if test_wfc_healthy; then
    FINAL_RESULT=ALREADY_HEALTHY
    EXIT_REASON=ALREADY_HEALTHY
    echo 'FINAL_RESULT=ALREADY_HEALTHY'
    print_runtime_counters
    return 0
  fi
  ATTEMPT=1
  while [ "$ATTEMPT" -le "$MAX_RECOVERY_ATTEMPTS" ]; do
    echo "[1/5] 准备 A0 (Attempt $ATTEMPT/$MAX_RECOVERY_ATTEMPTS)"
    stage_run A0 prepare_a0_step; RC=$?
    if [ "$RC" -ne 0 ]; then EXIT_REASON=A0_PREP_FAILED; break; fi
    if test_wfc_healthy; then RECOVERY_RESULT=HEALTHY_IN_A; FINAL_RESULT=WFC_HEALTHY; EXIT_REASON=SUCCESS_HEALTHY_IN_A0; print_runtime_counters; return 0; fi
    echo '[2/5] 进入飞行模式 / P state'
    stage_run P prepare_p_step; RC=$?
    if [ "$RC" -eq 10 ]; then RECOVERY_RESULT=HEALTHY_BEFORE_CORE; FINAL_RESULT=WFC_HEALTHY; EXIT_REASON=SUCCESS_HEALTHY_BEFORE_CORE; print_runtime_counters; return 0; fi
    if [ "$RC" -ne 0 ]; then
      EXIT_REASON=P_PREP_FAILED
      set_airplane 0; AIRPLANE_RC=$?
      if [ "$AIRPLANE_RC" -ne 0 ]; then EXIT_REASON=P_PREP_FAILED_AIRPLANE_RESTORE_FAILED; fi
      ATTEMPT=$((ATTEMPT + 1))
      continue
    fi
    echo '[3/5] 重建 X55'
    core_recovery "$ATTEMPT"; RC=$?
    if [ "$RC" -eq 0 ]; then
      stage_run FREEZE_COMMIT commit_freeze_success; FREEZE_RC=$?
      if [ "$FREEZE_RC" -eq 0 ]; then
        print_success; SUCCESS_RC=$?
        if [ "$SUCCESS_RC" -eq 0 ]; then EXIT_REASON=SUCCESS_WFC_HEALTHY_FREEZE; log_line "RECOVERY_TIME_MS=$(( $(now_ms) - START_MS ))"; return 0; fi
      fi
      FINAL_RESULT=FREEZE_INTEGRITY_FAILED
      EXIT_REASON=FREEZE_INTEGRITY_FAILED
      FREEZE_COMMIT_FAILED=1
      RC=70
    fi
    log_line "ATTEMPT_$ATTEMPT=FAILED core_rc=$RC recovery=$RECOVERY_RESULT"
    stage_run ATTEMPT_FAILURE_CLEANUP attempt_failure_cleanup
    CLEANUP_RC=$?
    if [ "$CLEANUP_RC" -ne 0 ]; then
      EXIT_REASON=ATTEMPT_CLEANUP_FAILED
      return 70
    fi
    if [ "$FREEZE_COMMIT_FAILED" = 1 ]; then return 70; fi
    ATTEMPT=$((ATTEMPT + 1))
    if [ "$ATTEMPT" -le "$MAX_RECOVERY_ATTEMPTS" ]; then
      log_line 'BOUNDED_RETRY=RETURN_TO_A0'
      set_airplane 0; AIRPLANE_RC=$?
      if [ "$AIRPLANE_RC" -ne 0 ]; then EXIT_REASON=RETRY_AIRPLANE_RESTORE_FAILED; break; fi
    fi
  done
  log_line 'FINAL_SAFE_CLEANUP=START'
  emergency_sim_on
  set_airplane 0; AIRPLANE_RC=$?
  if [ "$AIRPLANE_RC" -ne 0 ]; then log_line 'FINAL_AIRPLANE_OFF=FAIL'; fi
  stage_run A0_FINAL_RESTORE prepare_a0_step; FINAL_A0_RC=$?
  if [ "$FINAL_A0_RC" -eq 0 ]; then log_line 'FINAL_SAFE_A0_RESTORE=PASS'; else log_line 'FINAL_SAFE_A0_RESTORE=FAIL'; fi
  FINAL_RESULT=WFC_NOT_RECOVERED
  if [ "$EXIT_REASON" = NOT_SET ]; then EXIT_REASON=WFC_NOT_RECOVERED; fi
  echo 'FINAL_RESULT=WFC_NOT_RECOVERED'
  print_runtime_counters
  log_line "RECOVERY_TIME_MS=$(( $(now_ms) - START_MS ))"
  return 20
}

if [ "${RUNNER_LIBRARY_ONLY:-NO}" = YES ]; then return 0 2>/dev/null || exit 0; fi
golden_runner_main "$@"
PUBLIC_RC=$?
case "$PUBLIC_RC" in 0|10|20|30|40|50|60|70|90) ;; *) EXIT_REASON=INTERNAL_UNCLASSIFIED_RC; PUBLIC_RC=40;; esac
exit "$PUBLIC_RC"
