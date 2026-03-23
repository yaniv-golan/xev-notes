#!/usr/bin/env bash
set -euo pipefail
input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")

case "$file_path" in
  *.env|*.env.*|*/.env|*/.env.*)
    cat >&2 << 'EOF'
{
  "hookSpecificOutput": {"permissionDecision": "deny"},
  "systemMessage": "BLOCKED: Reading .env files is not allowed — it would expose API keys. Credentials are loaded automatically via auto-discovery."
}
EOF
    exit 2
    ;;
esac
exit 0
