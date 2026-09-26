#!/system/bin/sh

# Read-only pre-recovery capability gate shared by RC validation and the future
# writable runner. This file contains no recovery effect.

EXPECTED_PROBE_SHA256=AC46E9F62DB88C043DA08E4D5BB1D100EA8AC10EF2A74838F99C2237C2B9A91D
READY_FOR_RECOVERY=NO
READY_FOR_A0=NO
SELFTEST_RESULT=NOT_RUN
CURRENT_STAGE=INIT
EXIT_REASON=NOT_SET

print_write_counters() {
  echo "STATE_WRITE_COUNT=${STATE_WRITE_COUNT:-0}"
  echo "MODEM_WRITE_COUNT=${MODEM_WRITE_COUNT:-0}"
  echo "SIM_WRITE_COUNT=${SIM_WRITE_COUNT:-0}"
  echo "PHONE_WRITE_COUNT=${PHONE_WRITE_COUNT:-0}"
  echo "FILESYSTEM_WRITE_COUNT=${FILESYSTEM_WRITE_COUNT:-0}"
  return 0
}

selftest_finish() {
  FINAL_RC=$1
  FINAL_REASON=$2
  FINAL_KIND=$3
  if [ "$FINAL_RC" -ne 0 ] && { [ -z "$FINAL_REASON" ] || [ "$FINAL_REASON" = NOT_SET ]; }; then
    FINAL_REASON=INTERNAL_UNCLASSIFIED_RC
    FINAL_KIND=ERROR
    FINAL_RC=40
  fi
  EXIT_REASON=$FINAL_REASON
  SELFTEST_RESULT=$FINAL_KIND
  if [ "$FINAL_RC" -eq 0 ]; then
    READY_FOR_RECOVERY=YES
    READY_FOR_A0=YES
    echo 'PRE_A0_GATE=PASS'
  else
    READY_FOR_RECOVERY=NO
    READY_FOR_A0=NO
  fi
  echo "READY_FOR_A0=$READY_FOR_A0"
  echo "READY_FOR_RECOVERY=$READY_FOR_RECOVERY"
  echo "SELFTEST_RESULT=$SELFTEST_RESULT"
  echo "EXIT_RC=$FINAL_RC"
  echo "EXIT_STAGE=$CURRENT_STAGE"
  echo "EXIT_REASON=$EXIT_REASON"
  print_write_counters
  if [ "$FINAL_RC" -eq 0 ]; then
    echo 'FINAL_RESULT=SELFTEST_PASS'
  else
    echo 'FINAL_RESULT=SELFTEST_BLOCKED'
  fi
  return "$FINAL_RC"
}

step_root_gate() {
  if [ "$(id -u)" != 0 ]; then return 40; fi
  return 0
}

step_module_runtime_gate() {
  for RUNTIME_ITEM in \
    module.prop action.sh service.sh uninstall.sh \
    bin/common.sh bin/goldenctl.sh bin/golden-selftest.sh bin/golden-runner.sh \
    bin/golden-preflight.sh bin/x55-holder.sh lib/wfc-probe.jar; do
    if [ ! -r "$MODDIR/$RUNTIME_ITEM" ]; then
      echo "MODULE_RUNTIME_MISSING=$RUNTIME_ITEM"
      return 90
    fi
  done
  PROBE_HASH=$(sha256sum "$PROBE_JAR" 2>/dev/null | awk '{print toupper($1)}')
  if [ "$PROBE_HASH" != "$EXPECTED_PROBE_SHA256" ]; then
    echo "PROBE_HASH=$PROBE_HASH"
    return 90
  fi
  return 0
}

step_probe_gate() {
  run_probe
  RC=$?
  if [ "$RC" -ne 0 ]; then return 40; fi
  load_probe_fields
  RC=$?
  if [ "$RC" -ne 0 ]; then return 40; fi
  return 0
}

step_platform_gate_readonly() {
  collect_platform_status
  RC=$?
  if [ "$RC" -ne 0 ]; then return 40; fi
  echo "DEVICE=${PLATFORM_DEVICE:-UNKNOWN}"
  echo "ANDROID=${PLATFORM_ANDROID:-UNKNOWN}"
  echo "BUILD=${PLATFORM_BUILD:-UNKNOWN}"
  echo "MODEM=${PLATFORM_MODEM:-UNKNOWN}"
  if is_platform_supported; then return 0; fi
  return 30
}

step_target_gate_readonly() {
  echo "VOXI_SLOT=${TARGET_SLOT:-UNKNOWN}"
  echo "VOXI_PHONE=${TARGET_PHONE:-UNKNOWN}"
  echo "VOXI_SUB=${TARGET_SUB:-UNKNOWN}"
  echo "VOXI_CARRIER=${TARGET_CARRIER:-UNKNOWN}"
  echo "MCCMNC=${TARGET_MCC:-}${TARGET_MNC:-}"
  echo "VOXI_ACTIVE=${SUB_ACTIVE:-UNKNOWN}"
  echo "VOXI_UICC_ENABLED=${UICC_ENABLED:-UNKNOWN}"
  if is_target_mapping_valid; then return 0; fi
  return 30
}

step_network_observe_readonly() {
  collect_network_status
  RC=$?
  if [ "$RC" -ne 0 ]; then return 40; fi
  print_network_status
  if is_wifi_ready_now; then
    echo 'WIFI=READY'
  else
    echo 'WIFI=NOT_READY'
    return 30
  fi
  if [ "$VPN_DETECTED" = YES ]; then
    echo 'VPN=DETECTED'
  else
    echo 'VPN=UNVERIFIED'
    echo 'WARNING=Please confirm UK full-tunnel VPN is connected'
  fi
  echo 'NETWORK_PREFLIGHT=PASS'
  return 0
}

step_owner_inspection_readonly() {
  collect_owner_entry_status
  RC=$?
  if [ "$RC" -ne 0 ]; then return 40; fi
  classify_owner_entry_status
  RC=$?
  if [ "$RC" -ne 0 ]; then return 40; fi
  print_owner_entry_status
  RC=$?
  if [ "$RC" -ne 0 ]; then return 40; fi

  case "$ESOC_OWNER_CLASS" in
    NATIVE_PM_SERVICE)
      echo 'OWNER_BRANCH=NATIVE_PM_SERVICE'
      echo 'OWNER_INSPECTION=PASS'
      return 0
      ;;
    MODULE_GOLDEN_HOLDER)
      echo 'OWNER_BRANCH=MODULE_GOLDEN_HOLDER'
      echo 'OWNER_INSPECTION=BLOCK'
      echo 'BLOCK_REASON=EXISTING_MODULE_HOLDER'
      echo 'ACTION_REQUIRED=Full reboot before RC1 validation'
      return 30
      ;;
    UNKNOWN_OWNER)
      echo 'OWNER_BRANCH=UNKNOWN_OWNER'
      echo 'OWNER_INSPECTION=BLOCK'
      echo 'BLOCK_REASON=UNKNOWN_ESOC_OWNER'
      return 30
      ;;
    NO_OWNER)
      echo 'OWNER_BRANCH=NO_OWNER'
      echo 'OWNER_INSPECTION=BLOCK'
      echo 'BLOCK_REASON=NO_ESOC_OWNER'
      return 30
      ;;
    MULTIPLE_OWNERS)
      echo 'OWNER_BRANCH=MULTIPLE_OWNERS'
      echo 'OWNER_INSPECTION=BLOCK'
      echo 'BLOCK_REASON=MULTIPLE_ESOC_OWNERS'
      return 30
      ;;
    *)
      echo "OWNER_BRANCH=${ESOC_OWNER_CLASS:-INVALID}"
      echo 'OWNER_INSPECTION=ERROR'
      echo 'BLOCK_REASON=OWNER_CLASSIFICATION_INVALID'
      return 40
      ;;
  esac
}

step_entry_capability_readonly() {
  case "$ENTRY_AIRPLANE" in
    0)
      echo 'A0_CONSTRUCTION_REQUIRED=NO'
      return 0
      ;;
    1)
      echo 'A0_CONSTRUCTION_REQUIRED=YES'
      return 0
      ;;
    *)
      echo 'A0_CONSTRUCTION_REQUIRED=UNKNOWN'
      return 40
      ;;
  esac
}

run_selftest_step() {
  STEP_NAME=$1
  STEP_FUNCTION=$2
  CURRENT_STAGE=$STEP_NAME
  echo "STEP_BEGIN=$STEP_NAME"
  "$STEP_FUNCTION"
  STEP_RC=$?
  echo "STEP_END=$STEP_NAME RC=$STEP_RC"
  return "$STEP_RC"
}

pre_recovery_self_test() {
  STATE_WRITE_COUNT=0
  MODEM_WRITE_COUNT=0
  SIM_WRITE_COUNT=0
  PHONE_WRITE_COUNT=0
  FILESYSTEM_WRITE_COUNT=0

  echo '================================='
  echo ' VOXI WFC GOLDEN SELF-TEST RC1'
  echo '================================='
  echo "MODULE_VERSION=$MODULE_VERSION"
  ENTRY_AIRPLANE=$(get_airplane)
  echo "ENTRY_AIRPLANE=${ENTRY_AIRPLANE:-UNKNOWN}"

  run_selftest_step ROOT step_root_gate
  RC=$?
  if [ "$RC" -ne 0 ]; then
    selftest_finish 40 ROOT_REQUIRED ERROR
    FINISH_RC=$?
    return "$FINISH_RC"
  fi

  run_selftest_step MODULE_RUNTIME step_module_runtime_gate
  RC=$?
  if [ "$RC" -ne 0 ]; then
    selftest_finish 90 MODULE_RUNTIME_CORRUPT ERROR
    FINISH_RC=$?
    return "$FINISH_RC"
  fi

  run_selftest_step PROBE step_probe_gate
  RC=$?
  if [ "$RC" -ne 0 ]; then
    selftest_finish 40 PROBE_FAILED ERROR
    FINISH_RC=$?
    return "$FINISH_RC"
  fi

  run_selftest_step PLATFORM_GATE step_platform_gate_readonly
  RC=$?
  if [ "$RC" -ne 0 ]; then
    selftest_finish "$RC" PLATFORM_UNSUPPORTED BLOCKED
    FINISH_RC=$?
    return "$FINISH_RC"
  fi

  run_selftest_step TARGET_GATE step_target_gate_readonly
  RC=$?
  if [ "$RC" -ne 0 ]; then
    selftest_finish "$RC" TARGET_MAPPING_INVALID BLOCKED
    FINISH_RC=$?
    return "$FINISH_RC"
  fi

  run_selftest_step NETWORK_OBSERVE step_network_observe_readonly
  RC=$?
  if [ "$RC" -ne 0 ]; then
    selftest_finish "$RC" WIFI_NOT_READY BLOCKED
    FINISH_RC=$?
    return "$FINISH_RC"
  fi

  run_selftest_step OWNER_INSPECTION step_owner_inspection_readonly
  RC=$?
  if [ "$RC" -ne 0 ]; then
    case "$ESOC_OWNER_CLASS" in
      MODULE_GOLDEN_HOLDER) REASON=EXISTING_MODULE_HOLDER ;;
      UNKNOWN_OWNER) REASON=UNKNOWN_ESOC_OWNER ;;
      NO_OWNER) REASON=NO_ESOC_OWNER ;;
      MULTIPLE_OWNERS) REASON=MULTIPLE_ESOC_OWNERS ;;
      *) REASON=OWNER_COLLECTION_FAILED; RC=40 ;;
    esac
    selftest_finish "$RC" "$REASON" BLOCKED
    FINISH_RC=$?
    return "$FINISH_RC"
  fi

  run_selftest_step ENTRY_CAPABILITY step_entry_capability_readonly
  RC=$?
  if [ "$RC" -ne 0 ]; then
    selftest_finish 40 ENTRY_CAPABILITY_INVALID ERROR
    FINISH_RC=$?
    return "$FINISH_RC"
  fi

  selftest_finish 0 SELFTEST_COMPLETE PASS
  FINISH_RC=$?
  return "$FINISH_RC"
}
