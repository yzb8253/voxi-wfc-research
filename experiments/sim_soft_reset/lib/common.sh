#!/usr/bin/env sh

set -u

LAB_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ADB_BIN=${ADB_BIN:-adb}
SERIAL=${SERIAL:-}
OBSERVE_SECONDS=${OBSERVE_SECONDS:-180}
PROBE_JAR=/data/adb/modules/voxi_wfc_recovery/lib/wfc-probe.jar
RECOVERY_JAR=/data/adb/modules/voxi_wfc_recovery/lib/wfc-recovery-helper.jar
REMOVE_JAR=/data/adb/modules/voxi_wfc_recovery/lib/wfc-deep-remove-helper.jar

die() { echo "ERROR: $*" >&2; exit 1; }

adb_cmd() {
  if [ -n "$SERIAL" ]; then "$ADB_BIN" -s "$SERIAL" "$@"; else "$ADB_BIN" "$@"; fi
}

root_shell() {
  ESCAPED=$(printf '%s' "$1" | sed "s/'/'\\\\''/g")
  adb_cmd shell "su -c '$ESCAPED'"
}

require_device() {
  [ "$(adb_cmd get-state 2>/dev/null)" = device ] || die "ADB device is not online; set SERIAL explicitly"
  [ "$(root_shell 'id -u' 2>/dev/null | tr -d '\r')" = 0 ] || die "root/su is unavailable"
}

probe_json() {
  root_shell "CLASSPATH=$PROBE_JAR app_process /system/bin WfcStateProbe read-only-json" 2>/dev/null \
    | tr -d '\r' | sed -n '/^{/p' | tail -n 1
}

safety_gate() {
  JSON=$(probe_json)
  [ -n "$JSON" ] || die "WfcStateProbe failed"
  printf '%s\n' "$JSON" | grep -Eq '"target":\{"subId":11,"slotId":1,"phoneId":1,"carrierId":28,"mcc":234,"mnc":15,"mappingGate":true\}' \
    || die "VOXI fixed mapping gate failed"
  printf '%s\n' "$JSON" | grep -Eq '"protectedSlot0":\{"subId":1,"slotId":0,"carrierId":2237,"mcc":460,"mnc":11,"active":true,"mappingGate":true\}' \
    || die "China Telecom slot0 gate failed"
  printf '%s\n' "$JSON" | grep -q '"safetyGate":true' || die "combined safety gate failed"
}

capture() {
  LABEL=$1
  DIR=$2
  mkdir -p "$DIR/$LABEL"
  date -Iseconds > "$DIR/$LABEL/host-time.txt"
  probe_json > "$DIR/$LABEL/probe.json" || true
  root_shell 'getprop' > "$DIR/$LABEL/getprop.txt" 2>&1 || true
  root_shell 'ps -AZ' > "$DIR/$LABEL/processes.txt" 2>&1 || true
  root_shell 'service list' > "$DIR/$LABEL/services.txt" 2>&1 || true
  for SERVICE in isub phone telephony.registry telephony_ims carrier_config connectivity; do
    root_shell "dumpsys $SERVICE" > "$DIR/$LABEL/dumpsys-$SERVICE.txt" 2>&1 || true
  done
  root_shell 'ip link; ip route show table all; ip rule; ip xfrm state; ip xfrm policy' > "$DIR/$LABEL/network.txt" 2>&1 || true
}

sample() {
  AT=$1
  DIR=$2
  printf '%s\t%s\n' "$AT" "$(probe_json)" >> "$DIR/timeline-probe.jsonl"
  root_shell "dumpsys telephony.registry | grep -E 'mSimState|mServiceState|mDataConnectionState|mDataNetworkType'" \
    > "$DIR/registry-$AT.txt" 2>&1 || true
}

start_logcat() {
  DIR=$1
  adb_cmd logcat -v threadtime > "$DIR/logcat-full.txt" 2>&1 &
  LOGCAT_PID=$!
}

stop_logcat() {
  kill "$LOGCAT_PID" 2>/dev/null || true
  wait "$LOGCAT_PID" 2>/dev/null || true
}

observe() {
  DIR=$1
  START=$(date +%s)
  for TARGET in 0 1 2 3 5 10 15 20 30 45 60 90 120 180; do
    [ "$TARGET" -gt "$OBSERVE_SECONDS" ] && break
    NOW=$(( $(date +%s) - START ))
    WAIT=$((TARGET - NOW))
    [ "$WAIT" -gt 0 ] && sleep "$WAIT"
    sample "${TARGET}s" "$DIR"
  done
}

summarize() {
  DIR=$1
  FINAL=$(tail -n 1 "$DIR/timeline-probe.jsonl" 2>/dev/null | sed 's/^[^\t]*\t//')
  SIM_READY=NO
  grep -Eqi 'SIM_STATE_CHANGED.*(READY|LOADED)|sim.*state.*(READY|LOADED)|IccCard.*READY' "$DIR/logcat-full.txt" && SIM_READY=YES
  IMS=NO; TRANSPORT=NO; VOICE=NO; WFC=NO; EPDG=NO; XFRM=NO
  printf '%s' "$FINAL" | grep -q '"registrationStateRaw":2' && IMS=YES
  printf '%s' "$FINAL" | grep -q '"registrationTransportRaw":2' && TRANSPORT=YES
  printf '%s' "$FINAL" | grep -q '"voiceIwlanAvailable":true' && VOICE=YES
  printf '%s' "$FINAL" | grep -q '"wifiCallingAvailable":true' && WFC=YES
  printf '%s' "$FINAL" | grep -q '"udp4500Keepalive":true' && EPDG=YES
  printf '%s' "$FINAL" | grep -q '"xfrmTunnel":true' && XFRM=YES
  RESULT=FAIL
  [ "$IMS$TRANSPORT$VOICE$WFC" = YESYESYESYES ] && RESULT=PASS
  {
    echo "# Experiment result"
    echo
    echo "- SIM READY event: $SIM_READY"
    echo "- IMS REGISTERED(2): $IMS"
    echo "- Transport WLAN(2): $TRANSPORT"
    echo "- VOICE/IWLAN available: $VOICE"
    echo "- WFC available: $WFC"
    echo "- ePDG UDP/4500: $EPDG"
    echo "- XFRM: $XFRM"
    echo "- DIRECT_WFC_RECOVERY: $RESULT"
    echo
    echo 'Final probe:'
    echo '```json'
    printf '%s\n' "$FINAL"
    echo '```'
  } > "$DIR/RESULT.md"
}

run_experiment() {
  ID=$1
  TITLE=$2
  ACTION=$3
  require_device
  safety_gate
  STAMP=$(date '+%Y%m%d-%H%M%S')
  RUN_DIR="$LAB_ROOT/runs/$STAMP-$ID"
  mkdir -p "$RUN_DIR"
  {
    echo "id=$ID"
    echo "title=$TITLE"
    echo "serial=${SERIAL:-default}"
    echo "execute=${LAB_EXECUTE:-NO}"
    echo "started=$(date -Iseconds)"
  } > "$RUN_DIR/metadata.txt"
  capture before "$RUN_DIR"

  if [ "${LAB_EXECUTE:-NO}" != YES ]; then
    echo "DRY RUN: $TITLE"
    echo "Set LAB_EXECUTE=YES only after reviewing MATRIX.md."
    echo "No device write executed. Evidence: $RUN_DIR"
    return 0
  fi

  start_logcat "$RUN_DIR"
  trap 'stop_logcat' EXIT HUP INT TERM
  printf '%s\n' "action_start=$(date -Iseconds)" > "$RUN_DIR/action.txt"
  "$ACTION" >> "$RUN_DIR/action.txt" 2>&1
  ACTION_RC=$?
  printf '%s\n' "action_exit=$ACTION_RC action_end=$(date -Iseconds)" >> "$RUN_DIR/action.txt"
  observe "$RUN_DIR"
  stop_logcat
  trap - EXIT HUP INT TERM
  capture after "$RUN_DIR"
  summarize "$RUN_DIR"
  echo "Experiment complete: $RUN_DIR"
  return "$ACTION_RC"
}

blocked_experiment() {
  ID=$1; TITLE=$2; REASON=$3
  require_device
  safety_gate
  STAMP=$(date '+%Y%m%d-%H%M%S'); RUN_DIR="$LAB_ROOT/runs/$STAMP-$ID"
  mkdir -p "$RUN_DIR"; capture before "$RUN_DIR"
  printf '%s\n' "BLOCKED: $REASON" | tee "$RUN_DIR/action.txt"
  echo "No device write executed. Evidence: $RUN_DIR"
  exit 78
}
