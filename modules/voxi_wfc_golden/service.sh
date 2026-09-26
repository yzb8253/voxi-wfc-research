#!/system/bin/sh

# v1.0 intentionally performs no automatic recovery and no telephony/modem write.
MODDIR=${0%/*}
DATA_DIR=/data/adb/voxi-wfc-golden
STATE_DIR="$DATA_DIR/state"
LOG_DIR="$DATA_DIR/logs"
PIDFILE="$STATE_DIR/x55_holder.pid"
LOCKDIR="$STATE_DIR/recovery.lock.d"

umask 077
mkdir -p "$STATE_DIR" "$LOG_DIR"
chmod 0700 "$DATA_DIR" "$STATE_DIR" "$LOG_DIR" 2>/dev/null

# Remove only a confirmed dead module pidfile. Never signal a process here.
if [ -r "$PIDFILE" ]; then
  PID=$(cat "$PIDFILE" 2>/dev/null)
  case "$PID" in
    ''|*[!0-9]*) ;;
    *) [ ! -d "/proc/$PID" ] && rm -f "$PIDFILE" ;;
  esac
fi

# Likewise remove only a lock whose recorded owner is confirmed dead.
if [ -r "$LOCKDIR/pid" ]; then
  LOCKPID=$(cat "$LOCKDIR/pid" 2>/dev/null)
  case "$LOCKPID" in
    ''|*[!0-9]*) ;;
    *)
      if [ ! -d "/proc/$LOCKPID" ]; then
        rm -f "$LOCKDIR/pid"
        rmdir "$LOCKDIR" 2>/dev/null
      fi
      ;;
  esac
fi

exit 0
