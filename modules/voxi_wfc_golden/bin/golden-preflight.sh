#!/system/bin/sh

# Writable dfd8241 normalization effects. Predicates use 0/1 internally;
# every Effect/Step returns 0 or a documented public failure code.
qcrild_primary_line() { ps -A -o PID,PPID,NAME,ARGS 2>/dev/null | grep -E '^ *[0-9]+ +1 +qcrild +qcrild$' | head -n 1; }
qcrild2_line() { ps -A -o PID,PPID,NAME,ARGS 2>/dev/null | grep -E '^ *[0-9]+ +1 +qcrild +qcrild -c 2$' | head -n 1; }
line_pid() { printf '%s\n' "$1" | awk '{print $1}'; }

wait_native_dual_owner() {
  HPID=$1; MAX=$2; I=0
  while [ "$I" -lt "$MAX" ]; do
    PM_PID=$(get_per_mgr_pid)
    if [ "$(get_per_mgr_state)" = running ] && [ "$(get_per_mgr_exe)" = /vendor/bin/pm-service ] &&
       [ "$(owner_count)" -eq 2 ] && owner_has_pid "$HPID" && owner_has_pid "$PM_PID" && [ "$(get_x55_state)" = ONLINE ]; then return 0; fi
    sleep 1; I=$((I + 1))
  done
  return 30
}

stop_exact_holder() {
  HPID=$1; REASON=$2
  if ! holder_process_identity_ok "$HPID"; then log_line "HOLDER_STOP_BLOCKED identity mismatch pid=$HPID"; return 30; fi
  record_write "HOLDER_TERM pid=$HPID reason=$REASON"
  kill -TERM "$HPID" 2>/dev/null
  RC=$?
  if [ "$RC" -ne 0 ]; then return 60; fi
  I=0; while [ "$I" -lt 3 ] && [ -d "/proc/$HPID" ]; do sleep 1; I=$((I + 1)); done
  if [ -d "/proc/$HPID" ] && [ "$(readlink "/proc/$HPID/fd/9" 2>/dev/null)" = "$ESOC_DEVICE" ]; then
    record_write "HOLDER_KILL_EXACT pid=$HPID reason=$REASON"
    kill -KILL "$HPID" 2>/dev/null
    RC=$?
    if [ "$RC" -ne 0 ]; then return 60; fi
  fi
  I=0; while [ "$I" -lt 5 ] && [ -d "/proc/$HPID" ]; do sleep 1; I=$((I + 1)); done
  if [ -d "/proc/$HPID" ]; then return 70; fi
  SAVED=$(saved_holder_pid 2>/dev/null || true)
  if [ "$SAVED" = "$HPID" ]; then rm -f "$HOLDER_PIDFILE"; fi
  return 0
}

start_module_holder() {
  if [ -e "$HOLDER_PIDFILE" ]; then return 30; fi
  record_write 'HOLDER_START exact module process'
  nohup /system/bin/sh "$MODDIR/bin/x55-holder.sh" "$HOLDER_PIDFILE" </dev/null >/dev/null 2>&1 &
  I=0
  while [ "$I" -lt 10 ]; do
    HPID=$(saved_holder_pid 2>/dev/null || true)
    if [ -n "$HPID" ] && holder_identity_ok "$HPID"; then HOLDER_PID_CREATED=$HPID; log_line "HOLDER_PID=$HPID"; return 0; fi
    sleep 1; I=$((I + 1))
  done
  return 60
}

verify_native_fingerprint() {
  log_line 'NATIVE_FINGERPRINT_CHECK=START'
  if ! native_clean; then
    log_line 'NATIVE_FINGERPRINT_CHECK=FAIL reason=NATIVE_CLEAN_FALSE'
    return 1
  fi
  NATIVE_SAVED_HOLDER=$(saved_holder_pid 2>/dev/null || true)
  if [ -n "$NATIVE_SAVED_HOLDER" ]; then
    log_line "NATIVE_FINGERPRINT_CHECK=FAIL reason=MODULE_HOLDER_PRESENT pid=$NATIVE_SAVED_HOLDER"
    return 1
  fi
  if unknown_owner_present; then
    log_line 'NATIVE_FINGERPRINT_CHECK=FAIL reason=UNKNOWN_ESOC_OWNER'
    return 1
  fi
  log_line 'NATIVE_FINGERPRINT_CHECK=PASS'
  return 0
}

qcrild2_reacquire() {
  HPID=$1; PRIMARY_BEFORE=$(qcrild_primary_line); SLOT2_BEFORE=$(qcrild2_line); OLD_SLOT2_PID=$(line_pid "$SLOT2_BEFORE"); ENTRY_CRASH=$(get_crash_count)
  if [ "$(get_airplane)" != 0 ] || [ "$(get_per_mgr_state)" != running ] || [ "$(get_per_mgr_exe)" != /vendor/bin/pm-service ]; then return 30; fi
  if ! holder_identity_ok "$HPID"; then return 30; fi
  if [ "$(get_vendor_x55_state)" != OFFLINE ] || [ "$(get_x55_state)" != ONLINE ]; then return 30; fi
  case "$ENTRY_CRASH" in ''|*[!0-9]*) return 30;; esac
  if [ -z "$PRIMARY_BEFORE" ] || [ -z "$SLOT2_BEFORE" ]; then return 30; fi
  stop_exact_holder "$HPID" qcrild2_reacquire; RC=$?
  if [ "$RC" -ne 0 ]; then return "$RC"; fi
  I=0; OFFLINE_CRASH=
  while [ "$I" -lt 15 ]; do
    C=$(get_crash_count)
    if [ "$(owner_count)" -eq 0 ] && [ "$(get_vendor_x55_state)" = OFFLINE ] && [ "$(get_x55_state)" = OFFLINE ]; then
      case "$C" in ''|*[!0-9]*) ;; *) if [ "$C" -ge "$ENTRY_CRASH" ]; then OFFLINE_CRASH=$C; break; fi;; esac
    fi
    sleep 1; I=$((I + 1))
  done
  if [ -z "$OFFLINE_CRASH" ] || [ "$(qcrild_primary_line)" != "$PRIMARY_BEFORE" ] || [ "$(line_pid "$(qcrild2_line)")" != "$OLD_SLOT2_PID" ]; then return 30; fi
  record_write 'CTL_RESTART vendor.qcrild2'
  setprop ctl.restart vendor.qcrild2
  RC=$?
  if [ "$RC" -ne 0 ]; then return 60; fi
  I=0
  while [ "$I" -lt 15 ]; do
    sleep 1; NEW_SLOT2_PID=$(line_pid "$(qcrild2_line)"); PM_PID=$(get_per_mgr_pid)
    if [ -n "$NEW_SLOT2_PID" ] && [ "$NEW_SLOT2_PID" != "$OLD_SLOT2_PID" ] && [ "$(owner_count)" -eq 1 ] && owner_has_pid "$PM_PID" &&
       [ "$(get_per_mgr_exe)" = /vendor/bin/pm-service ] && [ "$(get_vendor_x55_state)" = ONLINE ] && [ "$(get_x55_state)" = ONLINE ] && [ "$(get_crash_count)" = "$OFFLINE_CRASH" ]; then
      if [ "$(qcrild_primary_line)" != "$PRIMARY_BEFORE" ]; then return 30; fi
      log_line "QCRILD2_REACQUIRE=PASS old=$OLD_SLOT2_PID new=$NEW_SLOT2_PID"; HOLDER_PID_CREATED=; return 0
    fi
    I=$((I + 1))
  done
  return 30
}

restore_native() {
  if verify_native_fingerprint; then ENVIRONMENT_TOUCHED=0; log_line 'RESTORE_NATIVE=ALREADY_NATIVE'; return 0; fi
  HPID=$(saved_holder_pid 2>/dev/null || true)
  if [ -n "$HPID" ] && [ ! -d "/proc/$HPID" ]; then rm -f "$HOLDER_PIDFILE"; log_line "RESTORE_NATIVE removed dead module pidfile pid=$HPID"; HPID=; fi
  if [ -z "$HPID" ]; then
    if unknown_owner_present; then log_line 'RESTORE_NATIVE=FAIL unknown owner without module holder'; return 30; fi
    if [ "$(get_per_mgr_state)" != running ]; then record_write 'CTL_START vendor.per_mgr'; setprop ctl.start vendor.per_mgr; RC=$?; if [ "$RC" -ne 0 ]; then return 60; fi; fi
    I=0; while [ "$I" -lt 20 ]; do if verify_native_fingerprint; then ENVIRONMENT_TOUCHED=0; log_line 'RESTORE_NATIVE=PASS path=no_holder_start'; return 0; fi; sleep 1; I=$((I + 1)); done
    record_write 'CTL_RESTART vendor.per_mgr'; setprop ctl.restart vendor.per_mgr; RC=$?; if [ "$RC" -ne 0 ]; then return 60; fi
    I=0; while [ "$I" -lt 20 ]; do if verify_native_fingerprint; then ENVIRONMENT_TOUCHED=0; log_line 'RESTORE_NATIVE=PASS path=no_holder_restart'; return 0; fi; sleep 1; I=$((I + 1)); done
    log_line 'RESTORE_NATIVE=FAIL no-holder native takeover failed'; return 70
  fi
  if ! holder_process_identity_ok "$HPID"; then log_line 'RESTORE_NATIVE=FAIL holder identity gate'; return 30; fi
  if unknown_owner_present; then log_line 'RESTORE_NATIVE=FAIL unknown owner'; return 30; fi
  if [ "$(get_per_mgr_state)" != running ]; then record_write 'CTL_START vendor.per_mgr'; setprop ctl.start vendor.per_mgr; RC=$?; if [ "$RC" -ne 0 ]; then return 60; fi; fi
  wait_native_dual_owner "$HPID" 20; RC=$?
  if [ "$RC" -ne 0 ]; then
    record_write 'CTL_RESTART vendor.per_mgr'; setprop ctl.restart vendor.per_mgr; RC=$?; if [ "$RC" -ne 0 ]; then return 60; fi
    sleep 2; wait_native_dual_owner "$HPID" 20; RC=$?
    if [ "$RC" -ne 0 ]; then log_line 'RESTORE_NATIVE=FAIL native dual-owner takeover not reached; holder preserved'; return 70; fi
  fi
  PM_PID=$(get_per_mgr_pid); log_line "NATIVE_TAKEOVER=PASS pmPid=$PM_PID holderPid=$HPID"
  stop_exact_holder "$HPID" native_pm_service_takeover; RC=$?
  if [ "$RC" -ne 0 ]; then return "$RC"; fi
  HOLDER_PID_CREATED=; sleep 3
  if ! verify_native_fingerprint; then return 70; fi
  ENVIRONMENT_TOUCHED=0; log_line 'RESTORE_NATIVE=PASS path=dual_owner'; return 0
}

normalize_a0_native() {
  if verify_native_fingerprint; then ENVIRONMENT_TOUCHED=0; return 0; fi
  restore_native; RC=$?
  if [ "$RC" -eq 0 ]; then return 0; fi
  if [ "$(get_airplane)" != 0 ]; then return 30; fi
  HPID=$(saved_holder_pid 2>/dev/null || true)
  if [ -z "$HPID" ]; then return 30; fi
  log_line 'A0_NORMALIZATION=qcrild2_reacquire_candidate'
  qcrild2_reacquire "$HPID"; RC=$?
  if [ "$RC" -ne 0 ]; then return "$RC"; fi
  sleep 3
  if ! verify_native_fingerprint; then return 30; fi
  ENVIRONMENT_TOUCHED=0; log_line 'A0_NORMALIZATION=PASS path=qcrild2_reacquire'; return 0
}

prepare_a0() {
  log_line 'A0_PREP=START'
  log_line 'A0_STEP=AIRPLANE_OFF'
  set_airplane 0; RC=$?; if [ "$RC" -ne 0 ]; then return "$RC"; fi
  log_line 'A0_STEP=WIFI'
  ensure_wifi_on; RC=$?; if [ "$RC" -ne 0 ]; then return "$RC"; fi
  log_line 'A0_STEP=SETTLE'
  log_line 'A_SETTLE=20s'; sleep 20
  log_line 'A0_STEP=NETWORK'
  network_preflight 20; RC=$?; if [ "$RC" -ne 0 ]; then log_line 'NETWORK_PREFLIGHT=FAIL in A0 Wi-Fi not ready'; return 30; fi
  log_line 'A0_STEP=TARGET'
  target_gate; RC=$?; if [ "$RC" -ne 0 ]; then return 30; fi
  log_line 'A0_STEP=NATIVE_FINGERPRINT'
  if ! verify_native_fingerprint; then
    log_line 'A0_STEP=NATIVE_NORMALIZATION'
    normalize_a0_native; RC=$?; if [ "$RC" -ne 0 ]; then return "$RC"; fi
  fi
  log_line 'A0_STEP=FINAL_VERIFY'
  if ! verify_native_fingerprint || [ "$(get_airplane)" != 0 ]; then return 30; fi
  log_line 'A0_READY=YES'; return 0
}

prepare_p() {
  log_line 'P_PREP=START'
  set_airplane 1; RC=$?; if [ "$RC" -ne 0 ]; then return "$RC"; fi
  ensure_wifi_on; RC=$?; if [ "$RC" -ne 0 ]; then return "$RC"; fi
  log_line 'P_SETTLE=20s'; sleep 20
  network_preflight 20; RC=$?; if [ "$RC" -ne 0 ]; then log_line 'NETWORK_PREFLIGHT=FAIL in P Wi-Fi not ready'; return 30; fi
  if test_wfc_healthy; then log_line 'P_PREP=ALREADY_HEALTHY'; return 10; fi
  probe_refresh; RC=$?; if [ "$RC" -ne 0 ]; then return 40; fi
  log_line "P_CNE registered=$QTI_REGISTERED active=$QTI_ACTIVE request=$QTI_REQUEST_ID satisfied=$QTI_SATISFIED_ID"
  if [ "$QTI_REQUEST_ID" != null ]; then log_line "P_CNE_GATE=BLOCK_EXISTING_REQUEST request=$QTI_REQUEST_ID"; return 30; fi
  log_line 'P_CNE_GATE=PASS request=null'; return 0
}
