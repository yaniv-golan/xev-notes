#!/usr/bin/env bash
# test_convert.sh — ENML conversion pipeline tests
set -uo pipefail

XEV_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="${XEV_ROOT}/test/fixtures"
source "${XEV_ROOT}/lib/convert.sh"

ERRORS=0

# Test: ENML to markdown
result=$(cat "${FIXTURES}/sample_note.enml" | xev_enml_to_markdown)
if [[ -n "$result" ]] && [[ $(echo "$result" | wc -l) -gt 5 ]]; then
  echo "  OK: enml_to_markdown produces output"
else
  echo "  FAIL: enml_to_markdown returned empty or too short"
  ERRORS=$((ERRORS + 1))
fi

# Test: en-todo conversion
enml='<en-note><p><en-todo checked="true"/>Done item</p><p><en-todo checked="false"/>Not done</p></en-note>'
result=$(echo "$enml" | xev_enml_to_markdown)
if [[ "$result" == *"[x]"* ]] && [[ "$result" == *"[ ]"* ]]; then
  echo "  OK: en-todo checkbox conversion"
else
  echo "  FAIL: en-todo not converted"
  echo "  DEBUG result hex: $(echo -n "$result" | xxd | head -3)"
  echo "  DEBUG pandoc version: $(pandoc --version | head -1)"
  echo "  DEBUG pre-pandoc: $(echo "$enml" | sed 's/<en-note>//g; s/<\/en-note>//g' | sed -E 's/<en-todo checked="true"\/>/XEVCHK1 /g' | sed -E 's/<en-todo checked="false"\/>/XEVCHK0 /g')"
  echo "  DEBUG post-pandoc: $(echo "$enml" | sed 's/<en-note>//g; s/<\/en-note>//g' | sed -E 's/<en-todo checked="true"\/>/XEVCHK1 /g' | sed -E 's/<en-todo checked="false"\/>/XEVCHK0 /g' | pandoc -f html -t gfm 2>/dev/null | head -3)"
  ERRORS=$((ERRORS + 1))
fi

# Test: markdown to ENML
result=$(echo "# Hello World" | xev_markdown_to_enml)
if [[ "$result" == *"en-note"* ]] && [[ "$result" == *"Hello World"* ]]; then
  echo "  OK: markdown_to_enml wraps in en-note"
else
  echo "  FAIL: markdown_to_enml: $result"
  ERRORS=$((ERRORS + 1))
fi

# Test: pandoc availability check
if xev_check_pandoc; then
  echo "  OK: pandoc available"
else
  echo "  WARN: pandoc not available, markdown conversion will degrade to text"
fi

exit $ERRORS
