#!/system/bin/sh

MODDIR=${0%/*}
MODDIR=${MODDIR%/*}
PROBE_JAR="$MODDIR/lib/wfc-probe.jar"
RECOVERY_JAR="$MODDIR/lib/wfc-recovery-helper.jar"
DEEP_REMOVE_JAR="$MODDIR/lib/wfc-deep-remove-helper.jar"
AUTO_RUNNER="$MODDIR/bin/wfc-auto-recover.sh"
DATA_DIR=/data/adb/voxi-wfc-recovery
LOG_DIR="$DATA_DIR/logs"
STATE_DIR="$DATA_DIR/state"
CONFIG_FILE="$DATA_DIR/config.conf"
FALLBACK_LOCK="$STATE_DIR/recovery.lock.d"
LOCK_OWNED=false
VERSION=v1.3

umask 077

require_root() {
  if [ "$(id -u)" != "0" ]; then
    echo "ERROR: run through Magisk root (su -c)." >&2
    exit 40
  fi
}

ensure_storage() {
  mkdir -p "$LOG_DIR" "$STATE_DIR" || return 1
  chmod 0700 "$DATA_DIR" "$LOG_DIR" "$STATE_DIR" 2>/dev/null
}

read_auto_config() {
  AUTO_RECOVER_BOOT=0
  if [ -r "$CONFIG_FILE" ]; then
    CONFIG_VALUE=$(sed -n 's/^AUTO_RECOVER_BOOT=\([01]\)$/\1/p' "$CONFIG_FILE" | tail -n 1)
    [ "$CONFIG_VALUE" = 1 ] && AUTO_RECOVER_BOOT=1
  fi
}

write_auto_config() {
  require_root
  ensure_storage || { echo "Unable to create module data directory." >&2; return 40; }
  CONFIG_TMP="$CONFIG_FILE.$$"
  if ! printf 'AUTO_RECOVER_BOOT=%s\n' "$1" > "$CONFIG_TMP"; then
    rm -f "$CONFIG_TMP"
    echo "Unable to write boot auto-recovery configuration." >&2
    return 40
  fi
  chmod 0600 "$CONFIG_TMP" 2>/dev/null
  if ! mv -f "$CONFIG_TMP" "$CONFIG_FILE"; then
    rm -f "$CONFIG_TMP"
    echo "Unable to install boot auto-recovery configuration." >&2
    return 40
  fi
  if [ "$1" = 1 ]; then
    echo "Boot Auto Recover: ENABLED"
  else
    echo "Boot Auto Recover: DISABLED"
  fi
}

auto_status_command() {
  require_root
  read_auto_config
  if [ "$AUTO_RECOVER_BOOT" = 1 ]; then
    echo "Boot Auto Recover: ENABLED"
  else
    echo "Boot Auto Recover: DISABLED"
  fi
}

run_probe() {
  PROBE_RAW=$(CLASSPATH="$PROBE_JAR" app_process /system/bin WfcStateProbe read-only-json 2>&1)
  PROBE_RC=$?
  PROBE_JSON=$(printf '%s\n' "$PROBE_RAW" | sed -n '/^{/p' | tail -n 1)
  [ "$PROBE_RC" -eq 0 ] && [ -n "$PROBE_JSON" ]
}

json_object() {
  printf '%s\n' "$PROBE_JSON" | sed -n "s/.*\"$1\":{\([^}]*\)}.*/\1/p"
}

json_field() {
  printf '%s\n' "$1" | sed -n "s/.*\"$2\":\([^,}]*\).*/\1/p" | sed 's/^"//;s/"$//'
}

json_root_field() {
  printf '%s\n' "$PROBE_JSON" | sed -n "s/.*\"$1\":\([^,}]*\).*/\1/p" | sed 's/^"//;s/"$//'
}

pretty_bool() {
  case "$1" in
    true) echo "$2" ;;
    false) echo "$3" ;;
    *) echo "UNKNOWN" ;;
  esac
}

load_fields() {
  TARGET_OBJ=$(json_object target)
  SLOT0_OBJ=$(json_object protectedSlot0)
  SUB_OBJ=$(json_object subscription)
  IMS_OBJ=$(json_object ims)
  MMTEL_OBJ=$(json_object mmtel)
  WFC_OBJ=$(json_object wfc)
  CONN_OBJ=$(json_object connectivity)
  EPDG_OBJ=$(json_object epdg)

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
  IMS_STATE=$(json_field "$IMS_OBJ" registrationStateName)
  IMS_STATE_RAW=$(json_field "$IMS_OBJ" registrationStateRaw)
  IMS_TRANSPORT=$(json_field "$IMS_OBJ" registrationTransportName)
  IMS_TRANSPORT_RAW=$(json_field "$IMS_OBJ" registrationTransportRaw)
  VOICE_IWLAN=$(json_field "$MMTEL_OBJ" voiceIwlanAvailable)
  MMTEL_READY=$(json_field "$MMTEL_OBJ" featureState)
  WFC_AVAILABLE=$(json_field "$WFC_OBJ" wifiCallingAvailable)
  IMS_AGENT=$(json_field "$CONN_OBJ" imsIwlanNetworkAgent)
  IMS_NETWORK_ID=$(json_field "$CONN_OBJ" imsNetworkId)
  QTI_REGISTERED=$(json_field "$CONN_OBJ" qtiCneRequestRegistered)
  QTI_ACTIVE=$(json_field "$CONN_OBJ" qtiCneRequestActive)
  QTI_REQUEST_ID=$(json_field "$CONN_OBJ" qtiCneRequestId)
  QTI_SATISFIED_ID=$(json_field "$CONN_OBJ" qtiCneSatisfiedRequestId)
  EPDG_KEEPALIVE=$(json_field "$EPDG_OBJ" udp4500Keepalive)
  XFRM_TUNNEL=$(json_field "$EPDG_OBJ" xfrmTunnel)
  SAFETY_GATE=$(json_root_field safetyGate)
  DIRECT_HEALTH=$(json_root_field directWfcHealthy)
  FAILURE_CLASS=$(json_root_field failureClass)
}

classify_result() {
  if [ "$DIRECT_HEALTH" = true ] && [ "$SAFETY_GATE" = true ]; then
    RESULT=HEALTHY; RESULT_RC=0
  elif [ "$SLOT0_GATE" != true ]; then
    RESULT=UNSAFE; RESULT_RC=30
  elif [ "$SUB_ACTIVE" = false ] || [ "$UICC_ENABLED" = false ]; then
    RESULT=INACTIVE; RESULT_RC=10
  elif [ "$SUB_ACTIVE" = true ] && [ "$UICC_ENABLED" = true ] && [ "$TARGET_GATE" = true ]; then
    RESULT=BROKEN; RESULT_RC=20
  elif [ -z "$SUB_ACTIVE" ] || [ "$SUB_ACTIVE" = null ]; then
    RESULT=UNKNOWN; RESULT_RC=40
  else
    RESULT=UNSAFE; RESULT_RC=30
  fi
}

print_status() {
  MCCMNC=UNKNOWN
  if [ "$TARGET_MCC" != null ] && [ "$TARGET_MNC" != null ] && [ -n "$TARGET_MCC" ] && [ -n "$TARGET_MNC" ]; then
    MCCMNC="${TARGET_MCC}${TARGET_MNC}"
  fi
  echo "=============================="
  echo "VOXI WFC Recovery $VERSION"
  echo "=============================="
  echo
  echo "VOXI: slot=${TARGET_SLOT:-UNKNOWN} phoneId=${TARGET_PHONE:-UNKNOWN} subId=${TARGET_SUB:-11} MCCMNC=$MCCMNC carrierId=${TARGET_CARRIER:-UNKNOWN}"
  echo "Subscription: $(pretty_bool "$SUB_ACTIVE" ACTIVE INACTIVE)"
  echo "UICC Apps: $(pretty_bool "$UICC_ENABLED" ENABLED DISABLED)"
  echo
  echo "CORE HEALTH:"
  echo "IMS: ${IMS_STATE:-UNKNOWN} (raw ${IMS_STATE_RAW:-UNKNOWN})"
  echo "Transport: ${IMS_TRANSPORT:-UNKNOWN} (raw ${IMS_TRANSPORT_RAW:-UNKNOWN})"
  echo "VOICE/IWLAN: $(pretty_bool "$VOICE_IWLAN" AVAILABLE UNAVAILABLE)"
  echo "WFC: $(pretty_bool "$WFC_AVAILABLE" AVAILABLE UNAVAILABLE)"
  echo "Result: $RESULT"
  echo "Failure class: ${FAILURE_CLASS:-F9}"
  echo
  echo "Supporting:"
  echo "IMS NetworkAgent: $(pretty_bool "$IMS_AGENT" PRESENT MISSING) (id ${IMS_NETWORK_ID:-UNKNOWN})"
  echo "qti.cne: registered=$(pretty_bool "$QTI_REGISTERED" YES NO) active=$(pretty_bool "$QTI_ACTIVE" YES NO) request=${QTI_REQUEST_ID:-UNKNOWN} satisfied=${QTI_SATISFIED_ID:-NONE}"
  echo "ePDG UDP/4500: $(pretty_bool "$EPDG_KEEPALIVE" PRESENT MISSING)"
  echo "XFRM: $(pretty_bool "$XFRM_TUNNEL" PRESENT MISSING)"
  echo "MMTEL: ${MMTEL_READY:-UNKNOWN}"
  echo "Protected slot0: subId=${SLOT0_SUB:-UNKNOWN} slot=${SLOT0_SLOT:-UNKNOWN} carrierId=${SLOT0_CARRIER:-UNKNOWN} MCCMNC=${SLOT0_MCC:-UNKNOWN}${SLOT0_MNC:-UNKNOWN} gate=$(pretty_bool "$SLOT0_GATE" PASS FAIL)"
}

status_command() {
  require_root
  if ! run_probe; then
    echo "Unable to run WfcStateProbe." >&2
    printf '%s\n' "$PROBE_RAW" >&2
    return 40
  fi
  load_fields; classify_result; print_status
  return "$RESULT_RC"
}

status_json_command() {
  require_root
  if ! run_probe; then
    echo "Unable to run WfcStateProbe." >&2
    printf '%s\n' "$PROBE_RAW" >&2
    return 40
  fi
  printf '%s\n' "$PROBE_JSON"
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

save_diagnostics() {
  ensure_storage || return 1
  STAMP=$(date '+%Y%m%d-%H%M%S'); DIR="$LOG_DIR/$STAMP"
  mkdir -p "$DIR" || return 1; chmod 0700 "$DIR"
  date -Iseconds > "$DIR/timestamp.txt" 2>/dev/null || date > "$DIR/timestamp.txt"
  printf '%s\n' "$PROBE_JSON" | sanitize_stream > "$DIR/probe.json"
  dumpsys isub 2>&1 | sanitize_stream > "$DIR/isub.txt"
  dumpsys telephony.registry 2>&1 | sanitize_stream > "$DIR/telephony.registry.txt"
  dumpsys phone 2>&1 | sanitize_stream > "$DIR/phone.txt"
  dumpsys connectivity 2>&1 | sanitize_stream > "$DIR/connectivity.txt"
  dumpsys carrier_config 2>&1 | sanitize_stream > "$DIR/carrier_config.txt"
  ip xfrm state 2>&1 | sanitize_stream > "$DIR/xfrm-state.txt"
  logcat -d -t 800 2>&1 | grep -Ei 'ims|iwlan|epdg|wfc|vowifi|carrierconfig|subscription|uicc' | tail -n 400 | sanitize_stream > "$DIR/logcat.txt"
  echo "$DIR"
}

release_lock() {
  if [ "$LOCK_OWNED" = true ]; then
    rm -rf "$FALLBACK_LOCK"
    LOCK_OWNED=false
  fi
}

acquire_lock() {
  ensure_storage || return 1
  if ! mkdir "$FALLBACK_LOCK" 2>/dev/null; then
    echo "Recovery already running or a lock directory is present."
    return 1
  fi
  LOCK_OWNED=true
  printf '%s\n' "$$" > "$FALLBACK_LOCK/pid"
  trap 'release_lock' EXIT HUP INT TERM
}

safe_recover_command() {
  require_root; acquire_lock || return 50
  if ! run_probe; then echo "Initial probe failed. No write operation was executed."; return 40; fi
  load_fields; classify_result; print_status
  if [ "$RESULT" = HEALTHY ]; then echo "WFC already healthy. No action required."; return 0; fi
  if [ "$SUB_ACTIVE" = true ] && [ "$UICC_ENABLED" = true ]; then
    echo "Active subscription detected. Safe Recover is blocked."
    echo "No write operation was executed. FAILURE_CLASS=${FAILURE_CLASS:-F9}"
    return 20
  fi
  if [ "$SUB_ACTIVE" != false ] && [ "$UICC_ENABLED" != false ]; then
    echo "Inactive/apps-disabled state was not established. No write operation was executed."; return 30
  fi

  GATE_OUTPUT=$(CLASSPATH="$RECOVERY_JAR" app_process /system/bin Slot1UiccRecoverHelper dry-run 2>&1); GATE_RC=$?
  printf '%s\n' "$GATE_OUTPUT" | sanitize_stream
  if [ "$GATE_RC" -ne 0 ] || ! printf '%s\n' "$GATE_OUTPUT" | grep -q '^inactiveRecoveryGate=PASS$'; then
    echo "Full inactive safety gate failed. No write operation was executed."; return 30
  fi
  OP_LOG="$LOG_DIR/safe-recovery-$(date '+%Y%m%d-%H%M%S').log"
  {
    echo "mode=safe-recover"
    echo "safety_gate=PASS"
    echo "initial=$(date -Iseconds 2>/dev/null || date) state=$RESULT failure=${FAILURE_CLASS:-F9}"
    echo "false_executed=NO"
  } > "$OP_LOG"
  START_EPOCH=$(date +%s)
  WRITE_OUTPUT=$(CLASSPATH="$RECOVERY_JAR" app_process /system/bin Slot1UiccRecoverHelper recover 2>&1); WRITE_RC=$?
  echo "true_timestamp=$(date -Iseconds 2>/dev/null || date) true_exit=$WRITE_RC" >> "$OP_LOG"
  printf '%s\n' "$WRITE_OUTPUT" | sanitize_stream | tee -a "$OP_LOG"
  if [ "$WRITE_RC" -ne 0 ]; then
    echo "result=SAFE_RECOVERY_WRITE_FAILED" >> "$OP_LOG"
    echo "No automatic retry performed." >> "$OP_LOG"
    echo "Safe Recover write failed; no retry."
    return 60
  fi
  while [ $(( $(date +%s) - START_EPOCH )) -lt 60 ]; do
    sleep 2
    if run_probe; then
      load_fields; ELAPSED=$(( $(date +%s) - START_EPOCH ))
      printf '%s\n' "elapsed=${ELAPSED}s $PROBE_JSON" | sanitize_stream >> "$OP_LOG"
      if [ "$DIRECT_HEALTH" = true ] && [ "$SAFETY_GATE" = true ]; then
        {
          echo "result=SAFE_RECOVERY_SUCCESS"
          echo "recovery_time_seconds=$ELAPSED"
          echo "final_ims=$IMS_STATE/$IMS_STATE_RAW transport=$IMS_TRANSPORT/$IMS_TRANSPORT_RAW voice_iwlan=$VOICE_IWLAN wfc=$WFC_AVAILABLE"
        } >> "$OP_LOG"
        echo "WFC RECOVERY SUCCESS"; echo "Recovery time: $ELAPSED seconds"; return 0
      fi
    fi
  done
  {
    echo "result=SAFE_RECOVERY_FAILED"
    echo "No automatic retry performed."
  } >> "$OP_LOG"
  echo "WFC RECOVERY FAILED. No additional write operation was attempted."; return 60
}

deep_recover_command() {
  require_root; acquire_lock || return 50
  if ! run_probe; then echo "Initial probe failed. No write operation was executed."; return 40; fi
  load_fields; classify_result; print_status
  if [ "$RESULT" = HEALTHY ]; then echo "WFC already healthy. Deep Recover is blocked; zero writes."; return 0; fi
  if [ "$SAFETY_GATE" != true ] || [ "$TARGET_GATE" != true ] || [ "$SLOT0_GATE" != true ] \
      || [ "$SUB_ACTIVE" != true ] || [ "$UICC_ENABLED" != true ] \
      || [ "$FAILURE_CLASS" != F1 ] || [ "$IMS_STATE_RAW" != 0 ] || [ "$WFC_AVAILABLE" != false ]; then
    echo "Deep Recover requires verified F1 ACTIVE-BROKEN with the complete dual-SIM safety gate."
    echo "No write operation was executed."; return 30
  fi

  REMOVE_GATE=$(CLASSPATH="$DEEP_REMOVE_JAR" app_process /system/bin Slot1UiccDisableHelper dry-run 2>&1); REMOVE_GATE_RC=$?
  printf '%s\n' "$REMOVE_GATE" | sanitize_stream
  if [ "$REMOVE_GATE_RC" -ne 0 ] || ! printf '%s\n' "$REMOVE_GATE" | grep -q '^deepRemoveGate=PASS$'; then
    echo "Deep remove safety gate failed. No write operation was executed."; return 30
  fi
  OP_LOG="$LOG_DIR/deep-recovery-$(date '+%Y%m%d-%H%M%S').log"
  {
    echo "mode=deep-recover"
    echo "safety_gate=PASS"
    echo "initial_f1_timestamp=$(date -Iseconds 2>/dev/null || date)"
    echo "initial_failure_class=$FAILURE_CLASS"
    echo "initial_slot0=subId:$SLOT0_SUB slot:$SLOT0_SLOT carrierId:$SLOT0_CARRIER mcc:$SLOT0_MCC mnc:$SLOT0_MNC"
    printf '%s\n' "$PROBE_JSON"; printf '%s\n' "$REMOVE_GATE"
  } | sanitize_stream > "$OP_LOG"

  echo "Executing one fixed VOXI software-remove write..."
  FALSE_START=$(date +%s)
  FALSE_OUTPUT=$(CLASSPATH="$DEEP_REMOVE_JAR" app_process /system/bin Slot1UiccDisableHelper disable 2>&1); FALSE_RC=$?
  printf '%s\n' "false_timestamp=$(date -Iseconds 2>/dev/null || date) false_exit=$FALSE_RC" >> "$OP_LOG"
  printf '%s\n' "$FALSE_OUTPUT" | sanitize_stream | tee -a "$OP_LOG"
  if [ "$FALSE_RC" -ne 0 ]; then
    echo "result=SOFTWARE_REMOVE_FAILED" >> "$OP_LOG"
    echo "No automatic retry performed." >> "$OP_LOG"
    echo "Software remove failed. No true call and no retry will be attempted."; return 61
  fi

  F8_REACHED=false
  F8_CONFIRM_COUNT=0
  while [ $(( $(date +%s) - FALSE_START )) -lt 30 ]; do
    sleep 1
    if run_probe; then
      load_fields; ELAPSED=$(( $(date +%s) - FALSE_START ))
      printf '%s\n' "remove_elapsed=${ELAPSED}s $PROBE_JSON" | sanitize_stream >> "$OP_LOG"
      if [ "$FAILURE_CLASS" = F8 ] && { [ "$SUB_ACTIVE" = false ] || [ "$UICC_ENABLED" = false ]; }; then
        F8_CONFIRM_COUNT=$((F8_CONFIRM_COUNT + 1))
        echo "f8_confirmation_sample=$F8_CONFIRM_COUNT elapsed_seconds=$ELAPSED" >> "$OP_LOG"
        if [ "$F8_CONFIRM_COUNT" -ge 2 ]; then
          F8_REACHED=true
          {
            echo "f8_confirmation_timestamp=$(date -Iseconds 2>/dev/null || date)"
            echo "f8_confirmation_elapsed_seconds=$ELAPSED"
            echo "f8_persistent_confirmation=PASS"
          } >> "$OP_LOG"
          echo "Persistent F8/inactive confirmed after ${ELAPSED}s."; break
        fi
      else
        F8_CONFIRM_COUNT=0
      fi
    fi
  done
  if [ "$F8_REACHED" != true ]; then
    echo "result=PERSISTENT_F8_NOT_CONFIRMED" >> "$OP_LOG"
    echo "No automatic retry performed." >> "$OP_LOG"
    echo "Persistent F8/inactive was not confirmed within 30 seconds. True is blocked."
    echo "No further write will be attempted."; return 62
  fi

  RECOVERY_GATE=$(CLASSPATH="$RECOVERY_JAR" app_process /system/bin Slot1UiccRecoverHelper dry-run 2>&1); RECOVERY_GATE_RC=$?
  printf '%s\n' "$RECOVERY_GATE" | sanitize_stream | tee -a "$OP_LOG"
  if [ "$RECOVERY_GATE_RC" -ne 0 ] || ! printf '%s\n' "$RECOVERY_GATE" | grep -q '^inactiveRecoveryGate=PASS$'; then
    echo "result=F8_RECOVERY_GATE_FAILED" >> "$OP_LOG"
    echo "No automatic retry performed." >> "$OP_LOG"
    echo "F8 recovery safety gate failed. True is blocked."; return 63
  fi

  echo "Executing one fixed VOXI software-insert write..."
  TRUE_START=$(date +%s)
  TRUE_OUTPUT=$(CLASSPATH="$RECOVERY_JAR" app_process /system/bin Slot1UiccRecoverHelper recover 2>&1); TRUE_RC=$?
  printf '%s\n' "true_timestamp=$(date -Iseconds 2>/dev/null || date) true_exit=$TRUE_RC" >> "$OP_LOG"
  printf '%s\n' "$TRUE_OUTPUT" | sanitize_stream | tee -a "$OP_LOG"
  if [ "$TRUE_RC" -ne 0 ]; then
    echo "result=SOFTWARE_INSERT_FAILED" >> "$OP_LOG"
    echo "No automatic retry performed." >> "$OP_LOG"
    echo "Software insert failed. No retry will be attempted."; return 64
  fi

  for PROBE_AT in 5 10 15 20 30 45 60 90 120; do
    NOW_ELAPSED=$(( $(date +%s) - TRUE_START ))
    WAIT_SECONDS=$((PROBE_AT - NOW_ELAPSED))
    [ "$WAIT_SECONDS" -gt 0 ] && sleep "$WAIT_SECONDS"
    if run_probe; then
      load_fields; ELAPSED=$(( $(date +%s) - TRUE_START ))
      printf '%s\n' "probe_target=${PROBE_AT}s recover_elapsed=${ELAPSED}s $PROBE_JSON" | sanitize_stream >> "$OP_LOG"
      if [ "$DIRECT_HEALTH" = true ] && [ "$SAFETY_GATE" = true ]; then
        {
          echo "deep_recovery_success_timestamp=$(date -Iseconds 2>/dev/null || date)"
          echo "recovery_time_seconds=$ELAPSED"
          echo "total_recovery_time_seconds=$(( $(date +%s) - FALSE_START ))"
          echo "final_ims=$IMS_STATE/$IMS_STATE_RAW transport=$IMS_TRANSPORT/$IMS_TRANSPORT_RAW voice_iwlan=$VOICE_IWLAN wfc=$WFC_AVAILABLE"
          echo "final_slot0=subId:$SLOT0_SUB slot:$SLOT0_SLOT carrierId:$SLOT0_CARRIER mcc:$SLOT0_MCC mnc:$SLOT0_MNC"
          echo "result=DEEP_RECOVERY_SUCCESS"
        } >> "$OP_LOG"
        echo "DEEP RECOVERY SUCCESS"; echo "Recovery time: $ELAPSED seconds"; return 0
      fi
    fi
  done
  {
    echo "deep_recovery_failure_timestamp=$(date -Iseconds 2>/dev/null || date)"
    echo "result=DEEP_RECOVERY_FAILED"
    echo "Failure point: ACTIVE + ENABLED after insert but IMS/CNE/ePDG did not recover"
    echo "No automatic retry performed."
    echo "final_ims=${IMS_STATE:-UNKNOWN}/${IMS_STATE_RAW:-UNKNOWN} transport=${IMS_TRANSPORT:-UNKNOWN}/${IMS_TRANSPORT_RAW:-UNKNOWN} voice_iwlan=${VOICE_IWLAN:-UNKNOWN} wfc=${WFC_AVAILABLE:-UNKNOWN}"
  } >> "$OP_LOG"
  echo "DEEP_RECOVERY_FAILED"
  echo "Failure point: ACTIVE + ENABLED after insert but IMS/CNE/ePDG did not recover"
  echo "No automatic retry performed."
  echo "HARD RECOVERY REQUIRED"
  echo "Suggested action:"
  echo "1. Keep UK VPN / Wi-Fi environment ready"
  echo "2. Reboot device once"
  echo "3. After reboot allow boot auto recovery to run"
  echo "4. If boot auto is disabled, run manual Deep Recover only once"
  return 65
}

recover_hard_command() {
  require_root
  if ! run_probe; then
    echo "Initial probe failed. No write operation was executed."
    echo "HARD RECOVERY REQUIRED"
    return 40
  fi
  load_fields; classify_result; print_status
  case "$RESULT" in
    HEALTHY)
      echo "SUCCESS: WFC already healthy. ZERO WRITE."
      return 0
      ;;
    INACTIVE)
      echo "F8/inactive detected. Running Safe Recover once."
      safe_recover_command; RECOVER_RC=$?
      ;;
    BROKEN)
      if [ "$FAILURE_CLASS" != F1 ] || [ "$SUB_ACTIVE" != true ] || [ "$UICC_ENABLED" != true ] \
          || [ "$IMS_STATE_RAW" != 0 ] || [ "$WFC_AVAILABLE" != false ]; then
        echo "State is not strict F1. No write operation was executed."
        echo "HARD RECOVERY REQUIRED"
        return 30
      fi
      echo "Strict F1 detected. Running Deep Recover once."
      deep_recover_command; RECOVER_RC=$?
      ;;
    *)
      echo "State is unsafe or unknown. No write operation was executed."
      echo "HARD RECOVERY REQUIRED"
      return 30
      ;;
  esac
  if [ "$RECOVER_RC" -eq 0 ]; then
    echo "SUCCESS"
    return 0
  fi
  echo "HARD RECOVERY REQUIRED"
  echo "Suggested action: keep UK VPN/Wi-Fi ready, reboot once, then allow one boot-auto or manual Deep Recover attempt."
  return "$RECOVER_RC"
}

diagnose_command() {
  require_root
  run_probe || PROBE_JSON='{"error":"WfcStateProbe failed"}'
  DIR=$(save_diagnostics) || { echo "Unable to save diagnostics." >&2; return 40; }
  echo "Diagnostics saved: $DIR"
}

usage() { echo "Usage: wfcctl.sh {status|status-json|safe-recover|deep-recover|recover-hard|diagnose|auto-enable|auto-disable|auto-status|auto-run-now|network-status|version}"; }

case "${1:-}" in
  status) status_command ;;
  status-json) status_json_command ;;
  safe-recover|recover) safe_recover_command ;;
  deep-recover) deep_recover_command ;;
  recover-hard) recover_hard_command ;;
  diagnose) diagnose_command ;;
  auto-enable) write_auto_config 1 ;;
  auto-disable) write_auto_config 0 ;;
  auto-status) auto_status_command ;;
  auto-run-now) require_root; exec "$AUTO_RUNNER" run-now ;;
  network-status) require_root; "$AUTO_RUNNER" network-status ;;
  version) echo "VOXI WFC Recovery $VERSION" ;;
  *) usage; exit 2 ;;
esac
