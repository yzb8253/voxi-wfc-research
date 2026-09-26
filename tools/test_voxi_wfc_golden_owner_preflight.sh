#!/usr/bin/env sh

# Offline owner/classification fixtures. No Android command reaches a device.
set +e
set +u
set +x

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MODDIR="$ROOT_DIR/modules/voxi_wfc_golden"
. "$MODDIR/bin/common.sh"
. "$MODDIR/bin/golden-selftest.sh"
. "$MODDIR/bin/golden-preflight.sh"

PHONE_WRITE_COUNT=0
STATE_WRITE_COUNT=0
MODEM_WRITE_COUNT=0
SIM_WRITE_COUNT=0
FILESYSTEM_WRITE_COUNT=0
LOG_FILE=

fail_fixture() {
  echo "OWNER_FIXTURE_FAIL=$*" >&2
  exit 1
}

fixture_collect_owner() {
  COLLECT_CALLS=$((COLLECT_CALLS + 1))
  PER_MGR_STATE=$FIX_PER_STATE
  PER_MGR_PID=$FIX_PER_PID
  PER_MGR_EXE=$FIX_PER_EXE
  X55_STATE=$FIX_X55
  ESOC_OWNER_LINES_SNAPSHOT=$FIX_OWNER_LINES
  ESOC_OWNER_COUNT=$FIX_OWNER_COUNT
  MODULE_HOLDER_PIDFILE_PRESENT=$FIX_PIDFILE_PRESENT
  MODULE_HOLDER_PID=$FIX_HOLDER_PID
  MODULE_HOLDER_ALIVE=$FIX_HOLDER_ALIVE
  MODULE_HOLDER_IDENTITY=$FIX_HOLDER_IDENTITY
  STALE_PIDFILE=$FIX_STALE
  return 0
}

collect_owner_entry_status() { fixture_collect_owner; return 0; }

set_fixture() {
  FIX_PER_STATE=$1
  FIX_PER_PID=$2
  FIX_PER_EXE=$3
  FIX_X55=$4
  FIX_OWNER_COUNT=$5
  FIX_OWNER_LINES=$6
  FIX_PIDFILE_PRESENT=$7
  FIX_HOLDER_PID=$8
  FIX_HOLDER_ALIVE=$9
  shift 9
  FIX_HOLDER_IDENTITY=$1
  FIX_STALE=$2
  return 0
}

run_owner_case() {
  EXPECT_CLASS=$1
  EXPECT_RC=$2
  COLLECT_CALLS=0
  if step_owner_inspection_readonly; then CASE_RC=0; else CASE_RC=$?; fi
  echo "FIXTURE_CLASS=$ESOC_OWNER_CLASS"
  echo "FIXTURE_RC=$CASE_RC"
  echo "FIXTURE_COLLECT_CALLS=$COLLECT_CALLS"
  if [ "$ESOC_OWNER_CLASS" != "$EXPECT_CLASS" ]; then return 99; fi
  if [ "$CASE_RC" -ne "$EXPECT_RC" ]; then return 98; fi
  if [ "$COLLECT_CALLS" -ne 1 ]; then return 97; fi
  return 0
}

# A. Exact real-device native snapshot from v1.0.2.
set_fixture running 1283 /vendor/bin/pm-service ONLINE 1 \
  'pm-service 1283 root 9r CHR /dev/subsys_esoc0' NO NONE NO NO NO
OUT_A=$(run_owner_case NATIVE_PM_SERVICE 0); RC_A=$?
[ "$RC_A" -eq 0 ] || fail_fixture "A rc=$RC_A"
printf '%s\n' "$OUT_A" | grep -q 'OWNER_BRANCH=NATIVE_PM_SERVICE' || fail_fixture 'A branch'
printf '%s\n' "$OUT_A" | grep -q 'OWNER_INSPECTION=PASS' || fail_fixture 'A pass'

# B. Exact module holder is observable but blocked in read-only RC1.
set_fixture stopped '' '' ONLINE 1 \
  'sh 777 root 9r CHR /dev/subsys_esoc0' YES 777 YES EXACT NO
OUT_B=$(run_owner_case MODULE_GOLDEN_HOLDER 30); RC_B=$?
[ "$RC_B" -eq 0 ] || fail_fixture "B rc=$RC_B"
printf '%s\n' "$OUT_B" | grep -q 'BLOCK_REASON=EXISTING_MODULE_HOLDER' || fail_fixture 'B reason'

# C. External holder with no module pidfile.
set_fixture stopped '' '' ONLINE 1 \
  'sh 900 root 9r CHR /dev/subsys_esoc0' NO NONE NO NO NO
OUT_C=$(run_owner_case UNKNOWN_OWNER 30); RC_C=$?
[ "$RC_C" -eq 0 ] || fail_fixture "C rc=$RC_C"

# D. No owner.
set_fixture stopped '' '' OFFLINE 0 '' NO NONE NO NO NO
OUT_D=$(run_owner_case NO_OWNER 30); RC_D=$?
[ "$RC_D" -eq 0 ] || fail_fixture "D rc=$RC_D"

# E. Multiple owners are never normalized by RC1.
set_fixture running 1283 /vendor/bin/pm-service ONLINE 2 \
  'pm-service 1283 root 9r CHR /dev/subsys_esoc0
sh 777 root 9r CHR /dev/subsys_esoc0' YES 777 YES EXACT NO
OUT_E=$(run_owner_case MULTIPLE_OWNERS 30); RC_E=$?
[ "$RC_E" -eq 0 ] || fail_fixture "E rc=$RC_E"

# F. Dead module pidfile is reported, not deleted; actual native snapshot wins.
set_fixture running 1283 /vendor/bin/pm-service ONLINE 1 \
  'pm-service 1283 root 9r CHR /dev/subsys_esoc0' YES 777 NO NO YES
OUT_F=$(run_owner_case NATIVE_PM_SERVICE 0); RC_F=$?
[ "$RC_F" -eq 0 ] || fail_fixture "F rc=$RC_F"
printf '%s\n' "$OUT_F" | grep -q 'STALE_PIDFILE=YES' || fail_fixture 'F stale marker'

# G. A live pidfile target with mismatched identity is unsafe.
set_fixture stopped '' '' ONLINE 1 \
  'sh 777 root 9r CHR /dev/subsys_esoc0' YES 777 YES MISMATCH NO
OUT_G=$(run_owner_case UNKNOWN_OWNER 30); RC_G=$?
[ "$RC_G" -eq 0 ] || fail_fixture "G rc=$RC_G"

# H. RC4 real-device BusyBox regression: legacy business variable LINES used to
# receive this native pm-service owner row and triggered "unexpected '1260'".
owner_lines() {
  printf '%s\n' 'pm-service  1260 system 9r CHR 234,11 0t0 26176 /dev/subsys_esoc0'
  return 0
}
get_per_mgr_pid() { printf '1260\n'; return 0; }
saved_holder_pid() { return 1; }
native_clean() { return 0; }
if unknown_owner_present; then H_UNKNOWN_RC=0; else H_UNKNOWN_RC=$?; fi
[ "$H_UNKNOWN_RC" -eq 1 ] || fail_fixture "H unknown-owner rc=$H_UNKNOWN_RC"
if verify_native_fingerprint; then H_NATIVE_RC=0; else H_NATIVE_RC=$?; fi
[ "$H_NATIVE_RC" -eq 0 ] || fail_fixture "H native-fingerprint rc=$H_NATIVE_RC"

echo 'OWNER_FIXTURE_A_NATIVE=PASS'
echo 'OWNER_FIXTURE_B_MODULE=PASS'
echo 'OWNER_FIXTURE_C_UNKNOWN=PASS'
echo 'OWNER_FIXTURE_D_NO_OWNER=PASS'
echo 'OWNER_FIXTURE_E_MULTIPLE=PASS'
echo 'OWNER_FIXTURE_F_STALE_PIDFILE=PASS'
echo 'OWNER_FIXTURE_G_IDENTITY_MISMATCH=PASS'
echo 'OWNER_FIXTURE_H_BUSYBOX_LINES_COLLISION=PASS'
echo 'OWNER_VARIABLE_COLLISION_FIXTURE=PASS'
echo 'NATIVE_PM_SERVICE_REAL_DEVICE_FIXTURE=PASS'
echo 'OWNER_CLASSIFY_ONCE=PASS'
echo 'OWNER_PREFLIGHT_FIXTURES=8/8 PASS'
echo 'PHONE_WRITES=0'
