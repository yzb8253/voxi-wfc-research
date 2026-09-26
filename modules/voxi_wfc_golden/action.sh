#!/system/bin/sh

SHELL_FLAGS_INITIAL=$-
set +e
set +u
set +x
SHELL_FLAGS_EFFECTIVE=$-
MODDIR=${0%/*}
echo "SHELL_PID=$$"
echo "SHELL_EXE=$(readlink /proc/$$/exe 2>/dev/null)"
echo "SHELL_FLAGS_INITIAL=$SHELL_FLAGS_INITIAL"
echo "SHELL_FLAGS_EFFECTIVE=$SHELL_FLAGS_EFFECTIVE"
"$MODDIR/bin/goldenctl.sh" self-test
RC=$?
case "$RC" in
  0|10|20|30|40|50|60|70|90) ;;
  *) RC=40 ;;
esac
echo
echo "ACTION_EXIT_RC=$RC"
exit "$RC"
