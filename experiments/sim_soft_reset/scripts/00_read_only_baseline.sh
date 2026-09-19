#!/usr/bin/env sh
. "$(dirname "$0")/../lib/common.sh"

baseline_action() { :; }
LAB_EXECUTE=YES OBSERVE_SECONDS=${BASELINE_OBSERVE_SECONDS:-5} run_experiment L0-00 "Read-only preserved-state baseline" baseline_action
