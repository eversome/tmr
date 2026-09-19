#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Stop Timers
# @raycast.mode silent

# Optional parameters:
# @raycast.icon ⏹
# @raycast.packageName tmr

# Documentation:
# @raycast.description Stop every running tmr countdown.

set -uo pipefail

count="$(pgrep -x tmr | wc -l | tr -d ' ')"

if [ "$count" = "0" ]; then
  echo "no timers running"
  exit 0
fi

pkill -x tmr || true

if [ "$count" = "1" ]; then
  echo "stopped 1 timer"
else
  echo "stopped $count timers"
fi
