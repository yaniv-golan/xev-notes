# shellcheck shell=bash
# webhook.sh — curl wrapper for Make.com webhooks

# Call a Make.com webhook with JSON payload
# Sets global XEV_RESPONSE with the response body (avoids subshell exit problem)
# Returns: 0 on success, 1 on error. On error, XEV_RESPONSE contains the error JSON.
# Callers MUST check return code: xev_webhook_call ... || xev_die_from_response
xev_webhook_call() {
  local url="$1"
  local payload="${2:-{}}"
  local progress_msg="${3:-Calling webhook...}"

  xev_progress "$progress_msg"

  local curl_args=(-s --max-time 200 -w '\n%{http_code}' -H "Content-Type: application/json")

  if [[ -n "${XEV_CFG_WEBHOOK_API_KEY:-}" ]]; then
    curl_args+=(-H "x-make-apikey: ${XEV_CFG_WEBHOOK_API_KEY}")
  fi

  if [[ "${XEV_TRACE:-false}" == "true" ]]; then
    echo "[TRACE] POST $(xev_mask_url "$url")" >&2
    echo "[TRACE] Body: $(echo "$payload" | head -c 200)" >&2
  fi

  local raw_response
  raw_response=$(curl "${curl_args[@]}" -d "$payload" "$url" 2>/dev/null)

  # Last line is HTTP status code (from -w '\n%{http_code}')
  XEV_LAST_HTTP_CODE=$(echo "$raw_response" | tail -1)
  local body
  body=$(echo "$raw_response" | sed '$d')

  xev_progress_done

  # Classify response by HTTP status code AND body
  case "$XEV_LAST_HTTP_CODE" in
    200)
      if [[ "$body" == "Accepted" ]]; then
        XEV_RESPONSE=$(xev_json_error "TIMEOUT" "Make.com scenario timed out (180s). Retry the command.")
        return 1
      fi
      if ! echo "$body" | jq . >/dev/null 2>&1; then
        XEV_RESPONSE=$(xev_json_error "MAKE_ERROR" "Invalid JSON response: $(echo "$body" | head -c 100)")
        return 1
      fi
      XEV_RESPONSE="$body"
      return 0
      ;;
    401|403)
      XEV_RESPONSE=$(xev_json_error "AUTH_FAILED" "Webhook returned HTTP ${XEV_LAST_HTTP_CODE}. Check webhook URL and API key.")
      return 1
      ;;
    429)
      XEV_RESPONSE=$(xev_json_error "RATE_LIMITED" "Too many requests (HTTP 429). Back off and retry.")
      return 1
      ;;
    000)
      XEV_RESPONSE=$(xev_json_error "MAKE_ERROR" "Connection failed. Check network and webhook URL.")
      return 1
      ;;
    *)
      XEV_RESPONSE=$(xev_json_error "MAKE_ERROR" "Webhook returned HTTP ${XEV_LAST_HTTP_CODE}: $(echo "$body" | head -c 100)")
      return 1
      ;;
  esac
}

# Helper: die using the error already in XEV_RESPONSE
xev_die_from_response() {
  echo "$XEV_RESPONSE"
  exit 1
}
