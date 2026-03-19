#!/usr/bin/env bash
# run_tests.sh — Execute all test_*.sh files
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
ERRORS=""

for test_file in "${SCRIPT_DIR}"/test_*.sh; do
  test_name="$(basename "$test_file")"
  if bash "$test_file"; then
    PASS=$((PASS + 1))
    echo "PASS: ${test_name}"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}  FAIL: ${test_name}\n"
    echo "FAIL: ${test_name}"
  fi
done

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ $FAIL -gt 0 ]]; then
  echo -e "\nFailures:\n${ERRORS}"
  exit 1
fi
