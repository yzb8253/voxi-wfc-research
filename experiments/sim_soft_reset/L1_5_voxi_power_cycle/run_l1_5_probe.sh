#!/usr/bin/env sh

# L1.5 is permanently read-only. This script intentionally has no action mode.
set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LAB_ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
. "$LAB_ROOT/lib/common.sh"

[ "$#" -eq 0 ] || die "this probe accepts no arguments"
[ "${LAB_EXECUTE:-NO}" != YES ] || die "L1.5 probe is read-only; LAB_EXECUTE=YES is rejected"

require_device

STAMP=$(date '+%Y%m%d-%H%M%S')
RUN_DIR="$LAB_ROOT/runs/$STAMP-L1_5-interface-probe"
mkdir -p "$RUN_DIR"

run_read_only() {
  NAME=$1
  COMMAND=$2
  {
    echo "command=$COMMAND"
    echo "captured=$(date -Iseconds)"
    echo
    root_shell "$COMMAND"
  } > "$RUN_DIR/$NAME.txt" 2>&1 || true
}

{
  echo "experiment=L1.5 VOXI slot power-cycle interface probe"
  echo "mode=READ_ONLY"
  echo "serial=${SERIAL:-default}"
  echo "started=$(date -Iseconds)"
  echo "target=slot1/phone1/sub11/IRadio-slot2/IUim-Uim1/qcrild2"
  echo "protected=slot0/phone0/sub1/IRadio-slot1/IUim-Uim0/qcrild"
  echo "forbidden=SIM power; UIM reset; qcrild control; raw Binder/HIDL transaction"
} > "$RUN_DIR/metadata.txt"

# State snapshots. Full raw output remains local because it may contain ICCID/IMSI data.
probe_json > "$RUN_DIR/wfc-probe.json" 2>&1 || true
run_read_only dumpsys-isub 'dumpsys isub'
run_read_only dumpsys-phone 'dumpsys phone'
run_read_only dumpsys-telephony-registry 'dumpsys telephony.registry'
run_read_only slot-status 'dumpsys isub | grep -E "SubscriptionInfo|slotIndex|simSlotIndex|mcc|mnc|carrierId|displayName|isEmbedded|uiccApplicationsEnabled"'

# Interface existence/help only. `service call phone` has no CODE, so service(1)
# prints usage and sends no Binder transaction.
run_read_only cmd-phone-help 'cmd phone help'
run_read_only binder-phone-no-transaction 'service call phone'
run_read_only binder-services 'service list | grep -E "phone:|isub:|telephony.registry|radio|uim"'
run_read_only hidl-radio-uim 'lshal 2>/dev/null | grep -E "android.hardware.radio(@1\\.[0-6])?::IRadio/(slot1|slot2)|android.hardware.radio.config(@1\\.[0-3])?::IRadioConfig/default|vendor.qti.hardware.radio.uim@1\\.[0-2]::IUim/Uim[01]"'
run_read_only qcrild-processes 'ps -A -o USER,PID,PPID,LABEL,NAME,ARGS | grep -E "qcrild($| )|qcrild -c 2"'
run_read_only framework-artifacts 'pm path com.android.phone; ls -l /system/framework/framework.jar /system/framework/telephony-common.jar /system/priv-app/TeleService/TeleService.apk; sha256sum /system/framework/framework.jar /system/framework/telephony-common.jar /system/priv-app/TeleService/TeleService.apk'
run_read_only uim-symbols 'for path in /vendor/lib64/vendor.qti.hardware.radio.uim@1.0.so /vendor/lib64/vendor.qti.hardware.radio.uim@1.1.so /vendor/lib64/vendor.qti.hardware.radio.uim@1.2.so; do echo "== $path =="; /debug_ramdisk/.magisk/busybox/busybox strings "$path" 2>/dev/null | grep -oE "_hidl_[A-Za-z0-9_]+" | sort -u; done'

# Existing logs are copied, never cleared. Bound the snapshot so the probe
# cannot be held open by an unusually large log buffer.
run_read_only logcat-full 'logcat -d -v threadtime -t 20000'
grep -Ei 'SIM_STATE_CHANGED|SERVICE_STATE_CHANGED|SubscriptionInfo|UiccController|UiccSlot|RadioConfig|qcril|QMI|UIM|ImsService|IWLAN|ePDG' \
  "$RUN_DIR/logcat-full.txt" > "$RUN_DIR/logcat-telephony-filtered.txt" || true

{
  echo "completed=$(date -Iseconds)"
  echo "device_write_count=0"
  echo "binder_transaction_count=0"
  echo "result=DRY_RUN_COMPLETE"
} >> "$RUN_DIR/metadata.txt"

echo "L1.5 read-only probe complete: $RUN_DIR"
echo "No SIM/UIM/RIL write was executed."
