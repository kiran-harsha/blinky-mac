# Blinky — eye-care reminders. A native overlay nudges you to blink and look away on
# configurable intervals; the shell only sends small events to control it.

[[ -n "${BLINKY_LOADED:-}" ]] && return
typeset -g BLINKY_LOADED=1
typeset -g _BLINKY_HOME="${BLINKY_HOME:-$HOME/.blinky}"
typeset -g _BLINKY_BIN="$_BLINKY_HOME/bin/blinky-overlay"
typeset -g _BLINKY_EVENTS="$_BLINKY_HOME/run/events"
typeset -g _BLINKY_PID="$_BLINKY_HOME/run/pid"
typeset -g _BLINKY_CONFIG="$_BLINKY_HOME/config"
typeset -g _BLINKY_HIDDEN=0

_blinky_running() {
  [[ -r "$_BLINKY_PID" ]] || return 1
  kill -0 "$(<"$_BLINKY_PID")" 2>/dev/null
}

_blinky_start() {
  [[ "$OSTYPE" == darwin* && -x "$_BLINKY_BIN" ]] || return 1
  _blinky_running && return 0
  mkdir -p "$_BLINKY_HOME/run"
  ( nohup "$_BLINKY_BIN" >/dev/null 2>&1 & )
}

_blinky_send() {
  [[ -d "$_BLINKY_HOME/run" ]] || return
  print -r -- "$1" >> "$_BLINKY_EVENTS"
}

# Wake blinky when a local interactive shell opens (skip over SSH).
[[ -z "${SSH_CONNECTION:-}" ]] && _blinky_start

_blinky_config_set() {
  local key="$1" value="$2" line
  local -a kept=()
  if [[ -r "$_BLINKY_CONFIG" ]]; then
    while IFS= read -r line; do [[ "$line" == "$key="* ]] || kept+=("$line"); done < "$_BLINKY_CONFIG"
  fi
  mkdir -p "${_BLINKY_CONFIG:h}"
  print -rl -- "${kept[@]}" "$key=$value" > "$_BLINKY_CONFIG"
}

_blinky_config_get() {
  local key="$1"
  [[ -r "$_BLINKY_CONFIG" ]] || return
  sed -n "s/^$key=//p" "$_BLINKY_CONFIG" | tail -1
}

# Get/set one frequency: `_blinky_freq <config-key> <label> <minutes-or-empty> <default>`.
_blinky_freq() {
  local key="$1" label="$2" minutes="${3:-}" default="$4"
  if [[ -z "$minutes" ]]; then
    local current="$(_blinky_config_get "$key")"
    echo "${current:-$default}"
    return
  fi
  if ! [[ "$minutes" =~ '^[0-9]+$' ]]; then
    echo "usage: blinky $label [minutes]  (0 disables)"
    return 1
  fi
  _blinky_config_set "$key" "$minutes"
  _blinky_start; _blinky_send reload
  echo "👁️ $label: $minutes min"
}

blinky() {
  case "${1:-}" in
    on)    _BLINKY_HIDDEN=0; _blinky_start; _blinky_send show; echo "👁️ blinky: on" ;;
    off)   _BLINKY_HIDDEN=1; _blinky_send hide; echo "blinky: off" ;;
    start) _blinky_start && echo "👁️ blinky started" || echo "overlay not installed — run install.sh" ;;
    quit)  _blinky_send quit; echo "👁️ blinky stopped" ;;
    blink-freq)    _blinky_freq blink_freq_min "blink-freq" "${2:-}" 1 ;;
    lookaway-freq) _blinky_freq lookaway_freq_min "lookaway-freq" "${2:-}" 20 ;;
    status)
      echo "blink-freq: $(_blinky_freq blink_freq_min "blink-freq" "" 1) min"
      echo "lookaway-freq: $(_blinky_freq lookaway_freq_min "lookaway-freq" "" 20) min"
      echo "state: $([[ "$_BLINKY_HIDDEN" == 1 ]] && echo off || echo on)"
      ;;
    demo)
      case "${2:-}" in
        blink|lookaway) _blinky_start; _blinky_send "demo $2" ;;
        *) echo "usage: blinky demo blink|lookaway" ;;
      esac
      ;;
    *) echo "usage: blinky {on|off|start|quit|status|blink-freq [min]|lookaway-freq [min]|demo blink|lookaway}" ;;
  esac
}
