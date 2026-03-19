# shellcheck shell=bash
# output.sh — JSON/JSONL/human output formatting, error envelope, masking

# Emit a success JSON envelope
xev_json_ok() {
  local data="$1"
  jq -n --argjson data "$data" '{"ok": true, "data": $data}'
}

# Emit an error JSON envelope
xev_json_error() {
  local code="$1"
  local message="$2"
  jq -n --arg code "$code" --arg msg "$message" \
    '{"ok": false, "error": {"code": $code, "message": $msg}}'
}

# Mask a webhook URL: keep first 30 chars + last 4
xev_mask_url() {
  local url="$1"
  local len=${#url}
  if [[ $len -le 34 ]]; then
    echo "$url"
  else
    echo "${url:0:30}...${url:$((len-4))}"
  fi
}

# Mask an API key: show only last 4 chars
xev_mask_key() {
  local key="$1"
  local len=${#key}
  if [[ $len -le 4 ]]; then
    echo "$key"
  else
    echo "****${key:$((len-4))}"
  fi
}

# Exit with error JSON on stdout and exit code 1
xev_die() {
  local code="$1"
  local message="$2"
  xev_json_error "$code" "$message"
  exit 1
}

# Exit with usage error on stderr and exit code 2
xev_die_usage() {
  echo "Error: $1" >&2
  echo "Run 'xev-cli --help' for usage." >&2
  exit 2
}

# Usage display
xev_usage() {
  cat <<'EOF'
Usage: xev-cli [global-flags] <command> [args]

Commands:
  search <query>     Search for notes
  get <note-id>      Get a note by ID
  notebooks          List notebooks
  create             Create a new note
  update <note-id>   Update an existing note
  config             Manage configuration

Global flags:
  --profile <name>   Config profile (default: "default")
  --config-file <p>  Alternate config file path
  --dotenv           Load .env from current directory
  --trace            Debug curl output (URLs redacted)
  --progress <mode>  auto|always|never (default: auto)
  --version          Show version
  --help             Show this help
EOF
}
