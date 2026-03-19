# shellcheck shell=bash
# progress.sh — Progress reporting: spinner (TTY) / NDJSON (non-TTY)

# ASCII spinner chars (Bash 3.2 safe — no multibyte Unicode)
# shellcheck disable=SC1003
_XEV_SPINNER_CHARS='|/-\'
_XEV_SPINNER_IDX=0

# Emit a progress message
# Usage: xev_progress "Searching Evernote..."
# Usage: xev_progress "Fetching note..." 1 2   # step 1 of 2
xev_progress() {
  [[ "${XEV_PROGRESS:-auto}" == "never" ]] && return

  local message="$1"
  local step="${2:-}"
  local total_steps="${3:-}"

  if [[ "${XEV_PROGRESS:-auto}" == "auto" && -t 2 ]]; then
    # TTY mode: spinner
    local char="${_XEV_SPINNER_CHARS:${_XEV_SPINNER_IDX}:1}"
    _XEV_SPINNER_IDX=$(( (_XEV_SPINNER_IDX + 1) % ${#_XEV_SPINNER_CHARS} ))
    printf '\r\033[K%s %s' "$char" "$message" >&2
  else
    # Non-TTY / always mode: NDJSON
    local json
    json=$(jq -n --arg msg "$message" '{"type":"progress","message":$msg,"progress":null}')
    if [[ -n "$step" ]]; then
      json=$(echo "$json" | jq --argjson s "$step" --argjson t "$total_steps" '. + {step:$s,total_steps:$t}')
    fi
    echo "$json" >&2
  fi
}

# Signal completion
xev_progress_done() {
  [[ "${XEV_PROGRESS:-auto}" == "never" ]] && return

  if [[ "${XEV_PROGRESS:-auto}" == "always" ]]; then
    # Always emit NDJSON regardless of TTY
    echo '{"type":"progress","message":"Done","progress":100}' >&2
  elif [[ -t 2 ]]; then
    printf '\r\033[K' >&2  # Clear spinner line
  else
    echo '{"type":"progress","message":"Done","progress":100}' >&2
  fi
}
