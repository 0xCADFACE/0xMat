#!/usr/bin/env bash
set -euo pipefail

### CONFIG #########################################################

LIB_ROOT="hexmat_profile_library"
GEO_SCRIPT="./geo.sh"

# Plasticity / xdotool assumptions (used for focusing window)
PLASTICITY_TITLE="Untitled - Plasticity"
ORIGIN_X="${ORIGIN_X:-100}"
ORIGIN_Y="${ORIGIN_Y:-100}"

DELAY_TINY=0.05
DELAY_SMALL=0.10

####################################################################


need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }
}

need_cmd jq
need_cmd xdotool
need_cmd xclip

if [ ! -x "$GEO_SCRIPT" ]; then
  echo "Geometry script not executable: $GEO_SCRIPT" >&2
  echo "Make it executable with: chmod +x $GEO_SCRIPT" >&2
  exit 1
fi

clean_dim() {
  local v="$1"
  v=${v//$'\r'/}
  v=${v//$'\n'/}
  printf '%s mm' "$v"
}

focus_plasticity() {
  xdotool mousemove --sync "$ORIGIN_X" "$ORIGIN_Y"
  sleep "$DELAY_TINY"
}

save_clipboard_to_file() {
  local outfile="$1"

  : > "$outfile"

  if xclip -selection clipboard -t application/vnd.plasticity.items -o >"$outfile" 2>/dev/null; then
    if [ -s "$outfile" ]; then
      return 0
    fi
  fi

  : > "$outfile"
  if xclip -selection primary -t application/vnd.plasticity.items -o >"$outfile" 2>/dev/null; then
    if [ -s "$outfile" ]; then
      return 0
    fi
  fi

  echo " Warning: could not read Plasticity clipboard into $outfile" >&2
  rm -f "$outfile"
  return 1
}

copy_current_profile_to_file() {
  local outfile="$1"

  focus_plasticity

  xdotool key a
  sleep "$DELAY_TINY"

  xdotool keydown ctrl
  sleep "$DELAY_TINY"
  xdotool key c
  sleep "$DELAY_TINY"
  xdotool keyup ctrl
  sleep "$DELAY_SMALL"

  save_clipboard_to_file "$outfile" || echo "No Plasticity data for $outfile" >&2

  xdotool key Delete
  sleep "$DELAY_SMALL"
  
  xdotool key Escape
  sleep "$DELAY_TINY"
}

####################################################################
# GLOBAL STATE FOR LIMIT & PROGRESS
####################################################################

DRY_RUN=0
LIMIT=0
TOTAL_PROFILES=0
DONE_PROFILES=0

progress_total=0
progress_current=0
progress_start_time=0

init_progress() {
  progress_total="$1"
  progress_current=0
  progress_start_time=$(date +%s)
  echo "Starting generation for $progress_total profile(s)..."
  echo
}

update_progress() {
  local msg="$1"

  {
    progress_current=$((progress_current + 1))

    local pct=0
    if [ "${progress_total:-0}" -gt 0 ]; then
      pct=$((progress_current * 100 / progress_total))
    fi

    local now
    now=$(date +%s)
    local elapsed=$((now - progress_start_time))

    printf "[%3d%%] %-40s (elapsed: %ds)\n" "$pct" "$msg" "$elapsed"
  }
}

finish_progress() {
  local elapsed=$(( $(date +%s) - progress_start_time ))
  echo
  echo "Completed $progress_current / $progress_total profile(s) in ${elapsed}s total."
}

####################################################################
# PROCESS ONE JSON FILE
####################################################################

process_json_file() {
  local json="$1"


  if [ ! -f "$json" ]; then
    echo "JSON file not found: $json" >&2
    return
  fi

  local base type family
  base=$(basename "$json")
  type="${base%.*}"

  case "$type" in
    HEA|IPE|HEM)
      family="hea" ;;
    CHS)
      family="chs" ;;
    RHS|SHS)
      family="rhs" ;;
    *)
      echo "Skipping JSON '$json': unknown profile family '$type'" >&2
      return ;;
  esac

  local OUT_BASE_DIR
  OUT_BASE_DIR=$(dirname "$json")

  local FILE_COUNT
  FILE_COUNT=$(jq 'length' "$json")
  local FILE_INDEX=0

  echo "============================================"
  echo "Using JSON:       $json"
  echo "Profile family:   $type  (builder: $family)"
  echo "Profiles in file: $FILE_COUNT"
  echo "Output base dir:  $OUT_BASE_DIR"
  echo


  while IFS= read -r row; do
    FILE_INDEX=$((FILE_INDEX + 1))

    if [ "$LIMIT" -gt 0 ] && [ "$DONE_PROFILES" -ge "$LIMIT" ]; then
      echo "Limit reached ($LIMIT profiles). Stopping."
      finish_progress
      exit 0
    fi

    local profile
    profile=$(jq -r '.profile' <<<"$row")

    if [ -z "$profile" ] || [ "$profile" = "null" ]; then
      echo "Skipping row with no profile name: $row" >&2
      continue
    fi

    DONE_PROFILES=$((DONE_PROFILES + 1))

    echo "--------------------------------------------"
    echo "Profile ${DONE_PROFILES}/${TOTAL_PROFILES} (file ${FILE_INDEX}/${FILE_COUNT})"
    echo "JSON: $json"
    echo "Profile: $profile"

    local dir="${OUT_BASE_DIR}/${profile}"
    echo "Output dir: $dir"
    mkdir -p "$dir"

    update_progress "Generating $profile"

    case "$family" in
      hea)
        local h b tw tf r
        h=$(clean_dim "$(jq -r '.h' <<<"$row")")
        b=$(clean_dim "$(jq -r '.b' <<<"$row")")
        tw=$(clean_dim "$(jq -r '.tw' <<<"$row")")
        tf=$(clean_dim "$(jq -r '.tf' <<<"$row")")
        r=$(clean_dim "$(jq -r '.r' <<<"$row")")

        echo "  h=$h  b=$b  tw=$tw  tf=$tf  r=$r"

        if [ "$DRY_RUN" -eq 0 ]; then
          if ! "$GEO_SCRIPT" hea "$h" "$b" "$tw" "$tf" "$r"; then
            echo "geo.sh hea failed for profile $profile" >&2
            continue
          fi
        else
          echo "  [DRY RUN] Would run: $GEO_SCRIPT hea $h $b $tw $tf $r"
        fi
        ;;
      chs)
        local D tw
        D=$(clean_dim "$(jq -r '.D' <<<"$row")")
        tw=$(clean_dim "$(jq -r '.tw' <<<"$row")")
        echo "  D=$D  tw=$tw"

        if [ "$DRY_RUN" -eq 0 ]; then
          if ! "$GEO_SCRIPT" chs "$D" "$tw"; then
            echo "geo.sh chs failed for profile $profile" >&2
            continue
          fi
        else
          echo "  [DRY RUN] Would run: $GEO_SCRIPT chs $D $tw"
        fi
        ;;
      rhs)
        local h b tw r
        h=$(clean_dim "$(jq -r '.h' <<<"$row")")
        b=$(clean_dim "$(jq -r '.b' <<<"$row")")
        tw=$(clean_dim "$(jq -r '.tw' <<<"$row")")
        r=$(clean_dim "$(jq -r '.r' <<<"$row")")
        echo "  h=$h  b=$b  tw=$tw  r=$r"

        if [ "$DRY_RUN" -eq 0 ]; then
          if ! "$GEO_SCRIPT" rhs "$h" "$b" "$tw" "$r"; then
            echo "geo.sh rhs failed for profile $profile" >&2
            continue
          fi
        else
          echo "  [DRY RUN] Would run: $GEO_SCRIPT rhs $h $b $tw $r"
        fi
        ;;
    esac

    if [ "$DRY_RUN" -eq 0 ]; then
      copy_current_profile_to_file "$dir/profile"
      echo "Saved: $dir/profile"
    else
      echo "  [DRY RUN] Would copy Plasticity geometry to $dir/profile"
    fi

    echo

    if [ "$LIMIT" -gt 0 ] && [ "$DONE_PROFILES" -ge "$LIMIT" ]; then
      echo "Limit reached ($LIMIT profiles). Stopping."
      finish_progress
      exit 0
    fi
  done < <(jq -c '.[]' "$json")

}

####################################################################
# MAIN
####################################################################

usage() {
  cat >&2 <<EOF
Usage: $0 [--limit N] [--dry-run] [JSON_FILE ...]
  Without JSON_FILE arguments, scans: $LIB_ROOT

Options:
  --limit N    Only process N profiles total, then stop.
  --dry-run    Do not call geo.sh or xdotool/xclip; just print what would happen.
EOF
}
setup_viewport_once() {
  echo "Normalizing Plasticity viewport..."
  xdotool key ctrl+b
  sleep "$DELAY_TINY"
  xdotool key ctrl+shift+b
  sleep "$DELAY_TINY"
  xdotool key --clearmodifiers KP_1
  sleep "$DELAY_TINY"
  xdotool key --clearmodifiers 2
  sleep "$DELAY_TINY"
}

main() {
  local json_files=()
  

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --limit)
        shift
        if [ "$#" -eq 0 ]; then
          echo "--limit requires an argument" >&2
          usage
          exit 1
        fi
        LIMIT="$1"
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        json_files+=("$1")
        shift
        ;;
    esac
  done

  if [ "${#json_files[@]}" -eq 0 ]; then
    if [ ! -d "$LIB_ROOT" ]; then
      echo "Profile library directory not found: $LIB_ROOT" >&2
      exit 1
    fi

    echo "Searching recursively for JSON profile definitions under: $LIB_ROOT"
    while IFS= read -r f; do
      json_files+=("$f")
    done < <(find "$LIB_ROOT" -type f -iname '*.json' | sort)

    if [ "${#json_files[@]}" -eq 0 ]; then
      echo "No JSON files found anywhere under $LIB_ROOT" >&2
      exit 1
    fi

    echo "Found ${#json_files[@]} JSON file(s):"
    for f in "${json_files[@]}"; do
      echo "->  $f"
    done
    echo
  fi


  TOTAL_PROFILES=0
  for json in "${json_files[@]}"; do
    if [ -f "$json" ]; then
      local_count=$(jq 'length' "$json")
      TOTAL_PROFILES=$((TOTAL_PROFILES + local_count))
    fi
  done

  if [ "$TOTAL_PROFILES" -eq 0 ]; then
    echo "No profiles found in the given JSON files."
    exit 0
  fi

  local progress_target="$TOTAL_PROFILES"
  if [ "$LIMIT" -gt 0 ] && [ "$LIMIT" -lt "$TOTAL_PROFILES" ]; then
    progress_target="$LIMIT"
  fi

  echo "Found ${#json_files[@]} JSON file(s)."
  echo "Total profiles across all JSONs: $TOTAL_PROFILES"
  if [ "$LIMIT" -gt 0 ]; then
    echo "Limit enabled: will stop after $LIMIT profiles."
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "DRY RUN: no geometry will actually be generated."
  fi
  echo

  init_progress "$progress_target"
  
  setup_viewport_once
  
  for json in "${json_files[@]}"; do
    process_json_file "$json"
  done

  finish_progress
  echo "All profiles processed. Done=$DONE_PROFILES / Total=$TOTAL_PROFILES"
}

main "$@"
