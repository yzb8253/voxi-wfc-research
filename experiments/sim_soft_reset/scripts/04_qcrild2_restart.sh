#!/usr/bin/env sh
. "$(dirname "$0")/../lib/common.sh"

qcrild2_restart() {
  [ "${ALLOW_KNOWN_FAILED:-NO}" = YES ] || { echo "Set ALLOW_KNOWN_FAILED=YES; previous M2 failed"; return 77; }
  PID=$(root_shell 'getprop init.svc_debug_pid.vendor.qcrild2' | tr -d '\r')
  case "$PID" in ''|*[!0-9]*) echo "No exact qcrild2 PID"; return 30 ;; esac
  CMD=$(root_shell "tr '\\000' ' ' < /proc/$PID/cmdline" | tr -d '\r')
  [ "$CMD" = '/vendor/bin/hw/qcrild -c 2 ' ] || [ "$CMD" = '/vendor/bin/hw/qcrild -c 2' ] \
    || { echo "qcrild2 cmdline mismatch: $CMD"; return 31; }
  root_shell "kill -TERM $PID"
}

run_experiment L2-02 "Exact target qcrild2 TERM and init restart" qcrild2_restart

