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
    notebook: (.["Notebook name"] // .notebookName // .notebook),
    notebook_id: (.["Notebook ID"] // .notebookId // .notebook_id),
    updated: (.["Date updated"] // .dateUpdated // .updated),
    note_link: (.["Note link"] // .noteLink // .note_link)
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
  notebooks=$(echo "$response" | jq '[.[] | {id: (.["Notebook ID"] // .notebookId), name: (.["Notebook name"] // .notebookName)}] | unique_by(.id)')

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

  # Resolve notebook name to GUID (with session cache)
  local nb_response
  local nb_cache="/tmp/xev-notebooks-cache-${UID:-0}.json"
  if [[ -f "$nb_cache" ]] && [[ $(( $(date +%s) - $(stat -f %m "$nb_cache" 2>/dev/null || stat -c %Y "$nb_cache" 2>/dev/null || echo 0) )) -lt 300 ]]; then
    nb_response=$(cat "$nb_cache")
  else
    xev_progress "Resolving notebook..."
    xev_webhook_call "$XEV_CFG_WEBHOOK_NOTEBOOKS" '{}' "Looking up notebook..." || xev_die_from_response
    nb_response="$XEV_RESPONSE"
    echo "$nb_response" > "$nb_cache"
  fi
  local notebook_id
  notebook_id=$(echo "$nb_response" | jq -r --arg name "$notebook" \
    '[.[] | select((.["Notebook name"] // .notebookName // .notebook_name // "") | ascii_downcase == ($name | ascii_downcase))] | .[0]["Notebook ID"] // .[0].notebookId // .[0].notebook_id // empty')

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
    # Use append webhook — send HTML fragment only, not full ENML envelope
    # The append module adds content inside the existing note's <en-note> element
    local append_html
    append_html=$(echo "$content" | pandoc -f markdown -t html 2>/dev/null | sed -E 's/ class="[^"]*"//g; s/ id="[^"]*"//g')
    local payload
    payload=$(jq -n --arg id "$note_id" --arg content "$append_html" \
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
    *) echo "Usage: xev-cli config [setup|setup --auto|show|check|path]" >&2; exit 2 ;;
  esac
}

cmd_config_setup() {
  local profile="${XEV_PROFILE:-default}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile) profile="$2"; shift 2 ;;
      --auto) cmd_config_setup_auto "$@"; return ;;
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

cmd_config_setup_auto() {
  local profile="${XEV_PROFILE:-default}"
  local zone=""
  local api_token=""
  local team_id=""

  # Parse remaining args after --auto was consumed
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile) profile="$2"; shift 2 ;;
      --zone) zone="$2"; shift 2 ;;
      --team-id) team_id="$2"; shift 2 ;;
      *) xev_die_usage "Unknown argument: $1" ;;
    esac
  done

  echo "xev-cli automatic setup"
  echo ""

  # Prompt for Make.com credentials
  if [[ -z "$zone" ]]; then
    read -rp "Make.com zone [eu2.make.com]: " zone
    zone="${zone:-eu2.make.com}"
  fi

  read -rsp "Make.com API token (from https://${zone}/user/api): " api_token
  echo ""
  [[ -z "$api_token" ]] && { echo "Error: API token is required" >&2; exit 2; }

  if [[ -z "$team_id" ]]; then
    read -rp "Make.com team ID (from your Make.com URL): " team_id
    [[ -z "$team_id" ]] && { echo "Error: Team ID is required" >&2; exit 2; }
  fi

  # Verify API token
  echo "Verifying API access..."
  local me_response
  me_response=$(curl -s -H "Authorization: Token ${api_token}" "https://${zone}/api/v2/users/me")
  if ! echo "$me_response" | jq -e '.authUser.name' >/dev/null 2>&1; then
    echo "Error: API token verification failed. Check your token and zone." >&2
    echo "Response: $(echo "$me_response" | head -c 200)" >&2
    exit 2
  fi
  local user_name
  user_name=$(echo "$me_response" | jq -r '.authUser.name')
  echo "  Authenticated as: ${user_name}"

  # Find blueprint files
  local bp_dir=""
  for dir in "${XEV_ROOT}/make/blueprints" "$(dirname "${BASH_SOURCE[0]}")/../../make/blueprints"; do
    if [[ -d "$dir" ]]; then
      bp_dir="$(cd "$dir" && pwd)"
      break
    fi
  done
  if [[ -z "$bp_dir" ]]; then
    echo "Error: Blueprint directory not found. Expected make/blueprints/ in the repo." >&2
    exit 2
  fi
  echo "  Blueprints: ${bp_dir}"

  # Create scenarios
  echo ""
  echo "Creating scenarios..."
  local scenarios="xev-search xev-get xev-notebooks xev-create xev-update xev-append"
  local urls=""
  local failed=0

  for name in $scenarios; do
    local bp_file="${bp_dir}/${name}.json"
    if [[ ! -f "$bp_file" ]]; then
      echo "  SKIP: ${name} (blueprint not found)"
      failed=$((failed + 1))
      continue
    fi

    # Create webhook hook
    local hook_resp
    hook_resp=$(curl -s -X POST -H "Authorization: Token ${api_token}" -H "Content-Type: application/json" \
      "https://${zone}/api/v2/hooks" \
      -d "{\"name\":\"${name}\",\"teamId\":${team_id},\"typeName\":\"gateway-webhook\",\"headers\":\"[]\",\"method\":\"POST\",\"stringify\":false}")
    local hook_id
    hook_id=$(echo "$hook_resp" | jq '.hook.id // empty')
    local hook_url
    hook_url=$(echo "$hook_resp" | jq -r '.hook.url // empty')

    if [[ -z "$hook_id" ]]; then
      echo "  FAIL: ${name} — hook creation failed: $(echo "$hook_resp" | jq -r '.detail // .message // "unknown error"')"
      failed=$((failed + 1))
      continue
    fi

    # Inject hook ID into blueprint
    local bp_with_hook
    bp_with_hook=$(jq --argjson hid "$hook_id" \
      '.flow[0].parameters.hook = $hid | .flow[0].metadata.restore.parameters.hook.label = .name' \
      "$bp_file")

    # Create scenario with "immediately" scheduling
    local bp_str
    bp_str=$(echo "$bp_with_hook" | jq -c '.' | jq -Rs '.')
    local create_payload
    create_payload=$(jq -n --argjson bp "$bp_str" --arg n "$name" --argjson tid "$team_id" \
      '{teamId: $tid, blueprint: $bp, scheduling: "{\"type\":\"immediately\"}", name: $n}')

    local sc_resp
    sc_resp=$(curl -s -X POST -H "Authorization: Token ${api_token}" -H "Content-Type: application/json" \
      "https://${zone}/api/v2/scenarios?confirmed=true" -d "$create_payload")
    local sc_id
    sc_id=$(echo "$sc_resp" | jq '.scenario.id // empty')

    if [[ -z "$sc_id" ]]; then
      echo "  FAIL: ${name} — scenario creation failed: $(echo "$sc_resp" | jq -r '.detail // .message // "unknown error"')"
      failed=$((failed + 1))
      continue
    fi

    echo "  OK: ${name} (scenario ${sc_id}, webhook ${hook_url})"

    # Collect URLs for config
    local key
    key=$(echo "$name" | sed 's/xev-//' | tr '-' '_')
    urls="${urls}${key}=${hook_url}\n"

    # Try to activate (may fail due to org restrictions)
    local start_resp
    start_resp=$(curl -s -X POST -H "Authorization: Token ${api_token}" \
      "https://${zone}/api/v2/scenarios/${sc_id}/start" 2>/dev/null)
    if echo "$start_resp" | jq -e '.scenario' >/dev/null 2>&1; then
      echo "       Activated"
    fi
  done

  if [[ $failed -gt 0 ]]; then
    echo ""
    echo "Warning: ${failed} scenario(s) failed to create."
  fi

  # Extract URLs and write config
  local url_search url_get url_notebooks url_create url_update url_append
  url_search=$(echo -e "$urls" | grep '^search=' | cut -d= -f2)
  url_get=$(echo -e "$urls" | grep '^get=' | cut -d= -f2)
  url_notebooks=$(echo -e "$urls" | grep '^notebooks=' | cut -d= -f2)
  url_create=$(echo -e "$urls" | grep '^create=' | cut -d= -f2)
  url_update=$(echo -e "$urls" | grep '^update=' | cut -d= -f2)
  url_append=$(echo -e "$urls" | grep '^append=' | cut -d= -f2)

  # Write config
  local config_file
  config_file="$(xev_config_path)"
  local config_dir
  config_dir="$(dirname "$config_file")"
  mkdir -p "$config_dir"

  local section
  if [[ "$profile" == "default" ]]; then
    section="[default]"
  else
    section="[profiles.${profile}]"
  fi

  cat > "$config_file" <<TOML
${section}
make_zone = "${zone}"
webhook_api_key = ""
webhook_search = "${url_search}"
webhook_get = "${url_get}"
webhook_notebooks = "${url_notebooks}"
webhook_create = "${url_create}"
webhook_update = "${url_update}"
webhook_append = "${url_append}"
webhook_get_attachment = ""
TOML

  chmod 600 "$config_file"
  echo ""
  echo "Config written to ${config_file}"

  # Print remaining manual steps
  echo ""
  echo "========================================="
  echo "REMAINING MANUAL STEPS (in Make.com UI):"
  echo "========================================="
  echo ""
  echo "1. Open each xev-* scenario in Make.com"
  echo "2. Click the Evernote module (green circle)"
  echo "3. Select your Evernote connection from the dropdown"
  echo "4. Save the scenario"
  echo "5. Activate the scenario (toggle ON at top right)"
  echo ""
  echo "Then verify:"
  echo "  xev-cli config check"
  echo "  xev-cli search \"test\" --limit 3 --output human"
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
