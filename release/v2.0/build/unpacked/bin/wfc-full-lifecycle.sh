#!/system/bin/sh

MODDIR=${0%/*}
MODDIR=${MODDIR%/*}
PROBE_JAR="$MODDIR/lib/wfc-probe.jar"
RECOVERY_JAR="$MODDIR/lib/wfc-recovery-helper.jar"
REMOVE_JAR="$MODDIR/lib/wfc-deep-remove-helper.jar"
DATA_DIR=/data/adb/voxi-wfc-recovery
LOG_DIR="$DATA_DIR/logs"
STATE_DIR="$DATA_DIR/state"
LOCK_DIR="$STATE_DIR/recovery.lock.d"
PENDING="$STATE_DIR/full_recover_pending"
LAST_STATE="$STATE_DIR/full_recover_last"
LOCK_OWNED=false
VERSION=v2.0

umask 077

now() { date -Iseconds 2>/dev/null || date; }
boot_id() { cat /proc/sys/kernel/random/boot_id 2>/dev/null; }

require_root() {
  [ "$(id -u)" = 0 ] || { echo "ERROR: root is required." >&2; exit 40; }
}

ensure_storage() {
  mkdir -p "$LOG_DIR" "$STATE_DIR" || return 1
  chmod 0700 "$DATA_DIR" "$LOG_DIR" "$STATE_DIR" 2>/dev/null
}

sync_path() {
  sync -f "$1" 2>/dev/null || sync
}

sanitize_stream() {
  sed -E \
    -e 's/(iccId=)[^ ,}]*/\1[REDACTED]/gI' \
    -e 's/(cardString=)[^ ,}]*/\1[REDACTED]/gI' \
    -e 's/(mNumber=)[^ ,}]*/\1[REDACTED]/gI' \
    -e 's/(imsi=)[^ ,}]*/\1[REDACTED]/gI' \
    -e 's/(subscriberId=)[^ ,}]*/\1[REDACTED]/gI' \
    -e 's/[0-9]{12,}/[REDACTED]/g'
}

log_line() {
  [ -n "$OP_LOG" ] && printf '%s %s\n' "$(now)" "$*" | sanitize_stream >> "$OP_LOG"
}

release_lock() {
  if [ "$LOCK_OWNED" = true ]; then
    rm -rf "$LOCK_DIR"
    LOCK_OWNED=false
  fi
}

create_lock() {
  mkdir "$LOCK_DIR" 2>/dev/null || return 1
  LOCK_OWNED=true
  printf '%s\n' "$$" > "$LOCK_DIR/pid"
  boot_id > "$LOCK_DIR/boot_id"
  trap 'release_lock' EXIT HUP INT TERM
}

acquire_lock() {
  ensure_storage || return 1
  if ! create_lock; then
    echo "Recovery already running or a lock directory is present."
    return 1
  fi
}

marker_value() {
  sed -n "s/^$1=//p" "$PENDING" 2>/dev/null | tail -n 1
}

read_marker() {
  [ -r "$PENDING" ] || return 1
  MARK_TIMESTAMP=$(marker_value timestamp)
  MARK_BOOT_BEFORE=$(marker_value boot_id_before)
  MARK_BOOT_AFTER=$(marker_value boot_id_after)
  MARK_TARGET_SUB=$(marker_value target_subId)
  MARK_TARGET_SLOT=$(marker_value target_slot)
  MARK_EXPECTED=$(marker_value expected_state)
  MARK_STAGE=$(marker_value stage)
  MARK_REBOOT=$(marker_value reboot_attempted)
  MARK_FALSE=$(marker_value false_executed)
  MARK_TRUE=$(marker_value true_executed)
  MARK_FAILURE=$(marker_value failure_reason)
  MARK_LOG=$(marker_value log_name)
}

write_marker() {
  STAGE_VALUE="$1"
  FAILURE_VALUE="$2"
  TMP="$PENDING.tmp.$$"
  {
    printf 'timestamp=%s\n' "$MARK_TIMESTAMP"
    printf 'updated_timestamp=%s\n' "$(now)"
    printf 'boot_id_before=%s\n' "$MARK_BOOT_BEFORE"
    printf 'boot_id_after=%s\n' "$MARK_BOOT_AFTER"
    printf 'target_subId=11\n'
    printf 'target_slot=1\n'
    printf 'expected_state=F8\n'
    printf 'stage=%s\n' "$STAGE_VALUE"
    printf 'reboot_attempted=%s\n' "$MARK_REBOOT"
    printf 'false_executed=%s\n' "$MARK_FALSE"
    printf 'true_executed=%s\n' "$MARK_TRUE"
    printf 'failure_reason=%s\n' "$FAILURE_VALUE"
    printf 'log_name=%s\n' "$MARK_LOG"
  } > "$TMP" || { rm -f "$TMP"; return 1; }
  chmod 0600 "$TMP" 2>/dev/null
  sync_path "$TMP"
  mv -f "$TMP" "$PENDING" || { rm -f "$TMP"; return 1; }
  sync_path "$PENDING"
  sync_path "$STATE_DIR"
  MARK_STAGE="$STAGE_VALUE"
  MARK_FAILURE="$FAILURE_VALUE"
}

mark_failed() {
  REASON="$1"
  write_marker FAILED "$REASON" || true
  log_line "result=FULL_LIFECYCLE_RECOVERY_FAIL failure_reason=$REASON"
  echo "FULL_LIFECYCLE_RECOVERY = FAIL"
  echo "Failure: $REASON"
  echo "No automatic retry will be attempted."
}

mark_complete() {
  ELAPSED="$1"
  write_marker COMPLETE '' || return 1
  cp -f "$PENDING" "$LAST_STATE" || return 1
  sync_path "$LAST_STATE"
  rm -f "$PENDING" || return 1
  sync_path "$STATE_DIR"
  log_line "result=FULL_LIFECYCLE_RECOVERY_PASS recovery_time_seconds=$ELAPSED"
}

acquire_resume_lock() {
  ensure_storage || return 1
  if [ -d "$LOCK_DIR" ]; then
    LOCK_BOOT=$(cat "$LOCK_DIR/boot_id" 2>/dev/null)
    CURRENT_BOOT=$(boot_id)
    if [ -n "$MARK_BOOT_BEFORE" ] && [ "$CURRENT_BOOT" != "$MARK_BOOT_BEFORE" ] \
        && [ "$LOCK_BOOT" = "$MARK_BOOT_BEFORE" ] && [ "$MARK_REBOOT" = 1 ] \
        && [ "$MARK_FALSE" = 1 ] && [ "$MARK_TRUE" = 0 ]; then
      rm -rf "$LOCK_DIR" || return 1
    fi
  fi
  create_lock
}

run_probe() {
  PROBE_RAW=$(CLASSPATH="$PROBE_JAR" app_process /system/bin WfcStateProbe read-only-json 2>&1)
  PROBE_RC=$?
  PROBE_JSON=$(printf '%s\n' "$PROBE_RAW" | sed -n '/^{/p' | tail -n 1)
  [ "$PROBE_RC" -eq 0 ] && [ -n "$PROBE_JSON" ]
}

json_object() { printf '%s\n' "$PROBE_JSON" | sed -n "s/.*\"$1\":{\([^}]*\)}.*/\1/p"; }
json_field() { printf '%s\n' "$1" | sed -n "s/.*\"$2\":\([^,}]*\).*/\1/p" | sed 's/^"//;s/"$//'; }
json_root_field() { printf '%s\n' "$PROBE_JSON" | sed -n "s/.*\"$1\":\([^,}]*\).*/\1/p" | sed 's/^"//;s/"$//'; }

load_fields() {
  TARGET_OBJ=$(json_object target)
  SLOT0_OBJ=$(json_object protectedSlot0)
  SUB_OBJ=$(json_object subscription)
  IMS_OBJ=$(json_object ims)
  MMTEL_OBJ=$(json_object mmtel)
  WFC_OBJ=$(json_object wfc)
  TARGET_SUB=$(json_field "$TARGET_OBJ" subId)
  TARGET_SLOT=$(json_field "$TARGET_OBJ" slotId)
  TARGET_PHONE=$(json_field "$TARGET_OBJ" phoneId)
  TARGET_CARRIER=$(json_field "$TARGET_OBJ" carrierId)
  TARGET_MCC=$(json_field "$TARGET_OBJ" mcc)
  TARGET_MNC=$(json_field "$TARGET_OBJ" mnc)
  TARGET_GATE=$(json_field "$TARGET_OBJ" mappingGate)
  SLOT0_GATE=$(json_field "$SLOT0_OBJ" mappingGate)
  SLOT0_SUB=$(json_field "$SLOT0_OBJ" subId)
  SLOT0_SLOT=$(json_field "$SLOT0_OBJ" slotId)
  SLOT0_CARRIER=$(json_field "$SLOT0_OBJ" carrierId)
  SLOT0_MCC=$(json_field "$SLOT0_OBJ" mcc)
  SLOT0_MNC=$(json_field "$SLOT0_OBJ" mnc)
  SUB_ACTIVE=$(json_field "$SUB_OBJ" active)
  UICC_ENABLED=$(json_field "$SUB_OBJ" areUiccApplicationsEnabled)
  IMS_STATE_RAW=$(json_field "$IMS_OBJ" registrationStateRaw)
  IMS_TRANSPORT_RAW=$(json_field "$IMS_OBJ" registrationTransportRaw)
  VOICE_IWLAN=$(json_field "$MMTEL_OBJ" voiceIwlanAvailable)
  WFC_AVAILABLE=$(json_field "$WFC_OBJ" wifiCallingAvailable)
  SAFETY_GATE=$(json_root_field safetyGate)
  DIRECT_HEALTH=$(json_root_field directWfcHealthy)
  FAILURE_CLASS=$(json_root_field failureClass)
}

slot0_gate_passes() {
  [ "$SLOT0_GATE" = true ] && [ "$SLOT0_SUB" = 1 ] && [ "$SLOT0_SLOT" = 0 ] \
    && [ "$SLOT0_CARRIER" = 2237 ] && [ "$SLOT0_MCC" = 460 ] && [ "$SLOT0_MNC" = 11 ]
}

strict_f1_passes() {
  [ "$SAFETY_GATE" = true ] && [ "$TARGET_GATE" = true ] \
    && [ "$TARGET_SUB" = 11 ] && [ "$TARGET_SLOT" = 1 ] && [ "$TARGET_PHONE" = 1 ] \
    && [ "$TARGET_CARRIER" = 28 ] && [ "$TARGET_MCC" = 234 ] && [ "$TARGET_MNC" = 15 ] \
    && [ "$SUB_ACTIVE" = true ] && [ "$UICC_ENABLED" = true ] \
    && [ "$FAILURE_CLASS" = F1 ] && [ "$IMS_STATE_RAW" = 0 ] && [ "$WFC_AVAILABLE" = false ] \
    && slot0_gate_passes
}

inactive_helper_passes() {
  INACTIVE_GATE=$(CLASSPATH="$RECOVERY_JAR" app_process /system/bin Slot1UiccRecoverHelper dry-run 2>&1)
  INACTIVE_RC=$?
  log_line "inactive_gate_rc=$INACTIVE_RC $(printf '%s' "$INACTIVE_GATE")"
  [ "$INACTIVE_RC" -eq 0 ] && printf '%s\n' "$INACTIVE_GATE" | grep -q '^inactiveRecoveryGate=PASS$'
}

f8_sample_passes() {
  run_probe || return 1
  load_fields
  log_line "f8_probe=$PROBE_JSON"
  [ "$FAILURE_CLASS" = F8 ] && [ "$TARGET_SUB" = 11 ] && [ "$TARGET_SLOT" = -1 ] \
    && [ "$SUB_ACTIVE" = false ] && slot0_gate_passes && inactive_helper_passes
}

confirm_persistent_f8() {
  LIMIT="$1"
  START=$(date +%s)
  COUNT=0
  while [ $(( $(date +%s) - START )) -lt "$LIMIT" ]; do
    if f8_sample_passes; then
      COUNT=$((COUNT + 1))
      log_line "f8_confirmation_sample=$COUNT"
      [ "$COUNT" -ge 2 ] && return 0
    else
      COUNT=0
    fi
    sleep 2
  done
  return 1
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

wait_for_network() {
  START=$(date +%s)
  while [ $(( $(date +%s) - START )) -lt 300 ]; do
    if wifi_ready && vpn_tun_ready; then
      log_line "network_gate=PASS elapsed_seconds=$(( $(date +%s) - START ))"
      return 0
    fi
    sleep 5
  done
  return 1
}

start_full_recovery() {
  require_root
  [ ! -e "$PENDING" ] || { echo "A full lifecycle marker already exists. Use full-status or full-cancel."; return 50; }
  acquire_lock || return 50
  STAMP=$(date '+%Y%m%d-%H%M%S')
  OP_LOG="$LOG_DIR/full-lifecycle-$STAMP.log"
  : > "$OP_LOG" || return 40
  chmod 0600 "$OP_LOG" 2>/dev/null
  log_line "mode=full-recover version=$VERSION"

  if ! run_probe; then echo "Initial probe failed. ZERO WRITE."; return 40; fi
  load_fields
  log_line "initial_probe=$PROBE_JSON"
  if ! strict_f1_passes; then
    echo "Full Recover requires strict F1 and the complete dual-SIM safety gate."
    echo "ZERO WRITE."
    return 30
  fi

  REMOVE_GATE=$(CLASSPATH="$REMOVE_JAR" app_process /system/bin Slot1UiccDisableHelper dry-run 2>&1)
  REMOVE_GATE_RC=$?
  printf '%s\n' "$REMOVE_GATE" | sanitize_stream | tee -a "$OP_LOG"
  if [ "$REMOVE_GATE_RC" -ne 0 ] || ! printf '%s\n' "$REMOVE_GATE" | grep -q '^deepRemoveGate=PASS$'; then
    echo "Software-remove safety gate failed. ZERO WRITE."
    return 30
  fi

  echo "Executing one fixed VOXI software-remove write."
  FALSE_OUTPUT=$(CLASSPATH="$REMOVE_JAR" app_process /system/bin Slot1UiccDisableHelper disable 2>&1)
  FALSE_RC=$?
  log_line "false_executed=1 false_exit=$FALSE_RC"
  printf '%s\n' "$FALSE_OUTPUT" | sanitize_stream | tee -a "$OP_LOG"
  if [ "$FALSE_RC" -ne 0 ]; then
    echo "Software remove failed. No reboot and no true call."
    return 61
  fi

  if ! confirm_persistent_f8 30; then
    echo "Persistent F8 was not confirmed twice. No reboot and no true call."
    log_line "result=F8_NOT_CONFIRMED"
    return 62
  fi

  MARK_TIMESTAMP=$(now)
  MARK_BOOT_BEFORE=$(boot_id)
  MARK_BOOT_AFTER=''
  MARK_REBOOT=1
  MARK_FALSE=1
  MARK_TRUE=0
  MARK_LOG=$(basename "$OP_LOG")
  if [ -z "$MARK_BOOT_BEFORE" ] || ! write_marker WAITING_FOR_REBOOT ''; then
    echo "Unable to persist the pending marker. Reboot is blocked."
    log_line "result=PENDING_MARKER_WRITE_FAILED"
    return 63
  fi
  log_line "pending_marker_fsynced=YES boot_id_before=$MARK_BOOT_BEFORE reboot_attempted=1"
  echo "Persistent F8 confirmed. Pending marker persisted. Rebooting once."
  reboot
  REBOOT_RC=$?
  mark_failed "REBOOT_COMMAND_RETURNED_$REBOOT_RC"
  return 64
}

resume_full_recovery() {
  require_root
  ensure_storage || return 40
  read_marker || return 0
  OP_LOG="$LOG_DIR/$MARK_LOG"
  [ -n "$MARK_LOG" ] || OP_LOG="$LOG_DIR/full-lifecycle-resume-$(date '+%Y%m%d-%H%M%S').log"

  if [ "$MARK_TARGET_SUB" != 11 ] || [ "$MARK_TARGET_SLOT" != 1 ] || [ "$MARK_EXPECTED" != F8 ] \
      || [ "$MARK_REBOOT" != 1 ] || [ "$MARK_FALSE" != 1 ] || [ "$MARK_TRUE" != 0 ] \
      || [ "$MARK_STAGE" != WAITING_FOR_REBOOT ]; then
    mark_failed INVALID_OR_ALREADY_CONSUMED_MARKER
    return 70
  fi

  CURRENT_BOOT=$(boot_id)
  if [ -z "$CURRENT_BOOT" ] || [ "$CURRENT_BOOT" = "$MARK_BOOT_BEFORE" ]; then
    mark_failed NEW_BOOT_ID_NOT_CONFIRMED
    return 71
  fi
  MARK_BOOT_AFTER="$CURRENT_BOOT"
  acquire_resume_lock || { mark_failed RECOVERY_LOCK_UNAVAILABLE; return 72; }
  log_line "resume_boot_id=$CURRENT_BOOT"

  BOOT_WAIT=$(date +%s)
  while [ "$(getprop sys.boot_completed 2>/dev/null)" != 1 ]; do
    if [ $(( $(date +%s) - BOOT_WAIT )) -ge 300 ]; then
      mark_failed BOOT_COMPLETION_TIMEOUT
      return 73
    fi
    sleep 5
  done

  if ! confirm_persistent_f8 120; then
    mark_failed POST_BOOT_F8_NOT_CONFIRMED
    return 74
  fi
  write_marker WAITING_FOR_NETWORK '' || { mark_failed MARKER_UPDATE_FAILED; return 75; }
  if ! wait_for_network; then
    mark_failed NETWORK_TIMEOUT
    return 76
  fi

  log_line "network_stability_delay_seconds=30"
  sleep 30
  if ! wifi_ready || ! vpn_tun_ready; then
    mark_failed NETWORK_NOT_STABLE
    return 77
  fi
  if ! confirm_persistent_f8 30; then
    mark_failed PRE_INSERT_F8_NOT_CONFIRMED
    return 78
  fi

  write_marker WAITING_TO_INSERT '' || { mark_failed MARKER_UPDATE_FAILED; return 79; }
  RECOVERY_GATE=$(CLASSPATH="$RECOVERY_JAR" app_process /system/bin Slot1UiccRecoverHelper dry-run 2>&1)
  RECOVERY_GATE_RC=$?
  printf '%s\n' "$RECOVERY_GATE" | sanitize_stream | tee -a "$OP_LOG"
  if [ "$RECOVERY_GATE_RC" -ne 0 ] || ! printf '%s\n' "$RECOVERY_GATE" | grep -q '^inactiveRecoveryGate=PASS$'; then
    mark_failed PRE_INSERT_RECOVERY_GATE_FAILED
    return 80
  fi

  MARK_TRUE=1
  write_marker WAITING_FOR_WFC '' || { mark_failed TRUE_ATTEMPT_MARKER_WRITE_FAILED; return 81; }
  log_line "true_attempt_persisted=YES"
  TRUE_START=$(date +%s)
  TRUE_OUTPUT=$(CLASSPATH="$RECOVERY_JAR" app_process /system/bin Slot1UiccRecoverHelper recover 2>&1)
  TRUE_RC=$?
  log_line "true_executed=1 true_exit=$TRUE_RC"
  printf '%s\n' "$TRUE_OUTPUT" | sanitize_stream | tee -a "$OP_LOG"
  if [ "$TRUE_RC" -ne 0 ]; then
    mark_failed SOFTWARE_INSERT_FAILED
    return 82
  fi

  for PROBE_AT in 5 10 15 20 30 45 60 90 120; do
    NOW_ELAPSED=$(( $(date +%s) - TRUE_START ))
    WAIT_SECONDS=$((PROBE_AT - NOW_ELAPSED))
    [ "$WAIT_SECONDS" -gt 0 ] && sleep "$WAIT_SECONDS"
    if run_probe; then
      load_fields
      ELAPSED=$(( $(date +%s) - TRUE_START ))
      log_line "probe_target=${PROBE_AT}s recover_elapsed=${ELAPSED}s probe=$PROBE_JSON"
      if [ "$DIRECT_HEALTH" = true ] && [ "$SAFETY_GATE" = true ] && slot0_gate_passes \
          && [ "$IMS_STATE_RAW" = 2 ] && [ "$IMS_TRANSPORT_RAW" = 2 ] \
          && [ "$VOICE_IWLAN" = true ] && [ "$WFC_AVAILABLE" = true ]; then
        if mark_complete "$ELAPSED"; then
          echo "FULL_LIFECYCLE_RECOVERY = PASS"
          echo "Recovery time: $ELAPSED seconds"
          return 0
        fi
        mark_failed COMPLETE_RECORD_FAILED
        return 83
      fi
    else
      log_line "probe_target=${PROBE_AT}s probe_failed=YES"
    fi
  done
  mark_failed WFC_HEALTH_TIMEOUT
  return 84
}

full_status() {
  require_root
  echo "Full lifecycle recovery:"
  if [ -r "$PENDING" ]; then
    read_marker
    if [ "$MARK_STAGE" = FAILED ]; then
      echo "FAILED"
      echo "Stage: FAILED"
      echo "Failure: ${MARK_FAILURE:-UNKNOWN}"
    else
      echo "PENDING"
      echo "Stage: ${MARK_STAGE:-UNKNOWN}"
    fi
    echo "false/reboot/true: ${MARK_FALSE:-?}/${MARK_REBOOT:-?}/${MARK_TRUE:-?}"
    echo "Boot before: ${MARK_BOOT_BEFORE:-UNKNOWN}"
    echo "Boot after: ${MARK_BOOT_AFTER:-PENDING}"
  elif [ -r "$LAST_STATE" ] && grep -q '^stage=COMPLETE$' "$LAST_STATE"; then
    echo "COMPLETE"
  else
    echo "IDLE"
  fi
}

full_cancel() {
  require_root
  ensure_storage || return 40
  acquire_lock || return 50
  if [ -e "$PENDING" ]; then
    rm -f "$PENDING" || { echo "Unable to clear pending marker."; return 40; }
    sync_path "$STATE_DIR"
    echo "Full lifecycle pending marker cleared. No SIM/UICC write was performed."
  else
    echo "No full lifecycle pending marker exists. ZERO WRITE."
  fi
  if run_probe; then
    load_fields
    if [ "$FAILURE_CLASS" = F8 ] || [ "$SUB_ACTIVE" = false ] || [ "$UICC_ENABLED" = false ]; then
      echo "WARNING: VOXI still appears inactive/disabled (F8). Cancel does not re-enable it."
    fi
  fi
}

case "${1:-}" in
  start) start_full_recovery ;;
  resume) resume_full_recovery ;;
  status) full_status ;;
  cancel) full_cancel ;;
  *) echo "Usage: wfc-full-lifecycle.sh {start|resume|status|cancel}"; exit 2 ;;
esac