#!/system/bin/sh

set +e
set +u
set +x

# RC1 is observation-only. Do not recover, normalize, remove stale pidfiles,
# or alter telephony/modem state during boot.
exit 0
