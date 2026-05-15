#!/usr/bin/env bash
# Two-line Claude Code status line.
# Line 1: dir: [project/subpath] | [model] [used / size] | [used%] used [tokens] | [remain%] remain [tokens] | thinking: On/Off | effort: [level]
# Line 2: 5 hour: [bar] [pct]% resets [t] (Xh Ym)  |  weekly: [bar] [pct]% resets [date, t] (Xd Y.Yh)

input=$(cat)

# ── ANSI ──────────────────────────────────────────────────────────────────────
R=$'\033[0m'
DIM=$'\033[2m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
MAGENTA=$'\033[35m'
BRED=$'\033[91m'
WHITE=$'\033[97m'
BLUE=$'\033[34m'

# ── Helpers ───────────────────────────────────────────────────────────────────
# Threshold color for a 0..100 value.
threshold_color() {
  local p=${1:-0}
  if   (( p >= 80 )); then printf '%s' "$BRED"
  elif (( p >= 50 )); then printf '%s' "$YELLOW"
  else                     printf '%s' "$GREEN"
  fi
}

# 10-char bar: filled = ●, empty = ○. Round pct to nearest 10.
build_bar() {
  local pct=${1:-0}
  local filled=$(( (pct + 5) / 10 ))
  (( filled > 10 )) && filled=10
  (( filled < 0 ))  && filled=0
  local empty=$(( 10 - filled ))
  local out="" i
  for (( i=0; i<filled; i++ )); do out+="●"; done
  for (( i=0; i<empty;  i++ )); do out+="○"; done
  printf '%s' "$out"
}

# 134938 → "135k" / 8500 → "8.5k" / 200000 → "200k"
fmt_k() {
  awk -v n="${1:-0}" 'BEGIN {
    if (n >= 10000)      printf "%dk",  int(n/1000 + 0.5);
    else if (n >= 1000)  printf "%.1fk", n/1000;
    else                 printf "%d",   n;
  }'
}

# 134938 → "134,938"
fmt_comma() {
  awk -v n="${1:-0}" 'BEGIN {
    s = sprintf("%d", n); out = "";
    while (length(s) > 3) {
      out = "," substr(s, length(s)-2) out;
      s   = substr(s, 1, length(s)-3);
    }
    print s out;
  }'
}

# Unix ts → "8:29pm"
fmt_time_only() {
  local ts="$1"
  { [ -z "$ts" ] || [ "$ts" = "null" ]; } && { printf -- '-'; return; }
  date -d "@$ts" '+%-I:%M%P' 2>/dev/null || printf -- '-'
}

# Unix ts → "feb 13, 11:29pm"
fmt_date_time() {
  local ts="$1"
  { [ -z "$ts" ] || [ "$ts" = "null" ]; } && { printf -- '-'; return; }
  date -d "@$ts" '+%b %-d, %-I:%M%P' 2>/dev/null | tr '[:upper:]' '[:lower:]' || printf -- '-'
}

# Unix ts → "(45m)" / "(2h 21m)" / "(3d 2.5h)"
# < 1h:   minutes only
# < 24h:  hours + minutes
# >= 24h: days + half-hours
fmt_duration() {
  local ts="$1"
  { [ -z "$ts" ] || [ "$ts" = "null" ]; } && { printf ''; return; }
  local now=$(date +%s)
  local secs=$(( ts - now ))
  if (( secs <= 0 )); then
    printf '(now)'
    return
  fi
  local mins=$(( secs / 60 ))
  if (( mins < 60 )); then
    printf '(%dm)' "$mins"
  elif (( mins < 1440 )); then
    local h=$(( mins / 60 ))
    local m=$(( mins % 60 ))
    printf '(%dh %dm)' "$h" "$m"
  else
    local days=$(( mins / 1440 ))
    local rem_mins=$(( mins % 1440 ))
    # round remaining to nearest 0.5h
    awk -v d="$days" -v rm="$rem_mins" 'BEGIN {
      half_hours = int((rm / 30) + 0.5);
      h = half_hours / 2;
      if (h == 0)        printf "(%dd)", d;
      else if (h == int(h)) printf "(%dd %dh)", d, h;
      else               printf "(%dd %.1fh)", d, h;
    }'
  fi
}

# Build the dir display: project name, plus /subpath if current_dir is deeper.
# Falls back gracefully if either field is missing.
build_dir() {
  local proj="$1"
  local cur="$2"
  local proj_name="" subpath=""

  if [ -n "$proj" ] && [ "$proj" != "null" ]; then
    proj_name=$(basename "$proj")
  elif [ -n "$cur" ] && [ "$cur" != "null" ]; then
    # No project_dir, just show current_dir basename
    printf '%s' "$(basename "$cur")"
    return
  else
    printf -- '-'
    return
  fi

  # If we have both, check whether current_dir is below project_dir
  if [ -n "$cur" ] && [ "$cur" != "null" ] && [ "$cur" != "$proj" ]; then
    # Strip project_dir prefix from current_dir to get the subpath
    case "$cur" in
      "$proj"/*)
        subpath="${cur#$proj/}"
        printf '%s/%s' "$proj_name" "$subpath"
        return
        ;;
    esac
  fi

  printf '%s' "$proj_name"
}

# ── Extract from stdin JSON ───────────────────────────────────────────────────
MODEL=$(printf '%s' "$input" | jq -r '.model.display_name // "claude"')

PROJ_DIR=$(printf '%s' "$input" | jq -r '.workspace.project_dir // empty')
CUR_DIR=$(printf  '%s' "$input" | jq -r '.workspace.current_dir // empty')
DIR_DISPLAY=$(build_dir "$PROJ_DIR" "$CUR_DIR")

CTX_SIZE=$(printf  '%s' "$input" | jq -r '.context_window.context_window_size // 200000')
USED_PCT=$(printf  '%s' "$input" | jq -r '.context_window.used_percentage // 0' | awk '{printf "%d", $1+0.5}')
TOK_USED=$(printf  '%s' "$input" | jq -r '.context_window.total_input_tokens // 0')
REMAIN_PCT=$(( 100 - USED_PCT ))
(( REMAIN_PCT < 0 )) && REMAIN_PCT=0
TOK_REMAIN=$(( CTX_SIZE - TOK_USED ))
(( TOK_REMAIN < 0 )) && TOK_REMAIN=0

EFFORT=$(printf    '%s' "$input" | jq -r '.effort.level // empty')
[ -z "$EFFORT" ] && EFFORT="-"

FIVE_PCT=$(printf  '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // 0'  | awk '{printf "%d", $1+0.5}')
FIVE_RST=$(printf  '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
SEVEN_PCT=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // 0'  | awk '{printf "%d", $1+0.5}')
SEVEN_RST=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# ── Thinking: env > stdin > settings.json > Off ───────────────────────────────
to_bool() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1|on|true|yes|enabled) printf 'On' ;;
    *)                      printf 'Off' ;;
  esac
}

THINKING=""
if [ -n "${CLAUDE_THINKING:-}" ]; then
  THINKING=$(to_bool "$CLAUDE_THINKING")
else
  ST=$(printf '%s' "$input" | jq -r '.thinking.enabled // empty')
  if [ -n "$ST" ] && [ "$ST" != "null" ]; then
    THINKING=$(to_bool "$ST")
  elif [ -f "$HOME/.claude/settings.json" ]; then
    KS=$(jq -r '
      [ .. | objects | to_entries[]?
        | select(.key | ascii_downcase | test("thinking"))
        | .value
      ] | .[0] // empty
    ' "$HOME/.claude/settings.json" 2>/dev/null)
    if [ -n "$KS" ] && [ "$KS" != "null" ]; then
      # Accept boolean true OR an object whose .enabled is true.
      if [ "$KS" = "true" ]; then
        THINKING="On"
      else
        EN=$(printf '%s' "$KS" | jq -r '.enabled // empty' 2>/dev/null)
        [ "$EN" = "true" ] && THINKING="On"
      fi
    fi
  fi
fi
[ -z "$THINKING" ] && THINKING="Off"

# ── Pre-format values ─────────────────────────────────────────────────────────
TOK_USED_K=$(fmt_k     "$TOK_USED")
CTX_K=$(fmt_k          "$CTX_SIZE")
TOK_USED_C=$(fmt_comma "$TOK_USED")
TOK_REMAIN_C=$(fmt_comma "$TOK_REMAIN")
FIVE_BAR=$(build_bar    "$FIVE_PCT")
SEVEN_BAR=$(build_bar   "$SEVEN_PCT")
FIVE_BAR_C=$(threshold_color  "$FIVE_PCT")
SEVEN_BAR_C=$(threshold_color "$SEVEN_PCT")
FIVE_RST_FMT=$(fmt_time_only  "$FIVE_RST")
SEVEN_RST_FMT=$(fmt_date_time "$SEVEN_RST")
FIVE_DUR=$(fmt_duration  "$FIVE_RST")
SEVEN_DUR=$(fmt_duration "$SEVEN_RST")

if [ "$THINKING" = "On" ]; then THINK_C="$GREEN"; else THINK_C="$DIM"; fi

case "$EFFORT" in
  max)    EFFORT_C="$BRED" ;;
  xhigh)  EFFORT_C="$MAGENTA" ;;
  high)   EFFORT_C="$YELLOW" ;;
  medium) EFFORT_C="$GREEN" ;;
  low|-)  EFFORT_C="$DIM" ;;
  *)      EFFORT_C="$DIM" ;;
esac

PIPE="${DIM}|${R}"

# ── Line 1 ────────────────────────────────────────────────────────────────────
printf 'dir: %s%s%s %s %s[%s]%s %s%s / %s%s %s %s%s%%%s used %s%s%s %s %s%s%%%s remain %s%s%s %s thinking: %s%s%s %s effort: %s%s%s\n' \
  "$BLUE"     "$DIR_DISPLAY"  "$R" \
  "$PIPE" \
  "$CYAN"     "$MODEL"        "$R" \
  "$WHITE"    "$TOK_USED_K"   "$CTX_K"      "$R" \
  "$PIPE" \
  "$MAGENTA"  "$USED_PCT"     "$R" \
  "$WHITE"    "$TOK_USED_C"   "$R" \
  "$PIPE" \
  "$GREEN"    "$REMAIN_PCT"   "$R" \
  "$WHITE"    "$TOK_REMAIN_C" "$R" \
  "$PIPE" \
  "$THINK_C"  "$THINKING"     "$R" \
  "$PIPE" \
  "$EFFORT_C" "$EFFORT"       "$R"

# ── Line 2 ────────────────────────────────────────────────────────────────────
printf '%s5 hour:%s %s%s%s %s%s%%%s %sresets %s%s %s%s%s  %s  %sweekly:%s %s%s%s %s%s%%%s %sresets %s%s %s%s%s\n' \
  "$WHITE"       "$R" \
  "$FIVE_BAR_C"  "$FIVE_BAR"      "$R" \
  "$WHITE"       "$FIVE_PCT"      "$R" \
  "$DIM"         "$FIVE_RST_FMT"  "$R" \
  "$FIVE_BAR_C"  "$FIVE_DUR"      "$R" \
  "$PIPE" \
  "$WHITE"       "$R" \
  "$SEVEN_BAR_C" "$SEVEN_BAR"     "$R" \
  "$WHITE"       "$SEVEN_PCT"     "$R" \
  "$DIM"         "$SEVEN_RST_FMT" "$R" \
  "$SEVEN_BAR_C" "$SEVEN_DUR"     "$R"
