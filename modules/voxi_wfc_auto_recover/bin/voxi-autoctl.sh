#!/system/bin/sh

MODDIR=${0%/*}
MODDIR=${MODDIR%/*}
DATA=/data/adb/voxi-wfc-auto-recover
CONFIG="$DATA/config.conf"
LOGS="$DATA/logs"
STATE="$DATA/state"
PROBE="$MODDIR/lib/wfc-probe.jar"
RECOVERY="$MODDIR/lib/wfc-recovery-helper.jar"
LOCK="$STATE/recovery.lock.d"
VERSION=v0.1.0

umask 077

require_root() {
  [ "$(id -u)" = 0 ] || { echo "ERROR: root is required" >&2; return 40; }
}

ensure_data() {
  mkdir -p "$LOGS" "$STATE" || return 1
  chmod 0700 "$DATA" "$LOGS" "$STATE" 2>/dev/null
}

sanitize() {
  sed -E \
    -e 's/(iccId=)[^ ,}]*/\1[REDACTED]/gI' \
    -e 's/(cardString=)[^ ,}]*/\1[REDACTED]/gI' \
    -e 's/(imsi=|subscriberId=|mNumber=)[^ ,}]*/\1[REDACTED]/gI' \
    -e 's/[0-9]{12,}/[REDACTED]/g'
}

probe() {
  PROBE_RAW=$(CLASSPATH="$PROBE" app_process /system/bin WfcStateProbe read-only-json 2>&1)
  PROBE_RC=$?
  PROBE_JSON=$(printf '%s\n' "$PROBE_RAW" | sed -n '/^{/p' | tail -n 1)
  [ "$PROBE_RC" -eq 0 ] && [ -n "$PROBE_JSON" ]
}

object() { printf '%s\n' "$PROBE_JSON" | sed -n "s/.*\"$1\":{\([^}]*\)}.*/\1/p"; }
field() { printf '%s\n' "$1" | sed -n "s/.*\"$2\":\([^,}]*\).*/\1/p" | sed 's/^\"//;s/\"$//'; }
root_field() { printf '%s\n' "$PROBE_JSON" | sed -n "s/.*\"$1\":\([^,}]*\).*/\1/p" | sed 's/^\"//;s/\"$//'; }

load() {
  TARGET=$(object target); SLOT0=$(object protectedSlot0); SUB=$(object subscription)
  IMS=$(object ims); MMTEL=$(object mmtel); WFC=$(object wfc)
  CONN=$(object connectivity); EPDG=$(object epdg)
  TARGET_SUB=$(field "$TARGET" subId); TARGET_SLOT=$(field "$TARGET" slotId)
  TARGET_PHONE=$(field "$TARGET" phoneId); TARGET_CARRIER=$(field "$TARGET" carrierId)
  TARGET_MCC=$(field "$TARGET" mcc); TARGET_MNC=$(field "$TARGET" mnc)
  TARGET_GATE=$(field "$TARGET" mappingGate)
  SLOT0_GATE=$(field "$SLOT0" mappingGate); SLOT0_SUB=$(field "$SLOT0" subId)
  SLOT0_SLOT=$(field "$SLOT0" slotId); SLOT0_CARRIER=$(field "$SLOT0" carrierId)
  SLOT0_MCC=$(field "$SLOT0" mcc); SLOT0_MNC=$(field "$SLOT0" mnc)
  SUB_ACTIVE=$(field "$SUB" active); UICC_ENABLED=$(field "$SUB" areUiccApplicationsEnabled)
  IMS_NAME=$(field "$IMS" registrationStateName); IMS_RAW=$(field "$IMS" registrationStateRaw)
  TRANSPORT=$(field "$IMS" registrationTransportName); TRANSPORT_RAW=$(field "$IMS" registrationTransportRaw)
  VOICE_IWLAN=$(field "$MMTEL" voiceIwlanAvailable); WFC_AVAILABLE=$(field "$WFC" wifiCallingAvailable)
  IMS_AGENT=$(field "$CONN" imsIwlanNetworkAgent); QTI_REQUEST=$(field "$CONN" qtiCneRequestRegistered)
  UDP4500=$(field "$EPDG" udp4500Keepalive); XFRM=$(field "$EPDG" xfrmTunnel)
  SAFETY=$(root_field safetyGate); HEALTHY=$(root_field directWfcHealthy); FAILURE=$(root_field failureClass)
}

classify() {
  if [ "$HEALTHY" = true ] && [ "$SAFETY" = true ]; then RESULT=HEALTHY; return 0; fi
  if [ "$SLOT0_GATE" != true ]; then RESULT=UNSAFE; return 30; fi
  if [ "$SUB_ACTIVE" = false ] || [ "$UICC_ENABLED" = false ]; then RESULT=INACTIVE; return 10; fi
  if [ "$SUB_ACTIVE" = true ] && [ "$UICC_ENABLED" = true ] && [ "$TARGET_GATE" = true ]; then RESULT=BROKEN; return 20; fi
  RESULT=UNKNOWN; return 40
}

bool_word() { [ "$1" = true ] && echo "$2" || { [ "$1" = false ] && echo "$3" || echo UNKNOWN; }; }

status() {
  require_root || return $?
  probe || { echo "Probe failed: $PROBE_RAW" >&2; return 40; }
  load; classify; RC=$?
  echo "VOXI WFC Auto Recover $VERSION"
  echo "VOXI: slot=$TARGET_SLOT phoneId=$TARGET_PHONE subId=$TARGET_SUB MCCMNC=$TARGET_MCC$TARGET_MNC carrierId=$TARGET_CARRIER"
  echo "Subscription: $(bool_word "$SUB_ACTIVE" ACTIVE INACTIVE)"
  echo "UICC Apps: $(bool_word "$UICC_ENABLED" ENABLED DISABLED)"
  echo "IMS: ${IMS_NAME:-UNKNOWN} (${IMS_RAW:-UNKNOWN})"
  echo "Transport: ${TRANSPORT:-UNKNOWN} (${TRANSPORT_RAW:-UNKNOWN})"
  echo "VOICE/IWLAN: $(bool_word "$VOICE_IWLAN" AVAILABLE UNAVAILABLE)"
  echo "WFC: $(bool_word "$WFC_AVAILABLE" AVAILABLE UNAVAILABLE)"
  echo "ePDG UDP/4500: $(bool_word "$UDP4500" PRESENT MISSING)"
  echo "XFRM: $(bool_word "$XFRM" PRESENT MISSING)"
  echo "qti.cne IMS request: $(bool_word "$QTI_REQUEST" PRESENT MISSING)"
  echo "qcrild: $(pidof vendor.qcrild 2>/dev/null || echo MISSING)"
  echo "qcrild2: $(pidof vendor.qcrild2 2>/dev/null || echo MISSING)"
  echo "Failure class: ${FAILURE:-F9}"
  echo "Protected slot0: subId=$SLOT0_SUB slot=$SLOT0_SLOT carrierId=$SLOT0_CARRIER MCCMNC=$SLOT0_MCC$SLOT0_MNC gate=$(bool_word "$SLOT0_GATE" PASS FAIL)"
  echo "Result: $RESULT"
  return "$RC"
}

read_config() {
  ENABLED=0
  if [ -r "$CONFIG" ]; then
    VALUE=$(sed -n 's/^ENABLED=\([01]\)$/\1/p' "$CONFIG" | tail -n 1)
    [ "$VALUE" = 1 ] && ENABLED=1
  fi
  case "$ENABLED" in 0|1) ;; *) ENABLED=0 ;; esac
}

write_enabled() {
  require_root || return $?
  ensure_data || return 40
  read_config
  TMP="$CONFIG.$$"
  sed '/^ENABLED=/d' "$CONFIG" 2>/dev/null > "$TMP"
  echo "ENABLED=$1" >> "$TMP"
  chmod 0600 "$TMP" && mv -f "$TMP" "$CONFIG"
  [ "$1" = 1 ] && echo "Automatic recovery: ENABLED" || echo "Automatic recovery: DISABLED"
}

recover_now() {
  require_root || return $?
  ensure_data || return 40
  if ! mkdir "$LOCK" 2>/dev/null; then echo "Recovery is already running"; return 50; fi
  trap 'rm -rf "$LOCK"' EXIT HUP INT TERM
  LOG="$LOGS/recovery-$(date '+%Y%m%d-%H%M%S').log"
  status 2>&1 | sanitize | tee "$LOG"
  probe || { echo "Probe failed; ZERO WRITE" | tee -a "$LOG"; return 40; }
  load; classify >/dev/null
  if [ "$RESULT" = HEALTHY ]; then echo "HEALTHY; ZERO WRITE" | tee -a "$LOG"; return 0; fi
  if [ "$RESULT" != INACTIVE ] || [ "$FAILURE" != F8 ]; then
    echo "Not strict F8. Automatic write blocked; ESCALATION_REQUIRED; ZERO WRITE" | tee -a "$LOG"
    return 20
  fi
  GATE=$(CLASSPATH="$RECOVERY" app_process /system/bin Slot1UiccRecoverHelper dry-run 2>&1); GATE_RC=$?
  printf '%s\n' "$GATE" | sanitize | tee -a "$LOG"
  if [ "$GATE_RC" -ne 0 ] || ! printf '%s\n' "$GATE" | grep -q '^inactiveRecoveryGate=PASS$'; then
    echo "F8 safety gate failed; ZERO WRITE" | tee -a "$LOG"; return 30
  fi
  echo "Executing one fixed setUiccApplicationsEnabled(true,11)" | tee -a "$LOG"
  OUT=$(CLASSPATH="$RECOVERY" app_process /system/bin Slot1UiccRecoverHelper recover 2>&1); WRITE_RC=$?
  printf '%s\n' "$OUT" | sanitize | tee -a "$LOG"
  [ "$WRITE_RC" -eq 0 ] || { echo "Write failed; no retry" | tee -a "$LOG"; return 60; }
  START=$(date +%s)
  while [ $(( $(date +%s) - START )) -lt 120 ]; do
    sleep 5
    if probe; then load; [ "$HEALTHY" = true ] && [ "$SAFETY" = true ] && {
      echo "RECOVERY PASS after $(( $(date +%s) - START )) seconds" | tee -a "$LOG"; return 0;
    }; fi
  done
  echo "RECOVERY FAIL; no retry; scene preserved" | tee -a "$LOG"
  return 60
}

diagnose() {
  require_root || return $?
  ensure_data || return 40
  DIR="$LOGS/diagnostic-$(date '+%Y%m%d-%H%M%S')"; mkdir -p "$DIR" || return 40
  status > "$DIR/status.txt" 2>&1
  probe && printf '%s\n' "$PROBE_JSON" | sanitize > "$DIR/probe.json"
  for SVC in isub phone telephony.registry telephony_ims carrier_config connectivity; do dumpsys "$SVC" 2>&1 | sanitize > "$DIR/dumpsys-$SVC.txt"; done
  ps -A -o USER,PID,PPID,NAME,CMDLINE 2>&1 | sanitize > "$DIR/processes.txt"
  logcat -d -v threadtime 2>&1 | sanitize > "$DIR/logcat-full.txt"
  echo "$DIR"
}

case "${1:-}" in
  status) status ;;
  status-json) require_root && probe && printf '%s\n' "$PROBE_JSON" ;;
  recover-now) recover_now ;;
  diagnose) diagnose ;;
  enable) write_enabled 1 ;;
  disable) write_enabled 0 ;;
  config) read_config; [ "$ENABLED" = 1 ] && echo "Automatic recovery: ENABLED" || echo "Automatic recovery: DISABLED"; cat "$CONFIG" 2>/dev/null ;;
  logs) ls -1t "$LOGS" 2>/dev/null | head -n 20 ;;
  version) echo "$VERSION" ;;
  *) echo "Usage: voxi-autoctl.sh {status|status-json|recover-now|diagnose|enable|disable|config|logs|version}"; exit 2 ;;
esac
