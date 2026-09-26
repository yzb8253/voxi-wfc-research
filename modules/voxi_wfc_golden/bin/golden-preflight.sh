#!/system/bin/sh

# Sourced by golden-runner.sh. Implements the dfd8241 native normalization.

qcrild_primary_line() { ps -A -o PID,PPID,NAME,ARGS 2>/dev/null | grep -E '^ *[0-9]+ +1 +qcrild +qcrild$' | head -n 1; }
qcrild2_line() { ps -A -o PID,PPID,NAME,ARGS 2>/dev/null | grep -E '^ *[0-9]+ +1 +qcrild +qcrild -c 2$' | head -n 1; }
line_pid() { printf '%s\n' "$1" | awk '{print $1}'; }

wait_native_dual_owner() {
  HPID=$1 MAX=$2 I=0
  while [ "$I" -lt "$MAX" ]; do
    PM_PID=$(get_per_mgr_pid)
    if [ "$(get_per_mgr_state)" = running ] && [ "$(get_per_mgr_exe)" = /vendor/bin/pm-service ] &&
       [ "$(owner_count)" -eq 2 ] && owner_has_pid "$HPID" && owner_has_pid "$PM_PID" &&
       [ "$(get_x55_state)" = ONLINE ]; then
      return 0
    fi
    sleep 1; I=$((I + 1))
  done
  return 1
}

stop_exact_holder() {
  HPID=$1 REASON=$2
  holder_process_identity_ok "$HPID" || { log_line "HOLDER_STOP_BLOCKED identity mismatch pid=$HPID"; return 1; }
  record_write "HOLDER_TERM pid=$HPID reason=$REASON"
  kill -TERM "$HPID" 2>/dev/null || return 1
  I=0
  while [ "$I" -lt 3 ] && [ -d "/proc/$HPID" ]; do sleep 1; I=$((I + 1)); done
  if [ -d "/proc/$HPID" ] && [ "$(readlink "/proc/$HPID/fd/9" 2>/dev/null)" = "$ESOC_DEVICE" ]; then
    record_write "HOLDER_KILL_EXACT pid=$HPID reason=$REASON"
    kill -KILL "$HPID" 2>/dev/null || return 1
  fi
  I=0
  while [ "$I" -lt 5 ] && [ -d "/proc/$HPID" ]; do sleep 1; I=$((I + 1)); done
  [ ! -d "/proc/$HPID" ] || return 1
  SAVED=$(saved_holder_pid 2>/dev/null || true)
  [ "$SAVED" = "$HPID" ] && rm -f "$HOLDER_PIDFILE"
  return 0
}

start_module_holder() {
  [ ! -e "$HOLDER_PIDFILE" ] || return 1
  record_write 'HOLDER_START exact module process'
  nohup /system/bin/sh "$MODDIR/bin/x55-holder.sh" "$HOLDER_PIDFILE" </dev/null >/dev/null 2>&1 &
  I=0
  while [ "$I" -lt 10 ]; do
    HPID=$(saved_holder_pid 2>/dev/null || true)
    if [ -n "$HPID" ] && holder_identity_ok "$HPID"; then
      HOLDER_PID_CREATED=$HPID
      log_line "HOLDER_PID=$HPID"
      return 0
    fi
    sleep 1; I=$((I + 1))
  done
  return 1
}

verify_native_fingerprint() {
  native_clean || return 1
  [ -z "$(saved_holder_pid 2>/dev/null || true)" ] || return 1
  if unknown_owner_present; then return 1; fi
  return 0
}

owner_pre_a0_gate() {
  echo '[3.5/9] 检查 X55 owner / Golden holder'
  log_line 'OWNER_INSPECTION=START'
  collect_owner_entry_status
  print_owner_entry_status

  HPID=$MODULE_HOLDER_PID
  if [ -n "$HPID" ]; then
    if [ "$MODULE_HOLDER_ALIVE" != YES ]; then
      rm -f "$HOLDER_PIDFILE"
      log_line "STALE_PIDFILE_REMOVED=$HPID"
    elif [ "$MODULE_HOLDER_IDENTITY" = EXACT ]; then
      echo '[3.6/9] 恢复上一次 Golden holder 的原生 ownership'
      if ! restore_native; then
        EXIT_REASON=PREVIOUS_HOLDER_RESTORE_FAILED
        log_line 'OWNER_INSPECTION=BLOCK reason=PREVIOUS_HOLDER_RESTORE_FAILED'
        return 30
      fi
    else
      EXIT_REASON=MODULE_HOLDER_IDENTITY_MISMATCH
      log_line "OWNER_INSPECTION=BLOCK reason=MODULE_HOLDER_IDENTITY_MISMATCH pid=$HPID"
      return 30
    fi
  fi

  if unknown_owner_present; then
    collect_owner_entry_status
    print_owner_entry_status
    EXIT_REASON=UNKNOWN_ESOC_OWNER
    log_line 'OWNER_INSPECTION=BLOCK'
    echo 'BLOCK_REASON=UNKNOWN_ESOC_OWNER'
    echo 'No phone write was executed.'
    echo 'A previous PC Golden holder may still be active.'
    echo 'Perform one full reboot before testing the standalone Magisk port.'
    return 30
  fi

  collect_owner_entry_status
  print_owner_entry_status
  log_line 'OWNER_INSPECTION=PASS'
  log_line 'PRE_A0_GATE=PASS'
  return 0
}

qcrild2_reacquire() {
  HPID=$1
  PRIMARY_BEFORE=$(qcrild_primary_line)
  SLOT2_BEFORE=$(qcrild2_line)
  OLD_SLOT2_PID=$(line_pid "$SLOT2_BEFORE")
  PM_PID=$(get_per_mgr_pid)
  ENTRY_CRASH=$(get_crash_count)

  [ "$(get_airplane)" = 0 ] || return 1
  [ "$(get_per_mgr_state)" = running ] || return 1
  [ "$(get_per_mgr_exe)" = /vendor/bin/pm-service ] || return 1
  holder_identity_ok "$HPID" || return 1
  [ "$(get_vendor_x55_state)" = OFFLINE ] || return 1
  [ "$(get_x55_state)" = ONLINE ] || return 1
  case "$ENTRY_CRASH" in ''|*[!0-9]*) return 1;; esac
  [ -n "$PRIMARY_BEFORE" ] && [ -n "$SLOT2_BEFORE" ] || return 1

  stop_exact_holder "$HPID" qcrild2_reacquire || return 1
  I=0; OFFLINE_CRASH=
  while [ "$I" -lt 15 ]; do
    C=$(get_crash_count)
    if [ "$(owner_count)" -eq 0 ] && [ "$(get_vendor_x55_state)" = OFFLINE ] &&
       [ "$(get_x55_state)" = OFFLINE ]; then
      case "$C" in ''|*[!0-9]*) ;; *) [ "$C" -ge "$ENTRY_CRASH" ] && { OFFLINE_CRASH=$C; break; };; esac
    fi
    sleep 1; I=$((I + 1))
  done
  [ -n "$OFFLINE_CRASH" ] || return 1
  [ "$(qcrild_primary_line)" = "$PRIMARY_BEFORE" ] || return 1
  [ "$(line_pid "$(qcrild2_line)")" = "$OLD_SLOT2_PID" ] || return 1

  record_write 'CTL_RESTART vendor.qcrild2'
  setprop ctl.restart vendor.qcrild2 || return 1
  I=0
  while [ "$I" -lt 15 ]; do
    sleep 1
    NEW_SLOT2_PID=$(line_pid "$(qcrild2_line)")
    PM_PID=$(get_per_mgr_pid)
    if [ -n "$NEW_SLOT2_PID" ] && [ "$NEW_SLOT2_PID" != "$OLD_SLOT2_PID" ] &&
       [ "$(owner_count)" -eq 1 ] && owner_has_pid "$PM_PID" &&
       [ "$(get_per_mgr_exe)" = /vendor/bin/pm-service ] &&
       [ "$(get_vendor_x55_state)" = ONLINE ] && [ "$(get_x55_state)" = ONLINE ] &&
       [ "$(get_crash_count)" = "$OFFLINE_CRASH" ]; then
      [ "$(qcrild_primary_line)" = "$PRIMARY_BEFORE" ] || return 1
      log_line "QCRILD2_REACQUIRE=PASS old=$OLD_SLOT2_PID new=$NEW_SLOT2_PID"
      HOLDER_PID_CREATED=
      return 0
    fi
    I=$((I + 1))
  done
  return 1
}

restore_native() {
  if verify_native_fingerprint; then
    ENVIRONMENT_TOUCHED=0
    log_line 'RESTORE_NATIVE=ALREADY_NATIVE'
    return 0
  fi

  HPID=$(saved_holder_pid 2>/dev/null || true)
  if [ -n "$HPID" ] && [ ! -d "/proc/$HPID" ]; then
    rm -f "$HOLDER_PIDFILE"
    log_line "RESTORE_NATIVE removed dead module pidfile pid=$HPID"
    HPID=
  fi
  if [ -z "$HPID" ]; then
    if unknown_owner_present; then log_line 'RESTORE_NATIVE=FAIL unknown owner without module holder'; return 1; fi
    if [ "$(get_per_mgr_state)" != running ]; then
      record_write 'CTL_START vendor.per_mgr'
      setprop ctl.start vendor.per_mgr || return 1
    fi
    I=0
    while [ "$I" -lt 20 ]; do
      if verify_native_fingerprint; then
        ENVIRONMENT_TOUCHED=0
        log_line 'RESTORE_NATIVE=PASS path=no_holder_start'
        return 0
      fi
      sleep 1; I=$((I + 1))
    done
    record_write 'CTL_RESTART vendor.per_mgr'
    setprop ctl.restart vendor.per_mgr || return 1
    I=0
    while [ "$I" -lt 20 ]; do
      if verify_native_fingerprint; then
        ENVIRONMENT_TOUCHED=0
        log_line 'RESTORE_NATIVE=PASS path=no_holder_restart'
        return 0
      fi
      sleep 1; I=$((I + 1))
    done
    log_line 'RESTORE_NATIVE=FAIL no-holder native takeover failed'
    return 1
  fi
  holder_process_identity_ok "$HPID" || { log_line 'RESTORE_NATIVE=FAIL holder identity gate'; return 1; }
  if unknown_owner_present; then log_line 'RESTORE_NATIVE=FAIL unknown owner'; return 1; fi

  STATE=$(get_per_mgr_state)
  if [ "$STATE" != running ]; then
    record_write 'CTL_START vendor.per_mgr'
    setprop ctl.start vendor.per_mgr || return 1
  fi

  if ! wait_native_dual_owner "$HPID" 20; then
    record_write 'CTL_RESTART vendor.per_mgr'
    setprop ctl.restart vendor.per_mgr || return 1
    sleep 2
    wait_native_dual_owner "$HPID" 20 || {
      log_line 'RESTORE_NATIVE=FAIL native dual-owner takeover not reached; holder preserved'
      return 1
    }
  fi

  PM_PID=$(get_per_mgr_pid)
  log_line "NATIVE_TAKEOVER=PASS pmPid=$PM_PID holderPid=$HPID"
  stop_exact_holder "$HPID" native_pm_service_takeover || return 1
  HOLDER_PID_CREATED=
  sleep 3
  verify_native_fingerprint || return 1
  ENVIRONMENT_TOUCHED=0
  log_line 'RESTORE_NATIVE=PASS path=dual_owner'
  return 0
}

normalize_a0_native() {
  if verify_native_fingerprint; then
    ENVIRONMENT_TOUCHED=0
    return 0
  fi
  if restore_native; then return 0; fi

  # This fallback belongs only to the next airplane-OFF A0 preflight, matching
  # repeatability_preflight.ps1 -> normalize_a1_qcrild2_reacquire.ps1.
  [ "$(get_airplane)" = 0 ] || return 1
  HPID=$(saved_holder_pid 2>/dev/null || true)
  [ -n "$HPID" ] || return 1
  log_line 'A0_NORMALIZATION=qcrild2_reacquire_candidate'
  qcrild2_reacquire "$HPID" || return 1
  sleep 3
  verify_native_fingerprint || return 1
  ENVIRONMENT_TOUCHED=0
  log_line 'A0_NORMALIZATION=PASS path=qcrild2_reacquire'
}

prepare_a0() {
  log_line 'A0_PREP=START'
  set_airplane 0 || return 1
  ensure_wifi_on || return 1
  log_line 'A_SETTLE=20s'
  sleep 20
  network_preflight 20 || { log_line 'NETWORK_PREFLIGHT=FAIL in A0 Wi-Fi not ready'; return 1; }
  target_gate || return 1

  if ! verify_native_fingerprint; then normalize_a0_native || return 1; fi
  verify_native_fingerprint || return 1
  [ "$(get_airplane)" = 0 ] || return 1
  log_line 'A0_READY=YES'
}

prepare_p() {
  log_line 'P_PREP=START'
  set_airplane 1 || return 1
  ensure_wifi_on || return 1
  log_line 'P_SETTLE=20s'
  sleep 20
  network_preflight 20 || { log_line 'NETWORK_PREFLIGHT=FAIL in P Wi-Fi not ready'; return 1; }
  if test_wfc_healthy; then
    log_line 'P_PREP=ALREADY_HEALTHY'
    return 2
  fi
  probe_refresh || return 1
  log_line "P_CNE registered=$QTI_REGISTERED active=$QTI_ACTIVE request=$QTI_REQUEST_ID satisfied=$QTI_SATISFIED_ID"
  [ "$QTI_REQUEST_ID" = null ] || { log_line "P_CNE_GATE=BLOCK_EXISTING_REQUEST request=$QTI_REQUEST_ID"; return 1; }
  log_line 'P_CNE_GATE=PASS request=null'
  return 0
}
