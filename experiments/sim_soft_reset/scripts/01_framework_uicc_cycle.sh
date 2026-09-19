#!/usr/bin/env sh
. "$(dirname "$0")/../lib/common.sh"

uicc_cycle() {
  root_shell "CLASSPATH=$REMOVE_JAR app_process /system/bin Slot1UiccDisableHelper dry-run" || return 30
  root_shell "CLASSPATH=$REMOVE_JAR app_process /system/bin Slot1UiccDisableHelper disable" || return 31
  REACHED=NO
  COUNT=0
  while [ "$COUNT" -lt 30 ]; do
    sleep 1; COUNT=$((COUNT + 1)); JSON=$(probe_json)
    if printf '%s' "$JSON" | grep -q '"failureClass":"F8"' && \
       printf '%s' "$JSON" | grep -Eq '"active":false|"areUiccApplicationsEnabled":false'; then REACHED=YES; break; fi
  done
  [ "$REACHED" = YES ] || { echo "Persistent F8 not reached; insert blocked"; return 32; }
  root_shell "CLASSPATH=$RECOVERY_JAR app_process /system/bin Slot1UiccRecoverHelper dry-run" || return 33
  root_shell "CLASSPATH=$RECOVERY_JAR app_process /system/bin Slot1UiccRecoverHelper recover"
}

run_experiment L1-01 "Framework UICC applications disable/F8/enable cycle" uicc_cycle

