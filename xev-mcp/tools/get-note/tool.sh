#!/usr/bin/env bash
set -uo pipefail
input="$(cat)"
note_id="$(echo "$input" | jq -r '.note_id')"
format="$(echo "$input" | jq -r '.format // "markdown"')"

xev-cli get "$note_id" --format "$format" 2>/dev/null
