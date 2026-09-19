#!/system/bin/sh

MODDIR=${0%/*}
MODDIR=${MODDIR%/*}
CTL="$MODDIR/bin/voxi-autoctl.sh"
DATA=/data/adb/voxi-wfc-auto-recover
CONFIG="$DATA/config.conf"
LOG="$DATA/logs/daemon.log"
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
ATTEMPT="$DATA/state/recovery-$BOOT_ID"

umask 077
mkdir -p "$DATA/logs" "$DATA/state" || exit 1

log() {
  printf '%s %s\n' "$(date -Iseconds 2>/dev/null || date)" "$*" >> "$LOG"
  tail -n 2000 "$LOG" > "$LOG.tmp" && mv -f "$LOG.tmp" "$LOG"
}

load_config() {
  ENABLED=0; POLL_SECONDS=60; FAILURE_CONFIRMATIONS=2
  RECOVERY_COOLDOWN_SECONDS=21600; MAX_RECOVERIES_PER_BOOT=1
  if [ -r "$CONFIG" ]; then
    VALUE=$(sed -n 's/^ENABLED=\([01]\)$/\1/p' "$CONFIG" | tail -n 1); [ "$VALUE" = 1 ] && ENABLED=1
    VALUE=$(sed -n 's/^POLL_SECONDS=\([0-9][0-9]*\)$/\1/p' "$CONFIG" | tail -n 1); [ -n "$VALUE" ] && POLL_SECONDS=$VALUE
    VALUE=$(sed -n 's/^FAILURE_CONFIRMATIONS=\([0-9][0-9]*\)$/\1/p' "$CONFIG" | tail -n 1); [ -n "$VALUE" ] && FAILURE_CONFIRMATIONS=$VALUE
  fi
  case "$ENABLED" in 0|1) ;; *) ENABLED=0 ;; esac
  case "$POLL_SECONDS" in ''|*[!0-9]*) POLL_SECONDS=60 ;; esac
  [ "$POLL_SECONDS" -ge 30 ] 2>/dev/null || POLL_SECONDS=30
  case "$FAILURE_CONFIRMATIONS" in ''|*[!0-9]*|0) FAILURE_CONFIRMATIONS=2 ;; esac
}

network_ready() {
  CONNECTIVITY=$(dumpsys connectivity 2>/dev/null)
  printf '%s\n' "$CONNECTIVITY" | grep -F 'NetworkAgentInfo{' | grep -F 'ni{WIFI CONNECTED' | grep -Fq 'VALIDATED' || return 1
  VPN=$(printf '%s\n' "$CONNECTIVITY" | grep -F 'NetworkAgentInfo{' | grep -F 'ni{VPN CONNECTED' | grep -F 'VALIDATED' | grep -E 'InterfaceName: tun[0-9]+' | head -n 1)
  [ -n "$VPN" ] || return 1
  IFACE=$(printf '%s\n' "$VPN" | sed -n 's/.*InterfaceName: \(tun[0-9][0-9]*\).*/\1/p')
  [ -n "$IFACE" ] && ip link show "$IFACE" 2>/dev/null | grep -q '<[^>]*UP[^>]*>'
}

while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 5; done
log "daemon_start boot_id=$BOOT_ID"
FAILS=0

while true; do
  load_config
  if [ "$ENABLED" != 1 ]; then FAILS=0; sleep "$POLL_SECONDS"; continue; fi
  if ! network_ready; then log "network_prerequisites=NOT_READY zero_write=YES"; FAILS=0; sleep "$POLL_SECONDS"; continue; fi

  "$CTL" status >/dev/null 2>&1; RC=$?
  case "$RC" in
    0) FAILS=0 ;;
    10)
      FAILS=$((FAILS + 1)); log "inactive_f8_candidate confirmation=$FAILS/$FAILURE_CONFIRMATIONS"
      if [ "$FAILS" -ge "$FAILURE_CONFIRMATIONS" ]; then
        if [ -e "$ATTEMPT" ]; then log "boot_recovery_budget_exhausted zero_write=YES"
        else
          date -Iseconds > "$ATTEMPT"
          log "validated_f8_recovery_start max_per_boot=$MAX_RECOVERIES_PER_BOOT"
          "$CTL" recover-now >> "$LOG" 2>&1
          log "validated_f8_recovery_exit=$?"
        fi
        FAILS=0
      fi
      ;;
    20) FAILS=$((FAILS + 1)); log "active_broken_detected escalation_required=YES zero_write=YES confirmation=$FAILS" ;;
    *) FAILS=0; log "unsafe_or_unknown probe_exit=$RC zero_write=YES" ;;
  esac
  sleep "$POLL_SECONDS"
done
