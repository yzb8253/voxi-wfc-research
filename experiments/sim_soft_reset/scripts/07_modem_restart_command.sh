#!/usr/bin/env sh
. "$(dirname "$0")/../lib/common.sh"

modem_restart() {
  [ "${ALLOW_MODEM_RESTART:-NO}" = YES ] || { echo "Set ALLOW_MODEM_RESTART=YES after implementation audit"; return 77; }
  root_shell 'cmd phone restart-modem'
}

run_experiment L3-02 "Framework cmd phone restart-modem (both slots)" modem_restart

