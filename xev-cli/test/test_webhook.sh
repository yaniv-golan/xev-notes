#!/usr/bin/env bash
# test_webhook.sh — Webhook caller tests
set -uo pipefail

XEV_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${XEV_ROOT}/lib/output.sh"
source "${XEV_ROOT}/lib/progress.sh"
source "${XEV_ROOT}/lib/webhook.sh"

XEV_PROGRESS="never"
XEV_TRACE=false
ERRORS=0

# Test: xev_die_from_response outputs error JSON
XEV_RESPONSE='{"ok":false,"error":{"code":"TIMEOUT","message":"test"}}'
result=$(xev_die_from_response 2>/dev/null) || true
if echo "$result" | jq -e '.error.code == "TIMEOUT"' >/dev/null 2>&1; then
  echo "  OK: xev_die_from_response outputs error JSON"
else
  echo "  FAIL: xev_die_from_response got: $result"
  ERRORS=$((ERRORS + 1))
fi

# Test: xev_json_error produces correct structure
result=$(xev_json_error "AUTH_FAILED" "Bad key")
if echo "$result" | jq -e '.ok == false and .error.code == "AUTH_FAILED"' >/dev/null 2>&1; then
  echo "  OK: xev_json_error structure"
else
  echo "  FAIL: xev_json_error got: $result"
  ERRORS=$((ERRORS + 1))
fi

exit $ERRORS
