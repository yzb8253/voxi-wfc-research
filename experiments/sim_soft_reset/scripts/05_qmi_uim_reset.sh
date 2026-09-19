#!/usr/bin/env sh
. "$(dirname "$0")/../lib/common.sh"

blocked_experiment L3-01 "Direct Qualcomm IUim/Uim1 or QMI UIM reset" \
  "Uim1 is present, but no reset/power method, transaction number, argument semantics and handler-to-QMI call chain have been verified. Raw calls are forbidden."

