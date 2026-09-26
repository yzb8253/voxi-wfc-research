#!/usr/bin/env sh
# Host model only. It proves the RC2 orchestrator classifies each path and its
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
  ENVIRONMENT_TOUCHED=0; SIM_MAY_BE_OFF=0; FREEZE_ON_HEALTHY=0; HOLDER_PID_CREATED=9001
  FINAL_RESULT=NOT_COMPLETED; RECOVERY_RESULT=NOT_COMPLETED; EXIT_REASON=NOT_SET
  CURRENT_STAGE=INIT; ATTEMPT=1; MODEL_SCENARIO=$1; MODEL_HEALTH=NO
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
print_health() { return 0; }
print_runtime_counters() { printf 'STATE=%s MODEM=%s SIM=%s\n' "$STATE_WRITE_COUNT" "$MODEM_WRITE_COUNT" "$SIM_WRITE_COUNT"; return 0; }
core_recovery() {
  case "$MODEL_SCENARIO" in
    success) SIM_WRITE_COUNT=$((SIM_WRITE_COUNT + 2)); STATE_WRITE_COUNT=$((STATE_WRITE_COUNT + 2)); PHONE_WRITE_COUNT=$((PHONE_WRITE_COUNT + 2)); MODEL_HEALTH=YES; RECOVERY_RESULT=SIM_CYCLE_1_SUCCESS; FREEZE_ON_HEALTHY=1; FINAL_RESULT=WFC_HEALTHY_FREEZE; return 0 ;;
    x55_only) MODEL_HEALTH=YES; RECOVERY_RESULT=X55_ONLY_SUCCESS; FREEZE_ON_HEALTHY=1; FINAL_RESULT=WFC_HEALTHY_FREEZE; return 0 ;;
    holder_fail|no_pon) return 30 ;;
    sim_off_fail) SIM_WRITE_COUNT=$((SIM_WRITE_COUNT + 1)); STATE_WRITE_COUNT=$((STATE_WRITE_COUNT + 1)); PHONE_WRITE_COUNT=$((PHONE_WRITE_COUNT + 1)); return 20 ;;
    sim_on_fail) SIM_WRITE_COUNT=$((SIM_WRITE_COUNT + 2)); STATE_WRITE_COUNT=$((STATE_WRITE_COUNT + 2)); PHONE_WRITE_COUNT=$((PHONE_WRITE_COUNT + 2)); SIM_MAY_BE_OFF=1; return 20 ;;
    wfc_timeout) SIM_WRITE_COUNT=$((SIM_WRITE_COUNT + 2)); STATE_WRITE_COUNT=$((STATE_WRITE_COUNT + 2)); PHONE_WRITE_COUNT=$((PHONE_WRITE_COUNT + 2)); return 20 ;;
    attempt2_success) if [ "$1" = 1 ]; then return 20; fi; MODEL_HEALTH=YES; RECOVERY_RESULT=SIM_CYCLE_1_SUCCESS; FREEZE_ON_HEALTHY=1; FINAL_RESULT=WFC_HEALTHY_FREEZE; return 0 ;;
    both_fail|cleanup_takeover_fail) return 20 ;;
    *) return 40 ;;
  esac
}
print_success() { [ "$MODEL_HOLDER" = YES ] || return 70; printf 'FINAL_RESULT=WFC_HEALTHY_FREEZE\n'; return 0; }
stage_run() { STAGE_NAME=$1; shift; CURRENT_STAGE=$STAGE_NAME; printf 'RECOVERY_STAGE_BEGIN=%s\n' "$STAGE_NAME"; "$@"; RC=$?; printf 'RECOVERY_STAGE_END=%s RC=%s\n' "$STAGE_NAME" "$RC"; return "$RC"; }
emergency_sim_on() { if [ "$SIM_MAY_BE_OFF" = 1 ]; then SIM_MAY_BE_OFF=0; SIM_WRITE_COUNT=$((SIM_WRITE_COUNT + 1)); fi; return 0; }
restore_native() { case "$MODEL_SCENARIO" in cleanup_takeover_fail) return 70;; *) return 0;; esac; }

run_case() {
  NAME=$1; EXPECT=$2; MODEL_HOLDER=YES; reset_model "$NAME"
  OUTFILE=$(mktemp)
  golden_runner_main >"$OUTFILE" 2>&1 || RC=$?
  RC=${RC:-0}
  OUTPUT=$(cat "$OUTFILE")
  rm -f "$OUTFILE"
  case "$NAME" in
    success) printf '%s\n' "$OUTPUT" | grep -q 'FINAL_RESULT=WFC_HEALTHY_FREEZE'; [ "$RC" -eq 0 ]; [ "$SIM_WRITE_COUNT" -eq 2 ] ;;
    x55_only) [ "$SIM_WRITE_COUNT" -eq 0 ]; [ "$RC" -eq 0 ] ;;
    holder_fail|no_pon) [ "$SIM_WRITE_COUNT" -eq 0 ]; [ "$RC" -eq 20 ] ;;
    sim_off_fail) [ "$RC" -eq 20 ]; [ "$SIM_WRITE_COUNT" -eq 2 ] ;;
    sim_on_fail) [ "$RC" -eq 20 ]; [ "$SIM_WRITE_COUNT" -eq 5 ] ;;
    wfc_timeout|both_fail|cleanup_takeover_fail) [ "$RC" -eq 20 ] ;;
    attempt2_success) [ "$RC" -eq 0 ]; printf '%s\n' "$OUTPUT" | grep -q 'FINAL_RESULT=WFC_HEALTHY_FREEZE' ;;
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
printf 'HOST_MODEL_PASS fixtures=10\n'
printf 'HOST_DEVICE_WRITES=0\n'
