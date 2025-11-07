#!/usr/bin/env bash
set -euo pipefail

DELAY=10
echo "Switch to the window you want to capture (waiting ${DELAY}s)..."
sleep "$DELAY"

# Get the active window ID
active_win=$(xdotool getactivewindow)

# Get the active window title
title=$(xdotool getwindowname "$active_win" 2>/dev/null || echo "(no title)")

# Get mouse position
eval "$(xdotool getmouselocation --shell)"  # defines X, Y, SCREEN, WINDOW

echo "--------------------------------"
echo "Active window title: $title"
echo "Cursor position: X=${X}  Y=${Y}"
echo "--------------------------------"
