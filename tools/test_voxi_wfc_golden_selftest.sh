#!/usr/bin/env sh

# Full offline RC1 orchestration fixture. Entry flags are intentionally cleared
# exactly as the Android entry scripts do.
set +e
set +u
set +x

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MODDIR="$ROOT_DIR/modules/voxi_wfc_golden"
. "$MODDIR/bin/common.sh"
. "$MODDIR/bin/golden-selftest.sh"

get_airplane() { echo 1; return 0; }
step_root_gate() { return 0; }
step_module_runtime_gate() { return 0; }
step_probe_gate() {
  TARGET_SLOT=1; TARGET_PHONE=1; TARGET_SUB=11; TARGET_CARRIER=28
  TARGET_MCC=234; TARGET_MNC=15; TARGET_GATE=true
  SUB_ACTIVE=true; UICC_ENABLED=true
  return 0
}
step_platform_gate_readonly() {
  echo 'DEVICE=cas'
  echo 'ANDROID=13'
  echo 'BUILD=V816.0.4.0.TJJCNXM'
  return 0
}
step_target_gate_readonly() {
  echo 'VOXI_SLOT=1'
  echo 'VOXI_SUB=11'
  echo 'MCCMNC=23415'
  return 0
}
step_network_observe_readonly() {
  echo 'WIFI=READY'
  echo 'VPN=DETECTED'
  echo 'VPN_INTERFACE=tun0'
  echo 'VPN_ROUTE_HINT=POLICY_ROUTING_PRESENT'
  return 0
}
step_owner_inspection_readonly() {
  echo 'PER_MGR_STATE=running'
  echo 'PER_MGR_PID=1283'
  echo 'PER_MGR_EXE=/vendor/bin/pm-service'
  echo 'X55_STATE=ONLINE'
  echo 'ESOC_OWNER_COUNT=1'
  echo 'MODULE_HOLDER_PID=NONE'
  echo 'MODULE_HOLDER_ALIVE=NO'
  echo 'MODULE_HOLDER_IDENTITY=NO'
  echo 'STALE_PIDFILE=NO'
  echo 'ESOC_OWNER_CLASS=NATIVE_PM_SERVICE'
  echo 'OWNER_BRANCH=NATIVE_PM_SERVICE'
  echo 'OWNER_INSPECTION=PASS'
  ESOC_OWNER_CLASS=NATIVE_PM_SERVICE
  return 0
}

OUT_FILE=${TMPDIR:-/tmp}/voxi-selftest-fixture-$$.txt
pre_recovery_self_test > "$OUT_FILE" 2>&1
RC=$?
OUTPUT=$(cat "$OUT_FILE")
rm -f "$OUT_FILE"
printf '%s\n' "$OUTPUT"

[ "$RC" -eq 0 ] || exit 91
for REQUIRED in \
  'STEP_END=PROBE RC=0' \
  'STEP_END=PLATFORM_GATE RC=0' \
  'STEP_END=TARGET_GATE RC=0' \
  'STEP_END=NETWORK_OBSERVE RC=0' \
  'STEP_END=OWNER_INSPECTION RC=0' \
  'STEP_END=ENTRY_CAPABILITY RC=0' \
  'OWNER_BRANCH=NATIVE_PM_SERVICE' \
  'PRE_A0_GATE=PASS' \
  'READY_FOR_A0=YES' \
  'READY_FOR_RECOVERY=YES' \
  'SELFTEST_RESULT=PASS' \
  'STATE_WRITE_COUNT=0' \
  'MODEM_WRITE_COUNT=0' \
  'SIM_WRITE_COUNT=0' \
  'FINAL_RESULT=SELFTEST_PASS'; do
  printf '%s\n' "$OUTPUT" | grep -q "$REQUIRED" || exit 92
done
echo 'RC1_SELFTEST_FIXTURE=PASS'

# A classified safety block must retain RC=30 and a non-empty reason; RC=1 and
# NOT_SET are forbidden at the public boundary.
step_owner_inspection_readonly() {
  ESOC_OWNER_CLASS=UNKNOWN_OWNER
  echo 'ESOC_OWNER_CLASS=UNKNOWN_OWNER'
  echo 'OWNER_BRANCH=UNKNOWN_OWNER'
  echo 'OWNER_INSPECTION=BLOCK'
  return 30
}
BLOCK_FILE=${TMPDIR:-/tmp}/voxi-selftest-block-fixture-$$.txt
pre_recovery_self_test > "$BLOCK_FILE" 2>&1
BLOCK_RC=$?
BLOCK_OUTPUT=$(cat "$BLOCK_FILE")
rm -f "$BLOCK_FILE"
[ "$BLOCK_RC" -eq 30 ] || exit 93
printf '%s\n' "$BLOCK_OUTPUT" | grep -q 'EXIT_REASON=UNKNOWN_ESOC_OWNER' || exit 94
printf '%s\n' "$BLOCK_OUTPUT" | grep -q 'SELFTEST_RESULT=BLOCKED' || exit 95
if printf '%s\n' "$BLOCK_OUTPUT" | grep -q 'EXIT_REASON=NOT_SET'; then exit 96; fi
echo 'RC1_SELFTEST_BLOCK_FIXTURE=PASS'
echo 'PUBLIC_EXIT_RC_1_FORBIDDEN=PASS'
echo 'PHONE_WRITES=0'
exit 0
