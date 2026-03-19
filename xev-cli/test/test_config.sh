#!/usr/bin/env bash
# test_config.sh — Config loading and resolution chain tests
set -uo pipefail

XEV_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="${XEV_ROOT}/test/fixtures"
source "${XEV_ROOT}/lib/output.sh"
source "${XEV_ROOT}/lib/config.sh"

ERRORS=0

# Test: load valid config
XEV_PROFILE="default"
xev_load_config "${FIXTURES}/config_valid.toml"
if [[ "${XEV_CFG_WEBHOOK_SEARCH}" == "https://hook.eu2.make.com/search_test" ]]; then
  echo "  OK: load valid config - search URL"
else
  echo "  FAIL: search URL got: ${XEV_CFG_WEBHOOK_SEARCH:-empty}"
  ERRORS=$((ERRORS + 1))
fi

if [[ "${XEV_CFG_WEBHOOK_API_KEY}" == "testkey123" ]]; then
  echo "  OK: load valid config - API key"
else
  echo "  FAIL: API key got: ${XEV_CFG_WEBHOOK_API_KEY:-empty}"
  ERRORS=$((ERRORS + 1))
fi

# Test: env var override
XEV_WEBHOOK_SEARCH="https://override.example.com/search"
xev_load_config "${FIXTURES}/config_valid.toml"
if [[ "${XEV_CFG_WEBHOOK_SEARCH}" == "https://override.example.com/search" ]]; then
  echo "  OK: env var override"
else
  echo "  FAIL: env override got: ${XEV_CFG_WEBHOOK_SEARCH}"
  ERRORS=$((ERRORS + 1))
fi
unset XEV_WEBHOOK_SEARCH

# Test: missing required field returns error
XEV_PROFILE="default"
result=$(xev_validate_config "${FIXTURES}/config_missing.toml" 2>&1) || true
if [[ "$result" == *"webhook_get"* ]]; then
  echo "  OK: detects missing webhook_get"
else
  echo "  FAIL: should detect missing webhook_get"
  ERRORS=$((ERRORS + 1))
fi

exit $ERRORS
