#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Start Timer
# @raycast.mode silent

# Optional parameters:
# @raycast.icon ⏱
# @raycast.packageName tmr
# @raycast.argument1 { "type": "text", "placeholder": "5m" }
# @raycast.argument2 { "type": "text", "placeholder": "name", "optional": true }

# Documentation:
# @raycast.description Start a countdown in a floating window, with a sound at the end.

set -euo pipefail

DURATION="$1"
NAME="${2:-}"

# Raycast runs script commands with a minimal PATH, so the binary is located
# explicitly rather than relied on being on it.
TMR=""
for candidate in /usr/local/bin/tmr /opt/homebrew/bin/tmr "$HOME/.local/bin/tmr"; do
  if [ -x "$candidate" ]; then
    TMR="$candidate"
    break
  fi
done

if [ -z "$TMR" ]; then
  echo "tmr not found in /usr/local/bin, /opt/homebrew/bin or ~/.local/bin"
  exit 1
fi

args=(-u -t "$DURATION")
if [ -n "$NAME" ]; then
  args+=(-n "$NAME")
fi

# Detached, so Raycast does not sit waiting for the countdown to finish.
nohup "$TMR" "${args[@]}" >/dev/null 2>&1 &
disown

if [ -n "$NAME" ]; then
  echo "$NAME: $DURATION"
else
  echo "timer: $DURATION"
fi
