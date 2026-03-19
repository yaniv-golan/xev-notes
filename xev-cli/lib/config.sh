# shellcheck shell=bash
# config.sh — TOML config loading, resolution chain, profile support

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

  # Parse TOML file if it exists
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
  if [[ "${XEV_DOTENV:-false}" == "true" ]] && [[ -f .env ]]; then
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
      [[ "$key" =~ ^[[:space:]]*# ]] && continue  # Skip comments
      [[ -z "$key" ]] && continue
      key=$(echo "$key" | xargs)  # Trim whitespace
      value=$(echo "$value" | sed 's/^"//;s/"$//')  # Strip quotes
      [[ -z "${!key:-}" ]] && export "$key=$value"  # Only set if not already set
    done < .env
  fi

  # Environment variable overrides (highest priority after CLI flags)
  # shellcheck disable=SC2034  # XEV_CFG_* vars are used by commands.sh
  [[ -n "${XEV_MAKE_ZONE:-}" ]] && XEV_CFG_MAKE_ZONE="$XEV_MAKE_ZONE"
  # shellcheck disable=SC2034
  [[ -n "${XEV_WEBHOOK_API_KEY:-}" ]] && XEV_CFG_WEBHOOK_API_KEY="$XEV_WEBHOOK_API_KEY"
  [[ -n "${XEV_WEBHOOK_SEARCH:-}" ]] && XEV_CFG_WEBHOOK_SEARCH="$XEV_WEBHOOK_SEARCH"
  [[ -n "${XEV_WEBHOOK_GET:-}" ]] && XEV_CFG_WEBHOOK_GET="$XEV_WEBHOOK_GET"
  [[ -n "${XEV_WEBHOOK_NOTEBOOKS:-}" ]] && XEV_CFG_WEBHOOK_NOTEBOOKS="$XEV_WEBHOOK_NOTEBOOKS"
  [[ -n "${XEV_WEBHOOK_CREATE:-}" ]] && XEV_CFG_WEBHOOK_CREATE="$XEV_WEBHOOK_CREATE"
  [[ -n "${XEV_WEBHOOK_UPDATE:-}" ]] && XEV_CFG_WEBHOOK_UPDATE="$XEV_WEBHOOK_UPDATE"
  [[ -n "${XEV_WEBHOOK_APPEND:-}" ]] && XEV_CFG_WEBHOOK_APPEND="$XEV_WEBHOOK_APPEND"
  [[ -n "${XEV_WEBHOOK_GET_ATTACHMENT:-}" ]] && XEV_CFG_WEBHOOK_GET_ATTACHMENT="$XEV_WEBHOOK_GET_ATTACHMENT"

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
  [[ -z "$XEV_CFG_WEBHOOK_GET_ATTACHMENT" ]] && missing="${missing} webhook_get_attachment"

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
