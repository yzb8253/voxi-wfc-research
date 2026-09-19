#!/system/bin/sh

MODDIR=${0%/*}
CTL="$MODDIR/bin/wfcctl.sh"
DATA_DIR=/data/adb/voxi-wfc-recovery
LOG_DIR="$DATA_DIR/logs/boot"
STATE_DIR="$DATA_DIR/state"
CONFIG_FILE="$DATA_DIR/config.conf"
DRY_RUN=false
[ "${1:-}" = dry-run ] && DRY_RUN=true

umask 077

timestamp() {
  date -Iseconds 2>/dev/null || date
}

log_line() {
  LINE="$(timestamp) $*"
  printf '%s\n' "$LINE"
  [ "$DRY_RUN" = true ] || printf '%s\n' "$LINE" >> "$LOG_FILE"
}

log_output() {
  printf '%s\n' "$1"
  [ "$DRY_RUN" = true ] || printf '%s\n' "$1" >> "$LOG_FILE"
}

read_auto_config() {
  AUTO_RECOVER_BOOT=0
  if [ -r "$CONFIG_FILE" ]; then
    CONFIG_VALUE=$(sed -n 's/^AUTO_RECOVER_BOOT=\([01]\)$/\1/p' "$CONFIG_FILE" | tail -n 1)
    [ "$CONFIG_VALUE" = 1 ] && AUTO_RECOVER_BOOT=1
  fi
}

wifi_ready() {
  CONNECTIVITY_STATE=$(dumpsys connectivity 2>/dev/null)
  printf '%s\n' "$CONNECTIVITY_STATE" \
    | grep -F 'NetworkAgentInfo{' \
    | grep -F 'ni{WIFI CONNECTED' \
    | grep -F 'Transports: WIFI' \
    | grep -F 'INTERNET' \
    | grep -Fq 'VALIDATED'
}

strict_f1() {
  STATUS_TEXT=$1
  printf '%s\n' "$STATUS_TEXT" | grep -Fqx 'VOXI: slot=1 phoneId=1 subId=11 MCCMNC=23415 carrierId=28' || return 1
  printf '%s\n' "$STATUS_TEXT" | grep -Fqx 'Subscription: ACTIVE' || return 1
  printf '%s\n' "$STATUS_TEXT" | grep -Fqx 'UICC Apps: ENABLED' || return 1
  printf '%s\n' "$STATUS_TEXT" | grep -Fqx 'IMS: NOT_REGISTERED (raw 0)' || return 1
  printf '%s\n' "$STATUS_TEXT" | grep -Fqx 'WFC: UNAVAILABLE' || return 1
  printf '%s\n' "$STATUS_TEXT" | grep -Fqx 'Failure class: F1' || return 1
  printf '%s\n' "$STATUS_TEXT" | grep -Fqx 'Protected slot0: subId=1 slot=0 carrierId=2237 MCCMNC=46011 gate=PASS' || return 1
  return 0
}

run_status() {
  PROBE_OUTPUT=$("$CTL" status 2>&1)
  PROBE_RC=$?
}

if [ "$DRY_RUN" = true ]; then
  echo 'VOXI WFC boot service dry-run'
  read_auto_config
  if [ "$AUTO_RECOVER_BOOT" = 1 ]; then
    echo 'Boot Auto Recover: ENABLED'
  else
    echo 'Boot Auto Recover: DISABLED'
  fi
  run_status
  log_output "$PROBE_OUTPUT"
  if [ "$PROBE_RC" -eq 0 ]; then
    echo 'DRY RUN: WFC already healthy'
    echo 'ZERO WRITE'
    exit 0
  fi
  echo 'DRY RUN: no recovery operation is permitted'
  echo 'ZERO WRITE'
  exit "$PROBE_RC"
fi

BOOT_WAITED=0
while [ "$(getprop sys.boot_completed)" != 1 ] && [ "$BOOT_WAITED" -lt 600 ]; do
  sleep 5
  BOOT_WAITED=$((BOOT_WAITED + 5))
done

mkdir -p "$LOG_DIR" "$STATE_DIR" || exit 40
chmod 0700 "$DATA_DIR" "$DATA_DIR/logs" "$LOG_DIR" "$STATE_DIR" 2>/dev/null
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
[ -n "$BOOT_ID" ] || BOOT_ID=unknown
LOG_FILE="$LOG_DIR/boot-$BOOT_ID.log"

if [ "$(getprop sys.boot_completed)" != 1 ]; then
  log_line 'BOOT NOT COMPLETED; AUTO RECOVERY ABORTED; ZERO WRITE'
  exit 40
fi

BOOT_COMPLETED_TIME=$(timestamp)
log_line "boot_id=$BOOT_ID"
log_line "boot_completed_time=$BOOT_COMPLETED_TIME"
log_line 'post_boot_settle_seconds=60'
sleep 60

read_auto_config
log_line "auto_config=AUTO_RECOVER_BOOT=$AUTO_RECOVER_BOOT"
if [ "$AUTO_RECOVER_BOOT" != 1 ]; then
  log_line 'BOOT AUTO RECOVERY DISABLED'
  log_line 'ZERO WRITE'
  exit 0
fi

NETWORK_WAITED=0
while ! wifi_ready; do
  if [ "$NETWORK_WAITED" -ge 300 ]; then
    log_line 'NETWORK NOT READY'
    log_line 'AUTO RECOVERY ABORTED; ZERO WRITE'
    exit 20
  fi
  sleep 10
  NETWORK_WAITED=$((NETWORK_WAITED + 10))
done
log_line "network_ready=YES waited_seconds=$NETWORK_WAITED"

run_status
log_line "first_probe_exit=$PROBE_RC"
log_output "$PROBE_OUTPUT"
if [ "$PROBE_RC" -eq 0 ]; then
  log_line 'BOOT: WFC already healthy'
  log_line 'ZERO WRITE'
  exit 0
fi
if ! strict_f1 "$PROBE_OUTPUT"; then
  log_line 'first_probe_strict_f1=NO safety_gate=FAIL_OR_NOT_F1'
  log_line 'AUTO RECOVERY ABORTED; ZERO WRITE'
  exit 20
fi
log_line 'first_probe_strict_f1=YES safety_gate=PASS'

ATTEMPT_MARK="$STATE_DIR/boot_attempt_$BOOT_ID"
if [ -e "$ATTEMPT_MARK" ]; then
  log_line 'BOOT RECOVERY ALREADY ATTEMPTED'
  log_line 'ZERO WRITE'
  exit 20
fi

log_line 'strict_f1_confirmation_wait_seconds=30'
sleep 30
run_status
log_line "second_probe_exit=$PROBE_RC"
log_output "$PROBE_OUTPUT"
if [ "$PROBE_RC" -eq 0 ]; then
  log_line 'BOOT: WFC recovered before second confirmation'
  log_line 'ZERO WRITE'
  exit 0
fi
if ! strict_f1 "$PROBE_OUTPUT"; then
  log_line 'second_probe_strict_f1=NO safety_gate=FAIL_OR_NOT_F1'
  log_line 'AUTO RECOVERY ABORTED; ZERO WRITE'
  exit 20
fi
log_line 'second_probe_strict_f1=YES safety_gate=PASS'

if ! mkdir "$ATTEMPT_MARK" 2>/dev/null; then
  log_line 'BOOT RECOVERY ALREADY ATTEMPTED'
  log_line 'ZERO WRITE'
  exit 20
fi
printf '%s\n' "attempt_started=$(timestamp)" > "$ATTEMPT_MARK/attempt.txt"
log_line 'boot_attempt_mark=CREATED max_attempts_this_boot=1'
log_line 'final_safety_gate=ENFORCED_BY_WFCCTL_DEEP_RECOVER'
log_line 'deep_recover=STARTED'

RECOVERY_START=$(date +%s)
DEEP_OUTPUT=$("$CTL" deep-recover 2>&1)
DEEP_RC=$?
log_output "$DEEP_OUTPUT"
RECOVERY_SECONDS=$(( $(date +%s) - RECOVERY_START ))

run_status
log_line "final_probe_exit=$PROBE_RC"
log_output "$PROBE_OUTPUT"
if [ "$DEEP_RC" -eq 0 ] && [ "$PROBE_RC" -eq 0 ]; then
  log_line 'BOOT AUTO RECOVERY SUCCESS'
  log_line "Recovery time: $RECOVERY_SECONDS sec"
  exit 0
fi

log_line "BOOT AUTO RECOVERY FAILED deep_exit=$DEEP_RC elapsed_seconds=$RECOVERY_SECONDS"
DIAG_OUTPUT=$("$CTL" diagnose 2>&1)
DIAG_RC=$?
log_line "diagnostics_exit=$DIAG_RC"
log_output "$DIAG_OUTPUT"
exit 60
