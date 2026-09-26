#!/system/bin/sh

MODDIR=${0%/*}
LOG=/data/adb/voxi-wfc-golden/uninstall.log
umask 077

if [ -x "$MODDIR/bin/goldenctl.sh" ] && [ -r /data/adb/voxi-wfc-golden/state/x55_holder.pid ]; then
  {
    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] uninstall restore-native requested"
    "$MODDIR/bin/goldenctl.sh" restore-native
    RC=$?
    echo "RESTORE_NATIVE_EXIT=$RC"
    if [ "$RC" -ne 0 ]; then
      echo 'WARNING: native takeover was not verified; module holder was not force-killed. Reboot restores the native startup chain.'
    fi
  } >> "$LOG" 2>&1
fi

exit 0
