#!/usr/bin/env sh
# Host model only. It proves the RC4 orchestrator classifies each path and its
# counters; it does not emulate Magisk, /dev/subsys_esoc0, or the X55.
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RUNNER_LIBRARY_ONLY=YES
MODDIR="$REPO/modules/voxi_wfc_golden"
export RUNNER_LIBRARY_ONLY
# shellcheck source=/dev/null
. "$REPO/modules/voxi_wfc_golden/bin/golden-runner.sh"
set -e
set -u
trap - EXIT HUP INT TERM

reset_model() {
  STATE_WRITE_COUNT=0; MODEM_WRITE_COUNT=0; SIM_WRITE_COUNT=0; PHONE_WRITE_COUNT=0
  ENVIRONMENT_TOUCHED=0; SIM_MAY_BE_OFF=0; FREEZE_ON_HEALTHY=0; HEALTHY_CANDIDATE=0; FREEZE_COMMIT_FAILED=0; HOLDER_PID_CREATED=9001
  FINAL_RESULT=NOT_COMPLETED; RECOVERY_RESULT=NOT_COMPLETED; EXIT_REASON=NOT_SET
  CURRENT_STAGE=INIT; ATTEMPT=1; MODEL_SCENARIO=$1; MODEL_HEALTH=NO; MODEL_HOLDER=YES; MODEL_OWNER_COUNT=1; MODEL_PER_MGR=stopped; MODEL_NATIVE=YES; RESTORE_CALLED=0; CORE_CALLS=0; EMERGENCY_CALLS=0; EVENT_TRACE=
}
log_line() { printf '%s\n' "$*"; return 0; }
now_ms() { printf '1000\n'; return 0; }
require_root() { return 0; }
acquire_lock() { return 0; }
release_lock() { return 0; }
ensure_storage() { return 0; }
get_airplane() { printf '1\n'; return 0; }
set_airplane() { STATE_WRITE_COUNT=$((STATE_WRITE_COUNT + 1)); PHONE_WRITE_COUNT=$((PHONE_WRITE_COUNT + 1)); return 0; }
test_wfc_healthy() { [ "$MODEL_HEALTH" = YES ]; }
prepare_a0() { return 0; }
prepare_p() { return 0; }
holder_identity_ok() { [ "$MODEL_HOLDER" = YES ]; }
owner_count() { printf '%s\n' "$MODEL_OWNER_COUNT"; return 0; }
get_x55_state() { printf 'ONLINE\n'; return 0; }
get_per_mgr_state() { printf '%s\n' "$MODEL_PER_MGR"; return 0; }
verify_native_fingerprint() { [ "$MODEL_NATIVE" = YES ]; }
print_health() { return 0; }
print_runtime_counters() { printf 'STATE=%s MODEM=%s SIM=%s\n' "$STATE_WRITE_COUNT" "$MODEM_WRITE_COUNT" "$SIM_WRITE_COUNT"; return 0; }
core_recovery() {
  CORE_CALLS=$((CORE_CALLS + 1))
  case "$MODEL_SCENARIO" in
    success|freeze_commit_pass) ENVIRONMENT_TOUCHED=1; SIM_WRITE_COUNT=$((SIM_WRITE_COUNT + 2)); STATE_WRITE_COUNT=$((STATE_WRITE_COUNT + 2)); PHONE_WRITE_COUNT=$((PHONE_WRITE_COUNT + 2)); MODEL_HEALTH=YES; RECOVERY_RESULT=SIM_CYCLE_1_SUCCESS; HEALTHY_CANDIDATE=1; return 0 ;;
    x55_only) ENVIRONMENT_TOUCHED=1; MODEL_HEALTH=YES; RECOVERY_RESULT=X55_ONLY_SUCCESS; HEALTHY_CANDIDATE=1; return 0 ;;
    freeze_holder_dead) ENVIRONMENT_TOUCHED=1; MODEL_HEALTH=YES; RECOVERY_RESULT=SIM_CYCLE_1_SUCCESS; HEALTHY_CANDIDATE=1; MODEL_HOLDER=NO; return 0 ;;
    freeze_owner_wrong) ENVIRONMENT_TOUCHED=1; MODEL_HEALTH=YES; RECOVERY_RESULT=SIM_CYCLE_1_SUCCESS; HEALTHY_CANDIDATE=1; MODEL_OWNER_COUNT=2; return 0 ;;
    holder_fail|no_pon|pon_fail_cleanup_then_attempt2) ENVIRONMENT_TOUCHED=1; if [ "$MODEL_SCENARIO" = pon_fail_cleanup_then_attempt2 ] && [ "$1" = 2 ]; then MODEL_HEALTH=YES; HEALTHY_CANDIDATE=1; RECOVERY_RESULT=SIM_CYCLE_1_SUCCESS; return 0; fi; return 30 ;;
    prewrite_failure_not_needed) return 30 ;;
    sim_off_fail) ENVIRONMENT_TOUCHED=1; SIM_WRITE_COUNT=$((SIM_WRITE_COUNT + 1)); STATE_WRITE_COUNT=$((STATE_WRITE_COUNT + 1)); PHONE_WRITE_COUNT=$((PHONE_WRITE_COUNT + 1)); return 20 ;;
    sim_on_fail|normal_on_fail_emergency_success|normal_on_fail_emergency_fail_native_restore|emergency_on_fail_native_cleanup_fail) ENVIRONMENT_TOUCHED=1; SIM_WRITE_COUNT=$((SIM_WRITE_COUNT + 2)); STATE_WRITE_COUNT=$((STATE_WRITE_COUNT + 2)); PHONE_WRITE_COUNT=$((PHONE_WRITE_COUNT + 2)); SIM_MAY_BE_OFF=1; if [ "$MODEL_SCENARIO" = normal_on_fail_emergency_success ] && [ "$1" = 2 ]; then SIM_MAY_BE_OFF=0; MODEL_HEALTH=YES; RECOVERY_RESULT=SIM_CYCLE_1_SUCCESS; HEALTHY_CANDIDATE=1; return 0; fi; return 20 ;;
    wfc_timeout) ENVIRONMENT_TOUCHED=1; SIM_WRITE_COUNT=$((SIM_WRITE_COUNT + 2)); STATE_WRITE_COUNT=$((STATE_WRITE_COUNT + 2)); PHONE_WRITE_COUNT=$((PHONE_WRITE_COUNT + 2)); return 20 ;;
    attempt2_success) ENVIRONMENT_TOUCHED=1; if [ "$1" = 1 ]; then return 20; fi; MODEL_HEALTH=YES; RECOVERY_RESULT=SIM_CYCLE_1_SUCCESS; HEALTHY_CANDIDATE=1; return 0 ;;
    both_fail|cleanup_takeover_fail|attempt_cleanup_failure_stops_retry) ENVIRONMENT_TOUCHED=1; return 20 ;;
    *) return 40 ;;
  esac
}
print_success() { [ "$FREEZE_ON_HEALTHY" = 1 ] || return 70; printf 'FINAL_RESULT=WFC_HEALTHY_FREEZE\n'; return 0; }
stage_run() { STAGE_NAME=$1; shift; CURRENT_STAGE=$STAGE_NAME; printf 'RECOVERY_STAGE_BEGIN=%s\n' "$STAGE_NAME"; "$@"; RC=$?; printf 'RECOVERY_STAGE_END=%s RC=%s\n' "$STAGE_NAME" "$RC"; return "$RC"; }
emergency_sim_on() {
  if [ "$SIM_MAY_BE_OFF" != 1 ]; then return 0; fi
  EMERGENCY_CALLS=$((EMERGENCY_CALLS + 1)); EVENT_TRACE="${EVENT_TRACE}emergency;"; SIM_WRITE_COUNT=$((SIM_WRITE_COUNT + 1))
  case "$MODEL_SCENARIO" in normal_on_fail_emergency_fail_native_restore|emergency_on_fail_native_cleanup_fail) SIM_MAY_BE_OFF=1; EVENT_TRACE="${EVENT_TRACE}emergency-fail;"; return 60;; esac
  SIM_MAY_BE_OFF=0; EVENT_TRACE="${EVENT_TRACE}emergency-pass;"; return 0
}
restore_native() { RESTORE_CALLED=$((RESTORE_CALLED + 1)); EVENT_TRACE="${EVENT_TRACE}restore;"; case "$MODEL_SCENARIO" in cleanup_takeover_fail|attempt_cleanup_failure_stops_retry|emergency_on_fail_native_cleanup_fail) return 70;; *) MODEL_NATIVE=YES; EVENT_TRACE="${EVENT_TRACE}native-ok;"; return 0;; esac; }

run_case() {
  NAME=$1; EXPECT=$2; reset_model "$NAME"
  OUTFILE=$(mktemp)
  golden_runner_main >"$OUTFILE" 2>&1 || RC=$?
  RC=${RC:-0}
  OUTPUT=$(cat "$OUTFILE")
  rm -f "$OUTFILE"
  case "$NAME" in
    success|freeze_commit_pass) printf '%s\n' "$OUTPUT" | grep -q 'FINAL_RESULT=WFC_HEALTHY_FREEZE'; [ "$RC" -eq 0 ]; [ "$SIM_WRITE_COUNT" -eq 2 ]; [ "$FREEZE_ON_HEALTHY" -eq 1 ] ;;
    x55_only) [ "$SIM_WRITE_COUNT" -eq 0 ]; [ "$RC" -eq 0 ] ;;
    holder_fail|no_pon) [ "$SIM_WRITE_COUNT" -eq 0 ]; [ "$RC" -eq 20 ]; [ "$RESTORE_CALLED" -ge 1 ] ;;
    prewrite_failure_not_needed) [ "$RC" -eq 20 ]; [ "$RESTORE_CALLED" -eq 0 ]; printf '%s\n' "$OUTPUT" | grep -q 'CLEANUP_NATIVE=NOT_NEEDED' ;;
    sim_off_fail) [ "$RC" -eq 20 ]; [ "$SIM_WRITE_COUNT" -eq 2 ] ;;
    sim_on_fail) [ "$RC" -eq 20 ]; [ "$SIM_WRITE_COUNT" -eq 6 ]; [ "$SIM_MAY_BE_OFF" -eq 0 ]; [ "$RESTORE_CALLED" -ge 1 ] ;;
    normal_on_fail_emergency_success) [ "$RC" -eq 0 ]; [ "$CORE_CALLS" -eq 2 ]; [ "$EMERGENCY_CALLS" -eq 1 ]; [ "$SIM_MAY_BE_OFF" -eq 0 ]; [ "$RESTORE_CALLED" -eq 1 ]; printf '%s\n' "$EVENT_TRACE" | grep -q 'emergency;emergency-pass;restore;native-ok;' ;;
    normal_on_fail_emergency_fail_native_restore) [ "$RC" -eq 70 ]; [ "$CORE_CALLS" -eq 1 ]; [ "$EMERGENCY_CALLS" -eq 1 ]; [ "$SIM_MAY_BE_OFF" -eq 1 ]; [ "$RESTORE_CALLED" -eq 1 ]; printf '%s\n' "$OUTPUT" | grep -q 'CLEANUP_RESULT=SIM_EMERGENCY_ON_FAILED_NATIVE_RESTORED'; printf '%s\n' "$EVENT_TRACE" | grep -q 'emergency;emergency-fail;restore;native-ok;' ;;
    emergency_on_fail_native_cleanup_fail) [ "$RC" -eq 70 ]; [ "$CORE_CALLS" -eq 1 ]; [ "$EMERGENCY_CALLS" -eq 1 ]; [ "$SIM_MAY_BE_OFF" -eq 1 ]; [ "$RESTORE_CALLED" -eq 1 ]; printf '%s\n' "$OUTPUT" | grep -q 'CLEANUP_RESULT=SIM_EMERGENCY_ON_FAILED_NATIVE_TAKEOVER_FAILED'; printf '%s\n' "$EVENT_TRACE" | grep -q 'emergency;emergency-fail;restore;' ;;
    wfc_timeout|both_fail) [ "$RC" -eq 20 ] ;;
    cleanup_takeover_fail) [ "$RC" -eq 70 ]; [ "$CORE_CALLS" -eq 1 ] ;;
    attempt2_success|pon_fail_cleanup_then_attempt2) [ "$RC" -eq 0 ]; printf '%s\n' "$OUTPUT" | grep -q 'FINAL_RESULT=WFC_HEALTHY_FREEZE'; [ "$RESTORE_CALLED" -ge 1 ] ;;
    freeze_holder_dead|freeze_owner_wrong) [ "$RC" -eq 70 ]; [ "$FREEZE_ON_HEALTHY" -eq 0 ]; [ "$RESTORE_CALLED" -ge 1 ]; printf '%s\n' "$OUTPUT" | grep -q 'FREEZE_COMMIT=FAIL' ;;
    attempt_cleanup_failure_stops_retry) [ "$RC" -eq 70 ]; [ "$CORE_CALLS" -eq 1 ]; [ "$RESTORE_CALLED" -eq 1 ] ;;
  esac
  printf 'MOCK_%s=PASS\n' "$NAME"
  unset RC
}

export PRE_RECOVERY_GATE_PASSED=YES
run_case success 0
run_case x55_only 0
run_case holder_fail 20
run_case no_pon 20
run_case sim_off_fail 20
run_case sim_on_fail 20
run_case wfc_timeout 20
run_case cleanup_takeover_fail 20
run_case attempt2_success 0
run_case both_fail 20
run_case freeze_commit_pass 0
run_case freeze_holder_dead 20
run_case freeze_owner_wrong 20
run_case pon_fail_cleanup_then_attempt2 0
run_case attempt_cleanup_failure_stops_retry 70
run_case prewrite_failure_not_needed 20
run_case normal_on_fail_emergency_success 0
run_case normal_on_fail_emergency_fail_native_restore 70
run_case emergency_on_fail_native_cleanup_fail 70
printf 'HOST_MODEL_PASS fixtures=19\n'
printf 'HOST_DEVICE_WRITES=0\n'
