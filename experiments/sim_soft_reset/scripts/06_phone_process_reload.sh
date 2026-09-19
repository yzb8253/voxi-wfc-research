#!/usr/bin/env sh
. "$(dirname "$0")/../lib/common.sh"

blocked_experiment L4-01 "com.android.phone process reload" \
  "Two live com.android.phone processes are present. Package/process ownership and the minimal independently restartable target must be resolved before signaling either PID."

