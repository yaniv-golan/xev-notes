#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
command=$(echo "$input" | jq -r '
  if .tool_input | type == "object" then .tool_input.command // ""
  elif .tool_input | type == "string" then .tool_input
  else "" end' 2>/dev/null || echo "")

# Not an xev-cli command — allow
[[ "$command" != *"xev-cli"* ]] && exit 0

# Config/help commands always allowed
[[ "$command" =~ (--help|--version|config) ]] && exit 0

# Check critical deps
missing=""
command -v jq &>/dev/null || missing="${missing} jq"
command -v curl &>/dev/null || missing="${missing} curl"

if [[ -n "$missing" ]]; then
  cat >&2 << EOF
{
  "hookSpecificOutput": {"permissionDecision": "deny"},
  "systemMessage": "BLOCKED: Missing required tools:${missing}. Install them and retry."
}
EOF
  exit 2
fi

# Check pandoc for write commands
if [[ "$command" == *"create"* || "$command" == *"update"* ]]; then
  if ! command -v pandoc &>/dev/null; then
    cat >&2 << 'EOF'
{
  "hookSpecificOutput": {"permissionDecision": "deny"},
  "systemMessage": "BLOCKED: pandoc is required for creating/updating notes. Install it and retry."
}
EOF
    exit 2
  fi
fi

# Validate config (discovery runs inside xev_load_config)
if ! xev-cli config check 2>/dev/null; then
  cat >&2 << 'EOF'
{
  "hookSpecificOutput": {"permissionDecision": "deny"},
  "systemMessage": "BLOCKED: xev-cli not configured. Create a .env file with MAKE_API_KEY and MAKE_TEAM_ID, or run: xev-cli config setup --auto"
}
EOF
  exit 2
fi

exit 0
