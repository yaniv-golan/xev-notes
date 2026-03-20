# shellcheck shell=bash
# commands.sh — Subcommand implementations

cmd_search() {
  local query=""
  local notebook=""
  local limit=20
  local output_mode="jsonl"

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --notebook) notebook="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      --output) output_mode="$2"; shift 2 ;;
      -*) xev_die_usage "Unknown flag: $1" ;;
      *)
        if [[ -z "$query" ]]; then
          query="$1"; shift
        else
          xev_die_usage "Unexpected argument: $1"
        fi
        ;;
    esac
  done

  [[ -z "$query" ]] && xev_die_usage "search requires a query argument"

  # Load config
  xev_load_config "$(xev_config_path)"
  if ! xev_validate_config; then
    xev_json_error "CONFIG_ERROR" "Invalid configuration. Run 'xev-cli config setup'."
    exit 2
  fi

  # Build search query with optional notebook prefix
  local full_query="$query"
  if [[ -n "$notebook" ]]; then
    full_query="notebook:\"${notebook}\" ${query}"
  fi

  # Build webhook payload
  local payload
  payload=$(jq -n --arg q "$full_query" --argjson l "$limit" \
    '{"query": $q, "limit": $l}')

  # Call webhook
  local response
  xev_webhook_call "$XEV_CFG_WEBHOOK_SEARCH" "$payload" "Searching Evernote..." || xev_die_from_response
  local response="$XEV_RESPONSE"

  # Normalize Make.com field names to spec contract
  local normalized
  normalized=$(echo "$response" | jq -c '[.[] | {
    id: (.["Note ID"] // .id),
    title: (.Title // .title),
    notebook: (.["Notebook name"] // .notebook),
    notebook_id: (.["Notebook ID"] // .notebook_id),
    updated: (.["Date updated"] // .updated),
    note_link: (.["Note link"] // .note_link)
  }]')

  # Format output
  case "$output_mode" in
    jsonl)
      echo "$normalized" | jq -c '.[]'
      ;;
    json)
      xev_json_ok "$normalized"
      ;;
    human)
      echo "$normalized" | jq -r '.[] | "\(.title)\t\(.notebook)\t\(.updated)"' | \
        column -t -s $'\t'
      ;;
  esac
}

cmd_get() {
  local note_id=""
  local format="markdown"
  local download_attachments=false
  local download_dir=""
  local output_mode="json"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --format) format="$2"; shift 2 ;;
      --download-attachments)
        download_attachments=true
        if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
          download_dir="$2"; shift 2
        else
          download_dir="."; shift
        fi
        ;;
      --output) output_mode="$2"; shift 2 ;;
      -*) xev_die_usage "Unknown flag: $1" ;;
      *)
        if [[ -z "$note_id" ]]; then
          note_id="$1"; shift
        else
          xev_die_usage "Unexpected argument: $1"
        fi
        ;;
    esac
  done

  [[ -z "$note_id" ]] && xev_die_usage "get requires a note ID"

  xev_load_config "$(xev_config_path)"
  if ! xev_validate_config; then
    xev_json_error "CONFIG_ERROR" "Invalid configuration. Run 'xev-cli config setup'."
    exit 2
  fi

  # Call webhook
  local payload
  payload=$(jq -n --arg id "$note_id" '{"note_id": $id}')
  local response
  xev_webhook_call "$XEV_CFG_WEBHOOK_GET" "$payload" "Fetching note..." || xev_die_from_response
  local response="$XEV_RESPONSE"

  # Extract content based on format
  local content
  case "$format" in
    enml)
      content=$(echo "$response" | jq -r '.["Content (ENML)"] // .htmlText // .content_enml // .content // ""')
      ;;
    text)
      content=$(echo "$response" | jq -r '.Content // .text // .content // ""')
      ;;
    markdown)
      local enml
      enml=$(echo "$response" | jq -r '.["Content (ENML)"] // .htmlText // .content_enml // ""')
      if [[ -n "$enml" ]]; then
        content=$(echo "$enml" | xev_enml_to_markdown)
      else
        content=$(echo "$response" | jq -r '.Content // .text // .content // ""')
      fi
      ;;
  esac

  # Build output JSON
  local note_title
  note_title=$(echo "$response" | jq -r '.Title // .title // "note"')
  local result
  result=$(echo "$response" | jq --arg content "$content" --arg fmt "$format" '{
    id: (.["Note ID"] // .note_id // .id),
    title: (.Title // .title),
    notebook: (.["Notebook name"] // .notebook_name // .notebookId // .notebook),
    updated: (.["Date updated"] // .dateUpdated // .date_updated // .updated),
    created: (.["Date created"] // .date_created // .created),
    content: $content,
    format: $fmt
  }')

  # Extract attachment metadata (always included in response, even without download)
  local attachments
  attachments=$(echo "$response" | jq -c '.attachments // []' 2>/dev/null || echo '[]')
  local att_count
  att_count=$(echo "$attachments" | jq 'length')

  # Add metadata-only attachments to result (no downloaded field)
  if [[ "$att_count" -gt 0 ]]; then
    local meta_atts
    meta_atts=$(echo "$attachments" | jq '[.[] | {name: (.name // "unnamed"), mime: (.mime // "application/octet-stream"), size: (.size // 0)}]')
    result=$(echo "$result" | jq --argjson atts "$meta_atts" '. + {attachments: $atts}')
  fi

  # Download attachments if requested
  if [[ "$download_attachments" == "true" && "$att_count" -gt 0 ]]; then
    # Sanitize title for directory name
    local safe_title
    # shellcheck disable=SC2001  # sed needed for negated character class
    safe_title=$(echo "$note_title" | sed 's/[^a-zA-Z0-9._-]/_/g')
    local target_dir="${download_dir}/${safe_title}"
    mkdir -p "$target_dir"

    local att_results="[]"
    local i=0
    while [[ $i -lt $att_count ]]; do
      local att_name att_hash att_mime att_size
      att_name=$(echo "$attachments" | jq -r ".[$i].name // \"attachment_$i\"")
      att_hash=$(echo "$attachments" | jq -r ".[$i].hash_hex // .[$i].hash // empty")
      att_mime=$(echo "$attachments" | jq -r ".[$i].mime // \"application/octet-stream\"")
      att_size=$(echo "$attachments" | jq -r ".[$i].size // 0")

      xev_progress "Downloading attachment $((i+1))/${att_count}: ${att_name}" $((i+1)) "$att_count"

      if [[ -n "$att_hash" ]]; then
        # Call xev-get-attachment webhook
        local att_payload
        att_payload=$(jq -n --arg id "$note_id" --arg hash "$att_hash" '{"note_id":$id,"resource_hash":$hash}')
        if xev_webhook_call "$XEV_CFG_WEBHOOK_GET_ATTACHMENT" "$att_payload" "Downloading ${att_name}..."; then
          local att_response="$XEV_RESPONSE"
          # Decode base64 and save (base64 -D on macOS, -d on Linux)
          local file_path="${target_dir}/${att_name}"
          local b64_flag="-d"
          [[ "$(uname)" == "Darwin" ]] && b64_flag="-D"
          if echo "$att_response" | jq -r '.data // .' | base64 "$b64_flag" > "$file_path" 2>/dev/null; then
            att_results=$(echo "$att_results" | jq --arg name "$att_name" --arg mime "$att_mime" --argjson size "$att_size" --arg path "$file_path" \
              '. + [{"name":$name,"mime":$mime,"size":$size,"downloaded":$path}]')
          else
            echo "Warning: Failed to decode attachment ${att_name}" >&2
          fi
        else
          echo "Warning: Failed to download attachment ${att_name}" >&2
        fi
      fi
      i=$((i+1))
    done
    xev_progress_done

    # Replace metadata-only attachments with download results (includes downloaded paths)
    result=$(echo "$result" | jq --argjson atts "$att_results" '. + {attachments: $atts}')
  fi

  case "$output_mode" in
    json) xev_json_ok "$result" ;;
    human)
      echo "$result" | jq -r '.title'
      echo "---"
      echo "$result" | jq -r '.content'
      if echo "$result" | jq -e '.attachments | length > 0' >/dev/null 2>&1; then
        echo ""
        echo "Attachments:"
        echo "$result" | jq -r '.attachments[] | if .downloaded then "  \(.name) → \(.downloaded)" else "  \(.name) (\(.mime), \(.size) bytes)" end'
      fi
      ;;
  esac
}
cmd_notebooks() {
  local output_mode="json"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output) output_mode="$2"; shift 2 ;;
      *) xev_die_usage "Unknown argument: $1" ;;
    esac
  done

  xev_load_config "$(xev_config_path)"
  if ! xev_validate_config; then
    xev_json_error "CONFIG_ERROR" "Invalid configuration. Run 'xev-cli config setup'."
    exit 2
  fi

  local response
  xev_webhook_call "$XEV_CFG_WEBHOOK_NOTEBOOKS" '{}' "Listing notebooks..." || xev_die_from_response
  local response="$XEV_RESPONSE"

  # Deduplicate notebook name/id pairs
  local notebooks
  notebooks=$(echo "$response" | jq '[.[] | {id: .["Notebook ID"], name: .["Notebook name"]}] | unique_by(.id)')

  case "$output_mode" in
    json) xev_json_ok "$notebooks" ;;
    jsonl) echo "$notebooks" | jq -c '.[]' ;;
    human) echo "$notebooks" | jq -r '.[] | "\(.name)\t\(.id)"' | column -t ;;
  esac
}

cmd_create() {
  local title="" notebook="" content="" content_file="" output_mode="json"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="$2"; shift 2 ;;
      --notebook) notebook="$2"; shift 2 ;;
      --content) content="$2"; shift 2 ;;
      --content-file) content_file="$2"; shift 2 ;;
      --output) output_mode="$2"; shift 2 ;;
      *) xev_die_usage "Unknown argument: $1" ;;
    esac
  done

  [[ -z "$title" ]] && xev_die_usage "create requires --title"
  [[ -z "$notebook" ]] && xev_die_usage "create requires --notebook"

  xev_load_config "$(xev_config_path)"
  if ! xev_validate_config; then
    xev_json_error "CONFIG_ERROR" "Invalid configuration. Run 'xev-cli config setup'."
    exit 2
  fi

  # Resolve notebook name to GUID
  xev_progress "Resolving notebook..."
  local nb_response
  xev_webhook_call "$XEV_CFG_WEBHOOK_NOTEBOOKS" '{}' "Looking up notebook..." || xev_die_from_response
  local nb_response="$XEV_RESPONSE"
  # Case-insensitive notebook name resolution (per spec)
  local notebook_id
  notebook_id=$(echo "$nb_response" | jq -r --arg name "$notebook" \
    '[.[] | select((.["Notebook name"] // .notebook_name // "") | ascii_downcase == ($name | ascii_downcase))] | .[0]["Notebook ID"] // .[0].notebook_id // empty')

  [[ -z "$notebook_id" ]] && xev_die "NOT_FOUND" "Notebook '${notebook}' not found"

  # Get content
  if [[ -n "$content_file" ]]; then
    content=$(cat "$content_file")
  fi

  # Convert content to ENML if provided
  local content_enml=""
  if [[ -n "$content" ]]; then
    content_enml=$(echo "$content" | xev_markdown_to_enml) || \
      xev_die "CONVERSION_ERROR" "Failed to convert content to ENML. Is pandoc installed?"
  fi

  # Call create webhook (escape_html: false tells Make.com to accept raw HTML/ENML)
  local payload
  payload=$(jq -n --arg title "$title" --arg nb "$notebook_id" --arg content "$content_enml" \
    '{"title": $title, "notebook_id": $nb, "content": $content, "escape_html": false}')

  local response
  xev_webhook_call "$XEV_CFG_WEBHOOK_CREATE" "$payload" "Creating note..." || xev_die_from_response
  local response="$XEV_RESPONSE"

  local result
  result=$(echo "$response" | jq '{id: (.["Note ID"] // .id), title: (.Title // .title)}')

  case "$output_mode" in
    json) xev_json_ok "$result" ;;
    human) echo "$result" | jq -r '"Created: \(.title) (ID: \(.id))"' ;;
  esac
}

cmd_update() {
  local note_id="" title="" content="" content_file="" append=false output_mode="json"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="$2"; shift 2 ;;
      --content) content="$2"; shift 2 ;;
      --content-file) content_file="$2"; shift 2 ;;
      --append) append=true; shift ;;
      --output) output_mode="$2"; shift 2 ;;
      -*) xev_die_usage "Unknown flag: $1" ;;
      *)
        if [[ -z "$note_id" ]]; then
          note_id="$1"; shift
        else
          xev_die_usage "Unexpected argument: $1"
        fi
        ;;
    esac
  done

  [[ -z "$note_id" ]] && xev_die_usage "update requires a note ID"

  xev_load_config "$(xev_config_path)"
  if ! xev_validate_config; then
    xev_json_error "CONFIG_ERROR" "Invalid configuration. Run 'xev-cli config setup'."
    exit 2
  fi

  if [[ -n "$content_file" ]]; then
    content=$(cat "$content_file")
  fi

  local content_enml=""
  if [[ -n "$content" ]]; then
    content_enml=$(echo "$content" | xev_markdown_to_enml) || \
      xev_die "CONVERSION_ERROR" "Failed to convert content to ENML."
  fi

  local response
  if [[ "$append" == "true" ]]; then
    # Use append webhook
    local payload
    payload=$(jq -n --arg id "$note_id" --arg content "$content_enml" \
      '{"note_id": $id, "content_enml": $content}')
    xev_webhook_call "$XEV_CFG_WEBHOOK_APPEND" "$payload" "Appending to note..." || xev_die_from_response
    local response="$XEV_RESPONSE"
  else
    # Use update webhook
    local payload
    payload=$(jq -n --arg id "$note_id" --arg title "$title" --arg content "$content_enml" \
      '{note_id: $id} + (if $title != "" then {title: $title} else {} end) + (if $content != "" then {content_enml: $content} else {} end)')
    xev_webhook_call "$XEV_CFG_WEBHOOK_UPDATE" "$payload" "Updating note..." || xev_die_from_response
    local response="$XEV_RESPONSE"
  fi

  local result
  result=$(echo "$response" | jq '{id: (.["Note ID"] // .id), title: (.Title // .title)}')

  case "$output_mode" in
    json) xev_json_ok "$result" ;;
    human) echo "$result" | jq -r '"Updated: \(.title) (ID: \(.id))"' ;;
  esac
}

cmd_config() {
  local subcmd="${1:-help}"
  shift || true

  case "$subcmd" in
    setup) cmd_config_setup "$@" ;;
    show) cmd_config_show "$@" ;;
    check) cmd_config_check "$@" ;;
    path) xev_config_path ;;
    *) echo "Usage: xev-cli config [setup|show|check|path]" >&2; exit 2 ;;
  esac
}

cmd_config_setup() {
  local profile="${XEV_PROFILE:-default}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile) profile="$2"; shift 2 ;;
      --auto) echo "Error: --auto is not yet implemented. Use manual setup." >&2; exit 2 ;;
      *) xev_die_usage "Unknown argument: $1" ;;
    esac
  done

  local config_file
  config_file="$(xev_config_path)"
  local config_dir
  config_dir="$(dirname "$config_file")"

  echo "xev-cli config setup (profile: ${profile})"
  echo ""

  # Check if profile already exists — confirm overwrite
  if [[ -f "$config_file" ]]; then
    local section_check
    if [[ "$profile" == "default" ]]; then
      section_check="[default]"
    else
      section_check="[profiles.${profile}]"
    fi
    if grep -qF "$section_check" "$config_file" 2>/dev/null; then
      local confirm
      read -rp "Profile '${profile}' already exists. Overwrite? [y/N]: " confirm
      if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Aborted." >&2
        exit 0
      fi
    fi
  fi

  local zone
  read -rp "Make.com zone [eu2.make.com]: " zone
  zone="${zone:-eu2.make.com}"

  local api_key
  read -rsp "Webhook API key (optional, press Enter to skip): " api_key
  echo ""

  local url_search url_get url_notebooks url_create url_update url_append url_get_attachment
  read -rsp "Webhook URL for search: " url_search; echo ""
  read -rsp "Webhook URL for get: " url_get; echo ""
  read -rsp "Webhook URL for notebooks: " url_notebooks; echo ""
  read -rsp "Webhook URL for create: " url_create; echo ""
  read -rsp "Webhook URL for update: " url_update; echo ""
  read -rsp "Webhook URL for append: " url_append; echo ""
  read -rsp "Webhook URL for get_attachment: " url_get_attachment; echo ""

  mkdir -p "$config_dir"

  local section
  if [[ "$profile" == "default" ]]; then
    section="[default]"
  else
    section="[profiles.${profile}]"
  fi

  local new_section
  new_section="${section}"
  new_section+=$'\n'"make_zone = \"${zone}\""
  [[ -n "$api_key" ]] && new_section+=$'\n'"webhook_api_key = \"${api_key}\""
  new_section+=$'\n'"webhook_search = \"${url_search}\""
  new_section+=$'\n'"webhook_get = \"${url_get}\""
  new_section+=$'\n'"webhook_notebooks = \"${url_notebooks}\""
  new_section+=$'\n'"webhook_create = \"${url_create}\""
  new_section+=$'\n'"webhook_update = \"${url_update}\""
  new_section+=$'\n'"webhook_append = \"${url_append}\""
  new_section+=$'\n'"webhook_get_attachment = \"${url_get_attachment}\""

  if [[ -f "$config_file" ]]; then
    local existing
    existing=$(perl -0pe "s/\Q${section}\E\n(?:(?!\[)[^\n]*\n)*//g" "$config_file")
    printf '%s\n\n%s\n' "$existing" "$new_section" > "$config_file"
  else
    echo "$new_section" > "$config_file"
  fi

  chmod 600 "$config_file"
  echo ""
  echo "Config written to ${config_file}"

  # Optional: ping webhooks to verify URLs are reachable
  local do_ping
  read -rp "Test webhook URLs with a ping? [y/N]: " do_ping
  if [[ "$do_ping" == "y" || "$do_ping" == "Y" ]]; then
    XEV_PROFILE="$profile"
    xev_load_config "$config_file"
    cmd_config_check --ping
  fi
}

cmd_config_show() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile) XEV_PROFILE="$2"; shift 2 ;;
      *) xev_die_usage "Unknown argument: $1" ;;
    esac
  done
  local config_file
  config_file="$(xev_config_path)"
  xev_load_config "$config_file"

  echo "Profile: ${XEV_PROFILE}"
  echo "Make Zone: ${XEV_CFG_MAKE_ZONE}"
  echo "API Key:   $(xev_mask_key "${XEV_CFG_WEBHOOK_API_KEY:-}")"
  echo "Webhooks:"
  echo "  search:         $(xev_mask_url "${XEV_CFG_WEBHOOK_SEARCH}")"
  echo "  get:            $(xev_mask_url "${XEV_CFG_WEBHOOK_GET}")"
  echo "  notebooks:      $(xev_mask_url "${XEV_CFG_WEBHOOK_NOTEBOOKS}")"
  echo "  create:         $(xev_mask_url "${XEV_CFG_WEBHOOK_CREATE}")"
  echo "  update:         $(xev_mask_url "${XEV_CFG_WEBHOOK_UPDATE}")"
  echo "  append:         $(xev_mask_url "${XEV_CFG_WEBHOOK_APPEND}")"
  echo "  get-attachment: $(xev_mask_url "${XEV_CFG_WEBHOOK_GET_ATTACHMENT}")"
}

cmd_config_check() {
  local ping=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ping) ping=true; shift ;;
      --profile) XEV_PROFILE="$2"; shift 2 ;;
      *) xev_die_usage "Unknown argument: $1" ;;
    esac
  done

  local config_file
  config_file="$(xev_config_path)"

  if [[ ! -f "$config_file" ]]; then
    echo "FAIL: Config file not found at ${config_file}"
    echo "Run: xev-cli config setup"
    exit 1
  fi
  echo "OK: Config file exists"

  local perms
  perms=$(stat -f '%Lp' "$config_file" 2>/dev/null || stat -c '%a' "$config_file" 2>/dev/null)
  if [[ "$perms" == "600" ]]; then
    echo "OK: Permissions are 600"
  else
    echo "WARN: Permissions are ${perms} (should be 600)"
  fi

  xev_load_config "$config_file"
  if xev_validate_config; then
    echo "OK: All webhook URLs configured"
  else
    echo "FAIL: Missing webhook URLs"
    exit 1
  fi

  if [[ "$ping" == "true" ]]; then
    echo "Pinging webhooks..."
    local webhooks=("search:$XEV_CFG_WEBHOOK_SEARCH" "get:$XEV_CFG_WEBHOOK_GET" "notebooks:$XEV_CFG_WEBHOOK_NOTEBOOKS" "create:$XEV_CFG_WEBHOOK_CREATE" "update:$XEV_CFG_WEBHOOK_UPDATE" "append:$XEV_CFG_WEBHOOK_APPEND" "get-attachment:$XEV_CFG_WEBHOOK_GET_ATTACHMENT")
    for entry in "${webhooks[@]}"; do
      local name="${entry%%:*}"
      local url="${entry#*:}"
      local curl_args=(-s -o /dev/null --max-time 10 -w '%{http_code}' -d '{}' -H "Content-Type: application/json")
      [[ -n "${XEV_CFG_WEBHOOK_API_KEY:-}" ]] && curl_args+=(-H "x-make-apikey: ${XEV_CFG_WEBHOOK_API_KEY}")
      local result
      result=$(curl "${curl_args[@]}" "$url" 2>/dev/null)
      if [[ "$result" == "200" ]]; then
        echo "  OK: ${name}"
      else
        echo "  FAIL: ${name} (HTTP ${result})"
      fi
    done
  fi

  echo ""
  echo "Config is valid."
}
