#!/usr/bin/env bash
set -uo pipefail
XEV_CLI="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../xev-cli/bin" && pwd)/xev-cli"
input="$(cat)"
note_id="$(echo "$input" | jq -r '.note_id')"
format="$(echo "$input" | jq -r '.format // "markdown"')"
download="$(echo "$input" | jq -r '.download_attachments // false')"

args=("$note_id" --format "$format")
[[ "$download" == "true" ]] && args+=(--download-attachments)

"$XEV_CLI" get "${args[@]}" 2>/dev/null
