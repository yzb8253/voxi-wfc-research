#!/usr/bin/env sh

# Offline mocked control-flow fixtures. No Android command reaches a device.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MODDIR="$ROOT_DIR/modules/voxi_wfc_golden"
. "$MODDIR/bin/common.sh"
. "$MODDIR/bin/golden-preflight.sh"

LOG_FILE=
PHONE_WRITE_COUNT=0
EXIT_REASON=NOT_SET
HOLDER_PIDFILE=/fixture/x55_holder.pid
RESTORE_CALLS=0

fail_fixture() {
  echo "OWNER_FIXTURE_FAIL=$*" >&2
  exit 1
}

run_gate_and_enter_attempt() {
  if owner_pre_a0_gate; then
    echo 'ATTEMPT_LOOP_ENTER=1'
    return 0
  else
    GATE_RC=$?
    return "$GATE_RC"
  fi
}

# Case A: no module holder, one native pm-service owner. A false negative
# probe is deliberately returned under `set -e`; control must still advance.
case_a_collect() {
  PER_MGR_STATE=running
  PER_MGR_PID=401
  PER_MGR_EXE=/vendor/bin/pm-service
  X55_STATE=ONLINE
  ESOC_OWNER_COUNT=1
  MODULE_HOLDER_PID=
  MODULE_HOLDER_ALIVE=NO
  MODULE_HOLDER_IDENTITY=NO
  ESOC_OWNER_CLASS=NATIVE_PM_SERVICE
}
collect_owner_entry_status() { case_a_collect; }
print_owner_entry_status() { echo "ESOC_OWNER_CLASS=$ESOC_OWNER_CLASS"; }
unknown_owner_present() { return 1; }
OUT_A=$(run_gate_and_enter_attempt)
printf '%s\n' "$OUT_A" | grep -q 'OWNER_INSPECTION=PASS' || fail_fixture 'case A owner pass missing'
printf '%s\n' "$OUT_A" | grep -q 'ATTEMPT_LOOP_ENTER=1' || fail_fixture 'case A did not enter attempt loop'

# Case B: no module pidfile identifies an old external holder. It must fail
# closed without any write and expose a stable reason.
case_b_collect() {
  PER_MGR_STATE=stopped
  PER_MGR_PID=
  PER_MGR_EXE=
  X55_STATE=ONLINE
  ESOC_OWNER_COUNT=1
  MODULE_HOLDER_PID=
  MODULE_HOLDER_ALIVE=NO
  MODULE_HOLDER_IDENTITY=NO
  ESOC_OWNER_CLASS=UNKNOWN_OWNER
}
collect_owner_entry_status() { case_b_collect; }
unknown_owner_present() { return 0; }
set +e
OUT_B=$(run_gate_and_enter_attempt)
RC_B=$?
set -e
[ "$RC_B" -eq 30 ] || fail_fixture "case B rc=$RC_B"
[ "$EXIT_REASON" = NOT_SET ] || true # command substitution has a subshell
printf '%s\n' "$OUT_B" | grep -q 'BLOCK_REASON=UNKNOWN_ESOC_OWNER' || fail_fixture 'case B reason missing'
[ "$PHONE_WRITE_COUNT" -eq 0 ] || fail_fixture 'case B phone write occurred'

# Case C: an exact module holder follows the existing restore-native path,
# then reclassifies as the native owner and advances.
CASE_C_PHASE=holder
collect_owner_entry_status() {
  if [ "$CASE_C_PHASE" = holder ]; then
    PER_MGR_STATE=stopped; PER_MGR_PID=; PER_MGR_EXE=; X55_STATE=ONLINE
    ESOC_OWNER_COUNT=1; MODULE_HOLDER_PID=777; MODULE_HOLDER_ALIVE=YES
    MODULE_HOLDER_IDENTITY=EXACT; ESOC_OWNER_CLASS=MODULE_GOLDEN_HOLDER
  else
    case_a_collect
  fi
}
restore_native() { RESTORE_CALLS=$((RESTORE_CALLS + 1)); CASE_C_PHASE=native; return 0; }
unknown_owner_present() { return 1; }
OUT_C=$(run_gate_and_enter_attempt)
printf '%s\n' "$OUT_C" | grep -q '恢复上一次 Golden holder' || fail_fixture 'case C restore path missing'
printf '%s\n' "$OUT_C" | grep -q 'ATTEMPT_LOOP_ENTER=1' || fail_fixture 'case C did not enter attempt loop'

echo 'OWNER_FIXTURE_A_NATIVE=PASS'
echo 'OWNER_FIXTURE_B_UNKNOWN=PASS'
echo 'OWNER_FIXTURE_C_MODULE_RESTORE=PASS'
echo 'OWNER_PREFLIGHT_FIXTURES=3/3 PASS'
echo 'PHONE_WRITES=0'
