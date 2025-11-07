#!/usr/bin/env bash
set -euo pipefail

########################################
# CONFIG
########################################

PLASTICITY_TITLE_SUBSTR="Plasticity"
DELAY_TINY=0.05
DELAY_SMALL=0.10

# Shared base resolution: used for BOTH Xephyr and Xvfb
BASE_RES="${BASE_RES:-1920x1080}"

# Xephyr nested visible display (for calibration)
NESTED_DISPLAY="${NESTED_DISPLAY:-:1}"
XE_SCREEN_SIZE="$BASE_RES"

# Xvfb headless display (for generation)
HEADLESS_DISPLAY="${HEADLESS_DISPLAY:-:2}"
XVFB_RES="${XVFB_RES:-${BASE_RES}x24}"

# Your generation script (runs in headless mode after calibration)
GEN_SCRIPT="${GEN_SCRIPT:-./batch_generate.sh}"

# Plasticity binary
PLASTICITY_BIN="${PLASTICITY_BIN:-plasticity}"

# Optional: enable VNC debug view into the Xvfb display (:2)
# Set ENABLE_VNC_DEBUG=1 in the environment to turn this on.
ENABLE_VNC_DEBUG="${ENABLE_VNC_DEBUG:-0}"

########################################
# DEP CHECKS
########################################

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1" >&2
    exit 1
  }
}

need_cmd xdotool
need_cmd Xvfb
need_cmd Xephyr
need_cmd "$PLASTICITY_BIN"

HAVE_ZENITY=0
if command -v zenity >/dev/null 2>&1; then
  HAVE_ZENITY=1
fi

# Only require x11vnc if debug VNC is enabled
if [ "$ENABLE_VNC_DEBUG" -eq 1 ]; then
  need_cmd x11vnc
fi

########################################
# GLOBALS
########################################

PLASTICITY_WIN_ID=""
MOVE_X_X=0
MOVE_X_Y=0
OFFSET_X_X=0
OFFSET_X_Y=0

ORIGIN_X=0
ORIGIN_Y=0

# PID of the "step" zenity info dialog (for MOVE/OFFSET prompts)
ZENITY_STEP_PID=""

########################################
# UTILS: WINDOW / INPUT (operate on current $DISPLAY)
########################################

init_origin_from_window_center() {
  # Requires PLASTICITY_WIN_ID to be set
  eval "$(xdotool getwindowgeometry --shell "$PLASTICITY_WIN_ID")"
  ORIGIN_X=$((X + WIDTH / 2))
  ORIGIN_Y=$((Y + HEIGHT / 2))
  echo "Computed origin from window center: ORIGIN_X=$ORIGIN_X ORIGIN_Y=$ORIGIN_Y"
}

scroll_at_origin() {
  local cx="$1"
  local cy="$2"
  local direction="$3"   # up, down, left, right
  local amount="${4:-5}"
  local button

  case "$direction" in
    up) button=4 ;;
    down) button=5 ;;
    left) button=6 ;;
    right) button=7 ;;
    *) echo "Invalid direction: $direction" >&2; return 1 ;;
  esac

  for ((i = 0; i < amount; i++)); do
    xdotool mousemove --window "$PLASTICITY_WIN_ID" "$cx" "$cy"
    xdotool click "$button"
    xdotool mousemove --window "$PLASTICITY_WIN_ID" "$cx" "$cy"
    sleep 0.02
  done
}

find_plasticity_window() {
  # Use a configurable title substring
  local pattern="$PLASTICITY_TITLE_SUBSTR"
  local id=""

  echo "Looking for window with title containing: $pattern (DISPLAY=$DISPLAY)"

  for i in {1..50}; do
    id=$(xdotool search --onlyvisible --name "$pattern" 2>/dev/null | head -n1 || true)
    if [ -n "$id" ]; then
      break
    fi
    sleep 0.2
  done

  if [ -z "$id" ]; then
    echo "Could not find a Plasticity window matching '$pattern' on DISPLAY=$DISPLAY." >&2
    echo "Debug: Here are some visible window titles on this DISPLAY:" >&2
    xdotool search --name . 2>/dev/null | while read -r wid; do
      xdotool getwindowname "$wid" 2>/dev/null || true
    done >&2
    exit 1
  fi

  echo "Found Plasticity window ID: $id"
  PLASTICITY_WIN_ID="$id"
}

focus_plasticity() {
  xdotool windowraise "$PLASTICITY_WIN_ID" 2>/dev/null || true
  xdotool windowfocus "$PLASTICITY_WIN_ID" 2>/dev/null || true
  sleep "$DELAY_TINY"
}

send_keys() {
  xdotool key --window "$PLASTICITY_WIN_ID" "$@"
}

send_text() {
  xdotool type --window "$PLASTICITY_WIN_ID" -- "$@"
}

# Window-relative center (for scrolling)
get_window_center() {
  eval "$(xdotool getwindowgeometry --shell "$PLASTICITY_WIN_ID")"
  local cx=$((WIDTH / 2))
  local cy=$((HEIGHT / 2))
  echo "$cx $cy"
}

# Screen-relative center (for circle drawing + nudge)
get_window_center_screen() {
  eval "$(xdotool getwindowgeometry --shell "$PLASTICITY_WIN_ID")"
  local cx=$((X + WIDTH / 2))
  local cy=$((Y + HEIGHT / 2))
  echo "$cx $cy"
}

show_initial_zenity() {
  local title="Hexmat Calibration"
  local text="Please create a NEW empty document in Plasticity (Ctrl + N), then click OK."

  local POS_X=200
  local POS_Y=100

  zenity --info \
    --title="$title" \
    --text="$text" &
  local zenity_pid=$!

  sleep 0.3

  local win_id
  win_id=$(xdotool search --sync --pid "$zenity_pid" --name "$title" | head -n1 || true)
  if [ -n "$win_id" ]; then
    xdotool windowmove  "$win_id" "$POS_X" "$POS_Y" 2>/dev/null || true
    xdotool windowraise "$win_id"                      2>/dev/null || true
    xdotool windowfocus "$win_id"                      2>/dev/null || true
  else
    echo "Warning: could not locate zenity window for positioning." >&2
  fi

  wait "$zenity_pid" || true
}

########################################
# STEP 1: NORMALIZE VIEWPORT + CIRCLE
########################################

normalize_viewport() {
  send_keys a
  sleep "$DELAY_SMALL"
  send_keys Delete
  sleep "$DELAY_SMALL"
  send_keys ctrl+b
  sleep "$DELAY_SMALL"
  send_keys ctrl+shift+b
  sleep "$DELAY_SMALL"
  send_keys KP_1
  sleep "$DELAY_SMALL"
  send_keys slash
  sleep "$DELAY_SMALL"

  read CX CY < <(get_window_center)
  scroll_at_origin "$CX" "$CY" down 20
  sleep "$DELAY_SMALL"
}

draw_center_circle() {
  local CX="$ORIGIN_X"
  local CY="$ORIGIN_Y"

  # Clear any stray tool state
  send_keys Escape
  sleep "$DELAY_TINY"

  # Start circle tool (Shift+C)
  send_keys shift+c
  sleep "$DELAY_SMALL"

  # Move to visual center of viewport
  xdotool mousemove "$CX" "$CY"
  sleep "$DELAY_TINY"

  # Click at center
  xdotool mousedown 1
  sleep "$DELAY_TINY"
  xdotool mouseup 1
  sleep "$DELAY_TINY"

  # Nudge away to define a radius
  local NUDGE=40
  xdotool mousemove "$((CX + NUDGE))" "$((CY + NUDGE))"
  sleep "$DELAY_SMALL"

  # Tab to numeric radius input
  send_keys Tab
  sleep "$DELAY_TINY"

  send_text "50"
  sleep "$DELAY_TINY"

  send_keys Return
  sleep "$DELAY_SMALL"
}

########################################
# STEP 2: CAPTURE MOVE / OFFSET INPUT POSITIONS
########################################

prompt_msg() {
  local msg="$1"
  echo
  echo "$msg"
  echo "Then click once on that input field in Plasticity."

  if [ "$HAVE_ZENITY" -eq 1 ]; then
    # Non-blocking info box. User does NOT need to press OK.
    # It will be closed automatically after we capture the position.
    zenity --info \
      --no-wrap \
      --title="Hexmat Calibration" \
      --text="$msg\n\nThen click once on that input field in Plasticity.\nThis dialog will close automatically when you click." \
      >/dev/null 2>&1 &
    ZENITY_STEP_PID=$!
    sleep 0.3   # give zenity a moment to appear
  fi
}

# Wait for a click (via xdotool selectwindow), capture mouse position, then
# close any step-zenity dialog.
capture_position() {
  echo "Click once on the target input field in Plasticity..." >&2
  echo "(Your cursor will change to a crosshair until you click.)" >&2

  # Wait for the user to click ANY window on this DISPLAY.
  # We assume they follow instructions and click the correct input field.
  xdotool selectwindow >/dev/null 2>&1

  # After the click, grab the mouse coordinates at that point.
  eval "$(xdotool getmouselocation --shell)"
  echo "$X $Y"

  # Close the step zenity dialog if it's still running
  if [ -n "${ZENITY_STEP_PID:-}" ]; then
    kill "$ZENITY_STEP_PID" 2>/dev/null || true
    unset ZENITY_STEP_PID
  fi

  return 0
}

calibrate_move_and_offset() {

  # --- MOVE dialog: a then g ---
  send_keys a
  sleep "$DELAY_SMALL"

  send_keys g
  sleep "$DELAY_SMALL"

  prompt_msg "Move the cursor to the X-coordinate input (leftmost field in the MOVE dialog)."

  read MOVE_X_X MOVE_X_Y < <(capture_position)
  echo "Captured MOVE X input at: $MOVE_X_X,$MOVE_X_Y"

  send_keys Escape
  sleep "$DELAY_TINY"
  send_keys Escape
  sleep "$DELAY_SMALL"

  # --- OFFSET dialog: a then o ---
  send_keys a
  sleep "$DELAY_SMALL"

  send_keys o
  sleep "$DELAY_SMALL"

  prompt_msg "Move the cursor to the OFFSET coordinate input (the field you want to use)."

  read OFFSET_X_X OFFSET_X_Y < <(capture_position)
  echo "Captured OFFSET input at: $OFFSET_X_X,$OFFSET_X_Y"

  send_keys Escape
  sleep "$DELAY_TINY"
  send_keys Escape
  sleep "$DELAY_SMALL"
}

########################################
# STEP 4: ASK TO START XVFB + GENERATION
########################################

ask_start_headless() {
  local resp=0
  if [ "$HAVE_ZENITY" -eq 1 ]; then
    zenity --question \
      --title="Hexmat" \
      --text="Calibration is complete.\n\nStart headless profile generation now (Xvfb + Plasticity + $GEN_SCRIPT)?"
    resp=$?
  else
    echo
    echo "Calibration complete. Start headless profile generation now? [y/N]"
    read -r ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] && resp=0 || resp=1
  fi
  return "$resp"
}

run_headless_generation() {
  echo "Starting Xvfb on $HEADLESS_DISPLAY with res $XVFB_RES..."

  # Start Xvfb
  Xvfb "$HEADLESS_DISPLAY" -screen 0 "$XVFB_RES" &
  local xvfb_pid=$!
  for i in {1..10}; do
    if xdpyinfo -display "$HEADLESS_DISPLAY" >/dev/null 2>&1; then
      echo "Xvfb is ready (after ${i}s)"
      break
    fi
    sleep 1
  done

  # Optional VNC debug: mirror the Xvfb display with x11vnc
  local vnc_pid=""
  if [ "$ENABLE_VNC_DEBUG" -eq 1 ]; then
    echo "ENABLE_VNC_DEBUG=1 – starting x11vnc on DISPLAY=$HEADLESS_DISPLAY (localhost only)..."
    DISPLAY="$HEADLESS_DISPLAY" x11vnc \
      -display "$HEADLESS_DISPLAY" \
      -localhost \
      -nopw \
      -forever \
      -shared \
      >/dev/null 2>&1 &
    vnc_pid=$!
    echo "x11vnc started (PID=$vnc_pid). Connect with a VNC client to localhost:0 (or :5900)."
    sleep 1
  fi

  DISPLAY="$HEADLESS_DISPLAY" setxkbmap us

  echo "Starting Plasticity in Xvfb..."
  DISPLAY="$HEADLESS_DISPLAY" "$PLASTICITY_BIN" &
  local plast_pid=$!
  sleep 3

  echo "Running generation script: $GEN_SCRIPT on DISPLAY=$HEADLESS_DISPLAY"
  echo "Passing calibration env:"
  echo "  ORIGIN_X=$ORIGIN_X ORIGIN_Y=$ORIGIN_Y"
  echo "  MOVE_UI_X=$MOVE_X_X MOVE_UI_Y=$MOVE_X_Y"
  echo "  OFFSET_UI_X=$OFFSET_X_X OFFSET_UI_Y=$OFFSET_X_Y"

  DISPLAY="$HEADLESS_DISPLAY" \
    ORIGIN_X="$ORIGIN_X" \
    ORIGIN_Y="$ORIGIN_Y" \
    MOVE_UI_X="$MOVE_X_X" \
    MOVE_UI_Y="$MOVE_X_Y" \
    OFFSET_UI_X="$OFFSET_X_X" \
    OFFSET_UI_Y="$OFFSET_X_Y" \
    "$GEN_SCRIPT" || echo "Generation script exited with non-zero status."

  echo "Stopping Plasticity and Xvfb..."
  kill "$plast_pid" 2>/dev/null || true

  if [ -n "$vnc_pid" ]; then
    echo "Stopping x11vnc (PID=$vnc_pid)..."
    kill "$vnc_pid" 2>/dev/null || true
  fi

  kill "$xvfb_pid" 2>/dev/null || true

  echo "Headless generation done."
}

warn_user_before_calibration() {
  if [ "$HAVE_ZENITY" -eq 1 ]; then
    zenity --question \
      --title="Hexmat Calibration" \
      --text=$'This calibration will draw geometry and change the active Plasticity document.\n\n\
It is intended to run on a NEW, empty document.\n\n\
Have you saved any important work and created a new empty document in Plasticity?'
    if [ $? -ne 0 ]; then
      echo "User cancelled calibration."
      return 1
    fi
  else
    echo
    echo "WARNING: This calibration will draw geometry and modify the current Plasticity document."
    echo "It is intended to run on a NEW, empty document."
    echo
    read -r -p "Have you saved your work and created a new empty document? [y/N] " ans
    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
      echo "User cancelled calibration."
      return 1
    fi
  fi
  return 0
}

########################################
# CALIBRATION MAIN (runs inside Xephyr, on $DISPLAY=NESTED_DISPLAY)
########################################

calibration_main() {
  echo "Hexmat / Plasticity interactive calibration"
  echo "DISPLAY: ${DISPLAY:-unset}"
  echo

  find_plasticity_window
  echo "Using Plasticity window ID: $PLASTICITY_WIN_ID"
  focus_plasticity

  init_origin_from_window_center
  
  if ! warn_user_before_calibration; then
    echo "Calibration cancelled by user."
    return 1
  fi

  normalize_viewport
  draw_center_circle

  calibrate_move_and_offset

  send_keys a
  sleep "$DELAY_SMALL"
  send_keys Delete
  sleep "$DELAY_SMALL"

  echo
  echo "Calibration complete (session-only; not saved to disk)."
  echo "  MOVE X input at:   $MOVE_X_X,$MOVE_X_Y"
  echo "  OFFSET input at:   $OFFSET_X_X,$OFFSET_X_Y"

  if ask_start_headless; then
    return 0
  else
    echo "Headless generation skipped at user request."
    return 1
  fi
}

########################################
# TOP-LEVEL: START XEPHYR, CALIBRATE, THEN OPTIONAL XVFB
########################################
main() {
  echo "Starting Xephyr calibration environment..."
  echo "  Xephyr DISPLAY: $NESTED_DISPLAY"
  echo "  Resolution:      $XE_SCREEN_SIZE"
  echo "  Headless Xvfb:   $HEADLESS_DISPLAY ($XVFB_RES)"
  if [ "$ENABLE_VNC_DEBUG" -eq 1 ]; then
    echo "  VNC debug:       ENABLED (x11vnc on $HEADLESS_DISPLAY)"
  else
    echo "  VNC debug:       disabled (set ENABLE_VNC_DEBUG=1 to enable)"
  fi
  echo

  Xephyr "$NESTED_DISPLAY" -screen "$XE_SCREEN_SIZE" &
  local xephyr_pid=$!
  sleep 1

  DISPLAY="$NESTED_DISPLAY" setxkbmap us

  echo "Starting Plasticity inside Xephyr..."
  DISPLAY="$NESTED_DISPLAY" "$PLASTICITY_BIN" &
  local plast_nested_pid=$!
  sleep 3

  echo "Running calibration inside Xephyr..."
  if DISPLAY="$NESTED_DISPLAY" calibration_main; then
    echo "Calibration OK; user chose to start headless generation."
    echo "Cleaning up Xephyr + nested Plasticity..."
    kill "$plast_nested_pid" 2>/dev/null || true
    kill "$xephyr_pid" 2>/dev/null || true

    echo "Starting headless generation on Xvfb..."
    run_headless_generation "$@"
  else
    echo "Calibration finished without starting headless generation."
    echo "Cleaning up Xephyr + nested Plasticity..."
    kill "$plast_nested_pid" 2>/dev/null || true
    kill "$xephyr_pid" 2>/dev/null || true
  fi

  echo "All done."
}
main "$@"
