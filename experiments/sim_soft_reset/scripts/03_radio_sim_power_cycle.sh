#!/usr/bin/env sh
. "$(dirname "$0")/../lib/common.sh"

blocked_experiment L2-01 "Slot1 standard Radio SIM power-down/up" \
  "Preferred candidate, but execution remains blocked until a fixed-target helper proves slot 1 mapping, exact power constants, result callback and guaranteed power-up rollback."

