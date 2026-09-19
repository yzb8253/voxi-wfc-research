#!/usr/bin/env sh
. "$(dirname "$0")/../lib/common.sh"

blocked_experiment L1-02 "TelephonyManager.refreshUiccProfile" \
  "Current-ROM API existence is proven, but its receiving phone/subscription scope and Binder invocation path are not yet proven."

