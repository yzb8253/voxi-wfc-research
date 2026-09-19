#!/system/bin/sh

MODDIR=${0%/*}
MODDIR=${MODDIR%/*}
PROBE_JAR="$MODDIR/lib/wfc-probe.jar"
RECOVERY_JAR="$MODDIR/lib/wfc-recovery-helper.jar"
DATA_DIR=/data/adb/voxi-wfc-recovery
LOG_DIR="$DATA_DIR/logs"
STATE_DIR="$DATA_DIR/state"
LOCK_DIR="$STATE_DIR/recover.lock"
VERSION=v1.0

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
  SUB_ACTIVE=$(json_field "$SUB_OBJ" active)
  UICC_ENABLED=$(json_field "$SUB_OBJ" areUiccApplicationsEnabled)
  IMS_STATE=$(json_field "$IMS_OBJ" registrationStateName)
  IMS_STATE_RAW=$(json_field "$IMS_OBJ" registrationStateRaw)
  IMS_TRANSPORT=$(json_field "$IMS_OBJ" registrationTransportName)
  IMS_TRANSPORT_RAW=$(json_field "$IMS_OBJ" registrationTransportRaw)
  VOICE_IWLAN=$(json_field "$MMTEL_OBJ" voiceIwlanAvailable)
  WFC_AVAILABLE=$(json_field "$WFC_OBJ" wifiCallingAvailable)
  IMS_AGENT=$(json_field "$CONN_OBJ" imsIwlanNetworkAgent)
  EPDG_KEEPALIVE=$(json_field "$EPDG_OBJ" udp4500Keepalive)
  SAFETY_GATE=$(json_root_field safetyGate)
  GOLDEN_STRONG=$(json_root_field goldenStrong)
  FAILURE_CLASS=$(json_root_field failureClass)
}

classify_result() {
  if [ "$GOLDEN_STRONG" = true ] && [ "$SAFETY_GATE" = true ]; then
    RESULT=HEALTHY
    RESULT_RC=0
  elif [ "$SLOT0_GATE" != true ]; then
    RESULT=UNSAFE
    RESULT_RC=30
  elif [ "$SUB_ACTIVE" = false ] || [ "$UICC_ENABLED" = false ]; then
    RESULT=INACTIVE
    RESULT_RC=10
  elif [ "$SUB_ACTIVE" = true ] && [ "$UICC_ENABLED" = true ] && [ "$TARGET_GATE" = true ]; then
    RESULT=BROKEN
    RESULT_RC=20
  elif [ -z "$SUB_ACTIVE" ] || [ "$SUB_ACTIVE" = null ]; then
    RESULT=UNKNOWN
    RESULT_RC=40
  else
    RESULT=UNSAFE
    RESULT_RC=30
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
  echo "VOXI:"
  echo "slot: ${TARGET_SLOT:-UNKNOWN}"
  echo "phoneId: ${TARGET_PHONE:-UNKNOWN}"
  echo "subId: ${TARGET_SUB:-11}"
  echo "MCCMNC: $MCCMNC"
  echo "carrierId: ${TARGET_CARRIER:-UNKNOWN}"
  echo
  echo "Subscription: $(pretty_bool "$SUB_ACTIVE" ACTIVE INACTIVE)"
  echo "UICC Apps: $(pretty_bool "$UICC_ENABLED" ENABLED DISABLED)"
  echo
  echo "IMS: ${IMS_STATE:-UNKNOWN}"
  echo "Transport: ${IMS_TRANSPORT:-UNKNOWN}"
  echo "Voice over IWLAN: $(pretty_bool "$VOICE_IWLAN" AVAILABLE UNAVAILABLE)"
  echo "WFC: $(pretty_bool "$WFC_AVAILABLE" AVAILABLE UNAVAILABLE)"
  echo "IMS NetworkAgent: $(pretty_bool "$IMS_AGENT" ACTIVE MISSING)"
  echo "ePDG: $(pretty_bool "$EPDG_KEEPALIVE" ACTIVE MISSING)"
  echo
  echo "Result:"
  echo "$RESULT"
  echo
  echo "Failure class:"
  echo "${FAILURE_CLASS:-F9}"
}

status_command() {
  require_root
  if ! run_probe; then
    echo "Unable to run WfcStateProbe." >&2
    printf '%s\n' "$PROBE_RAW" >&2
    return 40
  fi
  load_fields
  classify_result
  print_status
  return "$RESULT_RC"
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
  STAMP=$(date '+%Y%m%d-%H%M%S')
  DIR="$LOG_DIR/$STAMP"
  mkdir -p "$DIR" || return 1
  chmod 0700 "$DIR"
  date -Iseconds > "$DIR/timestamp.txt" 2>/dev/null || date > "$DIR/timestamp.txt"
  printf '%s\n' "$PROBE_JSON" | sanitize_stream > "$DIR/probe.json"
  dumpsys isub 2>&1 | sanitize_stream > "$DIR/isub.txt"
  dumpsys telephony.registry 2>&1 | sanitize_stream > "$DIR/telephony.registry.txt"
  dumpsys phone 2>&1 | sanitize_stream > "$DIR/phone.txt"
  dumpsys connectivity 2>&1 | sanitize_stream > "$DIR/connectivity.txt"
  dumpsys carrier_config 2>&1 | sanitize_stream > "$DIR/carrier_config.txt"
  logcat -d -t 800 2>&1 | grep -Ei 'ims|iwlan|epdg|wfc|vowifi|carrierconfig|subscription|uicc' | tail -n 400 | sanitize_stream > "$DIR/logcat.txt"
  echo "$DIR"
}

acquire_lock() {
  ensure_storage || return 1
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "Recovery already running."
    return 1
  fi
  echo $$ > "$LOCK_DIR/pid"
  trap 'rm -rf "$LOCK_DIR"' EXIT HUP INT TERM
}

recover_command() {
  require_root
  acquire_lock || return 50

  if ! run_probe; then
    echo "Initial probe failed. No write operation was executed."
    return 40
  fi
  load_fields
  classify_result
  print_status

  if [ "$RESULT" = HEALTHY ]; then
    echo
    echo "WFC already healthy."
    echo "No action required."
    return 0
  fi

  if [ "$SUB_ACTIVE" = true ] && [ "$UICC_ENABLED" = true ]; then
    echo
    echo "WFC is abnormal but subscription is active."
    echo "Automatic recovery is intentionally blocked."
    echo "No write operation was executed."
    echo "FAILURE_CLASS: ${FAILURE_CLASS:-F9}"
    return 20
  fi

  if [ "$SUB_ACTIVE" != false ] && [ "$UICC_ENABLED" != false ]; then
    echo "Inactive/apps-disabled state was not established. No write operation was executed."
    echo "FAILURE_CLASS: ${FAILURE_CLASS:-F9}"
    return 30
  fi

  echo
  echo "Validated inactive VOXI subscription candidate detected."
  GATE_OUTPUT=$(CLASSPATH="$RECOVERY_JAR" app_process /system/bin Slot1UiccRecoverHelper dry-run 2>&1)
  GATE_RC=$?
  printf '%s\n' "$GATE_OUTPUT" | sanitize_stream
  if [ "$GATE_RC" -ne 0 ] || ! printf '%s\n' "$GATE_OUTPUT" | grep -q '^inactiveRecoveryGate=PASS$'; then
    echo "Full inactive safety gate failed. No write operation was executed."
    return 30
  fi

  ensure_storage || return 40
  OP_LOG="$LOG_DIR/recovery-$(date '+%Y%m%d-%H%M%S').log"
  {
    echo "timestamp=$(date -Iseconds 2>/dev/null || date)"
    echo "pre_failure_class=${FAILURE_CLASS:-F9}"
    printf '%s\n' "$GATE_OUTPUT"
  } | sanitize_stream > "$OP_LOG"

  echo "Executing the single validated recovery write..."
  START_EPOCH=$(date +%s)
  WRITE_OUTPUT=$(CLASSPATH="$RECOVERY_JAR" app_process /system/bin Slot1UiccRecoverHelper recover 2>&1)
  WRITE_RC=$?
  printf '%s\n' "$WRITE_OUTPUT" | sanitize_stream | tee -a "$OP_LOG"
  echo "helper_exit=$WRITE_RC" >> "$OP_LOG"
  if [ "$WRITE_RC" -ne 0 ]; then
    echo "WFC RECOVERY FAILED"
    echo "The single write attempt returned an error. No additional write will be attempted."
    run_probe
    DIR=$(save_diagnostics)
    echo "Diagnostics: $DIR"
    return 60
  fi

  FIRST_GOLDEN=
  for DEADLINE in 1 2 3 5 10 15 20 30 45 60; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_EPOCH))
    if [ "$ELAPSED" -lt "$DEADLINE" ]; then
      sleep $((DEADLINE - ELAPSED))
    fi
    if ! run_probe; then
      printf '%s\n' "probe_error_at=${DEADLINE}s" >> "$OP_LOG"
      continue
    fi
    load_fields
    classify_result
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_EPOCH))
    printf '%s\n' "elapsed=${ELAPSED}s $PROBE_JSON" | sanitize_stream >> "$OP_LOG"
    echo "Probe ${ELAPSED}s: $RESULT / ${FAILURE_CLASS:-F9}"
    if [ "$GOLDEN_STRONG" = true ] && [ "$SLOT0_GATE" = true ]; then
      FIRST_GOLDEN=$ELAPSED
      echo "GOLDEN_STRONG reached; confirming for 5 seconds..."
      sleep 5
      if run_probe; then
        load_fields
        classify_result
        printf '%s\n' "confirmation $PROBE_JSON" | sanitize_stream >> "$OP_LOG"
        if [ "$GOLDEN_STRONG" = true ] && [ "$SLOT0_GATE" = true ]; then
          echo "WFC RECOVERY SUCCESS"
          echo "Recovery time: $FIRST_GOLDEN seconds"
          return 0
        fi
      fi
      echo "Confirmation failed; observation continues without another write."
    fi
  done

  echo "WFC RECOVERY FAILED"
  echo "No additional write operation was attempted."
  run_probe
  DIR=$(save_diagnostics)
  echo "Diagnostics: $DIR"
  return 60
}

diagnose_command() {
  require_root
  if ! run_probe; then
    PROBE_JSON='{"error":"WfcStateProbe failed"}'
  fi
  DIR=$(save_diagnostics) || {
    echo "Unable to save diagnostics." >&2
    return 40
  }
  echo "Diagnostics saved: $DIR"
}

usage() {
  echo "Usage: wfcctl.sh {status|recover|diagnose|version}"
}

case "${1:-}" in
  status) status_command ;;
  recover) recover_command ;;
  diagnose) diagnose_command ;;
  version) echo "VOXI WFC Recovery $VERSION" ;;
  *) usage; exit 2 ;;
esac
