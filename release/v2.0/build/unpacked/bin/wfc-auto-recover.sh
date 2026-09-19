#!/system/bin/sh

MODDIR=${0%/*}
MODDIR=${MODDIR%/*}
CTL="$MODDIR/bin/wfcctl.sh"
DATA_DIR=/data/adb/voxi-wfc-recovery
LOG_DIR="$DATA_DIR/logs/boot"
STATE_DIR="$DATA_DIR/state"
CONFIG_FILE="$DATA_DIR/config.conf"
MODE=${1:-}
DRY_RUN=false
[ "$MODE" = dry-run ] && DRY_RUN=true

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

vpn_tun_ready() {
  CONNECTIVITY_STATE=$(dumpsys connectivity 2>/dev/null)
  VPN_AGENT=$(printf '%s\n' "$CONNECTIVITY_STATE" \
    | grep -F 'NetworkAgentInfo{' \
    | grep -F 'ni{VPN CONNECTED' \
    | grep -F 'Transports: WIFI|VPN' \
    | grep -F 'INTERNET' \
    | grep -F 'VALIDATED' \
    | grep -F 'InterfaceName: tun' \
    | head -n 1)
  [ -n "$VPN_AGENT" ] || return 1

  VPN_IF=$(printf '%s\n' "$VPN_AGENT" | sed -n 's/.*InterfaceName: \(tun[0-9][0-9]*\).*/\1/p')
  [ -n "$VPN_IF" ] || return 1

  LINK_LINE=$(ip link show "$VPN_IF" 2>/dev/null | head -n 1)
  LINK_FLAGS=$(printf '%s\n' "$LINK_LINE" | sed -n 's/^[0-9][0-9]*: [^:]*: <\([^>]*\)>.*/\1/p')
  case ",$LINK_FLAGS," in *,UP,*) ;; *) return 1 ;; esac
  case ",$LINK_FLAGS," in *,LOWER_UP,*) ;; *) return 1 ;; esac

  ip route show table all 2>/dev/null | grep -Eq "^default .*dev ${VPN_IF}([[:space:]]|$)"
}

print_network_status() {
  if wifi_ready; then WIFI_STATUS=READY; else WIFI_STATUS='NOT READY'; fi
  if vpn_tun_ready; then VPN_STATUS=READY; else VPN_STATUS='NOT READY'; fi
  echo 'Current network prerequisites:'
  echo "Wi-Fi: $WIFI_STATUS"
  echo "VPN/TUN: $VPN_STATUS"
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

wait_for_wifi() {
  WIFI_WAITED=0
  while ! wifi_ready; do
    [ "$WIFI_WAITED" -ge 300 ] && return 1
    sleep 10
    WIFI_WAITED=$((WIFI_WAITED + 10))
  done
  return 0
}

wait_for_vpn() {
  VPN_WAITED=0
  while ! vpn_tun_ready; do
    [ "$VPN_WAITED" -ge 300 ] && return 1
    sleep 10
    VPN_WAITED=$((VPN_WAITED + 10))
  done
  return 0
}

case "$MODE" in
  network-status)
    print_network_status
    exit 0
    ;;
  dry-run)
    echo 'VOXI WFC auto-recovery dry-run'
    read_auto_config
    echo "AUTO_RECOVER_BOOT=$AUTO_RECOVER_BOOT"
    print_network_status
    run_status
    log_output "$PROBE_OUTPUT"
    if [ "$PROBE_RC" -eq 0 ]; then
      echo 'DRY RUN: WFC already healthy'
    elif strict_f1 "$PROBE_OUTPUT"; then
      echo 'DRY RUN: strict F1 confirmed once; recovery is suppressed'
    else
      echo 'DRY RUN: state is not eligible for automatic recovery'
    fi
    echo 'ZERO WRITE'
    exit 0
    ;;
  boot|run-now) ;;
  *) echo 'Usage: wfc-auto-recover.sh {boot|run-now|network-status|dry-run}' >&2; exit 2 ;;
esac

if [ "$MODE" = boot ]; then
  BOOT_WAITED=0
  while [ "$(getprop sys.boot_completed)" != 1 ] && [ "$BOOT_WAITED" -lt 600 ]; do
    sleep 5
    BOOT_WAITED=$((BOOT_WAITED + 5))
  done
fi

mkdir -p "$LOG_DIR" "$STATE_DIR" || exit 40
chmod 0700 "$DATA_DIR" "$DATA_DIR/logs" "$LOG_DIR" "$STATE_DIR" 2>/dev/null
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
[ -n "$BOOT_ID" ] || BOOT_ID=unknown
if [ "$MODE" = boot ]; then
  LOG_FILE="$LOG_DIR/boot-$BOOT_ID.log"
else
  LOG_FILE="$LOG_DIR/manual-auto-$(date '+%Y%m%d-%H%M%S').log"
fi
log_line "mode=$MODE boot_id=$BOOT_ID"

if [ "$MODE" = boot ]; then
  if [ "$(getprop sys.boot_completed)" != 1 ]; then
    log_line 'BOOT NOT COMPLETED; AUTO RECOVERY ABORTED; ZERO WRITE'
    exit 40
  fi
  log_line "boot_completed_time=$(timestamp)"
  read_auto_config
  log_line "auto_config=AUTO_RECOVER_BOOT=$AUTO_RECOVER_BOOT"
  if [ "$AUTO_RECOVER_BOOT" != 1 ]; then
    log_line 'BOOT AUTO RECOVERY DISABLED'
    log_line 'ZERO WRITE'
    exit 0
  fi
else
  read_auto_config
  log_line "manual_auto_run_now=YES current_auto_config=$AUTO_RECOVER_BOOT"
fi

if ! wait_for_wifi; then
  log_line 'WIFI NOT READY after 300 seconds'
  log_line 'AUTO RECOVERY ABORTED; ZERO WRITE; attempt_not_consumed=YES'
  exit 20
fi
log_line "wifi_ready=YES waited_seconds=$WIFI_WAITED"

if ! wait_for_vpn; then
  log_line 'VPN/TUN NOT READY after 300 seconds'
  log_line 'AUTO RECOVERY ABORTED; ZERO WRITE; attempt_not_consumed=YES'
  exit 20
fi
log_line "vpn_tun_ready=YES interface=$VPN_IF waited_seconds=$VPN_WAITED"
log_line 'vpn_tun_stabilization_seconds=20'
sleep 20

if ! wifi_ready || ! vpn_tun_ready; then
  log_line 'NETWORK PREREQUISITES LOST DURING STABILIZATION'
  log_line 'AUTO RECOVERY ABORTED; ZERO WRITE; attempt_not_consumed=YES'
  exit 20
fi
log_line "network_prerequisites_stable=YES vpn_interface=$VPN_IF"

run_status
log_line "first_probe_exit=$PROBE_RC"
log_output "$PROBE_OUTPUT"
if [ "$PROBE_RC" -eq 0 ]; then
  log_line 'WFC already healthy'
  log_line 'ZERO WRITE'
  exit 0
fi
if [ "$PROBE_RC" -eq 10 ]; then
  log_line 'first_probe_state=F8_OR_INACTIVE safety_gate=PASS'
  log_line 'safe_recover=STARTED max_calls=1'
  SAFE_OUTPUT=$("$CTL" safe-recover 2>&1)
  SAFE_RC=$?
  log_output "$SAFE_OUTPUT"
  if [ "$SAFE_RC" -eq 0 ]; then
    log_line 'AUTO SAFE RECOVERY SUCCESS'
    exit 0
  fi
  log_line "AUTO SAFE RECOVERY FAILED exit=$SAFE_RC"
  log_line 'HARD RECOVERY REQUIRED'
  log_line 'No automatic retry performed.'
  exit 60
fi
if ! strict_f1 "$PROBE_OUTPUT"; then
  log_line 'first_probe_strict_f1=NO safety_gate=FAIL_OR_NOT_F1'
  log_line 'AUTO RECOVERY ABORTED; ZERO WRITE'
  exit 20
fi
log_line 'first_probe_strict_f1=YES safety_gate=PASS'

ATTEMPT_MARK="$STATE_DIR/boot_attempt_$BOOT_ID"
if [ "$MODE" = boot ] && [ -e "$ATTEMPT_MARK" ]; then
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
  log_line 'WFC recovered before second confirmation'
  log_line 'ZERO WRITE'
  exit 0
fi
if ! strict_f1 "$PROBE_OUTPUT"; then
  log_line 'second_probe_strict_f1=NO safety_gate=FAIL_OR_NOT_F1'
  log_line 'AUTO RECOVERY ABORTED; ZERO WRITE'
  exit 20
fi
log_line 'second_probe_strict_f1=YES safety_gate=PASS'

if [ "$MODE" = boot ]; then
  if ! mkdir "$ATTEMPT_MARK" 2>/dev/null; then
    log_line 'BOOT RECOVERY ALREADY ATTEMPTED'
    log_line 'ZERO WRITE'
    exit 20
  fi
  printf '%s\n' "attempt_started=$(timestamp) mode=$MODE" > "$ATTEMPT_MARK/attempt.txt"
  log_line 'boot_attempt_mark=CREATED max_deep_attempts_this_boot=1'
else
  log_line 'manual_run=YES boot_attempt_marker=IGNORED_AND_NOT_CREATED'
fi
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
  log_line 'AUTO RECOVERY SUCCESS'
  log_line "Recovery time: $RECOVERY_SECONDS sec"
  exit 0
fi

log_line "AUTO RECOVERY FAILED deep_exit=$DEEP_RC elapsed_seconds=$RECOVERY_SECONDS"
if [ "$MODE" = boot ]; then
  log_line 'BOOT AUTO RECOVERY FAILED'
else
  log_line 'MANUAL AUTO RECOVERY FAILED'
fi
log_line 'HARD RECOVERY REQUIRED'
log_line 'Failure point: ACTIVE + ENABLED after insert but IMS/CNE/ePDG did not recover'
log_line 'No automatic retry performed.'
DIAG_OUTPUT=$("$CTL" diagnose 2>&1)
DIAG_RC=$?
log_line "diagnostics_exit=$DIAG_RC"
log_output "$DIAG_OUTPUT"
exit 60
