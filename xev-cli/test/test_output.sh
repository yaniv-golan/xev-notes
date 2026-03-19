#!/usr/bin/env bash
# test_output.sh — Test output formatting functions
set -uo pipefail

XEV_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${XEV_ROOT}/lib/output.sh"

ERRORS=0

# Test xev_json_ok
result=$(xev_json_ok '{"id":"abc"}')
expected='{"ok":true,"data":{"id":"abc"}}'
if [[ "$(echo "$result" | jq -c .)" == "$(echo "$expected" | jq -c .)" ]]; then
  echo "  OK: xev_json_ok"
else
  echo "  FAIL: xev_json_ok got: $result"
  ERRORS=$((ERRORS + 1))
fi

# Test xev_json_error
result=$(xev_json_error "NOT_FOUND" "Note does not exist")
if echo "$result" | jq -e '.ok == false and .error.code == "NOT_FOUND"' >/dev/null 2>&1; then
  echo "  OK: xev_json_error"
else
  echo "  FAIL: xev_json_error got: $result"
  ERRORS=$((ERRORS + 1))
fi

# Test xev_mask_url
result=$(xev_mask_url "https://hook.eu2.make.com/abcdefghijklmnopqrstuvwxyz1234567890")
if [[ "$result" == "https://hook.eu2.make.com/abcd...7890" ]]; then
  echo "  OK: xev_mask_url"
else
  echo "  FAIL: xev_mask_url got: $result"
  ERRORS=$((ERRORS + 1))
fi

# Test xev_mask_key
result=$(xev_mask_key "mysecretapikey12345")
if [[ "$result" == "****2345" ]]; then
  echo "  OK: xev_mask_key"
else
  echo "  FAIL: xev_mask_key got: $result"
  ERRORS=$((ERRORS + 1))
fi

exit $ERRORS
