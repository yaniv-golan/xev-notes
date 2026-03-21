#!/usr/bin/env bash
set -uo pipefail
input="$(cat)"
note_id="$(echo "$input" | jq -r '.note_id')"
format="$(echo "$input" | jq -r '.format // "markdown"')"
download="$(echo "$input" | jq -r '.download_attachments // false')"

args=("$note_id" --format "$format")
[[ "$download" == "true" ]] && args+=(--download-attachments)

xev-cli get "${args[@]}" 2>/dev/null
