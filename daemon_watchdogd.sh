#!/bin/bash
DAEMON_DIR=$(cd $(dirname "$0"); pwd)

log_file="./watchdog.log";
cmd="$DAEMON_DIR/daemon_watchdog.sh > $log_file 2>&1 &"

proc=`ps xaww | grep -v " grep" | grep -- "daemon_watchdog.sh"`
if test -z "$proc"; then
    eval "$cmd"
else
    echo "daemon_watchdog.sh already running"
fi
