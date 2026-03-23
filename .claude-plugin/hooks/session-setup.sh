#!/usr/bin/env bash
set -euo pipefail

# 1. Add xev-cli to PATH
xev_bin="${CLAUDE_PLUGIN_ROOT}/xev-cli/bin"
if [[ -d "$xev_bin" ]]; then
  export PATH="$xev_bin:$PATH"
  [[ -n "${CLAUDE_ENV_FILE:-}" ]] && echo "export PATH=\"$xev_bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

# 2. Find .env in Cowork mounted folders (if XEV_DOTENV_DIR not already set)
if [[ -z "${XEV_DOTENV_DIR:-}" ]] && [[ -d "./mnt" ]]; then
  for dir in ./mnt/[^.]*; do
    [[ -d "$dir" ]] || continue
    [[ "$(basename "$dir")" == "uploads" ]] && continue
    if [[ -f "$dir/.env" ]] && grep -q "MAKE_API_KEY" "$dir/.env" 2>/dev/null; then
      export XEV_DOTENV_DIR="$dir"
      [[ -n "${CLAUDE_ENV_FILE:-}" ]] && echo "export XEV_DOTENV_DIR=\"$dir\"" >> "$CLAUDE_ENV_FILE"
      break
    fi
  done
fi

exit 0
