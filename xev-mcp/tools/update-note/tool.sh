#!/usr/bin/env bash
set -uo pipefail
input="$(cat)"
note_id="$(echo "$input" | jq -r '.note_id')"
title="$(echo "$input" | jq -r '.title // empty')"
content="$(echo "$input" | jq -r '.content // empty')"
append="$(echo "$input" | jq -r '.append // false')"

args=("$note_id")
[[ -n "$title" ]] && args+=(--title "$title")
[[ -n "$content" ]] && args+=(--content "$content")
[[ "$append" == "true" ]] && args+=(--append)

xev-cli update "${args[@]}" 2>/dev/null
