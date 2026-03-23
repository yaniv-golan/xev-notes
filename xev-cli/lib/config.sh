# shellcheck shell=bash
# config.sh — TOML config loading, resolution chain, profile support

# Discover xev-* webhook URLs from Make.com API and populate empty XEV_CFG_WEBHOOK_* vars
# Requires MAKE_API_KEY and MAKE_TEAM_ID to be set (in env or loaded from .env)
# Uses a 300s file cache keyed by UID + team ID + zone
xev_discover_hooks() {
  local api_key="${MAKE_API_KEY:-}"
  local team_id="${MAKE_TEAM_ID:-}"
  local zone="${MAKE_ZONE:-eu2.make.com}"

  [[ -z "$api_key" || -z "$team_id" ]] && return 1

  # Cache keyed by team ID + zone to prevent cross-region contamination
  local cache="/tmp/xev-hooks-cache-${UID:-0}-${team_id}-$(echo "$zone" | tr '.' '-').json"
  local cache_age=999999
  if [[ -f "$cache" ]]; then
    local now
    now=$(date +%s)
    local mtime
    mtime=$(stat -f %m "$cache" 2>/dev/null || stat -c %Y "$cache" 2>/dev/null || echo 0)
    cache_age=$(( now - mtime ))
  fi

  local hooks_json
  if [[ $cache_age -lt 300 ]]; then
    hooks_json=$(cat "$cache")
  else
    # Discover via API
    hooks_json=$(curl -s --max-time 10 \
      -H "Authorization: Token ${api_key}" \
      "https://${zone}/api/v2/hooks?teamId=${team_id}&pg%5Blimit%5D=200" 2>/dev/null)

    if ! echo "$hooks_json" | jq -e '.hooks' >/dev/null 2>&1; then
      return 1  # API call failed or returned unexpected payload
    fi

    # Filter to exact xev-* hook names, prefer hooks linked to scenarios
    local all_xev_hooks
    all_xev_hooks=$(echo "$hooks_json" | jq '[
      .hooks[]
      | select(.name | test("^xev-(search|get|notebooks|create|update|append)$"))
      | {name, url, id, linked: ((.data.scenarioId // .scenarioId // null) != null)}
    ]')

    # Try linked hooks first (those attached to active scenarios)
    hooks_json=$(echo "$all_xev_hooks" | jq '[
      [.[] | select(.linked)] | group_by(.name) | map(sort_by(.id) | last)
    ] | flatten')

    # Fall back to all hooks if no linked ones found
    if [[ $(echo "$hooks_json" | jq 'length') -eq 0 ]]; then
      hooks_json=$(echo "$all_xev_hooks" | jq '[
        group_by(.name) | map(sort_by(.id) | last)
      ] | flatten')
    fi

    echo "$hooks_json" > "$cache"
  fi

  # Map hook names to config variables (only fill empty ones)
  local mappings="search:XEV_CFG_WEBHOOK_SEARCH get:XEV_CFG_WEBHOOK_GET notebooks:XEV_CFG_WEBHOOK_NOTEBOOKS create:XEV_CFG_WEBHOOK_CREATE update:XEV_CFG_WEBHOOK_UPDATE append:XEV_CFG_WEBHOOK_APPEND"

  for mapping in $mappings; do
    local suffix="${mapping%%:*}"
    local var="${mapping#*:}"
    if [[ -z "${!var:-}" ]]; then
      local url
      url=$(echo "$hooks_json" | jq -r --arg n "xev-${suffix}" '.[] | select(.name == $n) | .url // empty')
      if [[ -n "$url" ]]; then
        printf -v "$var" '%s' "$url"
      fi
    fi
  done
}

# Simple TOML parser for flat key=value under [section] headers
# Sets XEV_CFG_* variables
xev_load_config() {
  local config_file="$1"
  local profile="${XEV_PROFILE:-default}"

  # Defaults
  XEV_CFG_MAKE_ZONE=""
  XEV_CFG_WEBHOOK_API_KEY=""
  XEV_CFG_WEBHOOK_SEARCH=""
  XEV_CFG_WEBHOOK_GET=""
  XEV_CFG_WEBHOOK_NOTEBOOKS=""
  XEV_CFG_WEBHOOK_CREATE=""
  XEV_CFG_WEBHOOK_UPDATE=""
  XEV_CFG_WEBHOOK_APPEND=""
  XEV_CFG_WEBHOOK_GET_ATTACHMENT=""

  # Parse TOML file if it exists (config file is optional)
  if [[ -f "$config_file" ]]; then
    local current_section=""
    local target_section=""

    # Determine target section
    if [[ "$profile" == "default" ]]; then
      target_section="default"
    else
      target_section="profiles.${profile}"
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
      # Skip comments and empty lines
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ -z "${line// /}" ]] && continue

      # Section header
      if [[ "$line" =~ ^\[([^]]+)\] ]]; then
        current_section="${BASH_REMATCH[1]}"
        continue
      fi

      # Key = value (only in target section)
      if [[ "$current_section" == "$target_section" ]] && [[ "$line" =~ ^[[:space:]]*([a-z_]+)[[:space:]]*=[[:space:]]*\"?([^\"]*)\"? ]]; then
        local key="${BASH_REMATCH[1]}"
        local value="${BASH_REMATCH[2]}"
        local var_name
        var_name="XEV_CFG_$(echo "$key" | tr '[:lower:]' '[:upper:]')"
        printf -v "$var_name" '%s' "$value"  # Safe: no eval, prevents code injection
      fi
    done < "$config_file"
  fi

  # Dotenv loading (step 3 in resolution chain)
  # XEV_DOTENV_DIR takes precedence; fallback to --dotenv flag (XEV_DOTENV=true → ./.env)
  local dotenv_file=""
  if [[ -n "${XEV_DOTENV_DIR:-}" ]]; then
    dotenv_file="${XEV_DOTENV_DIR}/.env"
  elif [[ "${XEV_DOTENV:-false}" == "true" ]]; then
    dotenv_file=".env"
  fi

  if [[ -n "$dotenv_file" ]] && [[ -f "$dotenv_file" ]]; then
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
      [[ "$key" =~ ^[[:space:]]*# ]] && continue  # Skip comments
      [[ -z "$key" ]] && continue
      key=$(echo "$key" | xargs)  # Trim whitespace
      value=$(echo "$value" | sed 's/^"//;s/"$//')  # Strip quotes
      [[ -z "${!key:-}" ]] && export "$key=$value"  # Only set if not already set
    done < "$dotenv_file"
  fi

  # Environment variable overrides (highest priority after CLI flags)
  # shellcheck disable=SC2034  # XEV_CFG_* vars are used by commands.sh
  [[ -n "${XEV_MAKE_ZONE:-}" ]] && XEV_CFG_MAKE_ZONE="$XEV_MAKE_ZONE"
  [[ -n "${MAKE_API_KEY:-}" ]] && export MAKE_API_KEY
  [[ -n "${MAKE_TEAM_ID:-}" ]] && export MAKE_TEAM_ID
  [[ -n "${MAKE_ZONE:-}" ]] && export MAKE_ZONE
  # shellcheck disable=SC2034
  [[ -n "${XEV_WEBHOOK_API_KEY:-}" ]] && XEV_CFG_WEBHOOK_API_KEY="$XEV_WEBHOOK_API_KEY"
  [[ -n "${XEV_WEBHOOK_SEARCH:-}" ]] && XEV_CFG_WEBHOOK_SEARCH="$XEV_WEBHOOK_SEARCH"
  [[ -n "${XEV_WEBHOOK_GET:-}" ]] && XEV_CFG_WEBHOOK_GET="$XEV_WEBHOOK_GET"
  [[ -n "${XEV_WEBHOOK_NOTEBOOKS:-}" ]] && XEV_CFG_WEBHOOK_NOTEBOOKS="$XEV_WEBHOOK_NOTEBOOKS"
  [[ -n "${XEV_WEBHOOK_CREATE:-}" ]] && XEV_CFG_WEBHOOK_CREATE="$XEV_WEBHOOK_CREATE"
  [[ -n "${XEV_WEBHOOK_UPDATE:-}" ]] && XEV_CFG_WEBHOOK_UPDATE="$XEV_WEBHOOK_UPDATE"
  [[ -n "${XEV_WEBHOOK_APPEND:-}" ]] && XEV_CFG_WEBHOOK_APPEND="$XEV_WEBHOOK_APPEND"
  [[ -n "${XEV_WEBHOOK_GET_ATTACHMENT:-}" ]] && XEV_CFG_WEBHOOK_GET_ATTACHMENT="$XEV_WEBHOOK_GET_ATTACHMENT"

  # Auto-discovery: if any required webhook URLs are still empty, try Make.com API
  if [[ -z "$XEV_CFG_WEBHOOK_SEARCH" || -z "$XEV_CFG_WEBHOOK_GET" || \
        -z "$XEV_CFG_WEBHOOK_NOTEBOOKS" || -z "$XEV_CFG_WEBHOOK_CREATE" || \
        -z "$XEV_CFG_WEBHOOK_UPDATE" || -z "$XEV_CFG_WEBHOOK_APPEND" ]]; then
    xev_discover_hooks || true
  fi

  # Check file permissions (warn if not 0600)
  if [[ -f "$config_file" ]]; then
    local perms
    perms=$(stat -f '%Lp' "$config_file" 2>/dev/null || stat -c '%a' "$config_file" 2>/dev/null)
    if [[ "$perms" != "600" ]]; then
      echo "Warning: config file permissions are ${perms}, should be 600" >&2
    fi
  fi
}

# Validate that all required config values are present
xev_validate_config() {
  local config_file="${1:-}"
  [[ -n "$config_file" ]] && xev_load_config "$config_file"

  local missing=""
  [[ -z "$XEV_CFG_WEBHOOK_SEARCH" ]] && missing="${missing} webhook_search"
  [[ -z "$XEV_CFG_WEBHOOK_GET" ]] && missing="${missing} webhook_get"
  [[ -z "$XEV_CFG_WEBHOOK_NOTEBOOKS" ]] && missing="${missing} webhook_notebooks"
  [[ -z "$XEV_CFG_WEBHOOK_CREATE" ]] && missing="${missing} webhook_create"
  [[ -z "$XEV_CFG_WEBHOOK_UPDATE" ]] && missing="${missing} webhook_update"
  [[ -z "$XEV_CFG_WEBHOOK_APPEND" ]] && missing="${missing} webhook_append"
  # webhook_get_attachment is optional — attachment download degrades gracefully
  # [[ -z "$XEV_CFG_WEBHOOK_GET_ATTACHMENT" ]] && missing="${missing} webhook_get_attachment"

  if [[ -n "$missing" ]]; then
    echo "Missing required config:${missing}" >&2
    return 1
  fi
  return 0
}

# Resolve the config file path
xev_config_path() {
  if [[ -n "${XEV_CONFIG_FILE:-}" ]]; then
    echo "$XEV_CONFIG_FILE"
  else
    echo "${HOME}/.config/xev-cli/config.toml"
  fi
}
