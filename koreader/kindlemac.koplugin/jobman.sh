#!/bin/sh
# Runs Jobman in the foreground (KOReader waits, with its input closed).
# Pressing the power button also closes it, as jobman.sh does.
J=/mnt/us/jobman/jobman
[ -x "$J" ] || exit 2
"$J" < /dev/null > /mnt/us/jobman/jobman.log 2>&1 &
JP=$!
lipc-wait-event com.lab126.powerd goingToScreenSaver,usbConfigured > /dev/null 2>&1 &
LW=$!
while kill -0 $JP 2>/dev/null; do
    kill -0 $LW 2>/dev/null || { kill $JP 2>/dev/null; break; }
    usleep 300000
done
kill $LW 2>/dev/null
wait $JP 2>/dev/null
exit 0
