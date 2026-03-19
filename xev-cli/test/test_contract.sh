#!/usr/bin/env bash
# test_contract.sh — Contract tests against real Make.com response fixtures
set -uo pipefail

XEV_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="${XEV_ROOT}/test/fixtures"
source "${XEV_ROOT}/lib/output.sh"

ERRORS=0

# Test: search normalization against real Make.com response fixture
fixture=$(cat "${FIXTURES}/makecom_search_response.json")
normalized=$(echo "$fixture" | jq -c '[.[] | {
  id: (.["Note ID"] // .id),
  title: (.Title // .title),
  notebook: (.["Notebook name"] // .notebook),
  notebook_id: (.["Notebook ID"] // .notebook_id),
  updated: (.["Date updated"] // .updated),
  note_link: (.["Note link"] // .note_link)
}]')

# Verify first result has correct normalized field names
first=$(echo "$normalized" | jq '.[0]')
if echo "$first" | jq -e '.id and .title and .notebook and .notebook_id and .updated and .note_link' >/dev/null 2>&1; then
  echo "  OK: search normalization produces all required fields"
else
  echo "  FAIL: search normalization missing fields: $first"
  ERRORS=$((ERRORS + 1))
fi

# Verify values are correct
if echo "$first" | jq -e '.id == "e72652cc-1dd3-4ec0-b7ed-5a8e49e322c9" and .title == "Barry Katz" and .notebook == "Private"' >/dev/null 2>&1; then
  echo "  OK: search normalization values correct"
else
  echo "  FAIL: search normalization values wrong: $first"
  ERRORS=$((ERRORS + 1))
fi

exit $ERRORS
