#!/usr/bin/env bash
# test_scaffold.sh — Verify xev-cli entry point works
set -uo pipefail

XEV="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/xev-cli"
ERRORS=0

# Test --version
output=$("$XEV" --version 2>&1)
if [[ "$output" == *"0.1.0"* ]]; then
  echo "  OK: --version"
else
  echo "  FAIL: --version returned: $output"
  ERRORS=$((ERRORS + 1))
fi

# Test --help
output=$("$XEV" --help 2>&1)
if [[ "$output" == *"search"* ]] && [[ "$output" == *"config"* ]]; then
  echo "  OK: --help"
else
  echo "  FAIL: --help missing commands"
  ERRORS=$((ERRORS + 1))
fi

# Test unknown command
"$XEV" nosuchcommand >/dev/null 2>&1
if [[ $? -eq 2 ]]; then
  echo "  OK: unknown command exits 2"
else
  echo "  FAIL: unknown command should exit 2"
  ERRORS=$((ERRORS + 1))
fi

exit $ERRORS
