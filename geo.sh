#!/usr/bin/env bash
set -euo pipefail

### CONFIG #########################################################

PLASTICITY_TITLE="${PLASTICITY_TITLE:-Untitled - Plasticity}"


# Origin where you start geometry (screen coords)
ORIGIN_X="${ORIGIN_X:-960}"
ORIGIN_Y="${ORIGIN_Y:-544}"

# Move dialog X-field position (screen coords)
MOVE_UI_X="${MOVE_UI_X:-290}"
MOVE_UI_Y="${MOVE_UI_Y:-411}"

# Offset / generic numeric field position (screen coords)
# (Typically your "OFFSET" calibration click)
OFFSET_UI_X="${OFFSET_UI_X:-$MOVE_UI_X}"
OFFSET_UI_Y="${OFFSET_UI_Y:-$MOVE_UI_Y}"

# Tools
LINE_TOOL_KEY="Shift+a"   # line tool
MIRROR_TOOL_KEY="Alt+x"
CORNER_RECTANGLE_KEY="Shift+r"
CIRCLE_KEY="Shift+c"

# Small nudge distance in pixels, to give direction
NUDGE=15

# Delays
DELAY_TINY=0.05
DELAY_SMALL=0.10

####################################################################

press_return() {
  local label="${1:-}"
  if [ -n "$label" ]; then
    echo "DEBUG RETURN: $label (caller=${FUNCNAME[1]})" >&2
  else
    echo "DEBUG RETURN: caller=${FUNCNAME[1]}" >&2
  fi
  xdotool key Return
  sleep "$DELAY_TINY"
}

debug_bytes() {
  local label="$1"
  local val="$2"
  printf 'DEBUG %s: ' "$label" >&2
  printf '%q\n' "$val" >&2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }
}
need_cmd xdotool
need_cmd date   # for timestamps

start_ms=0

now_ms() {
  date +%s%3N
}


focus_plasticity_by_mouse_origin() {
  xdotool mousemove  "$ORIGIN_X" "$ORIGIN_Y"
  sleep "$DELAY_TINY"
}

### SHARED MOVE LOGIC ##############################################

mirror_selection_two_axes() {
  focus_plasticity_by_mouse_origin

  xdotool key a
  sleep "$DELAY_TINY"

  ### First mirror: nudge down from origin ###
  xdotool key --clearmodifiers "$MIRROR_TOOL_KEY"
  sleep "$DELAY_SMALL"

  xdotool mousemove "$ORIGIN_X" "$ORIGIN_Y"
  sleep "$DELAY_TINY"
  xdotool mousemove "$ORIGIN_X" $((ORIGIN_Y + NUDGE + 20))
  sleep "$DELAY_TINY"

  xdotool mousedown 1
  sleep 0.07
  xdotool mouseup 1
  sleep "$DELAY_TINY"
  press_return
  sleep "$DELAY_TINY"

  xdotool key a

  ### Second mirror: nudge left from origin ###
  xdotool key --clearmodifiers "$MIRROR_TOOL_KEY"
  sleep "$DELAY_SMALL"

  xdotool mousemove "$ORIGIN_X" "$ORIGIN_Y"
  sleep "$DELAY_TINY"
  xdotool mousemove $((ORIGIN_X - NUDGE - 20)) "$ORIGIN_Y"
  sleep "$DELAY_TINY"

  xdotool mousedown 1
  sleep 0.07
  xdotool mouseup 1
  sleep "$DELAY_TINY"
  press_return
  sleep "$DELAY_TINY"

}

move_selection_to_xy() {
  local x="$1"
  local y="$2"

  xdotool key g
  sleep "$DELAY_SMALL"

  xdotool mousemove "$MOVE_UI_X" "$MOVE_UI_Y"
  sleep "$DELAY_TINY"

  xdotool mousedown 1
  sleep "$DELAY_TINY"
  xdotool mouseup 1
  sleep "$DELAY_TINY"

  xdotool key Ctrl+a
  sleep "$DELAY_TINY"
  xdotool type --delay 15 "$x"
  sleep "$DELAY_TINY"

  xdotool key Tab
  sleep "$DELAY_TINY"
  xdotool key Tab
  sleep "$DELAY_TINY"

  xdotool key Ctrl+a
  sleep "$DELAY_TINY"
  xdotool type --delay 15 "$y"
  sleep "$DELAY_TINY"

  press_return
  sleep "$DELAY_TINY"
  press_return
  sleep "$DELAY_TINY"
}

### LINE DRAWING ####################################################

draw_line() {
  local orientation="$1"   # "vertical" or "horizontal"
  local length="$2"
  local target_x="$3"
  local target_y="$4"

  start_ms=$(now_ms)
  echo "=== draw_line $orientation len='$length' move_to=($target_x,$target_y) ==="

  focus_plasticity_by_mouse_origin

  xdotool key Escape
  sleep "$DELAY_TINY"

  xdotool key --clearmodifiers "$LINE_TOOL_KEY"
  sleep "$DELAY_SMALL"

  xdotool mousemove "$ORIGIN_X" "$ORIGIN_Y"
  sleep "$DELAY_TINY"

  xdotool mousedown 1
  sleep "$DELAY_TINY"
  xdotool mouseup 1
  sleep "$DELAY_TINY"

  if [ "$orientation" = "vertical" ]; then
    xdotool mousemove "$ORIGIN_X" $((ORIGIN_Y - NUDGE))
  else
    xdotool mousemove $((ORIGIN_X + NUDGE)) "$ORIGIN_Y"
  fi
  sleep "$DELAY_TINY"

  xdotool key Tab
  sleep "$DELAY_TINY"

  xdotool type --delay 15 "$length"
  sleep "$DELAY_TINY"

  press_return
  sleep "$DELAY_TINY"

  move_selection_to_xy "$target_x" "$target_y"
}

### ARC DRAWING #####################################################

draw_center_arc() {
  local quadrant="$1"   # "tr", "tl", "br", "bl"
  local radius="$2"
  local target_x="$3"
  local target_y="$4"

  local cx="$ORIGIN_X"
  local cy="$ORIGIN_Y"

  start_ms=$(now_ms)
  echo "=== draw_center_arc quad=$quadrant r='$radius' move_to=($target_x,$target_y) center=($cx,$cy) ==="

  focus_plasticity_by_mouse_origin

  local side vert
  case "$quadrant" in
    tr|rt) side="right"; vert="top" ;;
    tl|lt) side="left";  vert="top" ;;
    br|rb) side="right"; vert="bottom" ;;
    bl|lb) side="left";  vert="bottom" ;;
    *)
      echo "Unknown quadrant '$quadrant' (use tr, tl, br, bl)" >&2
      return 1
      ;;
  esac

  xdotool key f
  sleep "$DELAY_TINY"
  xdotool type --delay 15 "center point arc"
  sleep "$DELAY_SMALL"
  xdotool key Down 
  sleep "$DELAY_TINY"
  press_return
  sleep "$DELAY_SMALL"

  xdotool mousemove "$cx" "$cy"
  sleep 0.12
  xdotool mousedown 1
  sleep 0.07
  xdotool mouseup 1
  sleep "$DELAY_TINY"

  local hx
  if [ "$side" = "right" ]; then
    hx=$((cx + NUDGE))
  else
    hx=$((cx - NUDGE))
  fi

  xdotool mousemove "$hx" "$cy"
  sleep "$DELAY_TINY"

  xdotool key Tab
  sleep "$DELAY_TINY"
  xdotool type --delay 15 "$radius"
  sleep "$DELAY_TINY"
  press_return
  sleep "$DELAY_TINY"

  local vy
  if [ "$vert" = "top" ]; then
    vy=$((cy - NUDGE))
  else
    vy=$((cy + NUDGE))
  fi

  xdotool mousemove "$hx" "$vy"
  sleep "$DELAY_TINY"

  xdotool mousemove "$cx" "$vy"
  sleep 0.12
  xdotool mousedown 1
  sleep 0.07
  xdotool mouseup 1
  sleep "$DELAY_TINY"

  move_selection_to_xy "$target_x" "$target_y"

}

### RHS BUILDER #####################################################

build_rhs() {
  local h="$1"
  local b="$2"
  local tw="$3"
  local r="$4"

  
  echo "=== build_rhs h=$h b=$b tw=$tw r=$r ==="

  focus_plasticity_by_mouse_origin

  xdotool key Escape
  sleep "$DELAY_TINY"

  xdotool key f
  sleep "$DELAY_TINY"
  xdotool type --delay 15 "center re"
  sleep $DELAY_SMALL
  xdotool key Down 
  sleep "$DELAY_TINY"
  press_return
  sleep "$DELAY_SMALL"

  xdotool mousemove "$ORIGIN_X" "$ORIGIN_Y"
  sleep "$DELAY_TINY"

  xdotool mousedown 1
  sleep "$DELAY_TINY"
  xdotool mouseup 1
  sleep "$DELAY_TINY"

  xdotool mousemove $((ORIGIN_X + NUDGE)) $((ORIGIN_Y + NUDGE))
  sleep "$DELAY_TINY"

  xdotool key c
  sleep "$DELAY_TINY"

  xdotool key Tab
  sleep "$DELAY_TINY"
  xdotool type --delay 15 "$b"
  sleep "$DELAY_TINY"
  xdotool key Tab
  sleep "$DELAY_TINY"
  xdotool type --delay 15 "$h"
  sleep "$DELAY_TINY"
  press_return
  sleep "$DELAY_TINY"

  xdotool key b
  sleep "$DELAY_TINY"

  # Radius field: use OFFSET coordinates
  xdotool mousemove "$OFFSET_UI_X" "$OFFSET_UI_Y"
  sleep "$DELAY_TINY"

  xdotool mousedown 1
  sleep "$DELAY_TINY"
  xdotool mouseup 1
  sleep "$DELAY_TINY"

  xdotool type --delay 15 "$r"
  sleep "$DELAY_TINY"
  press_return
  sleep "$DELAY_TINY"

  xdotool key o
  sleep "$DELAY_TINY"

  # Offset distance: also use OFFSET coordinates
  xdotool mousemove "$OFFSET_UI_X" "$OFFSET_UI_Y"
  sleep "$DELAY_TINY"

  xdotool mousedown 1
  sleep "$DELAY_TINY"
  xdotool mouseup 1
  sleep "$DELAY_TINY"

  xdotool type --delay 15 "-"
  xdotool type --delay 15 "$tw"
  sleep "$DELAY_TINY"
  press_return
  sleep "$DELAY_TINY"

  press_return
  sleep "$DELAY_TINY"
}

build_chs() {
  local d="$1"
  local tw="$2"
  
  echo "=== build_chs d=$d tw=$tw ==="

  focus_plasticity_by_mouse_origin

  xdotool key Escape
  sleep "$DELAY_TINY"

  xdotool key --clearmodifiers "$CIRCLE_KEY"
  sleep "$DELAY_SMALL"

  xdotool mousemove "$ORIGIN_X" "$ORIGIN_Y"
  sleep "$DELAY_TINY"

  xdotool mousedown 1
  sleep "$DELAY_TINY"
  xdotool mouseup 1
  sleep "$DELAY_TINY"

  xdotool mousemove $((ORIGIN_X + NUDGE)) $((ORIGIN_Y + NUDGE))
  sleep "$DELAY_TINY"

  xdotool key Tab
  sleep "$DELAY_TINY"

  xdotool type --delay 15 "$d"
  sleep "$DELAY_TINY"

  press_return
  sleep "$DELAY_TINY"

  xdotool key o
  sleep "$DELAY_TINY"

  # Offset distance: use OFFSET coordinates (from calibration)
  xdotool mousemove "$OFFSET_UI_X" "$OFFSET_UI_Y"
  sleep "$DELAY_TINY"

  xdotool mousedown 1
  sleep "$DELAY_TINY"
  xdotool mouseup 1
  sleep "$DELAY_TINY"

  xdotool type --delay 15 "-"
  xdotool type --delay 15 "$tw"
  sleep "$DELAY_TINY"
  press_return
  sleep "$DELAY_TINY"

  press_return
  sleep "$DELAY_TINY"
}

### HEA BUILDER #####################################################

build_hea() {
  local h="$1"
  local b="$2"
  local tw="$3"
  local tf="$4"
  local r="$5"
  debug_bytes "h" "$h"
  debug_bytes "b" "$b"
  debug_bytes "tw" "$tw"
  debug_bytes "r" "$r"

  echo "=== build_hea h=$h b=$b tw=$tw tf=$tf r=$r ==="

  draw_line "horizontal" "(${b}/2)" "0" "(${h}/2)"
  draw_line "vertical" "${tf}" "(${b}/2)" "(${h}/2)-${tf}"
  draw_line "horizontal" "(${b}/2)-(${tw}/2)-${r}" "(${tw}/2)+${r}" "(${h}/2)-${tf}"
  draw_center_arc "tl" "${r}" "(${tw}/2)+${r}" "(${h}/2)-${tf}-${r}"
  draw_line "vertical" "(${h}/2)-${tf}-${r}" "(${tw}/2)" "0"
  
  mirror_selection_two_axes

  sleep "$DELAY_TINY"

  xdotool key a
  sleep "$DELAY_TINY"

  xdotool key j
  sleep "$DELAY_TINY"

  xdotool key Escape
}

### CLI DISPATCH ###################################################

usage() {
  echo "Usage:" >&2
  echo "  $0 [--origin-x X --origin-y Y --move-x X --move-y Y --offset-x X --offset-y Y] line <vertical|horizontal> <length_expr> <x_expr> <y_expr>" >&2
  echo "  $0 [..coords..] arc  <tr|tl|br|bl> <radius_expr> <x_expr> <y_expr>" >&2
  echo "  $0 [..coords..] hea  <h> <b> <tw> <tf> <r>" >&2
  echo "  $0 [..coords..] rhs  <h> <b> <tw> <r>" >&2
  echo "  $0 [..coords..] chs  <d> <tw>" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --origin-x) ORIGIN_X="$2"; shift 2 ;;
    --origin-y) ORIGIN_Y="$2"; shift 2 ;;
    --move-x)   MOVE_UI_X="$2"; shift 2 ;;
    --move-y)   MOVE_UI_Y="$2"; shift 2 ;;
    --offset-x) OFFSET_UI_X="$2"; shift 2 ;;
    --offset-y) OFFSET_UI_Y="$2"; shift 2 ;;
    --help|-h)
      usage
      exit 0
      ;;
    line|arc|rhs|chs|hea)
      break
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

cmd="${1-}"

case "$cmd" in
  line)
    if [ "$#" -ne 5 ]; then
      echo "Usage: $0 [coords...] line <vertical|horizontal> <length_expr> <x_expr> <y_expr>" >&2
      exit 1
    fi
    draw_line "$2" "$3" "$4" "$5"
    ;;
  arc)
    if [ "$#" -ne 5 ]; then
      echo "Usage: $0 [coords...] arc <tr|tl|br|bl> <radius_expr> <x_expr> <y_expr>" >&2
      exit 1
    fi
    draw_center_arc "$2" "$3" "$4" "$5"
    ;;
  rhs)
    if [ "$#" -ne 5 ]; then
      echo "Usage: $0 [coords...] rhs <h> <b> <tw> <r>" >&2
      exit 1
    fi
    build_rhs "$2" "$3" "$4" "$5"
    ;;
  chs)
    if [ "$#" -ne 3 ]; then
      echo "Usage: $0 [coords...] chs <d> <tw>" >&2
      exit 1
    fi
    build_chs "$2" "$3"
    ;;
  hea)
    if [ "$#" -ne 6 ]; then
      echo "Usage: $0 [coords...] hea <h> <b> <tw> <tf> <r>" >&2
      exit 1
    fi
    build_hea "$2" "$3" "$4" "$5" "$6"
    ;;
  *)
    usage
    exit 1
    ;;
esac
